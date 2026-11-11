extends SceneTree

const Ring = preload("res://scripts/ring_wall.gd")
var game
var failures := 0
func _init() -> void: call_deferred("run")

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func capture(file: String) -> void:
	if DisplayServer.get_name() == "headless": return
	game.queue_redraw()
	for i in range(3):
		await process_frame
		await RenderingServer.frame_post_draw
	var folder := ProjectSettings.globalize_path("res://../artifacts/game/ring-wall")
	DirAccess.make_dir_recursive_absolute(folder)
	check(root.get_texture().get_image().save_png(folder.path_join(file+".png")) == OK,"capture")

func check_recoil(contact: Vector2, speed: float, expected: Array, reinforcement := 0, gap := false) -> void:
	game.wall.hp_left.clear()
	# Leave only one wall cell in contact with the five-wide bow.
	for y in [-2, -1, 1, 2]:
		game.wall.hp_left[Vector2i(10000,y)] = 0.0
	var bow := Vector2i(2,0)
	game.development.tile_at(bow).reinforcement = reinforcement
	for tile in game.island_tiles: tile.hp = Ring.Rules.tile_max_hp(tile)
	if gap: game.development.destroy_tile(bow + Vector2i.LEFT)
	var mass: float = game.island_mass
	game.island_pos = contact
	game.camera_world = contact
	game.collision_cooldown = 0.0
	game.island_velocity = Vector2(speed, 150)
	game.wall.collide_island()
	for tile in game.island_tiles:
		var cell: Vector2i = tile.cell
		var damage: int = expected[bow.x-cell.x] if cell.y == 0 else 0
		check(tile.hp == Ring.Rules.tile_max_hp(tile)-damage,"recoil at %s, normal speed %s" % [cell,speed])
	var wall_hp: float = game.wall.hp_left.get(Vector2i(10000,0),Ring.max_hp(0))
	var expected_wall_hp := maxf(0.0,Ring.max_hp(0)-mass*speed) if speed >= Ring.MIN_SPEED else Ring.max_hp(0)
	check(is_equal_approx(wall_hp,expected_wall_hp),"only direct contact damages the wall")

