extends SceneTree

const Tiles = preload("res://scripts/island_tiles.gd")
var failures: Array[String] = []
var checks := 0

func _init() -> void:
	call_deferred("_run")

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition: failures.append(label)

func _click(game: Node2D, button: int, cell: Vector2i) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = true
	event.position = game._world_to_screen(game.island_pos + Vector2(cell) * Tiles.CELL_SIZE)
	game._unhandled_input(event)

func _run() -> void:
	var game := (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await process_frame
	game.set_physics_process(false)
	game.set_process(false)
	game._start_demo()
	game.hazards = []
	var dev = game.development
	var menu = dev.tile_menu
	var land := Vector2i(1, -2)
	_click(game, MOUSE_BUTTON_RIGHT, land)
	check(menu.is_open() and menu.cell == land and not dev.modal.visible, "Right-click opens the local tile menu without the engineering modal")
	check(menu.buttons.has("farm") and menu.buttons.has("power") and not menu.buttons.has("upgrade"), "Empty land offers building actions only")
	check(menu.buttons.power.disabled and "动力工程" in menu.buttons.power.text, "Unresearched building shows a disabled choice and its requirement")
	check(menu.buttons.farm.disabled, "Missing food disables tilling")
	var coins_before: int = game.coins
	check(not menu.activate("power") and game.coins == coins_before and dev.tile_at(land).facility == "", "Direct invocation of a locked action cannot bypass research")
	game.rice_stock = 2
	menu.update()
	check(not menu.buttons.farm.disabled, "Availability refreshes when required resources change")
	var plots_before: int = game.plots.size()
	menu.buttons.farm.pressed.emit()
	check(not menu.is_open() and dev.tile_at(land).kind == "farm", "Choosing tilling immediately affects the clicked land")
	check(game.coins == coins_before - 10 and game.rice_stock == 1 and game.plots.size() == plots_before + 1, "Tilling charges once and creates one crop slot")
	_click(game, MOUSE_BUTTON_RIGHT, land)
	check(menu.buttons.has("plant_rice") and menu.buttons.has("plant_tomato") and not menu.buttons.has("power"), "Farm menu offers planting instead of buildings")
	game.rice_seeds = 0
	game.tomato_seeds = 3
	menu.update()
	check(menu.buttons.plant_rice.disabled and not menu.buttons.plant_tomato.disabled, "Seed choices respect independent crop inventory")
	menu.buttons.plant_tomato.pressed.emit()
	var index: int = dev.plot_at(land)
	check(game.plots[index].state == 1 and game.plots[index].crop_type == game.CROP_TOMATO and game.tomato_seeds == 2, "Context planting applies the selected crop to the anchored farm")
	_click(game, MOUSE_BUTTON_RIGHT, land)
	check(menu.buttons.harvest.disabled and menu.buttons.restore.disabled, "Growing crop cannot be harvested or erased by restoration")
	game.plots[index].state = 2
	game.plots[index].progress = 1.0
	menu.update()
	coins_before = game.coins
	menu.buttons.harvest.pressed.emit()
	check(game.plots[index].state == 0 and game.coins == coins_before + 4, "Harvest from the tile menu grants the correct crop reward")
	game.coins = 1000
	game.rice_stock = 20
	dev.materials = {"wood": 100, "stone": 100, "ore": 100, "magma": 5}
	dev.tech.engine = 1
	dev.tech.storage = 1
	var engine := Vector2i(2, 0)
	_click(game, MOUSE_BUTTON_RIGHT, engine)
	check(not menu.buttons.power.disabled, "Unlocked and affordable construction is enabled")
	coins_before = game.coins
	menu.buttons.power.pressed.emit()
	check(dev.tile_at(engine).facility == "power" and game.coins == coins_before - 40, "Building from the menu consumes the advertised resources")
	_click(game, MOUSE_BUTTON_RIGHT, engine)
	check(menu.buttons.keys() == ["upgrade", "repair", "move"], "Facilities expose only upgrade, repair and relocation")
	check(menu.buttons.repair.disabled, "Undamaged facility cannot be repaired")
	var quote: Dictionary = dev.upgrade_cost(engine)
	coins_before = game.coins
	menu.buttons.upgrade.pressed.emit()
	check(dev.tile_at(engine).level == 2 and game.coins == coins_before - quote.coins, "Upgrade price matches the action deduction")
	_click(game, MOUSE_BUTTON_RIGHT, engine)
	check(menu.buttons.upgrade.disabled, "Building level cap is visible before selecting an upgrade")
	dev.tile_at(engine).hp = 50.0
	menu.update()
	quote = dev.repair_cost(engine)
	coins_before = game.coins
	menu.buttons.repair.pressed.emit()
	check(dev.tile_at(engine).hp == 100.0 and game.coins == coins_before - quote.coins, "Facility repair restores the selected building at the quoted price")
	_click(game, MOUSE_BUTTON_RIGHT, engine)
	menu.buttons.move.pressed.emit()
	check(dev.move_from == engine and game.selected_tool == 2 and not menu.is_open(), "Relocation remembers the selected source and asks for a destination")
	var destination := Vector2i(-2, 0)
	_click(game, MOUSE_BUTTON_RIGHT, destination)
	check(dev.move_from == dev.NONE and not menu.is_open() and dev.tile_at(engine).facility == "power", "Right-click cancels active placement without opening another menu")
	_click(game, MOUSE_BUTTON_RIGHT, engine)
	menu.buttons.move.pressed.emit()
	coins_before = game.coins
	_click(game, MOUSE_BUTTON_LEFT, destination)
	check(dev.tile_at(destination).facility == "power" and dev.tile_at(engine).facility == "" and game.coins == coins_before - 5, "Relocation completes on the chosen destination and charges once")
	game._select_tool(game.TOOL_HOOK)
	game.hook_state = game.HOOK_EXTEND
	_click(game, MOUSE_BUTTON_RIGHT, land)
	check(game.hook_state == game.HOOK_RETRACT and not menu.is_open(), "Right-click during grappling retracts the hook first")
	game.hook_state = game.HOOK_READY
	dev.select_action("farm")
	_click(game, MOUSE_BUTTON_RIGHT, engine)
	check(game.selected_tool == game.TOOL_HOOK and not menu.is_open(), "Building placement is cancelled before offering tile actions")
	dev.select_action("gather")
	_click(game, MOUSE_BUTTON_RIGHT, Vector2i(2, -2))
	check(menu.is_open() and menu.buttons.gather.disabled and not menu.buttons.has("farm"), "Resource terrain offers extraction and respects mining research")
	dev.tech.development = 1
	menu.update()
	check(not menu.buttons.gather.disabled, "Mining becomes available after research")
	menu.buttons.gather.pressed.emit()
	check(dev.tile_at(Vector2i(2, -2)).kind == "grass", "Context extraction frees a resource tile")
	game._select_tool(game.TOOL_HOOK)
	_click(game, MOUSE_BUTTON_RIGHT, engine)
	var energy_before: float = game.energy
	_click(game, MOUSE_BUTTON_LEFT, Vector2i(8, 8))
	check(not menu.is_open() and game.hook_state == game.HOOK_READY and game.energy == energy_before, "Outside click closes the menu without firing a tool")
	_click(game, MOUSE_BUTTON_RIGHT, engine)
	var escape := InputEventAction.new()
	escape.action = "ui_cancel"
	escape.pressed = true
	game._unhandled_input(escape)
	check(not menu.is_open(), "Escape dismisses the menu")
	dev.tech.terraform = 1
	var edge := Vector2i(2, -2)
	_click(game, MOUSE_BUTTON_RIGHT, edge)
	var tiles_before: int = game.island_tiles.size()
	menu.buttons.trim.pressed.emit()
	check(menu.confirm_trim and game.island_tiles.size() == tiles_before, "Trimming requires a second explicit selection")
	menu.buttons.cancel.pressed.emit()
	check(not menu.is_open() and game.island_tiles.size() == tiles_before, "Cancelling trim preserves the tile")
	_click(game, MOUSE_BUTTON_RIGHT, edge)
	menu.buttons.trim.pressed.emit()
	menu.buttons.confirm_trim.pressed.emit()
	check(dev.tile_at(edge).is_empty() and game.island_tiles.size() == tiles_before - 1, "Confirmed trimming removes exactly the selected tile")
	_click(game, MOUSE_BUTTON_RIGHT, engine)
	coins_before = game.coins
	game.coins = 0
	check(not menu.activate("water") and dev.tile_at(engine).facility == "", "Stale UI callbacks recheck affordability before spending")
	game.coins = coins_before
	menu.close()
	game.sky_map_open = true
	_click(game, MOUSE_BUTTON_RIGHT, engine)
	check(not menu.is_open(), "Map input cannot accidentally open a world tile menu")
	game.sky_map_open = false
	_click(game, MOUSE_BUTTON_RIGHT, engine)
	dev.toggle(true)
	check(not menu.is_open() and dev.modal.visible, "Opening technology dismisses local actions")
	dev.close_menu()
	# Follow the selected tile at different camera scales, including viewport edges.
	for zoom in [0.55, 1.15]:
		game.camera_zoom = zoom
		game.camera_world = game.island_pos + Vector2(engine) * Tiles.CELL_SIZE - (Vector2(1120, 615) - game.VIEW_CENTER) / zoom
		_click(game, MOUSE_BUTTON_RIGHT, engine)
		await process_frame
		menu.update()
		check(menu.cell == engine and Rect2(Vector2(0, 80), Vector2(1152, 568)).encloses(menu.panel.get_global_rect()), "Menu is anchored to the correct tile and clamped inside the viewport")
		menu.close()
	if DisplayServer.get_name() != "headless": await _capture(game)
	game.queue_free()
	await process_frame
	for failure in failures: push_error(failure)
	print("CONTEXT MENU TEST: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _capture(game: Node2D) -> void:
	var dev = game.development
	dev.tile_menu.close()
	dev.close_menu()
	game.island_tiles = Tiles.initial_tiles()
	game.plots = []
	for y in range(-1, 2):
		for x in range(-1, 2):
			game.plots.append({"cell": Vector2i(x, y), "state": 2 if x == 1 else 1, "progress": 1.0 if x == 1 else 0.55, "crop_type": posmod(x + y, 2)})
	game.camera_zoom = 1.05
	game.camera_world = game.island_pos + Vector2(0, 12)
	game.targets = []
	game.hazards = []
	game.zones = []
	game.current_weather = -1
	game.weather_tint = 0.0
	game.rice_stock = 15
	game.energy_crop_stock = 8
	game.rice_seeds = 3
	game.tomato_seeds = 2
	game.coins = 186
	dev.materials = {"wood": 24, "stone": 18, "ore": 4, "magma": 1}
	for key in dev.tech: dev.tech[key] = 0
	dev.tech.engine = 1
	dev.tech.storage = 1
	dev.tech.forestry = 1
	dev.sync()
	game._select_crop_tool(game.CROP_RICE)
	game.notice_label.text = ""
	game.context_panel.hide()
	game.merchant_available = true
	game.merchant_stay_left = 64.0
	await _save_frame(game, "context-overview-preview.png")
	_click(game, MOUSE_BUTTON_RIGHT, Vector2i(2, 0))
	await _save_frame(game, "context-land-preview.png")
	_check_layout(game)
	dev.tile_menu.close()
	dev.tile_at(Vector2i(-1, -2)).hp = 58.0
	_click(game, MOUSE_BUTTON_RIGHT, Vector2i(-1, -2))
	await _save_frame(game, "context-facility-preview.png")
	_check_layout(game)
	dev.tile_menu.close()
	game.plots[dev.plot_at(Vector2i(-1, 0))].state = 0
	_click(game, MOUSE_BUTTON_RIGHT, Vector2i(-1, 0))
	await _save_frame(game, "context-farm-preview.png")
	_check_layout(game)

func _check_layout(game: Node2D) -> void:
	var menu = game.development.tile_menu
	check(menu.panel.size.x <= 320 and menu.panel.size.y <= 520, "Context menu remains compact")
	for button in menu.buttons.values():
		check(menu.panel.get_global_rect().encloses(button.get_global_rect()), "All tile actions fit inside the popup")
	check(game.tool_sidebar.get_global_rect().end.x <= 140 and game.tool_sidebar.get_global_rect().end.y < 580, "Quick tools fit along the left edge")

func _save_frame(game: Node2D, filename: String) -> void:
	game._update_hud()
	game.queue_redraw()
	await process_frame
	game.development.tile_menu.update()
	await process_frame
	await RenderingServer.frame_post_draw
	var path := ProjectSettings.globalize_path("res://../artifacts/game/" + filename)
	check(root.get_texture().get_image().save_png(path) == OK, "Saved preview " + filename)
