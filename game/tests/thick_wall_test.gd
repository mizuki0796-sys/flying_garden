extends SceneTree

const Wall = preload("res://scripts/thick_wall.gd")
const Tiles = preload("res://scripts/island_tiles.gd")
const Rules = preload("res://scripts/development_rules.gd")
var game
var checks := 0
var failures := 0

func _init() -> void: call_deferred("run")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)

func hit(speed := 100.0) -> void:
	game.island_pos = game.world_origin + Vector2(0, Wall.NEAR - game.wall.depth - game.island_bounds.position.y - 1.0)
	game.island_velocity = Vector2(0, -speed)
	game.wall.collide_island()

func repair_all() -> void:
	for tile in game.island_tiles: tile.hp = Rules.tile_max_hp(tile)

func capture(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	game.camera_world = game.island_pos
	game._update_hud()
	game.queue_redraw()
	game.map_ink.queue_redraw()
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var folder := ProjectSettings.globalize_path("res://../artifacts/game/thick-wall")
	DirAccess.make_dir_recursive_absolute(folder)
	check(root.get_texture().get_image().save_png(folder.path_join(name + ".png")) == OK, "Capture " + name)

func run() -> void:
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game._start_demo()
	game.wall = Wall.new(game) # Regression coverage for saves with the original straight wall.
	game.active_sector = Vector2i(2147483647,2147483647)
	game._update_world_stream()
	game.set_process(false)
	game.set_physics_process(false)
	game.saves.directory = "res://../.codex_tmp/wall-test-saves"
	check(game.wall.enabled and game.wall.depth == 0.0, "New game has an untouched wall")
	for terrain in game.hazards: check(game.wall.keep_terrain(terrain), "No generated islands inside or outside wall")
	await capture("01-start")
	var count: int = game.island_tiles.size()
	hit(10.0)
	check(game.wall.depth == 0.0 and game.island_velocity.y == 0.0, "Slow contact blocks without progress")
	check(game.island_pos.y + game.island_bounds.position.y > game.world_origin.y + Wall.NEAR, "Overlap resolved")
	hit()
	check(game.wall.depth > 0.0 and game.wall.depth < Wall.STAGES[0], "Impact advances but does not award every hit")
	check(game.island_tiles.size() == count, "Wall damage preserves tiles and facilities")
	check(game.island_tiles.any(func(tile): return tile.hp < Rules.tile_max_hp(tile)), "Impact costs durability")
	check(game.development.tile_at(Vector2i(0,-1)).hp == 77.0, "North impact transmits 23 damage south to the second row")
	var depth: float = game.wall.depth
	hit()
	check(game.wall.depth == depth, "Cooldown prevents repeat hits")
	var weak_cell := Vector2i(-2, -2)
	game.development.tile_at(weak_cell).hp = 1.0
	game.collision_cooldown = 0.0
	hit()
	check(game.development.tile_at(weak_cell).is_empty(), "Lethal wall impact removes its tile")
	depth = game.wall.depth
	game.development.materials = {"wood": 9999, "stone": 9999, "ore": 9999, "magma": 9999}
	game.coins = 99999
	var leading_cell := Vector2i(-1, -2)
	check(game.development.repair(leading_cell), "Existing repair restores leading tile")
	game.collision_cooldown = 0.0
	hit()
	check(game.wall.depth > depth, "Repaired tiles can advance again")
	repair_all()
	game.wall.depth = 150.0
	game.collision_cooldown = 0.0
	hit()
	check(game.wall.journal().contains(Wall.RECORDS[0]), "Threshold unlocks persistent clue")
	var survey_target: Dictionary = game.targets[0]
	game.rice_stock = 10
	game.hook_max_distance = 100000.0
	check(game.development.survey(survey_target), "Existing survey grants a wall rumor")
	game.development.survey(survey_target)
	check(game.wall.rumors == 1 and game.wall.journal().contains(Wall.RUMORS[0]), "Exploration rumor is readable")
	await capture("02-breach")
	var packet: Dictionary = game.saves.snapshot()
	check(game.saves.validate(packet), "Wall save validates")
	check(game.saves.save_slot(1), "Save wall progress")
	depth = game.wall.depth
	game.wall.depth = 0.0
	check(game.saves.load_slot(1), "Load wall save")
	check(game.wall.depth == depth and game.wall.rumors == 1, "Progress and lore survive load")
	var bad: Dictionary = packet.duplicate(true)
	bad.wall.depth = NAN
	check(not game.saves.validate(bad), "Reject nonfinite depth")
	bad.wall = {"enabled": true, "depth": 0.0, "rumors": 0, "crossed": true}
	check(not game.saves.validate(bad), "Reject premature crossing")
	packet.erase("wall")
	check(game.saves.validate(packet), "Old saves remain valid")
	game.wall.restore({})
	check(not game.wall.enabled and game.wall.solids(Rect2(-5000, -5000, 10000, 10000)).is_empty(), "Old saves preserve geography")
	game.wall.restore({"enabled": true, "depth": depth, "rumors": 1, "crossed": false})
	var ship = game.explorer
	ship.built = true
	ship.state = "manual"
	ship.position = game.world_origin + Vector2(0, Wall.NEAR - depth + 100)
	ship.velocity = Vector2(0, -100)
	game.hazards = []
	game.island_pos = game.world_origin + Vector2(1000, 1000)
	ship.move_with_collisions(Vector2(0, -2000))
	check(ship.position.y > game.world_origin.y + Wall.NEAR - depth and game.wall.depth == depth, "Fast ship cannot bypass or damage wall")
	ship.position = game.world_origin + Vector2(0, Wall.NEAR - depth - 5)
	ship.move_with_collisions(Vector2.ZERO)
	check(ship.position.y > game.world_origin.y + Wall.NEAR - depth, "Overlapping ship separates from wall")
	ship.built = false
	for attempt in range(20):
		repair_all()
		game.collision_cooldown = 0.0
		hit()
		if game.wall.depth == Wall.THICKNESS: break
	check(game.wall.depth == Wall.THICKNESS, "Repeated repaired impacts open the complete thickness")
	game.island_pos = game.world_origin + Vector2(0, Wall.NEAR - Wall.THICKNESS - 200)
	game.wall.collide_island()
	check(game.wall.crossed, "Entire island can cross completed opening")
	game.merchant_available = true
	game._update_merchant(1.0)
	check(not game.merchant_available, "No merchant follows into lifeless exterior")
	game.merchant_arrival_left = 0.0
	game._update_merchant(1000.0)
	check(not game.merchant_available, "No new exterior visitor spawns")
	check(game.wall.journal().contains(Wall.RECORDS[3]), "Final record remains available")
	await capture("03-outside")
	game.island_pos = game.world_origin
	game.wall.collide_island()
	check(game.island_pos == game.world_origin and game.wall.crossed, "Return through opening retains completion")
	game._update_merchant(1.0)
	check(game.merchant_available, "Merchants resume after returning inside")
	game.island_pos = game.world_origin + Vector2(1000, Wall.NEAR - game.island_bounds.position.y - 1)
	game.island_velocity = Vector2(0, -100)
	game.wall.collide_island()
	check(game.island_pos.y + game.island_bounds.position.y > game.world_origin.y + Wall.NEAR, "Wall beside opening remains solid")
	game.island_pos = game.world_origin
	game.sky_map_open = true
	game.development.tech.radar = 3
	game.map_center = game.world_origin + Vector2(0, -400)
	await capture("04-map")
	game.sky_map_open = false
	game.guide_panel.show()
	await capture("05-journal")
	game.wall.depth = 0.0
	game.wall.crossed = false
	game.island_pos = game.world_origin + Vector2(0, Wall.NEAR - game.island_bounds.position.y + 1.0)
	game.island_velocity = Vector2(0, -100)
	game.collision_cooldown = 0.0
	repair_all()
	game.development.tile_at(Vector2i(0, 2)).facility = "power"
	game.development.tech.engine = 1
	game._apply_movement(0.1, Vector2.ZERO, false)
	check(game.wall.depth > 0.0, "Real movement invokes wall impact")
	var terrain := {"pos": game.world_origin + Vector2(0, Wall.NEAR - 1), "tiles": [game.island_tiles[0].duplicate()], "velocity": Vector2(0, -100), "active": true}
	game.hazards = [terrain]
	game.wall.depth = 0.0
	game.wall.collide_terrain()
	check(terrain.pos.y - 32.0 > game.world_origin.y + Wall.NEAR and terrain.velocity.y == 0, "Wild islands cannot drift into wall")
	game.hazards = []
	print("THICK_WALL_TEST checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
