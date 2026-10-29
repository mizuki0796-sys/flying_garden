extends SceneTree

const Tiles = preload("res://scripts/island_tiles.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var count := 1000
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--tiles="):
			count = maxi(1, int(argument.trim_prefix("--tiles=")))
	var scene: PackedScene = load("res://main.tscn")
	var game := scene.instantiate()
	root.add_child(game)
	await process_frame
	game.set_physics_process(false)
	game.set_process(false)
	game.demo_started = true
	game.get_node("HUD").hide()
	game.hazards = []
	game.targets = []
	game.zones = []
	game.plots = []
	game.current_weather = -1
	game.selected_plot = -1
	game.hovered_plot = -1
	game.island_tiles = _make_tiles(count)
	game._refresh_island_shape()
	game.camera_world = game.island_pos + game.island_bounds.get_center()
	game.camera_zoom = game._god_zoom_limit()
	game.camera_zoom_target = game.camera_zoom
	var started := Time.get_ticks_usec()
	game.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	var first_frame_ms := float(Time.get_ticks_usec() - started) / 1000.0
	var path := ProjectSettings.globalize_path("res://../artifacts/game/large-map-%d-actual-render.png" % count)
	var error := root.get_texture().get_image().save_png(path)
	if error != OK:
		push_error("Actual render image failed: %s" % error)
		quit(1)
		return
	var warm_total_ms := 0.0
	for sample in range(3):
		started = Time.get_ticks_usec()
		game.queue_redraw()
		await process_frame
		await RenderingServer.frame_post_draw
		warm_total_ms += float(Time.get_ticks_usec() - started) / 1000.0
	var warm_average_ms := warm_total_ms / 3.0
	print("ACTUAL LARGE MAP RENDER %d: first %.2f ms, warm average %.2f ms, estimated %.2f FPS, zoom %.5f, %s" % [count, first_frame_ms, warm_average_ms, 1000.0 / warm_average_ms, game.camera_zoom, path])
	quit(0)


func _make_tiles(count: int) -> Array:
	var columns := ceili(sqrt(float(count) * 1.12))
	var rows := ceili(float(count) / columns)
	var tiles: Array = []
	tiles.resize(count)
	for index in range(count):
		var raw := Vector2i(index % columns, index / columns)
		var cell := raw - Vector2i(columns / 2, rows / 2)
		var value := posmod(raw.x * 17 + raw.y * 31, 97)
		var kind := "grass"
		if value < 6: kind = "tree"
		elif value < 10: kind = "rock"
		elif value == 10: kind = "gold"
		elif value == 11: kind = "lava"
		tiles[index] = {"cell": cell, "kind": kind, "facility": "", "level": 1, "hp": 100.0, "depleted": false}
	return tiles
