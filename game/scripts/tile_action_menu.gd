extends RefCounted

const Rules = preload("res://scripts/development_rules.gd")
const Tiles = preload("res://scripts/island_tiles.gd")
const NONE := Vector2i(999999, 999999)
const LABELS := {"gather": "采集资源", "farm": "开垦农田", "tree": "种植林木", "power": "建造引擎室", "water": "建造储能室", "grapple": "建造抓钩小屋", "energy": "建造能源工厂", "repair": "修缮", "upgrade": "升级设施", "move": "搬迁设施", "trim": "剪裁地块", "confirm_trim": "确认抛弃地块", "cancel": "取消", "restore": "整平为土地", "plant_rice": "播种水稻", "plant_tomato": "播种番茄", "harvest": "收获作物"}
const ICONS := {"gather": "build", "farm": "rice", "tree": "wood", "power": "energy", "water": "house", "energy": "energy", "repair": "build", "upgrade": "growth", "move": "focus", "trim": "land", "confirm_trim": "land", "cancel": "help", "restore": "land", "plant_rice": "rice_seeds", "plant_tomato": "tomato_seeds", "harvest": "rice"}
const SHORT_NAMES := {"coins": "金", "wood": "木", "stone": "石", "ore": "矿", "magma": "岩浆", "food": "粮", "rice_seeds": "稻种", "tomato_seeds": "番茄种"}
var game
var panel: PanelContainer
var content: VBoxContainer
var cell := NONE
var confirm_trim := false
var buttons: Dictionary = {}

func _init(owner_node) -> void:
	game = owner_node

func create_ui(root: Control) -> void:
	panel = game._make_panel(Vector2.ZERO, Vector2(292, 0), Color("#fff5dc"))
	panel.name = "TileActionMenu"
	panel.z_index = 4
	root.add_child(panel)
	content = VBoxContainer.new()
	content.add_theme_constant_override("separation", 4)
	panel.add_child(game._with_margin(content, 9))
	panel.hide()
	panel.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
			close()
			game.get_viewport().set_input_as_handled())

func is_open() -> bool:
	return panel != null and panel.visible

func close() -> void:
	if panel != null: panel.hide()
	cell = NONE
	confirm_trim = false
	game.queue_redraw()

func open_at(target: Vector2i) -> bool:
	var dev = game.development
	if game.sky_map_open or dev.modal.visible or game.hook_state != game.HOOK_READY or dev.tile_at(target).is_empty():
		close()
		return false
	cell = target
	confirm_trim = false
	game.context_panel.hide()
	game.hovered_plot = -1
	render()
	panel.show()
	update()
	game.queue_redraw()
	return true

func actions_for(target: Vector2i) -> Array:
	var dev = game.development
	var tile: Dictionary = dev.tile_at(target)
	if tile.is_empty(): return []
	if str(tile.facility) == "farm_hut": return ["farm_crop", "farm_toggle", "upgrade", "repair", "move"]
	if str(tile.facility) == "energy": return ["fuel_source", "repair", "move"]
	if str(tile.facility) != "": return ["upgrade", "repair", "move"]
	var actions: Array = []
	if tile.kind == "farm":
		var index: int = dev.plot_at(target)
		if index >= 0 and int(game.plots[index].state) == 0:
			actions.append_array(["plant_rice", "plant_tomato"])
		else: actions.append("harvest")
		actions.append("restore")
	else:
		if not bool(tile.get("depleted", false)): actions.append("gather")
		if tile.kind in ["grass", "sand"]:
			actions.append("farm")
			if tile.kind == "grass": actions.append("tree")
			actions.append_array(["power", "water", "grapple", "energy", "farm_hut"])
	if float(tile.get("hp", 100.0)) < 100.0: actions.append("repair")
	actions.append("trim")
	return actions

