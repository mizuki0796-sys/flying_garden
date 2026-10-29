extends Control

const Rules = preload("res://scripts/development_rules.gd")
const GROUPS := [
	{"name": "动力与能源", "icon": "energy", "keys": ["engine", "efficiency", "storage", "bioenergy", "automatic", "mineral_energy", "geothermal"]},
	{"name": "岛屿建设", "icon": "land", "keys": ["development", "terraform", "layout", "recycling"]},
	{"name": "农林生产", "icon": "rice", "keys": ["agri_automation", "forestry"]},
	{"name": "防护与天气", "icon": "shield", "keys": ["reinforcement", "shelter", "forecast"]},
	{"name": "航行与对接", "icon": "map", "keys": ["hook", "docking", "radar"]},
	{"name": "港口与探索", "icon": "house", "keys": ["harbor", "exploration"]},
]
const ICONS := {"engine": "build", "efficiency": "energy", "storage": "house", "bioenergy": "rice", "automatic": "house", "mineral_energy": "ore", "geothermal": "magma", "development": "land", "terraform": "damage", "layout": "land", "recycling": "growth", "agri_automation": "rice", "forestry": "wood", "reinforcement": "stone", "shelter": "shield", "forecast": "rain", "hook": "build", "docking": "land", "radar": "focus", "harbor": "house", "exploration": "map"}
const HOVER_DELAY := 0.5
var game
var dev
var group_index := 0
var nodes: Dictionary = {}
var card: PanelContainer
var active_key := ""
var pending_key := ""
var hover_time := 0.0
var leave_time := 0.0
var research_button: Button
var surface: Control

func setup(owner_game, category: int) -> void:
	game = owner_game
	dev = game.development
	group_index = category
	custom_minimum_size = Vector2(952, 460)
	mouse_filter = Control.MOUSE_FILTER_PASS
	render()

func _label(text: String, pixels := 14) -> Label:
	var label: Label = dev._energy_label(text, pixels)
	return label

func _icon(key: String, pixels: int) -> TextureRect:
	var icon: TextureRect = game._hud_texture(key, pixels)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return icon

func _panel(pos: Vector2, dimensions: Vector2, fill: String, border: String) -> Panel:
	var panel := Panel.new()
	panel.position = pos
	panel.size = dimensions
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", game._button_style(Color(fill), Color(border)))
	surface.add_child(panel)
	return panel

func position_for(key: String) -> Vector2:
	if group_index == 0:
		return {"engine": Vector2(150, 86), "efficiency": Vector2(326, 86), "storage": Vector2(502, 86), "bioenergy": Vector2(150, 246), "automatic": Vector2(326, 246), "mineral_energy": Vector2(502, 206), "geothermal": Vector2(502, 336)}[key]
	if group_index == 1:
		return {"development": Vector2(150, 156), "terraform": Vector2(326, 156), "layout": Vector2(502, 86), "recycling": Vector2(502, 246)}[key]
	var index: int = GROUPS[group_index].keys.find(key)
	return Vector2(150 + index * 176, 156)

func _texture(key: String) -> Texture2D:
	match key:
		"automatic": return game.energy_conversion_texture
		"engine": return game.power_hut_texture
		"storage": return game.water_grain_hut_texture
		"hook": return game.grapple_hut_texture
		"agri_automation": return game.farm_hut_textures[0]
	return game._hud_icon(str(ICONS[key]))

