extends RefCounted

const Rules = preload("res://scripts/development_rules.gd")
const Tiles = preload("res://scripts/island_tiles.gd")
const NONE := Vector2i(999999, 999999)
var game
var materials := {"wood": 12, "stone": 8, "ore": 6, "magma": 0}
var tech: Dictionary = {}
var auto_fuel := true
var action := "gather"
var move_from := NONE
var trim_pending := NONE
var modal: PanelContainer
var content: VBoxContainer
var resource_label: Label
var status_label: Label
var tech_open := false
var selected_crop := 0
var operation_message := "B 开发  ·  T 科技  ·  H 批量收获  ·  J 批量播种"

func _init(owner_node) -> void:
	game = owner_node
	for key in Rules.TECH:
		tech[key] = 0

func stock(key: String) -> int:
	match key:
		"coins": return game.coins
		"food": return game.rice_stock
		"seeds": return game.seeds
	return materials.get(key, 0)

func add_stock(key: String, amount: int) -> void:
	match key:
		"coins": game.coins += amount
		"food": game.rice_stock += amount
		"seeds": game.seeds += amount
		_: materials[key] = int(materials.get(key, 0)) + amount

func can_pay(cost: Dictionary) -> bool:
	for key in cost:
		if stock(key) < int(cost[key]): return false
	return true

func pay(cost: Dictionary) -> bool:
	if not can_pay(cost):
		message("资源不足，需要：" + Rules.cost_text(cost))
		return false
	for key in cost: add_stock(key, -int(cost[key]))
	return true

func message(text: String) -> void:
	operation_message = text
	if status_label != null: status_label.text = text

func tile_at(cell: Vector2i) -> Dictionary:
	for tile in game.island_tiles:
		if tile.cell == cell: return tile
	return {}

func cell_at(world_position: Vector2) -> Vector2i:
	var p: Vector2 = (world_position - game.island_pos) / Tiles.CELL_SIZE
	return Vector2i(floori(p.x + 0.5), floori(p.y + 0.5))

func plot_at(cell: Vector2i) -> int:
	for i in range(game.plots.size()):
		if game.plots[i].cell == cell: return i
	return -1

func sync() -> void:
	var storage := 75.0
	var grapple_level := 1
	for tile in game.island_tiles:
		if str(tile.facility) == "water": storage += 75.0 * int(tile.get("level", 1))
		if str(tile.facility) == "grapple": grapple_level = int(tile.get("level", 1))
	game.energy_capacity = storage * (1.0 + 0.2 * int(tech.storage))
	game.energy = minf(game.energy, game.energy_capacity)
	game.hook_max_distance = game.movement_settings.hook_range_tiles * game.movement_settings.tile_size + 96.0 * int(tech.hook) + 48.0 * (grapple_level - 1)
	game._refresh_island_shape()
	game._clamp_focus_offset()

func engine_power() -> float:
	var output := 0.0
	for tile in game.island_tiles:
		if str(tile.facility) == "power":
			output += (1.0 + 0.5 * (int(tile.get("level", 1)) - 1)) * maxf(0.25, float(tile.get("hp", 100.0)) / 100.0)
	return output * (1.0 + 0.3 * int(tech.engine))

func efficiency() -> float:
	return 1.0 - 0.15 * int(tech.efficiency)

func research_cost(key: String) -> Dictionary:
	return Rules.scaled_cost(Rules.TECH[key].cost, int(tech[key]) + 1)

func research(key: String) -> bool:
	if not Rules.TECH.has(key): return false
	var rule: Dictionary = Rules.TECH[key]
	if int(tech[key]) >= int(rule.max):
		message("该科技已满级")
		return false
	for required in rule.needs:
		if int(tech[required]) < int(rule.needs[required]):
			message("前置科技：%s Lv.%d" % [Rules.TECH[required].name, rule.needs[required]])
			return false
	if not pay(research_cost(key)): return false
	tech[key] += 1
	sync()
	message("研究完成：%s Lv.%d" % [rule.name, tech[key]])
	return true

