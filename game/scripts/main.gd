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
const MAP_SCALE := 0.16
const WorldLayout = preload("res://scripts/world_layout.gd")
const IslandTiles = preload("res://scripts/island_tiles.gd")
const PixelTerrain = preload("res://scripts/pixel_terrain.gd")
const Development = preload("res://scripts/island_development.gd")
const WeatherSystem = preload("res://scripts/weather_system.gd")
var development
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
var seeds := 5
var rice_stock := 0
var energy_crop_stock := 0
var harvested := 0
var gathered := 0
var day_minutes := 8.0 * 60.0
var demo_started := false
var selected_tool := TOOL_HOOK
var current_weather := -1
var collision_cooldown := 0.0
var goal_announced := false
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

var sky_map_open := false
var map_destination := Vector2.ZERO
var map_destination_set := false
var autopilot_active := false
var autopilot_state := "待机"
var autopilot_reason := ""
var autopilot_unlocked := true
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
var rice_atlas: Texture2D
var tomato_atlas: Texture2D
var terrain_textures: Dictionary = {}
var tree_texture: Texture2D
var steward_texture: Texture2D
var power_hut_texture: Texture2D
var grapple_hut_texture: Texture2D
var water_grain_hut_texture: Texture2D
var money_label: Label
var energy_label: Label
var fuel_label: Label
var seed_label: Label
var time_label: Label
var weather_label: Label
var context_label: Label
var context_title_label: Label
var notice_label: Label
var navigation_label: Label
var navigation_panel: PanelContainer
var context_panel: PanelContainer
var map_clip: Control
var map_ink: Node2D
var view_button: Button
var map_button: Button
var fuel_button: Button
var hook_button: Button
var seed_button: Button
var tomato_button: Button
var intro_panel: PanelContainer
var guide_panel: PanelContainer
var guide_body: Label
var guide_expanded := false
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
	_load_pixel_v2_assets()
	_initialize_world()
	development = Development.new(self)
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
	var scale_reference: Texture2D = load("res://assets/pixel_v2/characters/world_scale_reference_v1.png")
	tree_texture = PixelTerrain.approved_tree()
	steward_texture = _atlas_region(scale_reference, Rect2(1046, 414, 232, 297))
	rice_atlas = load("res://assets/pixel_v2/crops/rice_growth_5stage_v2.png")
	tomato_atlas = load("res://assets/pixel_v2/crops/tomato_growth_5stage_v2.png")
	power_hut_texture = _atlas_region(load("res://assets/pixel_v2/facilities/engine_room_v2.png"), Rect2(295, 91, 958, 845))
	water_grain_hut_texture = _atlas_region(load("res://assets/pixel_v2/facilities/energy_storage_room_v2.png"), Rect2(320, 59, 912, 902))
	grapple_hut_texture = _atlas_region(load("res://assets/pixel_v2/facilities/grapple_workshop_v2.png"), Rect2(299, 142, 1099, 775))


func _initialize_world() -> void:
	island_tiles = IslandTiles.initial_tiles()
	_refresh_island_shape()
	for index in range(9):
		plots.append({"cell": Vector2i(index % 3 - 1, int(index / 3) - 1), "state": 0, "progress": 0.0, "crop_type": CROP_RICE if index % 2 == 0 else CROP_TOMATO})

	_update_world_stream()


func _update_world_stream() -> void:
	var sector := WorldLayout.sector_at(island_pos, world_origin)
	if sector == active_sector:
		return
	var attached: Dictionary = targets[hooked_target] if hooked_target >= 0 else {}
	active_sector = sector
	targets = []
	hazards = []
	for y in range(sector.y - WorldLayout.ACTIVE_RADIUS, sector.y + WorldLayout.ACTIVE_RADIUS + 1):
		for x in range(sector.x - WorldLayout.ACTIVE_RADIUS, sector.x + WorldLayout.ACTIVE_RADIUS + 1):
			var key := Vector2i(x, y)
			if not world_sectors.has(key):
				world_sectors[key] = WorldLayout.make_sector(key, world_origin)
			var content: Dictionary = world_sectors[key]
			if not content.has("island_targets"):
				content.island_targets = []
			for terrain in content.hazards:
				if not terrain.has("tiles"):
					terrain.tiles = IslandTiles.wild_tiles(int(terrain.biome), int(terrain.variant), int(terrain.get("size_class", 0)))
					var bounds: Rect2 = IslandTiles.bounds(terrain.tiles)
					terrain.radius = bounds.size.length() * 0.5
					terrain.active = true
					terrain.tethered = false
					content.island_targets.append({"pos": terrain.pos, "type": terrain.name, "value": 0,
						"weight": IslandTiles.mass(terrain.tiles), "active": true,
						"respawn": 0.0, "island": terrain})
			hazards.append_array(content.hazards)
			targets.append_array(content.island_targets)
	if not attached.is_empty():
		hooked_target = targets.find(attached)
		if hooked_target < 0:
			targets.append(attached)
			hooked_target = targets.size() - 1
	else:
		hooked_target = -1


func _refresh_island_shape() -> void:
	island_bounds = IslandTiles.bounds(island_tiles)
	island_mass = IslandTiles.mass(island_tiles)
	island_mass_changed.emit(island_mass)


func _clamp_focus_offset() -> void:
	var bounds := island_bounds.grow(float(movement_settings.tile_size) * 0.5)
	focus_offset = focus_offset.clamp(bounds.position, bounds.end)


