extends RefCounted

const Rules = preload("res://scripts/development_rules.gd")
# Short labels stay visible; the same buttons carry full keyboard/mouse hints.
const ACTIONS := [
	["gather", "采集", "wood", "", "采集地形资源；矿石与岩浆需要开拓科技。"],
	["farm", "开垦农田", "rice", "", "在空闲草地或沙地开垦，再选择作物播种。"],
	["tree", "林业种植", "wood", "forestry", "在空闲草地种下树苗，可连续点击多格种植。\n晴朗白天约 %d 秒成熟；成熟后用采集工具收获木材。\n林木保护半径 %d 格内农田，保护效果随成长和健康提升。" % [Rules.TREE_GROW_SECONDS, Rules.FOREST_RADIUS]],
	["power", "引擎室", "energy", "engine", "增加浮岛推力；科技等级决定建造数量上限。"],
	["water", "储能室", "house", "storage", "每级增加 75 E 基础储量，可建多座。"],
	["grapple", "抓钩小屋", "focus", "hook", "提供抓钩发射点；全岛限一座。"],
	["energy", "能源工厂", "energy", "automatic", "消耗所选来源补能；全岛限一座。"],
	["farm_hut", "管理小屋", "house", "agri_automation", "每 6 秒管理半径内农田；初始半径 2 格。\n右键小屋切换作物、暂停或升级。"],
	["harbor", "探索港口", "map", "harbor", "建在浮岛外围，供探索飞船停泊；全岛限一座。"],
	["reinforce", "加固", "shield", "reinforcement", "提高地块耐久；科技每级解锁 3 次，最多 15 次。\n费用随加固次数增加，右键目标地块可查。"],
	["upgrade", "升级", "growth", "", "提升设施等级；费用与上限由设施及科技决定。\n右键目标设施可查看当前费用。"],
	["repair", "修缮", "build", "", "修复地块、设施或林木。农田修复便宜，地基修复昂贵。\n右键目标地块查看实际费用。"],
	["move", "搬迁", "focus", "", "先点设施，再点空闲草地或沙地；消耗 5 金币。"],
	["restore", "整平", "land", "", "将已收获的空农田整平为土地；消耗 2 金币。"],
	["survey", "勘探", "map", "", "点击附近野外浮岛，查看资源与估值。\n消耗 8 金币、1 粮食；开拓 III 后降至 4 金币、1 粮食。"],
	["trim", "剪裁", "land", "terraform", "再次点击同一格确认抛弃；地形与作物不返还。"],
	["recycle", "回收", "stone", "recycling", "再次点击确认回收，按科技返还部分加固投入。"],
]

static func button(dev, parent: Control, key: String, title: String, icon: String, hint: String, callback: Callable) -> Button:
	var item: Button = dev.game._make_small_button(title)
	item.name = "Development_" + key
	item.custom_minimum_size = Vector2(122, 40)
	item.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	item.add_theme_font_size_override("font_size", 13)
	item.icon = dev.game._icon(2) if key == "grapple" else dev.game._hud_icon(icon)
	if key == "gather": item.icon = dev.game.gather_button.icon
	item.expand_icon = true
	item.add_theme_constant_override("icon_max_width", 24)
	item.add_theme_color_override("font_disabled_color", Color("#737563"))
	item.add_theme_stylebox_override("disabled", dev.game._button_style(Color("#e8e6d9"), Color("#bec1ad")))
	item.tooltip_text = hint
	item.pressed.connect(callback)
	parent.add_child(item)
	return item

static func render(dev) -> void:
	dev.modal.position = Vector2(8, 90)
	dev.modal.size = Vector2(426, 510)
	var header := HBoxContainer.new()
	dev.content.add_child(header)
	var title: Label = dev._energy_label("岛屿开发", 21)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close := button(dev, header, "close", "", "focus", "关闭 · Esc", dev.close_menu)
	close.icon = null
	close.text = "×"
	close.custom_minimum_size = Vector2(32, 28)
	close.size_flags_horizontal = Control.SIZE_SHRINK_END
	var stock := GridContainer.new()
	stock.columns = 4
	dev.content.add_child(stock)
	for key in Rules.RESOURCE_NAMES:
		var row := HBoxContainer.new()
		row.custom_minimum_size.x = 94
		row.mouse_filter = Control.MOUSE_FILTER_STOP
		row.tooltip_text = Rules.RESOURCE_NAMES[key]
		stock.add_child(row)
		var mark: TextureRect = dev.game._hud_texture("rice" if key == "food" else key, 20)
		mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(mark)
		var count: Label = dev._energy_label(str(dev.stock(key)), 13)
		count.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(count)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	dev.content.add_child(grid)
	for entry in ACTIONS:
		var key: String = entry[0]
		var required: String = entry[3]
		var reason := ""
		if required != "" and int(dev.tech[required]) == 0:
			reason = "需研究：" + str(Rules.TECH[required].name) + "（T 科技树）"
		elif key == "power" and dev.facility_count(key) >= int(dev.tech.engine): reason = "引擎数量已达上限"
		elif key in ["grapple", "energy", "harbor"] and dev.has_facility(key): reason = "已建造，全岛限一座"
		if key == "recycle" and int(dev.tech.terraform) == 0: reason = "需研究：岛屿剪裁（T 科技树）"
		var cost: Dictionary = Rules.BUILD_COSTS.get(key, Rules.TRIM_COST if key in ["trim", "recycle"] else {})
		if reason == "" and not dev.can_pay(cost): reason = "资源不足"
		var hint: String = entry[1] + "\n" + entry[4]
		if not cost.is_empty(): hint += "\n消耗：" + Rules.cost_text(cost)
		if reason != "": hint += "\n" + reason
		var item := button(dev, grid, key, entry[1], entry[2], hint, dev.select_action.bind(key))
		item.disabled = reason != ""
		if key == "tree" and reason == "":
			item.add_theme_stylebox_override("normal", dev.game._button_style(Color("#dce8bd"), Color("#769250")))
	var links := GridContainer.new()
	links.columns = 3
	links.add_theme_constant_override("h_separation", 6)
	dev.content.add_child(links)
	button(dev, links, "ship", "飞船", "map", "探索飞船与港口管理", dev.game.explorer.open_menu)
	button(dev, links, "layout", "布局", "land", "整岛剪裁与布局预设；需整岛规划科技，应用消耗资源。", dev.layout.open)
	button(dev, links, "fuel", "能源", "energy", dev.fuel_status() + "\n点击选择能源来源", dev.toggle_energy)
	if dev.game.merchant_available:
		button(dev, links, "trade", "商人", "coins", "流浪商人已到访，点击交易", dev.open_trade.bind("流浪商人"))
