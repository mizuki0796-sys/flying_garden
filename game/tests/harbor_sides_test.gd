extends SceneTree
const Tiles = preload("res://scripts/island_tiles.gd")
var game
var checks := 0
var failures := 0
func _init() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)
func run() -> void:
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game._start_demo()
	game.set_process(false)
	game.set_physics_process(false)
	game.hazards = []
	game.targets = []
	game.island_velocity = Vector2.ZERO
	game.island_tiles = [{"cell": Vector2i.ZERO, "kind": "grass", "facility": "harbor", "level": 1, "hp": 100.0, "depleted": false}]
	game.plots = []
	game._refresh_island_shape()
	var ship = game.explorer
	var dev = game.development
	ship.built = true
	ship.home_cell = Vector2i.ZERO
	dev.tech.exploration = 1
	check(ship.berths(Vector2i.ZERO).size() == 4, "Four sides of the same harbor are available")
	for side in [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]:
		var berth: Vector2 = ship.berths(Vector2i.ZERO)[side]
		ship.position = berth + Vector2(side) * 5.0
		ship.velocity = -Vector2(side) * 10.0
		ship.hp = 100.0
		ship.charge = 100.0
		ship.state = "manual"
		ship.manual_move(0.2, -Vector2(side))
		check(ship.state == "docked" and ship.home_direction == side and ship.position == berth, "Dock on side " + str(side))
		ship.cargo = {"ore": 2}
		var ore: int = dev.materials.ore
		game.energy = 150.0
		ship.update(0.1)
		check(ship.position == berth and ship.cargo.is_empty() and dev.materials.ore == ore + 2 and ship.charge > 100.0, "Keep side while unloading and charging")
		var packet: Dictionary = ship.snapshot()
		ship.home_direction = Vector2i.ZERO
		ship.restore(packet)
		ship.update(0.0)
		check(ship.home_direction == side and ship.position == berth, "Restore selected side")
		ship.state = "returning"
		ship.home_direction = -side
		ship.position = berth + Vector2(side) * 30.0
		check(ship.dock_position() == berth, "Return chooses closest side")
	ship.state = "manual"
	ship.position = ship.berths(Vector2i.ZERO)[Vector2i.RIGHT] + Vector2(5, 0)
	ship.velocity = Vector2(-100, 0)
	ship.charge = 500.0
	ship.manual_move(0.05, Vector2.LEFT)
	check(ship.state != "docked", "High-speed approach cannot snap into berth")
	var blocked: Dictionary = game.island_tiles[0].duplicate()
	blocked.facility = ""
	blocked.cell = Vector2i.RIGHT
	game.island_tiles.append(blocked)
	game._refresh_island_shape()
	check(not ship.berths(Vector2i.ZERO).has(Vector2i.RIGHT) and ship.berths(Vector2i.ZERO).size() == 3, "Occupied side is excluded")
	game.hazards = [{"active": true, "tiles": [{"cell": Vector2i.ZERO}], "pos": game.island_pos + Vector2(0, -68)}]
	check(not ship.berths(Vector2i.ZERO).has(Vector2i.UP), "External island also blocks berth volume")
	game.hazards = []
	ship.state = "docked"
	ship.home_direction = Vector2i.LEFT
	ship.position = ship.dock_position()
	game.saves.directory = "res://../.codex_tmp/harbor-sides-saves"
	check(game.saves.save_slot(1) and game.saves.load_slot(1) and ship.home_direction == Vector2i.LEFT, "Actual save/load preserves side")
	var data: Dictionary = game.saves.snapshot()
	data.ship.home_direction = Vector2i(1, 1)
	check(not game.saves.validate(data), "Reject invalid saved side")
	var legacy: Dictionary = ship.snapshot()
	legacy.erase("home_direction")
	ship.restore(legacy)
	check(ship.berths(Vector2i.ZERO).values().has(ship.dock_position()), "Legacy save chooses a free side")
	print("HARBOR SIDES: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
