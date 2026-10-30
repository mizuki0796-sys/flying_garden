extends SceneTree

const OUTPUT := "res://../artifacts/game/engine-wheel-clean/"

func _init() -> void:
	call_deferred("run")

func capture(canvas: Node2D, path: String) -> void:
	canvas.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	assert(root.get_texture().get_image().save_png(path) == OK)

func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("A rendering display is required")
		quit(1)
		return
	root.size = Vector2i(480, 600)
	root.content_scale_size = Vector2i(480, 600)
	for folder in ["frames", "baseline", "detail", "detail-baseline"]:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT + folder))
	var canvas = load("res://tests/engine_wheel_preview_canvas.gd").new()
	canvas.show_title = false
	root.add_child(canvas)
	for frame in range(80):
		canvas.animation_time = frame / 20.0
		canvas.preview_scale = 3.0
		canvas.preview_bottom_center = Vector2(240, 552)
		canvas.baseline_mode = false
		await capture(canvas, OUTPUT + "frames/frame-%03d.png" % frame)
		canvas.baseline_mode = true
		await capture(canvas, OUTPUT + "baseline/frame-%03d.png" % frame)
		canvas.preview_scale = 12.0
		canvas.preview_bottom_center = Vector2(0, 590)
		canvas.baseline_mode = false
		await capture(canvas, OUTPUT + "detail/frame-%03d.png" % frame)
		canvas.baseline_mode = true
		await capture(canvas, OUTPUT + "detail-baseline/frame-%03d.png" % frame)
	canvas.preview_scale = 1.0
	canvas.preview_bottom_center = Vector2(240, 350)
	canvas.baseline_mode = false
	await capture(canvas, OUTPUT + "native-size.png")
	canvas.queue_free()
	await process_frame
	await capture_in_game()
	print("CLEAN WHEEL: 80 frames at 3x + 12x, same-time baselines, native size")
	quit()

func capture_in_game() -> void:
	root.size = Vector2i(1152, 648)
	root.content_scale_size = Vector2i(1152, 648)
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.set_physics_process(false)
	game._start_demo()
	game.development.tile_at(Vector2i(0, -2)).facility = "power"
	game.animation_time = 0.75
	game.context_panel.hide()
	game._set_view_mode(game.VIEW_FOCUS)
	game.camera_zoom = 1.5
	game.camera_zoom_target = 1.5
	game.camera_world = game.island_pos + Vector2(0, -40)
	await capture(game, OUTPUT + "in-game.png")
	game.queue_free()
	await process_frame