func _physics_process(delta: float) -> void:
	if not demo_started:
		return
	if development.modal != null and development.modal.visible:
		_update_hud()
		return

	day_minutes = fmod(day_minutes + delta * 5.0, 1440.0)
	energy_warning_left = maxf(0.0, energy_warning_left - delta)
	development.update(delta)
	collision_cooldown = maxf(0.0, collision_cooldown - delta)
	worker_slow_time = maxf(0.0, worker_slow_time - delta)
	control_stun_time = maxf(0.0, control_stun_time - delta)
	screen_shake_time = maxf(0.0, screen_shake_time - delta)
	warning_ping_cooldown = maxf(0.0, warning_ping_cooldown - delta)

	var manual_direction := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if sky_map_open:
		manual_direction = Vector2.ZERO
	if control_stun_time > 0.0:
		manual_direction = Vector2.ZERO
	if manual_direction.length_squared() > 0.01:
		if autopilot_active:
			_cancel_autopilot("玩家接管")
		if view_mode == VIEW_FOCUS:
			_set_view_mode(VIEW_GOD, "开始驾驶，已切换上帝视角")

	_update_world_stream()
	_update_warning()
	var drive_direction := manual_direction
	if autopilot_active:
		drive_direction = _autopilot_direction()
	_apply_movement(delta, drive_direction, drive_direction.length_squared() > 0.01)
	_update_camera(delta)
	_update_focus_pan(delta)

	_update_zones(delta)
	_update_weather_hazards(delta)
	_update_merchant(delta)
	_update_crops(delta)
	_update_hook(delta)
	_update_targets(delta)
	_check_collisions()
	_check_goal()
	_update_hud()
	queue_redraw()


func _process(delta: float) -> void:
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
	if not sky_map_open and (development == null or development.modal == null or not development.modal.visible):
		var mouse := get_viewport().get_mouse_position()
		for index in range(plots.size()):
			if _plot_rect(index).has_point(mouse):
				next_hover = index
				break
	if hovered_plot != next_hover:
		hovered_plot = next_hover
		queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if not demo_started:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_B or event.keycode == KEY_T:
			development.toggle(event.keycode == KEY_T)
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_H or event.keycode == KEY_J:
			development.batch(event.keycode == KEY_H)
			get_viewport().set_input_as_handled()
			return
	if development.modal.visible:
		if event.is_action_pressed("ui_cancel"): development.modal.hide()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("toggle_view"):
		_toggle_view()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("toggle_map"):
		sky_map_open = not sky_map_open
		_show_notice("天空地图：点击设置目的地，回车确认启航。" if sky_map_open else "已关闭天空地图。")
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("refuel"):
		_refuel_from_crops()
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
			if selected_tool == 2:
				development.move_from = development.NONE
				development.trim_pending = development.NONE
				_select_tool(TOOL_HOOK)
			else:
				_cancel_hook()
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
	if autopilot_active:
		speed_limit *= movement_settings.autopilot_cruise_ratio

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
	if autopilot_active:
		energy_rate += movement_settings.autopilot_energy_per_second
	if energy_rate > 0.0:
		var requested := energy_rate * _mass_energy_ratio() * delta
		var consumed := minf(energy, requested)
		if consumed > 0.0:
			_consume_energy(consumed, "自动驾驶" if autopilot_active else "浮岛推进")

	island_pos += island_velocity * delta
	if energy <= 0.0 and autopilot_active:
		_cancel_autopilot("能源耗尽")
	elif energy < movement_settings.autopilot_min_energy and autopilot_active:
		_cancel_autopilot("能源低于 20 E")


func _autopilot_direction() -> Vector2:
	if not map_destination_set:
		_cancel_autopilot("目的地丢失")
		return Vector2.ZERO
	var to_target := map_destination - island_pos
	var distance := to_target.length()
	if distance <= movement_settings.autopilot_arrival_radius and island_velocity.length() < 2.0:
		island_velocity = Vector2.ZERO
		_cancel_autopilot("已到达目的地")
		return Vector2.ZERO
	var desired := to_target.normalized()
	var warning_radius: float = movement_settings.warning_radius_tiles * movement_settings.tile_size
	for hazard_value in hazards:
		var hazard: Dictionary = hazard_value
		if not bool(hazard.active) or bool(hazard.tethered):
			continue
		var to_hazard: Vector2 = hazard.pos - island_pos
		var clearance := _hazard_clearance(hazard)
		if clearance <= warning_radius and desired.dot(to_hazard.normalized()) > 0.2:
			if clearance < 28.0:
				_set_autopilot_state("等待", "前方障碍过近")
				return Vector2.ZERO
			var away: Vector2 = hazard.pos.direction_to(island_pos)
			var tangent := desired.orthogonal()
			if tangent.dot(away) < 0.0:
				tangent = -tangent
			_set_autopilot_state("避障", "绕行荒岛")
			return (desired + tangent * 1.35).normalized()

	var brake_acceleration: float = _engine_thrust() / _effective_mass() * movement_settings.passive_brake_ratio
	var braking_distance := island_velocity.length_squared() / maxf(1.0, 2.0 * brake_acceleration) + 18.0
	if distance <= braking_distance:
		_set_autopilot_state("减速", "接近目的地")
		return Vector2.ZERO
	_set_autopilot_state("巡航", "前往目的地")
	return desired


func _set_autopilot_state(state_value: String, reason: String) -> void:
	if autopilot_state == state_value and autopilot_reason == reason:
		return
	autopilot_state = state_value
	autopilot_reason = reason
	autopilot_state_changed.emit(state_value, reason)


func _start_autopilot() -> void:
	if development.engine_power() <= 0.0:
		_show_notice("没有引擎；先在科技树研究动力工程并建造引擎室。")
		return
	if not autopilot_unlocked:
		_show_notice("需要天空地图、自动驾驶小屋和预警系统。")
		return
	if not map_destination_set:
		_show_notice("请先在天空地图上点击目的地。")
		return
	if energy < movement_settings.autopilot_min_energy:
		_warn_energy("自动驾驶至少需要 20 E")
		return
	autopilot_active = true
	sky_map_open = false
	_set_autopilot_state("巡航", "自动驾驶已启动")
	_show_notice("自动驾驶已启动；WASD 或 Esc 可立即接管。")
	_play_tone(660.0, 0.10, -10.0)


