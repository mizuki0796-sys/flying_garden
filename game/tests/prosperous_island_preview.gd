extends SceneTree

# A presentation fixture only: 100 occupied cells rendered by the actual game.
func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	root.size = Vector2i(1920, 1080)
	root.content_scale_size = Vector2i(1152, 648)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.set_physics_process(false)
	game._start_demo()
	game.island_tiles = []
	game.plots = []
	game.hazards = []
	game.targets = []
	game.zones = []
	game.current_weather = -1
	game.weather_tint = 0.0
	game.wind_strength = 0.14
	game.animation_time = 6.4
	game.selected_tool = game.TOOL_HOOK
	game.selected_plot = -1
	game.hovered_plot = -1
	game.day_number = 48
	game.day_minutes = 9 * 60 + 30
	game.coins = 8650
	game.rice_stock = 640
	game.energy_crop_stock = 380
	game.rice_seeds = 180
	game.tomato_seeds = 120
	game.development.materials = {"wood": 820, "stone": 460, "ore": 210, "magma": 36}
	for key in game.development.tech:
		game.development.tech[key] = int(game.development.Rules.TECH[key].max)
	game.development.fuel_source = "tomato"
	# Sheltered farm blocks surround a central service lane. Sand is existing
	# terrain used as a visual path, not a new road mechanic.
	var buildings := {
		Vector2i(2, 1): "water", Vector2i(4, 1): "water",
		Vector2i(7, 1): "energy", Vector2i(9, 1): "water",
		Vector2i(5, 3): "farm_hut", Vector2i(6, 5): "farm_hut",
		Vector2i(5, 7): "farm_hut", Vector2i(11, 4): "grapple",
		Vector2i(3, 8): "power", Vector2i(5, 8): "power", Vector2i(8, 8): "power",
	}
	var trees := [Vector2i(2, 0), Vector2i(4, 0), Vector2i(7, 0), Vector2i(9, 0),
		Vector2i(0, 1), Vector2i(11, 1), Vector2i(0, 3), Vector2i(11, 3),
		Vector2i(0, 6), Vector2i(11, 6), Vector2i(1, 7), Vector2i(10, 7)]
	for y in range(9):
		for x in range(12):
			if y in [0, 8] and (x < 2 or x > 9): continue
			var p := Vector2i(x, y)
			var cell := p - Vector2i(5, 4)
			var kind := "grass"
			var facility: String = buildings.get(p, "")
			if y == 2 or x in [5, 6]: kind = "sand"
			if y >= 3 and y <= 7 and (x >= 1 and x <= 4 or x >= 7 and x <= 10):
				kind = "farm"
			if p in trees: kind = "tree"
			if not facility.is_empty(): kind = "grass"
			if p == Vector2i(0, 5): kind = "rock"
			if p == Vector2i(11, 5): kind = "gold"
			var tile := {"cell": cell, "kind": kind, "facility": facility, "level": 1, "hp": 100.0, "depleted": false}
			if facility in ["power", "water", "grapple"]: tile.level = 4
			if facility == "farm_hut":
				tile.level = 3
				tile.farm_enabled = true
				tile.farm_crop = 0 if x == 5 else 1
			game.island_tiles.append(tile)
			if kind == "farm":
				var ripe := posmod(x + y * 3, 9) != 0
				game.plots.append({"cell": cell, "state": 2 if ripe else 1, "progress": 1.0 if ripe else 0.68, "crop_type": 0 if x <= 4 else 1, "weather_penalty": 1.0})
	if game.island_tiles.size() != 100:
		push_error("Preview must contain exactly 100 tiles")
		quit(1)
		return
	game.development.sync()
	game.energy = game.energy_capacity
	game._update_hud()
	game.context_panel.hide()
	game.notice_label.text = ""
	game.camera_zoom = game._god_zoom_limit()
	game.camera_zoom_target = game.camera_zoom
	game.camera_world = game.island_pos + game._island_visual_bounds().get_center()
	await _capture(game, "prosperous-100-island-gameplay.png")
	game.get_node("HUD").hide()
	game.camera_zoom = 0.78
	game.camera_world = game.island_pos + game._island_visual_bounds().get_center() + Vector2(0, 14)
	await _capture(game, "prosperous-100-island.png")
	print("PROSPEROUS PREVIEW: %d tiles, %d farms, %d buildings, %d trees" % [game.island_tiles.size(), game.plots.size(), buildings.size(), trees.size()])
	quit(0)

func _capture(game, filename: String) -> void:
	game.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	var path := ProjectSettings.globalize_path("res://../artifacts/game/" + filename)
	var error := root.get_texture().get_image().save_png(path)
	if error != OK:
		push_error("Screenshot failed: %s" % error)
		quit(1)
	print("Saved " + path)
