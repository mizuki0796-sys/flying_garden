extends SceneTree

const OUT := "res://../artifacts/game/thick-wall-impact/"
const FPS := 20

func _init() -> void:
	call_deferred("run")

func run() -> void:
	if DisplayServer.get_name() == "headless": quit(1); return
	root.size = Vector2i(1152, 648)
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.set_physics_process(false)
	game._start_demo()
	# This recorder documents the straight-wall prototype retained for old saves.
	game.wall = preload("res://scripts/thick_wall.gd").new(game)
	game.active_sector = Vector2i(2147483647,2147483647)
	game._update_world_stream()
	# Prepare propulsion for the recording without touching a player save.
	game.coins = 500
	game.development.materials = {"wood": 40, "stone": 30, "ore": 15, "magma": 0}
	assert(game.development.research("engine"))
	assert(game.development.build(Vector2i(1, 2), "power"))
	game.development.close_menu()
	game._show_notice("试玩演示：已建好动力室，向北加速撞墙。", 8.0)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT + "frames"))
	var impact_frame := -1
	var frame_count := 0
	Input.action_press("move_up")
	for frame in range(FPS * 16):
		game._physics_process(1.0 / FPS)
		game._process(1.0 / FPS)
		if impact_frame < 0 and game.wall.depth > 0.0:
			impact_frame = frame
			Input.action_release("move_up")
		game.queue_redraw()
		await process_frame
		await RenderingServer.frame_post_draw
		var picture := root.get_texture().get_image()
		assert(picture.save_png(OUT + "frames/frame-%03d.png" % frame) == OK)
		if frame == impact_frame: assert(picture.save_png(OUT + "impact.png") == OK)
		frame_count += 1
		if impact_frame >= 0 and frame >= impact_frame + FPS * 3: break
	Input.action_release("move_up")
	assert(impact_frame >= 0, "Actual movement must hit the wall")
	assert(game.island_tiles.any(func(tile): return float(tile.hp) < 100.0), "Collision must damage a leading tile")
	var report := {"fps": FPS, "frames": frame_count, "impact_frame": impact_frame, "depth": game.wall.depth, "energy": game.energy}
	var file := FileAccess.open(OUT + "capture.json", FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify(report, "\t"))
	print("WALL_PREVIEW ", JSON.stringify(report))
	quit()
