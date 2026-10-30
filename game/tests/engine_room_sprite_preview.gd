extends SceneTree

# Capture the existing game renderer, including its unchanged chimney smoke.
# No generated video, motion retiming, automatic looping or new visual effects.
const OUTPUT := "res://../artifacts/game/engine-room-sprite-trial/"
const FPS := 20
const FRAME_COUNT := 80

func _init() -> void:
	call_deferred("run")

func capture(viewport: SubViewport, canvas: Node2D, path: String) -> void:
	canvas.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	assert(viewport.get_texture().get_image().save_png(path) == OK)

func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("A rendering display is required for the sprite capture")
		quit(1)
		return
	root.size = Vector2i(480, 600)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(480, 600)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	for folder in ["frames", "baseline", "preview"]:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT + folder))
	var canvas = load("res://tests/engine_wheel_preview_canvas.gd").new()
	canvas.show_title = false
	viewport.add_child(canvas)
	for frame in range(FRAME_COUNT):
		canvas.animation_time = frame / float(FPS)
		canvas.transparent_background = true
		canvas.baseline_mode = false
		await capture(viewport, canvas, OUTPUT + "frames/frame-%03d.png" % frame)
		canvas.baseline_mode = true
		await capture(viewport, canvas, OUTPUT + "baseline/frame-%03d.png" % frame)
		canvas.baseline_mode = false
		canvas.transparent_background = false
		await capture(viewport, canvas, OUTPUT + "preview/frame-%03d.png" % frame)
	var manifest := {
		"source": "game/assets/pixel_v2/facilities/engine_room_v2.png",
		"renderer": "game/scripts/main.gd::_draw_building",
		"frames": FRAME_COUNT, "fps": FPS, "duration_seconds": FRAME_COUNT / float(FPS),
		"canvas": [480, 600], "game_width": 92, "preview_scale": 3,
		"bottom_center": [240, 552], "wind_strength": 0.15,
		"wheel_speed_radians_per_second": 2.8,
		"smoke_cycle_seconds": 4.0,
		"seamless_loop": false,
		"new_generated_artwork": false, "paid_generation_calls": 0,
		"rgba_frames": "frames/frame-%03d.png", "opaque_frames": "preview/frame-%03d.png",
	}
	var file := FileAccess.open(OUTPUT + "capture.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest, "\t"))
	file.close()
	viewport.queue_free()
	await process_frame
	print("ENGINE ROOM SPRITE: 80 RGBA frames, 80 baseline frames, 80 opaque preview frames")
	quit(0)