func _cancel_autopilot(reason: String) -> void:
	if not autopilot_active and autopilot_reason == reason:
		return
	autopilot_active = false
	_set_autopilot_state("待机", reason)
	if "能源" in reason:
		_warn_energy(reason)
	else:
		_show_notice("自动驾驶中断：%s" % reason)

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
		if not bool(hazard.active) or bool(hazard.tethered) or not _has_collision_trend(hazard):
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
	if energy >= energy_capacity - 0.01:
		return
	if development == null or not development.has_facility("energy"):
		if not quiet:
			_warn_energy("需要研究能源自动化并建造能源工厂")
		return
	if int(development.tech.geothermal) > 0 and int(development.materials.magma) > 0:
		development.materials.magma -= 1
		_add_energy(60.0, "消耗岩浆晶")
	elif int(development.tech.bioenergy) > 0 and energy_crop_stock > 0:
		energy_crop_stock -= 1
		_add_energy(development.crop_energy(CROP_TOMATO), "能源工厂处理能源作物")
	elif int(development.tech.bioenergy) > 0 and rice_stock > 0:
		rice_stock -= 1
		_add_energy(development.crop_energy(CROP_RICE), "能源工厂处理粮食")
	elif int(development.tech.mineral_energy) > 0 and int(development.materials.ore) > 0:
		development.materials.ore -= 1
		_add_energy(development.ore_energy(), "能源工厂处理矿物")
	elif not quiet:
		_warn_energy("缺少已解锁的燃料；检查作物能源或矿物能源科技")


func _warn_energy(reason: String) -> void:
	energy_warning_text = reason
	energy_warning_left = 3.0
	if energy_label != null:
		energy_label.tooltip_text = reason


func _toggle_view() -> void:
	if view_mode == VIEW_GOD:
		if not autopilot_active and island_velocity.length() > 1.0:
			_show_notice("手动驾驶需保持上帝视角。")
			return
		_set_view_mode(VIEW_FOCUS, "已进入聚焦视角；中键拖拽或靠近屏幕边缘平移。")
	else:
		_set_view_mode(VIEW_GOD, "已进入上帝视角。")


func _set_view_mode(mode: int, notice: String = "") -> void:
	if view_mode == mode:
		return
	view_mode = mode
	view_transition_left = movement_settings.view_transition_time
	if mode == VIEW_GOD:
		camera_zoom_target = movement_settings.god_zoom_default
	else:
		focus_offset = Vector2.ZERO
		camera_zoom_target = movement_settings.focus_zoom_default
	view_mode_changed.emit(mode)
	if not notice.is_empty():
		_show_notice(notice)
	_play_tone(440.0 if mode == VIEW_GOD else 520.0, 0.08, -17.0)


func _adjust_zoom(amount: float) -> void:
	if view_mode == VIEW_GOD:
		camera_zoom_target = clampf(camera_zoom_target + amount, movement_settings.god_zoom_min, movement_settings.god_zoom_max)
	else:
		camera_zoom_target = clampf(camera_zoom_target + amount, movement_settings.focus_zoom_min, movement_settings.focus_zoom_max)
	view_transition_left = movement_settings.view_transition_time


func _update_camera(delta: float) -> void:
	view_transition_left = maxf(0.0, view_transition_left - delta)
	var zoom_speed := maxf(0.01, absf(camera_zoom_target - camera_zoom) / maxf(0.05, movement_settings.view_transition_time))
	camera_zoom = move_toward(camera_zoom, camera_zoom_target, zoom_speed * delta)
	if view_mode == VIEW_FOCUS:
		camera_world = island_pos + focus_offset
	else:
		var target: Vector2 = island_pos + island_velocity * movement_settings.camera_look_ahead_seconds
		camera_world = camera_world.lerp(target, 1.0 - exp(-delta / movement_settings.camera_smooth_time))


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
	if not MAP_RECT.has_point(screen_position):
		return
	map_destination = island_pos + (screen_position - MAP_RECT.get_center()) / MAP_SCALE
	map_destination_set = true
	_show_notice("目的地已标记；按回车启航。")


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
		return
	weather_hazard_left -= delta
	if weather_hazard_left > 0.0 or plots.is_empty():
		return
	weather_hazard_left = 8.0 if kind == "snow" else 6.0
	var index := weather_rng.randi_range(0, plots.size() - 1)
	var plot: Dictionary = plots[index]
	plot.weather_penalty = 0.55 if kind == "snow" else 0.35
	plots[index] = plot
	if kind == "cyclone":
		var mitigation := 1.0 - 0.18 * int(development.tech.forecast)
		development.damage_cell(plot.cell, 28.0 * mitigation, "飓风破坏")
		_show_notice("飓风毁坏了一块农田与其作物；离开风区后仍需修缮。", 4.0)
	else:
		_show_notice("积雪覆盖了一块农田；离开雪区后减速效果解除。", 3.0)

func _update_merchant(delta: float) -> void:
	if merchant_available:
		merchant_stay_left -= delta
		if merchant_stay_left <= 0.0:
			merchant_available = false
			merchant_arrival_left = 210.0
			_show_notice("流浪商人离开了。")
		return
	merchant_arrival_left -= delta
	if merchant_arrival_left <= 0.0:
		merchant_available = true
		merchant_stay_left = 75.0
		_show_notice("流浪商人降落！打开 B 开发面板即可交易。", 6.0)


func _update_crops(delta: float) -> void:
	var multiplier := _growth_multiplier()
	for index in range(plots.size()):
		var plot: Dictionary = plots[index]
		if int(plot.state) == 1:
			var tile: Dictionary = development.tile_at(plot.cell)
			var health := maxf(0.25, float(tile.get("hp", 100.0)) / 100.0)
			var weather_penalty := float(plot.get("weather_penalty", 1.0))
			plot.progress = minf(1.0, float(plot.progress) + delta * multiplier * weather_penalty * health / Development.Rules.CROP_GROW_SECONDS)
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
	if collision_cooldown > 0.0 or island_velocity.length() < 35.0:
		return
	for index in range(hazards.size()):
		var hazard: Dictionary = hazards[index]
		if not bool(hazard.active) or bool(hazard.tethered):
			continue
		var hazard_pos: Vector2 = hazard.pos
		if _hazard_clearance(hazard) < 0.0:
			collision_cooldown = 2.0
			var hazard_mass := IslandTiles.mass(hazard.tiles)
			var collision_cost := minf(energy, 8.0 + island_velocity.length() * 0.25 + hazard_mass * 0.5)
			_consume_energy(collision_cost, "碰撞")
			var removed: int = development.collision_at(hazard_pos, island_velocity.length(), hazard_mass)
			var push: Vector2 = hazard_pos.direction_to(island_pos)
			if push.length_squared() < 0.01:
				push = Vector2.RIGHT
			island_pos += push * 45.0
			island_velocity *= -0.35
			hazard.pos -= push * 65.0
			hazards[index] = hazard
			if autopilot_active:
				_cancel_autopilot("发生碰撞")
			_show_notice("撞击崩落 %d 格；质量与速度越大，波及范围越大。" % removed, 5.0)
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
			_show_notice("%s已接入！+%d 地块 · 当前 %d 格 · 质量 %.1f" % [str(target.type), target.island.tiles.size(), island_tiles.size(), island_mass], 5.0)
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

