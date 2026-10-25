extends RefCounted

const Rules = preload("res://scripts/development_rules.gd")
const INK := Color("#354957")
const TEAL := Color("#346b65")
const GOLD := Color("#e7b65c")
var game
var mode := "buy"
var badge: Button
var status_label: Label
var wallet_label: Label
var offers: Array = []
var products: Array = []

func _init(owner_node) -> void:
	game = owner_node

func create_badge(root: Control) -> void:
	badge = Button.new()
	badge.name = "MerchantArrivalPrompt"
	badge.position = Vector2(392, 554)
	badge.size = Vector2(368, 68)
	badge.z_index = 5
	badge.icon = game._hud_icon("coins")
	badge.expand_icon = true
	badge.add_theme_constant_override("icon_max_width", 32)
	badge.add_theme_font_size_override("font_size", 18)
	badge.add_theme_color_override("font_color", Color("#3c3523"))
	badge.add_theme_color_override("font_hover_color", Color.WHITE)
	var arrival_style: StyleBoxFlat = game._button_style(Color("#ffe39a"), Color("#b36d28"))
	arrival_style.set_border_width_all(3)
	arrival_style.shadow_color = Color(0.12, 0.19, 0.19, 0.4)
	arrival_style.shadow_size = 8
	badge.add_theme_stylebox_override("normal", arrival_style)
	badge.add_theme_stylebox_override("hover", game._button_style(TEAL, GOLD))
	badge.pressed.connect(game.development.open_trade.bind("流浪商人"))
	badge.tooltip_text = "商人已到访，点击购买物资或出售库存"
	root.add_child(badge)

func _label(parent: Control, text: String, font_size := 14, color := INK) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label

func _row(parent: Control, separation := 8) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", separation)
	parent.add_child(row)
	return row

func select_mode(value: String) -> void:
	if value not in ["buy", "sell"] or not game.development.can_trade(): return
	mode = value
	game.development.render_menu()

func _resize() -> void:
	if not is_instance_valid(game) or not game.development.trade_open: return
	var panel_size := Vector2(680, 350 if mode == "buy" else 282)
	game.development.modal.position = (game.VIEW_SIZE - panel_size) * 0.5
	game.development.modal.size = panel_size

func _product(parent: Control, key: String, title: String, icons: Array, inventory: String, price: int, unit: String, wide := false) -> HBoxContainer:
	var panel := PanelContainer.new()
	panel.name = "Product_" + key
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style: StyleBoxFlat = game._button_style(Color("#fff8e7"), Color("#c7c6ae"))
	style.content_margin_left = 3
	style.content_margin_right = 3
	style.set_border_width_all(1)
	panel.add_theme_stylebox_override("panel", style)
	parent.add_child(panel)
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 7)
	panel.add_child(game._with_margin(body, 7))
	var item_icons: Array = []
	for icon_key in icons:
		var icon: TextureRect = game._hud_texture(icon_key, 22 if icons.size() > 1 else 28)
		icon.tooltip_text = {"rice": "水稻", "tomato": "番茄"}.get(icon_key, Rules.RESOURCE_NAMES.get(icon_key, icon_key))
		body.add_child(icon)
		item_icons.append(icon)
	var caption := VBoxContainer.new()
	caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	caption.add_theme_constant_override("separation", 0)
	body.add_child(caption)
	var title_row := _row(caption, 5)
	_label(title_row, title, 14)
	var stock_label := _label(title_row, inventory, 10, Color("#71806c"))
	stock_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var price_row := _row(caption, 3)
	price_row.add_child(game._hud_texture("coins", 14))
	var price_label := _label(price_row, "%d 金币 / %s" % [price, unit], 11, Color("#855b2e"))
	var actions := _row(body, 4)
	actions.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if wide and mode == "sell": actions.custom_minimum_size.x = 228
	products.append({"key": key, "icons": item_icons, "price_label": price_label, "stock_label": stock_label, "panel": panel})
	return actions

func _offer(parent: Control, key: String, amount: int, price: int, callback: Callable, stock := "") -> void:
	var buying := mode == "buy"
	var button: Button = game._make_small_button(("买%d%s\n%d金" if buying else "卖%d%s · %d金") % [amount, "包" if key == "bundle" else "份", price])
	button.name = ("Buy_" if buying else "Sell_") + key + "_" + str(amount)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.custom_minimum_size = Vector2(54 if buying else 110, 34)
	button.add_theme_font_size_override("font_size", 11)
	button.add_theme_color_override("font_color", INK)
	button.add_theme_color_override("font_disabled_color", Color("#8c9387"))
	button.add_theme_stylebox_override("normal", game._button_style(Color("#dfebd6") if buying else Color("#f1dfb5"), Color("#92ab87") if buying else Color("#c4a06a")))
	button.add_theme_stylebox_override("disabled", game._button_style(Color("#e7e7dd"), Color("#c8cbbd")))
	button.pressed.connect(callback)
	parent.add_child(button)
	offers.append({"key": key, "button": button, "cost": price if buying else 0, "price": price, "stock": stock, "amount": amount if not buying else 0})

