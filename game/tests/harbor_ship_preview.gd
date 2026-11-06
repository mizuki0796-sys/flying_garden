extends SceneTree

const OUT := "res://../artifacts/game/collector-states/"
const Tiles = preload("res://scripts/island_tiles.gd")
var game

func _init() -> void: call_deferred("run")

func capture(name: String) -> void:
	game.notice_label.text = ""
	game._update_hud()
	game.queue_redraw()
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var error := root.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT + name + ".png"))
	assert(error == OK, "Screenshot must save successfully")

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	root.size = Vector2i(1152, 648)
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game._start_demo()
	game.set_process(false)
	game.set_physics_process(false)
	game.targets = []
	game.hazards = []
	game.zones = []
	game.current_weather = -1
	game.weather_tint = 0.0
	game.day_minutes = 600
	game.animation_time = 2.35
	game.wind_strength = 0.14
	game.coins = 38000
	game.development.materials = {"wood": 2100, "stone": 1500, "ore": 1000, "magma": 200}
	game.development.tech.harbor = 1
	game.development.tech.exploration = 1
	game.development.tech.radar = 3
	assert(not game.explorer.construct(), "Ordinary terrain cannot provide ship docking")
	var original_tile: Dictionary = game.development.tile_at(Vector2i(2, 0)).duplicate(true)
	var original_count: int = game.island_tiles.size()
	var port_built: bool = game.development.build(Vector2i(2, 0), "harbor")
	assert(port_built, "Build the real harbor on a perimeter tile")
	var installed: Dictionary = game.development.tile_at(Vector2i(2, 0))
	assert(installed.kind == original_tile.kind and installed.cell == original_tile.cell, "Install on the original terrain without replacing it")
	assert(game.island_tiles.size() == original_count, "Harbor overlay must not add land")
	var ship_built: bool = game.explorer.construct()
	assert(ship_built, "Construct the real exploration ship")
	for cell in [Vector2i(2, 0), Vector2i(-2, 0), Vector2i(0, -2), Vector2i(0, 2)]:
		assert(game.harbor_visual.outward(cell, game.island_tiles) == cell / 2, "Perimeter art must face away from island")
	assert(game.explorer.position == game.island_pos + Vector2(244, 0), "Ship docks alongside the outer berth")
	game.development.close_menu()
	game.selected_plot = -1
	game.hovered_plot = -1
	game.camera_world = game.island_pos + Vector2(0, -15)
	game.camera_zoom = 1.0
	game.camera_zoom_target = 1.0
	await capture("01-harbor-and-ship-overview")
	var port_center: Vector2 = game.island_pos + Vector2(160, 0)
	game.camera_world = port_center + Vector2(35, -25)
	game.camera_zoom = 3.0
	await capture("02-docked-closeup")
	assert(game.explorer.visual.texture.get_size() == Vector2(80, 64), "Complete ship including embedded propulsion must fit one tile")
	game.hazards = [{"pos": port_center + Vector2(500, -32), "active": true,
		"biome": 1, "name": "矿石岛", "tiles": Tiles.wild_tiles(1, 1),
		"world_key": "harbor-preview", "world_index": 0}]
	game.explorer.charge = game.explorer.BATTERY
	if "--states" in OS.get_cmdline_user_args():
		await capture_states()
		quit()
		return
	if "--video" in OS.get_cmdline_user_args():
		await capture_video(port_center)
		quit()
		return
	var launched: bool = game.explorer.launch()
	assert(launched, "Launch toward an actual mineral island")
	game.explorer.update(0.8)
	assert(game.explorer.state == "outbound", "Capture the ship during actual outbound travel")
	game.camera_world = port_center + Vector2(60, -25)
	await capture("03-departing-closeup")
	game.explorer.recall()
	for step in range(30): game.explorer.update(0.1)
	assert(game.explorer.state == "docked", "Ship returns to the new berth")
	assert(game.explorer.position == game.explorer.dock_position(), "Returned ship aligns with berth")
	var previous := Vector2i(2, 0)
	var destinations := [Vector2i(0, -2), Vector2i(-2, -1), Vector2i(0, 2)]
	for i in range(destinations.size()):
		var cell: Vector2i = destinations[i]
		assert(game.development.relocate(previous, cell), "Relocate the real harbor to another island edge")
		game.explorer.update(0.0)
		var direction: Vector2i = game.harbor_visual.outward(cell, game.island_tiles)
		assert(game.development.tile_at(cell + direction).is_empty(), "Berth must be an empty space adjacent to the special harbor tile")
		assert(game.explorer.position == game.explorer.dock_position(), "Docked ship follows only the special harbor tile")
		game.camera_world = game.island_pos + Vector2(cell) * Tiles.CELL_SIZE + Vector2(game.harbor_visual.outward(cell, game.island_tiles)) * 35.0
		await capture("%02d-edge-berth" % (i + 4))
		previous = cell
	assert(game.harbor_visual.texture.get_size() == Vector2(80, 64), "Special harbor occupies exactly one logical tile")
	var port: Dictionary = game.explorer.harbor()
	var docked_position: Vector2 = game.explorer.position
	port.facility = ""
	game.explorer.update(0.1)
	assert(game.explorer.position == docked_position, "Missing harbor must not create a fallback berth beside ordinary land")
	assert(not game.explorer.launch(), "Missing harbor cannot dispatch ships")
	port.facility = "harbor"
	print("HARBOR SHIP PREVIEW: 6 screenshots captured")
	quit()

