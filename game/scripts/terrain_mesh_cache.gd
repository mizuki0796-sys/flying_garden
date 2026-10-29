extends RefCounted

# Cache the SAME terrain draw commands and shadow meshes at their build origin.
# Keep native terrain rectangles for exact sampling; combine only consecutive
# shadow polygons of the same color, preserving their original painter order.
class MeshCanvas extends RefCounted:
	var retain_rectangles := false
	var rectangles: Array = []
	var batches: Array = []
	var vertices := PackedVector2Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var current_texture: Texture2D
	var current_color := Color.WHITE

	func draw_texture_rect_region(texture: Texture2D, rect: Rect2, region: Rect2) -> void:
		if retain_rectangles:
			rectangles.append({"texture": texture, "rect": rect, "region": region})
			return
		var uv0 := region.position / texture.get_size()
		var uv1 := region.end / texture.get_size()
		_append(texture, _corners(rect), PackedVector2Array([uv0, Vector2(uv1.x, uv0.y), uv1, Vector2(uv0.x, uv1.y)]), Color.WHITE)

	func draw_rect(rect: Rect2, color: Color) -> void:
		if retain_rectangles:
			rectangles.append({"texture": null, "rect": rect, "color": color})
			return
		_append(null, _corners(rect), PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]), color)

	func draw_colored_polygon(polygon: PackedVector2Array, color: Color) -> void:
		var texcoords := PackedVector2Array()
		texcoords.resize(polygon.size())
		_append(null, polygon, texcoords, color)

	func _corners(rect: Rect2) -> PackedVector2Array:
		return PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)])

	func _append(texture: Texture2D, points: PackedVector2Array, texcoords: PackedVector2Array, color: Color) -> void:
		if texture != current_texture or color != current_color:
			flush()
			current_texture = texture
			current_color = color
		var base := vertices.size()
		vertices.append_array(points)
		uvs.append_array(texcoords)
		for index in Geometry2D.triangulate_polygon(points): indices.append(base + index)

	func flush() -> void:
		if indices.is_empty(): return
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_INDEX] = indices
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, Mesh.ARRAY_FLAG_USE_2D_VERTICES)
		# Mesh vertex colors are quantized to 8 bits. Keep shadow opacity in the
		# canvas modulation instead, matching the original draw_colored_polygon.
		batches.append({"mesh": mesh, "texture": current_texture, "color": current_color})
		vertices = PackedVector2Array()
		uvs = PackedVector2Array()
		indices = PackedInt32Array()

var signature: Array = []
var footprint: Array = []
var texture_ids: Array = []
var ground: Array = []
var shadow: Array = []
var ground_origin := Vector2.ZERO
var shadow_origin := Vector2.ZERO
var ground_builds := 0
var shadow_builds := 0

func draw(canvas: Node2D, origin: Vector2, tiles: Array, textures: Dictionary, tile_drawer: GDScript) -> void:
	var next_signature: Array = []
	var next_footprint: Array = []
	for tile in tiles:
		next_signature.append_array([tile.cell, tile.kind, bool(tile.get("depleted", false))])
		next_footprint.append(tile.cell)
	var next_textures: Array = []
	for key in textures: next_textures.append_array([key, textures[key].get_instance_id()])
	# Snapshots deliberately include in-place changes (harvest, tree death, load).
	# Position, HP, wind and camera do not invalidate immutable ground geometry.
	if signature != next_signature or texture_ids != next_textures:
		var recorder := MeshCanvas.new()
		# Preserve Godot's native region clipping/interpolation at terrain seams.
		# Converting these rects to meshes changes a few nearest-neighbor samples.
		recorder.retain_rectangles = true
		# Evaluate clipping at the original world coordinates: calculating it at
		# zero changes float rounding in UVs, visible as seams at fractional zoom.
		tile_drawer._draw_textured_ground(recorder, origin, tiles, tile_drawer.CELL_SIZE, textures)
		recorder.flush()
		ground = recorder.rectangles
		ground_origin = origin
		signature = next_signature
		texture_ids = next_textures
		ground_builds += 1
	if footprint != next_footprint:
		var recorder := MeshCanvas.new()
		tile_drawer.draw_shadow(recorder, origin, tiles)
		recorder.flush()
		shadow = recorder.batches
		shadow_origin = origin
		footprint = next_footprint
		shadow_builds += 1
	var transform := Transform2D(0.0, origin - shadow_origin)
	for batch in shadow: canvas.draw_mesh(batch.mesh, batch.texture, transform, batch.color)
	for command in ground:
		var rect := Rect2(command.rect.position + (origin - ground_origin), command.rect.size)
		if command.texture != null:
			canvas.draw_texture_rect_region(command.texture, rect, command.region)
		else:
			canvas.draw_rect(rect, command.color)
