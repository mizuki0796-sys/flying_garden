extends RefCounted

# The terrain footprint is shared by rendering, farming, picking, and island mass.
const PixelTerrain = preload("res://scripts/pixel_terrain.gd")
const CELL_SIZE := Vector2(80, 64)
const MASS := {"grass": 1.0, "farm": 1.0, "sand": 0.8, "tree": 1.3, "rock": 1.6, "lava": 1.4, "gold": 2.2}
const COLORS := {"grass": Color("#85b960"), "farm": Color("#91bc68"), "sand": Color("#e6ca8c"), "tree": Color("#719b58"), "rock": Color("#a3aa87"), "lava": Color("#874d42"), "gold": Color("#a39867")}
static var shadow_cache: Dictionary = {}


static func initial_tiles() -> Array:
	var terrain := [
		["tree", "grass", "grass", "grass", "rock"],
		["sand", "farm", "farm", "farm", "grass"],
		["grass", "farm", "farm", "farm", "grass"],
		["tree", "farm", "farm", "farm", "rock"],
		["sand", "grass", "sand", "grass", "tree"]
	]
	var tiles: Array = []
	for y in range(5):
		for x in range(5):
			var facility := ""
			if Vector2i(x, y) == Vector2i(1, 0):
				facility = "water"
			var cell := Vector2i(x - 2, y - 2)
			tiles.append({"cell": cell, "kind": terrain[y][x], "facility": facility, "level": 1, "hp": 100.0, "depleted": false})
	return tiles


static func wild_tiles(biome: int, variant: int, size_class := 0) -> Array:
	var tiles: Array = []
	var shapes := [
		[Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1)],
		[Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)],
		[Vector2i(-1, 0), Vector2i(0, 0), Vector2i(1, 0)],
		[Vector2i(0, -1), Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1)]
	]
	var cells: Array = shapes[variant % shapes.size()]
	if size_class > 0:
		cells = []
		var radius := 2 if size_class == 1 else 3
		for y in range(-radius, radius + 1):
			for x in range(-radius, radius + 1):
				# Uneven corners keep large islands readable instead of making rectangles.
				if abs(x) + abs(y) <= radius + 1 and posmod(x * 7 + y * 11 + variant, 9) != 0:
					cells.append(Vector2i(x, y))
	for cell in cells:
		var kind := "grass"
		if biome == 0 and (cell.x + cell.y) % 2 == 0:
			kind = "tree"
		elif biome == 1:
			kind = "rock"
		elif biome == 2:
			kind = "sand" if cell.x != 1 else "rock"
		elif biome == 4:
			kind = "lava" if cell.x == 0 else "rock"
		elif biome == 5:
			kind = "gold" if cell.x == 0 else "rock"
		tiles.append({"cell": cell, "kind": kind, "facility": "", "level": 1, "hp": 100.0, "depleted": false})
	return tiles


static func bounds(tiles: Array) -> Rect2:
	var result := cell_rect(Vector2.ZERO, tiles[0].cell)
	for tile in tiles:
		result = result.merge(cell_rect(Vector2.ZERO, tile.cell))
	return result


static func mass(tiles: Array) -> float:
	var total := 0.0
	for tile in tiles:
		total += float(MASS[tile.kind])
		if not str(tile.facility).is_empty():
			total += 0.5
	return total


static func cell_rect(center: Vector2, cell: Vector2i, size: Vector2 = CELL_SIZE) -> Rect2:
	return Rect2(center + Vector2(cell) * size - size * 0.5, size)

static func rect_clearance(a: Rect2, b: Rect2) -> float:
	var gap := (b.get_center() - a.get_center()).abs() - (a.size + b.size) * 0.5
	return Vector2(maxf(gap.x, 0.0), maxf(gap.y, 0.0)).length() + minf(maxf(gap.x, gap.y), 0.0)

static func clearance(a_tiles: Array, a_origin: Vector2, b_tiles: Array, b_origin: Vector2) -> float:
	var closest := INF
	for a in a_tiles:
		var a_rect := cell_rect(a_origin, a.cell)
		for b in b_tiles:
			closest = minf(closest, rect_clearance(a_rect, cell_rect(b_origin, b.cell)))
	return closest