func capture_video(port_center: Vector2) -> void:
	const FPS := 30
	const FRAMES := 240
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT + "video-frames"))
	game.camera_world = port_center + Vector2(100, -25)
	for frame in range(FRAMES):
		if frame == 60:
			assert(game.explorer.launch(), "Launch the actual ship at 2 seconds")
		if frame == 90:
			assert(game.explorer.state == "outbound", "Ship must travel before recall")
			game.explorer.recall()
		game.explorer.update(1.0 / FPS)
		game.animation_time = 2.35 + float(frame) / FPS
		await capture("video-frames/frame-%03d" % frame)
	assert(game.explorer.state == "docked", "Video must finish with successful return")
	assert(game.explorer.position == game.explorer.dock_position(), "Returned ship aligns with berth")
	print("HARBOR SHIP VIDEO: 240 frames, 30 FPS, 8 seconds; launch and return PASS")

func capture_states() -> void:
	var ship = game.explorer
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT + "state-frames"))
	var frame := 0
	var anchor: Vector2 = ship.dock_position()
	game.camera_world = anchor + Vector2(-45, -15)
	game.camera_zoom = 3.0
	for amount in [0, ship.capacity() / 2, ship.capacity()]:
		ship.cargo = {"ore": amount}
		await capture("cargo-%02d" % amount)
		for step in range(15):
			await capture("state-frames/frame-%03d" % frame)
			frame += 1
	ship.cargo = {}
	var directions := [Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT, Vector2.UP, Vector2(1, 1), Vector2(-1, 1), Vector2(-1, -1), Vector2(1, -1)]
	for i in range(directions.size()):
		ship.position = anchor
		ship.state = "docked"
		ship.charge = 500.0
		ship.exhaust.clear()
		ship.exhaust_elapsed = 0.0
		game.hazards[0].pos = anchor + directions[i].normalized() * 500
		assert(ship.launch())
		for step in range(15):
			ship.update(1.0 / 15.0)
			game.camera_world = ship.position + Vector2(0, -15)
			await capture("state-frames/frame-%03d" % frame)
			frame += 1
		assert(not ship.exhaust.is_empty() and ship.visual.rotation == 0.0)
		await capture("direction-%d" % i)
	print("SHIP STATES VIDEO: 165 frames, 15 FPS; three cargo states and eight travel directions PASS")