func gather(cell: Vector2i) -> bool:
	var tile := tile_at(cell)
	if tile.is_empty(): return false
	if not str(tile.facility).is_empty():
		message("先搬走这格上的设施，再采集地形")
		return false
	if tile.kind == "farm":
		var index := plot_at(cell)
		if index >= 0 and int(game.plots[index].state) == 2:
			game._interact_with_plot(game._plot_rect(index).get_center())
			return true
		message("农田可用 H 收获，或种植工具管理")
		return false
	if bool(tile.get("depleted", false)):
		message("这格资源已采尽，可建造设施或改为农田")
		return false
	var required := 2 if tile.kind == "lava" else (1 if tile.kind in ["rock", "gold"] else 0)
	if int(tech.development) < required:
		message("需要岛屿开拓 Lv.%d" % required)
		return false
	var yield_values: Dictionary = Rules.YIELDS[tile.kind]
	var multiplier := 2 if int(tech.development) >= 3 else 1
	for key in yield_values: add_stock(key, int(yield_values[key]) * multiplier)
	message("采集%s：%s" % [Rules.TERRAIN_NAMES[tile.kind], Rules.cost_text(Rules.scaled_cost(yield_values, multiplier))])
	tile.kind = "grass"
	tile.depleted = true
	game.gathered += 1
	sync()
	return true

func build(cell: Vector2i, kind: String) -> bool:
	var tile := tile_at(cell)
	if tile.is_empty() or not Rules.BUILD_COSTS.has(kind): return false
	if str(tile.facility) != "" or tile.kind not in ["grass", "sand"]:
		message("请选一格没有设施的草地或沙地；林木、矿石须先采集")
		return false
	var required := "engine" if kind == "power" else "storage"
	if kind != "farm" and int(tech[required]) < 1:
		message("先在 T 科技树研究" + str(Rules.TECH[required].name))
		return false
	if not pay(Rules.BUILD_COSTS[kind]): return false
	if kind == "farm":
		tile.kind = "farm"
		game.plots.append({"cell": cell, "state": 0, "progress": 0.0, "crop_type": selected_crop})
	else:
		tile.facility = kind
		tile.level = 1
	sync()
	message("建造完成：" + ("农田" if kind == "farm" else str(Rules.FACILITY_NAMES[kind])))
	return true

func upgrade(cell: Vector2i) -> bool:
	var tile := tile_at(cell)
	if tile.is_empty() or str(tile.facility) == "":
		message("请选择一座设施")
		return false
	var branch: String = {"power": "engine", "water": "storage", "grapple": "hook"}[tile.facility]
	var level := int(tile.get("level", 1))
	if level >= int(tech[branch]) + 1:
		message("请先提升%s研究等级；建筑当前 Lv.%d" % [Rules.TECH[branch].name, level])
		return false
	if not pay(Rules.scaled_cost({"coins": 20, "wood": 2, "ore": 2}, level)): return false
	tile.level = level + 1
	sync()
	message("%s升级至 Lv.%d" % [Rules.FACILITY_NAMES[tile.facility], tile.level])
	return true

func relocate(from: Vector2i, to: Vector2i) -> bool:
	if game.hook_state != game.HOOK_READY:
		message("等待抓钩收回后再搬迁设施")
		return false
	var source := tile_at(from)
	var destination := tile_at(to)
	if source.is_empty() or destination.is_empty() or from == to: return false
	if str(source.facility) == "" or str(destination.facility) != "" or destination.kind not in ["grass", "sand"]:
		message("选择有设施的起点，再选择空闲草地或沙地")
		return false
	if not pay({"coins": 5}): return false
	destination.facility = source.facility
	destination.level = source.get("level", 1)
	# Damage follows the building; moving it is not a free repair.
	destination.hp = minf(float(source.get("hp", 100.0)), float(destination.get("hp", 100.0)))
	source.facility = ""
	source.level = 1
	sync()
	message("设施搬迁完成；抓钩发射点按小屋位置更新")
	return true

func can_trim(cell: Vector2i) -> bool:
	var tile := tile_at(cell)
	if tile.is_empty() or cell == Vector2i.ZERO or game.island_tiles.size() <= 1 or str(tile.facility) != "": return false
	var occupied: Dictionary = {}
	for value in game.island_tiles:
		if value.cell != cell: occupied[value.cell] = true
	var seen := {Vector2i.ZERO: true}
	var queue: Array = [Vector2i.ZERO]
	while not queue.is_empty():
		var current: Vector2i = queue.pop_front()
		for direction in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var neighbor: Vector2i = current + direction
			if occupied.has(neighbor) and not seen.has(neighbor):
				seen[neighbor] = true
				queue.append(neighbor)
	return seen.size() == occupied.size()

