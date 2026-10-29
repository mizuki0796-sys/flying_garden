extends RefCounted

# The master supplies the building, rim and COMPLETE foreground connecting rod.
# Only the spokes move behind that foreground. No generated wall or glow is drawn.
const ROOT := "res://assets/pixel_v2/facilities/engine_room_layers_v1/"
const ORIGINAL_REGION := Rect2(295, 91, 958, 845)
const WHEEL_CENTER := Vector2(1025, 684)
const SOURCE_CENTER := Vector2(1024, 648)
const SOURCE_RADIUS := Vector2(158, 166)
const PIXEL_SIZE := 18
const PHASE_COUNT := 128
# Traced from the green annotation; coordinates refer to the original PNG.
const CONNECTION_OUTLINE := [
	Vector2(817, 631), Vector2(920, 631), Vector2(934, 666),
	Vector2(962, 666), Vector2(962, 648), Vector2(980, 648),
	Vector2(980, 631), Vector2(998, 631), Vector2(998, 613),
	Vector2(1070, 613), Vector2(1070, 631), Vector2(1088, 631),
	Vector2(1088, 721), Vector2(1070, 721), Vector2(1070, 739),
	Vector2(980, 739), Vector2(980, 721), Vector2(932, 721),
	Vector2(926, 757), Vector2(817, 757),
]
# Inner opening of the ORIGINAL wheel. Each row is [y, left, right].
# Keeping the rim in the master also keeps its silhouette and lighting fixed.
const OPENING_ROWS := [
	Vector3i(523, 962, 1088), Vector3i(541, 944, 1106),
	Vector3i(559, 926, 1124), Vector3i(577, 908, 1142),
	Vector3i(595, 890, 1142), Vector3i(613, 890, 1142),
	Vector3i(631, 890, 1142), Vector3i(649, 890, 1142),
	Vector3i(667, 890, 1142), Vector3i(685, 890, 1142),
	Vector3i(703, 908, 1142), Vector3i(721, 926, 1142),
	Vector3i(739, 944, 1124), Vector3i(757, 944, 1106),
	Vector3i(775, 962, 1106), Vector3i(793, 980, 1088),
]
var phase_meshes: Array[ArrayMesh] = []
var cells: Array[Dictionary] = []

func load_assets() -> void:
	var master: Image = load("res://assets/pixel_v2/facilities/engine_room_v2.png").get_image()
	var spokes: Image = load(ROOT + "flywheel.png").get_image()
	_build_cells(master)
	phase_meshes.clear()
	for phase in range(PHASE_COUNT):
		phase_meshes.append(_build_phase(spokes, TAU * phase / PHASE_COUNT))

func _copper(color: Color) -> bool:
	# Copper includes the pale yellow highlights, not just orange midtones.
	var orange_or_shadow := color.r > color.g * 1.3 and color.r > color.b * 1.3
	var yellow_highlight := color.r >= color.g * 0.94 and color.r > color.b * 1.35 and color.g > color.b * 1.1
	return color.a > 0.94 and (orange_or_shadow or yellow_highlight)

func _wall_sample(source: Image, point: Vector2i) -> Color:
	# Local reconstruction behind old spokes; visible wall pixels stay original.
	for distance in range(PIXEL_SIZE, 145, PIXEL_SIZE):
		for offset in [Vector2i(-distance, 0), Vector2i(distance, 0), Vector2i(0, -distance), Vector2i(0, distance)]:
			var candidate: Vector2i = point + offset
			if candidate.x < 906 or candidate.x > 1140 or candidate.y < 528 or candidate.y > 806: continue
			if Geometry2D.is_point_in_polygon(Vector2(candidate), PackedVector2Array(CONNECTION_OUTLINE)): continue
			var color := source.get_pixelv(candidate)
			if color.a > 0.94 and not _copper(color) and maxf(color.r, maxf(color.g, color.b)) < 0.24:
				color.a = 1.0
				return color
	var fallback := source.get_pixel(990, 550)
	fallback.a = 1.0
	return fallback

func _build_cells(source: Image) -> void:
	cells.clear()
	var foreground := PackedVector2Array(CONNECTION_OUTLINE)
	for row in OPENING_ROWS:
		for x in range(row.y, row.z, PIXEL_SIZE):
			var region := Rect2(x, row.x, PIXEL_SIZE, PIXEL_SIZE)
			var polygon := PackedVector2Array([region.position, Vector2(region.end.x, region.position.y), region.end, Vector2(region.position.x, region.end.y)])
			var clipped := Geometry2D.clip_polygons(polygon, foreground)
			# Keep entire pixel blocks at the rod's two diagonal boundaries.
			# Partial moving triangles would look like loose flecks at this scale.
			if not Geometry2D.intersect_polygons(polygon, foreground).is_empty(): continue
			var point := Vector2i(region.get_center())
			var patches: Array[Dictionary] = []
			# Exact source-pixel runs remove old copper, including its dark edge.
			# The former 6px center-sample mask left static copper crumbs behind.
			for py in range(int(region.position.y), int(region.end.y)):
				var run_start := -1
				for px in range(x, x + PIXEL_SIZE + 1):
					var erase := px < x + PIXEL_SIZE and not Geometry2D.is_point_in_polygon(Vector2(px + 0.5, py + 0.5), foreground) and _copper(source.get_pixel(px, py))
					if erase and run_start < 0: run_start = px
					if not erase and run_start >= 0:
						patches.append({"rect": Rect2(run_start, py, px - run_start, 1)})
						run_start = -1
			cells.append({"point": Vector2(point), "polygons": clipped, "patches": patches, "backing": _wall_sample(source, point)})

func _append_polygon(vertices: PackedVector3Array, colors: PackedColorArray, indices: PackedInt32Array, polygon: PackedVector2Array, color: Color) -> void:
	var base := vertices.size()
	for point in polygon:
		vertices.append(Vector3(point.x, point.y, 0))
		colors.append(color)
	for index in Geometry2D.triangulate_polygon(polygon): indices.append(base + index)

func _build_phase(source: Image, angle: float) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	for cell in cells:
		var local: Vector2 = cell.point - WHEEL_CENTER
		# The painted opening extends farther above its axle. Map its two halves
		# separately, keeping the axle and original rim at their exact positions.
		var unit := local / Vector2(135, 161 if local.y < 0 else 127)
		# Sample the spoke band, never the detached asset's outer rim. Extend its
		# radial ends to the original opening so no rotating ring fragments appear.
		var source_unit := unit.rotated(-angle).limit_length(0.80)
		var sample_point := Vector2i(SOURCE_CENTER + source_unit * SOURCE_RADIUS)
		var color := source.get_pixelv(sample_point)
		# Discard ALL translucent glow and background; retain solid spoke pixels.
		var spoke := _copper(color) and color.r > 0.32
		if spoke:
			color.a = 1.0
			for polygon in cell.polygons: _append_polygon(vertices, colors, indices, polygon, color)
		else:
			for patch in cell.patches:
				var rect: Rect2 = patch.rect
				_append_polygon(vertices, colors, indices, PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]), cell.backing)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

func draw(canvas: CanvasItem, original: Texture2D, destination: Rect2, angle: float) -> void:
	canvas.draw_texture_rect(original, destination, false)
	var scale_value := destination.size.x / ORIGINAL_REGION.size.x
	var origin := destination.position - ORIGINAL_REGION.position * scale_value
	var phase := posmod(roundi(angle / TAU * PHASE_COUNT), PHASE_COUNT)
	canvas.draw_mesh(phase_meshes[phase], null, Transform2D(Vector2(scale_value, 0), Vector2(0, scale_value), origin))
