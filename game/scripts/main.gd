extends Node2D

signal energy_changed(delta: float, reason: String)
signal island_mass_changed(mass: float)
signal view_mode_changed(mode: int)
signal autopilot_state_changed(state: String, reason: String)
signal grapple_state_changed(state: int)
signal emergency_stop_triggered(speed: float)
signal obstacle_warning(direction: Vector2, distance: float)
signal merge_ready(target: Dictionary)

const VIEW_SIZE := Vector2(1152.0, 648.0)
const VIEW_CENTER := VIEW_SIZE * 0.5
const HOOK_READY := 0
const HOOK_EXTEND := 1
const HOOK_DANGLE := 2
const HOOK_RETRACT := 3
const HOOK_FIXING := 4
const TOOL_HOOK := 0
const TOOL_SEED := 1
const CROP_RICE := 0
const CROP_TOMATO := 1
const CROP_STAGE_COUNT := 5
# These concept sheets are NOT equally spaced atlases. Read each complete plant
# with a transparent margin; keep the same uniform source scale across stages.
const RICE_FRAMES := [Rect2(140, 0, 156, 724), Rect2(489, 0, 244, 724), Rect2(844, 0, 312, 724), Rect2(1228, 0, 399, 724), Rect2(1680, 0, 466, 724)]
const TOMATO_FRAMES := [Rect2(82, 0, 213, 724), Rect2(387, 0, 356, 724), Rect2(793, 0, 385, 724), Rect2(1209, 0, 440, 724), Rect2(1682, 0, 468, 724)]
const VIEW_GOD := 0
const VIEW_FOCUS := 1
const MAP_RECT := Rect2(118.0, 96.0, 916.0, 446.0)
const WorldLayout = preload("res://scripts/world_layout.gd")
const IslandTiles = preload("res://scripts/island_tiles.gd")
const PixelTerrain = preload("res://scripts/pixel_terrain.gd")
const Development = preload("res://scripts/island_development.gd")
const WeatherSystem = preload("res://scripts/weather_system.gd")
const ScaleRules = preload("res://scripts/scale_rules.gd")
# Explicit inspector override for development builds only; normal play stays at 100.
@export_range(100, 144, 1) var debug_player_tile_limit: int = ScaleRules.PLAYER_TILE_LIMIT
var development
var land
var explorer
var saves
var sector_pool = preload("res://scripts/sector_pool.gd").new()
var tile_index: Dictionary = {}
var indexed_tiles: Array = []
var ordered_tiles: Array = []
var optimized_rendering := true
var crop_renderer = preload("res://scripts/crop_renderer.gd").new()
var terrain_mesh_cache = preload("res://scripts/terrain_mesh_cache.gd").new()
var nearby_terrain_cache: Dictionary = {}
var hud_refresh_left := 0.0
var weather_elapsed := 0.0
var weather_refresh := 0.0
var weather_tint := 0.0
var lightning_left := 0.0
var lightning_next := 8.0
var weather_rng := RandomNumberGenerator.new()
var weather_hazard_left := 8.0
var energy_warning_left := 0.0
var energy_warning_text := ""
var merchant_arrival_left := 45.0
var merchant_stay_left := 0.0
var merchant_available := false

var movement_settings: Resource = preload("res://data/movement_settings.tres")

const SKY_TOP := Color("#8ed1e8")
const SKY_BOTTOM := Color("#d9f0dc")
const INK := Color("#4b2f25")
const PANEL := Color("#f7e4b9")
const PANEL_DARK := Color("#d8b276")
const GRASS := Color("#65a94f")
const GRASS_LIGHT := Color("#8acb60")
const SOIL := Color("#8a5438")
const SOIL_LIGHT := Color("#b7774c")
const PLOT_FRAME := Color("#5b382b")
const PLOT_HOVER := Color("#fff0a8")
const PLOT_SELECTED := Color("#ffd467")
const PLOT_GROWING := Color("#74ad55")
const PLOT_READY := Color("#f2ba43")

var island_pos := Vector2(575.0, 350.0)
var world_origin := island_pos
var island_velocity := Vector2.ZERO
var island_mass := 28.0
var engine_level := 1
var inertia_damping_level := 0
var energy_capacity := 150.0
var energy := 150.0
var coins := 78
var rice_seeds := 3
var tomato_seeds := 2
var rice_stock := 0
var energy_crop_stock := 0
var harvested := 0
var gathered := 0
var day_minutes := 8.0 * 60.0
var day_number := 1
var animation_time := 0.0
var wind_strength := 0.12
var demo_started := false
var selected_tool := TOOL_HOOK
var current_weather := -1
var collision_cooldown := 0.0
var worker_slow_time := 0.0
var control_stun_time := 0.0
var emergency_braking := false
var screen_shake_time := 0.0
var screen_shake_strength := 0.0

var view_mode := VIEW_GOD
var camera_world := island_pos
var camera_zoom := 0.55
var camera_zoom_target := 0.55
var focus_offset := Vector2.ZERO
var view_transition_left := 0.0
var middle_dragging := false
var last_mouse_position := Vector2.ZERO

var navigation_view
var map_scale := 0.16
var map_center := island_pos
var sky_map_open := false
var map_destination := Vector2.ZERO
var map_destination_set := false
var autopilot_active := false
var autopilot_state := "待机"
var autopilot_reason := ""
var autopilot_unlocked := false
var warning_system_unlocked := true
var warning_direction := Vector2.ZERO
var warning_distance := INF
var warning_ping_cooldown := 0.0
var soft_boundary_active := false

var hook_state := HOOK_READY
var hook_pos := Vector2.ZERO
var hook_dir := Vector2.RIGHT
var hooked_target := -1
var hook_max_distance := 330.0
var hook_dangle_left := 0.0
var hook_launch_energy_paid := 0.0
var hook_fixing_left := 0.0
var merge_offset := Vector2i.ZERO

var targets: Array = []
var hazards: Array = []
var zones: Array = []
var plots: Array = []
var island_tiles: Array = []
var island_bounds := Rect2(-200, -160, 400, 320)
var world_sectors: Dictionary = {}
var active_sector := Vector2i(2147483647, 2147483647)

var icon_atlas: Texture2D
var hud_icon_atlas: Texture2D
const HUD_ICONS := ["land", "mass", "house", "wood", "stone", "ore", "magma", "tomato", "focus", "map", "build", "tech", "help", "cloud", "snow", "cyclone", "growth", "damage", "shield", "time", "rice_seeds", "tomato_seeds"]
var resource_labels: Dictionary = {}
var weather_icon: TextureRect
var weather_timer: Label
var weather_risk: Label
var weather_risk_icon: TextureRect
var navigation_buttons: GridContainer
var inspected_island: Dictionary = {}
var rice_atlas: Texture2D
var tomato_atlas: Texture2D
var terrain_textures: Dictionary = {}
var tree_texture: Texture2D
var power_hut_texture: Texture2D
var engine_room_animation = preload("res://scripts/engine_room_animation.gd").new()
var grapple_hut_texture: Texture2D
var water_grain_hut_texture: Texture2D
const EnergyConversionUI = preload("res://scripts/energy_conversion_ui.gd")
var energy_conversion_source: Texture2D
var energy_conversion_texture: Texture2D
var farm_hut_textures: Array[Texture2D] = []
var money_label: Label
var energy_label: Label
var fuel_label: Label
var time_label: Label
var weather_label: Label
var context_label: Label
var context_title_label: Label
var notice_label: Label
var header_row: HBoxContainer
var stats_row: HBoxContainer
var context_panel: PanelContainer
var map_clip: Control
var map_ink: Node2D
var map_button: Button
var fuel_button: Button
var hook_button: Button
var seed_button: Button
var tomato_button: Button
var gather_button: Button
var tool_sidebar: PanelContainer
var intro_panel: PanelContainer
var guide_panel: PanelContainer
var guide_body: Label
var notice_time := 0.0
var hovered_plot := -1
var selected_plot := -1


func _ready() -> void:
	get_window().title = "flying_garden · Godot 4.7 Demo"
	island_mass = movement_settings.initial_mass
	energy_capacity = movement_settings.base_energy_capacity
	energy = energy_capacity
	hook_max_distance = movement_settings.hook_range_tiles * movement_settings.tile_size
	camera_world = island_pos
	camera_zoom = movement_settings.god_zoom_default
	camera_zoom_target = camera_zoom
	icon_atlas = load("res://assets/ui/farm_ui_icons.png")
	hud_icon_atlas = load("res://assets/ui/hud_icons.svg")
	_load_pixel_v2_assets()
	_initialize_world()
	development = Development.new(self)
	land = preload("res://scripts/land_systems.gd").new(self)
	explorer = preload("res://scripts/exploration_ship.gd").new(self)
	saves = preload("res://scripts/save_slots.gd").new(self)
	get_tree().auto_accept_quit = false
	development.sync()
	weather_rng.seed = 20261022
	_update_zones(0.0)
	_build_hud()
	hook_pos = _hook_origin()
	queue_redraw()
	var user_args := OS.get_cmdline_user_args()
	if "--capture-development-preview" in user_args or "--capture-weather-preview" in user_args:
		call_deferred("_capture_development_preview", "--capture-weather-preview" in user_args)
	elif "--capture-preview" in user_args or "--capture-map-preview" in user_args or "--capture-expanded-preview" in user_args:
		call_deferred("_capture_preview", "--capture-map-preview" in user_args, "--capture-expanded-preview" in user_args)


func _atlas_region(texture: Texture2D, region: Rect2) -> AtlasTexture:
	var result := AtlasTexture.new()
	result.atlas = texture
	result.region = region
	result.filter_clip = true
	return result


func _load_pixel_v2_assets() -> void:
	terrain_textures = PixelTerrain.load_sources().duplicate()
	terrain_textures["tree"] = terrain_textures["grass"]
	tree_texture = PixelTerrain.approved_tree()
	rice_atlas = load("res://assets/pixel_v2/crops/rice_growth_5stage_v2.png")
	tomato_atlas = load("res://assets/pixel_v2/crops/tomato_growth_5stage_v2.png")
	power_hut_texture = _atlas_region(load("res://assets/pixel_v2/facilities/engine_room_v2.png"), Rect2(295, 91, 958, 845))
	engine_room_animation.load_assets()
	water_grain_hut_texture = _atlas_region(load("res://assets/pixel_v2/facilities/energy_storage_room_v2.png"), Rect2(320, 59, 912, 902))
	energy_conversion_source = ImageTexture.create_from_image(Image.load_from_file(ProjectSettings.globalize_path(EnergyConversionUI.SOURCE)))
	energy_conversion_texture = _atlas_region(energy_conversion_source, EnergyConversionUI.GAME_REGION)
	grapple_hut_texture = _atlas_region(load("res://assets/pixel_v2/facilities/grapple_workshop_v2.png"), Rect2(299, 142, 1099, 775))
	for crop in ["rice", "tomato"]:
		var source: Texture2D = load("res://assets/pixel_v2/facilities/farm_management_hut_%s_v1.png" % crop)
		# Both approved silhouettes occupy the same frame. Ignore isolated near-
		# transparent pixels elsewhere on the canvas so both huts keep equal scale.
		farm_hut_textures.append(_atlas_region(source, Rect2(296, 134, 946, 808)))


func farm_hut_texture(tile: Dictionary) -> Texture2D:
	return farm_hut_textures[clampi(int(tile.get("farm_crop", CROP_RICE)), CROP_RICE, CROP_TOMATO)]


func _initialize_world() -> void:
	island_tiles = IslandTiles.initial_tiles()
	_refresh_island_shape()
	for index in range(9):
		plots.append({"cell": Vector2i(index % 3 - 1, int(index / 3) - 1), "state": 0, "progress": 0.0, "crop_type": CROP_RICE if index % 2 == 0 else CROP_TOMATO})

	_update_world_stream()


func _update_world_stream() -> void:
	var sector := WorldLayout.sector_at(island_pos, world_origin)
	if sector == active_sector: return
	nearby_terrain_cache.clear()
	var attached: Dictionary = targets[hooked_target] if hooked_target >= 0 and hooked_target < targets.size() else {}
	var wanted: Dictionary = {}
	for y in range(sector.y - WorldLayout.ACTIVE_RADIUS, sector.y + WorldLayout.ACTIVE_RADIUS + 1):
		for x in range(sector.x - WorldLayout.ACTIVE_RADIUS, sector.x + WorldLayout.ACTIVE_RADIUS + 1):
			wanted[Vector2i(x, y)] = true
	# In-flight objects pin their source sector so pooled records never invalidate them.
	if not attached.is_empty() and attached.has("island"): wanted[attached.island.get("world_key", sector)] = true
	if explorer != null and not explorer.target.is_empty(): wanted[explorer.target.get("world_key", sector)] = true
	for key in world_sectors.keys():
		if not wanted.has(key):
			sector_pool.release(key, world_sectors[key])
			world_sectors.erase(key)
	active_sector = sector
	targets = []
	hazards = []
	for key in wanted:
		if not world_sectors.has(key): world_sectors[key] = sector_pool.acquire(key, world_origin)
		var content: Dictionary = world_sectors[key]
		hazards.append_array(content.hazards)
		targets.append_array(content.island_targets)
	if not attached.is_empty():
		hooked_target = targets.find(attached)
		if hooked_target < 0:
			targets.append(attached)
			hooked_target = targets.size() - 1
	else: hooked_target = -1


func _refresh_island_shape() -> void:
	indexed_tiles = island_tiles
	tile_index.clear()
	for tile in island_tiles: tile_index[tile.cell] = tile
	ordered_tiles = island_tiles.duplicate()
	ordered_tiles.sort_custom(IslandTiles._tile_painter_order)
	island_bounds = IslandTiles.bounds(island_tiles)
	island_mass = IslandTiles.mass(island_tiles)
	island_mass_changed.emit(island_mass)


func _clamp_focus_offset() -> void:
	var bounds := island_bounds
	focus_offset = focus_offset.clamp(bounds.position, bounds.end)
	# Keep the focal point on actual land even for a concave or expanded island.
	var nearest := focus_offset
	var distance := INF
	for tile in island_tiles:
		var rect := IslandTiles.cell_rect(Vector2.ZERO, tile.cell).grow(-0.01)
		var point := focus_offset.clamp(rect.position, rect.end)
		var candidate := point.distance_squared_to(focus_offset)
		if candidate < distance:
			nearest = point
			distance = candidate
	focus_offset = nearest


func _island_visual_bounds() -> Rect2:
	# Include tall trees, roofs and the exposed soil beneath the tile footprint.
	return Rect2(island_bounds.position - Vector2(38, 112), island_bounds.size + Vector2(76, 160))


func _god_zoom_limit() -> float:
	var visual := _island_visual_bounds()
	return minf(movement_settings.god_zoom_max, minf(880.0 / visual.size.x, 440.0 / visual.size.y))


func _default_player_zoom() -> float:
	return minf(movement_settings.god_zoom_default, _god_zoom_limit())


