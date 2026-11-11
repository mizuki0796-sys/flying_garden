extends SceneTree
const Tiles = preload("res://scripts/island_tiles.gd")
const Physics = preload("res://scripts/island_physics.gd")
var game
var checks := 0
var failures := 0
func _init() -> void: call_deferred("run")
func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(text)
func tile(cell := Vector2i.ZERO) -> Dictionary:
	return {"cell": cell, "kind": "grass", "facility": "", "level": 1, "hp": 100.0, "depleted": false}
func island(pos: Vector2, count := 1) -> Dictionary:
	var cells: Array = []
	for i in range(count): cells.append(tile(Vector2i(0, i)))
	return {"pos": pos, "tiles": cells, "active": true, "tethered": false, "velocity": Vector2.ZERO, "radius": 100.0}
func capture(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	game.queue_redraw()
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../artifacts/game/inertia/" + name + ".png")) == OK, "Capture " + name)
func run() -> void:
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game._start_demo()
	game.wall.enabled = false # Synthetic collision fixtures use coordinates occupied by the new wall.
	game.set_process(false)
	game.set_physics_process(false)
	game.hazards = []
	game.targets = []
	var ship = game.explorer
	ship.built = true
	ship.state = "manual"
	ship.charge = 500.0
	ship.position = game.island_pos + Vector2(2000, 0)
	ship.manual_move(0.1, Vector2.RIGHT)
	check(ship.velocity.x > 0 and ship.velocity.x < ship.speed(), "Ship accelerates rather than jumping to cruise")
	var first: float = ship.velocity.x
	ship.manual_move(0.1, Vector2.RIGHT)
	check(ship.velocity.x > first, "Holding thrust builds speed")
	var point: Vector2 = ship.position
	var speed: float = ship.velocity.length()
	ship.manual_move(0.1, Vector2.ZERO)
	check(ship.position.x > point.x and ship.velocity.length() < speed and ship.velocity.length() > 0, "Release drifts and decelerates")
	ship.manual_move(5.0, Vector2.ZERO)
	check(ship.velocity.is_zero_approx(), "Passive braking eventually stops")
	ship.velocity = Vector2.ZERO
	ship.cargo = {"ore": ship.capacity()}
	ship.manual_move(0.1, Vector2.RIGHT)
	check(ship.velocity.x < first, "Cargo mass reduces acceleration")
	ship.cargo = {}
	ship.velocity = Vector2(100, 0)
	ship.manual_move(0.1, Vector2.LEFT)
	check(ship.velocity.x > 0 and ship.velocity.x < 100, "Reverse thrust brakes before reversing")
	ship.charge = 0.0
	point = ship.position
	ship.manual_move(0.1, Vector2.RIGHT)
	check(ship.position.x > point.x and ship.velocity.x > 0, "Power loss preserves decaying momentum")
	ship.built = false
	game.island_tiles = [tile()]
	game.plots = []
	game._refresh_island_shape()
	game.island_pos = Vector2.ZERO
	var light := island(Vector2(79, 0))
	game.hazards = [light]
	game.island_velocity = Vector2(20, 0)
	game._check_collisions()
	check(light.velocity.x > 0 and game.island_velocity.x < 20, "Gentle contact transfers momentum")
	check(is_equal_approx(light.velocity.x + game.island_velocity.x, 20.0), "Contact conserves momentum")
	check(light.tiles[0].hp == 100.0 and game.island_tiles[0].hp == 100.0, "Gentle push causes no damage")
	var light_speed: float = light.velocity.x
	point = light.pos
	Physics.move_wild([light], 0.5, 0.15)
	check(light.pos.x > point.x and light.velocity.x > 0 and light.velocity.x < light_speed, "Unconnected island coasts after push")
	var heavy := island(Vector2(79, 0), 5)
	game.island_pos = Vector2.ZERO
	game.island_velocity = Vector2(20, 0)
	game.hazards = [heavy]
	game._check_collisions()
	check(heavy.velocity.x > 0 and heavy.velocity.x < light_speed, "Heavier island resists identical push")
	var a := island(Vector2.ZERO)
	var b := island(Vector2(79, 0))
	a.velocity = Vector2(100, 0)
	Physics.move_wild([a, b], 0.0, 0.15)
	check(a.tiles[0].hp < 100.0 and b.tiles[0].hp < 100.0, "Wild islands both take high-speed damage")
	check(b.velocity.x > 0, "Wild island collision transfers motion")
	game.island_tiles = [tile(), tile(Vector2i(0, 1))]
	game.island_tiles[1].facility = "water"
	game.island_tiles[1].core = true
	game._refresh_island_shape()
	game.island_pos = Vector2.ZERO
	game.island_velocity = Vector2.ZERO
	var incoming := island(Vector2(79, 0))
	incoming.velocity = Vector2(-100, 0)
	game.hazards = [incoming]
	game.collision_cooldown = 0.0
	game._check_collisions()
	check(incoming.tiles[0].hp < 100.0 and game.island_tiles.size() < 2, "Incoming island damages both sides even with stationary player")
	game.island_tiles = [tile()]
	game._refresh_island_shape()
	game.island_pos = Vector2.ZERO
	var core := tile(Vector2i.LEFT)
	core.facility = "water"
	core.core = true
	game.island_tiles.append(core)
	game.island_tiles[0].facility = "power"
	game._refresh_island_shape()
	game.development.tech.engine = 1
	game.movement_settings.base_thrust = 240.0
	game.island_velocity = Vector2(1000, 0)
	game.hazards = [island(Vector2(200, 0))]
	game._apply_movement(0.5, Vector2.ZERO, false)
	check(game.hazards[0].velocity.x > 0, "Substeps prevent island tunnelling")
	ship.built = true
	ship.hp = 100.0
	ship.charge = 500.0
	ship.state = "manual"
	ship.position = Vector2(1000, 0)
	ship.velocity = Vector2(100, 0)
	var struck := island(Vector2(1100, 0))
	game.hazards = [struck]
	ship.move_with_collisions(Vector2(100, 0))
	check(ship.hp < 100.0 and struck.tiles[0].hp < 100.0 and struck.velocity.x > 0, "Ship collision damages both and pushes island")
	check(not ship.can_dock(), "Fast impact cannot immediately dock")
	var saved: Dictionary = ship.snapshot()
	ship.restore(saved)
	check(ship.velocity == saved.velocity, "Ship velocity survives restore")
	saved.erase("velocity")
	ship.restore(saved)
	check(ship.velocity == Vector2.ZERO, "Legacy ship saves default to rest")
	var pool = preload("res://scripts/sector_pool.gd").new()
	var sector: Dictionary = pool.acquire(Vector2i(0, -1), Vector2.ZERO)
	sector.hazards[0].velocity = Vector2(12, 3)
	sector.hazards[0].tiles[0].hp = 55.0
	pool.release(Vector2i(0, -1), sector)
	sector = pool.acquire(Vector2i(0, -1), Vector2.ZERO)
	check(sector.hazards[0].velocity == Vector2(12, 3) and sector.hazards[0].tiles[0].hp == 55.0, "Sector unload and reload preserve inertia and damage")
	game.world_sectors[Vector2i(0, -1)] = sector
	var packet: Dictionary = game.saves.snapshot()
	check(game.saves.validate(packet), "Inertial world snapshot remains valid")
	game.saves.directory = "res://../.codex_tmp/inertia-saves"
	ship.velocity = Vector2(18, 4)
	check(game.saves.save_slot(1) and game.saves.load_slot(1) and ship.velocity == Vector2(18, 4), "Actual save/load retains ship momentum")
	check(game.world_sectors[Vector2i(0, -1)].hazards[0].velocity == Vector2(12, 3), "Actual save/load retains island momentum")
	packet.ship.velocity = Vector2(NAN, 0)
	check(not game.saves.validate(packet), "Reject non-finite ship velocity in saves")
	packet = game.saves.snapshot()
	packet.sectors[Vector2i(0, -1)].hazards[0].velocity = Vector2(INF, 0)
	check(not game.saves.validate(packet), "Reject non-finite island velocity in saves")
	if DisplayServer.get_name() != "headless":
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://../artifacts/game/inertia"))
		root.size = Vector2i(1152, 648)
		game.island_tiles = Tiles.initial_tiles()
		game._refresh_island_shape()
		game.development.sync()
		game.island_pos = Vector2.ZERO
		ship.built = false
		game.current_weather = -1
		game.day_minutes = 600
		game.animation_time = 2.35
		game.development.tech.radar = 3
		var neighbor: Dictionary = sector.hazards[0].duplicate(true)
		neighbor.tiles = Tiles.wild_tiles(3, 1)
		neighbor.biome = 3
		neighbor.pos = Vector2(279, 0)
		neighbor.velocity = Vector2.ZERO
		game.hazards = [neighbor]
		game.camera_world = Vector2(100, 0)
		game.camera_zoom = 1.4
		game.camera_zoom_target = 1.4
		game.island_velocity = Vector2(80, 0)
		game.collision_cooldown = 0.0
		game.notice_label.text = ""
		await capture("01-before-impact")
		game._check_collisions()
		game._update_hud()
		await capture("02-both-damaged")
		var start: Vector2 = neighbor.pos
		Physics.move_wild(game.hazards, 1.0, 0.15)
		check(neighbor.pos.x > start.x, "Preview island keeps drifting after collision")
		await capture("03-island-coasting")
	print("INERTIA: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
