extends SceneTree

const Rules = preload("res://scripts/development_rules.gd")
const MULTIPLIERS := [1, 2, 3, 5, 8, 12, 18, 27, 40, 60, 90]
var checks := 0
var failures := 0
var game

func _init() -> void: call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)

func tile(cell: Vector2i, kind: String, facility := "") -> Dictionary:
	return {"cell": cell, "kind": kind, "facility": facility, "level": 1, "hp": 100.0, "depleted": false}

func run() -> void:
	root.size = Vector2i(1152, 648)
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game._start_demo()
	game.set_process(false)
	game.set_physics_process(false)
	var dev = game.development
	game.saves.directory = "res://../.codex_tmp/production-tech-saves"
	check(dev.crop_yield() == 1 and dev.gathering_multiplier() == 1, "Unresearched production unchanged")
	check(Rules.research_cost("engine", 2).coins == 225, "Existing research prices unchanged")
	for key in ["gathering", "crop_yield"]:
		game.coins = 9
		check(not dev.research(key) and dev.tech[key] == 0 and game.coins == 9, "Insufficient funds cannot upgrade")
		game.coins = 10
		check(dev.research(key) and dev.tech[key] == 1 and game.coins == 0, "First level costs only ten coins without materials")
		game.coins = 2000000
		dev.materials = {"wood": 100000, "stone": 100000, "ore": 100000, "magma": 100000}
		var previous := {"coins": 10}
		for level in range(1, 10):
			var cost: Dictionary = dev.research_cost(key)
			for resource in previous:
				check(int(cost[resource]) > int(previous[resource]), "Every resource cost grows at level %d" % (level + 1))
			var before: Dictionary = {}
			for resource in cost: before[resource] = dev.stock(resource)
			check(dev.research(key) and dev.tech[key] == level + 1, "All ten levels reachable")
			for resource in cost: check(dev.stock(resource) == before[resource] - cost[resource], "Exact research payment")
			previous = cost
		var coins: int = game.coins
		check(not dev.research(key) and game.coins == coins, "No eleventh level or payment")
	for level in range(11):
		dev.tech.gathering = level
		dev.tech.crop_yield = level
		check(dev.crop_yield() == MULTIPLIERS[level] and dev.gathering_multiplier() == MULTIPLIERS[level], "All production multipliers")
		check(is_equal_approx(game.explorer.mining_interval(), 3.0 / MULTIPLIERS[level]), "Ship mining interval follows research")
	dev.tech.development = 3
	game.island_tiles = [tile(Vector2i.ZERO, "grass"), tile(Vector2i(1, 0), "rock"), tile(Vector2i(0, 1), "farm")]
	game.plots = [{"cell": Vector2i(0, 1), "state": 2, "progress": 1.0, "crop_type": 0}]
	dev.sync()
	var ore: int = dev.materials.ore
	check(dev.gather(Vector2i(1, 0)) and dev.materials.ore == ore + 720, "Ground gathering stacks with development III")
	check(not dev.gather(Vector2i(1, 0)) and dev.materials.ore == ore + 720, "Depleted tile cannot award twice")
	for crop in [0, 1]:
		game.plots[0].state = 2
		game.plots[0].crop_type = crop
		var stock: int = game.rice_stock if crop == 0 else game.energy_crop_stock
		var seeds: int = game.seed_stock(crop)
		var coins: int = game.coins
		game._interact_with_plot(game._plot_rect(0).get_center())
		check((game.rice_stock if crop == 0 else game.energy_crop_stock) == stock + 90, "Manual crop yield")
		check(game.coins == coins + dev.harvest_coins(crop) * 90 and game.seed_stock(crop) == seeds + 1, "Harvest income scales, seed refund stays one")
	dev.tile_at(Vector2i.ZERO).facility = "farm_hut"
	dev.tech.agri_automation = 1
	game.plots[0].state = 2
	game.plots[0].crop_type = 0
	var rice: int = game.rice_stock
	check(dev.manage_farms() == 2 and game.rice_stock == rice + 90 and game.plots[0].state == 1, "Auto harvesting scales and replants once")
	check(dev.manage_farms() == 0 and game.rice_stock == rice + 90, "Growing crop cannot be harvested twice")
	var ship = game.explorer
	dev.tech.exploration = 1
	ship.built = true
	ship.state = "mining"
	ship.position = game.island_pos
	ship.charge = 500.0
	ship.target = {"active": true, "size_class": 0, "pos": ship.position, "tiles": [tile(Vector2i.ZERO, "rock"), tile(Vector2i(1, 0), "rock"), tile(Vector2i(2, 0), "rock"), tile(Vector2i(3, 0), "rock")]}
	ship.position -= Vector2(200.1, 0)
	ship.dock_offset = ship.position - Vector2(ship.target.pos)
	ship.mining_left = ship.mining_interval()
	ship.update(0.11)
	check(ship.load_weight() == 24 and ship.state == "returning", "Low frame rate processes full mining speed, stops at capacity")
	check(not ship.target.tiles[3].depleted and ship.charge == 464.0, "Mining keeps per-deposit yield and energy cost")
	ship.built = false
	ship.state = "docked"
	ship.target = {}
	ship.cargo = {}
	check(game.saves.save_slot(1), "Save both production levels")
	dev.tech.gathering = 0
	dev.tech.crop_yield = 0
	check(game.saves.load_slot(1) and dev.tech.gathering == 10 and dev.tech.crop_yield == 10, "Restore both production levels")
	var packet: Dictionary = game.saves.snapshot()
	for key in ["gathering", "crop_yield"]:
		for bad in [-1, 11, 1.5]:
			packet.tech[key] = bad
			check(not game.saves.validate(packet), "Reject invalid production level")
		packet.tech[key] = 10
	packet.tech.erase("gathering")
	packet.tech.erase("crop_yield")
	check(game.saves.validate(packet), "Legacy save accepted")
	var bytes := var_to_bytes(packet)
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(bytes)
	var file := FileAccess.open(game.saves.path_for(2), FileAccess.WRITE)
	file.store_buffer(hashing.finish())
	file.store_buffer(bytes)
	file.close()
	check(game.saves.load_slot(2) and dev.tech.gathering == 0 and dev.tech.crop_yield == 0, "Legacy save receives level zero for both branches")
	dev.toggle(true)
	var ui = dev.content.get_node("TechnologyTree")
	ui.set_process(false)
	for level in [0, 9, 10]:
		for key in ["gathering", "crop_yield"]:
			dev.tech[key] = level
			ui.jump_to(key)
			await process_frame
			await process_frame
			ui._place_card()
			check(ui.get_global_rect().encloses(ui.card.get_global_rect()), "Production details fit panel at every price tier")
			check(ui.research_button.disabled == (level == 10), "Research button reflects max level")
			if DisplayServer.get_name() != "headless":
				await RenderingServer.frame_post_draw
				var directory := ProjectSettings.globalize_path("res://../artifacts/game/production-tech")
				DirAccess.make_dir_recursive_absolute(directory)
				root.get_texture().get_image().save_png(directory.path_join("%s-%d.png" % [key, level]))
	game.queue_free()
	await process_frame
	print("PRODUCTION TECH: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