func _target_lock_reason(target: Dictionary) -> String:
	if not target.has("island"):
		return ""
	var terrain: Dictionary = target.island
	var size_class := int(terrain.get("size_class", 0))
	var required := 2 if size_class >= 2 else (1 if size_class == 1 or bool(terrain.get("shop", false)) else 0)
	if int(development.tech.docking) < required:
		return "需要岛屿对接 %s" % ("II" if required == 2 else "I")
	return ""


func _begin_island_attachment(target: Dictionary) -> void:
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
			var plot: Dictionary = plots[index]
			var crop_type: int = development.selected_crop if int(plot.state) == 0 else int(plot.crop_type)
			var crop_name := _crop_name(crop_type)
			if int(plot.state) == 0:
				var farm_tile: Dictionary = development.tile_at(plot.cell)
				if float(farm_tile.get("hp", 100.0)) < 100.0:
					_show_notice("农田受损，必须先通过 B → 修缮恢复后才能播种。")
					return
				if seeds <= 0:
					_show_notice("种子不足：B → 采集草地或林木，可以获得种子。")
					return
				seeds -= 1
				plot.crop_type = crop_type
				plot.state = 1
				plot.progress = 0.0
				plot.weather_penalty = 1.0
				_show_notice("播种%s成功，雨水区会让作物生长得更快。" % crop_name)
			elif int(plot.state) == 1:
				_show_notice("%s生长进度 %d%%" % [crop_name, int(float(plot.progress) * 100.0)])
			else:
				var yield_count: int = development.crop_yield()
				var coin_income: int = Development.Rules.HARVEST_COINS * yield_count
				coins += coin_income
				seeds += 1
				harvested += 1
				if int(plot.crop_type) == CROP_RICE:
					rice_stock += yield_count
				else:
					energy_crop_stock += yield_count
				plot.state = 0
				plot.progress = 0.0
				plot.weather_penalty = 1.0
				_show_notice("收获%s ×%d：+%d 金币，返还 1 种子" % [crop_name, yield_count, coin_income])
			plots[index] = plot
			queue_redraw()
			return
	_show_notice("请点击农田格；B → 开垦可以增加农田。")


func _check_goal() -> void:
	if not goal_announced and coins >= 200 and harvested >= 2 and gathered >= 3:
		goal_announced = true
		_show_notice("Demo 目标完成！你的浮岛经济开始正循环了。", 6.0)


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


func _build_hud() -> void:
	var canvas := CanvasLayer.new()
	canvas.name = "HUD"
	add_child(canvas)

	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(root)

	var stats_panel := _make_panel(Vector2(18, 16), Vector2(542, 68), PANEL)
	root.add_child(stats_panel)
	var stats_row := HBoxContainer.new()
	stats_row.add_theme_constant_override("separation", 12)
	stats_panel.add_child(_with_margin(stats_row, 10))
	money_label = _add_stat(stats_row, 0, "金币")
	energy_label = _add_stat(stats_row, 1, "能源")
	seed_label = _add_stat(stats_row, 3, "种子")
	fuel_label = _add_stat(stats_row, 4, "产能作物")

	var clock_panel := _make_panel(Vector2(578, 16), Vector2(166, 68), PANEL)
	root.add_child(clock_panel)
	var clock_box := VBoxContainer.new()
	clock_box.alignment = BoxContainer.ALIGNMENT_CENTER
	clock_panel.add_child(_with_margin(clock_box, 8))
	time_label = Label.new()
	time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	time_label.add_theme_font_size_override("font_size", 20)
	time_label.add_theme_color_override("font_color", INK)
	clock_box.add_child(time_label)
	weather_label = Label.new()
	weather_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	weather_label.add_theme_font_size_override("font_size", 13)
	weather_label.add_theme_color_override("font_color", Color("#76503b"))
	clock_box.add_child(weather_label)

	navigation_panel = _make_panel(Vector2(18, 120), Vector2(336, 116), Color("#e8f1de"))
	root.add_child(navigation_panel)
	var navigation_box := VBoxContainer.new()
	navigation_box.add_theme_constant_override("separation", 7)
	navigation_panel.add_child(_with_margin(navigation_box, 10))
	navigation_label = Label.new()
	navigation_label.add_theme_font_size_override("font_size", 13)
	navigation_label.add_theme_color_override("font_color", INK)
	navigation_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	navigation_box.add_child(navigation_label)
	var navigation_buttons := HBoxContainer.new()
	navigation_buttons.add_theme_constant_override("separation", 6)
	navigation_box.add_child(navigation_buttons)
	view_button = _make_small_button("Tab 聚焦")
	view_button.pressed.connect(_toggle_view)
	navigation_buttons.add_child(view_button)
	map_button = _make_small_button("M 天空地图")
	map_button.pressed.connect(func() -> void:
		sky_map_open = not sky_map_open
		_show_notice("天空地图：点击目的地，回车启航。" if sky_map_open else "已关闭天空地图。")
	)
	navigation_buttons.add_child(map_button)
	fuel_button = _make_small_button("R 能源工厂")
	fuel_button.pressed.connect(_refuel_from_crops)
	navigation_buttons.add_child(fuel_button)

	guide_panel = _make_panel(Vector2(18, 244), Vector2(300, 42), Color("#eef2dc"))
	root.add_child(guide_panel)
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
	var guide_toggle := _make_small_button("展开")
	guide_toggle.custom_minimum_size = Vector2(62, 26)
	guide_toggle.pressed.connect(func() -> void:
		guide_expanded = not guide_expanded
		guide_body.visible = guide_expanded
		guide_panel.size.y = 108.0 if guide_expanded else 42.0
		guide_toggle.text = "隐藏" if guide_expanded else "展开"
	)
	guide_header.add_child(guide_toggle)
	guide_body = Label.new()
	guide_body.text = "WASD 驾驶　Space 急停　M 地图\nTab 视角　R 能源厂　B 开发 / T 科技\n1/Q 抓钩　2/F 种植"
	guide_body.add_theme_font_size_override("font_size", 12)
	guide_body.add_theme_color_override("font_color", Color("#624635"))
	guide_body.visible = false
	guide_box.add_child(guide_body)

	context_panel = _make_panel(Vector2(904, 120), Vector2(230, 196), Color("#f8eacb"))
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

	var toolbar := _make_panel(Vector2(380, 570), Vector2(392, 62), Color("#f9e8c3"))
	root.add_child(toolbar)
	var tools_row := HBoxContainer.new()
	tools_row.alignment = BoxContainer.ALIGNMENT_CENTER
	tools_row.add_theme_constant_override("separation", 7)
	toolbar.add_child(_with_margin(tools_row, 6))
	hook_button = _make_tool_button("1 / Q  抓钩", 2)
	hook_button.pressed.connect(func() -> void: _select_tool(TOOL_HOOK))
	hook_button.custom_minimum_size = Vector2(118, 46)
	tools_row.add_child(hook_button)
	seed_button = _make_tool_button("水稻", 3)
	seed_button.pressed.connect(_select_crop_tool.bind(CROP_RICE))
	seed_button.custom_minimum_size = Vector2(108, 46)
	tools_row.add_child(seed_button)
	tomato_button = _make_tool_button("番茄", 3)
	tomato_button.pressed.connect(_select_crop_tool.bind(CROP_TOMATO))
	tomato_button.custom_minimum_size = Vector2(108, 46)
	tools_row.add_child(tomato_button)

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
	_build_intro(root)
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

	var footer := Label.new()
	footer.text = "初步目标：200 金币 · 收获 2 次 · 采集 3 格资源"
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
		_show_notice("天空地图：群岛、物资和天气分布；点击目的地后按 Enter 启航。" if show_map else "主岛由独立地块拼成。用抓钩拖回右上方的小岛，即可扩张。", 8.0)
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
		for key in ["engine", "storage", "bioenergy", "hook", "development", "agriculture"]:
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