func trim(cell: Vector2i) -> bool:
	if int(tech.terraform) == 0:
		message("先研究岛屿剪裁科技")
		return false
	if game.hook_state != game.HOOK_READY:
		message("抓钩作业期间不能剪裁")
		return false
	if not can_trim(cell):
		message("不能抛弃核心、设施地块或会切断主岛的地块；请先搬走设施")
		return false
	var index := plot_at(cell)
	if index >= 0: game.plots.remove_at(index)
	game.island_tiles.erase(tile_at(cell))
	sync()
	message("地块已抛弃；地形和未收获作物不返还")
	return true

func repair_cost(cell: Vector2i) -> Dictionary:
	var tile := tile_at(cell)
	var lost := 100.0 - float(tile.get("hp", 100.0))
	return {"coins": ceili(lost / 5.0), "wood": ceili(lost / 25.0), "stone": ceili(lost / 35.0)}

func repair(cell: Vector2i) -> bool:
	var tile := tile_at(cell)
	if tile.is_empty() or float(tile.get("hp", 100.0)) >= 100.0:
		message("这格无需修缮")
		return false
	if not pay(repair_cost(cell)): return false
	tile.hp = 100.0
	sync()
	message("修缮完成，耐久恢复 100；设施与农田效率恢复")
	return true

func damage_at(world_position: Vector2, speed: float) -> void:
	var nearest: Dictionary = {}
	var distance := INF
	for tile in game.island_tiles:
		var d: float = (game.island_pos + Vector2(tile.cell) * Tiles.CELL_SIZE).distance_squared_to(world_position)
		if d < distance:
			distance = d
			nearest = tile
	if nearest.is_empty(): return
	var damage := clampf(speed * 0.55, 12.0, 65.0)
	nearest.hp = maxf(0.0, float(nearest.get("hp", 100.0)) - damage)
	message("碰撞受损：地块耐久 %d/100；B → 修缮，费用 %s" % [nearest.hp, Rules.cost_text(repair_cost(nearest.cell))])
	game.screen_shake_time = 0.3
	game.screen_shake_strength = 5.0

func survey(target: Dictionary) -> bool:
	if not target.has("island") or not bool(target.active): return false
	var terrain: Dictionary = target.island
	if game._hazard_clearance(terrain) > game.hook_max_distance + 200.0:
		message("靠近岛屿后才能勘探（抓钩射程 +200 px）")
		return false
	if bool(terrain.get("surveyed", false)):
		message(str(terrain.report))
		return true
	if not pay({"coins": 4 if int(tech.development) >= 3 else 8, "food": 1}): return false
	var total: Dictionary = {}
	for tile in terrain.tiles:
		for key in Rules.YIELDS.get(tile.kind, {}):
			total[key] = int(total.get(key, 0)) + int(Rules.YIELDS[tile.kind][key]) * (2 if int(tech.development) >= 3 else 1)
	var value := 0
	for key in total: value += int(total[key]) * int({"coins": 1, "wood": 3, "stone": 2, "ore": 5, "magma": 10, "food": 6, "seeds": 4}[key])
	terrain.surveyed = true
	terrain.report = "%s · 资源 %s · 参考估值 %d 金（非即时销售；需接入后采集）" % [terrain.name, Rules.cost_text(total), value]
	message(terrain.report)
	return true

func batch(harvest: bool) -> int:
	var count := 0
	for index in range(game.plots.size()):
		var plot: Dictionary = game.plots[index]
		if (harvest and int(plot.state) == 2) or (not harvest and int(plot.state) == 0 and game.seeds > 0):
			if not harvest: plot.crop_type = selected_crop
			game._interact_with_plot(game._plot_rect(index).get_center())
			count += 1
	message("批量%s %d 格%s" % ["收获" if harvest else "播种", count, "" if harvest else (" · 水稻" if selected_crop == 0 else " · 番茄")])
	return count

