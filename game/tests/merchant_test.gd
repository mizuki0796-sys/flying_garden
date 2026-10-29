extends SceneTree

const Tiles = preload("res://scripts/island_tiles.gd")
const Rules = preload("res://scripts/development_rules.gd")
var failures: Array[String] = []
var checks := 0

func _init() -> void:
	call_deferred("_run")

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition: failures.append(label)

func _run() -> void:
	var game := (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await process_frame
	game.set_physics_process(false)
	game.set_process(false)
	game._start_demo()
	var dev = game.development
	var initial_ore: int = dev.materials.ore
	check(dev.research("engine") and dev.build(Vector2i(0, -2), "power"), "Starting stock funds the first engine without mining")
	check(initial_ore - dev.materials.ore == 2, "First engine including its research consumes only two ore")
	game.coins = 10000
	dev.materials.wood = 1000
	check(dev.research("hook") and dev.build(Vector2i(2, 0), "grapple"), "Starting mineral stock also funds the first grapple")
	check(dev.materials.ore == initial_ore - 4, "Propulsion and grapple leave minerals for the next branch")
	# Quotes and actual deductions must agree at every upgrade, not just in UI.
	dev.tech.engine = 0
	dev.materials.ore = 100
	for level in range(3):
		var expected := {"coins": [25, 75, 225][level], "wood": [3, 9, 27][level], "ore": [1, 3, 9][level]}
		check(dev.research_cost("engine") == expected, "Engine upgrade %d has exponential resource requirements" % (level + 1))
		var before := {"coins": game.coins, "wood": dev.materials.wood, "ore": dev.materials.ore}
		check(dev.research("engine"), "Affordable engine upgrade succeeds")
		for key in expected: check(before[key] - dev.stock(key) == expected[key], "Research consumes the quoted " + key)
	var coins_before: int = game.coins
	check(not dev.research("engine") and game.coins == coins_before, "Maxed research cannot charge again")
	dev.tech.storage = 2
	dev.materials.stone = 8
	check(not dev.research("storage") and dev.tech.storage == 2 and dev.materials.stone == 8 and game.coins == coins_before, "Third-tier storage rejects insufficient minerals atomically")
	dev.tech.storage = 0
	dev.materials.stone = 100
	dev.tech.terraform = 1
	game.rice_stock = 2
	var restored := Vector2i(0, 2)
	check(not dev.tile_at(restored).has("reserved"), "No island plot is reserved for a merchant")
	check(dev.gather(restored) and dev.build(restored, "farm"), "Former trading plot can be gathered and tilled normally")
	check(dev.restore_farmland(restored) and dev.can_trim(restored), "Former trading plot can be restored and trimmed")
	check(not dev.open_trade("流浪商人") and not dev.market_ui.badge.visible, "Absent merchant has no entry or idle prompt")
	game.merchant_arrival_left = 0.01
	game._update_merchant(0.02)
	check(game.merchant_available and dev.market_ui.badge.visible and not dev.modal.visible, "Arrival only shows the bottom prompt without interrupting gameplay")
	dev.market_ui.badge.pressed.emit()
	check(dev.trade_open and dev.modal.visible and not dev.market_ui.badge.visible, "Clicking the prompt opens the purchasing page")
	game.rice_stock = 20
	game.energy_crop_stock = 20
	check(dev.market_ui.mode == "buy" and dev.market_ui.products.size() == 7, "All seven purchase products are shown")
	_check_product_icons(dev.market_ui)
	for key in ["stone", "ore", "magma"]:
		for amount in [1, 5]:
			coins_before = game.coins
			var stock_before: int = dev.stock(key)
			check(dev.trade_buy_mineral(key, amount), "Merchant sells mineral: %s x%d" % [key, amount])
			check(game.coins == coins_before - Rules.MINERAL_BUY_PRICES[key] * amount and dev.stock(key) == stock_before + amount, "Purchase charges the advertised mineral price")
	game.coins = 1000
	for entry in [["rice_seeds", 2, 4], ["tomato_seeds", 2, 8], ["wood", 8, 20]]:
		var stock_before: int = dev.stock(entry[0])
		coins_before = game.coins
		_press_offer(dev.market_ui, "Buy_%s_%d" % [entry[0], entry[1]])
		check(dev.stock(entry[0]) == stock_before + entry[1] and game.coins == coins_before - entry[2], "Supply card buys exactly its displayed item and quantity")
	var rice_before: int = game.rice_stock
	var seed_before: int = game.rice_seeds
	var tomato_seed_before: int = game.tomato_seeds
	_press_offer(dev.market_ui, "Buy_bundle_1")
	check(game.rice_stock == rice_before + 4 and game.rice_seeds == seed_before + 1 and game.tomato_seeds == tomato_seed_before + 1, "Bundle delivers each of its three illustrated contents")
	game.coins = 34
	var materials: Dictionary = dev.materials.duplicate()
	dev.market_ui.update()
	check(not dev.trade_buy_mineral("ore") and game.coins == 34 and dev.materials == materials, "Insufficient coins cannot buy ore")
	for offer in dev.market_ui.offers:
		if offer.cost >= 35: check(offer.button.disabled, "Unaffordable purchase button is disabled")
	game.coins = 1000
	dev.render_menu()
	var ore_before: int = dev.materials.ore
	_press_offer(dev.market_ui, "Buy_ore_5")
	check(game.coins == 825 and dev.materials.ore == ore_before + 5, "Five-ore purchase button matches its price and quantity")
	dev.market_ui.select_mode("sell")
	check(dev.market_ui.products.size() == 3, "Sales show rice, tomatoes and ore as individual products")
	_check_product_icons(dev.market_ui)
	for entry in [["rice", 1, 1], ["rice", 10, 10], ["tomato", 1, 2], ["tomato", 10, 20], ["ore", 3, 35]]:
		var key: String = entry[0]
		var stock_before: int = game.energy_crop_stock if key == "tomato" else dev.stock("food" if key == "rice" else key)
		coins_before = game.coins
		_press_offer(dev.market_ui, "Sell_%s_%d" % [key, entry[1]])
		var after: int = game.energy_crop_stock if key == "tomato" else dev.stock("food" if key == "rice" else key)
		check(after == stock_before - entry[1] and game.coins == coins_before + entry[2], "Sale button consumes displayed stock and pays the displayed total")
		check(dev.market_ui.mode == "sell", "Selling keeps the sales page selected")
	game.energy_crop_stock = 0
	game.coins = 0
	dev.market_ui.update()
	for offer in dev.market_ui.offers:
		if offer.key == "tomato": check(offer.button.disabled, "Empty inventory disables sales")
		if offer.key == "ore": check(not offer.button.disabled, "Selling stocked ore never requires coins")
	coins_before = game.coins
	check(not dev.trade_sell_crop(game.CROP_TOMATO) and game.coins == coins_before, "Empty stock cannot be sold")
	dev.close_menu()
	dev.update()
	check(dev.market_ui.badge.visible and not dev.trade_buy_mineral("ore"), "Closing trading restores the prompt and rejects stale trades")
	dev.open_trade("流浪商人")
	var stale_buy: Callable = dev.trade_buy_mineral.bind("ore", 1)
	materials = dev.materials.duplicate()
	game.merchant_stay_left = 0.01
	game._physics_process(0.02)
	check(not game.merchant_available and not dev.trade_open and not dev.modal.visible and not dev.market_ui.badge.visible, "Departure removes both prompt and trading panel")
	check(not stale_buy.call() and not dev.trade_sell_ore() and not dev.trade_sell_crop(game.CROP_RICE), "Departed merchant rejects all stale transactions")
	check(game.coins == coins_before and dev.materials == materials, "Rejected transactions preserve inventory and money")
	dev.tech.docking = 1
	game.coins = 1000
	check(dev.open_trade("漂流商店岛") and dev.trade_buy_mineral("ore"), "Docked shop island retains buying")
	game._update_merchant(210.1)
	game._update_merchant(75.1)
	check(dev.trade_open and dev.trade_source == "漂流商店岛", "Wandering merchant departure does not close a shop-island trade")
	dev.close_menu()
	game._update_merchant(210.1)
	check(game.merchant_available and dev.market_ui.badge.visible, "Next visit shows the bottom prompt again")
	dev.open_trade("流浪商人")
	dev.toggle(false)
	check(not dev.trade_open and dev.modal.visible, "Development menu replaces trading without keeping an active session")
	await process_frame
	check(dev.modal.size == Vector2(380, 510) and dev.modal.position.x == 8, "Deferred market layout cannot resize the left development drawer after switching")
	dev.close_menu()
	if DisplayServer.get_name() != "headless": await _capture(game)
	game.queue_free()
	await process_frame
	for failure in failures: push_error(failure)
	print("MERCHANT TEST: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _check_product_icons(ui) -> void:
	for product in ui.products:
		check(not product.icons.is_empty() and "金币 /" in product.price_label.text, "Each product has its own item art and explicit price unit")
		for icon in product.icons:
			check(icon.texture != null, "Each illustrated item has a loaded texture")

func _press_offer(ui, name_value: String) -> void:
	for offer in ui.offers:
		if str(offer.button.name) == name_value:
			check(not offer.button.disabled, "Requested offer is enabled: " + name_value)
			offer.button.pressed.emit()
			return
	check(false, "Missing offer: " + name_value)

func _capture(game: Node2D) -> void:
	game.camera_zoom = 1.05
	game.camera_world = game.island_pos + Vector2(0, 12)
	game.targets = []
	game.hazards = []
	game.zones = []
	game.current_weather = -1
	game.weather_tint = 0.0
	game.selected_tool = game.TOOL_HOOK
	game.context_panel.hide()
	game.notice_label.text = ""
	game.island_tiles = Tiles.initial_tiles()
	game.plots = []
	for y in range(-1, 2):
		for x in range(-1, 2):
			game.plots.append({"cell": Vector2i(x, y), "state": 2 if x == 1 else 1, "progress": 1.0 if x == 1 else 0.55, "crop_type": posmod(x + y, 2)})
	game.development.materials = {"wood": 24, "stone": 18, "ore": 4, "magma": 1}
	game.rice_stock = 15
	game.energy_crop_stock = 8
	game.rice_seeds = 3
	game.tomato_seeds = 2
	game.coins = 286
	game.development.sync()
	game.merchant_available = false
	game.merchant_arrival_left = 0.1
	game._update_merchant(0.2)
	await _save_frame(game, "merchant-arrival-preview.png")
	game.development.market_ui.badge.pressed.emit()
	await _save_frame(game, "merchant-buy-preview.png")
	_check_layout(game)
	game.development.market_ui.select_mode("sell")
	await _save_frame(game, "merchant-sell-preview.png")
	_check_layout(game)
	game._update_merchant(75.1)
	game.notice_label.text = ""
	await _save_frame(game, "merchant-departed-preview.png")

func _check_layout(game: Node2D) -> void:
	var modal: Rect2 = game.development.modal.get_global_rect()
	check(modal.end.x <= 1152 and modal.end.y <= 648, "Market fits the viewport")
	check(modal.size.x <= 680 and modal.size.y <= 350, "Trading stays in a compact window")
	for product in game.development.market_ui.products:
		check(modal.encloses(product.panel.get_global_rect()), "Product card fits inside the market")
	for offer in game.development.market_ui.offers:
		check(modal.encloses(offer.button.get_global_rect()), "Action button fits inside the market")

func _save_frame(game: Node2D, filename: String) -> void:
	game._update_hud()
	game.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	var path := ProjectSettings.globalize_path("res://../artifacts/game/" + filename)
	check(root.get_texture().get_image().save_png(path) == OK, "Saved preview " + filename)