func _add_stat(parent: HBoxContainer, icon_index: int, caption: String) -> Label:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(119, 46)
	row.add_theme_constant_override("separation", 6)
	parent.add_child(row)
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(38, 38)
	icon.texture = _icon(icon_index)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	row.add_child(icon)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(box)
	var small := Label.new()
	small.text = caption
	small.add_theme_font_size_override("font_size", 11)
	small.add_theme_color_override("font_color", Color("#876044"))
	box.add_child(small)
	var value := Label.new()
	value.add_theme_font_size_override("font_size", 18)
	value.add_theme_color_override("font_color", INK)
	box.add_child(value)
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
	hook_button.add_theme_stylebox_override("hover", _button_style(Color("#ffe39a"), Color("#7c512f")))
	seed_button.add_theme_stylebox_override("hover", _button_style(Color("#ffe39a"), Color("#7c512f")))
	tomato_button.add_theme_stylebox_override("hover", _button_style(Color("#ffe39a"), Color("#7c512f")))


func _update_hud() -> void:
	if money_label == null:
		return
	money_label.text = str(coins)
	energy_label.text = "%d/%d E%s" % [int(energy), int(energy_capacity), " !" if energy < energy_capacity * 0.2 or energy_warning_left > 0.0 else ""]
	energy_label.tooltip_text = energy_warning_text if energy_warning_left > 0.0 else "R 手动补能；T 研究自动填充与高效利用"
	if energy / energy_capacity < 0.2 or energy_warning_left > 0.0:
		energy_label.add_theme_color_override("font_color", Color("#b87626"))
	else:
		energy_label.add_theme_color_override("font_color", INK)
	seed_label.text = str(seeds)
	fuel_label.text = "稻%d 能%d" % [rice_stock, energy_crop_stock]
	var hour := int(day_minutes / 60.0)
	var minute := int(day_minutes) % 60
	time_label.text = "第 1 天　%02d:%02d" % [hour, minute]
	if current_weather < 0:
		weather_label.text = "普通气候 · 生长 ×1.0"
	else:
		var zone: Dictionary = zones[current_weather]
		weather_label.text = "%s ×%.2f · %ds" % [str(zone.name), _growth_multiplier(), int(zone.remaining)]
	var view_name := "上帝" if view_mode == VIEW_GOD else "聚焦"
	var navigation_state := autopilot_state if autopilot_active else "手动"
	var boundary_text := " · 云海边缘减速 50%" if soft_boundary_active else ""
	navigation_label.text = "%d 地块　质量 %.1f　速度 %.2f 格/s\n%s视角 · %s%s　坐标 %d,%d" % [island_tiles.size(), island_mass, island_velocity.length() / movement_settings.tile_size, view_name, navigation_state, boundary_text, int((island_pos.x - world_origin.x) / movement_settings.tile_size), int((island_pos.y - world_origin.y) / movement_settings.tile_size)]
	view_button.text = "Tab %s" % ("上帝" if view_mode == VIEW_FOCUS else "聚焦")
	map_button.text = "M %s地图" % ("关闭" if sky_map_open else "天空")
	var rice_ready := 0
	var tomato_ready := 0
	for plot_value in plots:
		if int(plot_value.state) == 2:
			if int(plot_value.crop_type) == CROP_RICE: rice_ready += 1
			else: tomato_ready += 1
	seed_button.text = "水稻%s" % (" [%d]" % rice_ready if rice_ready > 0 else "")
	tomato_button.text = "番茄%s" % (" [%d]" % tomato_ready if tomato_ready > 0 else "")
	seed_button.tooltip_text = "选择水稻"
	tomato_button.tooltip_text = "选择番茄"
	hook_button.disabled = not development.has_facility("grapple")
	hook_button.tooltip_text = "研究抓钩工程并建造抓钩小屋" if hook_button.disabled else "发射抓钩"
	var has_fuel := (int(development.tech.bioenergy) > 0 and rice_stock + energy_crop_stock > 0) or (int(development.tech.mineral_energy) > 0 and int(development.materials.ore) > 0) or (int(development.tech.geothermal) > 0 and int(development.materials.magma) > 0)
	fuel_button.disabled = not development.has_facility("energy") or not has_fuel or energy >= energy_capacity - 0.01
	navigation_panel.visible = not sky_map_open
	context_panel.visible = not sky_map_open
	map_clip.visible = sky_map_open
	if sky_map_open:
		map_ink.queue_redraw()
	development.update()