func update() -> void:
	if int(tech.automatic) > 0 and auto_fuel and game.energy < game.energy_capacity * 0.30:
		game._refuel_from_crops(true)
	if resource_label != null:
		resource_label.text = "木 %d  石 %d  矿 %d  岩浆 %d  粮 %d  |  B 开发  T 科技  H 收获  J 播种" % [materials.wood, materials.stone, materials.ore, materials.magma, game.rice_stock]
	if status_label != null: status_label.text = operation_message

func select_action(value: String) -> void:
	action = value
	move_from = NONE
	trim_pending = NONE
	modal.hide()
	game.selected_tool = 2
	game._update_tool_styles()
	message("%s：点击岛上地块；右键/Esc 取消。" % {"gather": "采集", "farm": "开垦", "power": "建引擎", "water": "建储能", "upgrade": "升级设施", "move": "搬迁（先起点再终点）", "repair": "修缮", "trim": "剪裁（两次点击确认）", "survey": "勘探（点击野外岛屿）"}[action])

func click(world_position: Vector2) -> void:
	if action == "survey":
		for target in game.targets:
			if not target.has("island") or not bool(target.active): continue
			var terrain: Dictionary = target.island
			var center: Vector2 = Tiles.bounds(terrain.tiles).get_center()
			for tile in terrain.tiles:
				if Tiles.cell_rect(terrain.pos - center, tile.cell).has_point(world_position):
					survey(target)
					return
		message("请点击附近野外岛屿")
		return
	var cell := cell_at(world_position)
	if tile_at(cell).is_empty():
		message("请点击主岛的地块")
		return
	match action:
		"gather": gather(cell)
		"farm", "power", "water": build(cell, action)
		"upgrade": upgrade(cell)
		"repair": repair(cell)
		"move":
			if move_from == NONE:
				if str(tile_at(cell).facility) == "":
					message("起点必须是设施所在格")
					return
				move_from = cell
				message("已选中设施，再点空闲草地/沙地搬迁；费用 5 金")
			elif relocate(move_from, cell): move_from = NONE
		"trim":
			if trim_pending == cell:
				trim(cell)
				trim_pending = NONE
			else:
				trim_pending = cell
				message("再次点击同一格确认抛弃；地形和作物不返还。右键取消")

func create_ui(root: Control) -> void:
	var bar: PanelContainer = game._make_panel(Vector2(18, 86), Vector2(1116, 28), Color("#eff1d4"))
	root.add_child(bar)
	resource_label = Label.new()
	resource_label.add_theme_font_size_override("font_size", 13)
	resource_label.add_theme_color_override("font_color", game.INK)
	bar.add_child(resource_label)
	var action_row := HBoxContainer.new()
	action_row.position = Vector2(18, 244)
	root.add_child(action_row)
	for entry in [["B 开发", false], ["T 科技", true]]:
		var button: Button = game._make_small_button(entry[0])
		button.pressed.connect(toggle.bind(entry[1]))
		action_row.add_child(button)
	status_label = Label.new()
	status_label.position = Vector2(18, 493)
	status_label.size = Vector2(1116, 51)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.add_theme_font_size_override("font_size", 14)
	status_label.add_theme_color_override("font_color", game.INK)
	status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(status_label)
	modal = game._make_panel(Vector2(222, 116), Vector2(708, 420), Color("#fff1ce"))
	root.add_child(modal)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	modal.add_child(game._with_margin(scroll, 14))
	content = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 7)
	scroll.add_child(content)
	modal.hide()
	update()

func toggle(show_tech: bool) -> void:
	if modal.visible and tech_open == show_tech:
		modal.hide()
		return
	tech_open = show_tech
	game.sky_map_open = false
	render_menu()
	modal.show()

func text_row(text: String, size := 14) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", game.INK)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 640
	content.add_child(label)

func button_row(text: String, callback: Callable, disabled := false) -> void:
	var button: Button = game._make_small_button(text)
	button.disabled = disabled
	button.pressed.connect(callback)
	content.add_child(button)