func _clamp_god_camera() -> void:
	var visual := _island_visual_bounds()
	# Reserve space for the HUD, tools and visitor banner.
	var safe := Rect2(156, 100, 968, 448)
	var lower := island_pos + visual.end - (safe.end - VIEW_CENTER) / camera_zoom
	var upper := island_pos + visual.position - (safe.position - VIEW_CENTER) / camera_zoom
	# At close range the island exceeds the safe frame; keep both bounds ordered.
	camera_world = camera_world.clamp(lower.min(upper), lower.max(upper))


func _physics_process(delta: float) -> void:
	if navigation_view != null and navigation_view.paused(): return
	if not demo_started or (saves != null and saves.is_open()):
		return
	# The visitor's departure clock also runs while browsing the market.
	_update_merchant(delta)
	if development.modal != null and (development.modal.visible or development.tile_menu.is_open()):
		_tick_hud(delta)
		return

	day_minutes += delta * 5.0
	day_number += int(day_minutes / 1440.0)
	day_minutes = fmod(day_minutes, 1440.0)
	energy_warning_left = maxf(0.0, energy_warning_left - delta)
	development.update(delta)
	land.update_trees(delta)
	explorer.update(delta)
	collision_cooldown = maxf(0.0, collision_cooldown - delta)
	worker_slow_time = maxf(0.0, worker_slow_time - delta)
	control_stun_time = maxf(0.0, control_stun_time - delta)
	screen_shake_time = maxf(0.0, screen_shake_time - delta)
	warning_ping_cooldown = maxf(0.0, warning_ping_cooldown - delta)

	var manual_direction := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if control_stun_time > 0.0:
		manual_direction = Vector2.ZERO

	_update_world_stream()
	_update_warning()
	var drive_direction := manual_direction
	_apply_movement(delta, drive_direction, drive_direction.length_squared() > 0.01)
	_update_focus_pan(delta)
	_update_camera(delta)

	_update_zones(delta)
	_update_weather_hazards(delta)
	_update_crops(delta)
	_update_hook(delta)
	_update_targets(delta)
	_check_collisions()
	_tick_hud(delta)
	queue_redraw()


func _process(delta: float) -> void:
	if navigation_view != null:
		navigation_view.update(delta)
		if navigation_view.paused(): return
	animation_time += delta
	var kind := _weather_kind()
	var target_wind: float = {"clear": 0.12, "sun": 0.10, "cloud": 0.20, "rain": 0.34, "snow": 0.25, "storm": 0.65, "cyclone": 1.6}[kind]
	wind_strength = move_toward(wind_strength, target_wind, delta * 0.7)
	queue_redraw()
	if notice_time > 0.0:
		notice_time -= delta
		if notice_time <= 0.0 and notice_label != null:
			notice_label.text = ""
	if demo_started:
		_update_plot_hover()
		_update_context_card()
		_fit_context_panel()


func _update_plot_hover() -> void:
	var next_hover := -1
	if not sky_map_open and (development == null or development.modal == null or (not development.modal.visible and not development.tile_menu.is_open())):
		var mouse := get_viewport().get_mouse_position()
		for index in range(plots.size()):
			if _plot_rect(index).has_point(mouse):
				next_hover = index
				break
	if hovered_plot != next_hover:
		hovered_plot = next_hover
		queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if navigation_view != null and navigation_view.paused() and not saves.is_open():
		navigation_view._input(event)
		return
	if saves.is_open():
		if event.is_action_pressed("ui_cancel"): saves.close()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F5:
		saves.open_menu()
		get_viewport().set_input_as_handled()
		return
	if not demo_started:
		return
	if development.tile_menu.is_open():
		if event.is_action_pressed("ui_cancel") or (event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]):
			development.tile_menu.close()
			get_viewport().set_input_as_handled()
			return
		if event is InputEventKey and event.pressed:
			development.tile_menu.close()
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_B or event.keycode == KEY_T:
			development.toggle(event.keycode == KEY_T)
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_R:
			development.toggle_energy()
			get_viewport().set_input_as_handled()
			return
	if development.modal.visible:
		if event.is_action_pressed("ui_cancel"): development.close_menu()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_E:
		_toggle_island_details(_screen_to_world(get_viewport().get_mouse_position()))
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_cancel") and not inspected_island.is_empty():
		inspected_island = {}
		_update_context_card()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("toggle_map"):
		navigation_view.toggle_map()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("refuel"):
		development.toggle_energy()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("emergency_stop"):
		_emergency_stop()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept") and sky_map_open:
		_start_autopilot()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel"):
		if selected_tool == 2:
			development.move_from = development.NONE
			development.trim_pending = development.NONE
			_select_tool(TOOL_HOOK)
		elif sky_map_open:
			sky_map_open = false
			_show_notice("已关闭天空地图。")
		elif autopilot_active:
			_cancel_autopilot("玩家接管")
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("tool_hook"):
		_select_tool(TOOL_HOOK)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("tool_seed"):
		_select_tool(TOOL_SEED)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("use_tool"):
		if selected_tool == TOOL_HOOK:
			_fire_hook(_screen_to_world(get_viewport().get_mouse_position()))
		else:
			_interact_with_plot(get_viewport().get_mouse_position())
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and middle_dragging and view_mode == VIEW_FOCUS:
		focus_offset -= event.relative / camera_zoom
		_clamp_focus_offset()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			middle_dragging = event.pressed
			last_mouse_position = event.position
			get_viewport().set_input_as_handled()
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_adjust_zoom(0.1)
			get_viewport().set_input_as_handled()
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_adjust_zoom(-0.1)
			get_viewport().set_input_as_handled()
		elif event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			if sky_map_open:
				_set_map_destination(event.position)
			elif selected_tool == 2:
				development.click(_screen_to_world(event.position))
			elif selected_tool == TOOL_HOOK:
				_fire_hook(_screen_to_world(event.position))
			else:
				_interact_with_plot(event.position)
			get_viewport().set_input_as_handled()
		elif event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
			if hook_state != HOOK_READY:
				_cancel_hook()
			elif selected_tool == 2 and development.action != "gather":
				development.move_from = development.NONE
				development.trim_pending = development.NONE
				_select_tool(TOOL_HOOK)
			elif not sky_map_open:
				development.tile_menu.open_at(development.cell_at(_screen_to_world(event.position)))
			get_viewport().set_input_as_handled()


func _effective_mass() -> float:
	return island_mass * (1.0 - 0.10 * float(inertia_damping_level))


func _engine_thrust() -> float:
	return movement_settings.base_thrust * (development.engine_power() if development != null else 1.0)


func _max_speed() -> float:
	return _engine_thrust() / (_effective_mass() * movement_settings.drag_coefficient)


func _mass_energy_ratio() -> float:
	return _effective_mass() / movement_settings.initial_mass * (development.efficiency() if development != null else 1.0)


func _consume_energy(amount: float, reason: String) -> bool:
	if amount <= 0.0:
		return true
	if energy + 0.0001 < amount:
		return false
	energy = maxf(0.0, energy - amount)
	energy_changed.emit(-amount, reason)
	return true


func _add_energy(amount: float, reason: String) -> void:
	var before := energy
	energy = minf(energy_capacity, energy + amount)
	if energy > before:
		energy_changed.emit(energy - before, reason)


func _apply_movement(delta: float, direction: Vector2, wants_thrust: bool) -> void:
	var effective_mass := _effective_mass()
	var acceleration := _engine_thrust() / effective_mass
	var boundary_distance: float = movement_settings.soft_boundary_tiles * movement_settings.tile_size
	soft_boundary_active = absf(island_pos.x - world_origin.x) > boundary_distance or absf(island_pos.y - world_origin.y) > boundary_distance
	var boundary_ratio: float = movement_settings.soft_boundary_speed_ratio if soft_boundary_active else 1.0
	var speed_limit: float = _max_speed() * boundary_ratio

	var thrusting := wants_thrust and energy > 0.0 and not emergency_braking and _engine_thrust() > 0.0
	if emergency_braking:
		island_velocity = island_velocity.move_toward(Vector2.ZERO, acceleration * movement_settings.emergency_brake_multiplier * delta)
		if island_velocity.length() < 0.5:
			island_velocity = Vector2.ZERO
			emergency_braking = false
	elif thrusting:
		island_velocity += direction.normalized() * acceleration * delta
	else:
		island_velocity = island_velocity.move_toward(Vector2.ZERO, acceleration * movement_settings.passive_brake_ratio * delta)

	island_velocity *= exp(-movement_settings.drag_coefficient * delta)
	if island_velocity.length() > speed_limit:
		island_velocity = island_velocity.normalized() * speed_limit

	var energy_rate := 0.0
	if island_velocity.length() > 0.5:
		energy_rate += movement_settings.moving_energy_per_second
	if thrusting:
		energy_rate += movement_settings.thrust_energy_per_second
	if energy_rate > 0.0:
		var requested := energy_rate * _mass_energy_ratio() * delta
		var consumed := minf(energy, requested)
		if consumed > 0.0:
			_consume_energy(consumed, "浮岛推进")

	island_pos += island_velocity * delta
	if energy <= 0.0 and autopilot_active:
		_cancel_autopilot("能源耗尽")
	elif energy < movement_settings.autopilot_min_energy and autopilot_active:
		_cancel_autopilot("能源低于 20 E")


func _set_autopilot_state(state_value: String, reason: String) -> void:
	if autopilot_state == state_value and autopilot_reason == reason:
		return
	autopilot_state = state_value
	autopilot_reason = reason
	autopilot_state_changed.emit(state_value, reason)


func _start_autopilot() -> void:
	# Retained for old callers/saves; destinations now provide a manual bearing only.
	_cancel_autopilot("自动导航已取消，请返回现实视角手动驾驶")


func _cancel_autopilot(reason: String) -> void:
	if not autopilot_active and autopilot_reason == reason:
		return
	autopilot_active = false
	_set_autopilot_state("待机", reason)

func _has_collision_trend(hazard: Dictionary) -> bool:
	var speed: float = island_velocity.length()
	if speed < 5.0:
		return false
	var offset: Vector2 = hazard.pos - island_pos
	if offset.length_squared() < 0.01:
		return true
	var closing_speed: float = island_velocity.dot(offset.normalized())
	if closing_speed <= 3.0:
		return false
	var time_to_closest: float = offset.dot(island_velocity) / maxf(0.01, island_velocity.length_squared())
	if time_to_closest < 0.0 or time_to_closest > 6.0:
		return false
	var closest_offset: Vector2 = offset - island_velocity * time_to_closest
	var island_radius: float = maxf(island_bounds.size.x, island_bounds.size.y) * 0.45
	return closest_offset.length() <= float(hazard.radius) + island_radius + 24.0


func _update_warning() -> void:
	warning_direction = Vector2.ZERO
	warning_distance = INF
	if not warning_system_unlocked:
		return
	for hazard_value in hazards:
		var hazard: Dictionary = hazard_value
		if not bool(hazard.active) or bool(hazard.tethered) or not _radar_visible(hazard.pos) or not _has_collision_trend(hazard):
			continue
		var offset: Vector2 = hazard.pos - island_pos
		var clearance := _hazard_clearance(hazard)
		if clearance < warning_distance:
			warning_distance = clearance
			warning_direction = offset.normalized()
	var radius: float = movement_settings.warning_radius_tiles * movement_settings.tile_size
	if warning_distance <= radius:
		obstacle_warning.emit(warning_direction, warning_distance)
		if warning_ping_cooldown <= 0.0:
			var closeness := 1.0 - clampf(warning_distance / radius, 0.0, 1.0)
			warning_ping_cooldown = lerpf(1.2, 0.2, closeness)
			_play_tone(1000.0, 0.055, -15.0)


func _emergency_stop() -> void:
	if island_velocity.length() < 1.0:
		_show_notice("浮岛几乎静止，无需急停。")
		return
	var cost: float = movement_settings.emergency_stop_cost * _mass_energy_ratio()
	if not _consume_energy(cost, "急停"):
		_warn_energy("急停需要 %d E" % int(ceil(cost)))
		return
	if autopilot_active:
		_cancel_autopilot("玩家急停")
	var speed_before := island_velocity.length()
	emergency_braking = true
	control_stun_time = 0.3
	worker_slow_time = 8.0
	screen_shake_time = 0.3
	screen_shake_strength = clampf(speed_before / maxf(1.0, _max_speed()), 0.25, 1.4) * 13.0
	var growing_indices: Array[int] = []
	for index in range(plots.size()):
		if int(plots[index].state) != 0:
			growing_indices.append(index)
	var lost := mini(8, int(ceil(float(growing_indices.size()) * 0.30)))
	for loss_index in range(lost):
		var plot_index := growing_indices[growing_indices.size() - 1 - loss_index]
		var plot: Dictionary = plots[plot_index]
		plot.state = 0
		plot.progress = 0.0
		plots[plot_index] = plot
	emergency_stop_triggered.emit(speed_before)
	_show_notice("紧急制动！消耗 %d E，损失 %d 份未收获作物。" % [int(ceil(cost)), lost], 4.0)
	_play_tone(130.0, 0.22, -5.0)


func _refuel_from_crops(quiet := false) -> void:
	if not development.process_fuel() and not quiet:
		_warn_energy(development.fuel_status())


func _warn_energy(reason: String) -> void:
	energy_warning_text = reason
	energy_warning_left = 3.0
	if energy_label != null:
		energy_label.tooltip_text = reason


func _set_view_mode(mode: int, notice: String = "") -> void:
	if view_mode == mode:
		return
	view_mode = mode
	view_transition_left = movement_settings.view_transition_time
	if mode == VIEW_GOD:
		camera_zoom_target = _default_player_zoom()
		camera_zoom = minf(camera_zoom, _god_zoom_limit())
		_clamp_god_camera()
	else:
		focus_offset = island_bounds.get_center()
		_clamp_focus_offset()
		camera_world = island_pos + focus_offset
		camera_zoom_target = movement_settings.focus_zoom_default
	view_mode_changed.emit(mode)
	if not notice.is_empty():
		_show_notice(notice)
	_play_tone(440.0 if mode == VIEW_GOD else 520.0, 0.08, -17.0)


func _adjust_zoom(amount: float) -> void:
	if view_mode == VIEW_GOD:
		camera_zoom_target = clampf(camera_zoom_target + amount, _default_player_zoom(), movement_settings.focus_zoom_max)
	else:
		camera_zoom_target = clampf(camera_zoom_target + amount, movement_settings.focus_zoom_min, movement_settings.focus_zoom_max)
	view_transition_left = movement_settings.view_transition_time


