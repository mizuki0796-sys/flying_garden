extends RefCounted

const Rules = preload("res://scripts/development_rules.gd")
const Tiles = preload("res://scripts/island_tiles.gd")
const CAPACITY := 24
const BATTERY := 500.0
var game
var built := false
var state := "docked"
var charge := 0.0
var position := Vector2.ZERO
var cargo: Dictionary = {}
var target: Dictionary = {}
var mining_left := 3.0
var status_label: Label

func _init(owner_node) -> void:
	game = owner_node

func harbor() -> Dictionary:
	for tile in game.island_tiles:
		if tile.facility == "harbor": return tile
	return {}

func dock_position() -> Vector2:
	var tile := harbor()
	return game.island_pos + Vector2(tile.get("cell", Vector2i.ZERO)) * Tiles.CELL_SIZE + Vector2(0, -32)

func load_weight() -> int:
	var total := 0
	for value in cargo.values(): total += int(value)
	return total

func speed() -> float:
	return 150.0 / (1.0 + load_weight() / 12.0)

func construct() -> bool:
	if built or int(game.development.tech.exploration) == 0 or harbor().is_empty(): return false
	if Rules.tile_health(harbor()) < 1.0: game.development.message("请先修缮港口"); return false
	if not game.development.pay(Rules.SHIP_BUILD_COST): return false
	built = true
	position = dock_position()
	game.development.message("探索飞船已建成，正在从浮岛吸收能源")
	return true

func deposits(terrain: Dictionary) -> Array:
	var result: Array = []
	if not bool(terrain.get("active", false)) or bool(terrain.get("tethered", false)) or bool(terrain.get("shop", false)): return result
	for tile in terrain.get("tiles", []):
		if tile.kind in ["rock", "gold", "lava"] and not bool(tile.get("depleted", false)):
			result.append(tile)
	return result

func launch_reason() -> String:
	if not built: return "尚未建造飞船"
	if state != "docked": return "飞船正在执行任务"
	if harbor().is_empty() or Rules.tile_health(harbor()) < 1.0: return "港口缺失或需要修缮"
	if charge < BATTERY: return "等待充能至 500 E"
	return ""

func launch() -> bool:
	var reason := launch_reason()
	if reason != "": game.development.message(reason); return false
	target = {}
	var nearest := minf(2000.0, game.development.radar_range())
	for terrain in game.hazards:
		var distance: float = position.distance_to(terrain.pos)
		if distance < nearest and not deposits(terrain).is_empty():
			target = terrain
			nearest = distance
	if target.is_empty(): game.development.message("雷达内 2000 px 范围没有可采矿岛屿；移动空岛后再试"); return false
	state = "outbound"
	game.development.message("探索飞船启航：" + str(target.name))
	return true

func recall() -> void:
	if built and state != "docked": state = "returning"

func update(delta: float) -> void:
	if not built: return
	if state == "docked":
		position = dock_position()
		var port := harbor()
		if not port.is_empty() and Rules.tile_health(port) >= 1.0:
			for key in cargo: game.development.add_stock(key, int(cargo[key]))
			cargo.clear()
			var amount := minf(minf(25.0 * delta, BATTERY - charge), game.energy)
			if amount > 0.0:
				game.energy -= amount
				charge += amount
		return
	# Preserve enough energy to bring the growing payload home. A moving home can
	# outrun this reserve; an empty battery then permits only slow emergency drift.
	var return_reserve := position.distance_to(dock_position()) / speed() * 2.0 + 20.0
	if charge <= return_reserve or target.is_empty() or deposits(target).is_empty(): state = "returning"
	if state in ["outbound", "returning"]:
		var destination: Vector2 = target.pos if state == "outbound" else dock_position()
		var distance := position.distance_to(destination)
		var travel := minf(distance, speed() * delta * (1.0 if charge > 0.0 else 0.15))
		position = position.move_toward(destination, travel)
		charge = maxf(0.0, charge - travel / speed() * 2.0)
		if position.distance_to(destination) <= 4.0:
			if state == "outbound": state = "mining"; mining_left = 3.0
			elif not harbor().is_empty(): state = "docked"; target = {}
	elif state == "mining":
		mining_left -= delta
		if mining_left <= 0.0:
			mining_left += 3.0
			mine_once()

