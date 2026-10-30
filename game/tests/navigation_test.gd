extends SceneTree

class Probe extends "res://scripts/main.gd":
	var detail_draws := 0
	var draw_us: Array = []
	func _draw_island() -> void:
		detail_draws += 1
		super._draw_island()
	func _draw() -> void:
		var start := Time.get_ticks_usec()
		super._draw()
		draw_us.append(Time.get_ticks_usec() - start)

var game
var nav
var failures := 0
var checks := 0
const OUT := "res://../artifacts/game/navigation/"

func _init() -> void: call_deferred("run")

func check(value: bool, title: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(title)

func capture(name: String) -> Image:
	game.queue_redraw()
	game.map_ink.queue_redraw()
	await process_frame
	await process_frame
	if DisplayServer.get_name() == "headless": return null
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(OUT + name + ".png"))
	return img

func key(code: int) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = true
	root.push_input(event)
	event = event.duplicate()
	event.pressed = false
	root.push_input(event)

func wheel(point: Vector2, direction: int) -> void:
	var event := InputEventMouseButton.new()
	event.position = point
	event.button_index = direction
	event.pressed = true
	root.push_input(event)

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT + "frames"))
	root.size = Vector2i(1152, 648)
	game = Probe.new()
	root.add_child(game)
	await process_frame
	game._start_demo()
	game.set_process(false)
	game.set_physics_process(false)
	nav = game.navigation_view
	game.development.tech.radar = 3
	game.development.tech.engine = 1
	game.island_tiles[0].facility = "power"
	game.development.sync()
	game.notice_label.text = ""
	game.camera_zoom = 0.4
	game.camera_zoom_target = 0.4
	game._update_camera(0)
	game.optimized_rendering = false
	await capture("01-original-wide")
	var old_us: Array = []
	for i in range(8):
		game.queue_redraw()
		await process_frame
		if not game.draw_us.is_empty(): old_us.append(game.draw_us.back())
	game.optimized_rendering = true
	await capture("02-cached-wide")
	var cached_us: Array = []
	for i in range(8):
		game.queue_redraw()
		await process_frame
		if not game.draw_us.is_empty(): cached_us.append(game.draw_us.back())
	game.island_velocity = Vector2(10, 2)
	var state: Dictionary = game.saves.snapshot()
	var anim: float = game.animation_time
	key(KEY_TAB)
	key(KEY_V)
	check(not nav.paused() and not InputMap.has_action("toggle_view"), "removed overview keys cannot pause or switch views")
	check(game.navigation_buttons.get_child(0) == game.map_button, "map replaces removed overview toolbar entry")
	key(KEY_M)
	check(game.sky_map_open and nav.paused(), "M opens paused map directly")
	var draws_before: int = game.detail_draws
	Input.action_press("move_right")
	for i in range(20):
		game._physics_process(0.1)
		game._process(0.1)
	Input.action_release("move_right")
	check(game.island_pos == state.state.island_pos and game.island_velocity == state.state.island_velocity, "map freezes position and inertia even with driving input")
	check(game.day_minutes == state.state.day_minutes and game.weather_elapsed == state.state.weather_elapsed and game.animation_time == anim, "map freezes time, weather and animation")
	check(game.energy == state.state.energy and game.merchant_arrival_left == state.state.merchant_arrival_left and game.plots == state.plots, "map freezes resources, merchant timer and crops")
	key(KEY_B)
	key(KEY_SPACE)
	check(not game.development.modal.visible and game.energy == state.state.energy, "map cannot build or spend energy braking")
	await capture("03-map-default")
	check(game.detail_draws == draws_before, "map draws no detailed world underneath")
	game.saves.request_exit()
	key(KEY_ESCAPE)
	check(not game.saves.is_open() and game.sky_map_open, "cancel closing the window returns to paused map")
	var start_center: Vector2 = game.map_center
	Input.action_press("move_right")
	game._process(0.3)
	game._physics_process(0.3)
	Input.action_release("move_right")
	check(game.map_center.x > start_center.x and game.island_pos == state.state.island_pos, "WASD pans the map without moving island")
	check(game._world_to_map(game.island_pos) != game.MAP_RECT.get_center(), "player icon follows independent map center")
	var point: Vector2 = game.MAP_RECT.get_center() + Vector2(100, 25)
	var world_anchor: Vector2 = game._map_to_world(point)
	var old_scale: float = game.map_scale
	var camera_before: float = game.camera_zoom_target
	wheel(point, MOUSE_BUTTON_WHEEL_UP)
	check(game.map_scale > old_scale and game._map_to_world(point).is_equal_approx(world_anchor), "wheel zooms around cursor without shifting its world point")
	check(game.camera_zoom_target == camera_before, "map wheel never zooms the normal camera")
	wheel(point, MOUSE_BUTTON_WHEEL_DOWN)
	check(is_equal_approx(game.map_scale, old_scale), "wheel down reverses zoom")
	wheel(Vector2.ZERO, MOUSE_BUTTON_WHEEL_UP)
	check(is_equal_approx(game.map_scale, old_scale), "wheel outside map cannot change zoom")
	game.map_center = game.island_pos
	for i in range(35): wheel(game.MAP_RECT.get_center(), MOUSE_BUTTON_WHEEL_UP)
	check(is_equal_approx(game.map_scale, nav.MAP_ZOOM_MAX), "zoom in is bounded")
	await capture("07-map-zoom-in")
	for i in range(45): wheel(game.MAP_RECT.get_center(), MOUSE_BUTTON_WHEEL_DOWN)
	check(is_equal_approx(game.map_scale, nav.MAP_ZOOM_MIN), "zoom out is bounded")
	await capture("08-map-zoom-out")
	wheel(point, MOUSE_BUTTON_WHEEL_UP)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = point
	root.push_input(click)
	check(game.map_destination.is_equal_approx(game.map_center + Vector2(100, 25) / game.map_scale), "panned and zoomed map click converts to correct world coordinate")
	key(KEY_ENTER)
	check(game.sky_map_open and not game.autopilot_active, "Enter cannot launch automatic navigation")
	game._physics_process(2)
	check(game.island_pos == state.state.island_pos and game.energy == state.state.energy, "map pauses drift and consumption")
	var island: Dictionary = game.hazards[0]
	for candidate in game.hazards:
		if candidate.active and game._radar_visible(candidate.pos): island = candidate; break
	game.map_center = island.pos
	game.map_scale = 0.4
	var tile: Dictionary = island.tiles[0]
	var world: Vector2 = island.pos - game.IslandTiles.bounds(island.tiles).get_center() + Vector2(tile.cell) * game.IslandTiles.CELL_SIZE
	point = game._world_to_map(world)
	nav.clear_hover()
	nav.poll_hover(point, 0)
	nav.poll_hover(point, 0.54)
	check(not nav.hover_card.visible, "hover waits before showing a card")
	nav.poll_hover(point, 0.02)
	check(nav.hover_card.visible and nav.hover_label.text.contains(island.name), "island hover shows real basic information")
	await capture("04-map-island-hover")
	nav.poll_hover(Vector2.ZERO, 1)
	check(not nav.hover_card.visible, "leaving map dismisses hover")
	var zone: Dictionary = game.WeatherSystem.region("test", "storm", game.island_pos + Vector2(400, 0), 300, Vector2(0.5, 0), 120)
	game.zones = [zone]
	game.current_weather = 0
	game.map_center = zone.pos
	game.hazards = []
	point = game._world_to_map(zone.pos)
	nav.poll_hover(point, 0)
	nav.poll_hover(point, 0.6)
	check(nav.hover_card.visible and nav.hover_label.text.contains("雷暴"), "weather hover shows weather and growth")
	await capture("05-map-weather-hover")
	check(game.detail_draws == draws_before, "sky map draws no detailed world underneath")
	key(KEY_ESCAPE)
	check(not nav.paused() and not nav.hover_card.visible, "Escape closes map before cancelling a tool")
	Input.action_press("move_right")
	game._physics_process(0.1)
	Input.action_release("move_right")
	check(game.island_pos != state.state.island_pos and game.map_destination_set, "returning to reality permits manual driving and preserves marker")
	await capture("06-manual-bearing")
	# Save migration must never resume the former automated driver.
	game.saves.directory = "res://../.codex_tmp/navigation-test-saves"
	game.autopilot_active = true
	check(game.saves.save_slot(1), "legacy active-navigation state can be saved for migration test")
	check(game.saves.load_slot(1) and not game.autopilot_active and game.map_destination_set, "loading preserves marker but cancels old automatic route")
	old_us.sort()
	cached_us.sort()
	if old_us.size() > 4 and cached_us.size() > 4:
		print("WIDE VIEW draw CPU median: original=%s us cached=%s us" % [old_us[4], cached_us[4]])
	game.queue_free()
	await process_frame
	print("NAVIGATION: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
