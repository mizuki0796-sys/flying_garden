extends SceneTree

const Weather = preload("res://scripts/weather_system.gd")
const Rules = preload("res://scripts/development_rules.gd")
var failures: Array[String] = []
var checks := 0

func _init() -> void:
	call_deferred("_run")

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition: failures.append(label)

func _run() -> void:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_physics_process(false)
	game.set_process(false)
	game._start_demo()
	var dev = game.development
	check(is_equal_approx(game._engine_thrust(), 240.0), "starting engine retains baseline thrust")
	check(not dev.research("automatic"), "automatic refuel requires efficiency research")
	check(not dev.gather(Vector2i(2, -2)), "mining requires island development research")
	var initial_seeds: int = game.seeds
	check(dev.gather(Vector2i(-2, -2)) and game.seeds > initial_seeds, "forest supplies extra seeds and wood")
	var resources_before: Dictionary = dev.materials.duplicate()
	check(not dev.gather(Vector2i(-2, -2)) and dev.materials == resources_before, "depleted terrain cannot be repeatedly harvested")
	var before: int = game.coins
	check(not dev.build(Vector2i(0, -2), "power") and game.coins == before, "construction locked before research without paying")
	game.coins = 5000
	game.rice_stock = 100
	dev.materials = {"wood": 200, "stone": 200, "ore": 200, "magma": 5}
	check(dev.research("engine"), "power engineering research completes")
	var thrust_before: float = game._engine_thrust()
	var wood_before: int = dev.materials.wood
	before = game.coins
	check(dev.build(Vector2i(0, -2), "power"), "engine occupies one available tile")
	check(game.coins == before - 40 and dev.materials.wood == wood_before - 6, "building consumes specified resources")
	check(game._engine_thrust() > thrust_before * 1.9, "multiple engines add thrust")
	thrust_before = game._engine_thrust()
	check(dev.upgrade(Vector2i(0, -2)) and game._engine_thrust() > thrust_before, "building upgrade improves power")
	before = game.coins
	check(not dev.upgrade(Vector2i(0, -2)) and game.coins == before, "building level is capped by technology")
	check(not dev.build(Vector2i(0, -2), "water") and game.coins == before, "building on occupied tile does not spend")
	check(dev.research("storage"), "storage research unlocks construction")
	var capacity_before: float = game.energy_capacity
	check(dev.build(Vector2i(1, 2), "water") and game.energy_capacity > capacity_before, "storage construction increases energy capacity")
	capacity_before = game.energy_capacity
	check(dev.upgrade(Vector2i(1, 2)) and game.energy_capacity > capacity_before, "storage upgrade increases capacity")
	var origin_before: Vector2 = game._hook_origin()
	dev.tile_at(Vector2i(2, 0)).hp = 55.0
	check(dev.relocate(Vector2i(2, 0), Vector2i(-2, 0)), "grapple hut relocates")
	check(game._hook_origin() != origin_before and dev.tile_at(Vector2i(-2, 0)).hp == 55.0, "launch origin and damage follow moved hut")
	var range_before: float = game.hook_max_distance
	check(dev.research("hook") and game.hook_max_distance > range_before, "hook range technology applies immediately")
	check(dev.upgrade(Vector2i(-2, 0)), "grapple building can upgrade after research")
	check(dev.research("development") and dev.gather(Vector2i(2, -2)), "development unlocks mineral extraction")
	check(dev.research("development"), "advanced development unlocks lava")
	var harvested_ore: int = dev.materials.ore
	var extra_tile: Dictionary = dev.tile_at(Vector2i(2, 1))
	extra_tile.kind = "lava"
	extra_tile.depleted = false
	check(dev.gather(Vector2i(2, 1)) and dev.materials.ore > harvested_ore, "lava has collectible material yields")
	check(dev.research("efficiency"), "energy efficiency research completes")
	check(is_equal_approx(dev.efficiency(), 0.85), "efficiency reduces mechanical costs by 15 percent")
	check(dev.research("geothermal"), "geothermal has satisfied development and efficiency prerequisites")
	game.energy = 0.0
	var magma_before: int = dev.materials.magma
	game._refuel_from_crops()
	check(game.energy == 60.0 and dev.materials.magma == magma_before - 1, "magma is consumed as high-value fuel")
	check(dev.research("automatic"), "automatic refuel unlocks")
	dev.materials.magma = 0
	game.energy_crop_stock = 1
	game.energy = 0.0
	dev.update()
	check(game.energy == 35.0 and game.energy_crop_stock == 0, "automatic fill consumes a stock item")
	dev.auto_fuel = false
	game.energy = 0.0
	dev.update()
	check(game.energy == 0.0, "automatic fill toggle is respected")
	game.notice_label.text = "保留现有通知"
	game.hook_state = game.HOOK_READY
	for i in range(50): game._fire_hook(game.island_pos + Vector2(200, 0))
	check(game.notice_label.text == "保留现有通知" and game.hook_state == game.HOOK_READY, "repeated zero-energy actions only warn in the energy field")
	game._update_hud()
	check("!" in game.energy_label.text, "low energy is visible locally in the HUD")
	var plot_count: int = game.plots.size()
	check(dev.build(Vector2i(2, -2), "farm") and game.plots.size() == plot_count + 1, "reclaimed mineral tile becomes a dynamic farm")
	game.seeds = 2
	check(dev.batch(false) == 2 and game.seeds == 0, "batch planting stops at inventory limit")
	for plot in game.plots:
		if plot.state == 1:
			plot.state = 2
			plot.progress = 1.0
	check(dev.batch(true) == 2 and game.seeds == 2, "batch harvest collects each mature plot once")
	before = game.coins
	check(dev.batch(true) == 0 and game.coins == before, "repeated batch harvest does not duplicate rewards")
	var starter: Dictionary = {}
	for target in game.targets:
		check(target.has("island"), "world has no independent floating loot")
		if target.pos.distance_to(game.world_origin + Vector2(450, -100)) < 1.0: starter = target
	game.rice_stock = 10
	before = game.coins
	check(dev.survey(starter) and game.coins == before - 8 and game.rice_stock == 9, "survey spends gold and food")
	before = game.coins
	check(dev.survey(starter) and game.coins == before and "参考估值" in starter.island.report, "survey report persists without duplicate payment")
	var power_cell := Vector2i(0, -2)
	var engine: Dictionary = dev.tile_at(power_cell)
	engine.hp = 100.0
	thrust_before = game._engine_thrust()
	dev.damage_at(game.island_pos + Vector2(power_cell) * game.IslandTiles.CELL_SIZE, 80.0)
	check(engine.hp < 100.0 and game._engine_thrust() < thrust_before, "collision damage degrades engine output")
	var repair_price: Dictionary = dev.repair_cost(power_cell)
	before = game.coins
	check(dev.repair(power_cell) and engine.hp == 100.0 and game.coins == before - repair_price.coins, "repair pays materials and restores durability")
	check(is_equal_approx(game._engine_thrust(), thrust_before), "repair restores engine output")
	game.coins = 0
	engine.hp = 30.0
	check(not dev.repair(power_cell) and engine.hp == 30.0, "unaffordable repair cannot restore durability")
	game.coins = 5000
	check(not dev.trim(Vector2i(2, 2)), "island clipping requires research")
	check(dev.research("terraform"), "island clipping research unlocks")
	check(not dev.trim(Vector2i.ZERO) and not dev.trim(power_cell), "core and facilities are protected from clipping")
	var count_before: int = game.island_tiles.size()
	check(dev.trim(Vector2i(2, -2)) and game.island_tiles.size() == count_before - 1, "clipping removes a chosen connected edge tile")
	check(dev.plot_at(Vector2i(2, -2)) == -1, "clipping removes the associated dynamic farm")
	# A narrow bridge may not disconnect retained land.
	game.island_tiles = [{"cell": Vector2i.ZERO, "kind": "grass", "facility": ""}, {"cell": Vector2i(1, 0), "kind": "grass", "facility": ""}, {"cell": Vector2i(2, 0), "kind": "grass", "facility": ""}]
	check(not dev.can_trim(Vector2i(1, 0)) and dev.can_trim(Vector2i(2, 0)), "clipping keeps all remaining tiles connected")
	# The actual menu can open and build all rows without deferred callback failures.
	dev.toggle(true)
	check(dev.modal.visible and dev.content.get_child_count() > 10, "technology tree UI renders all research branches")
	dev.toggle(false)
	check(dev.modal.visible and not dev.tech_open, "development menu renders all actions")
	dev.modal.hide()
	_test_weather()
	game.queue_free()
	await process_frame
	for failure in failures: push_error(failure)
	print("DEVELOPMENT TEST: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _test_weather() -> void:
	var kinds: Dictionary = {}
	check(PI * Weather.RAIN_RADIUS * Weather.RAIN_RADIUS >= 100 * 400 * 320, "rain/storm area is at least 100 starting islands")
	for elapsed in range(0, 1100, 37):
		var zones: Array = Weather.regions(Vector2.ZERO, Vector2.ZERO, float(elapsed))
		var ids: Dictionary = {}
		for zone in zones:
			ids[zone.id] = zone
			kinds[zone.kind] = true
			check(zone.remaining > 0 and zone.velocity.length() < 0.7, "weather has finite duration and slow drift")
		for zone in zones:
			if not zone.has("parent_id"): continue
			check(ids.has(zone.parent_id), "precipitation cannot exist without a cloudy parent")
			if ids.has(zone.parent_id):
				var parent: Dictionary = ids[zone.parent_id]
				check(parent.kind == "cloud" and zone.pos.distance_to(parent.pos) + zone.radius <= parent.radius, "rain/storm stays entirely inside its parent cloud")
				check(zone.remaining <= parent.remaining and zone.velocity == parent.velocity, "precipitation cannot outlive or drift out of parent")
	check(kinds.size() == 4, "sun, cloud, rain, and thunderstorm occur")
	var first: Dictionary = Weather.regions(Vector2.ZERO, Vector2.ZERO, 0.0)[0]
	var later: Array = Weather.regions(first.pos, Vector2.ZERO, float(first.remaining) + 0.1)
	var old_survived := false
	for zone in later:
		if zone.id == first.id: old_survived = true
	check(not old_survived, "weather expires instead of remaining permanently")