static func contact(a_tiles: Array, a_origin: Vector2, b_tiles: Array, b_origin: Vector2) -> Dictionary:
	# The same 80 x 64 occupied cells used to draw both islands. Canopies,
	# shadows, cliff decoration and enclosing circles never cause damage.
	var result: Dictionary = {}
	for a in a_tiles:
		var a_rect := cell_rect(a_origin, a.cell)
		for b in b_tiles:
			var b_rect := cell_rect(b_origin, b.cell)
			if not a_rect.intersects(b_rect): continue
			var overlap := a_rect.intersection(b_rect)
			var depth := minf(overlap.size.x, overlap.size.y)
			if depth <= 0.01 or depth <= float(result.get("depth", 0.0)): continue
			var delta := a_rect.get_center() - b_rect.get_center()
			var normal := Vector2(signf(delta.x), 0) if overlap.size.x < overlap.size.y else Vector2(0, signf(delta.y))
			if normal == Vector2.ZERO: normal = Vector2.LEFT
			result = {"point": overlap.get_center(), "normal": normal, "depth": depth, "cell": a.cell}
	return result


static func draw_ground(canvas: Node2D, center: Vector2, tiles: Array, size: Vector2 = CELL_SIZE, textures: Dictionary = {}) -> void:
	if not textures.is_empty():
		_draw_textured_ground(canvas, center, tiles, size, textures)
		return
	var occupied: Dictionary = {}
	for tile in tiles:
		occupied[tile.cell] = true
	var depth := size.y * 0.56
	# Exposed cliff faces only: adjacent cells form a single connected land mass.
	for tile in tiles:
		var cell: Vector2i = tile.cell
		var rect := cell_rect(center, cell, size)
		var drop := Vector2(8.0 * size.x / CELL_SIZE.x, depth)
		if not occupied.has(cell + Vector2i(0, 1)):
			var left := Vector2(rect.position.x, rect.end.y)
			var right := rect.end
			canvas.draw_colored_polygon(PackedVector2Array([left, right, right + drop, left + drop]), Color("#815a49"))
			canvas.draw_colored_polygon(PackedVector2Array([left + drop, left.lerp(right, 0.45) + drop + Vector2(0, depth * 0.28), right + drop]), Color("#65534b"))
			canvas.draw_line(left + drop * 0.45, right + drop * 0.45, Color("#ad8060"), maxf(1.0, size.y * 0.08))
			for pebble in range(3):
				var pebble_pos := left + Vector2(size.x * (0.16 + pebble * 0.29), depth * 0.67)
				canvas.draw_rect(Rect2(pebble_pos, size * Vector2(0.12, 0.09)), Color("#c29b76"))
		if not occupied.has(cell + Vector2i(1, 0)):
			var top := Vector2(rect.end.x, rect.position.y)
			canvas.draw_colored_polygon(PackedVector2Array([top, rect.end, rect.end + drop, top + drop]), Color("#61524b"))
	for tile in tiles:
		var cell: Vector2i = tile.cell
		var rect := cell_rect(center, cell, size)
		var color: Color = COLORS[tile.kind]
		color = color.lightened(0.025 * posmod(cell.x + cell.y * 3, 3))
		canvas.draw_rect(rect, color)
		canvas.draw_rect(rect.grow(-1.0), color.darkened(0.12), false, 1.0)
		canvas.draw_line(rect.position + Vector2(2, 2), rect.position + Vector2(size.x - 2, 2), color.lightened(0.15), 2.0)
		if not occupied.has(cell + Vector2i(0, 1)):
			canvas.draw_line(Vector2(rect.position.x, rect.end.y - 2), rect.end - Vector2(0, 2), color.darkened(0.28), maxf(2.0, size.y * 0.08))
		if tile.kind == "grass" or tile.kind == "sand" or tile.kind == "tree":
			for mark in range(4):
				var detail := rect.position + size * Vector2(0.15 + 0.20 * mark, 0.25 + 0.15 * posmod(cell.x + cell.y + mark, 4))
				canvas.draw_rect(Rect2(detail, Vector2(3, 2) * size.x / CELL_SIZE.x), color.darkened(0.20))

