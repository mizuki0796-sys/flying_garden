extends SceneTree

const OUT := "res://../artifacts/game/collector-single-tile-animation/"
const Rotor = preload("res://art_templates/complex_ui/collector_propellers.gd")
const FPS := 50
const FRAME_COUNT := 80
var ship: Sprite2D

func _init() -> void:
	call_deferred("run")

func capture(seconds: float, baseline := false) -> Image:
	ship.set_time(seconds)
	ship.material.set_shader_parameter("original_only", baseline)
	await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()

func check_blades() -> void:
	for region in [Rotor.LEFT_REGION, Rotor.RIGHT_REGION]:
		var center := Rotor.LEFT_HUB if region == Rotor.LEFT_REGION else Rotor.RIGHT_HUB
		var cells := {}
		for y in range(region.position.y, region.end.y):
			for x in range(region.position.x, region.end.x):
				if ship.blade_image.get_pixel(x, y).a < 0.5: continue
				var point := Vector2i(x, y)
				cells[point] = true
				var radius := ((Vector2(point) - center) / Vector2(0.55, 1)).length()
				assert(region.has_point(Vector2i(center - Vector2(radius * 0.55, radius))) and region.has_point(Vector2i(center + Vector2(radius * 0.55, radius))), "Blade swept bounds exceed the authorized region")
		assert(not cells.is_empty())
		var pending: Array[Vector2i] = [cells.keys()[0]]
		cells.erase(pending[0])
		while not pending.is_empty():
			var point: Vector2i = pending.pop_back()
			for step in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var neighbor: Vector2i = point + step
				if cells.has(neighbor):
					cells.erase(neighbor)
					pending.append(neighbor)
		assert(cells.is_empty(), "The moving blade must be one solid connected piece")
		var root_point := Vector2i(center) + Vector2i(0, -4)
		assert(ship.blade_image.get_pixelv(root_point).a == 1.0, "Blade root must reach behind the fixed axle cap")

func run() -> void:
	assert(DisplayServer.get_name() != "headless", "Use GPU rendering for the preview")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT + "frames"))
	root.size = Vector2i(640, 640)
	root.content_scale_size = root.size
	var background := ColorRect.new()
	background.color = Color("#e2ebe2")
	background.size = Vector2(640, 640)
	root.add_child(background)
	ship = Rotor.new()
	root.add_child(ship)
	ship.set_process(false)
	ship.position = Vector2(320, 320)
	var native_scale: Vector2 = ship.scale
	assert((ship.region_rect.size * native_scale).x <= 80.0 and (ship.region_rect.size * native_scale).y <= 64.0)
	ship.scale *= 7.0
	ship.parts_mask.save_png(OUT + "parts-mask.png")
	ship.blade_image.save_png(OUT + "blade-source.png")
	check_blades()
	var baseline := await capture(0, true)
	assert(baseline.save_png(OUT + "baseline.png") == OK)
	var moving_rects: Array[Rect2i] = []
	var protected_pixel_count := 640 * 640
	for region in [Rotor.LEFT_REGION, Rotor.RIGHT_REGION]:
		var start := (ship.position + (Vector2(region.position) - Rotor.SOURCE_CENTER) * ship.scale).floor()
		var end := (ship.position + (Vector2(region.end) - Rotor.SOURCE_CENTER) * ship.scale).ceil()
		var rect := Rect2i(Vector2i(start), Vector2i(end - start))
		moving_rects.append(rect)
		protected_pixel_count -= rect.get_area()
	var hub_pixels := PackedInt32Array()
	for y in range(640):
		for x in range(640):
			var point := Vector2i((Vector2(x + 0.5, y + 0.5) - ship.position) / ship.scale + Rotor.SOURCE_CENTER)
			if (Rotor.LEFT_REGION.has_point(point) or Rotor.RIGHT_REGION.has_point(point)) and ship.parts_mask.get_pixelv(point).g > 0.5:
				hub_pixels.append((y * 640 + x) * 3)
	baseline.convert(Image.FORMAT_RGB8)
	var reference := baseline.get_data()
	var fixed_reference: Image = baseline.duplicate()
	for rect in moving_rects: fixed_reference.fill_rect(rect, Color.BLACK)
	var fixed_bytes := fixed_reference.get_data()
	var first: Image
	var animated_frames := 0
	var side_changes := [0, 0]
	var previous: Image
	for frame in range(FRAME_COUNT):
		var current := await capture(float(frame) / FPS)
		assert(current.save_png(OUT + "frames/frame-%03d.png" % frame) == OK)
		current.convert(Image.FORMAT_RGB8)
		var pixels := current.get_data()
		var fixed: Image = current.duplicate()
		for rect in moving_rects: fixed.fill_rect(rect, Color.BLACK)
		assert(fixed.get_data() == fixed_bytes, "Ship outside the two rotor regions changed")
		for offset in hub_pixels:
			assert(pixels[offset] == reference[offset] and pixels[offset + 1] == reference[offset + 1] and pixels[offset + 2] == reference[offset + 2], "Protected ship pixel changed at frame %d, byte %d" % [frame, offset])
		if previous != null:
			for side in range(2):
				if current.get_region(moving_rects[side]).get_data() != previous.get_region(moving_rects[side]).get_data():
					side_changes[side] += 1
		previous = current
		if frame == 0:
			first = current
		elif pixels != first.get_data():
			animated_frames += 1
	var loop := await capture(float(FRAME_COUNT) / FPS)
	loop.convert(Image.FORMAT_RGB8)
	assert(loop.get_data() == first.get_data(), "Loop endpoint must match frame zero")
	assert(side_changes == [FRAME_COUNT - 1, FRAME_COUNT - 1], "Both propellers must advance at every sample")
	ship.scale = native_scale
	var native := await capture(0.2)
	assert(native.save_png(OUT + "native-size.png") == OK)
	var report := {"fps": FPS, "frames": FRAME_COUNT, "duration": float(FRAME_COUNT) / FPS,
		"period": Rotor.PERIOD, "protected_pixels_per_frame": protected_pixel_count,
		"protected_hub_pixels_per_frame": hub_pixels.size(), "changed_frames": animated_frames,
		"consecutive_changes_per_side": side_changes, "solid_blades_and_swept_bounds": "PASS",
		"max_size": [80, 64], "canvas_size_in_game": [80, 64], "pixel_scope": "PASS", "loop": "PASS"}
	var file := FileAccess.open(OUT + "validation.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	print("COLLECTOR PROPELLERS: ", JSON.stringify(report))
	quit()
