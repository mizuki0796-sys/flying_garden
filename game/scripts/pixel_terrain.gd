extends RefCounted

# Source PNGs are read-only. Render their original artwork directly; only shared
# border strips are occluded when cells connect. Never mirror/resample the art.
const SOURCE_ROOT := "res://assets/pixel_v2/terrain/"
const FOOTPRINTS := {
	"grass": Rect2(286, 186, 806, 645),
	"farm": Rect2(242, 174, 894, 635),
	"sand": Rect2(214, 117, 956, 714),
	"rock": Rect2(357, 125, 800, 640),
	"lava": Rect2(235, 140, 931, 744),
	"gold": Rect2(355, 129, 806, 645),
}
const ART_BOTTOM := {"grass": 1028.0, "farm": 1004.0, "sand": 1052.0, "rock": 963.0, "lava": 1050.0, "gold": 964.0}
const TREE_REGION := Rect2i(366, 13, 806, 742)
const TREE_HEIGHT := 110.0
static var sources: Dictionary = {}


static func terrain_kind(kind: String) -> String:
	return "grass" if kind == "tree" else kind


static func load_sources() -> Dictionary:
	if sources.is_empty():
		for kind in FOOTPRINTS:
			sources[kind] = load(SOURCE_ROOT + kind + "_tile_concept_v1.png")
	return sources


static func draw_original(canvas: Node2D, rect: Rect2, kind: String, exposed: Dictionary) -> void:
	kind = terrain_kind(kind)
	var source: Texture2D = load_sources()[kind]
	var footprint: Rect2 = FOOTPRINTS[kind]
	# One uniform scale: stones, furrows, and pixel clusters retain their shape.
	var scale_value := minf(rect.size.x / footprint.size.x, rect.size.y / footprint.size.y)
	var origin := rect.get_center() - footprint.get_center() * scale_value
	var visual_top := origin.y + footprint.position.y * scale_value
	var visual_bottom := origin.y + footprint.end.y * scale_value
	var clip := Rect2(rect.position, rect.size)
	if exposed.left:
		clip.position.x -= 3.0 * rect.size.x / 80.0
		clip.size.x += 3.0 * rect.size.x / 80.0
	if exposed.right:
		clip.size.x += 4.5 * rect.size.x / 80.0
	clip.position.y = visual_top - (3.0 * rect.size.x / 80.0 if exposed.up else 0.0)
	clip.size.y = (origin.y + float(ART_BOTTOM[kind]) * scale_value if exposed.down else visual_bottom) - clip.position.y
	var region := Rect2((clip.position - origin) / scale_value, clip.size / scale_value)
	canvas.draw_texture_rect_region(source, clip, region)


static func ground_kind(kind: String) -> String:
	# The approved farmland has a grass verge. Keep it between planting beds.
	return "grass" if kind in ["grass", "tree", "farm"] else kind


static func draw_cliff_join(canvas: Node2D, rect: Rect2, kind_a: String, kind_b: String) -> void:
	var a: Rect2 = FOOTPRINTS[terrain_kind(kind_a)]
	var b: Rect2 = FOOTPRINTS[terrain_kind(kind_b)]
	var scale_a := minf(rect.size.x / a.size.x, rect.size.y / a.size.y)
	var scale_b := minf(rect.size.x / b.size.x, rect.size.y / b.size.y)
	var origin_a := rect.get_center().y - a.get_center().y * scale_a
	var origin_b := rect.get_center().y - b.get_center().y * scale_b
	var top := maxf(origin_a + a.end.y * scale_a, origin_b + b.end.y * scale_b)
	var bottom := minf(origin_a + float(ART_BOTTOM[terrain_kind(kind_a)]) * scale_a, origin_b + float(ART_BOTTOM[terrain_kind(kind_b)]) * scale_b)
	var width := 6.0 * rect.size.x / 80.0
	var destination := Rect2(rect.end.x - width * 0.5, top, width, bottom - top)
	var source := Rect2(a.get_center().x - width / scale_a * 0.5, (top - origin_a) / scale_a, width / scale_a, (bottom - top) / scale_a)
	canvas.draw_texture_rect_region(load_sources()[terrain_kind(kind_a)], destination, source)