static func draw_shadow(canvas, origin: Vector2, tiles: Array) -> void:
	var cells: Array = []
	for tile in tiles: cells.append(tile.cell)
	var key := str(cells)
	if not shadow_cache.has(key):
		var contours: Array[PackedVector2Array] = []
		var footprint := bounds(tiles)
		for tile in tiles:
			var rect := cell_rect(Vector2.ZERO, tile.cell).grow(0.05)
			var polygon := PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)])
			var index := 0
			while index < contours.size():
				var merged := Geometry2D.merge_polygons(polygon, contours[index])
				if merged.size() == 1:
					polygon = merged[0]
					contours.remove_at(index)
					index = 0
				else: index += 1
			contours.append(polygon)
		var layers: Array = []
		for contour in contours:
			var projected := PackedVector2Array()
			for point in contour:
				projected.append(Vector2(point.x + 18.0, footprint.end.y + 20.0 + (point.y - footprint.get_center().y) * 0.28))
			for feather in [18.0, 14.0, 10.0, 7.0, 4.0, 1.0]:
				for expanded in Geometry2D.offset_polygon(projected, feather, Geometry2D.JOIN_ROUND):
					layers.append(expanded)
		if shadow_cache.size() > 256: shadow_cache.clear()
		shadow_cache[key] = layers
	for polygon in shadow_cache[key]:
		var points := PackedVector2Array()
		for point in polygon: points.append(point + origin)
		canvas.draw_colored_polygon(points, Color(0.16, 0.27, 0.30, 0.021))


static func wind_bend(time: float, phase: float, strength: float) -> float:
	return -strength * (0.55 + sin(time * (1.8 + strength) + phase) * 0.45 + sin(time * 5.3 + phase * 1.7) * 0.20)


static func draw_wind_sprite(canvas: Node2D, texture: Texture2D, destination: Rect2, region: Rect2, root_y: float, bend: float, tint := Color.WHITE) -> void:
	# Bend the upper silhouette in strips, keeping the trunk/roots planted.
	var texture_size := texture.get_size()
	var height := maxf(1.0, root_y - destination.position.y)
	for strip in range(10):
		var top := float(strip) / 10.0
		var bottom := float(strip + 1) / 10.0
		var y0 := destination.position.y + destination.size.y * top
		var y1 := destination.position.y + destination.size.y * bottom
		var x0 := bend * pow(clampf((root_y - y0) / height, 0.0, 1.0), 2.0)
		var x1 := bend * pow(clampf((root_y - y1) / height, 0.0, 1.0), 2.0)
		var points := PackedVector2Array([Vector2(destination.position.x + x0, y0), Vector2(destination.end.x + x0, y0), Vector2(destination.end.x + x1, y1), Vector2(destination.position.x + x1, y1)])
		var uv0 := (region.position + Vector2(0, region.size.y * top)) / texture_size
		var uv1 := (region.position + Vector2(region.size.x, region.size.y * bottom)) / texture_size
		canvas.draw_polygon(points, PackedColorArray([tint]), PackedVector2Array([uv0, Vector2(uv1.x, uv0.y), uv1, Vector2(uv0.x, uv1.y)]), texture)


static func _tile_painter_order(a: Dictionary, b: Dictionary) -> bool:
	var a_cell: Vector2i = a.cell
	var b_cell: Vector2i = b.cell
	if a_cell.y == b_cell.y:
		return a_cell.x < b_cell.x
	return a_cell.y < b_cell.y