func _update_camera(delta: float) -> void:
	if view_mode == VIEW_GOD:
		camera_zoom_target = clampf(camera_zoom_target, _default_player_zoom(), movement_settings.focus_zoom_max)
		camera_zoom = clampf(camera_zoom, _default_player_zoom(), movement_settings.focus_zoom_max)
	view_transition_left = maxf(0.0, view_transition_left - delta)
	var zoom_speed := maxf(0.01, absf(camera_zoom_target - camera_zoom) / maxf(0.05, movement_settings.view_transition_time))
	camera_zoom = move_toward(camera_zoom, camera_zoom_target, zoom_speed * delta)
	if view_mode == VIEW_FOCUS:
		_clamp_focus_offset()
		camera_world = island_pos + focus_offset
	else:
		var target: Vector2 = island_pos + _island_visual_bounds().get_center() + island_velocity * movement_settings.camera_look_ahead_seconds
		camera_world = camera_world.lerp(target, 1.0 - exp(-delta / movement_settings.camera_smooth_time))
		_clamp_god_camera()


func _update_focus_pan(delta: float) -> void:
	if view_mode != VIEW_FOCUS or middle_dragging:
		return
	var mouse := get_viewport().get_mouse_position()
	var edge := Vector2.ZERO
	if mouse.x <= 12.0:
		edge.x = -1.0
	elif mouse.x >= VIEW_SIZE.x - 12.0:
		edge.x = 1.0
	if mouse.y <= 12.0:
		edge.y = -1.0
	elif mouse.y >= VIEW_SIZE.y - 12.0:
		edge.y = 1.0
	if edge.length_squared() > 0.0:
		focus_offset += edge.normalized() * movement_settings.edge_pan_speed * delta / camera_zoom
		_clamp_focus_offset()


func _world_to_screen(world_position: Vector2) -> Vector2:
	return VIEW_CENTER + (world_position - camera_world) * camera_zoom


func _screen_to_world(screen_position: Vector2) -> Vector2:
	return camera_world + (screen_position - VIEW_CENTER) / camera_zoom


func _set_map_destination(screen_position: Vector2) -> void:
	if not map_clip.get_global_rect().has_point(screen_position):
		return
	map_destination = _map_to_world(screen_position)
	map_destination_set = true
	map_ink.queue_redraw()
	_show_notice("航向已标记；按 M 返回后手动驾驶。")


func _play_tone(frequency: float, duration: float, volume_db: float) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var mix_rate := 22050
	var sample_count := maxi(1, int(duration * mix_rate))
	var data := PackedByteArray()
	data.resize(sample_count * 2)
	for sample_index in range(sample_count):
		var phase := TAU * frequency * float(sample_index) / float(mix_rate)
		var envelope := 1.0 - float(sample_index) / float(sample_count)
		var sample_value := int(sin(phase) * envelope * 9000.0)
		data.encode_s16(sample_index * 2, sample_value)
	var wave := AudioStreamWAV.new()
	wave.format = AudioStreamWAV.FORMAT_16_BITS
	wave.mix_rate = mix_rate
	wave.stereo = false
	wave.data = data
	var player := AudioStreamPlayer.new()
	player.stream = wave
	player.volume_db = volume_db
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()


func _update_zones(delta: float) -> void:
	weather_elapsed += delta
	weather_refresh -= delta
	if weather_refresh <= 0.0:
		zones = WeatherSystem.regions(island_pos, world_origin, weather_elapsed)
		weather_refresh = 0.25
	current_weather = -1
	var priority := -1
	for index in range(zones.size()):
		var zone: Dictionary = zones[index]
		if island_pos.distance_to(zone.pos) <= zone.radius and int(zone.priority) > priority:
			current_weather = index
			priority = int(zone.priority)
	var kind := "clear" if current_weather < 0 else str(zones[current_weather].kind)
	var wanted_tint := float({"clear": 0.0, "sun": 0.10, "cloud": -0.12, "rain": -0.15, "storm": -0.23, "snow": -0.08, "cyclone": -0.28}[kind])
	weather_tint = move_toward(weather_tint, wanted_tint, delta * 0.15)
	lightning_left = maxf(0.0, lightning_left - delta)
	if kind == "storm":
		lightning_next -= delta
		if lightning_next <= 0.0:
			lightning_left = 0.18
			lightning_next = weather_rng.randf_range(7.0, 14.0)

func _update_weather_hazards(delta: float) -> void:
	var kind := "clear" if current_weather < 0 else str(zones[current_weather].kind)
	if kind not in ["snow", "cyclone"]:
		weather_hazard_left = 8.0
		for plot in plots:
			plot.weather_penalty = 1.0
			plot.weather_kind = ""
		return
	weather_hazard_left -= delta
	if weather_hazard_left > 0.0 or plots.is_empty():
		return
	weather_hazard_left = 8.0 if kind == "snow" else 6.0
	var index := weather_rng.randi_range(0, plots.size() - 1)
	var plot: Dictionary = plots[index]
	plot.weather_kind = kind
	plot.weather_penalty = _plot_weather_penalty(plot)
	plots[index] = plot
	if kind == "cyclone":
		var mitigation: float = development.weather_damage_factor(plot.cell)
		development.damage_cell(plot.cell, 28.0 * mitigation, "飓风破坏", false)
		if int(plot.state) != 0:
			plot.progress = maxf(0.0, float(plot.progress) - 0.35 * mitigation)
			plot.state = 0 if float(development.tile_at(plot.cell).hp) <= 0.0 else 1
		_show_notice("飓风损伤农田并损失作物进度；林木减灾 %d%%，仍需修缮。" % roundi(development.forest_protection(plot.cell) * 100), 4.0)
	else:
		_show_notice("积雪覆盖了一块农田；离开雪区后减速效果解除。", 3.0)

func _update_merchant(delta: float) -> void:
	if merchant_available:
		merchant_stay_left -= delta
		if merchant_stay_left <= 0.0:
			merchant_available = false
			merchant_stay_left = 0.0
			merchant_arrival_left = 210.0
			development.merchant_state_changed()
			_show_notice("流浪商人已离开，交易结束。")
		return
	merchant_arrival_left -= delta
	if merchant_arrival_left <= 0.0:
		merchant_available = true
		merchant_arrival_left = 0.0
		merchant_stay_left = 75.0
		development.merchant_state_changed()
		_show_notice("流浪商人已到访！点击下方金色商店入口购买或出售，停留 75 秒。", 8.0)
		_play_tone(660.0, 0.18, -16.0)


func _plot_weather_penalty(plot: Dictionary) -> float:
	var kind := _weather_kind()
	if kind not in ["snow", "cyclone"] or str(plot.get("weather_kind", "")) != kind: return 1.0
	var base := 0.45 if kind == "snow" else 0.65
	return 1.0 - base * development.weather_damage_factor(plot.cell)


func _update_crops(delta: float) -> void:
	var multiplier := _weather_growth_multiplier()
	for index in range(plots.size()):
		var plot: Dictionary = plots[index]
		if int(plot.state) == 1:
			var tile: Dictionary = development.tile_at(plot.cell)
			var health := maxf(0.25, Development.Rules.tile_health(tile))
			var weather_penalty := _plot_weather_penalty(plot)
			plot.weather_penalty = weather_penalty
			var local_growth := multiplier
			if multiplier < 1.0 and _weather_kind() in ["storm", "snow", "cyclone"]:
				local_growth = minf(maxf(multiplier, 0.85), 1.0 - (1.0 - multiplier) * (1.0 - development.forest_protection(plot.cell)))
			plot.progress = minf(1.0, float(plot.progress) + delta * local_growth * _night_growth() * weather_penalty * health / Development.Rules.CROP_GROW_SECONDS)
			if float(plot.progress) >= 1.0:
				plot.state = 2
				_show_notice("作物成熟了！切换到种植工具后点击收获。")
		plots[index] = plot


func _update_hook(delta: float) -> void:
	var origin := _hook_origin()
	if hook_state == HOOK_READY:
		hook_pos = origin
		return

	if hook_state == HOOK_EXTEND:
		hook_pos += hook_dir * movement_settings.hook_extend_speed * delta
		for index in range(targets.size()):
			var target: Dictionary = targets[index]
			if bool(target.active) and _hook_hits_target(target):
				var lock_reason := _target_lock_reason(target)
				if not lock_reason.is_empty():
					hook_state = HOOK_RETRACT
					grapple_state_changed.emit(hook_state)
					_show_notice(lock_reason + "；当前抓钩无法固定这座岛。", 4.0)
					break
				hooked_target = index
				if target.has("island"):
					target.island.tethered = true
					hook_pos = target.pos
				hook_state = HOOK_RETRACT
				grapple_state_changed.emit(hook_state)
				_show_notice("抓到了%s，正在回收……" % str(target.type))
				break
		if hook_state == HOOK_EXTEND and hook_pos.distance_to(origin) >= hook_max_distance:
			hook_state = HOOK_DANGLE
			hook_dangle_left = movement_settings.hook_dangle_time
			var refund := maxf(0.0, hook_launch_energy_paid - movement_settings.hook_miss_cost * _mass_energy_ratio())
			_add_energy(refund, "抓钩落空返还")
			grapple_state_changed.emit(hook_state)
	elif hook_state == HOOK_DANGLE:
		hook_dangle_left -= delta
		hook_pos.y += 18.0 * delta
		if hook_dangle_left <= 0.0:
			hook_state = HOOK_RETRACT
			grapple_state_changed.emit(hook_state)
	elif hook_state == HOOK_FIXING:
		var attached: Dictionary = targets[hooked_target]
		var center: Vector2 = IslandTiles.bounds(attached.island.tiles).get_center()
		hook_pos = island_pos + Vector2(merge_offset) * IslandTiles.CELL_SIZE + center
		attached.pos = hook_pos
		attached.island.pos = hook_pos
		hook_fixing_left -= delta * (0.5 if worker_slow_time > 0.0 else 1.0)
		if hook_fixing_left <= 0.0:
			_finish_hook()
	else:
		var retract_speed: float = movement_settings.hook_empty_retract_speed
		if hooked_target >= 0:
			var hooked: Dictionary = targets[hooked_target]
			var load_cost: float = (movement_settings.loaded_hook_energy_per_second + movement_settings.loaded_hook_mass_energy_per_second * float(hooked.weight)) * _mass_energy_ratio() * development.hook_efficiency() * delta
			if not _consume_energy(load_cost, "抓钩拖拽"):
				_warn_energy("抓钩负载悬停；R 补能后继续")
				return
			retract_speed *= movement_settings.hook_loaded_retract_ratio / float(hooked.weight)
		hook_pos = hook_pos.move_toward(origin, retract_speed * delta)
		if hooked_target >= 0:
			var attached: Dictionary = targets[hooked_target]
			attached.pos = hook_pos
			if attached.has("island"):
				attached.island.pos = hook_pos
				if _hazard_clearance(attached.island) <= float(movement_settings.tile_size) * 1.5:
					_begin_island_attachment(attached)
					return
			targets[hooked_target] = attached
		if hook_pos.distance_to(origin) < 14.0:
			_finish_hook()


func _update_targets(delta: float) -> void:
	for index in range(targets.size()):
		var target: Dictionary = targets[index]
		if target.has("island"):
			target.pos = target.island.pos
			continue
		if not bool(target.active):
			target.respawn = float(target.respawn) - delta
			if float(target.respawn) <= 0.0:
				if island_bounds.grow(45.0).has_point(Vector2(target.home) - island_pos):
					continue
				target.active = true
				target.pos = target.home
			targets[index] = target


func _hazard_clearance(hazard: Dictionary) -> float:
	if hazard.has("tiles"):
		var bounds: Rect2 = IslandTiles.bounds(hazard.tiles)
		var origin: Vector2 = hazard.pos - bounds.get_center()
		var broad := IslandTiles.rect_clearance(Rect2(island_pos + island_bounds.position, island_bounds.size), Rect2(origin + bounds.position, bounds.size))
		if broad > float(movement_settings.warning_radius_tiles) * float(movement_settings.tile_size): return broad
		return IslandTiles.clearance(island_tiles, island_pos, hazard.tiles, origin)
	# Legacy point hazards are used only by navigation warning probes.
	var local_position: Vector2 = hazard.pos - island_pos
	var relative := (local_position - island_bounds.get_center()).abs() - island_bounds.size * 0.5
	var broad_distance := Vector2(maxf(relative.x, 0.0), maxf(relative.y, 0.0)).length() + minf(maxf(relative.x, relative.y), 0.0) - float(hazard.radius)
	if broad_distance > float(movement_settings.warning_radius_tiles) * float(movement_settings.tile_size):
		return broad_distance
	var closest := INF
	for tile in island_tiles:
		var offset: Vector2 = (local_position - Vector2(tile.cell) * IslandTiles.CELL_SIZE).abs() - IslandTiles.CELL_SIZE * 0.5
		var distance := Vector2(maxf(offset.x, 0.0), maxf(offset.y, 0.0)).length() + minf(maxf(offset.x, offset.y), 0.0)
		closest = minf(closest, distance - float(hazard.radius))
	return closest


func _check_collisions() -> void:
	for index in range(hazards.size()):
		var hazard: Dictionary = hazards[index]
		if not bool(hazard.active) or bool(hazard.tethered) or not hazard.has("tiles"):
			continue
		var bounds: Rect2 = IslandTiles.bounds(hazard.tiles)
		var origin: Vector2 = hazard.pos - bounds.get_center()
		if not Rect2(island_pos + island_bounds.position, island_bounds.size).intersects(Rect2(origin + bounds.position, bounds.size)):
			continue
		var hit: Dictionary = IslandTiles.contact(island_tiles, island_pos, hazard.tiles, origin)
		if hit.is_empty(): continue
		var push: Vector2 = hit.normal
		var impact_speed := maxf(0.0, -island_velocity.dot(push))
		if collision_cooldown <= 0.0 and impact_speed >= 35.0:
			collision_cooldown = 2.0
			var hazard_mass := IslandTiles.mass(hazard.tiles)
			var collision_cost := minf(energy, 8.0 + impact_speed * 0.25 + hazard_mass * 0.5)
			_consume_energy(collision_cost, "碰撞")
			var removed: int = development.collision_at(hit.point, impact_speed, hazard_mass)
			if autopilot_active:
				_cancel_autopilot("发生碰撞")
			_show_notice("撞击崩落 %d 格；质量与速度越大，波及范围越大。" % removed, 5.0)
		# Resolve actual penetration even at low speed or during the damage cooldown.
		island_pos += push * (float(hit.depth) + 1.0) * 0.4
		hazard.pos -= push * (float(hit.depth) + 1.0) * 0.6
		if impact_speed > 0.0: island_velocity += push * impact_speed * 1.35
		return


func _fire_hook(target_position: Vector2) -> void:
	if hook_state != HOOK_READY:
		return
	if development == null or not development.has_facility("grapple"):
		_show_notice("抓钩尚未安装；研究抓钩工程并建造唯一的抓钩小屋。")
		return
	var launch_cost: float = movement_settings.hook_launch_cost * _mass_energy_ratio() * development.hook_efficiency()
	if not _consume_energy(launch_cost, "抓钩发射"):
		_warn_energy("抓钩发射需要 %d E" % int(ceil(launch_cost)))
		return
	var origin := _hook_origin()
	hook_dir = origin.direction_to(target_position)
	if hook_dir.length_squared() < 0.01:
		hook_dir = Vector2.RIGHT
	hook_pos = origin
	hooked_target = -1
	hook_launch_energy_paid = launch_cost
	hook_state = HOOK_EXTEND
	grapple_state_changed.emit(hook_state)
	_show_notice("抓钩发射！右键可以提前收回。")
	_play_tone(720.0, 0.08, -12.0)