static func draw_join(canvas: Node2D, rect: Rect2, kind_a: String, kind_b: String, vertical: bool) -> void:
	var a := ground_kind(kind_a)
	var b := ground_kind(kind_b)
	if a == b:
		_draw_join_part(canvas, rect, rect, a, vertical)
		return
	var length := rect.size.y if vertical else rect.size.x
	var step_size := length / (16.0 if vertical else 20.0)
	for index in range(int(round(length / step_size))):
		var offset := step_size * index
		# Only the narrow shared border changes; the rest of each original stays put.
		var split: float = 0.5 if a == b else [0.3, 0.5, 0.7, 0.5][index % 4]
		var first := Rect2(rect.position + (Vector2(0, offset) if vertical else Vector2(offset, 0)), Vector2(rect.size.x * split, step_size) if vertical else Vector2(step_size, rect.size.y * split))
		var second := Rect2(first.position + (Vector2(first.size.x, 0) if vertical else Vector2(0, first.size.y)), Vector2(rect.size.x - first.size.x, step_size) if vertical else Vector2(step_size, rect.size.y - first.size.y))
		_draw_join_part(canvas, first, rect, a, vertical)
		_draw_join_part(canvas, second, rect, b, vertical)


static func _draw_join_part(canvas: Node2D, part: Rect2, whole: Rect2, kind: String, vertical: bool) -> void:
	var footprint: Rect2 = FOOTPRINTS[kind]
	var scale_value := (whole.size.y / 64.0 if vertical else whole.size.x / 80.0) * 80.0 / footprint.size.x
	var source_position := footprint.get_center() + (part.position - whole.get_center()) / scale_value
	# Choose the original middle strip, away from the authored bevel. Do not mirror,
	# recolor, blur, or build a new low-resolution image from sampled colors.
	var source_rect := Rect2(source_position, part.size / scale_value)
	canvas.draw_texture_rect_region(load_sources()[kind], part, source_rect)


static func approved_tree() -> Texture2D:
	var original: Texture2D = load(SOURCE_ROOT + "tree_tile_concept_v2_large.png")
	var tree := original.get_image().get_region(TREE_REGION)
	# Trace the lower canopy where the concept's grass lies behind the branches.
	# RGB pixels inside the silhouette are copied unchanged from the approved tree.
	var lower_canopy := PackedVector2Array([
		Vector2(366, 475), Vector2(1172, 475),
		Vector2(1172, 497), Vector2(1094, 497), Vector2(1094, 537),
		Vector2(1055, 537), Vector2(1055, 576), Vector2(995, 576),
		Vector2(995, 596), Vector2(935, 596), Vector2(935, 577),
		Vector2(875, 577), Vector2(875, 597), Vector2(845, 597),
		Vector2(845, 755), Vector2(634, 755), Vector2(634, 597),
		Vector2(546, 597), Vector2(546, 577), Vector2(506, 577),
		Vector2(506, 557), Vector2(466, 557), Vector2(466, 518),
		Vector2(426, 518), Vector2(426, 497), Vector2(366, 497),
	])
	for y in range(tree.get_height()):
		for x in range(tree.get_width()):
			var color := tree.get_pixel(x, y)
			var p := Vector2i(x, y) + TREE_REGION.position
			var keep := color.a >= 0.95
			if p.y >= 597:
				# Trunk and root pixels; exclude the green ground around them.
				keep = keep and color.r > color.g * 1.12 and color.r > color.b * 1.35
			elif p.y >= 475:
				keep = keep and Geometry2D.is_point_in_polygon(Vector2(p), lower_canopy)
			color.a = 1.0 if keep else 0.0
			tree.set_pixel(x, y, color)
	return ImageTexture.create_from_image(tree)
