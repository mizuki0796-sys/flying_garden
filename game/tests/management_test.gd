extends SceneTree

const Rules = preload("res://scripts/development_rules.gd")
const Tiles = preload("res://scripts/island_tiles.gd")
const Weather = preload("res://scripts/weather_system.gd")
var checks := 0
var failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition: failures.append(label)

func _tile(cell: Vector2i, kind := "grass", facility := "") -> Dictionary:
	return {"cell": cell, "kind": kind, "facility": facility, "level": 1, "hp": 100.0, "depleted": false}

func _plot(cell: Vector2i) -> Dictionary:
	return {"cell": cell, "state": 0, "progress": 0.0, "crop_type": 0}

func _run() -> void:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.set_physics_process(false)
	game._start_demo()
	game.coins = 100000
	game.rice_stock = 100
	game.development.materials = {"wood": 1000, "stone": 1000, "ore": 1000, "magma": 10}
	_test_energy(game)
	_test_farms(game)
	_test_overlap_crop(game)
	_test_forest(game)
	_test_camera(game)
	_test_tree_hover()
	if DisplayServer.get_name() != "headless": await _capture(game)
	game.queue_free()
	await process_frame
	for failure in failures: push_error(failure)
	print("MANAGEMENT TEST: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _test_energy(game) -> void:
	var dev = game.development
	game.energy = 0.0
	check(dev.fuel_source == "" and not dev.select_fuel("magma"), "Fuel starts unselected and locked technologies cannot be selected")
	dev.tech.bioenergy = 1
	dev.tech.automatic = 1
	dev.tech.mineral_energy = 1
	dev.tech.geothermal = 1
	dev.update(50.0)
	check(game.energy == 0.0 and game.rice_stock == 100, "Unselected sources never replenish energy or spend inventory")
	dev.select_fuel("rice")
	check(not dev.process_fuel(), "Selected fuel still requires a factory")
	check(dev.build(Vector2i(0, -2), "energy"), "Factory can be built after its technology")
	dev.select_fuel("")
	dev.update(24.0)
	check(game.energy == 0.0 and game.rice_stock == 100, "Even a completed factory stays off without a selection")
	dev.select_fuel("rice")
	dev.update(0.1)
	dev.update(12.0)
	check(game.energy == 16.0 and game.rice_stock == 98 and dev.materials.magma == 10, "Factory continuously consumes only the selected source")
	game.energy = game.energy_capacity - 1.0
	dev.update(12.0)
	var rice: int = game.rice_stock
	dev.update(120.0)
	check(game.energy == game.energy_capacity and game.rice_stock == rice, "Full storage stops spending even across many cycles")
	game.energy -= 20.0
	dev.update(12.0)
	check(game.rice_stock == rice - 1, "Selected source resumes when energy falls")
	game.rice_stock = 0
	game.energy = 0
	dev.update(24.0)
	check(game.energy == 0 and dev.materials.magma == 10 and dev.materials.ore == 998, "Exhausted selected fuel never falls back to ore or magma")
	game.rice_stock = 1
	dev.update(12.0)
	check(game.energy == 8.0 and game.rice_stock == 0, "Restocking resumes the selected source")
	game.energy_crop_stock = 2
	dev.select_fuel("tomato")
	dev.update(0.1)
	check(game.energy == 28.0 and game.energy_crop_stock == 1, "Changing selection processes the new crop at its researched rate")
	dev.select_fuel("")
	dev.update(30.0)
	check(game.energy == 28.0 and game.energy_crop_stock == 1, "Clearing selection immediately disables replenishment")
	dev.select_fuel("ore")
	dev.tile_at(Vector2i(0, -2)).facility = ""
	dev.update(20.0)
	check(game.energy == 28.0, "Removing the factory stops processing")
	game.fuel_button.pressed.emit()
	check(dev.energy_open and dev.modal.visible, "HUD opens the source selector even without a working factory")
	dev.close_menu()
	dev.select_fuel("")

func _test_farms(game) -> void:
	var dev = game.development
	check(not Rules.TECH.has("agriculture"), "Scale farming is removed from the technology tree")
	game.island_tiles = [_tile(Vector2i.ZERO), _tile(Vector2i(0, 1)), _tile(Vector2i(3, 1))]
	game.plots = []
	for cell in [Vector2i(1, 0), Vector2i(2, 0), Vector2i(2, 1), Vector2i(4, 0)]:
		game.island_tiles.append(_tile(cell, "farm"))
		game.plots.append(_plot(cell))
	dev.sync()
	check(not dev.build(Vector2i.ZERO, "farm_hut"), "Management hut requires technology")
	check(dev.research("agri_automation"), "Farm automation research is reachable without scale farming")
	game.rice_seeds = 10
	game.tomato_seeds = 0
	check(dev.manage_farms() == 0, "Research alone cannot automate fields")
	check(dev.build(Vector2i.ZERO, "farm_hut"), "Hut is constructed on land")
	dev.update(Rules.FARM_CYCLE_SECONDS)
	check(game.plots[0].state == 1 and game.plots[1].state == 1 and game.plots[2].state == 0 and game.plots[3].state == 0, "Timer plants within a Euclidean radius of two tiles")
	check(not dev.upgrade(Vector2i.ZERO), "Hut upgrades require higher management research")
	check(dev.research("agri_automation") and dev.upgrade(Vector2i.ZERO), "Research II permits hut level two")
	check(dev.farm_radius(dev.tile_at(Vector2i.ZERO)) == 3 and dev.manage_farms() == 1, "Hut upgrade expands coverage to three tiles")
	check(dev.build(Vector2i(0, 1), "farm_hut"), "Multiple huts can cover separate areas")
	for i in range(3): game.plots[i].state = 2
	var harvested: int = game.harvested
	var rice: int = game.rice_stock
	dev.manage_farms()
	check(game.harvested == harvested + 3 and game.rice_stock == rice + 3, "Overlapping huts harvest each field exactly once")
	check(game.rice_seeds == 7, "Automatic harvest and replant balance matching seeds")
	dev.tile_at(Vector2i.ZERO).farm_enabled = false
	dev.tile_at(Vector2i(0, 1)).farm_enabled = false
	game.plots[0].state = 2
	check(dev.manage_farms() == 0, "Paused huts cannot harvest")
	dev.tile_at(Vector2i.ZERO).farm_enabled = true
	dev.tile_at(Vector2i.ZERO).hp = 90.0
	check(dev.manage_farms() == 0, "Damaged huts stop until repaired")
	dev.tile_at(Vector2i.ZERO).hp = 100.0
	dev.tile_at(Vector2i(1, 0)).hp = 90.0
	check(dev.manage_farms() == 0, "Managers do not repair or work damaged farmland")
	dev.tile_at(Vector2i(1, 0)).hp = 100.0
	dev.tile_at(Vector2i.ZERO).farm_crop = 1
	dev.manage_farms()
	check(game.plots[0].state == 0 and game.rice_seeds == 8, "Missing tomato seeds cannot be replaced by rice seeds")
	game.tomato_seeds = 1
	dev.manage_farms()
	check(game.plots[0].crop_type == 1 and game.tomato_seeds == 0, "Restocking the chosen seed allows automatic planting")
	check(dev.research("agri_automation") and dev.upgrade(Vector2i.ZERO) and dev.farm_radius(dev.tile_at(Vector2i.ZERO)) == 4, "Final hut upgrade expands coverage to four tiles")
	check(not dev.upgrade(Vector2i.ZERO), "Hut level is capped at three")
	check(dev.tile_menu.open_at(Vector2i.ZERO), "Hut context menu opens")
	check(dev.tile_menu.activate("farm_crop") and dev.tile_at(Vector2i.ZERO).farm_crop == 0, "Hut UI changes its own crop")
	check(dev.tile_menu.activate("farm_toggle") and not dev.tile_at(Vector2i.ZERO).farm_enabled, "Hut UI can pause management")
	dev.tile_menu.close()
	check(dev.relocate(Vector2i.ZERO, Vector2i(3, 1)), "Management hut can relocate")
	check(dev.tile_at(Vector2i(3, 1)).level == 3 and not dev.tile_at(Vector2i(3, 1)).farm_enabled, "Relocation preserves hut level and management settings")
	dev.tile_at(Vector2i(3, 1)).farm_enabled = true
	check(dev.farm_manager(Vector2i(4, 0)).cell == Vector2i(3, 1), "Management radius follows the hut after relocation")

func _test_overlap_crop(game) -> void:
	var dev = game.development
	var left := _tile(Vector2i(-1, 0), "grass", "farm_hut")
	var right := _tile(Vector2i(1, 0), "grass", "farm_hut")
	left.farm_crop = game.CROP_TOMATO
	right.farm_crop = game.CROP_TOMATO
	game.island_tiles = [left, right, _tile(Vector2i.ZERO, "farm"), _tile(Vector2i(3, 0), "farm")]
	game.plots = [_plot(Vector2i.ZERO), _plot(Vector2i(3, 0))]
	dev.sync()
	game.rice_seeds = 5
	game.tomato_seeds = 8
	dev.manage_farms()
	check(game.plots[0].crop_type == game.CROP_RICE and game.plots[1].crop_type == game.CROP_TOMATO, "Even two tomato huts sow rice in overlaps; singly covered land keeps tomato")
	check(game.rice_seeds == 4 and game.tomato_seeds == 7, "Overlap sowing consumes one rice seed and never double-spends")
	game.plots[0].crop_type = game.CROP_TOMATO
	game.plots[0].progress = 0.5
	dev.manage_farms()
	check(game.plots[0].crop_type == game.CROP_TOMATO and game.plots[0].progress == 0.5, "Existing growing tomatoes are preserved in overlapping coverage")
	game.plots[0].state = 2
	game.plots[0].progress = 1.0
	var harvested: int = game.harvested
	var tomatoes: int = game.energy_crop_stock
	dev.manage_farms()
	check(game.harvested == harvested + 1 and game.energy_crop_stock == tomatoes + 1 and game.plots[0].crop_type == game.CROP_RICE, "Overlap harvests the actual crop once, then replants rice")
	game.plots[0].state = 0
	game.rice_seeds = 0
	var tomato_seeds: int = game.tomato_seeds
	dev.manage_farms()
	check(game.plots[0].state == 0 and game.tomato_seeds == tomato_seeds, "Missing rice seeds pauses overlap planting rather than burning tomato seeds")
	left.farm_enabled = false
	dev.manage_farms()
	check(game.plots[0].crop_type == game.CROP_TOMATO and game.plots[0].state == 1, "Paused huts do not force rice overlap priority")
	game.plots[0].state = 0
	left.farm_enabled = true
	left.hp = 90.0
	dev.manage_farms()
	check(game.plots[0].crop_type == game.CROP_TOMATO and game.plots[0].state == 1, "Damaged huts do not force rice overlap priority")
	left.hp = 100.0
	game.plots[0].state = 0
	game.rice_seeds = 1
	dev.manage_farms()
	check(game.plots[0].crop_type == game.CROP_RICE and game.rice_seeds == 0, "Repair and rice restocking restore overlapping rice sowing")

func _test_forest(game) -> void:
	var dev = game.development
	game.island_tiles = [_tile(Vector2i.ZERO, "farm"), _tile(Vector2i(2, 0), "tree"), _tile(Vector2i(-2, 0), "tree")]
	game.plots = [_plot(Vector2i.ZERO)]
	dev.sync()
	check(is_equal_approx(dev.forest_protection(Vector2i.ZERO), 0.15), "Existing forest provides basic protection without research and does not stack")
	check(dev.forest_protection(Vector2i(0, 3)) == 0.0, "Forests cannot protect distant farmland")
	check(not dev.research("shelter") and dev.research("forestry"), "Protection upgrades require forestry research")
	for level in range(3): check(dev.research("shelter"), "Protection research level %d is reachable" % (level + 1))
	dev.tech.forecast = 3
	check(is_equal_approx(dev.forest_protection(Vector2i.ZERO), 0.60), "Full forest technology has a sixty percent cap")
	check(is_equal_approx(dev.weather_damage_factor(Vector2i.ZERO), 0.20), "Stacking forecasts still leaves at least twenty percent hazard damage")
	game.zones = [Weather.region("test", "cyclone", game.island_pos, 1000, Vector2.ZERO, 90)]
	game.current_weather = 0
	game.plots[0].state = 2
	game.plots[0].progress = 1.0
	game.weather_hazard_left = 0.0
	game._update_weather_hazards(0.1)
	check(dev.tile_at(Vector2i.ZERO).hp < 100 and game.plots[0].progress < 1.0 and game.plots[0].state == 1, "Protected fields still take damage and lose mature crop progress")
	var protected_hp: float = dev.tile_at(Vector2i.ZERO).hp
	game.island_tiles[1].hp = 0.0
	game.island_tiles[2].hp = 0.0
	check(dev.forest_protection(Vector2i.ZERO) == 0.0, "Destroyed trees provide no protection")
	dev.tile_at(Vector2i.ZERO).hp = 100.0
	game.weather_hazard_left = 0.0
	game._update_weather_hazards(0.1)
	check(dev.tile_at(Vector2i.ZERO).hp < protected_hp, "Unprotected farmland takes more damage")
	game.zones[0].kind = "snow"
	game.weather_hazard_left = 0.0
	game._update_weather_hazards(0.1)
	var uncovered: float = game._plot_weather_penalty(game.plots[0])
	game.island_tiles[1].hp = 100.0
	check(game._plot_weather_penalty(game.plots[0]) > uncovered and game._plot_weather_penalty(game.plots[0]) < 1.0, "Forest reduces snow penalty without eliminating it")
	game.current_weather = -1
	game._update_weather_hazards(0.1)
	check(game.plots[0].weather_kind == "" and game.plots[0].weather_penalty == 1.0, "Leaving extreme weather clears temporary snow coverage")

func _test_camera(game) -> void:
	game.island_tiles = []
	game.plots = []
	for x in range(50): game.island_tiles.append(_tile(Vector2i(x, 0)))
	game.development.sync()
	game._set_view_mode(game.VIEW_GOD)
	game._adjust_zoom(-10.0)
	game.island_velocity = Vector2(10000, -10000)
	game._update_camera(1.0)
	var bounds: Rect2 = game._island_visual_bounds()
	var safe := Rect2(155, 99, 970, 450)
	check(safe.has_point(game._world_to_screen(game.island_pos + bounds.position)) and safe.has_point(game._world_to_screen(game.island_pos + bounds.end)), "Default player view includes every edge of an asymmetrically expanded island even during flight")
	check(game.camera_zoom_target < game.movement_settings.god_zoom_min, "A large island can zoom out below the old fixed limit")
	var fit: float = game.camera_zoom_target
	game._adjust_zoom(10.0)
	check(game.camera_zoom_target > fit, "Player view can zoom in from the full-island baseline")
	game._adjust_zoom(-10.0)
	check(is_equal_approx(game.camera_zoom_target, fit), "Player view cannot zoom out beyond the full-island baseline")
	game._set_view_mode(game.VIEW_FOCUS)
	game.focus_offset = Vector2(100000, -100000)
	game._update_camera(0.1)
	check(game.development.cell_at(game.camera_world) == Vector2i(49, 0), "Micro view cannot pan beyond the player's actual island tiles")
	game.focus_offset = Vector2(-100000, 100000)
	game._update_camera(0.1)
	check(game.development.cell_at(game.camera_world) == Vector2i.ZERO, "Micro view can inspect the other end of the full island")
	game.development.tech.radar = 0
	check(not game._radar_visible(game.island_pos + Vector2(900, 0)), "World visibility excludes objects outside radar range")
	game.development.tech.radar = 1
	check(game._radar_visible(game.island_pos + Vector2(900, 0)), "Radar upgrades reveal the previously hidden position")
	game.island_velocity = Vector2.ZERO

func _test_tree_hover() -> void:
	var rect := Rect2(100, 100, 100, 110)
	check(Tiles.tree_hover_alpha(rect, 210, -35, Vector2(120, 120)) < 0.3, "Hovered canopy becomes translucent")
	check(Tiles.tree_hover_alpha(rect, 210, -35, Vector2(500, 500)) == 1.0, "Moving away restores opaque trees")
	check(Tiles.tree_hover_alpha(rect, 210, -35, Vector2(80, 105)) < 0.3, "Hover detection follows wind-bent canopy")

func _capture(game) -> void:
	var dev = game.development
	game.island_tiles = Tiles.initial_tiles()
	game.plots = []
	for y in range(-1, 2):
		for x in range(-1, 2): game.plots.append(_plot(Vector2i(x, y)))
	game.current_weather = -1
	game.zones = []
	game.targets = []
	game.hazards = []
	game.camera_zoom = 1.3
	game.camera_zoom_target = 1.3
	game.focus_offset = Vector2.ZERO
	dev.sync()
	game.notice_label.text = ""
	dev.build(Vector2i(0, -2), "farm_hut")
	dev.build(Vector2i(1, -2), "energy")
	dev.manage_farms()
	game.merchant_available = true
	game.merchant_stay_left = 75
	await _save(game, "management-island.png")
	dev.toggle(false)
	dev.toggle_energy()
	await _save(game, "energy-source-picker.png")
	check(Rect2(Vector2.ZERO, game.VIEW_SIZE).encloses(dev.modal.get_global_rect()), "Source selector fits the viewport after opening from development")
	for child in dev.content.get_children():
		if child is Button:
			check(dev.modal.get_global_rect().encloses(child.get_global_rect()) and child.get_global_rect().end.y <= dev.modal.get_global_rect().end.y - 14, "Fuel selection button fits the visible modal content")
	dev.close_menu()
	dev.tile_menu.open_at(Vector2i(0, -2))
	await _save(game, "farm-management-hut.png")
	check(Rect2(Vector2.ZERO, game.VIEW_SIZE).encloses(dev.tile_menu.panel.get_global_rect()), "Hut settings fit the viewport")
	dev.tile_menu.close()
	dev.toggle(true)
	await _save(game, "management-technology.png")
	check(not dev.modal.get_global_rect().intersects(dev.market_ui.badge.get_global_rect()), "Merchant prompt does not obscure the technology panel")
	check(Rect2(Vector2.ZERO, game.VIEW_SIZE).encloses(dev.market_ui.badge.get_global_rect()), "Compact merchant prompt fits the viewport")
	dev.close_menu()
	game._set_view_mode(game.VIEW_GOD)
	game._adjust_zoom(10.0)
	game._update_camera(1.0)
	await _save(game, "management-god-view.png")
	await _test_tree_render(game)
	game.sky_map_open = true
	dev.tech.radar = 0
	await _save(game, "radar-fog.png")

class TreeProbe extends Node2D:
	var texture: Texture2D
	var pointer := Vector2.INF
	func _draw() -> void:
		draw_rect(Rect2(0, 0, 260, 210), Color("#9dc2a2"))
		draw_rect(Rect2(80, 70, 100, 80), Color("#9a6439"))
		Tiles.draw_decor(self, Vector2(130, 180), [{"cell": Vector2i.ZERO, "kind": "tree", "facility": ""}], Tiles.CELL_SIZE, false, texture, true, 0, 0, pointer)

func _test_tree_render(game) -> void:
	# An offscreen viewport provides deterministic pointer positions, independent
	# of the desktop's real cursor and whether the test window has focus.
	var viewport := SubViewport.new()
	viewport.size = Vector2i(260, 210)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var probe := TreeProbe.new()
	probe.texture = game.tree_texture
	viewport.add_child(probe)
	await process_frame
	await RenderingServer.frame_post_draw
	var opaque := viewport.get_texture().get_image()
	probe.pointer = Vector2(130, 115)
	probe.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	var faded := viewport.get_texture().get_image()
	var changed := 0
	for y in range(95, 135):
		for x in range(110, 150):
			if opaque.get_pixel(x, y) != faded.get_pixel(x, y): changed += 1
	check(changed > 100, "Hovering a rendered tree reveals the field behind its canopy")
	faded.save_png(ProjectSettings.globalize_path("res://../artifacts/game/management-tree-hover.png"))
	opaque.save_png(ProjectSettings.globalize_path("res://../artifacts/game/management-tree-opaque.png"))
	probe.pointer = Vector2.INF
	probe.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	check(viewport.get_texture().get_image().get_data() == opaque.get_data(), "Moving off the tree restores its original rendering")
	viewport.queue_free()

func _save(game, name_value: String) -> void:
	game._update_hud()
	game.queue_redraw()
	for frame in range(3): await process_frame
	await RenderingServer.frame_post_draw
	var path := ProjectSettings.globalize_path("res://../artifacts/game/" + name_value)
	check(root.get_texture().get_image().save_png(path) == OK, "Preview saved: " + name_value)