func run() -> void:
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game._start_demo()
	game.set_process(false)
	game.set_physics_process(false)
	var spawn: Vector2 = game.world_origin
	var origin: Vector2 = game.wall.ring_center()
	check(game.island_pos == spawn and (spawn-origin)/Ring.SIZE == Vector2(0,-9994),"spawn six cells inside north wall")
	for direction in [Vector2.RIGHT,Vector2.LEFT,Vector2.UP,Vector2.DOWN]:
		var widths := [0,0,0,0,0]
		for r in range(9998,10018):
			var cell := Vector2i((direction*(r+0.5)).floor())
			var k := Ring.layer(cell)
			var area := Rect2(origin+Vector2(cell)*Ring.SIZE+Vector2.ONE,Vector2.ONE)
			check(game.wall.solids(area).is_empty() == (k < 0),"collision matches cell")
			if k >= 0: widths[k] += 1
		check(widths == [5,4,3,2,1],"radial widths")
	var legacy := Ring.new(game)
	var old_state: Dictionary = game.wall.snapshot()
	old_state.erase("near_wall_spawn")
	old_state.erase("hp_scale")
	old_state.cells = {Vector2i(10000,0): 0.0, Vector2i(10014,0): 550.0}
	old_state.depth = 1.0
	check(Ring.valid_ring(old_state),"legacy damage validates at original scale")
	legacy.restore(old_state)
	check(legacy.hp_left[Vector2i(10000,0)] == 0.0 and legacy.hp_left[Vector2i(10014,0)] == 5500.0,"legacy breaches and remaining health fractions persist")
	for k in range(5):
		check(Ring.max_hp(k) == [3000,5000,7000,9000,11000][k],"material health")
	check(legacy.ring_center() == spawn,"older ring saves keep their centered geography")
	check(game.wall.solids(Rect2(spawn+game.island_bounds.position,game.island_bounds.size)).is_empty(),"spawn is open")
	var contact: Vector2 = origin+Vector2(800000-game.island_bounds.end.x+1,32)
	game.island_pos = contact
	game.camera_world = origin+Vector2(800000,32)
	game.camera_zoom = 0.38
	game._update_world_stream()
	game._update_hud()
	await capture("01-intact")
	game.island_velocity = Vector2(10,0)
	game.wall.collide_island()
	check(game.wall.hp_left.is_empty() and game.island_velocity.x == 0,"slow contact blocked")
	game.island_pos = contact
	game.island_velocity = Vector2(36,0)
	game.wall.collide_island()
	check(not game.wall.hp_left.is_empty(),"normal impact damages individual cells")
	check(game.island_tiles.any(func(t): return t.hp < 100.0),"impact costs island hp")
	var partial: Dictionary = game.wall.hp_left.duplicate()
	game.saves.directory = "res://../.codex_tmp/ring-wall-test-saves"
	check(game.saves.save_slot(1) and game.saves.load_slot(1),"partial damage save roundtrip")
	check(game.wall.ring_center() == origin and game.wall.hp_left == partial,"origin and damage persisted")
	game.island_pos = contact
	game.island_velocity = Vector2(100,0)
	game.collision_cooldown = 0.0
	game.wall.collide_island()
	var cell := Vector2i(10000,0)
	check(game.wall.hp_left[cell] > 0 and game.wall.hp_left[cell] < partial[cell],"reinforced wall withstands another impact")
	for attempt in range(40):
		if game.wall.hp_left[cell] == 0.0: break
		for tile in game.island_tiles: tile.hp = Ring.Rules.tile_max_hp(tile)
		game.island_pos = contact
		game.island_velocity = Vector2(100,0)
		game.collision_cooldown = 0.0
		game.wall.collide_island()
	check(game.wall.hp_left.get(cell,-1.0) == 0.0,"east wood tile removed")
	var hole := Rect2(origin+Vector2(cell)*Ring.SIZE+Vector2.ONE,Vector2.ONE)
	check(game.wall.solids(hole).is_empty() and not game.wall.solids(Rect2(hole.position+Vector2(80,0),hole.size)).is_empty(),"hole is open and next layer still solid")
	await capture("02-impact")
	check(game.saves.save_slot(1) and game.saves.load_slot(1) and game.wall.solids(hole).is_empty(),"hole persists on load")
	var invalid: Dictionary = game.saves.snapshot()
	invalid.wall.cells[Vector2i.ZERO] = 0.0
	check(not game.saves.validate(invalid),"reject damage outside ring")
	var ship = game.explorer
	ship.position = origin+Vector2(800000-120,64*8)
	ship.move_with_collisions(Vector2(2200,0))
	check(ship.position.x < origin.x+800000,"swept ship cannot pass unbroken east wall")
	# Exercise the normal driver at the next row with enough propulsion for the outer-zone speed limit.
	game.hazards = []
	game.targets = []
	game.island_tiles[0].facility = "power"
	game.island_tiles[0].level = 4
	game.development.tech.engine = 2
	game.island_pos = contact+Vector2(79-1,0)
	game.island_velocity = Vector2(70,0)
	game.collision_cooldown = 0
	game._apply_movement(0.08,Vector2.RIGHT,false)
	check(game.wall.hp_left.has(Vector2i(10001,0)),"movement damages the next wall row")
	game.map_center = origin+Vector2(800000,0)
	game.sky_map_open = true
	game.map_ink.queue_redraw()
	await capture("04-map")
	game.sky_map_open = false
	game.camera_zoom = 0.38
	game.camera_world = origin+Vector2(7075,7075)*Ring.SIZE
	await capture("03-diagonal")
	check_recoil(contact,34.9,[0,0,0,0,0])
	check_recoil(contact,35,[13,0,0,0,0])
	check_recoil(contact,55,[23,12,0,0,0])
	check_recoil(contact,75,[33,17,8,0,0])
	check_recoil(contact,95,[43,22,11,5,0])
	check_recoil(contact,115,[53,27,13,7,3])
	check_recoil(contact,75,[19,9,5,0,0],5)
	check_recoil(contact,115,[53,0,0,0,0],0,true)
	game.island_pos = spawn
	game.camera_world = spawn
	print("RING_WALL_TEST failures=",failures)
	quit(1 if failures else 0)