func _update_context_card() -> void:
	var mouse := get_viewport().get_mouse_position()
	var own_cell: Vector2i = development.cell_at(_screen_to_world(mouse))
	if not development.tile_at(own_cell).is_empty():
		context_title_label.text = "地块档案 · %d,%d" % [own_cell.x, own_cell.y]
		context_label.text = development.tile_description(own_cell)
		return
	for target in targets:
		if bool(target.active) and mouse.distance_to(_world_to_screen(target.pos)) < 42.0 * camera_zoom:
			if target.has("island"):
				var lock_reason := _target_lock_reason(target)
				context_title_label.text = "商店岛" if bool(target.island.get("shop", false)) else "待接入岛屿"
				context_label.text = "%s · %s\n%d 格 / 质量 %.1f\n%s%s" % [str(target.type), str(target.island.get("rarity", "普通")), target.island.tiles.size(), float(target.weight), str(target.island.get("report", "尚未勘探")), "\n锁定：" + lock_reason if not lock_reason.is_empty() else ""]
				return
			context_title_label.text = "漂浮物资"
			context_label.text = "%s\n\n回收价值：%d 金币\n抓钩负重：×%.2f" % [str(target.type), int(target.value), float(target.weight)]
			return
	for hazard in hazards:
		if bool(hazard.active) and mouse.distance_to(_world_to_screen(hazard.pos)) < float(hazard.radius) * camera_zoom:
			context_title_label.text = "野外岛屿"
			context_label.text = "%s · %s · %d 格\n%s" % [str(hazard.name), str(hazard.get("rarity", "普通")), hazard.tiles.size(), str(hazard.get("report", "可勘探；接入后采集"))]
			return
	for zone in zones:
		if mouse.distance_to(_world_to_screen(zone.pos)) < float(zone.radius) * camera_zoom:
			context_title_label.text = "天气区域"
			context_label.text = "%s\n\n作物生长倍率：×%.2f\n驾驶浮岛进入区域即可生效。" % [str(zone.name), float(zone.growth)]
			return
	if selected_plot >= 0 and selected_tool == TOOL_SEED:
		_set_plot_context(selected_plot)
		return
	context_title_label.text = "岛屿观察"
	context_label.text = "%d 格 · 质量 %.1f\n%s\nB 开发 · T 科技" % [island_tiles.size(), island_mass, "尚无引擎，先在岛上发展" if development.engine_power() <= 0.0 else "引擎在线，可以启航"]


func _fit_context_panel() -> void:
	if context_panel == null or context_label == null:
		return
	var line_count: int = maxi(1, context_label.text.count("\n") + 1)
	context_panel.size.y = clampf(64.0 + line_count * 18.0, 118.0, 188.0)


func _set_plot_context(index: int) -> void:
	var plot: Dictionary = plots[index]
	var crop_name := _crop_name(int(plot.crop_type))
	var yield_count: int = development.crop_yield()
	var income: int = Development.Rules.HARVEST_COINS * yield_count
	context_title_label.text = "农田地块 · %d,%d" % [int(plot.cell.x), int(plot.cell.y)]
	if int(plot.state) == 0:
		context_label.text = "%s田 · 空闲\n播种 −1 种子\n预计产量 ×%d · %d 金" % [crop_name, yield_count, income]
	elif int(plot.state) == 1:
		context_label.text = "%s · 生长 %d%%\n约 %d 秒成熟\n综合效率 ×%.2f" % [crop_name, int(float(plot.progress) * 100.0), _crop_seconds_left(plot), _growth_multiplier() * float(plot.get("weather_penalty", 1.0))]
	else:
		context_label.text = "%s · 成熟\n收获 ×%d · %d 金\n能源工厂：每份 %d E" % [crop_name, yield_count, income, _crop_energy(int(plot.crop_type))]
	var farm: Dictionary = development.tile_at(plot.cell)
	if float(farm.get("hp", 100.0)) < 100.0:
		context_label.text += "\n\n受损 %d/100 · 禁止播种\n修缮：%s" % [farm.hp, Development.Rules.cost_text(development.repair_cost(plot.cell))]


func _growth_multiplier() -> float:
	if current_weather < 0:
		return 1.0
	var zone: Dictionary = zones[current_weather]
	return development.weather_growth(str(zone.kind), float(zone.growth))


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
	_draw_sky()
	var shake := Vector2.ZERO
	if screen_shake_time > 0.0:
		var phase := Time.get_ticks_msec() * 0.09
		shake = Vector2(sin(phase), cos(phase * 1.37)) * screen_shake_strength * (screen_shake_time / 0.3)
	draw_set_transform(VIEW_CENTER + shake - camera_world * camera_zoom, 0.0, Vector2(camera_zoom, camera_zoom))
	_draw_weather_zones()
	_draw_targets()
	_draw_hazards()
	_draw_island()
	_draw_hook()
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_draw_weather_effects()
	_draw_warning_overlay()
	_draw_soft_boundary_overlay()
	if sky_map_open:
		_draw_sky_map()


