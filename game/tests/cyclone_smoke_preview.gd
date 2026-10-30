extends SceneTree

const OUTPUT := "res://../artifacts/game/cyclone-smoke/"

func _init() -> void:
	call_deferred("run")

func capture(canvas, path: String) -> Image:
	canvas.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	var result := root.get_texture().get_image()
	assert(result.save_png(path) == OK)
	return result

func run() -> void:
	if DisplayServer.get_name() == "headless": quit(1); return
	root.size = Vector2i(480, 600)
	root.content_scale_size = Vector2i(480, 600)
	for folder in ["calm", "frames"]:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT + folder))
	var canvas = load("res://tests/engine_wheel_preview_canvas.gd").new()
	canvas.show_title = false
	root.add_child(canvas)
	var changed := 0
	for frame in range(80):
		canvas.animation_time = frame / 20.0
		canvas.wind_strength = 0.15
		var calm: Image = await capture(canvas, OUTPUT + "calm/frame-%03d.png" % frame)
		canvas.wind_strength = 1.6
		var gale: Image = await capture(canvas, OUTPUT + "frames/frame-%03d.png" % frame)
		# Chimney origin is above y=330; compare full building region below it.
		if calm.get_region(Rect2i(0, 330, 480, 270)).get_data() != gale.get_region(Rect2i(0, 330, 480, 270)).get_data():
			push_error("Smoke change altered protected building pixels")
			quit(1)
			return
		if calm.get_data() != gale.get_data(): changed += 1
	print("CYCLONE SMOKE: %d/80 frames differ only above protected building; 20 FPS, 4 seconds" % changed)
	canvas.queue_free()
	await process_frame
	quit(0 if changed == 80 else 1)
