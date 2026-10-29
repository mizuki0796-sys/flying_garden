extends SceneTree

const Rules = preload("res://scripts/development_rules.gd")
const Tiles = preload("res://scripts/island_tiles.gd")
var failures: Array[String] = []
var checks := 0

func _init() -> void:
	call_deferred("run")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label); push_error(label)

func index_of(layout, cell: Vector2i) -> int:
	for i in range(layout.draft.size()):
		if layout.draft[i].cell == cell: return i
	return -1

func run() -> void:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.set_physics_process(false)
	game._start_demo()
	var dev = game.development
	var layout = dev.layout
	game.coins = 20000
	dev.materials = {"wood": 2000, "stone": 2000, "ore": 2000, "magma": 0}
	layout.open()
	check(not dev.layout_open, "Editor is technology gated")
	check(not dev.research("layout"), "Research requires prerequisites")
	dev.tech.terraform = 1
	dev.tech.development = 2
	var coins: int = game.coins
	check(dev.research("layout") and game.coins == coins - 300, "Research charges quoted moderate unlock price")
	var old: Dictionary = game.saves.snapshot()
	old.tech.erase("layout")
	old.erase("layout_presets")
	check(game.saves.validate(old), "Old version-1 saves remain compatible")
	layout.begin()
	check(layout.validate_layout(layout.draft).is_empty(), "Initial layout is valid")
	coins = game.coins
	check(not layout.apply() and game.coins == coins, "Unchanged application is free and rejected")
	layout.selected = [index_of(layout, Vector2i.ZERO)]
	check(not layout.move_selection(Vector2i.RIGHT), "Core cannot move")
	layout.selected = [index_of(layout, Vector2i(-1, 0))]
	check(not layout.move_selection(Vector2i.RIGHT), "Core cannot be swapped")
	layout.selected = [index_of(layout, Vector2i(-2, -2))]
	check(layout.move_selection(Vector2i(-5, 0)), "Draft permits temporarily disconnected arrangement")
	check(not layout.validate_layout(layout.draft).is_empty(), "Disconnected final layout rejected")
	check(not layout.apply() and game.coins == coins, "Invalid layout consumes no resources")
	layout.undo()
	check(layout.moved_count() == 0, "Undo restores draft")
	layout.selected = [index_of(layout, Vector2i(-2, -2)), index_of(layout, Vector2i(-2, -1))]
	check(not layout.move_selection(Vector2i.RIGHT), "Group overlap rejected")
	check(layout.move_selection(Vector2i.LEFT), "Group movement supported")
	check(layout.moved_count() == 2, "Group quote counts moved tiles")
	layout.reset()
	# Complete tile state and plot state must follow a swap.
	var farm_cell := Vector2i(1, 0)
	var house_cell := Vector2i(-1, -2)
	var farm: Dictionary = dev.tile_at(farm_cell)
	farm.reinforcement = 3
	farm.hp = 132.0
	var plot: Dictionary = game.plots[dev.plot_at(farm_cell)]
	plot.state = 1
	plot.progress = 0.41
	plot.crop_type = 1
	plot.weather_kind = "cyclone"
	var expected_plot := plot.duplicate(true)
	var expected_farm := farm.duplicate(true)
	layout.begin()
	check(layout.save_preset(0), "Save original preset without charge")
	layout.selected = [index_of(layout, farm_cell)]
	check(layout.move_selection(house_cell - farm_cell), "Occupied single-cell drop swaps tiles")
	check(layout.save_preset(1), "Save alternate preset")
	check(layout.quote() == {"coins": 580, "wood": 68, "stone": 92, "ore": 24}, "Quote includes base cost plus both moved cells")
	check(game.coins == coins, "Draft edits and presets cost nothing")
	var before_tiles: Array = game.island_tiles.duplicate(true)
	game.coins = 0
	check(not layout.apply() and game.island_tiles == before_tiles, "Insufficient funds leave world unchanged")
	game.coins = coins
	game.hook_state = game.HOOK_EXTEND
	check(not layout.apply() and game.coins == coins, "Hook operation prevents commit")
	game.hook_state = game.HOOK_READY
	game.explorer.state = "outbound"
	check(not layout.apply() and game.coins == coins, "Active expedition prevents commit")
	game.explorer.state = "docked"
	var hazards: Array = game.hazards
	game.hazards = [{"active": true, "pos": game.island_pos, "tiles": [{"cell": Vector2i.ZERO}]}]
	check(not layout.apply() and game.coins == coins, "External island overlap prevents commit")
	game.hazards = hazards
	var wood: int = dev.materials.wood
	check(layout.apply(), "Valid funded layout applies")
	check(game.coins == coins - 580 and dev.materials.wood == wood - 68, "Commit charges exactly once")
	expected_farm.cell = house_cell
	expected_plot.cell = house_cell
	check(dev.tile_at(house_cell) == expected_farm, "Full tile durability and reinforcement preserved")
	check(game.plots[dev.plot_at(house_cell)] == expected_plot, "Crop state, progress and weather preserved")
	check(dev.tile_at(farm_cell).facility == "water", "Building follows its tile")
	check(game.tile_index.has(house_cell) and game.ordered_tiles.size() == game.island_tiles.size(), "Rendering and picking indices rebuilt")
	coins = game.coins
	check(not layout.apply() and game.coins == coins, "Repeated stale commit cannot double spend")
	layout.begin()
	check(layout.load_preset(0) and layout.moved_count() == 2, "Original preset remains bound to tile identities after rearrangement")
	check(layout.apply() and game.coins == coins - 580, "Applying a saved preset also charges resources")
	check(dev.tile_at(farm_cell).hp == 132.0, "Preset cannot repair tiles")
	layout.begin()
	var ship_tile: Dictionary = dev.tile_at(Vector2i(-2, 0))
	ship_tile.facility = "harbor"
	layout.begin()
	layout.selected = [index_of(layout, Vector2i(-2, 0))]
	layout.move_selection(Vector2i.RIGHT)
	check("港口" in layout.validate_layout(layout.draft), "Harbor cannot be moved into interior")
	ship_tile.facility = ""
	layout.begin()
	check(layout.save_preset(2), "Third preset supported")
	game.saves.directory = "res://../.codex_tmp/layout-test-saves"
	check(game.saves.save_slot(1), "Presets save to disk")
	layout.presets = [{}, {}, {}]
	check(game.saves.load_slot(1) and not layout.presets[2].is_empty(), "Presets survive reload")
	layout.begin()
	game.island_tiles.append({"cell": Vector2i(3, 0), "kind": "grass", "facility": "", "level": 1, "hp": 100.0})
	layout.begin()
	check(not layout.load_preset(0), "Topology change rejects outdated presets")
	game.island_tiles.pop_back()
	dev.sync()
	check(game.saves.validate(game.saves.snapshot()), "New save format validates")
	var bad: Dictionary = game.saves.snapshot()
	bad.layout_presets = [{1: "bad"}, {}, {}]
	check(not game.saves.validate(bad), "Malformed presets rejected")
	for wind in [0.1, 0.4, 0.65]:
		game.wind_strength = wind
		for age in [0.0, 0.2, 0.5, 0.9]:
			var sample: Dictionary = game._smoke_puff(age, 0.3)
			var drift: float = -minf(wind, 0.4) * age * 8.0 + sin(age * 4.0 + 0.3) * age * 2.0
			check(sample.offset.is_equal_approx(Vector2(drift, -age * 86.0)) and sample.stretch == Vector2.ONE, "Ordinary weather preserves smoke sample")
	game.wind_strength = 1.6
	var gale: Dictionary = game._smoke_puff(0.4, 0.3)
	check(gale.offset.x < -60 and gale.stretch.x > 2.0 and gale.opacity < 0.5, "Cyclone blows, stretches and fades smoke")
	check(game._smoke_puff(0.6, 0.3).opacity == 0.0, "Cyclone fully disperses old puffs")
	layout.open()
	await process_frame
	await process_frame
	var board = layout.board
	board.fit()
	var source := Vector2(2, -2)
	var target := Vector2(2, -1)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = board.offset + (source if pressed else target) * Tiles.CELL_SIZE * board.zoom
		board.input_event(event)
	check(layout.moved_count() == 2, "Board drag event swaps cells")
	layout.apply_button.pressed.emit()
	check(layout.confirmation and dev.modal.visible, "Apply button requires review of cost before commit")
	coins = game.coins
	dev.close_menu()
	check(game.coins == coins, "Cancel confirmation is free")
	layout.open()
	await process_frame
	check(layout.moved_count() == 0, "Reopening discards cancelled changes")
	if DisplayServer.get_name() != "headless":
		await capture(game, "layout-editor.png")
	layout.selected = [index_of(layout, Vector2i(-2, -2))]
	layout.move_selection(Vector2i(-1, 1))
	layout.apply_button.pressed.emit()
	if DisplayServer.get_name() != "headless": await capture(game, "layout-proposed.png")
	layout.apply_button.pressed.emit()
	check(not dev.modal.visible and dev.tile_at(Vector2i(-3, -1)).kind == "tree", "Confirm button commits edited shape")
	if DisplayServer.get_name() != "headless":
		game.wind_strength = 1.6
		game.animation_time = 1.0
		await capture(game, "layout-in-game.png")
	game.queue_free()
	await process_frame
	print("ISLAND LAYOUT: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func capture(game, filename: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://../artifacts/game/island-layout"))
	game.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://../artifacts/game/island-layout/" + filename)
