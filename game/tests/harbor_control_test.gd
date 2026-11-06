extends SceneTree

const Tiles = preload("res://scripts/island_tiles.gd")
class Preview extends "res://scripts/main.gd":
	var original_port := false
	func _draw_harbor(canvas: Node2D, center: Vector2, cell: Vector2i, tiles: Array) -> void:
		if original_port:
			canvas.draw_texture_rect(harbor_visual.texture, Rect2(center - Vector2(40, 32), Vector2(80, 64)), false)
		else:
			super._draw_harbor(canvas, center, cell, tiles)
var game
var failures := 0
var checks := 0
func _init() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func capture(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	game.queue_redraw()
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../artifacts/game/harbor-control/" + name + ".png"))
func run() -> void:
	root.size = Vector2i(1152, 648)
	game = Preview.new()
	root.add_child(game)
	await process_frame
	game._start_demo()
	game.set_process(false)
	game.set_physics_process(false)
	game.hazards = []
	game.targets = []
	game.zones = []
	game.current_weather = -1
	game.weather_tint = 0.0
	game.day_minutes = 600
	game.animation_time = 2.35
	game.wind_strength = 0.14
	game.coins = 1000000
	var dev = game.development
	dev.materials = {"wood": 100000, "stone": 100000, "ore": 100000, "magma": 10000}
	dev.tech.harbor = 1
	dev.tech.exploration = 1
	dev.tech.radar = 3
	check(dev.build(Vector2i(2, 0), "harbor"), "First port")
	check(dev.build(Vector2i(0, -2), "harbor"), "Second port unrestricted")
	var menu = dev.tile_menu
	check(menu.actions_for(Vector2i(2, 0)) == ["ship_repair", "ship_build"], "Exactly two harbor actions")
	menu.open_at(Vector2i(0, -2))
	check(menu.activate("ship_build"), "Construct through actual menu")
	var ship = game.explorer
	check(ship.harbor().cell == Vector2i(0, -2), "Ship uses clicked harbor")
	menu.open_at(Vector2i(2, 0))
	check(not menu.activate("ship_build"), "Second ship rejected at another harbor")
	menu.close()
	ship.hp = 50.0
	menu.open_at(Vector2i(0, -2))
	check(menu.activate("ship_repair") and ship.hp == 100.0, "Repair through menu")
	ship.charge = 500.0
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = game._world_to_screen(ship.position)
	game._unhandled_input(click)
	check(game.follow_ship and game.camera_world == ship.position, "Click ship takes control and camera")
	var before: Vector2 = ship.position
	Input.action_press("move_up")
	game._physics_process(0.1)
	Input.action_release("move_up")
	check(ship.position.y < before.y and ship.state == "manual", "WASD moves ship")
	check(game.island_velocity.is_zero_approx(), "WASD does not drive main island")
	Input.action_press("move_up")
	for step in range(12): ship.update(1.0 / 60.0)
	Input.action_release("move_up")
	check(not ship.exhaust.is_empty(), "Manual flight retains existing propulsion effects")
	before = ship.position
	ship.update(0.1)
	check(ship.position != before and ship.velocity.length() > 0.0, "Release keys retains inertia while braking")
	ship.position = ship.dock_position() + Vector2(0, -5)
	ship.velocity = Vector2(0, 10)
	ship.manual_move(0.2, Vector2.DOWN)
	var home := {"pos": game.island_pos + Tiles.bounds(game.island_tiles).get_center(), "tiles": game.island_tiles}
	check(ship.clearance(home) >= -0.01, "Fast manual movement cannot tunnel through home")
	check(ship.state == "docked" and ship.harbor().cell == Vector2i(0, -2), "Return to berth docks")
	ship.update(0.0)
	ship.hp = 100.0
	ship.home_cell = Vector2i(2, 0)
	ship.position = ship.dock_position() + Vector2(5, 0)
	ship.velocity = Vector2(-10, 0)
	ship.manual_move(0.2, Vector2.LEFT)
	check(ship.state == "docked" and ship.harbor().cell == Vector2i(2, 0), "Manual docking works at another port")
	var wild := {"pos": game.island_pos + Vector2(800, 0), "active": true, "tethered": true, "tiles": [{"cell": Vector2i.ZERO, "kind": "grass", "facility": "", "hp": 100.0}]}
	game.hazards = [wild]
	ship.hp = 100.0
	ship.charge = 500.0
	ship.position = wild.pos + Vector2(200, 0)
	ship.manual_move(10.0, Vector2.LEFT)
	check(ship.clearance(wild) >= -0.01, "Tethered ordinary land blocks the hull")
	ship.hp = 100.0
	ship.charge = 0.0
	ship.position = wild.pos + Vector2(200, 0)
	ship.state = "returning"
	ship.towed = true
	dev.tech.hook = 1
	dev.tile_at(Vector2i(1, 0)).facility = "grapple"
	game.energy = 150.0
	ship.update_tow(10.0)
	check(ship.clearance(wild) >= -0.01 and not ship.towed, "Tow stops at obstructing terrain")
	ship.hp = 100.0
	ship.charge = 100.0
	ship.state = "manual"
	ship.target = {}
	game.saves.directory = "res://../.codex_tmp/harbor-control-saves"
	check(game.saves.save_slot(1) and game.saves.load_slot(1), "Manual flight roundtrips save")
	check(ship.state == "manual" and ship.home_cell == Vector2i(2, 0), "Flight and selected port retained")
	game.hazards = []
	ship.position = ship.dock_position()
	ship.state = "docked"
	ship.hp = 100.0
	game.camera_world = game.island_pos + Vector2(150, -20)
	game.camera_zoom = 3.0
	game.camera_zoom_target = 3.0
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://../artifacts/game/harbor-control"))
	game.notice_label.text = ""
	await capture("01-port-perspective")
	if DisplayServer.get_name() != "headless":
		var after: Image = root.get_texture().get_image()
		game.original_port = true
		await capture("00-original-projection")
		var before_image: Image = root.get_texture().get_image()
		var unchanged := true
		for y in range(after.get_height()):
			for x in range(after.get_width()):
				var world: Vector2 = game._screen_to_world(Vector2(x, y))
				var permitted := false
				for tile in game.island_tiles:
					if tile.facility == "harbor" and Tiles.cell_rect(game.island_pos, tile.cell).grow(1).has_point(world):
						permitted = true
				if not permitted and after.get_pixel(x, y) != before_image.get_pixel(x, y): unchanged = false
		check(unchanged, "Pixels outside harbor footprints remain identical")
		game.original_port = false
	click.button_index = MOUSE_BUTTON_RIGHT
	click.position = game._world_to_screen(game.island_pos + Vector2(160, 0))
	game._unhandled_input(click)
	check(menu.is_open() and menu.buttons.size() == 2, "Right click opens two-option port popup")
	await capture("02-port-menu")
	menu.close()
	game._toggle_ship_view()
	check(game.follow_ship, "Ship view can be re-entered after loading")
	game._toggle_ship_view()
	check(not game.follow_ship, "Ship button returns to island control")
	if DisplayServer.get_name() != "headless":
		game.camera_world = ship.position
		game.camera_zoom = 3.0
		ship.hp = 60.0
		ship.charge = 175.0
		var anchor: Vector2 = game._world_to_screen(ship.position + Vector2(-40, -70))
		var status_region := Rect2i(Vector2i(anchor), Vector2i(240, 105))
		await capture("03-ship-status-hidden")
		var hidden: Image = root.get_texture().get_image().get_region(status_region)
		game.follow_ship = true
		await capture("04-ship-status-controlled")
		var shown: Image = root.get_texture().get_image().get_region(status_region)
		check(hidden.get_data() != shown.get_data(), "Taking control displays ship status")
		ship.hp = 20.0
		ship.charge = 50.0
		await capture("05-ship-status-consumed")
		var changed: Image = root.get_texture().get_image().get_region(status_region)
		check(shown.get_region(Rect2i(0, 0, 240, 48)).get_data() != changed.get_region(Rect2i(0, 0, 240, 48)).get_data(), "Health display updates")
		check(shown.get_region(Rect2i(0, 48, 240, 57)).get_data() != changed.get_region(Rect2i(0, 48, 240, 57)).get_data(), "Energy display updates as charge is consumed")
		game.follow_ship = false
		await capture("06-ship-status-released")
		check(hidden.get_data() == root.get_texture().get_image().get_region(status_region).get_data(), "Both displays disappear after releasing control")
	print("HARBOR CONTROL: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