func _cancel_hook() -> void:
	if hook_state != HOOK_READY and hook_state != HOOK_FIXING:
		hook_state = HOOK_RETRACT
		grapple_state_changed.emit(hook_state)


func _finish_hook() -> void:
	if hooked_target >= 0:
		var target: Dictionary = targets[hooked_target]
		if target.has("island"):
			var capacity_reason := _island_capacity_reason(target)
			if not capacity_reason.is_empty():
				_release_over_capacity_target(target, capacity_reason)
				return
			for tile in target.island.tiles:
				var added: Dictionary = tile.duplicate(true)
				added.cell = Vector2i(added.cell) + merge_offset
				island_tiles.append(added)
			target.island.active = false
			target.island.tethered = false
			target.active = false
			_refresh_island_shape()
			development.sync()
			merge_ready.emit(target.island)
			_show_notice("%s已接入！+%d 地块 · 当前 %d/%d 格 · 质量 %.1f" % [str(target.type), target.island.tiles.size(), island_tiles.size(), player_tile_limit(), island_mass], 5.0)
		else:
			coins += int(target.value)
			gathered += 1
			_show_notice("回收%s：+%d 金币" % [str(target.type), int(target.value)])
			target.active = false
			target.respawn = 7.0
		targets[hooked_target] = target
	hooked_target = -1
	hook_state = HOOK_READY
	hook_launch_energy_paid = 0.0
	grapple_state_changed.emit(hook_state)
	hook_pos = _hook_origin()


func _hook_hits_target(target: Dictionary) -> bool:
	if not target.has("island"):
		return hook_pos.distance_to(target.pos) < 34.0
	var center: Vector2 = IslandTiles.bounds(target.island.tiles).get_center()
	for tile in target.island.tiles:
		if IslandTiles.cell_rect(target.pos - center, tile.cell).grow(4.0).has_point(hook_pos):
			return true
	return false

func player_tile_limit() -> int:
	return ScaleRules.player_limit(debug_player_tile_limit, OS.is_debug_build())


func _island_capacity_reason(target: Dictionary) -> String:
	if not target.has("island") or bool(target.island.get("shop", false)):
		return ""
	# Technology previews can carry island metadata before terrain is populated.
	var incoming: int = target.island.get("tiles", []).size()
	var remaining := maxi(0, player_tile_limit() - island_tiles.size())
	if incoming > remaining:
		return "岛屿容量不足：当前 %d/%d 格，目标 %d 格，剩余 %d 格；请先剪裁或选择更小的岛" % [island_tiles.size(), player_tile_limit(), incoming, remaining]
	return ""


func _release_over_capacity_target(target: Dictionary, reason: String) -> void:
	target.island.tethered = false
	hooked_target = -1
	hook_state = HOOK_READY
	hook_fixing_left = 0.0
	hook_launch_energy_paid = 0.0
	hook_pos = _hook_origin()
	grapple_state_changed.emit(hook_state)
	_show_notice(reason, 5.0)


func _target_lock_reason(target: Dictionary) -> String:
	if not target.has("island"):
		return ""
	var capacity_reason := _island_capacity_reason(target)
	if not capacity_reason.is_empty():
		return capacity_reason
	var terrain: Dictionary = target.island
	var size_class := int(terrain.get("size_class", 0))
	var required := 2 if size_class >= 2 else (1 if size_class == 1 or bool(terrain.get("shop", false)) else 0)
	if int(development.tech.docking) < required:
		return "需要岛屿对接 %s" % ("II" if required == 2 else "I")
	return ""


func _begin_island_attachment(target: Dictionary) -> void:
	var capacity_reason := _island_capacity_reason(target)
	if not capacity_reason.is_empty():
		_release_over_capacity_target(target, capacity_reason)
		return
	if bool(target.island.get("shop", false)):
		target.island.tethered = false
		hooked_target = -1
		hook_state = HOOK_READY
		hook_launch_energy_paid = 0.0
		hook_pos = _hook_origin()
		development.open_trade("漂流商店岛")
		return
	var occupied: Dictionary = {}
	for tile in island_tiles:
		occupied[tile.cell] = true
	var incoming: Array = target.island.tiles
	var center: Vector2 = IslandTiles.bounds(incoming).get_center()
	var desired: Vector2 = target.pos - island_pos
	var best_score := INF
	var visited: Dictionary = {}
	# Every candidate shares an edge; accept only translations with no occupied cells.
	for host in island_tiles:
		for neighbor in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			for edge in incoming:
				var offset: Vector2i = host.cell + neighbor - edge.cell
				if visited.has(offset):
					continue
				visited[offset] = true
				var overlap := false
				for tile in incoming:
					if occupied.has(Vector2i(tile.cell) + offset):
						overlap = true
						break
				if overlap:
					continue
				var score := (Vector2(offset) * IslandTiles.CELL_SIZE + center).distance_squared_to(desired)
				if score < best_score:
					best_score = score
					merge_offset = offset
	hook_state = HOOK_FIXING
	hook_fixing_left = 2.0
	grapple_state_changed.emit(hook_state)
	_show_notice("工人正在固定%s，地块将按网格接入主岛……" % str(target.type))


func _interact_with_plot(mouse_position: Vector2) -> void:
	for index in range(plots.size()):
		if _plot_rect(index).has_point(mouse_position):
			selected_plot = index
			hovered_plot = index
			_work_plot(index, development.selected_crop)
			return
	_show_notice("请点击农田格；B → 开垦可以增加农田。")


func _work_plot(index: int, planting_crop: int, quiet := false) -> bool:
	if index < 0 or index >= plots.size(): return false
	var plot: Dictionary = plots[index]
	var crop_type: int = planting_crop if int(plot.state) == 0 else int(plot.crop_type)
	var crop_name := _crop_name(crop_type)
	if int(plot.state) == 0:
		var farm_tile: Dictionary = development.tile_at(plot.cell)
		if farm_tile.is_empty() or farm_tile.kind != "farm" or Development.Rules.tile_health(farm_tile) < 1.0:
			if not quiet: _show_notice("农田受损，请右键这格农田选择修缮后再播种。")
			return false
		if seed_stock(crop_type) <= 0:
			if not quiet: _show_notice("%s种子不足：采集草地/林木或向商人购买对应种子。" % crop_name)
			return false
		add_crop_seeds(crop_type, -1)
		plot.crop_type = crop_type
		plot.state = 1
		plot.progress = 0.0
		plot.weather_penalty = 1.0
		if not quiet: _show_notice("播种%s成功，雨水区会让作物生长得更快。" % crop_name)
	elif int(plot.state) == 1:
		if not quiet: _show_notice("%s生长进度 %d%%" % [crop_name, int(float(plot.progress) * 100.0)])
		return false
	else:
		var yield_count: int = development.crop_yield()
		var coin_income: int = development.harvest_coins(crop_type) * yield_count
		coins += coin_income
		add_crop_seeds(crop_type, 1)
		harvested += 1
		if crop_type == CROP_RICE: rice_stock += yield_count
		else: energy_crop_stock += yield_count
		plot.state = 0
		plot.progress = 0.0
		plot.weather_penalty = 1.0
		if not quiet: _show_notice("收获%s ×%d：+%d 金币，返还 1 %s种子" % [crop_name, yield_count, coin_income, crop_name])
	queue_redraw()
	return true


func _random_outer_position(seed_value: int) -> Vector2:
	var angle := fmod(Time.get_ticks_msec() * 0.001 + seed_value * 1.7, TAU)
	var distance := 330.0 + seed_value * 14.0
	return island_pos + Vector2.from_angle(angle) * distance


func _hook_origin() -> Vector2:
	for tile in island_tiles:
		if str(tile.facility) == "grapple":
			return island_pos + Vector2(tile.cell) * IslandTiles.CELL_SIZE + Vector2(24, -12)
	return island_pos


func _plot_rect(index: int) -> Rect2:
	var world_rect := _plot_world_rect(index)
	return Rect2(_world_to_screen(world_rect.position), world_rect.size * camera_zoom)


func _plot_world_rect(index: int) -> Rect2:
	return IslandTiles.cell_rect(island_pos, plots[index].cell).grow(-7.0)


func _crop_name(crop_type: int) -> String:
	return "水稻" if crop_type == CROP_RICE else "番茄"

func seed_stock(crop_type: int) -> int:
	return rice_seeds if crop_type == CROP_RICE else tomato_seeds

func add_crop_seeds(crop_type: int, amount: int) -> void:
	if crop_type == CROP_RICE: rice_seeds += amount
	else: tomato_seeds += amount


func _build_hud() -> void:
	var canvas := CanvasLayer.new()
	canvas.name = "HUD"
	add_child(canvas)

	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(root)

	var backdrop := Control.new()
	backdrop.name = "SkyIslandHeaderCanvas"
	backdrop.set_script(preload("res://scripts/hud_backdrop.gd"))
	backdrop.position = Vector2(6, 4)
	backdrop.size = Vector2(1140, 82)
	root.add_child(backdrop)
	# Keep the compact single row above its decorative floating-island canvas.
	header_row = HBoxContainer.new()
	header_row.name = "TopRow"
	header_row.position = Vector2(14, 8)
	header_row.size = Vector2(1124, 58)
	header_row.add_theme_constant_override("separation", 10)
	root.add_child(header_row)
	var weather_block := HBoxContainer.new()
	weather_block.custom_minimum_size = Vector2(188, 58)
	weather_block.add_theme_constant_override("separation", 6)
	header_row.add_child(weather_block)
	weather_icon = _hud_texture("sun", 38)
	weather_block.add_child(weather_icon)
	var clock_box := VBoxContainer.new()
	clock_box.alignment = BoxContainer.ALIGNMENT_CENTER
	clock_box.add_theme_constant_override("separation", 0)
	weather_block.add_child(clock_box)
	time_label = Label.new()
	time_label.add_theme_font_size_override("font_size", 12)
	time_label.add_theme_color_override("font_color", INK)
	clock_box.add_child(time_label)
	var growth_row := HBoxContainer.new()
	clock_box.add_child(growth_row)
	growth_row.add_child(_hud_texture("growth", 17))
	weather_label = Label.new()
	weather_label.add_theme_font_size_override("font_size", 16)
	growth_row.add_child(weather_label)
	var risk_row := HBoxContainer.new()
	clock_box.add_child(risk_row)
	weather_risk_icon = _hud_texture("damage", 13)
	risk_row.add_child(weather_risk_icon)
	weather_risk = Label.new()
	weather_risk.add_theme_font_size_override("font_size", 11)
	weather_risk.add_theme_color_override("font_color", Color("#a64d39"))
	risk_row.add_child(weather_risk)
	weather_timer = Label.new()
	weather_timer.add_theme_font_size_override("font_size", 11)
	weather_timer.add_theme_color_override("font_color", Color("#584b3b"))
	risk_row.add_child(weather_timer)

	stats_row = HBoxContainer.new()
	stats_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stats_row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	stats_row.add_theme_constant_override("separation", 4)
	header_row.add_child(stats_row)
	for entry in [["land", "地块数量"], ["mass", "岛屿质量"], ["house", "房屋数量"], ["coins", "金币"], ["wood", "木材"], ["stone", "石头"], ["ore", "矿物"], ["magma", "岩浆晶"], ["energy", "能源 / 容量"], ["rice", "水稻库存"], ["tomato", "番茄 / 能源作物库存"], ["rice_seeds", "水稻种子"], ["tomato_seeds", "番茄种子"]]:
		resource_labels[entry[0]] = _add_resource_stat(stats_row, entry[0], entry[1])
	money_label = resource_labels.coins
	energy_label = resource_labels.energy
	fuel_label = resource_labels.tomato

	navigation_buttons = GridContainer.new()
	navigation_buttons.columns = 1
	navigation_buttons.add_theme_constant_override("separation", 2)
	navigation_buttons.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	map_button = _make_icon_button("map", "M · 天空地图")
	map_button.pressed.connect(func() -> void: navigation_view.toggle_map())
	navigation_buttons.add_child(map_button)
	for entry in [["build", "B · 岛屿开发", false], ["tech", "T · 科技树", true]]:
		var button := _make_icon_button(entry[0], entry[1])
		button.pressed.connect(development.toggle.bind(entry[2]))
		navigation_buttons.add_child(button)
	fuel_button = _make_icon_button("energy", "R · 选择能源来源")
	fuel_button.pressed.connect(development.toggle_energy)
	navigation_buttons.add_child(fuel_button)

	var help_button := _make_icon_button("help", "按键指南")
	help_button.pressed.connect(func() -> void: guide_panel.visible = not guide_panel.visible)
	navigation_buttons.add_child(help_button)
	guide_panel = _make_panel(Vector2(8, 90), Vector2(320, 110), Color("#eef2dc"))
	guide_panel.z_index = 6
	root.add_child(guide_panel)
	guide_panel.hide()
	var guide_box := VBoxContainer.new()
	guide_box.add_theme_constant_override("separation", 3)
	guide_panel.add_child(_with_margin(guide_box, 8))
	var guide_header := HBoxContainer.new()
	guide_box.add_child(guide_header)
	var guide_title := Label.new()
	guide_title.text = "按键指南"
	guide_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	guide_title.add_theme_font_size_override("font_size", 14)
	guide_title.add_theme_color_override("font_color", INK)
	guide_header.add_child(guide_title)
	var guide_toggle := _make_small_button("×")
	guide_toggle.custom_minimum_size = Vector2(62, 26)
	guide_toggle.pressed.connect(func() -> void:
		guide_panel.hide()
	)
	guide_header.add_child(guide_toggle)
	guide_body = Label.new()
	guide_body.text = "WASD 驾驶　Space 急停　M 地图\n滚轮缩放　R 能源厂　B 开发 / T 科技\n左侧选工具 · 右键地块操作 · F5 存档\n指向未连接岛屿按 E 查看 · E/Esc 收起"
	guide_body.add_theme_font_size_override("font_size", 12)
	guide_body.add_theme_color_override("font_color", Color("#624635"))
	guide_body.visible = true
	guide_box.add_child(guide_body)

	context_panel = _make_panel(Vector2(8, 90), Vector2(300, 196), Color("#f8eacb"))
	context_panel.z_index = 5
	root.add_child(context_panel)
	var context_box := VBoxContainer.new()
	context_box.add_theme_constant_override("separation", 5)
	context_panel.add_child(_with_margin(context_box, 10))
	context_title_label = Label.new()
	context_title_label.text = "岛屿观察"
	context_title_label.add_theme_font_size_override("font_size", 16)
	context_title_label.add_theme_color_override("font_color", INK)
	context_box.add_child(context_title_label)
	var divider := HSeparator.new()
	context_box.add_child(divider)
	context_label = Label.new()
	context_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	context_label.add_theme_font_size_override("font_size", 12)
	context_label.add_theme_color_override("font_color", Color("#624635"))
	context_box.add_child(context_label)
	var close_details := _make_small_button("收起 · E / Esc")
	close_details.pressed.connect(func(): inspected_island = {}; _update_context_card())
	context_box.add_child(close_details)
	context_panel.hide()

	tool_sidebar = _make_panel(Vector2(8, 90), Vector2(64, 0), Color("#f9e8c3"))
	tool_sidebar.name = "QuickToolsSidebar"
	root.add_child(tool_sidebar)
	var tools_row := VBoxContainer.new()
	tools_row.alignment = BoxContainer.ALIGNMENT_CENTER
	tools_row.add_theme_constant_override("separation", 3)
	tool_sidebar.add_child(_with_margin(tools_row, 5))
	tools_row.add_child(navigation_buttons)
	hook_button = _make_tool_button("抓钩", 2)
	hook_button.pressed.connect(func() -> void: _select_tool(TOOL_HOOK))
	hook_button.custom_minimum_size = Vector2(100, 44)
	tools_row.add_child(hook_button)
	seed_button = _make_tool_button("水稻", 3)
	seed_button.icon = _hud_icon("rice_seeds")
	seed_button.pressed.connect(_select_crop_tool.bind(CROP_RICE))
	seed_button.custom_minimum_size = Vector2(100, 44)
	tools_row.add_child(seed_button)
	tomato_button = _make_tool_button("番茄", 3)
	tomato_button.icon = _hud_icon("tomato_seeds")
	tomato_button.pressed.connect(_select_crop_tool.bind(CROP_TOMATO))
	tomato_button.custom_minimum_size = Vector2(100, 44)
	tools_row.add_child(tomato_button)
	gather_button = _make_tool_button("采集", 5)
	gather_button.icon = load("res://assets/ui/lucide/pickaxe.svg")
	gather_button.name = "GatherButton"
	gather_button.custom_minimum_size = Vector2(100, 44)
	gather_button.pressed.connect(development.select_action.bind("gather"))
	tools_row.add_child(gather_button)
	var tech_button := _make_tool_button("岛屿布局", 1)
	tech_button.icon = load("res://assets/ui/lucide/layout-grid.svg")
	tech_button.name = "IslandLayoutButton"
	tech_button.custom_minimum_size = Vector2(100, 44)
	tech_button.tooltip_text = "整岛剪裁与布局预设"
	tech_button.pressed.connect(development.layout.open)
	tools_row.add_child(tech_button)
	for button in [hook_button, seed_button, tomato_button, gather_button, tech_button]:
		button.add_theme_font_size_override("font_size", 12)
		button.add_theme_constant_override("icon_max_width", 25)
		button.focus_mode = Control.FOCUS_NONE
	var save_button := _make_icon_button("house", "")
	save_button.name = "SaveButton"
	save_button.icon = load("res://assets/ui/lucide/save.svg")
	save_button.pressed.connect(func() -> void: saves.open_menu())
	tools_row.add_child(save_button)
	for button in navigation_buttons.get_children() + [hook_button, seed_button, tomato_button, gather_button, tech_button, save_button]:
		button.text = ""
		button.tooltip_text = ""
		button.custom_minimum_size = Vector2(48, 32)
		button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.expand_icon = true
		button.add_theme_constant_override("icon_max_width", 24)

	notice_label = Label.new()
	notice_label.position = Vector2(24, 588)
	notice_label.size = Vector2(340, 42)
	notice_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	notice_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	notice_label.add_theme_font_size_override("font_size", 14)
	notice_label.add_theme_color_override("font_color", Color.WHITE)
	notice_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	notice_label.add_theme_constant_override("shadow_offset_x", 2)
	notice_label.add_theme_constant_override("shadow_offset_y", 2)
	root.add_child(notice_label)

	# Clip the dense strategic layer, including clouds and predictions, to its frame.
	map_clip = Control.new()
	map_clip.position = MAP_RECT.position + Vector2(4, 42)
	map_clip.size = MAP_RECT.size - Vector2(8, 76)
	map_clip.clip_contents = true
	map_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(map_clip)
	map_ink = Node2D.new()
	map_ink.position = -map_clip.position
	map_clip.add_child(map_ink)
	map_ink.draw.connect(_draw_sky_map_content)

	development.create_ui(root)
	navigation_view = preload("res://scripts/navigation_view.gd").new()
	navigation_view.setup(self, root)
	_build_intro(root)
	saves.create_ui(root)
	_update_tool_styles()
	_update_hud()