func _draw_sky() -> void:
	draw_rect(Rect2(Vector2.ZERO, VIEW_SIZE), SKY_TOP)
	for line in range(12):
		var blend := float(line) / 11.0
		var color := SKY_TOP.lerp(SKY_BOTTOM, blend)
		draw_rect(Rect2(0, line * VIEW_SIZE.y / 12.0, VIEW_SIZE.x, VIEW_SIZE.y / 12.0 + 1.0), color)
	var drift := fmod(Time.get_ticks_msec() * 0.012, VIEW_SIZE.x + 300.0) - 150.0
	_draw_cloud(Vector2(drift, 118), 0.8)
	_draw_cloud(Vector2(fmod(drift + 520.0, VIEW_SIZE.x + 260.0) - 100.0, 235), 0.58)
	_draw_cloud(Vector2(fmod(drift + 930.0, VIEW_SIZE.x + 300.0) - 120.0, 520), 0.72)


func _draw_cloud(position_value: Vector2, scale_value: float) -> void:
	var cloud_color := Color(1, 1, 1, 0.42)
	draw_circle(position_value, 32.0 * scale_value, cloud_color)
	draw_circle(position_value + Vector2(31, 3) * scale_value, 24.0 * scale_value, cloud_color)
	draw_circle(position_value + Vector2(-34, 7) * scale_value, 22.0 * scale_value, cloud_color)
	draw_rect(Rect2(position_value + Vector2(-42, 2) * scale_value, Vector2(84, 25) * scale_value), cloud_color)


func _draw_weather_zones() -> void:
	for zone in zones:
		if not _world_visible(zone.pos, float(zone.radius)):
			continue
		draw_circle(zone.pos, float(zone.radius), zone.color)
		draw_arc(zone.pos, float(zone.radius), 0, TAU, 72, zone.edge, 3.0)
		draw_arc(zone.pos, float(zone.radius) - 9.0, 0, TAU, 72, Color(zone.edge, 0.45), 1.5)
		var icon_texture := _icon(int(zone.icon))
		draw_texture_rect(icon_texture, Rect2(zone.pos - Vector2(28, 28), Vector2(56, 56)), false, Color(1, 1, 1, 0.82))


func _draw_targets() -> void:
	for target in targets:
		if not bool(target.active) or target.has("island") or not _world_visible(target.pos, 40.0):
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


func _draw_hazards() -> void:
	for hazard in hazards:
		if not bool(hazard.active) or not _world_visible(hazard.pos, 200.0):
			continue
		var p: Vector2 = hazard.pos
		var bounds: Rect2 = IslandTiles.bounds(hazard.tiles)
		draw_colored_polygon(_ellipse_points(p + Vector2(16, bounds.size.y * 0.5 + 24), Vector2(bounds.size.x * 0.55, 30), 20), Color(0.19, 0.28, 0.30, 0.10))
		IslandTiles.draw_ground(self, p - bounds.get_center(), hazard.tiles, IslandTiles.CELL_SIZE, terrain_textures)
		IslandTiles.draw_decor(self, p - bounds.get_center(), hazard.tiles, IslandTiles.CELL_SIZE, int(hazard.biome) == 1, tree_texture, true)


