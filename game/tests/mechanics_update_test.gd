extends SceneTree

const Rules = preload("res://scripts/development_rules.gd")
const Tiles = preload("res://scripts/island_tiles.gd")
var checks := 0
var failures: Array[String] = []

func _init() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message); push_error(message)

func run() -> void:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.set_physics_process(false)
	game._start_demo()
	game.saves.directory = "res://../.codex_tmp/mechanics-test-saves"
	if "--load-only" in OS.get_cmdline_user_args():
		check(game.saves.load_slot(1), "Fresh process restores a previous save")
		check(game.coins == 1234 and game.explorer.state == "outbound", "Fresh process restores economy and active flight")
		check(not game.explorer.target.is_empty(), "Fresh process rebinds ship destination")
		game.queue_free()
		await process_frame
		print("FRESH PROCESS SAVE TEST: %d checks, %d failures" % [checks, failures.size()])
		quit(0 if failures.is_empty() else 1)
		return
	check(game.saves.validate(game.saves.snapshot()), "Fresh game snapshot validates")
	game.coins = 100000000
	game.rice_stock = 100000
	game.development.materials = {"wood": 1000000, "stone": 1000000, "ore": 1000000, "magma": 1000000}
	test_night(game)
	test_land(game)
	test_trees(game)
	test_ship(game)
	test_saves(game)
	test_pool(game)
	if DisplayServer.get_name() != "headless": await capture(game)
	game.queue_free()
	await process_frame
	print("MECHANICS UPDATE TEST: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func test_night(game) -> void:
	game.current_weather = -1
	game.day_minutes = 12 * 60.0
	game.plots[0].state = 1
	game.plots[0].progress = 0.0
	game._update_crops(10.0)
	var day: float = game.plots[0].progress
	game.day_minutes = 22 * 60.0
	game.plots[0].progress = 0.0
	game._update_crops(10.0)
	check(is_equal_approx(game.plots[0].progress, day * 0.8), "Night growth is exactly 80 percent of daytime")
	game.zones = [{"kind": "cyclone", "growth": 0.5}]
	game.current_weather = 0
	var base: float = game._growth_multiplier()
	game.day_minutes = 12 * 60.0
	check(is_equal_approx(base, game._growth_multiplier() * 0.8), "Night multiplies weather effects rather than replacing them")
	game.current_weather = -1
	game.day_minutes = 6 * 60.0
	check(game._night_growth() == 1.0, "Dawn restores daytime growth")
	game.day_minutes = 18 * 60.0
	check(game._night_growth() == 0.8, "Night starts at 18:00")
	game.day_minutes = 12 * 60.0
	for level in range(1, 4):
		game.development.tech.mineral_energy = level
		check(game.development.ore_energy() == [36, 60, 90][level - 1], "Mineral fuel doubled at level %d" % level)
	game.development.tech.geothermal = 1
	check(game.development.fuel_energy("magma") == 120, "Magma produces 120 E")

func test_land(game) -> void:
	var dev = game.development
	var cell := Vector2i(2, 0)
	var before: int = game.coins
	check(not game.land.reinforce(cell) and game.coins == before, "Unresearched reinforcement cannot spend resources")
	dev.tech.development = 1
	for stage in range(1, 6):
		check(dev.research("reinforcement"), "Research reinforcement stage %d" % stage)
		for step in range(3): check(game.land.reinforce(cell), "Each research stage unlocks three upgrades")
		check(not game.land.reinforce(cell), "No upgrades beyond the researched tier")
	var tile: Dictionary = dev.tile_at(cell)
	check(tile.reinforcement == 15 and tile.hp == 400.0, "Fifteen upgrades produce 400 maximum durability")
	check(Rules.reinforcement_cost(14).stone == 16384, "Upgrade cost grows geometrically")
	dev.damage_cell(cell, 45.0)
	check(tile.hp == 355.0, "Damage consumes reinforced durability")
	check(dev.repair(cell) and tile.hp == 400.0, "Repair restores the new maximum")
	dev.collision_at(game.island_pos + Vector2(cell) * Tiles.CELL_SIZE, 35.0, 10.0)
	check(not dev.tile_at(cell).is_empty() and tile.hp > 0 and tile.hp < 400, "Reinforced ground absorbs an impact before collapsing")
	dev.repair(cell)
	dev.tech.recycling = 1
	var low: Dictionary = game.land.refund(cell)
	dev.tech.recycling = 3
	var high: Dictionary = game.land.refund(cell)
	check(high.stone > low.stone and high.stone < tile.reinforcement_spent.stone, "Higher recycling tiers return more but never the full investment")
	before = dev.materials.stone
	check(game.land.recycle(cell), "Recycling removes a valid edge tile")
	check(dev.materials.stone == before + high.stone and dev.tile_at(cell).is_empty(), "Refund is paid once and the land is removed")
	check(not game.land.recycle(cell), "Cannot recycle the same tile twice")
	check(not game.land.recycle(Vector2i.ZERO), "Core cannot be recycled")
	check(game.land.refund(Vector2i(2, 1)) == {"stone": 1}, "Unreinforced land returns one stone")
	dev.tech.terraform = 1
	before = game.coins
	var wood: int = dev.materials.wood
	check(dev.trim(Vector2i(2, 1)), "Clipping still removes connected edge land")
	check(game.coins == before - 2 and dev.materials.wood == wood - 1, "Clipping charges the small resource fee")

func test_trees(game) -> void:
	var dev = game.development
	var cell := Vector2i(1, -2)
	dev.tech.forestry = 1
	check(dev.build(cell, "tree"), "Planting creates a sapling")
	var tile: Dictionary = dev.tile_at(cell)
	check(tile.tree_progress == 0.0 and tile.tree_hp == 25.0, "Saplings start with stage-specific vitality")
	check(not dev.gather(cell), "Immature trees cannot be harvested")
	game.current_weather = -1
	game.day_minutes = 12 * 60.0
	game.land.update_trees(45.0)
	check(is_equal_approx(tile.tree_progress, 0.25) and tile.tree_hp == 45.0, "Tree growth takes four crop durations and updates stage health")
	game.land.damage_tree(tile, 10)
	check(tile.tree_hp == 35.0 and not dev.repair_cost(cell).is_empty(), "Tree damage is independently repairable")
	check(dev.repair(cell) and tile.tree_hp == 45, "Repair restores tree vitality")
	game.zones = [{"kind": "storm", "growth": 0.7}]
	game.current_weather = 0
	game.land.update_trees(10)
	check(tile.tree_hp < 45.0, "Severe weather damages trees")
	game.land.damage_tree(tile, 1000)
	check(tile.kind == "grass" and tile.depleted, "Dead tree becomes empty land with no harvest payout")
	game.current_weather = -1
	check(dev.build(cell, "tree"), "Dead tree can be replanted")
	game.land.update_trees(180)
	check(tile.tree_progress == 1.0 and tile.tree_hp == 100.0, "Tree reaches maturity in 180 clear daytime seconds")

func test_ship(game) -> void:
	var dev = game.development
	var ship = game.explorer
	dev.tech.harbor = 1
	dev.tech.exploration = 1
	var inner: Dictionary = dev.tile_at(Vector2i.ZERO)
	inner.kind = "grass"
	game.plots.remove_at(dev.plot_at(Vector2i.ZERO))
	check(not dev.build(Vector2i.ZERO, "harbor"), "Port cannot be built in the island interior")
	check(dev.build(Vector2i(-2, 0), "harbor"), "Port can be built on perimeter land")
	check(not dev.build(Vector2i(0, -2), "harbor"), "Only one port can be constructed")
	check(ship.construct() and not ship.construct(), "Only one exploration ship can be constructed")
	game.energy = 150.0
	ship.update(2)
	check(ship.charge == 50.0 and game.energy == 100.0, "Dock charging transfers island energy without creating it")
	check(not ship.launch(), "Ship waits for a full charge")
	ship.cargo = {"ore": 12}
	check(ship.speed() == 75.0, "Cargo mass slows flight")
	ship.cargo = {}
	ship.charge = 500.0
	dev.tech.radar = 3
	var terrain: Dictionary = game.hazards[0]
	terrain.tiles[0].kind = "rock"
	terrain.tiles[0].depleted = false
	check(ship.launch(), "Charged ship finds a real mineral deposit")
	var mined_tile: Dictionary = ship.deposits(ship.target)[0]
	terrain = ship.target
	var ore: int = dev.materials.ore
	for i in range(2400): ship.update(0.25)
	check(ship.state == "docked" and dev.materials.ore > ore, "Ship completes outbound, mining, return and unloading")
	check(mined_tile.depleted and mined_tile.kind == "grass", "Mining depletes the actual external deposit")
	check(ship.cargo.is_empty(), "Delivered cargo is cleared")
	terrain.tiles[0].kind = "rock"
	terrain.tiles[0].depleted = false
	ship.charge = 500.0
	check(ship.launch(), "Second mission starts for in-flight save test")
	ship.update(1.0)

func test_saves(game) -> void:
	var saves = game.saves
	var ship_position: Vector2 = game.explorer.position
	var health: float = game.development.tile_at(Vector2i(1, -2)).tree_hp
	check(not saves.save_slot(0) and not saves.save_slot(6), "Exactly five slots are addressable")
	for slot in range(1, 6):
		game.coins = slot * 1234
		game.day_number = slot + 2
		check(saves.save_slot(slot), "Write independent slot %d" % slot)
	check(saves.read_packet(1).get("state", {}).get("coins", -1) == 1234, "Writing other slots does not overwrite slot one")
	for slot in range(1, 6):
		check(saves.load_slot(slot), "Read slot %d" % slot)
		check(game.coins == slot * 1234 and game.day_number == slot + 2, "Restore exact per-slot economy and time")
		check(game.explorer.state == "outbound" and game.explorer.position == ship_position, "Restore in-flight position and task")
		check(game.development.tile_at(Vector2i(1, -2)).tree_hp == health, "Restore tree vitality")
		check(not game.explorer.target.is_empty() and is_same(game.explorer.target, game.world_sectors[game.explorer.target.world_key].hazards[game.explorer.target.world_index]), "Ship target shares the restored live world record")
	var before: int = game.coins
	var bad := FileAccess.open(saves.path_for(5), FileAccess.WRITE)
	bad.store_string("not a valid save")
	bad.close()
	check(not saves.load_slot(5) and game.coins == before, "Corrupt file cannot mutate current play")
	check(saves.save_slot(5), "Corrupt test slot can be replaced with a valid save")
	saves.open_menu()
	var minutes: float = game.day_minutes
	game._physics_process(1.0)
	check(game.day_minutes == minutes, "Save menu pauses simulation")
	saves.choose("load", 1)
	check(saves.pending_action == "load", "Loading asks before discarding unsaved progress")
	saves.choose("save", 1)
	check(saves.pending_action == "save", "Overwrite requires confirmation")
	saves.request_exit()
	check(saves.is_open() and saves.exit_pending, "Window-close flow asks to save")
	saves.close()
	check(not saves.is_open() and not saves.exit_pending, "Cancel exit returns to current game")
	# A grapple operation has independent persistent identity, including sectors
	# outside the current neighborhood.
	var target: Dictionary = game.targets[0]
	game.hooked_target = 0
	game.hook_state = game.HOOK_FIXING
	game.hook_fixing_left = 3.25
	game.merge_offset = Vector2i(8, 0)
	target.island.tethered = true
	check(saves.save_slot(4) and saves.load_slot(4), "Save and restore during grapple fixing")
	check(game.hook_state == game.HOOK_FIXING and game.hook_fixing_left == 3.25 and game.hooked_target >= 0, "Grapple timer and target are restored")
	check(is_same(game.targets[game.hooked_target].island, game.world_sectors[target.island.world_key].hazards[target.island.world_index]), "Grapple and world share the restored island")
	game._cancel_hook()
	game.explorer.recall()
	game.explorer.state = "docked"
	game.explorer.target = {}

func test_pool(game) -> void:
	var origin: Vector2 = game.island_pos
	var terrain: Dictionary = game.hazards[0]
	var key: Vector2i = terrain.world_key
	var index: int = terrain.world_index
	terrain.active = false
	for step in range(1, 25):
		game.island_pos = game.world_origin + Vector2(step * 640 * 2, 0)
		game._update_world_stream()
		check(game.world_sectors.size() <= 123, "World keeps a bounded active neighborhood")
	check(game.sector_pool.reused > 0 and game.sector_pool.free_records.size() <= 121, "Sector records are reused within a bounded pool")
	game.island_pos = origin
	game._update_world_stream()
	check(not game.world_sectors[key].hazards[index].active, "Consumed island does not respawn after pooled streaming")
	check(game.saves.save_slot(3) and game.saves.load_slot(3), "Streamed world can be saved and restored")
	check(not game.world_sectors[key].hazards[index].active, "Consumed island stays consumed after reload")
	check(game.sector_pool.journal.size() < 10, "Untouched sectors do not accumulate in save journals")
	var original: Array = game.island_tiles
	var larger: Array = []
	for i in range(400): larger.append({"cell": Vector2i(i % 20 - 10, i / 20 - 10), "kind": "grass", "facility": "", "hp": 100.0, "level": 1, "depleted": false})
	game.island_tiles = larger
	game._refresh_island_shape()
	var started := Time.get_ticks_usec()
	for i in range(10000): game.development.tile_at(Vector2i(9, 9))
	var indexed_ms := (Time.get_ticks_usec() - started) / 1000.0
	started = Time.get_ticks_usec()
	for i in range(10000):
		for tile in game.island_tiles:
			if tile.cell == Vector2i(9, 9): break
	var linear_ms := (Time.get_ticks_usec() - started) / 1000.0
	print("400-tile lookup / 10000 calls: indexed %.2f ms, linear %.2f ms; pooled tiles created=%d reused=%d; journal=%d" % [indexed_ms, linear_ms, game.sector_pool.tile_created, game.sector_pool.tile_reused, game.sector_pool.journal.size()])
	check(game.development.tile_at(Vector2i(9, 9)).cell == Vector2i(9, 9), "Larger-island indexed lookup returns the correct tile")
	game.island_tiles = original
	game.development.sync()

func capture(game) -> void:
	game.hook_state = game.HOOK_READY
	game.hooked_target = -1
	game.context_panel.hide()
	game.coins = 50000
	game.day_minutes = 22 * 60.0
	game.day_number = 12
	game.development.tech.agri_automation = 3
	var tile: Dictionary = game.development.tile_at(Vector2i(0, -2))
	tile.facility = "farm_hut"
	tile.level = 3
	tile.farm_crop = 0
	tile.farm_enabled = true
	game.development.tile_at(Vector2i(2, -2)).kind = "lava"
	for plot in game.plots:
		plot.state = 1
		plot.progress = 0.2 + posmod(plot.cell.x + plot.cell.y, 4) * 0.18
	game._update_tool_styles()
	game._set_view_mode(game.VIEW_FOCUS)
	game.camera_zoom = 1.0
	game.camera_zoom_target = 1.0
	game.camera_world = game.island_pos
	game.development.sync()
	game._update_hud()
	game.queue_redraw()
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://../artifacts/game/mechanics-night.png")
	check(game.development.tile_menu.open_at(tile.cell), "Dedicated hut interface opens")
	await process_frame
	await process_frame
	game.development.tile_menu.update()
	await RenderingServer.frame_post_draw
	check(Rect2(Vector2.ZERO, game.VIEW_SIZE).encloses(game.development.tile_menu.panel.get_global_rect()), "Hut interface remains inside viewport")
	root.get_texture().get_image().save_png("res://../artifacts/game/mechanics-hut.png")
	game.saves.open_menu()
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	check(Rect2(Vector2.ZERO, game.VIEW_SIZE).encloses(game.saves.panel.get_global_rect()), "Five-slot menu remains inside viewport")
	root.get_texture().get_image().save_png("res://../artifacts/game/mechanics-saves.png")
	game.saves.close()
	game.explorer.open_menu()
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://../artifacts/game/mechanics-ship.png")
	game.development.close_menu()
