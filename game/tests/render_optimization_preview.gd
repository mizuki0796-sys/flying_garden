extends SceneTree

const Fixture = preload("res://tests/render_performance_fixture.gd")
const OUT := "res://../artifacts/game/render-optimization/frames/"

func _init() -> void:
	call_deferred("run")

func run() -> void:
	assert(DisplayServer.get_name() != "headless", "Preview needs actual GPU rendering")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	root.size = Vector2i(1152, 648)
	var game := Fixture.new()
	root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	game._start_demo()
	game.get_node("HUD").hide()
	game.isolate_island = true
	game.configure(25)
	game.wind_strength = 1.6
	for frame in range(40):
		game.animation_time = 2.35 + float(frame) / 20.0
		game.queue_redraw()
		await process_frame
		await RenderingServer.frame_post_draw
		assert(root.get_texture().get_image().save_png(OUT + "frame-%03d.png" % frame) == OK)
	var file := FileAccess.open(OUT + "parameters.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"frames": 40, "fps": 20, "start_time": 2.35,
		"wind": 1.6, "tiles": 25, "camera_zoom": game.camera_zoom,
		"camera_world": [game.camera_world.x, game.camera_world.y],
		"resolution": [1152, 648], "seamless_loop": false}, "  "))
	print("RENDER PREVIEW: 40 frames from actual island renderer")
	quit()