func render(content: VBoxContainer) -> void:
	var dev = game.development
	offers.clear()
	products.clear()
	_resize()
	call_deferred("_resize")
	dev.modal.add_theme_stylebox_override("panel", game._button_style(Color("#eef0df"), TEAL))
	var header := _row(content, 12)
	_label(header, dev.trade_source, 21, TEAL).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_label = _label(header, "", 12, TEAL)
	status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var wallet := _row(header, 4)
	wallet.add_child(game._hud_texture("coins", 20))
	wallet_label = _label(wallet, "", 16, Color("#855b2e"))
	wallet_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var close: Button = game._make_small_button("×")
	close.custom_minimum_size = Vector2(30, 28)
	close.tooltip_text = "关闭 · Esc"
	close.pressed.connect(dev.close_menu)
	header.add_child(close)
	var tabs := _row(content, 8)
	for entry in [["buy", "购买物资"], ["sell", "出售库存"]]:
		var tab: Button = game._make_small_button(entry[1])
		tab.name = "Tab_" + entry[0]
		tab.custom_minimum_size = Vector2(126, 28)
		tab.add_theme_font_size_override("font_size", 13)
		tab.add_theme_stylebox_override("normal", game._button_style(TEAL if mode == entry[0] else Color("#e2e7d5"), TEAL))
		tab.add_theme_color_override("font_color", Color("#fff4d8") if mode == entry[0] else INK)
		tab.pressed.connect(select_mode.bind(entry[0]))
		tabs.add_child(tab)
	if mode == "buy": _render_buy(content)
	else: _render_sell(content)
	update()

func _render_buy(content: VBoxContainer) -> void:
	var dev = game.development
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 8)
	content.add_child(grid)
	for key in Rules.MINERAL_BUY_PRICES:
		var price: int = Rules.MINERAL_BUY_PRICES[key]
		var actions := _product(grid, key, Rules.RESOURCE_NAMES[key], [key], "库存%d" % dev.stock(key), price, "份")
		for amount in [1, 5]:
			_offer(actions, key, amount, price * amount, dev.trade_buy_mineral.bind(key, amount))
	for entry in [["rice_seeds", 2, 4], ["tomato_seeds", 2, 8], ["wood", 8, 20]]:
		var key: String = entry[0]
		var amount: int = entry[1]
		var price: int = entry[2]
		var actions := _product(grid, key, Rules.RESOURCE_NAMES[key], [key], "库存%d" % dev.stock(key), price, "%d 份" % amount)
		_offer(actions, key, amount, price, dev.trade_buy.bind(price, {key: amount}, "%s ×%d" % [Rules.RESOURCE_NAMES[key], amount]))
	var bundle := _product(content, "bundle", "旅行补给包", ["rice", "rice_seeds", "tomato_seeds"], "水稻×4 / 稻种×1 / 番茄种×1", 12, "包", true)
	_offer(bundle, "bundle", 1, 12, dev.trade_buy.bind(12, {"food": 4, "rice_seeds": 1, "tomato_seeds": 1}, "旅行补给包"))

func _render_sell(content: VBoxContainer) -> void:
	var dev = game.development
	for crop in [game.CROP_RICE, game.CROP_TOMATO]:
		var key := "rice" if crop == game.CROP_RICE else "tomato"
		var available: int = game.rice_stock if crop == game.CROP_RICE else game.energy_crop_stock
		var actions := _product(content, key, game._crop_name(crop), [key], "库存%d" % available, Rules.CROP_SELL_COINS[crop], "份", true)
		for amount in [1, 10]:
			_offer(actions, key, amount, Rules.CROP_SELL_COINS[crop] * amount, dev.trade_sell_crop.bind(crop, amount), "food" if crop == game.CROP_RICE else "tomato")
	var ore := _product(content, "ore", "矿物", ["ore"], "库存%d" % dev.materials.ore, 35, "3 份", true)
	_offer(ore, "ore", 3, 35, dev.trade_sell_ore, "ore")

func update() -> void:
	var dev = game.development
	var remaining := ceili(maxf(0.0, game.merchant_stay_left))
	if is_instance_valid(badge):
		badge.visible = game.demo_started and game.merchant_available and not dev.trade_open
		var compact: bool = dev.modal != null and dev.modal.visible and not dev.energy_open
		badge.text = ("商店已开张 · %ds · 点击交易  ›" if compact else "商店已开张 · 剩余 %ds\n点击购买 / 出售  ›") % remaining
		badge.add_theme_font_size_override("font_size", 14 if compact else 18)
		badge.add_theme_constant_override("icon_max_width", 20 if compact else 32)
		badge.position = Vector2(392, 610 if compact else 554)
		badge.size = Vector2(368, 32 if compact else 68)
		var pulse := 0.95 + 0.05 * sin(game.animation_time * 4.0)
		badge.modulate = Color(1.0, pulse, pulse, 1.0)
	if not dev.trade_open or not is_instance_valid(status_label): return
	status_label.text = "剩余 %ds" % remaining if dev.trade_source == "流浪商人" else "已对接"
	wallet_label.text = str(game.coins)
	for offer in offers:
		var available := 0
		if offer.stock != "": available = game.energy_crop_stock if offer.stock == "tomato" else dev.stock(offer.stock)
		offer.button.disabled = not dev.can_trade() or game.coins < int(offer.cost) or available < int(offer.amount)
	for product in products:
		if product.key == "bundle": continue
		var available: int = game.energy_crop_stock if product.key == "tomato" else dev.stock("food" if product.key == "rice" else product.key)
		product.stock_label.text = ("库存%d" if mode == "buy" else "库存%d") % available
