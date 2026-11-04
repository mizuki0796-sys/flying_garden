extends SceneTree

const Tiles = preload("res://scripts/island_tiles.gd")
const Rules = preload("res://scripts/development_rules.gd")
const OUT := "res://../artifacts/game/ship-docking/"
var game
var ship
var terrain: Dictionary
var checks := 0
var failures := 0

func _init() -> void: call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)

func rock(cell: Vector2i) -> Dictionary:
	return {"cell": cell, "kind": "rock", "facility": "", "level": 1, "hp": 100.0, "depleted": false}

func contact() -> void:
	ship.state = "contact"
	ship.target = terrain
	ship.charge = 500.0
	terrain.velocity = Vector2.ZERO
	ship.velocity = Vector2.ZERO
	ship.position = Vector2(terrain.pos) - Vector2(Tiles.bounds(terrain.tiles).size.x * 0.5 + 40.1, 0)
	ship.dock_offset = ship.position - Vector2(terrain.pos)
	ship.cargo.clear()

func capture(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	game._update_hud()
	game.notice_label.text = ""
	ship.update_ui()
	game.queue_redraw()
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(OUT + name + ".png") == OK, "Capture " + name)

func write_packet(slot: int, packet: Dictionary) -> void:
	var bytes := var_to_bytes(packet)
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(bytes)
	var file := FileAccess.open(game.saves.path_for(slot), FileAccess.WRITE)
	file.store_buffer(hash.finish())
	file.store_buffer(bytes)
	file.close()

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	root.size = Vector2i(1152, 648)
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game._start_demo()
	game.set_process(false)
	game.set_physics_process(false)
	game.saves.directory = "res://../.codex_tmp/ship-docking-saves"
	ship = game.explorer
	var dev = game.development
	game.coins = 100000000
	dev.materials = {"wood": 2000000, "stone": 2000000, "ore": 2000000, "magma": 2000000}
	dev.tech.harbor = 1
	dev.tech.radar = 3
	check(not dev.research("ship_capacity"), "Capacity requires exploration research")
	dev.tech.exploration = 3
	check(dev.build(Vector2i(2, 0), "harbor") and ship.construct(), "Real harbor and ship constructed")
	terrain = game.hazards[0]
	terrain.tiles = [rock(Vector2i.ZERO), rock(Vector2i(1, 0)), rock(Vector2i(0, 1)), rock(Vector2i(1, 1))]
	terrain.pos = ship.position + Vector2(650, 0)
	terrain.active = true
	terrain.tethered = false
	terrain.shop = false
	terrain.size_class = 0
	terrain.name = "测试矿岛"
	terrain.biome = 1
	game.hazards = [terrain]
	ship.charge = 500.0
	check(ship.launch() and not ship.dock_island(), "Launch cannot dock remotely")
	for step in range(1000):
		ship.update(1.0 / 30.0)
		if ship.state == "contact": break
	check(ship.state == "contact" and ship.hp == 100.0 and ship.can_dock(), "Automatic approach stops safely at actual edge")
	check(ship.load_weight() == 0 and not terrain.tiles[0].depleted, "Contact alone never harvests")
	for step in range(120): ship.update(0.1)
	check(ship.hp == 100.0 and ship.load_weight() == 0, "Waiting never causes repeated damage or mining")
	game.camera_world = ship.position + Vector2(65, 0)
	game.camera_zoom = 1.6
	ship.update_ui()
	check(ship.dock_button.visible, "Actual button appears beside contacted ship")
	await capture("01-contact")
	check(game.saves.save_slot(1), "Save contact state")
	ship.dock_button.pressed.emit()
	check(ship.state == "mining", "Actual button confirms docking")
	check(not ship.dock_island(), "Cannot confirm twice")
	ship.update(3.01)
	check(ship.load_weight() == 8 and terrain.tiles[0].depleted, "First confirmed batch consumes a real deposit")
	ship.update(6.0)
	check(ship.load_weight() == 24 and ship.state == "returning" and not terrain.tiles[3].depleted, "Base mission stops at 24 and leaves remaining deposits")
	var before: int = dev.materials.ore
	for step in range(1000):
		ship.update(0.1)
		if ship.state == "docked": ship.update(0.0); break
	check(ship.state == "docked" and ship.load_weight() == 0 and dev.materials.ore == before + 12, "Full cargo returns and unloads at real port")
	check(game.saves.load_slot(1) and ship.state == "contact" and ship.can_dock(), "Load requires clicking contact button again")
	terrain = ship.target
	game.hazards = [terrain]
	check(ship.dock_island() and game.saves.save_slot(2), "Save confirmed docking")
	check(game.saves.load_slot(2) and ship.state == "mining", "Confirmed docking persists")
	terrain = ship.target
	game.hazards = [terrain]
	for direction in [Vector2.RIGHT, Vector2.LEFT, Vector2.DOWN, Vector2.UP]:
		terrain.velocity = Vector2.ZERO
		ship.hp = 100.0
		ship.state = "outbound"
		ship.target = terrain
		ship.position = Vector2(terrain.pos) - direction * 400.0
		ship.velocity = direction * 200.0
		ship.move_with_collisions(direction * 800.0)
		check(ship.state == "manual" and ship.hp == 40.0 and ship.built, "Fast sweep in every direction damages but does not destroy full health")
		check(absf(ship.clearance(terrain)) < 1.0, "Fast sweep cannot tunnel through island")
	ship.position = Vector2(terrain.pos) + Vector2(-400, -Tiles.bounds(terrain.tiles).size.y * 0.5 - 32)
	ship.hp = 100.0
	ship.velocity = Vector2(200, 0)
	ship.move_with_collisions(Vector2(800, 0))
	check(ship.hp == 100.0 and ship.position.x > terrain.pos.x, "Grazing along hull edge causes no collision")
	var original: Array = terrain.tiles
	terrain.tiles = [rock(Vector2i(-2, 0)), rock(Vector2i(2, 0))]
	ship.position = Vector2(terrain.pos) + Vector2(0, -300)
	ship.velocity = Vector2(0, 200)
	ship.move_with_collisions(Vector2(0, 600))
	check(ship.hp == 100.0 and ship.position.y > terrain.pos.y, "Empty gap inside island bounds does not collide")
	terrain.tiles = original
	contact()
	ship.hp = 40.0
	await capture("02-damaged")
	ship.cargo = {"ore": 12}
	ship.position = Vector2(terrain.pos) - Vector2(400, 0)
	ship.velocity = Vector2(200, 0)
	ship.move_with_collisions(Vector2(800, 0))
	check(not ship.built and ship.hp == 0.0 and ship.cargo.is_empty(), "Repeated high-speed collision destroys ship and cargo")
	check(not ship.stranded() and not ship.dock_island(), "Destroyed ship cannot be rescued or docked")
	check(game.saves.save_slot(3) and game.saves.load_slot(3) and ship.hp == 0.0 and not ship.built, "Destruction persists")
	var coins: int = game.coins
	check(ship.construct() and ship.hp == 100.0 and ship.charge == 0.0 and game.coins == coins - Rules.SHIP_BUILD_COST.coins, "Rebuilding pays full cost and restores empty ship")
	ship.hp = 41.0
	game.coins = 589
	check(not ship.repair() and ship.hp == 41.0 and game.coins == 589, "Insufficient repair funds do not alter health or money")
	game.coins = 100000000
	coins = game.coins
	var ore: int = dev.materials.ore
	check(ship.repair() and ship.hp == 100.0 and game.coins == coins - 590 and dev.materials.ore == ore - 6, "Dock repair charges missing health exactly")
	ship.hp = 50.0
	ship.state = "outbound"
	check(not ship.repair(), "Cannot repair away from port")
	ship.state = "docked"
	ship.harbor().hp = 50.0
	check(not ship.repair(), "Broken port cannot repair ship")
	ship.harbor().hp = 100.0
	ship.hp = 100.0
	terrain = game.world_sectors[terrain.world_key].hazards[terrain.world_index]
	terrain.tiles = [rock(Vector2i.ZERO), rock(Vector2i(1, 0)), rock(Vector2i(0, 1)), rock(Vector2i(1, 1))]
	game.hazards = [terrain]
	contact()
	ship.cargo = {"ore": 22}
	check(ship.dock_island(), "Part-filled hold can dock")
	var charge: float = ship.charge
	ship.update(3.01)
	check(ship.state == "overflow" and ship.load_weight() == 22 and ship.charge == charge and not terrain.tiles[0].depleted, "Overflow pauses before consuming cargo, energy or deposit")
	ship.update(30.0)
	check(ship.state == "overflow" and ship.load_weight() == 22 and ship.charge == charge, "Overflow waits indefinitely for explicit choice")
	game.camera_world = ship.position + Vector2(65, 0)
	ship.update_ui()
	check(ship.overflow_panel.visible and "无法找回" in ship.overflow_label.text, "Visible warning states irreversible loss")
	check(ship.next_batch().discarded == {"stone": 2, "ore": 4}, "Warning names exactly what will be discarded")
	await capture("04-overflow-warning")
	ship.overflow_return.pressed.emit()
	check(ship.state == "returning" and not terrain.tiles[0].depleted and ship.load_weight() == 22, "Cancel preserves cargo and unmined resource")
	contact()
	ship.cargo = {"ore": 22}
	ship.dock_island()
	ship.update(3.01)
	check(game.saves.save_slot(3) and game.saves.load_slot(3) and ship.state == "overflow", "Overflow prompt persists without treating save as consent")
	terrain = ship.target
	game.hazards = [terrain]
	ship.overflow_confirm.pressed.emit()
	check(ship.load_weight() == 24 and ship.cargo == {"ore": 22, "stone": 2}, "Confirmation keeps only available capacity")
	check(terrain.tiles[0].depleted and ship.state == "returning" and ship.charge == charge - 12.0, "Confirmed discard consumes one batch and returns full")
	check("丢弃" in game.notice_label.text and not ship.confirm_overflow(), "Discard warns again and cannot be repeated")
	contact()
	ship.cargo = {"ore": 22}
	ship.dock_island()
	ship.update(3.01)
	check(ship.state == "overflow", "Next oversized batch also needs confirmation")
	dev.tech.ship_capacity = 1
	ship.update(0.01)
	check(ship.state == "mining" and ship.load_weight() == 22, "Expansion while waiting clears shortage without discarding anything")
	dev.tech.ship_capacity = 0
	ship.state = "docked"
	ship.cargo.clear()
	ship.target = {}
	for level in range(1, 11):
		var cost: Dictionary = dev.research_cost("ship_capacity")
		coins = game.coins
		check(dev.research("ship_capacity") and ship.capacity() == Rules.SHIP_CAPACITIES[level] and game.coins == coins - cost.coins, "All ten cargo upgrades pay real cost")
		ship.cargo = {"ore": ship.capacity() / 2}
		check(is_equal_approx(ship.speed(), 75.0), "Half-full speed stays usable after expansion")
	check(not dev.research("ship_capacity") and ship.capacity() == 1000, "Hard maximum is 1000, no level eleven")
	for weight in [0, 24, 999, 1000]:
		ship.cargo = {"ore": weight}
		check(ship.cargo_state() == (0 if weight == 0 else (2 if weight == 1000 else 1)), "Cargo appearance uses upgraded capacity")
	terrain = game.world_sectors[terrain.world_key].hazards[terrain.world_index]
	terrain.active = true
	terrain.tethered = false
	terrain.shop = false
	terrain.size_class = 0
	terrain.pos = ship.dock_position() + Vector2(1500, 0)
	terrain.tiles = []
	for i in range(126): terrain.tiles.append(rock(Vector2i(i % 14, i / 14)))
	game.hazards = [terrain]
	contact()
	dev.tech.gathering = 10
	check(ship.dock_island(), "Expanded ship docks normally")
	ship.update(4.2)
	check(ship.load_weight() == 1000 and ship.state == "returning" and not terrain.tiles[125].depleted, "Real mining fills exactly 1000, leaves extra deposit")
	check(is_equal_approx(ship.charge, 464.0) and is_equal_approx(ship.speed(), 50.0), "Full expanded hold keeps mining energy and travel usable")
	check(not ship.mine_once() and ship.load_weight() == 1000, "No mining past mission capacity")
	check(game.saves.save_slot(4) and game.saves.load_slot(4) and ship.capacity() == 1000 and ship.load_weight() == 1000, "Capacity and full cargo survive saving")
	terrain = ship.target
	game.hazards = [terrain]
	ore = dev.materials.ore
	for step in range(1000):
		ship.update(0.1)
		if ship.state == "docked": ship.update(0.0); break
	check(ship.state == "docked" and ship.load_weight() == 0 and dev.materials.ore == ore + 500, "Full 1000-item cargo completes real return and unloading")
	ship.target = terrain
	ship.state = "returning"
	var packet: Dictionary = game.saves.snapshot()
	for bad_hp in [-1.0, 101.0, NAN, 50]:
		packet.ship.hp = bad_hp
		check(not game.saves.validate(packet), "Invalid health rejected")
	packet.ship.hp = 100.0
	packet.ship.cargo = {"ore": 1001}
	check(not game.saves.validate(packet), "Overfilled save rejected")
	packet.ship.cargo = {}
	packet.tech.ship_capacity = 11
	check(not game.saves.validate(packet), "Invalid capacity level rejected")
	packet.tech.erase("ship_capacity")
	packet.ship.erase("hp")
	packet.ship.erase("dock_offset")
	packet.ship.state = "mining"
	packet.ship.position = terrain.pos
	check(game.saves.validate(packet), "Old ship save accepted")
	write_packet(5, packet)
	check(game.saves.load_slot(5) and ship.capacity() == 24 and ship.hp == 100.0 and ship.state == "outbound", "Legacy ship gets base hold, full health, and must dock again")
	check(ship.clearance(ship.target) >= 0.0, "Legacy center-of-island position is safely moved outside collision volume")
	dev.tech.ship_capacity = 9
	dev.toggle(true)
	var ui = dev.content.get_node("TechnologyTree")
	ui.set_process(false)
	ui.jump_to("ship_capacity")
	await capture("03-capacity-tech")
	await process_frame
	ui._place_card()
	check(ui.get_global_rect().encloses(ui.card.get_global_rect()), "Level ten price and capacity fit technology card")
	dev.close_menu()
	game.queue_free()
	await process_frame
	print("SHIP DOCKING: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