func render() -> void:
	_hide_card()
	if is_instance_valid(surface):
		remove_child(surface)
		surface.queue_free()
	nodes.clear()
	surface = Control.new()
	surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	surface.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(surface)
	var title := _label("科技树", 21)
	title.position = Vector2(40, 0)
	surface.add_child(title)
	var symbol := _icon("tech", 28)
	symbol.position = Vector2(2, 0)
	surface.add_child(symbol)
	var heading := _label(str(GROUPS[group_index].name), 17)
	heading.position = Vector2(140, 4)
	surface.add_child(heading)
	var researched := 0
	for key in GROUPS[group_index].keys:
		if int(dev.tech[key]) > 0: researched += 1
	var count := _label("%d / %d" % [researched, GROUPS[group_index].keys.size()], 13)
	count.position = Vector2(850, 5)
	surface.add_child(count)
	var close: Button = dev._energy_action("close", "关闭 · Esc", dev.close_menu)
	close.position = Vector2(918, 0)
	surface.add_child(close)
	_panel(Vector2(0, 47), Vector2(94, 410), "#ede3c5", "#d4c6a3")
	_panel(Vector2(115, 47), Vector2(837, 410), "#fbf2d9", "#ddcfae")
	for i in range(GROUPS.size()):
		var button: Button = game._make_small_button("")
		button.name = "Category_%d" % i
		button.position = Vector2(15, 60 + i * 64)
		button.custom_minimum_size = Vector2(64, 54)
		button.size = Vector2(64, 54)
		button.icon = game._hud_icon(str(GROUPS[i].icon))
		button.expand_icon = true
		button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.add_theme_constant_override("icon_max_width", 33)
		button.tooltip_text = str(GROUPS[i].name)
		button.add_theme_stylebox_override("normal", game._button_style(Color("#cdddaf") if i == group_index else Color("#f7edcf"), Color("#6e8353") if i == group_index else Color("#d4c6a3")))
		button.set_deferred("size", Vector2(64, 54))
		button.pressed.connect(select_group.bind(i))
		surface.add_child(button)
	var wires := Control.new()
	wires.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wires.draw.connect(func() -> void:
		for key in GROUPS[group_index].keys:
			for required in Rules.TECH[key].needs:
				if required not in GROUPS[group_index].keys: continue
				var start := position_for(required) + Vector2(76, 38)
				var end := position_for(key) + Vector2(0, 38)
				var mid := (start.x + end.x) * 0.5
				var color := Color("#849a64") if int(dev.tech[required]) >= int(Rules.TECH[key].needs[required]) else Color("#c3b69a")
				wires.draw_polyline(PackedVector2Array([start, Vector2(mid, start.y), Vector2(mid, end.y), end]), color, 3)
	)
	surface.add_child(wires)
	for key in GROUPS[group_index].keys: _add_node(str(key))

func _add_node(key: String) -> void:
	var rule: Dictionary = Rules.TECH[key]
	var button: Button = game._make_small_button("")
	button.name = "Tech_" + key
	button.position = position_for(key)
	button.custom_minimum_size = Vector2(76, 76)
	button.size = Vector2(76, 76)
	button.add_theme_stylebox_override("normal", game._button_style(Color("#dfeac9") if int(dev.tech[key]) > 0 else Color("#f4ecd6"), Color("#70875a") if int(dev.tech[key]) > 0 else Color("#b6aa87")))
	button.add_theme_stylebox_override("hover", game._button_style(Color("#f6dc91"), Color("#99743b")))
	button.pressed.connect(show_card.bind(key))
	button.focus_entered.connect(show_card.bind(key))
	surface.add_child(button)
	button.set_deferred("size", Vector2(76, 76))
	nodes[key] = button
	var icon := TextureRect.new()
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture = _texture(key)
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(icon)
	icon.position = Vector2(12, 7)
	icon.size = Vector2(52, 50)
	if key == "bioenergy":
		var badge := _icon("energy" if key == "automatic" else "tomato", 23)
		badge.position = Vector2(43, 33)
		button.add_child(badge)
	var pips := Control.new()
	pips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pips.position = Vector2(38 - int(rule.max) * 7, 64)
	pips.draw.connect(func() -> void:
		for i in range(int(rule.max)):
			pips.draw_rect(Rect2(i * 14, 0, 10, 5), Color("#71884f") if i < int(dev.tech[key]) else Color("#c6bea6"))
	)
	button.add_child(pips)
	if dev._tech_blocked(key):
		var lock: Control = dev._energy_mark("lock")
		lock.position = Vector2(59, -5)
		button.add_child(lock)

func select_group(index: int) -> void:
	group_index = index
	dev.selected_tech_group = index
	render()

func jump_to(key: String) -> void:
	for i in range(GROUPS.size()):
		if key in GROUPS[i].keys:
			select_group(i)
			show_card(key)
			return

func _hide_card() -> void:
	if is_instance_valid(card):
		card.get_parent().remove_child(card)
		card.queue_free()
	card = null
	active_key = ""
	pending_key = ""
	hover_time = 0.0
	leave_time = 0.0

