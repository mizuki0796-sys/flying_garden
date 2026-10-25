extends SceneTree

const Tiles = preload("res://scripts/island_tiles.gd")
const Rules = preload("res://scripts/development_rules.gd")
const Weather = preload("res://scripts/weather_system.gd")
var failures: Array[String] = []
var checks := 0

func _init() -> void:
	call_deferred("_run")

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition: failures.append(description)

func _run() -> void:
	var game := (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.set_physics_process(false)
	game._start_demo()
	var dev = game.development
	game.coins = 5000
	game.rice_stock = 100
	dev.materials = {"wood": 200, "stone": 200, "ore": 200, "magma": 5}
	_check_seed_inventory(game)
	# Exercise actual single-field rewards after removing scale farming.
	var incomes: Array[int] = []
	for crop in [game.CROP_RICE, game.CROP_TOMATO]:
		game.plots[0].crop_type = crop
		game.plots[0].state = 2
		game.plots[0].progress = 1.0
		var before: int = game.coins
		game._interact_with_plot(game._plot_rect(0).get_center())
		incomes.append(game.coins - before)
	check(incomes == [2, 4], "Single-field rice and tomato harvests pay the fixed rewards")
	game.energy_crop_stock += 3
	check(not dev.open_trade("流浪商人"), "Absent merchant cannot open a sale session")
	game.merchant_available = true
	check(dev.open_trade("流浪商人"), "Arriving merchant opens crop trade")
	var rice_before: int = game.rice_seeds
	var tomato_before: int = game.tomato_seeds
	dev.trade_buy(4, {"rice_seeds": 2}, "水稻种子")
	check(game.rice_seeds == rice_before + 2 and game.tomato_seeds == tomato_before, "Buying rice seeds does not add tomato seeds")
	dev.trade_buy(8, {"tomato_seeds": 2}, "番茄种子")
	check(game.rice_seeds == rice_before + 2 and game.tomato_seeds == tomato_before + 2, "Buying tomato seeds does not add rice seeds")
	for crop in [game.CROP_RICE, game.CROP_TOMATO]:
		var before: int = game.coins
		var inventory: int = game.rice_stock if crop == game.CROP_RICE else game.energy_crop_stock
		check(dev.trade_sell_crop(crop, 3), "Stocked crops can be sold")
		var after: int = game.rice_stock if crop == game.CROP_RICE else game.energy_crop_stock
		check(inventory - after == 3 and game.coins - before == 3 * Rules.CROP_SELL_COINS[crop], "Crop sales consume exactly the sold inventory and pay the discounted price")
		check(not dev.trade_sell_crop(crop, inventory + 1), "Insufficient stock cannot be sold")
	game.merchant_available = false
	var before: int = game.coins
	check(not dev.trade_sell_crop(game.CROP_RICE) and game.coins == before, "Departed merchant cannot pay through a stale callback")
	dev.trade_open = false
	dev.modal.hide()
	var farm := Vector2i(-1, -1)
	var land := Vector2i(0, -2)
	dev.tile_at(farm).hp = 10.0
	dev.tile_at(land).hp = 10.0
	check(dev.repair_cost(land).coins >= dev.repair_cost(farm).coins * 25, "Land repair is far more expensive than field maintenance")
	check(not dev.build(land, "farm"), "Opening a cheap field cannot bypass damaged-land repair")
	check(dev.repair_cost(Vector2i(999, 999)).is_empty(), "Missing land has no repair quote")
	for kind in Rules.FACILITY_NAMES:
		dev.tile_at(land).facility = kind
		for hp in [0.0, 40.0, 99.0]:
			dev.tile_at(land).hp = hp
			var quote: Dictionary = dev.repair_cost(land)
			for key in quote:
				check(quote[key] <= Rules.BUILD_COSTS[kind][key], "House repair never costs more than construction")
			check(quote.coins >= ceili(Rules.BUILD_COSTS[kind].coins * 0.35), "House repair retains a significant minimum cost")
	dev.tile_at(land).facility = ""
	dev.tile_at(land).hp = 100.0
	var farm_index: int = dev.plot_at(farm)
	game.plots[farm_index].state = 1
	before = game.coins
	check(not dev.restore_farmland(farm) and game.coins == before, "Field restoration protects unharvested crops without charging")
	game.plots[farm_index].state = 0
	var count: int = game.plots.size()
	check(dev.restore_farmland(farm), "Damaged empty farmland can be restored cheaply")
	check(game.coins == before - 2 and dev.tile_at(farm).kind == "grass" and dev.tile_at(farm).hp == 100.0, "Restoration charges two coins and restores normal land")
	check(game.plots.size() == count - 1 and dev.plot_at(farm) == -1 and game.selected_plot == -1, "Restored field removes its crop slot and stale selection")
	check(dev.build(farm, "farm") and game.plots.size() == count, "Restored land can be tilled again")
	_check_collisions(game)
	# Simulate rollover through the actual game tick.
	game.hazards = []
	game.island_velocity = Vector2.ZERO
	game.day_minutes = 1439.0
	game.day_number = 1
	game._physics_process(0.3)
	check(game.day_number == 2 and game.day_minutes < 1.0, "Day counter advances at midnight")
	if DisplayServer.get_name() != "headless": await _capture(game)
	game.queue_free()
	await process_frame
	for failure in failures: push_error(failure)
	print("REVISION TEST: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _tile(cell: Vector2i) -> Dictionary:
	return {"cell": cell, "kind": "grass", "facility": "", "hp": 100.0}

func _check_seed_inventory(game: Node2D) -> void:
	var dev = game.development
	game.rice_seeds = 0
	game.tomato_seeds = 5
	dev.selected_crop = game.CROP_RICE
	game._interact_with_plot(game._plot_rect(0).get_center())
	check(game.plots[0].state == 0 and game.tomato_seeds == 5, "Tomato seeds cannot substitute for missing rice seeds")
	game.rice_seeds = 2
	game._interact_with_plot(game._plot_rect(0).get_center())
	check(game.plots[0].state == 1 and game.rice_seeds == 1 and game.tomato_seeds == 5, "Rice planting debits the rice inventory alone")
	game.tomato_seeds = 0
	dev.selected_crop = game.CROP_TOMATO
	game._interact_with_plot(game._plot_rect(1).get_center())
	check(game.plots[1].state == 0 and game.rice_seeds == 1, "Rice seeds cannot substitute for missing tomato seeds")
	game.tomato_seeds = 2
	game._interact_with_plot(game._plot_rect(1).get_center())
	check(game.plots[1].state == 1 and game.rice_seeds == 1 and game.tomato_seeds == 1, "Tomato planting debits the tomato inventory alone")
	game.plots[0].state = 2
	game._interact_with_plot(game._plot_rect(0).get_center())
	check(game.rice_seeds == 2 and game.tomato_seeds == 1, "Harvesting rice returns rice seeds even with the tomato tool selected")
	dev.selected_crop = game.CROP_RICE
	game.plots[1].state = 2
	game._interact_with_plot(game._plot_rect(1).get_center())
	check(game.rice_seeds == 2 and game.tomato_seeds == 2, "Harvesting tomatoes returns tomato seeds even with the rice tool selected")
	dev.tech.agri_automation = 1
	dev.selected_crop = game.CROP_TOMATO
	game.rice_seeds = 10
	game.tomato_seeds = 2
	check(dev.build(Vector2i(0, -2), "farm_hut"), "Tomato manager is constructed with the selected crop")
	check(dev.manage_farms() == 2 and game.tomato_seeds == 0 and game.rice_seeds == 10, "Local tomato planting respects only tomato seed availability")
	for plot in game.plots:
		if int(plot.state) == 1: plot.state = 2
	var stock_before: int = game.energy_crop_stock
	check(dev.manage_farms() == 4 and game.energy_crop_stock == stock_before + 2 and game.tomato_seeds == 0 and game.rice_seeds == 10, "Local harvest returns matching seeds then replants without using rice seeds")
	dev.tile_at(Vector2i(0, -2)).facility = ""
	dev.tech.agri_automation = 0
	dev.selected_crop = game.CROP_RICE
	game.selected_plot = -1
	game.hovered_plot = -1

func _check_collisions(game: Node2D) -> void:
	var original: Array = game.island_tiles.duplicate(true)
	var plots: Array = game.plots.duplicate(true)
	var position: Vector2 = game.island_pos
	var neighbor := {"pos": position + Vector2(246, 0), "tiles": [_tile(Vector2i.ZERO)], "active": true, "tethered": false, "radius": 120.0}
	game.hazards = [neighbor]
	game.island_velocity = Vector2(80, 0)
	game.collision_cooldown = 0.0
	var energy_before: float = game.energy
	check(is_equal_approx(game._hazard_clearance(neighbor), 6.0), "Clearance uses real edges, ignoring the old oversized radius")
	game._check_collisions()
	check(game.island_tiles.size() == original.size() and game.energy == energy_before, "Visibly separated islands cannot cause damage or energy loss")
	neighbor.pos.x = position.x + 240.0
	game._check_collisions()
	check(game.island_tiles.size() == original.size(), "Touching edges alone do not destroy tiles")
	neighbor.pos.x = position.x + 239.0
	game._check_collisions()
	check(game.island_tiles.size() == original.size() - 1 and game.development.tile_at(Vector2i(2, 0)).is_empty(), "Real overlap damages the contacted edge tile")
	game.island_tiles = original.duplicate(true)
	game.plots = plots.duplicate(true)
	game.island_pos = position
	game._refresh_island_shape()
	neighbor.pos = position + Vector2(239, 0)
	game.island_velocity = Vector2(10, 0)
	game.collision_cooldown = 0.0
	game._check_collisions()
	check(game.island_tiles.size() == original.size() and game._hazard_clearance(neighbor) >= 0.0, "Slow contact separates islands without destruction")
	game.island_pos = position
	neighbor.pos = position + Vector2(239, 0)
	game.island_velocity = Vector2(0, 90)
	game._check_collisions()
	check(game.island_tiles.size() == original.size(), "Tangential motion does not count as a high-speed impact")
	var concave := [_tile(Vector2i(-1, 0)), _tile(Vector2i(-1, 1)), _tile(Vector2i(0, 1)), _tile(Vector2i(1, 1)), _tile(Vector2i(1, 0))]
	check(Tiles.contact(concave, Vector2.ZERO, [_tile(Vector2i.ZERO)], Vector2.ZERO).is_empty(), "Empty space inside a concave outline is not solid")
	check(Tiles.contact([_tile(Vector2i.ZERO)], Vector2.ZERO, [_tile(Vector2i.ZERO)], Vector2(81, 63)).is_empty(), "Near diagonal corners do not create a circular false positive")
	# Non-centered wild shapes must use exactly the rendering origin.
	neighbor.tiles = [_tile(Vector2i(4, 3)), _tile(Vector2i(5, 3)), _tile(Vector2i(4, 4))]
	neighbor.pos = position + Vector2(300, 0)
	game.island_pos = position
	check(is_equal_approx(game._hazard_clearance(neighbor), 20.0), "Asymmetric island bounds are centered consistently with rendering")
	game.island_tiles = original
	game.plots = plots
	game.island_pos = position
	game._refresh_island_shape()

func _capture(game: Node2D) -> void:
	game.island_tiles = Tiles.initial_tiles()
	game.plots = []
	for y in range(-1, 2):
		for x in range(-1, 2):
			game.plots.append({"cell": Vector2i(x, y), "state": 2, "progress": 1.0, "crop_type": posmod(x + y, 2), "weather_penalty": 1.0})
	game.development.sync()
	game.camera_zoom = 1.0
	game.camera_world = game.island_pos + Vector2(0, -30)
	game.targets = []
	game.hazards = []
	game.current_weather = -1
	game.zones = []
	game.weather_tint = 0.0
	game.coins = 78
	game.day_number = 1
	game.day_minutes = 629.0
	game.rice_stock = 12
	game.energy_crop_stock = 8
	game.development.materials = {"wood": 12, "stone": 8, "ore": 6, "magma": 2}
	game.development.tech.forecast = 0
	game.selected_tool = game.TOOL_HOOK
	game.selected_plot = -1
	game.hovered_plot = -1
	game.context_panel.hide()
	game.notice_label.text = ""
	game.wind_strength = 0.12
	game.animation_time = 2.0
	await _save_frame(game, "hud-revision-preview.png")
	for frame in range(2):
		game.zones = [Weather.region("preview:cyclone", "cyclone", game.island_pos, Weather.RAIN_RADIUS, Vector2(-0.4, 0.1), 90.0)]
		game.current_weather = 0
		game.weather_tint = -0.28
		game.wind_strength = 1.6
		game.animation_time = 2.0 + frame * 0.55
		await _save_frame(game, "cyclone-animation-%d.png" % frame)

func _save_frame(game: Node2D, filename: String) -> void:
	game._update_hud()
	game.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	var path := ProjectSettings.globalize_path("res://../artifacts/game/" + filename)
	check(root.get_texture().get_image().save_png(path) == OK, "Visual preview saved: " + filename)
