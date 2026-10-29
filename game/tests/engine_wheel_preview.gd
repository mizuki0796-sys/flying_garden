extends SceneTree

const OUTPUT := "res://../artifacts/game/engine-wheel-only/"

func _init() -> void:
	call_deferred("run")

func capture(canvas, path: String) -> void:
	canvas.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	assert(root.get_texture().get_image().save_png(path) == OK)

func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Use a rendering display for frame capture")
		quit(1)
		return
	root.size = Vector2i(480, 600)
	root.content_scale_size = Vector2i(480, 600)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT + "frames"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT + "baseline"))
	var canvas = load("res://tests/engine_wheel_preview_canvas.gd").new()
	root.add_child(canvas)
	for frame in range(80):
		canvas.animation_time = frame / 20.0
		canvas.baseline_mode = false
		await capture(canvas, OUTPUT + "frames/frame-%03d.png" % frame)
		canvas.baseline_mode = true
		await capture(canvas, OUTPUT + "baseline/frame-%03d.png" % frame)
	canvas.queue_free()
	await process_frame
	print("WHEEL PREVIEW: 80 current frames + 80 original/smoke reference frames")
	quit()