func _build_intro(root: Control) -> void:
	intro_panel = _make_panel(Vector2(319, 145), Vector2(514, 346), Color("#fff0c9"))
	root.add_child(intro_panel)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 12)
	intro_panel.add_child(_with_margin(box, 24))

	var title := Label.new()
	title.text = "flying_garden"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", Color("#3e6b3d"))
	box.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Godot 4.7 · 可玩机制测试版"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 16)
	subtitle.add_theme_color_override("font_color", Color("#805d43"))
	box.add_child(subtitle)

	var guide := Label.new()
	guide.text = "先在岛上采集与种田，再研究动力工程建造引擎。\nB 开发 · T 科技 · 详细按键可在左上角随时展开。"
	guide.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	guide.add_theme_font_size_override("font_size", 15)
	guide.add_theme_color_override("font_color", INK)
	guide.add_theme_constant_override("line_spacing", 6)
	box.add_child(guide)

	var start_button := Button.new()
	start_button.text = "开始试玩"
	start_button.custom_minimum_size = Vector2(210, 50)
	start_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	start_button.add_theme_font_size_override("font_size", 20)
	start_button.add_theme_color_override("font_color", Color.WHITE)
	start_button.add_theme_stylebox_override("normal", _button_style(Color("#5c984d"), Color("#3d6d37")))
	start_button.add_theme_stylebox_override("hover", _button_style(Color("#70ad5c"), Color("#3d6d37")))
	start_button.add_theme_stylebox_override("pressed", _button_style(Color("#497d3f"), Color("#315a2d")))
	start_button.pressed.connect(_start_demo)
	box.add_child(start_button)
	var load_button := _make_small_button("读取存档 · 继续旅程")
	load_button.pressed.connect(func() -> void: saves.open_menu())
	box.add_child(load_button)

	var footer := Label.new()
	footer.text = "自由建设你的空岛 · 随时保存，随时继续"
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.add_theme_font_size_override("font_size", 13)
	footer.add_theme_color_override("font_color", Color("#8b684d"))
	box.add_child(footer)


func _start_demo() -> void:
	demo_started = true
	intro_panel.hide()
	_show_notice("开局没有引擎与抓钩。先采集、种田，再用 T 研究科技并用 B 建造。", 7.0)


func _capture_preview(show_map := false, expand_island := false) -> void:
	demo_started = true
	intro_panel.hide()
	selected_tool = TOOL_SEED
	selected_plot = 1
	var preview_plot_a: Dictionary = plots[0]
	preview_plot_a.state = 1
	preview_plot_a.progress = 0.55
	plots[0] = preview_plot_a
	var preview_plot_b: Dictionary = plots[1]
	preview_plot_b.state = 2
	preview_plot_b.progress = 1.0
	plots[1] = preview_plot_b
	if expand_island:
		for target in targets:
			if target.has("island") and target.pos.distance_to(world_origin + Vector2(450, -100)) < 1.0:
				_fire_hook(target.pos)
				for step in range(640):
					_update_hook(0.025)
					if hook_state == HOOK_READY:
						break
				break
	if show_map:
		sky_map_open = true
		map_destination = island_pos + Vector2(1100.0, -620.0)
		map_destination_set = true
	_update_tool_styles()
	if not expand_island:
		_show_notice("天空地图：群岛、物资和天气分布；WASD 平移，点击标记后返回手动驾驶。" if show_map else "主岛由独立地块拼成。用抓钩拖回右上方的小岛，即可扩张。", 8.0)
	for frame in range(4):
		await get_tree().process_frame
	if not show_map and selected_plot >= 0:
		set_process(false)
		hovered_plot = selected_plot
		_set_plot_context(selected_plot)
		queue_redraw()
	await RenderingServer.frame_post_draw
	var preview := get_viewport().get_texture().get_image()
	var preview_name := "navigation-preview.png" if show_map else ("expanded-island-preview.png" if expand_island else "demo-preview.png")
	var preview_path := ProjectSettings.globalize_path("res://../artifacts/game/%s" % preview_name)
	var save_error := preview.save_png(preview_path)
	if save_error != OK:
		push_error("Preview capture failed with error %s" % save_error)
	else:
		print("Preview captured: %s" % preview_path)
	get_tree().quit()

func _capture_development_preview(show_weather := false) -> void:
	demo_started = true
	intro_panel.hide()
	set_physics_process(false)
	if show_weather:
		development.modal.hide()
		zones = [WeatherSystem.region("preview:cyclone", "cyclone", island_pos, WeatherSystem.RAIN_RADIUS, Vector2(-0.4, 0.1), 90.0)]
		current_weather = 0
		weather_tint = -0.28
		weather_hazard_left = 0.0
		_update_weather_hazards(0.1)
	else:
		coins = 999
		rice_stock = 40
		development.materials = {"wood": 99, "stone": 99, "ore": 99, "magma": 9}
		for key in ["engine", "storage", "bioenergy", "hook", "development", "forestry"]:
			development.tech[key] = 1
		development.sync()
		development.toggle(true)
	_update_hud()
	queue_redraw()
	for frame in range(4):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var preview := get_viewport().get_texture().get_image()
	var preview_name := "weather-preview.png" if show_weather else "development-preview.png"
	var preview_path := ProjectSettings.globalize_path("res://../artifacts/game/%s" % preview_name)
	DirAccess.make_dir_recursive_absolute(preview_path.get_base_dir())
	var save_error := preview.save_png(preview_path)
	if save_error != OK:
		push_error("Development preview capture failed with error %s" % save_error)
	else:
		print("Preview captured: %s" % preview_path)
	get_tree().quit()


func _make_panel(panel_position: Vector2, panel_size: Vector2, color: Color) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.position = panel_position
	panel.size = panel_size
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = INK
	style.set_border_width_all(3)
	style.set_corner_radius_all(10)
	style.shadow_color = Color(0.22, 0.14, 0.1, 0.28)
	style.shadow_size = 5
	style.shadow_offset = Vector2(3, 4)
	panel.add_theme_stylebox_override("panel", style)
	return panel


func _with_margin(child: Control, margin_value: int) -> MarginContainer:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", margin_value)
	margin.add_theme_constant_override("margin_top", margin_value)
	margin.add_theme_constant_override("margin_right", margin_value)
	margin.add_theme_constant_override("margin_bottom", margin_value)
	margin.add_child(child)
	return margin


func _hud_icon(key: String) -> Texture2D:
	var original := {"coins": 0, "energy": 1, "rice": 4, "sun": 5, "clear": 5, "rain": 6, "storm": 7}
	if original.has(key): return _icon(int(original[key]))
	return _atlas_region(hud_icon_atlas, Rect2(HUD_ICONS.find(key) * 32, 0, 32, 32))


func _hud_texture(key: String, pixels: int) -> TextureRect:
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(pixels, pixels)
	icon.texture = _hud_icon(key)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return icon


func _make_icon_button(key: String, hint: String) -> Button:
	var button := _make_small_button("")
	button.icon = _hud_icon(key)
	button.expand_icon = true
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.add_theme_constant_override("icon_max_width", 25)
	button.custom_minimum_size = Vector2(28, 32)
	button.tooltip_text = hint
	button.focus_mode = Control.FOCUS_NONE
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	button.add_theme_color_override("icon_hover_color", Color("#fff1b8"))
	button.add_theme_color_override("icon_pressed_color", Color("#ffd875"))
	return button


func _add_resource_stat(parent: HBoxContainer, key: String, caption: String) -> Label:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(82 if key == "energy" else (56 if key == "mass" else 42), 32)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 2)
	row.tooltip_text = caption
	parent.add_child(row)
	var icon := _hud_texture(key, 22)
	icon.tooltip_text = caption
	row.add_child(icon)
	var value := Label.new()
	value.add_theme_font_size_override("font_size", 13)
	value.add_theme_color_override("font_color", INK)
	value.add_theme_color_override("font_shadow_color", Color(1.0, 1.0, 0.88, 0.5))
	value.add_theme_constant_override("shadow_offset_x", 0)
	value.add_theme_constant_override("shadow_offset_y", 1)
	value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value.clip_text = true
	if key == "land":
		value.custom_minimum_size.x = 48
		value.clip_text = false
	value.tooltip_text = caption
	row.add_child(value)
	return value


func _make_small_button(text_value: String) -> Button:
	var button := Button.new()
	button.text = text_value
	button.custom_minimum_size = Vector2(96, 30)
	button.add_theme_font_size_override("font_size", 11)
	button.add_theme_color_override("font_color", INK)
	button.add_theme_color_override("font_hover_color", INK)
	button.add_theme_stylebox_override("normal", _button_style(Color("#d8e8c8"), Color("#688052")))
	button.add_theme_stylebox_override("hover", _button_style(Color("#edf6df"), Color("#526a40")))
	return button


func _make_tool_button(text_value: String, icon_index: int) -> Button:
	var button := Button.new()
	button.text = text_value
	button.icon = _icon(icon_index)
	button.add_theme_constant_override("icon_max_width", 34)
	button.expand_icon = true
	button.custom_minimum_size = Vector2(126, 52)
	button.add_theme_font_size_override("font_size", 14)
	button.add_theme_color_override("font_color", INK)
	button.add_theme_color_override("font_hover_color", INK)
	button.add_theme_color_override("font_pressed_color", INK)
	return button