static func _draw_textured_ground(canvas, center: Vector2, tiles: Array, size: Vector2, textures: Dictionary) -> void:
	var ordered := tiles.duplicate()
	ordered.sort_custom(_tile_painter_order)
	var occupied: Dictionary = {}
	for tile in tiles:
		occupied[tile.cell] = tile
	# Continuous backing, then original artwork, then shared-border occlusion.
	# All exterior teeth and soil/rock strata come from the source PNGs.
	for tile in ordered:
		var rect := cell_rect(center, tile.cell, size)
		canvas.draw_texture_rect_region(textures["grass"], rect, PixelTerrain.FOOTPRINTS.grass)
	for tile in ordered:
		var rect := cell_rect(center, tile.cell, size)
		var exposed := {
			"up": not occupied.has(tile.cell + Vector2i.UP),
			"down": not occupied.has(tile.cell + Vector2i.DOWN),
			"left": not occupied.has(tile.cell + Vector2i.LEFT),
			"right": not occupied.has(tile.cell + Vector2i.RIGHT),
		}
		PixelTerrain.draw_original(canvas, rect, str(tile.kind), exposed)
	var join_width := 10.0 * size.x / CELL_SIZE.x
	for vertical in [true, false]:
		for tile in ordered:
			var direction := Vector2i.RIGHT if vertical else Vector2i.DOWN
			if not occupied.has(tile.cell + direction):
				continue
			var neighbor: Dictionary = occupied[tile.cell + direction]
			var rect := cell_rect(center, tile.cell, size)
			var join := Rect2(Vector2(rect.end.x - join_width * 0.5, rect.position.y), Vector2(join_width, size.y)) if vertical else Rect2(Vector2(rect.position.x, rect.end.y - join_width * 0.5), Vector2(size.x, join_width))
			# Don't cover the original perimeter bevel where a join meets open sky.
			var before := Vector2i.UP if vertical else Vector2i.LEFT
			var after := Vector2i.DOWN if vertical else Vector2i.RIGHT
			var inset := 4.0 * size.x / CELL_SIZE.x
			if not occupied.has(tile.cell + before) and not occupied.has(neighbor.cell + before):
				join.position += Vector2(0, inset) if vertical else Vector2(inset, 0)
				join.size -= Vector2(0, inset) if vertical else Vector2(inset, 0)
			if not occupied.has(tile.cell + after) and not occupied.has(neighbor.cell + after):
				join.size -= Vector2(0, inset) if vertical else Vector2(inset, 0)
			PixelTerrain.draw_join(canvas, join, str(tile.kind), str(neighbor.kind), vertical)
			if vertical and not occupied.has(tile.cell + Vector2i.DOWN) and not occupied.has(neighbor.cell + Vector2i.DOWN):
				PixelTerrain.draw_cliff_join(canvas, rect, str(tile.kind), str(neighbor.kind))
	for tile in ordered:
		if bool(tile.get("depleted", false)):
			var rect := cell_rect(center, tile.cell, size)
			for mark in range(3):
				var offset := Vector2(-8 + mark * 6, 18 + posmod(mark, 2) * 3) * size.x / CELL_SIZE.x
				canvas.draw_rect(Rect2(rect.get_center() + offset, Vector2(4, 2) * size.x / CELL_SIZE.x), Color("#695443"))


static func draw_tree(canvas: Node2D, p: Vector2, scale_value: float) -> void:
	canvas.draw_rect(Rect2(p + Vector2(-5, -14) * scale_value, Vector2(10, 23) * scale_value), Color("#805741"))
	var tiers := [Rect2(-22, -49, 44, 28), Rect2(-30, -40, 60, 20), Rect2(-17, -60, 34, 24)]
	for tier in tiers:
		canvas.draw_rect(Rect2(p + tier.position * scale_value, tier.size * scale_value), Color("#3f7852"))
	canvas.draw_rect(Rect2(p + Vector2(-19, -54) * scale_value, Vector2(32, 24) * scale_value), Color("#6baa57"))
	canvas.draw_rect(Rect2(p + Vector2(-11, -58) * scale_value, Vector2(17, 9) * scale_value), Color("#9bc96a"))
	canvas.draw_rect(Rect2(p + Vector2(10, -35) * scale_value, Vector2(12, 9) * scale_value), Color("#508c52"))


static func draw_rocks(canvas: Node2D, p: Vector2, scale_value: float, mineral := false) -> void:
	var vertices := PackedVector2Array()
	for v in [Vector2(-25, 6), Vector2(-22, -15), Vector2(-7, -27), Vector2(15, -25), Vector2(28, -8), Vector2(25, 10)]:
		vertices.append(p + v * scale_value)
	canvas.draw_colored_polygon(vertices, Color("#747e7c"))
	canvas.draw_colored_polygon(PackedVector2Array([p + Vector2(-22, -15) * scale_value, p + Vector2(-7, -27) * scale_value, p + Vector2(15, -25) * scale_value, p + Vector2(5, -6) * scale_value]), Color("#b2b9a9"))
	canvas.draw_line(p + Vector2(5, -6) * scale_value, p + Vector2(25, 10) * scale_value, Color("#525e61"), 2.0 * scale_value)
	if mineral:
		canvas.draw_rect(Rect2(p + Vector2(-6, -14) * scale_value, Vector2(9, 8) * scale_value), Color("#92dfd1"))
		canvas.draw_rect(Rect2(p + Vector2(13, -4) * scale_value, Vector2(7, 6) * scale_value), Color("#73b8be"))


