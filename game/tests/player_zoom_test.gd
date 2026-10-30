extends SceneTree

var game
var checks := 0
var failures := 0
const OUT := "res://../artifacts/game/player-zoom/"

func _init() -> void: call_deferred("run")

func check(ok: bool, title: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(title)

func wheel(direction: int) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = direction
	event.position = game.VIEW_CENTER
	event.pressed = true
	root.push_input(event)
	game._update_camera(0.4)

func capture(name: String) -> void:
	game.queue_redraw()
	await process_frame
	await process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT + name + ".png"))

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	root.size = Vector2i(1152, 648)
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game._start_demo()
	game.set_process(false)
	game.set_physics_process(false)
	game.notice_label.text = ""
	var base: float = game._default_player_zoom()
	check(is_equal_approx(game.camera_zoom, base), "initial camera keeps current default view")
	await capture("01-default")
	wheel(MOUSE_BUTTON_WHEEL_DOWN)
	check(is_equal_approx(game.camera_zoom, base), "wheel down at default cannot reveal a wider area")
	wheel(MOUSE_BUTTON_WHEEL_UP)
	check(game.camera_zoom > base, "wheel up approaches island details")
	for i in range(30): wheel(MOUSE_BUTTON_WHEEL_UP)
	check(is_equal_approx(game.camera_zoom, game.movement_settings.focus_zoom_max), "close-up zoom has a finite upper bound")
	check(game.camera_world.is_finite(), "close-up clamp keeps a valid camera center")
	var cell_point: Vector2 = game.island_pos + Vector2(80, 64)
	check(game._screen_to_world(game._world_to_screen(cell_point)).is_equal_approx(cell_point), "close-up preserves tile picking coordinates")
	await capture("02-detail")
	var detail: float = game.camera_zoom
	game.navigation_view.toggle_map()
	var scale_before: float = game.map_scale
	wheel(MOUSE_BUTTON_WHEEL_UP)
	check(game.map_scale > scale_before and is_equal_approx(game.camera_zoom, detail), "sky map wheel controls only map zoom")
	game.navigation_view.toggle_map()
	check(is_equal_approx(game.camera_zoom, detail), "closing map restores the close-up view")
	for i in range(40): wheel(MOUSE_BUTTON_WHEEL_DOWN)
	check(is_equal_approx(game.camera_zoom, base), "zooming back stops exactly at default")
	await capture("03-restored")
	var template: Dictionary = game.island_tiles[0].duplicate()
	game.island_tiles = []
	game.plots = []
	for i in range(100):
		var tile: Dictionary = template.duplicate()
		tile.cell = Vector2i(i % 10 - 5, i / 10 - 5)
		tile.kind = "grass"
		tile.facility = ""
		game.island_tiles.append(tile)
	game.development.sync()
	for i in range(40): wheel(MOUSE_BUTTON_WHEEL_DOWN)
	check(is_equal_approx(game.camera_zoom, game._default_player_zoom()) and game.camera_zoom < base, "expanded island restores its own fit-to-island baseline")
	game.camera_zoom = 0.01
	game.camera_zoom_target = 0.01
	game._update_camera(0)
	check(is_equal_approx(game.camera_zoom, game._default_player_zoom()), "legacy distant camera values cannot bypass the zoom floor")
	game.queue_free()
	await process_frame
	print("PLAYER ZOOM: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