func _button_style(color: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(3)
	style.set_corner_radius_all(8)
	style.content_margin_left = 10
	style.content_margin_right = 10
	return style


func _icon(index: int) -> AtlasTexture:
	var texture := AtlasTexture.new()
	texture.atlas = icon_atlas
	var atlas_size := icon_atlas.get_size()
	var cell := Vector2(atlas_size.x / 4.0, atlas_size.y / 2.0)
	texture.region = Rect2(Vector2(index % 4, index / 4) * cell, cell)
	return texture


func _select_tool(tool: int) -> void:
	if development.tile_menu != null: development.tile_menu.close()
	development.move_from = development.NONE
	development.trim_pending = development.NONE
	selected_tool = tool
	if selected_tool != TOOL_SEED:
		selected_plot = -1
	if selected_tool == TOOL_SEED and hook_state != HOOK_READY:
		_cancel_hook()
	_update_tool_styles()
	_show_notice("已选择%s工具" % ("抓钩" if tool == TOOL_HOOK else "种植"))

func _select_crop_tool(crop_type: int) -> void:
	development.selected_crop = crop_type
	_select_tool(TOOL_SEED)
	_show_notice("已选择%s；点击空闲农田播种。" % _crop_name(crop_type), 2.0)


func _update_tool_styles() -> void:
	if hook_button == null or seed_button == null or tomato_button == null:
		return
	var selected := _button_style(Color("#ffd875"), Color("#7c512f"))
	var normal := _button_style(Color("#ead1a0"), Color("#9c714e"))
	hook_button.add_theme_stylebox_override("normal", selected if selected_tool == TOOL_HOOK else normal)
	seed_button.add_theme_stylebox_override("normal", selected if selected_tool == TOOL_SEED and development.selected_crop == CROP_RICE else normal)
	tomato_button.add_theme_stylebox_override("normal", selected if selected_tool == TOOL_SEED and development.selected_crop == CROP_TOMATO else normal)
	if gather_button != null:
		gather_button.add_theme_stylebox_override("normal", selected if selected_tool == 2 and development.action == "gather" else normal)
		gather_button.add_theme_stylebox_override("hover", _button_style(Color("#ffe39a"), Color("#7c512f")))
	hook_button.add_theme_stylebox_override("hover", _button_style(Color("#ffe39a"), Color("#7c512f")))
	seed_button.add_theme_stylebox_override("hover", _button_style(Color("#ffe39a"), Color("#7c512f")))
	tomato_button.add_theme_stylebox_override("hover", _button_style(Color("#ffe39a"), Color("#7c512f")))


func _tick_hud(delta: float) -> void:
	hud_refresh_left -= delta
	if not optimized_rendering or hud_refresh_left <= 0.0:
		_update_hud()


func _update_hud() -> void:
	hud_refresh_left = 0.1
	if money_label == null:
		return
	tool_sidebar.visible = demo_started and not sky_map_open and not development.modal.visible and not navigation_view.paused()
	money_label.text = str(coins)
	energy_label.text = "%d/%d%s" % [int(energy), int(energy_capacity), " !" if energy < energy_capacity * 0.2 or energy_warning_left > 0.0 else ""]
	energy_label.tooltip_text = energy_warning_text if energy_warning_left > 0.0 else development.fuel_status() + "；R 选择来源"
	if energy / energy_capacity < 0.2 or energy_warning_left > 0.0:
		energy_label.add_theme_color_override("font_color", Color("#b87626"))
	else:
		energy_label.add_theme_color_override("font_color", INK)
	resource_labels.rice_seeds.text = str(rice_seeds)
	resource_labels.tomato_seeds.text = str(tomato_seeds)
	fuel_label.text = str(energy_crop_stock)
	resource_labels.land.text = "%d/%d" % [island_tiles.size(), player_tile_limit()]
	resource_labels.mass.text = "%.1f" % island_mass
	var houses := 0
	for tile in island_tiles:
		if not str(tile.facility).is_empty(): houses += 1
	resource_labels.house.text = str(houses)
	resource_labels.rice.text = str(rice_stock)
	for key in development.materials:
		resource_labels[key].text = str(development.materials[key])
	for key in resource_labels:
		var label: Label = resource_labels[key]
		if key == "land":
			label.tooltip_text = "岛屿地块：%d/%d；剩余 %d 格。常规发展目标 %d 格；合岛必须整座接入，商店交易不占容量。" % [island_tiles.size(), player_tile_limit(), maxi(0, player_tile_limit() - island_tiles.size()), ScaleRules.PLAYER_TYPICAL_TILES]
			label.add_theme_color_override("font_color", Color("#b87626") if island_tiles.size() >= player_tile_limit() else INK)
		elif key != "energy":
			var exact := float(label.text)
			label.tooltip_text = "%s：%s" % [label.get_parent().tooltip_text, label.text]
			if exact >= 1000000.0: label.text = "%.1fM" % (exact / 1000000.0)
			elif exact >= 10000.0: label.text = "%.0fk" % (exact / 1000.0)
			elif exact >= 1000.0: label.text = "%.1fk" % (exact / 1000.0)
		label.add_theme_font_size_override("font_size", 11 if label.text.length() > 3 else 13)
	var hour := int(day_minutes / 60.0)
	var minute := int(day_minutes) % 60
	time_label.text = "%s %d · %02d:%02d" % ["夜" if _night_growth() < 1.0 else "昼", day_number, hour, minute]
	time_label.tooltip_text = "18:00–06:00 夜间；作物生长乘以 80%，天气效果仍生效"
	var kind := _weather_kind()
	weather_icon.texture = _hud_icon(kind)
	weather_icon.tooltip_text = WeatherSystem.NAMES.get(kind, "普通气候")
	var growth := _growth_multiplier()
	weather_label.text = "%s ×%.2f" % ["↑" if growth > 1.0 else ("↓" if growth < 1.0 else "·"), growth]
	weather_label.add_theme_color_override("font_color", Color("#487344") if growth >= 1.0 else Color("#b2503d"))
	weather_label.tooltip_text = "作物生长速度 ×%.2f（已计入天气预报科技与夜间倍率）" % growth
	weather_timer.text = "◷ %ds" % ceili(zones[current_weather].remaining) if current_weather >= 0 else "—"
	weather_timer.tooltip_text = "当前天气剩余时间"
	weather_risk_icon.visible = kind in ["snow", "cyclone"] or int(development.tech.forecast) > 0
	weather_risk_icon.texture = _hud_icon("damage" if kind in ["snow", "cyclone"] else "shield")
	weather_risk.text = ""
	weather_risk.tooltip_text = ""
	if kind == "cyclone":
		weather_risk.text = "−%.0f / 6s" % (28.0 * (1.0 - 0.18 * int(development.tech.forecast)))
		weather_risk.tooltip_text = "每 6 秒随机农田受损并损失作物进度。附近林木与预报科技可减灾，但至少承受 20% 损伤；离开后仍需修缮。"
	elif kind == "snow":
		weather_risk.text = "−45% / 8s"
		weather_risk.tooltip_text = "每 8 秒积雪覆盖随机农田，基础额外减速 45%；林木和预报可减轻，离开雪区后解除。"
	elif int(development.tech.forecast) > 0:
		weather_risk.text = "+%d" % int(development.tech.forecast)
		weather_risk.tooltip_text = "天气预报等级：强化天气增益、减轻天气损失"
	navigation_buttons.tooltip_text = ""
	map_button.modulate = Color("#ffda82") if sky_map_open else Color.WHITE
	seed_button.text = ""
	tomato_button.text = ""
	for button in [map_button, seed_button, tomato_button, hook_button, fuel_button]:
		button.tooltip_text = ""
	hook_button.disabled = not development.has_facility("grapple")
	fuel_button.disabled = false
	if sky_map_open: context_panel.hide()
	map_clip.visible = sky_map_open
	if sky_map_open:
		map_ink.queue_redraw()
	development.update()


func _island_at_pointer(world_position: Vector2) -> Dictionary:
	if sky_map_open or view_mode != VIEW_GOD: return {}
	if not development.tile_at(development.cell_at(world_position)).is_empty(): return {}
	for hazard in hazards:
		if not bool(hazard.get("active", false)) or not hazard.has("tiles") or not _radar_visible(hazard.pos): continue
		var origin: Vector2 = hazard.pos - IslandTiles.bounds(hazard.tiles).get_center()
		for tile in hazard.tiles:
			if IslandTiles.cell_rect(origin, tile.cell).has_point(world_position): return hazard
	return {}

func _toggle_island_details(world_position: Vector2) -> void:
	if not inspected_island.is_empty():
		inspected_island = {}
	elif get_viewport().gui_get_hovered_control() == null:
		inspected_island = _island_at_pointer(world_position)
	_update_context_card()

func _update_context_card() -> void:
	context_panel.hide()
	if sky_map_open or development.modal.visible or development.tile_menu.is_open() or guide_panel.visible:
		inspected_island = {}
	if not inspected_island.is_empty():
		var still_present := false
		for hazard in hazards:
			if is_same(hazard, inspected_island): still_present = true; break
		if not still_present or not bool(inspected_island.get("active", false)) or view_mode != VIEW_GOD or not _radar_visible(inspected_island.pos):
			inspected_island = {}
	if not inspected_island.is_empty():
		var island: Dictionary = inspected_island
		context_title_label.text = "商店岛" if bool(island.get("shop", false)) else "未连接岛屿"
		context_label.text = "%s · %s\n%d 格 / 质量 %.1f\n%s" % [str(island.get("name", "野外岛屿")), str(island.get("rarity", "普通")), island.tiles.size(), IslandTiles.mass(island.tiles), str(island.get("report", "尚未勘探；接入后采集"))]
		for target in targets:
			if target.has("island") and is_same(target.island, island):
				var reason := _target_lock_reason(target)
				if not reason.is_empty(): context_label.text += "\n锁定：" + reason
				break
		context_panel.show()
	tool_sidebar.visible = not context_panel.visible and not development.modal.visible and not development.tile_menu.is_open() and not guide_panel.visible
	development.market_ui.update()

func _fit_context_panel() -> void:
	if context_panel == null or context_label == null:
		return
	var line_count: int = maxi(1, context_label.text.count("\n") + 1)
	context_panel.size.y = clampf(64.0 + line_count * 18.0, 118.0, 188.0)


func _set_plot_context(index: int) -> void:
	var plot: Dictionary = plots[index]
	var crop_type: int = development.selected_crop if int(plot.state) == 0 else int(plot.crop_type)
	var crop_name := _crop_name(crop_type)
	var yield_count: int = development.crop_yield()
	var income: int = development.harvest_coins(crop_type) * yield_count
	context_title_label.text = "农田地块 · %d,%d" % [int(plot.cell.x), int(plot.cell.y)]
	if int(plot.state) == 0:
		context_label.text = "%s田 · 空闲\n播种 −1 %s种子（库存 %d）\n预计产量 ×%d · %d 金" % [crop_name, crop_name, seed_stock(crop_type), yield_count, income]
	elif int(plot.state) == 1:
		context_label.text = "%s · 生长 %d%%\n约 %d 秒成熟\n综合效率 ×%.2f" % [crop_name, int(float(plot.progress) * 100.0), _crop_seconds_left(plot), _growth_multiplier() * float(plot.get("weather_penalty", 1.0))]
	else:
		context_label.text = "%s · 成熟\n收获 ×%d · %d 金\n能源工厂：每份 %d E" % [crop_name, yield_count, income, _crop_energy(int(plot.crop_type))]
	var farm: Dictionary = development.tile_at(plot.cell)
	if float(farm.get("hp", 100.0)) < 100.0:
		context_label.text += "\n\n受损 %d/100 · 禁止播种\n修缮：%s" % [farm.hp, Development.Rules.cost_text(development.repair_cost(plot.cell))]


func _growth_multiplier() -> float:
	return _weather_growth_multiplier() * _night_growth()

func _night_growth() -> float:
	return 0.8 if day_minutes >= 18.0 * 60.0 or day_minutes < 6.0 * 60.0 else 1.0

func _night_strength() -> float:
	var hour := day_minutes / 60.0
	if hour >= 18.0: return clampf((hour - 18.0) / 2.0, 0.0, 1.0)
	if hour < 6.0: return clampf((6.0 - hour) / 2.0, 0.0, 1.0)
	return 0.0

func _weather_growth_multiplier() -> float:
	if current_weather < 0:
		return 1.0
	var zone: Dictionary = zones[current_weather]
	return development.weather_growth(str(zone.kind), float(zone.growth))


func _weather_kind() -> String:
	return "clear" if current_weather < 0 or current_weather >= zones.size() else str(zones[current_weather].kind)


func _crop_energy(crop_type: int) -> int:
	return development.crop_energy(crop_type)


func _crop_seconds_left(plot: Dictionary) -> int:
	return int(ceil((1.0 - float(plot.progress)) * Development.Rules.CROP_GROW_SECONDS / maxf(0.01, _growth_multiplier() * float(plot.get("weather_penalty", 1.0)))))


func _show_notice(text_value: String, duration := 3.0) -> void:
	if notice_label == null:
		return
	notice_label.text = text_value
	notice_time = duration


func _draw() -> void:
	if sky_map_open:
		material = null
		_draw_sky()
		if sky_map_open: _draw_sky_map()
		return
	if optimized_rendering:
		crop_renderer.begin_frame(animation_time, wind_strength)
		if material != crop_renderer.material: material = crop_renderer.material
	else:
		if material != null: material = null
	_draw_sky()
	var shake := Vector2.ZERO
	if screen_shake_time > 0.0:
		var phase := Time.get_ticks_msec() * 0.09
		shake = Vector2(sin(phase), cos(phase * 1.37)) * screen_shake_strength * (screen_shake_time / 0.3)
	draw_set_transform(VIEW_CENTER + shake - camera_world * camera_zoom, 0.0, Vector2(camera_zoom, camera_zoom))
	_draw_targets()
	_draw_islands()
	_draw_hook()
	if explorer != null: explorer.draw_ship()
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_draw_weather_effects()
	_draw_night_lights()
	_draw_warning_overlay()
	_draw_soft_boundary_overlay()
	_draw_destination_bearing()
	if sky_map_open:
		_draw_sky_map()
	if optimized_rendering: crop_renderer.end_frame()


func _draw_sky() -> void:
	draw_rect(Rect2(Vector2.ZERO, VIEW_SIZE), SKY_TOP)
	for line in range(12):
		var blend := float(line) / 11.0
		var color := SKY_TOP.lerp(SKY_BOTTOM, blend).lerp(Color("#162d50").lerp(Color("#405473"), blend), _night_strength())
		draw_rect(Rect2(0, line * VIEW_SIZE.y / 12.0, VIEW_SIZE.x, VIEW_SIZE.y / 12.0 + 1.0), color)
	if _night_strength() > 0.0:
		for star in range(60):
			var point := Vector2(posmod(star * 179 + 27, 1152), posmod(star * 83 + 19, 530))
			draw_circle(point, 1.2, Color(0.85, 0.95, 1.0, _night_strength() * (0.45 + 0.25 * sin(animation_time + star))))
	var drift := fmod(animation_time * 12.0, VIEW_SIZE.x + 300.0) - 150.0
	_draw_cloud(Vector2(drift, 118), 0.8)
	_draw_cloud(Vector2(fmod(drift + 520.0, VIEW_SIZE.x + 260.0) - 100.0, 235), 0.58)
	_draw_cloud(Vector2(fmod(drift + 930.0, VIEW_SIZE.x + 300.0) - 120.0, 520), 0.72)


func _draw_cloud(position_value: Vector2, scale_value: float) -> void:
	var cloud_color := Color(1, 1, 1, 0.42).lerp(Color(0.38, 0.49, 0.69, 0.24), _night_strength())
	draw_circle(position_value, 32.0 * scale_value, cloud_color)
	draw_circle(position_value + Vector2(31, 3) * scale_value, 24.0 * scale_value, cloud_color)
	draw_circle(position_value + Vector2(-34, 7) * scale_value, 22.0 * scale_value, cloud_color)
	draw_rect(Rect2(position_value + Vector2(-42, 2) * scale_value, Vector2(84, 25) * scale_value), cloud_color)


func _draw_targets() -> void:
	if view_mode == VIEW_FOCUS: return
	for target in targets:
		if not bool(target.active) or target.has("island") or not _radar_visible(target.pos) or not _world_visible(target.pos, 40.0):
			continue
		var position_value: Vector2 = target.pos
		var type_value := str(target.type)
		draw_circle(position_value + Vector2(3, 6), 24, Color(0.18, 0.17, 0.18, 0.18))
		if type_value == "金币箱":
			draw_rect(Rect2(position_value - Vector2(23, 17), Vector2(46, 34)), Color("#a86735"))
			draw_rect(Rect2(position_value - Vector2(23, 17), Vector2(46, 34)), INK, false, 3.0)
			draw_rect(Rect2(position_value - Vector2(4, 17), Vector2(8, 34)), Color("#e7ba45"))
			draw_circle(position_value, 5, Color("#ffe06a"))
		elif type_value == "旧齿轮":
			draw_circle(position_value, 23, Color("#7f8c91"))
			draw_circle(position_value, 10, SKY_TOP)
			draw_arc(position_value, 23, 0, TAU, 12, INK, 3.0)
		else:
			draw_circle(position_value, 22, Color("#9c643b"))
			draw_rect(Rect2(position_value - Vector2(22, 5), Vector2(44, 10)), Color("#d39b52"))
			draw_arc(position_value, 22, 0, TAU, 24, INK, 3.0)


func _island_draw_order() -> Array[int]:
	var ordered: Array[int] = [-1]
	if view_mode == VIEW_FOCUS: return ordered
	for index in range(hazards.size()):
		var hazard: Dictionary = hazards[index]
		if not bool(hazard.active) or not _radar_visible(hazard.pos) or not _world_visible(hazard.pos, 200.0):
			continue
		ordered.append(index)
	# Wild island positions are footprint centers; use the same anchor for the player.
	var player_y := island_pos.y + island_bounds.get_center().y
	ordered.sort_custom(func(a: int, b: int) -> bool:
		var ay: float = player_y if a == -1 else hazards[a].pos.y
		var by: float = player_y if b == -1 else hazards[b].pos.y
		return a < b if ay == by else ay < by)
	return ordered


func _draw_islands() -> void:
	for index in _island_draw_order():
		if index == -1:
			_draw_island()
		else:
			_draw_hazard(hazards[index])


func _draw_hazard(hazard: Dictionary) -> void:
	var p: Vector2 = hazard.pos
	var bounds: Rect2 = IslandTiles.bounds(hazard.tiles)
	if optimized_rendering:
		var cache_key := "%s:%s" % [hazard.get("world_key", p), hazard.get("world_index", 0)]
		if not nearby_terrain_cache.has(cache_key): nearby_terrain_cache[cache_key] = preload("res://scripts/terrain_mesh_cache.gd").new()
		nearby_terrain_cache[cache_key].draw(self, p - bounds.get_center(), hazard.tiles, terrain_textures, IslandTiles)
	else:
		IslandTiles.draw_shadow(self, p - bounds.get_center(), hazard.tiles)
		IslandTiles.draw_ground(self, p - bounds.get_center(), hazard.tiles, IslandTiles.CELL_SIZE, terrain_textures)
	IslandTiles.draw_decor(self, p - bounds.get_center(), hazard.tiles, IslandTiles.CELL_SIZE, int(hazard.biome) == 1, tree_texture, true, animation_time, wind_strength, _tree_pointer())


func _draw_island() -> void:
	var p := island_pos
	if optimized_rendering:
		terrain_mesh_cache.draw(self, p, island_tiles, terrain_textures, IslandTiles)
	else:
		IslandTiles.draw_shadow(self, p, island_tiles)
		IslandTiles.draw_ground(self, p, island_tiles, IslandTiles.CELL_SIZE, terrain_textures)

	var ordered := ordered_tiles
	var plot_indices: Dictionary = {}
	for index in range(plots.size()):
		plot_indices[plots[index].cell] = index
	var visible_world := Rect2(_screen_to_world(Vector2.ZERO), VIEW_SIZE / camera_zoom).grow(16.0)
	for tile in ordered:
		# Include full roofs, tree canopies, crop sway and damage labels, not just
		# the cell footprint. Simulation and collisions continue outside the view.
		if optimized_rendering and not visible_world.intersects(IslandTiles.cell_rect(p, tile.cell).grow(160.0)):
			continue
		if plot_indices.has(tile.cell):
			_draw_plot(int(plot_indices[tile.cell]))
		IslandTiles.draw_decor(self, p, [tile], IslandTiles.CELL_SIZE, false, tree_texture, true, animation_time, wind_strength, _tree_pointer())
		var center: Vector2 = IslandTiles.cell_rect(p, tile.cell).get_center()
		var facility := str(tile.facility)
		if facility == "grapple":
			_draw_building(grapple_hut_texture, center + Vector2(12, 20), 100.0, facility)
		elif facility == "water":
			_draw_building(water_grain_hut_texture, center + Vector2(6, 20), 88.0, facility)
		elif facility == "energy":
			_draw_building(energy_conversion_texture, center + Vector2(6, 20), 88.0, facility)
		elif facility == "power":
			_draw_building(power_hut_texture, center + Vector2(0, 20), 92.0, facility)
		elif facility == "harbor":
			_draw_harbor(self, center)
		elif facility == "farm_hut":
			_draw_building(farm_hut_texture(tile), center + Vector2(0, 20), 80.0, "farm_hut")
		if facility != "":
			draw_string(ThemeDB.fallback_font, center + Vector2(-22, 32), "Lv.%d" % int(tile.get("level", 1)), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, INK)
		if Development.Rules.tile_health(tile) < 1.0:
			draw_line(center + Vector2(-25, -10), center + Vector2(16, 15), Color("#683b35"), 3.0)
			draw_rect(Rect2(center + Vector2(-28, 22), Vector2(56, 5)), INK)
			draw_rect(Rect2(center + Vector2(-28, 22), Vector2(56 * Development.Rules.tile_health(tile), 5)), Color("#e69a4b"))
	if selected_tool == 2:
		var selected_cell: Vector2i = development.cell_at(_screen_to_world(get_viewport().get_mouse_position()))
		if not development.tile_at(selected_cell).is_empty():
			draw_rect(IslandTiles.cell_rect(p, selected_cell).grow(-2), Color("#ffe88d"), false, 3.0)
		if development.trim_pending != development.NONE:
			draw_rect(IslandTiles.cell_rect(p, development.trim_pending), Color(1.0, 0.2, 0.15, 0.3))
	if development.tile_menu != null and development.tile_menu.is_open():
		draw_rect(IslandTiles.cell_rect(p, development.tile_menu.cell).grow(-2), Color("#ffe88d"), false, 3.0)
	_draw_management_range()


func _tree_pointer() -> Vector2:
	if sky_map_open or not demo_started or development.modal.visible: return Vector2.INF
	if get_viewport().gui_get_hovered_control() != null: return Vector2.INF
	return _screen_to_world(get_viewport().get_mouse_position())


func _draw_management_range() -> void:
	var cell: Vector2i = development.tile_menu.cell if development.tile_menu.is_open() else development.cell_at(_tree_pointer()) if _tree_pointer().is_finite() else development.NONE
	var hut: Dictionary = development.tile_at(cell)
	if hut.is_empty() or str(hut.facility) != "farm_hut": return
	var radius: int = development.farm_radius(hut)
	for tile in island_tiles:
		if tile.kind == "farm" and Vector2(tile.cell).distance_to(Vector2(cell)) <= radius:
			draw_rect(IslandTiles.cell_rect(island_pos, tile.cell).grow(-3), Color(0.42, 0.9, 0.62, 0.25))
	var points := _ellipse_points(island_pos + Vector2(cell) * IslandTiles.CELL_SIZE, IslandTiles.CELL_SIZE * radius, 64)
	points.append(points[0])
	draw_polyline(points, Color("#a7f0ad"), 2.0)

func _draw_harbor(canvas: Node2D, center: Vector2) -> void:
	canvas.draw_rect(Rect2(center + Vector2(-34, -12), Vector2(68, 35)), Color("#837351"))
	for pier in range(5): canvas.draw_line(center + Vector2(-28 + pier * 14, -12), center + Vector2(-28 + pier * 14, 23), Color("#c7b28a"), 3.0)
	canvas.draw_arc(center, 22, 0, TAU, 24, Color("#a7dfe5"), 2.0)

func _draw_building(texture: Texture2D, bottom_center: Vector2, width: float, kind := "water", canvas: Node2D = self) -> void:
	var source_size := water_grain_hut_texture.get_size() if kind == "energy" else texture.get_size()
	var size := Vector2(width, width * source_size.y / source_size.x)
	var destination := Rect2(bottom_center - Vector2(size.x * 0.5, size.y), size)
	if kind == "energy":
		EnergyConversionUI.draw_element(canvas, energy_conversion_source, destination, animation_time, EnergyConversionUI.GAME_REGION)
	elif kind == "power":
		engine_room_animation.draw(canvas, texture, destination, animation_time * 2.8)
	else:
		canvas.draw_texture_rect(texture, destination, false)
	# Farm cottages have no chimney or energy tank in the approved artwork.
	if kind == "farm_hut": return
	var phase := bottom_center.x * 0.03 + bottom_center.y * 0.02
	var chimney_uv: Vector2 = {"water": Vector2(0.49, 0.06), "energy": Vector2(0.49, 0.06), "power": Vector2(0.88, 0.07), "grapple": Vector2(0.17, 0.10)}[kind]
	_draw_chimney_smoke(destination.position + size * chimney_uv, phase, kind == "power" or kind == "energy", canvas)
	if kind == "water":
		var light := destination.position + size * Vector2(0.81, 0.79)
		var glow := 0.20 + (sin(animation_time * 2.5 + phase) + 1.0) * 0.12
		canvas.draw_rect(Rect2(light - Vector2(4, 5), Vector2(8, 10)), Color(0.86, 1.0, 0.43, glow))
	elif kind == "grapple":
		var lamp := destination.position + size * Vector2(0.12, 0.67)
		canvas.draw_rect(Rect2(lamp, Vector2(4, 5)), Color(1.0, 0.75, 0.32, 0.28 + sin(animation_time * 3.0 + phase) * 0.15))


func _smoke_puff(age: float, phase: float) -> Dictionary:
	# Keep all ordinary-weather samples identical; cyclone gusts disperse puffs.
	var gale := smoothstep(0.65, 1.6, wind_strength)
	var drift := -minf(wind_strength, 0.4) * age * 8.0 + sin(age * 4.0 + phase) * age * 2.0
	drift -= gale * (age * 135.0 + age * age * 100.0)
	var gust := sin(animation_time * 5.3 + phase + age * 7.0) * gale * age * 8.0
	var opacity := smoothstep(0.0, 0.08, age) * (1.0 - smoothstep(0.62, 1.0, age)) * 0.88
	opacity *= 1.0 - gale * smoothstep(0.12, 0.58, age)
	return {"offset": Vector2(drift, -age * 86.0 * (1.0 - gale * 0.55) + gust),
		"radius": 2.5 + age * 3.8, "stretch": Vector2(1.0 + gale * age * 3.0, 1.0 + gale * age * 0.4), "opacity": opacity}

func _draw_chimney_smoke(chimney: Vector2, phase: float, busy: bool, canvas: Node2D = self) -> void:
	var silhouette := PackedVector2Array([
		Vector2(-1.5, 0.35), Vector2(-1.6, -0.1), Vector2(-1.3, -0.65),
		Vector2(-0.65, -0.7), Vector2(-0.4, -1.15), Vector2(0.2, -1.25),
		Vector2(0.75, -0.9), Vector2(0.85, -0.45), Vector2(1.3, -0.35),
		Vector2(1.6, 0.1), Vector2(1.35, 0.6), Vector2(-1.0, 0.6)])
	for puff in range(4):
		var age := fposmod(animation_time / (4.0 if busy else 4.8) + phase * 0.13 + float(puff) / 4.0, 1.0)
		var sample := _smoke_puff(age, phase)
		var p: Vector2 = chimney + sample.offset
		var points := PackedVector2Array()
		for point in silhouette: points.append(p + point * float(sample.radius) * sample.stretch)
		canvas.draw_colored_polygon(points, Color(1.0, 1.0, 1.0, sample.opacity))


func _draw_plot(index: int) -> void:
	var base_rect := _plot_world_rect(index)
	var is_hovered := index == hovered_plot and not sky_map_open
	var is_selected := index == selected_plot
	var lift := 3.0 if is_hovered else (1.0 if is_selected else 0.0)
	var rect := Rect2(base_rect.position - Vector2(0, lift), base_rect.size)
	var plot: Dictionary = plots[index]
	var state := int(plot.state)
	var border := PLOT_HOVER if is_hovered else (PLOT_SELECTED if is_selected else PLOT_FRAME)
	var border_width := 4 if is_hovered or is_selected else 3

	# Keep flight view clear; planting/hover/selection still shows plot status.
	var show_status := selected_tool == TOOL_SEED or is_hovered or is_selected
	if show_status:
		draw_rect(Rect2(rect.position + Vector2(8, 8), Vector2(8, 4)), Color("#e7d06a") if int(plot.crop_type) == CROP_RICE else Color("#d96b50"))
	if is_hovered or is_selected:
		draw_rect(rect.grow(-6.0), border, false, border_width)
	if state == 0:
		for hole_x in range(3):
			draw_circle(rect.position + Vector2(25 + hole_x * 15, 29), 2.0, Color("#6e402e"))
		if is_hovered and selected_tool == TOOL_SEED:
			var center := rect.get_center()
			draw_line(center - Vector2(6, 0), center + Vector2(6, 0), PLOT_HOVER, 3.0)
			draw_line(center - Vector2(0, 6), center + Vector2(0, 6), PLOT_HOVER, 3.0)
		return
	var progress := float(plot.progress)
	_draw_crop_plants(self, plot, rect)
	if not show_status:
		return
	if state == 1:
		var bar_rect := Rect2(rect.position + Vector2(7, rect.size.y - 10), Vector2(rect.size.x - 14, 6))
		draw_rect(bar_rect.grow(2), Color("#4c3027"))
		draw_rect(bar_rect, Color("#e8d6a7"))
		draw_rect(Rect2(bar_rect.position, Vector2(bar_rect.size.x * progress, bar_rect.size.y)), PLOT_GROWING)
	else:
		var pulse := 1.0 + sin(Time.get_ticks_msec() * 0.008 + index) * 0.18
		var badge_center := rect.position + Vector2(rect.size.x - 10, 10)
		draw_circle(badge_center, 8.0 * pulse, Color(PLOT_READY, 0.24))
		draw_circle(badge_center, 5.0, PLOT_READY)
		draw_line(badge_center + Vector2(0, -3), badge_center + Vector2(0, 1), Color("#6a3d25"), 2.0)
		draw_circle(badge_center + Vector2(0, 4), 1.0, Color("#6a3d25"))


func _draw_crop_plants(canvas: Node2D, plot: Dictionary, rect: Rect2) -> void:
	var state := int(plot.state)
	if state == 0: return
	var progress := float(plot.progress)
	var stage := CROP_STAGE_COUNT - 1 if state == 2 else clampi(int(floor(progress * 4.0)), 0, CROP_STAGE_COUNT - 2)
	var crop_texture := rice_atlas if int(plot.crop_type) == CROP_RICE else tomato_atlas
	var rice := int(plot.crop_type) == CROP_RICE
	var source_rect: Rect2 = RICE_FRAMES[stage] if rice else TOMATO_FRAMES[stage]
	var source_scale := 30.0 / 498.0 if rice else 32.0 / 495.0
	var baseline := 628.0 if rice else 616.0
	var sprite_size := source_rect.size * source_scale
	var phase := float(plot.cell.x) * 1.8 + float(plot.cell.y) * 2.4
	# Fill the three soil rows with nine plants; each tile remains one crop.
	# Paint rear rows first, preserving each crop's original mature height.
	if optimized_rendering and canvas == self:
		crop_renderer.draw(canvas, plot.cell, crop_texture, source_rect, source_scale, baseline, stage, rect.get_center())
	else:
		for row in range(3):
			for column in range(3):
				var root_offset := Vector2((column - 1) * 18.0, -3.0 + row * 12.0)
				var root := rect.get_center() + root_offset
				var destination := Rect2(root - Vector2(sprite_size.x * 0.5, baseline * source_scale), sprite_size)
				var plant_phase := phase + row * 0.35 + column * 0.25
				var bend := IslandTiles.wind_bend(animation_time, plant_phase, wind_strength) * 4.0 * (0.45 + float(stage) * 0.14)
				IslandTiles.draw_wind_sprite(canvas, crop_texture, destination, source_rect, root.y, bend)


func _plot_style(fill: Color = SOIL_LIGHT, border: Color = SOIL, width: int = 3) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(7)
	return style


func _draw_hook() -> void:
	var origin := _hook_origin()
	if hook_state == HOOK_READY:
		return
	draw_line(origin, hook_pos, Color("#e4d6ba"), 4.0)
	draw_line(origin, hook_pos, INK, 1.0)
	var angle := hook_dir.angle()
	var hook_points := PackedVector2Array([
		hook_pos + Vector2(-9, -7).rotated(angle),
		hook_pos + Vector2(8, 0).rotated(angle),
		hook_pos + Vector2(-9, 8).rotated(angle)
	])
	draw_polyline(hook_points, Color("#dce2df"), 5.0)
	draw_polyline(hook_points, INK, 1.5)
	if hook_state == HOOK_FIXING:
		var progress := 1.0 - hook_fixing_left / 2.0
		var progress_origin := hook_pos + Vector2(-42, 56)
		draw_rect(Rect2(progress_origin, Vector2(84, 8)), INK)
		draw_rect(Rect2(progress_origin + Vector2(2, 2), Vector2(80 * progress, 4)), GRASS_LIGHT)


func _draw_warning_overlay() -> void:
	var radius: float = movement_settings.warning_radius_tiles * movement_settings.tile_size
	if warning_distance > radius or warning_direction.length_squared() < 0.01:
		return
	var center := VIEW_CENTER
	var arrow_center := center + warning_direction * Vector2(430.0, 238.0)
	arrow_center.x = clampf(arrow_center.x, 42.0, VIEW_SIZE.x - 42.0)
	arrow_center.y = clampf(arrow_center.y, 104.0, VIEW_SIZE.y - 42.0)
	var closeness := 1.0 - clampf(warning_distance / radius, 0.0, 1.0)
	var color := Color("#ff4d3d").lerp(Color("#ffcc55"), 1.0 - closeness)
	draw_circle(arrow_center, 23.0, Color(color, 0.24))
	var tip := arrow_center + warning_direction * 19.0
	var side := warning_direction.orthogonal() * 9.0
	draw_colored_polygon(PackedVector2Array([tip, arrow_center - warning_direction * 10.0 + side, arrow_center - warning_direction * 10.0 - side]), color)


func _draw_soft_boundary_overlay() -> void:
	if not soft_boundary_active:
		return
	draw_rect(Rect2(Vector2.ZERO, VIEW_SIZE), Color(0.88, 0.95, 1.0, 0.12))
	for stripe in range(8):
		var inset := float(stripe) * 12.0
		draw_rect(Rect2(inset, inset, VIEW_SIZE.x - inset * 2.0, VIEW_SIZE.y - inset * 2.0), Color(0.9, 0.97, 1.0, 0.05), false, 10.0)


func _draw_weather_effects() -> void:
	if weather_tint > 0.0:
		draw_rect(Rect2(Vector2.ZERO, VIEW_SIZE), Color(1.0, 0.94, 0.72, weather_tint))
	else:
		draw_rect(Rect2(Vector2.ZERO, VIEW_SIZE), Color(0.12, 0.18, 0.3, -weather_tint))
	var kind := "clear" if current_weather < 0 else str(zones[current_weather].kind)
	if kind in ["rain", "storm", "cyclone"]:
		for drop in range(100 if kind == "storm" else 65):
			var wind := 240.0 if kind == "cyclone" else 55.0
			var x := fposmod(drop * 137.1 - weather_elapsed * wind, VIEW_SIZE.x)
			var y := fposmod(drop * 89.7 + weather_elapsed * 420.0, VIEW_SIZE.y)
			draw_line(Vector2(x, y), Vector2(x - (15 if kind == "cyclone" else 5), y + 17), Color(0.75, 0.86, 1.0, 0.45), 1.4)
	if kind == "snow":
		for flake in range(70):
			var x := fposmod(flake * 149.3 + sin(weather_elapsed + flake) * 18.0, VIEW_SIZE.x)
			var y := fposmod(flake * 73.7 + weather_elapsed * 58.0, VIEW_SIZE.y)
			draw_circle(Vector2(x, y), 2.0, Color(0.95, 0.98, 1.0, 0.75))
	if kind == "storm" and lightning_left > 0.0:
		var x := 250.0 + fposmod(lightning_next * 73.0, 650.0)
		draw_polyline(PackedVector2Array([Vector2(x, 0), Vector2(x - 38, 64), Vector2(x + 12, 63), Vector2(x - 42, 147)]), Color(0.86, 0.9, 1.0, lightning_left / 0.18), 3.0)


func _map_to_world(screen_position: Vector2) -> Vector2:
	return map_center + (screen_position - MAP_RECT.get_center()) / map_scale


func _world_to_map(world_position: Vector2) -> Vector2:
	return MAP_RECT.get_center() + (world_position - map_center) * map_scale


func _draw_sky_map() -> void:
	draw_rect(Rect2(Vector2.ZERO, VIEW_SIZE), Color(0.05, 0.10, 0.16, 0.68))
	draw_rect(MAP_RECT, Color(0.08, 0.16, 0.22, 0.94))
	draw_rect(MAP_RECT, Color("#b8e3e2"), false, 3.0)
	var font := ThemeDB.fallback_font
	draw_string(font, MAP_RECT.position + Vector2(20, 30), "天空地图 · 已暂停 · 雷达 Lv.%d · 缩放 %d%%" % [int(development.tech.radar), roundi(map_scale / 0.16 * 100)], HORIZONTAL_ALIGNMENT_LEFT, -1.0, 17, Color.WHITE)
	draw_string(font, Vector2(MAP_RECT.position.x + 20, MAP_RECT.end.y - 14), "WASD 平移 · 滚轮缩放 · 点击标记 · 悬停查看 · 右键清除 · M / Esc 返回", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 13, Color("#d7edf1"))


func _draw_destination_bearing() -> void:
	if not map_destination_set or sky_map_open: return
	var direction := island_pos.direction_to(map_destination)
	var point := VIEW_CENTER + direction * Vector2(440, 210)
	var normal := direction.orthogonal()
	draw_colored_polygon(PackedVector2Array([point + direction * 14, point - direction * 8 + normal * 8, point - direction * 8 - normal * 8]), Color("#ffe47a"))
	draw_string(ThemeDB.fallback_font, point + Vector2(-32, 30), "%.0f" % island_pos.distance_to(map_destination), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, INK)


func _draw_sky_map_content() -> void:
	var grid_step := WorldLayout.SECTOR_SIZE * map_scale
	var origin := _world_to_map(world_origin)
	var grid_radius := ceili(maxf(MAP_RECT.size.x, MAP_RECT.size.y) / (2.0 * grid_step)) + 1
	for grid_index in range(-grid_radius, grid_radius + 1):
		var grid_x := MAP_RECT.get_center().x + fmod(origin.x - MAP_RECT.get_center().x, grid_step) + grid_index * grid_step
		var grid_y := MAP_RECT.get_center().y + fmod(origin.y - MAP_RECT.get_center().y, grid_step) + grid_index * grid_step
		map_ink.draw_line(Vector2(grid_x, MAP_RECT.position.y), Vector2(grid_x, MAP_RECT.end.y), Color(0.5, 0.7, 0.75, 0.12), 1.0)
		map_ink.draw_line(Vector2(MAP_RECT.position.x, grid_y), Vector2(MAP_RECT.end.x, grid_y), Color(0.5, 0.7, 0.75, 0.12), 1.0)
	for zone_value in zones:
		var zone: Dictionary = zone_value
		var map_position := _world_to_map(zone.pos)
		map_ink.draw_circle(map_position, float(zone.radius) * map_scale, Color(zone.color, 0.30))
		map_ink.draw_arc(map_position, float(zone.radius) * map_scale, 0.0, TAU, 40, Color(zone.edge, 0.65), 1.0)
		if warning_system_unlocked:
			map_ink.draw_line(map_position, _world_to_map(zone.pos + zone.velocity * 60.0), Color(zone.edge, 0.35), 1.0)
	for target in targets:
		if bool(target.active) and not target.has("island") and _radar_visible(target.pos):
			map_ink.draw_rect(Rect2(_world_to_map(target.pos) - Vector2(2, 2), Vector2(4, 4)), Color("#e5c78b"))
	for hazard_value in hazards:
		var hazard: Dictionary = hazard_value
		if not bool(hazard.active) or not _radar_visible(hazard.pos):
			continue
		var map_position := _world_to_map(hazard.pos)
		var center: Vector2 = IslandTiles.bounds(hazard.tiles).get_center() * map_scale
		var color: Color = Color("#c98be8") if bool(hazard.get("shop", false)) else [Color("#72a776"), Color("#a0b1b5"), Color("#d8bd7d"), Color("#a6c583"), Color("#cf6849"), Color("#e6c558")][int(hazard.biome)]
		for tile in hazard.tiles:
			var rect := IslandTiles.cell_rect(map_position - center, tile.cell, IslandTiles.CELL_SIZE * map_scale)
			map_ink.draw_rect(rect.grow(-0.4), color)
		if int(hazard.get("size_class", 0)) > 0:
			var radius := 10.0 + 4.0 * int(hazard.get("size_class", 0))
			map_ink.draw_circle(map_position, radius, Color.WHITE, false, 1.5)
	_draw_radar_fog()
	var island_map_position := _world_to_map(island_pos)
	for tile in island_tiles:
		var rect := IslandTiles.cell_rect(island_map_position, tile.cell, IslandTiles.CELL_SIZE * map_scale)
		map_ink.draw_rect(rect.grow(-0.4), Color("#acd98a"))
	map_ink.draw_circle(island_map_position, 7.0, Color("#335f68"))
	map_ink.draw_circle(island_map_position, 7.0, Color.WHITE, false, 2.0)
	if map_destination_set:
		var destination_screen := _world_to_map(map_destination)
		_draw_dashed_line(island_map_position, destination_screen, Color("#ffe47a"), 10.0, 5.0, 2.0, map_ink)
		map_ink.draw_circle(destination_screen, 9.0, Color("#ffcf55"), false, 3.0)
		map_ink.draw_line(destination_screen + Vector2(0, -18), destination_screen + Vector2(0, 10), Color("#ffcf55"), 3.0)


func _draw_dashed_line(from: Vector2, to: Vector2, color: Color, dash: float, gap: float, width: float, canvas: Node2D) -> void:
	var distance := from.distance_to(to)
	if distance < 0.01:
		return
	var direction := from.direction_to(to)
	var cursor := 0.0
	while cursor < distance:
		var segment_end := minf(distance, cursor + dash)
		canvas.draw_line(from + direction * cursor, from + direction * segment_end, color, width)
		cursor += dash + gap


func _ellipse_points(center: Vector2, radius: Vector2, steps: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	for index in range(steps):
		var angle := TAU * float(index) / float(steps)
		points.append(center + Vector2(cos(angle) * radius.x, sin(angle) * radius.y))
	return points


func _world_visible(world_position: Vector2, margin: float) -> bool:
	return Rect2(-Vector2.ONE * margin * camera_zoom, VIEW_SIZE + Vector2.ONE * margin * camera_zoom * 2.0).has_point(_world_to_screen(world_position))


func _radar_visible(world_position: Vector2) -> bool:
	return world_position.distance_to(island_pos) <= development.radar_range()


func _draw_radar_fog() -> void:
	var center := _world_to_map(island_pos)
	var radius: float = development.radar_range() * map_scale
	for segment in range(96):
		var a := Vector2.from_angle(TAU * segment / 96.0)
		var b := Vector2.from_angle(TAU * (segment + 1) / 96.0)
		map_ink.draw_colored_polygon(PackedVector2Array([center + a * radius, center + a * 3000.0, center + b * 3000.0, center + b * radius]), Color("#162733"))
	map_ink.draw_arc(center, radius, 0, TAU, 96, Color("#9ac9c2"), 1.5)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and saves != null:
		saves.request_exit()

func _draw_night_lights() -> void:
	var night := _night_strength()
	if night <= 0.0: return
	# World-only veil: HUD lives in its own CanvasLayer and stays fully readable.
	draw_rect(Rect2(Vector2.ZERO, VIEW_SIZE), Color(0.07, 0.12, 0.25, 0.32 * night))
	for tile in island_tiles:
		var point := _world_to_screen(island_pos + Vector2(tile.cell) * IslandTiles.CELL_SIZE)
		if tile.kind == "lava":
			for ring in range(4, 0, -1):
				draw_circle(point, ring * 12.0 * camera_zoom, Color(1.0, 0.46, 0.13, night * 0.06))
			draw_circle(point, 4 * camera_zoom, Color(1.0, 0.79, 0.26, night))
		if posmod(tile.cell.x * 3 + tile.cell.y * 7, 4) == 0:
			var phase: float = animation_time * 0.8 + tile.cell.x * 2.7 + tile.cell.y
			point += Vector2(sin(phase) * 16, -12 + cos(phase * 1.3) * 8) * camera_zoom
			var glow := night * (0.6 + sin(phase * 2.0) * 0.25)
			for ring in range(3, 0, -1):
				draw_circle(point, ring * 6.0 * camera_zoom, Color(0.65, 1.0, 0.58, glow * 0.12))
			draw_circle(point, maxf(1.2, 2.5 * camera_zoom), Color(0.88, 1.0, 0.63, glow))
