extends RefCounted

const WIND_SHADER = preload("res://shaders/crop_wind.gdshader")
var material := ShaderMaterial.new()
var meshes: Dictionary = {}
var plots: Dictionary = {}
var used: Dictionary = {}

func _init() -> void:
	material.shader = WIND_SHADER

func begin_frame(time: float, wind: float) -> void:
	material.set_shader_parameter("animation_time", time)
	material.set_shader_parameter("wind_strength", wind)
	used.clear()

func end_frame() -> void:
	# Removed farms and old save files must not accumulate GPU resources.
	for cell in plots.keys():
		if not used.has(cell): plots.erase(cell)

func draw(canvas: Node2D, cell: Vector2i, texture: Texture2D, region: Rect2,
		scale_value: float, baseline: float, stage: int, center: Vector2) -> void:
	var key := "%d:%d" % [texture.get_instance_id(), stage]
	if not meshes.has(key): meshes[key] = _make_mesh(texture, region, scale_value, baseline, stage)
	var record: Dictionary = plots.get(cell, {})
	if record.is_empty():
		var instances := MultiMesh.new()
		instances.transform_format = MultiMesh.TRANSFORM_2D
		instances.use_custom_data = true
		instances.instance_count = 9
		record = {"instances": instances, "key": "", "center": Vector2.INF}
		plots[cell] = record
	var mesh: MultiMesh = record.instances
	if record.key != key:
		mesh.mesh = meshes[key]
		for row in range(3):
			for column in range(3):
				var phase := float(cell.x) * 1.8 + float(cell.y) * 2.4 + row * 0.35 + column * 0.25
				# All authored cell phases are multiples of .05. Avoid passing a
				# full phase through GLES half floats (large phases lost precision).
				var whole := floorf(phase)
				var fraction := (phase - whole) * 1024.0
				mesh.set_instance_custom_data(row * 3 + column, Color(whole, floorf(fraction), fraction - floorf(fraction), 1.0))
		record.key = key
	if record.center != center:
		for row in range(3):
			for column in range(3):
				mesh.set_instance_transform_2d(row * 3 + column, Transform2D(0.0, center + Vector2((column - 1) * 18.0, -3.0 + row * 12.0)))
		record.center = center
	used[cell] = true
	canvas.draw_multimesh(mesh, texture)

func _make_mesh(texture: Texture2D, region: Rect2, scale_value: float, baseline: float, stage: int) -> ArrayMesh:
	var vertices := PackedVector2Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var bending := PackedFloat32Array()
	var size := region.size * scale_value
	# Same ten strip boundaries and triangulation as draw_wind_sprite. The GPU
	# moves those vertices, rather than regenerating ninety polygons per farm.
	for strip in range(10):
		var top := float(strip) / 10.0
		var bottom := float(strip + 1) / 10.0
		var y0 := -baseline * scale_value + size.y * top
		var y1 := -baseline * scale_value + size.y * bottom
		var base := vertices.size()
		vertices.append_array(PackedVector2Array([Vector2(-size.x * 0.5, y0), Vector2(size.x * 0.5, y0), Vector2(size.x * 0.5, y1), Vector2(-size.x * 0.5, y1)]))
		var uv0 := (region.position + Vector2(0, region.size.y * top)) / texture.get_size()
		var uv1 := (region.position + Vector2(region.size.x, region.size.y * bottom)) / texture.get_size()
		uvs.append_array(PackedVector2Array([uv0, Vector2(uv1.x, uv0.y), uv1, Vector2(uv0.x, uv1.y)]))
		indices.append_array(PackedInt32Array([base + 3, base, base + 1, base + 1, base + 2, base + 3]))
		for y in [y0, y0, y1, y1]:
			bending.append_array(PackedFloat32Array([pow(clampf(-y / (baseline * scale_value), 0.0, 1.0), 2.0), 4.0 * (0.45 + stage * 0.14), 0.0, 0.0]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	arrays[Mesh.ARRAY_CUSTOM0] = bending
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, Mesh.ARRAY_FLAG_USE_2D_VERTICES | (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT))
	return mesh