func quote(target: Vector2i, key: String) -> Dictionary:
	var dev = game.development
	var tile: Dictionary = dev.tile_at(target)
	var cost: Dictionary = {}
	var reason := ""
	if tile.is_empty(): return {"cost": {}, "reason": "地块已不存在"}
	var facility := str(tile.facility)
	var index: int = dev.plot_at(target)
	if Rules.BUILD_COSTS.has(key):
		cost = Rules.BUILD_COSTS[key]
		var required: String = {"tree": "forestry", "power": "engine", "water": "storage", "grapple": "hook", "energy": "automatic", "farm_hut": "agri_automation"}.get(key, "")
		if facility != "" or tile.kind not in (["grass"] if key == "tree" else ["grass", "sand"]): reason = "需要空闲土地"
		elif float(tile.get("hp", 100.0)) < 100.0: reason = "请先修缮"
		elif required != "" and int(dev.tech[required]) == 0: reason = "需" + str(Rules.TECH[required].name)
		elif key == "power" and dev.facility_count(key) >= int(dev.tech.engine): reason = "引擎数量已达上限"
		elif key in ["grapple", "energy"] and dev.has_facility(key): reason = "只能建造一座"
	elif key == "gather":
		var required := 2 if tile.kind == "lava" else (1 if tile.kind in ["rock", "gold"] else 0)
		if facility != "" or bool(tile.get("depleted", false)) or tile.kind == "farm": reason = "没有可采集资源"
		elif int(dev.tech.development) < required: reason = "需岛屿开拓 %d 级" % required
	elif key == "repair":
		cost = dev.repair_cost(target)
		if cost.is_empty(): reason = "耐久完好"
	elif key == "upgrade":
		cost = dev.upgrade_cost(target)
		if facility == "energy": reason = "通过能源科技提升效率"
		elif facility == "": reason = "请选择设施"
		else:
			var branch: String = {"power": "engine", "water": "storage", "grapple": "hook", "farm_hut": "agri_automation"}[facility]
			var max_level := int(dev.tech[branch]) + (0 if facility == "farm_hut" else 1)
			if int(tile.get("level", 1)) >= max_level: reason = "已满级" if facility == "farm_hut" and max_level == 3 else "需提升" + str(Rules.TECH[branch].name)
	elif key == "move":
		cost = {"coins": 5}
		if facility == "": reason = "请选择设施"
		elif game.hook_state != game.HOOK_READY: reason = "等待抓钩收回"
	elif key in ["trim", "confirm_trim"]:
		if int(dev.tech.terraform) == 0: reason = "需岛屿剪裁"
		elif game.hook_state != game.HOOK_READY: reason = "等待抓钩收回"
		elif not dev.can_trim(target): reason = "须保留核心、设施和连通性"
	elif key == "restore":
		cost = Rules.RESTORE_FARM_COST
		if tile.kind != "farm" or facility != "": reason = "请选择农田"
		elif index >= 0 and int(game.plots[index].state) != 0: reason = "请先收获作物"
	elif key in ["plant_rice", "plant_tomato", "harvest"]:
		if index < 0 or facility != "": reason = "请选择农田"
		elif key == "harvest":
			if int(game.plots[index].state) != 2: reason = "作物尚未成熟"
		else:
			cost = {"rice_seeds" if key == "plant_rice" else "tomato_seeds": 1}
			if float(tile.get("hp", 100.0)) < 100.0: reason = "请先修缮"
			elif int(game.plots[index].state) != 0: reason = "农田已有作物"
	if reason == "" and not dev.can_pay(cost): reason = "资源不足"
	return {"cost": cost, "reason": reason}

func _cost_text(cost: Dictionary) -> String:
	var parts: PackedStringArray = []
	for key in cost: parts.append("%d%s" % [cost[key], SHORT_NAMES[key]])
	return "  ".join(parts)

func _button_text(key: String, state: Dictionary) -> String:
	var tile: Dictionary = game.development.tile_at(cell)
	if key == "farm_crop": return "管理作物：%s · 点击切换" % game._crop_name(int(tile.get("farm_crop", 0)))
	if key == "farm_toggle": return "暂停自动管理" if bool(tile.get("farm_enabled", true)) else "启动自动管理"
	if key == "fuel_source": return "选择能源来源 · R"
	var title: String = "建造自动化管理小屋" if key == "farm_hut" else LABELS[key]
	if state.reason != "": title += " · " + str(state.reason)
	var detail := _cost_text(state.cost)
	if detail == "": detail = {"gather": "采集这格资源", "harvest": "收获这格成熟作物", "trim": "抛弃前需再次确认", "confirm_trim": "地形和作物不返还", "cancel": "保留地块"}.get(key, "")
	return title + ("\n" + detail if detail != "" else "")