func render_menu() -> void:
	for child in content.get_children():
		content.remove_child(child)
		child.queue_free()
	text_row("科技树 · 研究后即可建造 / 升级" if tech_open else "岛屿开发 · 选择操作，再点击地块", 21)
	text_row("面板打开时世界暂停；Esc 关闭。金币 %d / 粮食 %d / 木 %d / 石 %d / 矿 %d / 岩浆 %d" % [game.coins, game.rice_stock, materials.wood, materials.stone, materials.ore, materials.magma], 13)
	if tech_open:
		for key in Rules.TECH_ORDER:
			var rule: Dictionary = Rules.TECH[key]
			var maximum := int(tech[key]) >= int(rule.max)
			var blocked := false
			var needs: PackedStringArray = []
			for required in rule.needs:
				needs.append("%s %d" % [Rules.TECH[required].name, rule.needs[required]])
				if int(tech[required]) < int(rule.needs[required]): blocked = true
			text_row("%s %d/%d · %s%s" % [rule.name, tech[key], rule.max, rule.effect, "\n前置：" + " + ".join(needs) if not needs.is_empty() else ""], 13)
			button_row("已满级" if maximum else "研究 · " + Rules.cost_text(research_cost(key)), func() -> void:
				research(key)
				render_menu(), maximum or blocked or not can_pay(research_cost(key)))
	else:
		for entry in [["gather", "采集地形 · 林木/草地/沙地免费；矿石与岩浆需开拓科技"], ["farm", "开垦农田 · " + Rules.cost_text(Rules.BUILD_COSTS.farm)], ["power", "建引擎室（1 格）· " + Rules.cost_text(Rules.BUILD_COSTS.power)], ["water", "建储能室（1 格）· " + Rules.cost_text(Rules.BUILD_COSTS.water)], ["upgrade", "升级设施 · 当前等级 ×（20 金 +2 木 +2 矿）"], ["move", "搬迁设施 · 5 金；先点设施，再点空地"], ["repair", "修缮 · 按损坏程度消耗金币、木材、石材"], ["trim", "剪裁地块 · 科技解锁；两次点击确认抛弃"], ["survey", "勘探估值 · 8 金 +1 粮；开拓 III 降为 4 金"]]:
			button_row(entry[1], select_action.bind(entry[0]))
		button_row("当前批量作物：%s · 点击切换" % ("水稻" if selected_crop == 0 else "番茄"), func() -> void:
			selected_crop = 1 - selected_crop
			render_menu())
		button_row("H 批量收获", func() -> void: batch(true))
		button_row("J 批量播种", func() -> void: batch(false))
		button_row("自动填充：%s" % ("开" if auto_fuel else "关"), func() -> void:
			auto_fuel = not auto_fuel
			render_menu(), int(tech.automatic) == 0)
		button_row("岩浆晶转化 · 1 份 → 60 E", func() -> void:
			if materials.magma > 0 and game.energy < game.energy_capacity:
				materials.magma -= 1
				game._add_energy(60.0, "岩浆晶转化")
				render_menu(), int(tech.geothermal) == 0 or materials.magma == 0)
	button_row("关闭 · Esc", modal.hide)

func tile_description(cell: Vector2i) -> String:
	var tile := tile_at(cell)
	if tile.is_empty(): return ""
	var facility := str(tile.facility)
	var text := "%s%s · 耐久 %d/100\n" % [Rules.TERRAIN_NAMES[tile.kind], " / %s Lv.%d" % [Rules.FACILITY_NAMES[facility], tile.get("level", 1)] if facility != "" else "", tile.get("hp", 100.0)]
	if float(tile.get("hp", 100.0)) < 100.0: text += "修缮：" + Rules.cost_text(repair_cost(cell)) + "\n"
	if facility == "power": text += "引擎叠加推力，升级增加单格动力；受损会降低输出。\n"
	elif facility == "water": text += "每级提供 75 E 储量，再叠加储能科技。\n"
	elif facility == "grapple": text += "发射点随建筑位置移动；科技和建筑升级扩大射程。\n"
	elif tile.kind != "farm": text += "资源已采尽，可开发。\n" if bool(tile.get("depleted", false)) else "可采集：" + Rules.cost_text(Rules.YIELDS[tile.kind]) + "\n"
	return text + "B 开发 / T 科技"
