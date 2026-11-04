extends SceneTree

var game
var checks := 0
var failures := 0
const OUT := "res://../artifacts/game/ship-rescue/"

func _init() -> void: call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)

func capture(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	game._update_hud()
	game.notice_label.text = ""
	game.queue_redraw()
	game.map_ink.queue_redraw()
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(OUT + name + ".png") == OK, "Capture " + name)

func strand() -> void:
	game.explorer.state = "returning"
	game.explorer.charge = 0.0
	game.explorer.position = game.explorer.dock_position() + Vector2(160, 0)
	game.explorer.cargo = {"ore": 12}
	game.explorer.target = {}

func catch_ship() -> void:
	game.energy = 150.0
	game.targets = []
	game._fire_hook(game.explorer.position)
	for step in range(120):
		game._update_hook(1.0 / 60.0)
		if game.explorer.towed: break
	check(game.explorer.towed, "Actual hook projectile catches stranded ship")

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	root.size = Vector2i(1152, 648)
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game._start_demo()
	game.set_process(false)
	game.set_physics_process(false)
	game.day_minutes = 600
	game.current_weather = -1
	var ship = game.explorer
	var dev = game.development
	game._update_hud()
	check(game.ship_view_button.disabled, "No ship disables follow button")
	game.coins = 100000
	dev.materials = {"wood": 4000, "stone": 3000, "ore": 2000, "magma": 400}
	dev.tech.harbor = 1
	dev.tech.exploration = 1
	dev.tech.hook = 3
	dev.tech.radar = 3
	check(dev.build(Vector2i(2, 0), "harbor") and ship.construct(), "Construct ship at real harbor")
	check(dev.build(Vector2i(2, -1), "grapple"), "Construct real hook facility")
	game.hook_max_distance = 1000.0
	strand()
	var stranded_position: Vector2 = ship.position
	ship.update(10.0)
	check(ship.position == stranded_position and ship.stranded(), "No free movement without energy")
	ship.charge = 0.1
	ship.update(10.0)
	check(ship.position.distance_to(stranded_position) <= 7.51 and ship.charge == 0.0, "Travel capped by remaining battery")
	strand()
	game.ship_view_button.pressed.emit()
	game._update_camera(1.0)
	check(game.follow_ship and game.camera_world == ship.position, "Toolbar follows ship")
	ship.position += Vector2(0, 30)
	game._update_camera(0.1)
	check(game.camera_world == ship.position, "Camera tracks moving ship without island clamp")
	await capture("01-ship-camera")
	game.ship_view_button.pressed.emit()
	check(not game.follow_ship and game.camera_world == game.island_pos, "Second click returns to island")
	game.navigation_view.toggle_map()
	check(game.navigation_view.hover_at(ship.radar_rect().get_center()).get("key") == "ship", "Radar hover recognizes ship")
	await capture("02-radar-ship")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = ship.radar_rect().get_center()
	game.navigation_view._input(click)
	check(dev.explorer_open and not game.sky_map_open, "Radar click opens ship management")
	ship.rescue_quote = ship.rescue_cost()
	dev.render_menu()
	await capture("03-rescue-confirmation")
	dev.close_menu()
	strand()
	check(ship.rescue_cost() == 5200, "Price reduced to one tenth: 5000 plus 100 per 80px")
	var before: int = game.coins
	var port: Dictionary = ship.harbor()
	port.hp = 50.0
	check(not ship.emergency_rescue(5200) and game.coins == before, "Damaged harbor cannot receive paid rescue")
	port.hp = 100.0
	port.facility = ""
	check(not ship.emergency_rescue(5200) and game.coins == before, "Ordinary ground cannot receive rescue")
	port.facility = "harbor"
	game.coins = 5199
	check(not ship.emergency_rescue(5200) and game.coins == 5199, "Insufficient funds preserve balance")
	game.coins = before
	check(not ship.emergency_rescue(5100) and game.coins == before, "Stale quote cannot charge")
	check(ship.emergency_rescue(5200) and game.coins == before - 5200, "Paid rescue charges exactly once")
	check(ship.position == ship.dock_position() and ship.charge == 0.0 and ship.load_weight() == 12, "Paid rescue preserves cargo, requires charging, lands only at harbor")
	check(not ship.emergency_rescue(5200) and game.coins == before - 5200, "Double click cannot charge twice")
	strand()
	catch_ship()
	var start: Vector2 = ship.position
	game.energy = 0.0
	game._update_hook(0.1)
	check(ship.position == start and ship.towed, "No island power pauses towing")
	game.energy = 150.0
	game._update_hook(0.1)
	check(ship.position != start and game.energy < 150.0, "Towing moves toward harbor and consumes island energy")
	game.camera_world = (ship.position + game.island_pos) * 0.5
	game.camera_zoom = 1.5
	await capture("04-hook-rescue")
	game.saves.directory = "res://../.codex_tmp/ship-rescue-saves"
	check(game.saves.save_slot(1), "Save actual active ship tow")
	ship.release_tow()
	check(game.saves.load_slot(1) and ship.towed and game.hooked_target == -1, "Restore ship tow without island target")
	var count: int = game.island_tiles.size()
	for step in range(300): game._update_hook(1.0 / 60.0)
	check(ship.state == "docked" and ship.position == ship.dock_position() and not ship.towed, "Hook docks at harbor, not workshop")
	check(game.island_tiles.size() == count and ship.load_weight() == 12, "No added tiles or lost cargo during tow")
	ship.update(0.1)
	check(ship.cargo.is_empty() and ship.charge > 0, "Harbor unloads and charges normally")
	strand()
	catch_ship()
	port = ship.harbor()
	port.hp = 50.0
	start = ship.position
	game._update_hook(0.1)
	check(not ship.towed and ship.position == start and ship.stranded(), "Port damage releases tow without teleporting")
	port.hp = 100.0
	var old_save: Dictionary = game.saves.snapshot()
	old_save.ship.erase("towed")
	check(game.saves.validate(old_save), "Pre-rescue saves remain valid")
	old_save.ship.towed = "bad"
	check(not game.saves.validate(old_save), "Reject invalid tow field")
	game.queue_free()
	await process_frame
	print("SHIP RESCUE: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