static func tree_hover_alpha(destination: Rect2, root_y: float, bend: float, pointer: Vector2) -> float:
	if pointer.y < destination.position.y or pointer.y > destination.end.y: return 1.0
	var ratio := clampf((root_y - pointer.y) / maxf(1.0, root_y - destination.position.y), 0.0, 1.0)
	var unbent := pointer - Vector2(bend * ratio * ratio, 0)
	return 0.26 if destination.has_point(unbent) else 1.0


static func draw_decor(canvas: Node2D, center: Vector2, tiles: Array, size: Vector2, mineral := false, tree_texture: Texture2D = null, textured_ground := false, time := 0.0, wind := 0.0, pointer := Vector2.INF) -> void:
	var ordered := tiles
	if tiles.size() > 1:
		ordered = tiles.duplicate()
		ordered.sort_custom(_tile_painter_order)
	for tile in ordered:
		var p := cell_rect(center, tile.cell, size).get_center() + Vector2(0, size.y * 0.15)
		var scale_value := size.x / CELL_SIZE.x
		if tile.kind == "tree":
			if tree_texture != null:
				var tree_height := PixelTerrain.TREE_HEIGHT * scale_value * lerpf(0.22, 1.0, float(tile.get("tree_progress", 1.0)))
				var tree_width := tree_height * float(tree_texture.get_width()) / maxf(1.0, float(tree_texture.get_height()))
				var root := cell_rect(center, tile.cell, size).get_center()
				# The original trunk is slightly left of the canopy's center.
				# Align its root (source x=374 in the cropped 806px image) to the cell.
				var root_fraction := 374.0 / float(PixelTerrain.TREE_REGION.size.x)
				var destination := Rect2(root - Vector2(tree_width * root_fraction, tree_height), Vector2(tree_width, tree_height))
				var phase := float(tile.cell.x) * 1.7 + float(tile.cell.y) * 2.3 + center.x * 0.003
				var bend := wind_bend(time, phase, wind) * tree_height * 0.23
				var alpha := tree_hover_alpha(destination, root.y, bend, pointer)
				draw_wind_sprite(canvas, tree_texture, destination, Rect2(Vector2.ZERO, tree_texture.get_size()), root.y, bend, Color(1, 1, 1, alpha))
			else:
				draw_tree(canvas, cell_rect(center, tile.cell, size).get_center() - Vector2(0, 9) * scale_value, scale_value)
		elif tile.kind == "rock" and not textured_ground:
			draw_rocks(canvas, p, scale_value, mineral)
		elif tile.kind == "gold" and not textured_ground:
			draw_rocks(canvas, p, scale_value)
			for gold_index in range(3):
				canvas.draw_rect(Rect2(p + Vector2(-15 + gold_index * 12, -16 + gold_index * 5) * scale_value, Vector2(9, 9) * scale_value), Color("#ffe176"))
		elif tile.kind == "lava" and not textured_ground:
			canvas.draw_polyline(PackedVector2Array([p + Vector2(-26, -17) * scale_value, p + Vector2(-8, 4) * scale_value, p + Vector2(12, -9) * scale_value, p + Vector2(30, 12) * scale_value]), Color("#ff934d"), maxf(1.0, 6 * scale_value))
		elif tile.kind == "grass" and str(tile.facility).is_empty() and not textured_ground:
			var tint := Color("#f8deb1") if posmod(tile.cell.x + tile.cell.y, 2) == 0 else Color("#e8a6a2")
			canvas.draw_rect(Rect2(p + Vector2(15, 4) * scale_value, Vector2(4, 4) * scale_value), tint)
