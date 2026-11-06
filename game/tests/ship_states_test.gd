extends SceneTree

var checks := 0
var failures := 0

func _init() -> void: call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)

func run() -> void:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game._start_demo()
	game.set_process(false)
	game.set_physics_process(false)
	var dev = game.development
	var ship = game.explorer
	game.coins = 1000000
	dev.materials = {"wood": 100000, "stone": 100000, "ore": 100000, "magma": 100000}
	dev.tech.harbor = 1
	dev.tech.engine = 3
	dev.tech.radar = 3
	check(dev.research("exploration"), "Research level I")
	check(dev.build(Vector2i(2, 0), "harbor") and ship.construct(), "Build real harbor and ship")
	var islands: Array = []
	for size in range(3):
		islands.append({"active": true, "size_class": size, "name": "测试岛", "pos": ship.position + Vector2(500 - size * 100, 0), "tiles": [{"cell": Vector2i.ZERO, "kind": "rock", "depleted": false}]})
	game.hazards = islands
	for level in range(1, 4):
		check(dev.tech.exploration == level, "Actual research level")
		for size in range(3):
			check(not ship.deposits(islands[size]).is_empty() == (size < level), "Level gates size %d/%d" % [level, size])
		ship.state = "docked"
		ship.charge = 500.0
		check(ship.launch() and ship.target.size_class == level - 1, "Choose nearest unlocked island, skip nearer locked islands")
		if level < 3:
			var before: int = game.coins
			check(dev.research("exploration"), "Upgrade exploration")
			check(before - game.coins == 20000 * int(pow(3, level)), "Reuse escalating research price")
	check(not dev.research("exploration"), "No level IV")
	dev.tech.exploration = 1
	ship.target = islands[2]
	ship.state = "mining"
	check(not ship.mine_once() and not islands[2].tiles[0].depleted, "Locked island cannot be mined even with a restored target")
	game.hazards = [islands[2]]
	ship.state = "docked"
	ship.charge = 500.0
	check(not ship.launch(), "Only locked islands means no launch")
	dev.tech.exploration = 3
	for amount in [0, 1, 239, 240]:
		ship.cargo = {"ore": amount}
		check(ship.cargo_state() == (0 if amount == 0 else (2 if amount == 240 else 1)), "Cargo boundary %d" % amount)
		var saved: Dictionary = ship.snapshot()
		ship.cargo = {}
		ship.restore(saved)
		check(ship.load_weight() == amount, "Restore cargo %d" % amount)
	ship.state = "docked"
	ship.update(0.1)
	check(ship.cargo_state() == 0, "Dock unloading resets cargo visual")
	ship.cargo = {}
	ship.target = islands[0]
	ship.position = Vector2(ship.target.pos) - Vector2(80.1, 0)
	ship.state = "mining"
	ship.charge = 500.0
	check(ship.mine_once() and ship.cargo_state() == 1, "Real mining changes cargo from empty to partial")
	for direction in [Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT, Vector2.UP, Vector2(1, 1), Vector2(-1, 1), Vector2(-1, -1), Vector2(1, -1)]:
		# Exercise exhaust in open sky; inward flight from a berth now hits home.
		ship.position = ship.dock_position() + Vector2(1000, 0)
		ship.target = {"active": true, "size_class": 0, "pos": ship.position + direction.normalized() * 600, "tiles": [{"cell": Vector2i.ZERO, "kind": "rock"}]}
		game.hazards = [ship.target]
		ship.state = "outbound"
		ship.charge = 500.0
		ship.exhaust.clear()
		ship.exhaust_elapsed = 0.0
		for step in range(30): ship.update(1.0 / 30.0)
		check(not ship.exhaust.is_empty() and ship.exhaust.size() <= 5, "Sparse bounded exhaust in all eight directions")
		for puff in ship.exhaust:
			check((puff.pos - ship.position).dot(direction) < 0, "Exhaust remains behind travel direction")
	ship.charge = 0.0
	ship.update(0.1)
	check(ship.exhaust.is_empty(), "Unpowered drift has no exhaust")
	for stopped in ["mining", "docked"]:
		ship.exhaust.clear()
		ship.exhaust.append({"pos": ship.position, "age": 0.0})
		ship.state = stopped
		ship.update(0.01)
		check(ship.exhaust.is_empty(), "Stationary state clears exhaust")
	game.saves.directory = "res://../.codex_tmp/ship-states-saves"
	for level in [1, 2, 3]:
		dev.tech.exploration = level
		ship.cargo = {"ore": 12}
		check(game.saves.save_slot(level), "Save level %d" % level)
		dev.tech.exploration = 0
		ship.cargo = {}
		check(game.saves.load_slot(level) and dev.tech.exploration == level and ship.cargo_state() == 1, "Load level and cargo %d" % level)
	game.queue_free()
	await process_frame
	print("SHIP STATES: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
