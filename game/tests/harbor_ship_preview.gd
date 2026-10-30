extends SceneTree

const OUT := "res://../artifacts/game/harbor-ship/"
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
	var port_built: bool = game.development.build(Vector2i(2, 0), "harbor")
	assert(port_built, "Build the real harbor on a perimeter tile")
	var ship_built: bool = game.explorer.construct()
	assert(ship_built, "Construct the real exploration ship")
	game.development.close_menu()
	game.selected_plot = -1
	game.hovered_plot = -1
	game.camera_world = game.island_pos + Vector2(0, -15)
	game.camera_zoom = 1.0
	game.camera_zoom_target = 1.0
	await capture("01-harbor-and-ship-overview")
	var port_center: Vector2 = game.island_pos + Vector2(160, 0)
	game.camera_world = port_center + Vector2(0, -25)
	game.camera_zoom = 3.0
	await capture("02-docked-closeup")
	game.hazards = [{"pos": port_center + Vector2(500, -32), "active": true,
		"biome": 1, "name": "矿石岛", "tiles": Tiles.wild_tiles(1, 1),
		"world_key": "harbor-preview", "world_index": 0}]
	game.explorer.charge = game.explorer.BATTERY
	var launched: bool = game.explorer.launch()
	assert(launched, "Launch toward an actual mineral island")
	game.explorer.update(0.8)
	assert(game.explorer.state == "outbound", "Capture the ship during actual outbound travel")
	game.camera_world = port_center + Vector2(60, -25)
	await capture("03-departing-closeup")
	print("HARBOR SHIP PREVIEW: 3 screenshots captured")
	quit()
