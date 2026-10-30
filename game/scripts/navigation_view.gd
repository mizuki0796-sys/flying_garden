extends Control

const HOVER_DELAY := 0.55
const MAP_ZOOM_MIN := 0.06
const MAP_ZOOM_MAX := 0.8
var game
var hover_key := ""
var hover_time := 0.0
var hover_card: PanelContainer
var hover_label: Label

func setup(owner_node, ui: Control) -> void:
	game = owner_node
	name = "NavigationView"
	size = game.VIEW_SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 20
	ui.add_child(self)
	hover_card = game._make_panel(Vector2.ZERO, Vector2(270, 0), Color("#fff1d4"))
	hover_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hover_card)
	hover_label = Label.new()
	hover_label.custom_minimum_size.x = 246
	hover_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hover_label.add_theme_font_size_override("font_size", 14)
	hover_label.add_theme_color_override("font_color", game.INK)
	hover_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var margin: MarginContainer = game._with_margin(hover_label, 12)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hover_card.add_child(margin)
	hover_card.hide()

func paused() -> bool:
	return game.sky_map_open

func toggle_map() -> void:
	game.sky_map_open = not game.sky_map_open
	if game.sky_map_open:
		game.map_center = game.island_pos
		game.development.close_menu()
		game.development.tile_menu.close()
		game.guide_panel.hide()
		game.inspected_island = {}
		game.middle_dragging = false
		game._cancel_autopilot("手动驾驶")
	clear_hover()
	game._update_hud()
	game.queue_redraw()
	queue_redraw()

func clear_hover() -> void:
	hover_key = ""
	hover_time = 0.0
	if hover_card != null: hover_card.hide()

func _input(event: InputEvent) -> void:
	if not game.demo_started or game.saves.is_open(): return
	if event.is_action_pressed("toggle_map"):
		toggle_map()
	elif paused():
		if event.is_action_pressed("ui_cancel"):
			toggle_map()
		elif game.sky_map_open and event is InputEventMouseButton and event.pressed:
			if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
				zoom_map(event.position, 1.2 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.2)
			elif event.button_index == MOUSE_BUTTON_LEFT: game._set_map_destination(event.position)
			elif event.button_index == MOUSE_BUTTON_RIGHT:
				game.map_destination_set = false
				game.map_ink.queue_redraw()
	else: return
	get_viewport().set_input_as_handled()

func update(delta: float) -> void:
	if game.saves.is_open(): return
	if game.sky_map_open:
		var direction := Input.get_vector("move_left", "move_right", "move_up", "move_down")
		pan_map(direction, delta)
		poll_hover(get_viewport().get_mouse_position(), delta)

func zoom_map(point: Vector2, factor: float) -> void:
	if not game.map_clip.get_global_rect().has_point(point): return
	var anchor: Vector2 = game._map_to_world(point)
	game.map_scale = clampf(game.map_scale * factor, MAP_ZOOM_MIN, MAP_ZOOM_MAX)
	game.map_center = anchor - (point - game.MAP_RECT.get_center()) / game.map_scale
	clamp_center()
	clear_hover()
	game.queue_redraw()
	game.map_ink.queue_redraw()

func clamp_center() -> void:
	var limit: float = minf(game.development.radar_range(), game.WorldLayout.ACTIVE_RADIUS * game.WorldLayout.SECTOR_SIZE - 320.0)
	game.map_center = game.island_pos + (game.map_center - game.island_pos).limit_length(limit)

func pan_map(direction: Vector2, delta: float) -> void:
	if direction.is_zero_approx(): return
	game.map_center += direction.limit_length() * delta * 160.0 / game.map_scale
	clamp_center()
	clear_hover()
	game.queue_redraw()
	game.map_ink.queue_redraw()

func hover_at(point: Vector2) -> Dictionary:
	if not game.map_clip.get_global_rect().has_point(point): return {}
	var world: Vector2 = game._map_to_world(point)
	if not game.development.tile_at(game.development.cell_at(world)).is_empty():
		return {"key": "player", "text": "我的浮岛\n%d 格 · 质量 %.1f\n能源 %.0f / %.0f" % [game.island_tiles.size(), game.island_mass, game.energy, game.energy_capacity]}
	for island in game.hazards:
		if not island.active or not game._radar_visible(island.pos): continue
		var origin: Vector2 = island.pos - game.IslandTiles.bounds(island.tiles).get_center()
		for tile in island.tiles:
			if game.IslandTiles.cell_rect(origin, tile.cell).grow(12).has_point(world):
				return {"key": "island:%s:%s" % [island.world_key, island.world_index], "text": "%s · %s\n%d 格 · 距离 %.0f\n%s" % [island.name, island.get("rarity", "普通"), island.tiles.size(), game.island_pos.distance_to(island.pos), "可交易商店岛" if island.get("shop", false) else game.WorldLayout.BIOMES[int(island.biome)]]}
	if not game._radar_visible(world): return {}
	var weather: Dictionary = {}
	var priority := -1
	for index in range(game.zones.size()):
		var zone: Dictionary = game.zones[index]
		if world.distance_to(zone.pos) <= float(zone.radius) and int(zone.priority) > priority:
			priority = int(zone.priority)
			weather = {"key": "weather:%s" % zone.id, "text": "%s\n生长倍率 ×%.2f · 剩余 %.0f 秒\n范围 %.0f · 移动速度 %.1f" % [zone.name, zone.growth, zone.remaining, zone.radius, Vector2(zone.velocity).length()]}
	return weather

func poll_hover(point: Vector2, delta: float) -> void:
	var item := hover_at(point)
	if item.is_empty(): clear_hover(); return
	if hover_key != item.key:
		clear_hover()
		hover_key = item.key
	else: hover_time += delta
	if hover_time < HOVER_DELAY: return
	hover_label.text = item.text
	hover_card.reset_size()
	hover_card.position = (point + Vector2(18, 18)).clamp(Vector2(8, 84), game.VIEW_SIZE - hover_card.size - Vector2(8, 8))
	hover_card.show()