func _draw_island() -> void:
	var p := island_pos
	draw_colored_polygon(_ellipse_points(p + Vector2(island_bounds.get_center().x + 14, island_bounds.end.y + 8), Vector2(island_bounds.size.x * 0.52, 62), 32), Color(0.18, 0.24, 0.26, 0.13))
	IslandTiles.draw_ground(self, p, island_tiles, IslandTiles.CELL_SIZE, terrain_textures)

	var ordered := island_tiles.duplicate()
	ordered.sort_custom(IslandTiles._tile_painter_order)
	var plot_indices: Dictionary = {}
	for index in range(plots.size()):
		plot_indices[plots[index].cell] = index
	for tile in ordered:
		if plot_indices.has(tile.cell):
			_draw_plot(int(plot_indices[tile.cell]))
		var tree_offset := Vector2.ZERO
		if tile.kind == "tree":
			# Preserve the large tree; move its trunk within its cell, not its canopy pixels.
			tree_offset.x = -12.0 if tile.cell.x < 0 else 12.0
		IslandTiles.draw_decor(self, p + tree_offset, [tile], IslandTiles.CELL_SIZE, false, tree_texture, true)
		var center: Vector2 = IslandTiles.cell_rect(p, tile.cell).get_center()
		var facility := str(tile.facility)
		if facility == "grapple":
			_draw_building(grapple_hut_texture, center + Vector2(12, 20), 100.0)
		elif facility == "water":
			_draw_building(water_grain_hut_texture, center + Vector2(6, 20), 88.0)
		elif facility == "energy":
			_draw_building(water_grain_hut_texture, center + Vector2(6, 20), 88.0)
			draw_circle(center + Vector2(20, -24), 7.0, Color("#f1bd45"))
		elif facility == "power":
			_draw_building(power_hut_texture, center + Vector2(0, 20), 92.0)
		if facility != "":
			draw_string(ThemeDB.fallback_font, center + Vector2(-22, 32), "Lv.%d" % int(tile.get("level", 1)), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, INK)
		if float(tile.get("hp", 100.0)) < 100.0:
			draw_line(center + Vector2(-25, -10), center + Vector2(16, 15), Color("#683b35"), 3.0)
			draw_rect(Rect2(center + Vector2(-28, 22), Vector2(56, 5)), INK)
			draw_rect(Rect2(center + Vector2(-28, 22), Vector2(56 * float(tile.hp) / 100.0, 5)), Color("#e69a4b"))
	if selected_tool == 2:
		var selected_cell: Vector2i = development.cell_at(_screen_to_world(get_viewport().get_mouse_position()))
		if not development.tile_at(selected_cell).is_empty():
			draw_rect(IslandTiles.cell_rect(p, selected_cell).grow(-2), Color("#ffe88d"), false, 3.0)
		if development.trim_pending != development.NONE:
			draw_rect(IslandTiles.cell_rect(p, development.trim_pending), Color(1.0, 0.2, 0.15, 0.3))

	_draw_steward(p + Vector2(-12, 164))
	if merchant_available:
		_draw_steward(p + Vector2(42, 164))
		draw_string(ThemeDB.fallback_font, p + Vector2(22, 184), "商人", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#7a3f76"))


func _draw_building(texture: Texture2D, bottom_center: Vector2, width: float) -> void:
	var source_size := texture.get_size()
	var size := Vector2(width, width * source_size.y / source_size.x)
	var destination := Rect2(bottom_center - Vector2(size.x * 0.5, size.y), size)
	draw_texture_rect(texture, destination, false)


func _draw_steward(bottom_center: Vector2) -> void:
	var height := 40.0
	var width := height * float(steward_texture.get_width()) / maxf(1.0, float(steward_texture.get_height()))
	draw_texture_rect(steward_texture, Rect2(bottom_center - Vector2(width * 0.5, height), Vector2(width, height)), false)


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
	var stage := CROP_STAGE_COUNT - 1 if state == 2 else clampi(int(floor(progress * 4.0)), 0, CROP_STAGE_COUNT - 2)
	var crop_texture := rice_atlas if int(plot.crop_type) == CROP_RICE else tomato_atlas
	var rice := int(plot.crop_type) == CROP_RICE
	var source_rect: Rect2 = RICE_FRAMES[stage] if rice else TOMATO_FRAMES[stage]
	var source_scale := 30.0 / 498.0 if rice else 32.0 / 495.0
	var baseline := 628.0 if rice else 616.0
	var sprite_size := source_rect.size * source_scale
	var destination := Rect2(rect.get_center() + Vector2(-sprite_size.x * 0.5, 17.0 - baseline * source_scale), sprite_size)
	draw_texture_rect_region(crop_texture, destination, source_rect)
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
		for worker in range(3):
			var worker_pos := origin.lerp(hook_pos, minf(1.0, progress * 3.0)) + Vector2(-18 + worker * 18, 28 + sin(progress * 35.0 + worker) * 3.0)
			draw_circle(worker_pos + Vector2(0, -7), 5, Color("#f0c99d"))
			draw_rect(Rect2(worker_pos, Vector2(8, 10)), Color("#4c7f65"))


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


func _world_to_map(world_position: Vector2) -> Vector2:
	return MAP_RECT.get_center() + (world_position - island_pos) * MAP_SCALE


func _draw_sky_map() -> void:
	draw_rect(Rect2(Vector2.ZERO, VIEW_SIZE), Color(0.05, 0.10, 0.16, 0.68))
	draw_rect(MAP_RECT, Color(0.08, 0.16, 0.22, 0.94))
	draw_rect(MAP_RECT, Color("#b8e3e2"), false, 3.0)
	var font := ThemeDB.fallback_font
	draw_string(font, MAP_RECT.position + Vector2(20, 30), "天空地图 · 雷达 Lv.%d · 可见 %.1f 航区" % [int(development.tech.radar), development.radar_range() / WorldLayout.SECTOR_SIZE], HORIZONTAL_ALIGNMENT_LEFT, -1.0, 17, Color.WHITE)
	draw_string(font, Vector2(MAP_RECT.position.x + 20, MAP_RECT.end.y - 14), "大轮廓代表稀有大型岛 · 紫色为商店岛 · 点击标记 / Enter 启航", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 13, Color("#d7edf1"))


func _draw_sky_map_content() -> void:
	var grid_step := WorldLayout.SECTOR_SIZE * MAP_SCALE
	var origin := _world_to_map(world_origin)
	for grid_index in range(-12, 13):
		var grid_x := MAP_RECT.get_center().x + fmod(origin.x - MAP_RECT.get_center().x, grid_step) + grid_index * grid_step
		var grid_y := MAP_RECT.get_center().y + fmod(origin.y - MAP_RECT.get_center().y, grid_step) + grid_index * grid_step
		map_ink.draw_line(Vector2(grid_x, MAP_RECT.position.y), Vector2(grid_x, MAP_RECT.end.y), Color(0.5, 0.7, 0.75, 0.12), 1.0)
		map_ink.draw_line(Vector2(MAP_RECT.position.x, grid_y), Vector2(MAP_RECT.end.x, grid_y), Color(0.5, 0.7, 0.75, 0.12), 1.0)
	for zone_value in zones:
		var zone: Dictionary = zone_value
		var map_position := _world_to_map(zone.pos)
		map_ink.draw_circle(map_position, float(zone.radius) * MAP_SCALE, Color(zone.color, 0.30))
		map_ink.draw_arc(map_position, float(zone.radius) * MAP_SCALE, 0.0, TAU, 40, Color(zone.edge, 0.65), 1.0)
		if warning_system_unlocked:
			map_ink.draw_line(map_position, _world_to_map(zone.pos + zone.velocity * 60.0), Color(zone.edge, 0.35), 1.0)
	for target in targets:
		if bool(target.active) and not target.has("island"):
			map_ink.draw_rect(Rect2(_world_to_map(target.pos) - Vector2(2, 2), Vector2(4, 4)), Color("#e5c78b"))
	for hazard_value in hazards:
		var hazard: Dictionary = hazard_value
		if not bool(hazard.active) or hazard.pos.distance_to(island_pos) > development.radar_range():
			continue
		var map_position := _world_to_map(hazard.pos)
		var center: Vector2 = IslandTiles.bounds(hazard.tiles).get_center() * MAP_SCALE
		var color: Color = Color("#c98be8") if bool(hazard.get("shop", false)) else [Color("#72a776"), Color("#a0b1b5"), Color("#d8bd7d"), Color("#a6c583"), Color("#cf6849"), Color("#e6c558")][int(hazard.biome)]
		for tile in hazard.tiles:
			var rect := IslandTiles.cell_rect(map_position - center, tile.cell, IslandTiles.CELL_SIZE * MAP_SCALE)
			map_ink.draw_rect(rect.grow(-0.4), color)
		if int(hazard.get("size_class", 0)) > 0:
			var radius := 10.0 + 4.0 * int(hazard.get("size_class", 0))
			map_ink.draw_circle(map_position, radius, Color.WHITE, false, 1.5)
	var island_map_position := MAP_RECT.get_center()
	for tile in island_tiles:
		var rect := IslandTiles.cell_rect(island_map_position, tile.cell, IslandTiles.CELL_SIZE * MAP_SCALE)
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