func render() -> void:
	for child in content.get_children():
		content.remove_child(child)
		child.queue_free()
	buttons.clear()
	var tile: Dictionary = game.development.tile_at(cell)
	if tile.is_empty(): close(); return
	var header := Label.new()
	header.text = "%s  ·  %d,%d" % [Rules.FACILITY_NAMES.get(str(tile.facility), Rules.TERRAIN_NAMES[tile.kind]), cell.x, cell.y]
	if str(tile.facility) == "farm_hut": header.text += "\nLv.%d · 管理半径 %d 格" % [int(tile.get("level", 1)), game.development.farm_radius(tile)]
	elif str(tile.kind) == "farm": header.text += "\n林木减灾 %d%% · %s" % [roundi(game.development.forest_protection(cell) * 100), "小屋管理中" if not game.development.farm_manager(cell).is_empty() else "手动管理"]
	header.add_theme_font_size_override("font_size", 16)
	header.add_theme_color_override("font_color", game.INK)
	content.add_child(header)
	var keys: Array = ["confirm_trim", "cancel"] if confirm_trim else actions_for(cell)
	for key in keys:
		var state := quote(cell, key)
		var button: Button = game._make_small_button(_button_text(key, state))
		button.name = "TileAction_" + key
		button.custom_minimum_size = Vector2(268, 38)
		button.add_theme_font_size_override("font_size", 11)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.icon = game._icon(2) if key == "grapple" else game._hud_icon(ICONS.get(key, "house"))
		button.expand_icon = true
		button.add_theme_constant_override("icon_max_width", 22)
		button.add_theme_color_override("font_disabled_color", Color("#8e9384"))
		button.add_theme_stylebox_override("disabled", game._button_style(Color("#e8e6d9"), Color("#c7c9b8")))
		button.pressed.connect(activate.bind(key))
		content.add_child(button)
		buttons[key] = button
	var hint := Label.new()
	hint.text = "点击执行 · Esc / 点击外部关闭"
	hint.add_theme_font_size_override("font_size", 10)
	hint.add_theme_color_override("font_color", Color("#7e806c"))
	content.add_child(hint)
	panel.reset_size()
	call_deferred("update")
	update()

func _place() -> void:
	var anchor: Vector2 = game._world_to_screen(game.island_pos + Vector2(cell) * Tiles.CELL_SIZE)
	var position := anchor + Vector2(28, -24)
	if position.x + panel.size.x > game.VIEW_SIZE.x - 12: position.x = anchor.x - panel.size.x - 28
	panel.position = position.clamp(Vector2(144, 92), game.VIEW_SIZE - panel.size - Vector2(12, 12))

func update() -> void:
	if not is_instance_valid(game) or not is_open(): return
	if game.sky_map_open or game.development.modal.visible or game.development.tile_at(cell).is_empty(): close(); return
	_place()
	for key in buttons:
		var state := quote(cell, key)
		buttons[key].disabled = state.reason != ""
		buttons[key].text = _button_text(key, state)
		buttons[key].tooltip_text = str(state.reason) + ("\n" + Rules.cost_text(state.cost) if not state.cost.is_empty() else "")

func activate(key: String) -> bool:
	if not is_open() or not buttons.has(key): return false
	var dev = game.development
	var state := quote(cell, key)
	if state.reason != "": dev.message(state.reason); update(); return false
	if key == "cancel": close(); return true
	if key == "trim": confirm_trim = true; render(); return true
	if key in ["farm_crop", "farm_toggle"]:
		var tile: Dictionary = dev.tile_at(cell)
		if str(tile.facility) != "farm_hut": return false
		if key == "farm_crop": tile.farm_crop = 1 - int(tile.get("farm_crop", 0))
		else: tile.farm_enabled = not bool(tile.get("farm_enabled", true))
		render()
		return true
	var target := cell
	close()
	match key:
		"gather": return dev.gather(target)
		"farm", "tree", "power", "water", "grapple", "energy", "farm_hut": return dev.build(target, key)
		"fuel_source": dev.toggle_energy(); return true
		"upgrade": return dev.upgrade(target)
		"repair": return dev.repair(target)
		"restore": return dev.restore_farmland(target)
		"confirm_trim": return dev.trim(target)
		"move":
			dev.select_action("move")
			dev.move_from = target
			dev.message("点击空闲草地或沙地搬迁 · 5 金；右键 / Esc 取消")
			return true
		"plant_rice", "plant_tomato", "harvest":
			if key != "harvest": game._select_crop_tool(game.CROP_RICE if key == "plant_rice" else game.CROP_TOMATO)
			game._interact_with_plot(game._plot_rect(dev.plot_at(target)).get_center())
			return true
	return false