func show_card(key: String) -> void:
	if not nodes.has(key): return
	_hide_card()
	active_key = key
	dev.selected_tech = key
	var rule: Dictionary = Rules.TECH[key]
	card = PanelContainer.new()
	card.name = "TechnologyDetails"
	card.z_index = 20
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.custom_minimum_size.x = 300
	card.add_theme_stylebox_override("panel", game._button_style(Color("#fff8e5"), Color("#8e784e")))
	add_child(card)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	card.add_child(game._with_margin(body, 12))
	var title := HBoxContainer.new()
	body.add_child(title)
	title.add_child(_icon(str(ICONS[key]), 25))
	var name_label := _label(str(rule.name), 18)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_child(name_label)
	title.add_child(_label("%d / %d" % [dev.tech[key], rule.max], 12))
	var effect := _label(str(rule.effect), 14)
	effect.custom_minimum_size.x = 260
	effect.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(effect)
	if not rule.needs.is_empty():
		body.add_child(_label("前置", 12))
		var needs := HFlowContainer.new()
		body.add_child(needs)
		for required in rule.needs:
			var met: bool = int(dev.tech[required]) >= int(rule.needs[required])
			var prerequisite: Button = game._make_small_button("%d/%d %s" % [dev.tech[required], rule.needs[required], "✓" if met else "×"])
			prerequisite.name = "Requires_" + required
			prerequisite.icon = _texture(required)
			prerequisite.expand_icon = true
			prerequisite.add_theme_constant_override("icon_max_width", 24)
			prerequisite.tooltip_text = str(Rules.TECH[required].name) + " · 点击查看"
			prerequisite.pressed.connect(jump_to.bind(required))
			needs.add_child(prerequisite)
	var maximum: bool = int(dev.tech[key]) >= int(rule.max)
	var cost: Dictionary = dev.research_cost(key)
	if not maximum:
		var prices := HFlowContainer.new()
		prices.add_theme_constant_override("h_separation", 12)
		body.add_child(prices)
		for resource in cost:
			var row := HBoxContainer.new()
			prices.add_child(row)
			row.add_child(_icon("rice" if resource == "food" else resource, 22))
			var price := _label(str(cost[resource]), 14)
			if dev.stock(resource) < int(cost[resource]): price.add_theme_color_override("font_color", Color("#ae493a"))
			row.add_child(price)
	var blocked: bool = dev._tech_blocked(key)
	research_button = game._make_small_button("已满级" if maximum else ("前置未满足" if blocked else ("资源不足" if not dev.can_pay(cost) else "↑  研究")))
	research_button.name = "Research"
	research_button.add_theme_stylebox_override("disabled", game._button_style(Color("#e4decc"), Color("#b9b29c")))
	research_button.add_theme_color_override("font_disabled_color", Color("#7a705d"))
	research_button.custom_minimum_size.y = 40
	research_button.add_theme_font_size_override("font_size", 14)
	research_button.disabled = maximum or blocked or not dev.can_pay(cost)
	research_button.pressed.connect(_research.bind(key))
	body.add_child(research_button)
	_place_card()
	call_deferred("_place_card")

func _place_card() -> void:
	if not is_instance_valid(card) or not nodes.has(active_key): return
	card.reset_size()
	var rect: Rect2 = nodes[active_key].get_global_rect()
	var bounds := get_global_rect().intersection(Rect2(Vector2.ZERO, get_viewport_rect().size))
	var point := rect.position + Vector2(rect.size.x + 14, -60)
	if point.x + card.size.x > bounds.end.x: point.x = rect.position.x - card.size.x - 14
	point.x = clampf(point.x, bounds.position.x, maxf(bounds.position.x, bounds.end.x - card.size.x))
	point.y = clampf(point.y, bounds.position.y, maxf(bounds.position.y, bounds.end.y - card.size.y))
	card.global_position = point

func _research(key: String) -> void:
	if dev.research(key):
		render()
		show_card(key)

func _process(delta: float) -> void:
	if not is_visible_in_tree() or not dev.modal.visible or not dev.tech_open:
		_hide_card()
		return
	poll_hover(delta, get_global_mouse_position())

func poll_hover(delta: float, mouse: Vector2) -> void:
	if is_instance_valid(card):
		var source: Rect2 = nodes[active_key].get_global_rect()
		var popup := card.get_global_rect()
		var bridge := Rect2(Vector2(minf(source.end.x, popup.end.x), maxf(source.position.y, popup.position.y)), Vector2(14, minf(source.end.y, popup.end.y) - maxf(source.position.y, popup.position.y)))
		if popup.has_point(mouse) or source.has_point(mouse) or bridge.has_point(mouse):
			leave_time = 0.0
			return
		leave_time += delta
		if leave_time < 0.18: return
		_hide_card()
	var hovered := ""
	for key in nodes:
		if nodes[key].get_global_rect().has_point(mouse): hovered = key; break
	if hovered != pending_key:
		pending_key = hovered
		hover_time = 0.0
	if hovered.is_empty(): return
	hover_time += delta
	if hover_time >= HOVER_DELAY: show_card(hovered)