func mine_once() -> bool:
	var available := deposits(target)
	if available.is_empty() or charge < 12.0: state = "returning"; return false
	var tile: Dictionary = available[0]
	var goods: Dictionary = Rules.YIELDS[tile.kind]
	var weight := 0
	for key in goods:
		if key in ["stone", "ore", "magma"]: weight += int(goods[key])
	if load_weight() + weight > CAPACITY: state = "returning"; return false
	for key in goods:
		if key in ["stone", "ore", "magma"]: cargo[key] = int(cargo.get(key, 0)) + int(goods[key])
	charge -= 12.0
	tile.kind = "grass"
	tile.depleted = true
	if load_weight() >= CAPACITY or deposits(target).is_empty(): state = "returning"
	return true

func status_text() -> String:
	if not built: return "唯一探索飞船 · 尚未建造"
	var names := {"docked": "停泊 / 自动充能", "outbound": "前往矿岛", "mining": "正在采矿", "returning": "返航"}
	return "%s\n能源 %d / 500 E　货舱 %d / 24　速度 %.0f px/s\n%s" % [names[state], charge, load_weight(), speed(), "空货舱" if cargo.is_empty() else Rules.cost_text(cargo)]

func open_menu() -> void:
	var dev = game.development
	dev.close_menu()
	dev.tile_menu.close()
	game.sky_map_open = false
	dev.explorer_open = true
	dev.render_menu()
	dev.modal.show()

func render(content: VBoxContainer) -> void:
	var dev = game.development
	dev.modal.position = Vector2(8, 90)
	dev.modal.size = Vector2(1040, 510)
	dev.modal.add_theme_stylebox_override("panel", dev.default_modal_style)
	dev.text_row("探索港口 · 飞船管理", 24)
	status_label = Label.new()
	status_label.text = status_text()
	status_label.add_theme_color_override("font_color", game.INK)
	status_label.add_theme_font_size_override("font_size", 18)
	content.add_child(status_label)
	dev.text_row("停泊时每秒吸收浮岛 25 E；满能后可出航，自动寻找雷达内最近矿岛。\n载重越高，飞行越慢；货满或能源不足时自动返航，停泊后卸货。", 15)
	dev.button_row("飞船已建造（唯一）" if built else "建造飞船 · " + Rules.cost_text(Rules.SHIP_BUILD_COST), func() -> void: construct(); dev.render_menu(), built or int(dev.tech.exploration) == 0 or harbor().is_empty() or not dev.can_pay(Rules.SHIP_BUILD_COST))
	dev.button_row("派遣采矿" if launch_reason() == "" else "派遣采矿 · " + launch_reason(), func() -> void: launch(); dev.close_menu(), launch_reason() != "")
	dev.button_row("召回飞船", func() -> void: recall(); dev.close_menu(), not built or state == "docked")
	dev.button_row("关闭并继续运行 · Esc", dev.close_menu)

func snapshot() -> Dictionary:
	return {"built": built, "state": state, "charge": charge, "position": position, "cargo": cargo.duplicate(), "mining_left": mining_left, "target_key": target.get("world_key", Vector2i.ZERO), "target_index": target.get("world_index", -1)}

func restore(data: Dictionary) -> void:
	built = data.built
	state = data.state
	charge = data.charge
	position = data.position
	cargo = data.cargo.duplicate()
	mining_left = data.mining_left
	target = {}
	var index := int(data.target_index)
	if index >= 0 and game.world_sectors.has(data.target_key):
		var terrain: Array = game.world_sectors[data.target_key].hazards
		if index < terrain.size(): target = terrain[index]
	if built and state != "docked" and target.is_empty(): state = "returning"

func draw_ship() -> void:
	if not built: return
	var p := position
	# Deliberately simple placeholder silhouette requested for this version.
	game.draw_circle(p, 28.0, Color(0.1, 0.22, 0.3, 0.16))
	game.draw_colored_polygon(PackedVector2Array([p + Vector2(-26, 0), p + Vector2(0, -12), p + Vector2(28, 0), p + Vector2(0, 15)]), Color("#e9be72"))
	game.draw_rect(Rect2(p + Vector2(-10, -8), Vector2(20, 13)), Color("#598fa1"))
	game.draw_line(p + Vector2(-20, -13), p + Vector2(20, -13), Color("#d5ede4"), 3.0)
	game.draw_circle(p + Vector2(-18, 4), 3.0, Color("#bfff9e"))
