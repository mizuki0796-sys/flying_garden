extends RefCounted

const Rules = preload("res://scripts/development_rules.gd")
const Tiles = preload("res://scripts/island_tiles.gd")
const BATTERY := 500.0
const MAX_HP := 100.0
const SAFE_CONTACT_SPEED := 35.0
const HULL := Vector2(80, 64)
const DOCK_SPEED := 20.0
const Physics = preload("res://scripts/island_physics.gd")
var game
var home_cell := Vector2i(999999, 999999)
var home_direction := Vector2i.ZERO
var built := false
var state := "docked"
var charge := 0.0
var position := Vector2.ZERO
var cargo: Dictionary = {}
var target: Dictionary = {}
var mining_left := 3.0
var status_label: Label
var visual_viewport: SubViewport
var visual: Sprite2D
var exhaust: Array[Dictionary] = []
var exhaust_elapsed := 0.0
var towed := false
var rescue_quote := -1
var hp := MAX_HP
var velocity := Vector2.ZERO
var dock_offset := Vector2.ZERO
var dock_button: Button
var overflow_panel: PanelContainer
var overflow_label: Label
var overflow_confirm: Button
var overflow_return: Button

func _init(owner_node) -> void:
	game = owner_node

func harbor() -> Dictionary:
	var selected: Dictionary = game.development.tile_at(home_cell)
	if selected.get("facility", "") == "harbor": return selected
	for tile in game.island_tiles:
		if tile.facility == "harbor": return tile
	return {}

func berths(cell: Vector2i) -> Dictionary:
	var result: Dictionary = {}
	for direction in [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]:
		var point: Vector2 = game.island_pos + Vector2(cell) * Tiles.CELL_SIZE + Vector2(direction) * (84.0 if direction.x != 0 else 68.0)
		var hull := Rect2(point - HULL * 0.5, HULL)
		var blocked := false
		for tile in game.island_tiles:
			if hull.intersects(Tiles.cell_rect(game.island_pos, tile.cell)): blocked = true; break
		if blocked: continue
		for terrain in game.hazards:
			if not terrain.get("active", false) or terrain.get("tiles", []).is_empty(): continue
			var origin := terrain_origin(terrain)
			for tile in terrain.tiles:
				if hull.intersects(Tiles.cell_rect(origin, tile.cell)): blocked = true; break
			if blocked: break
		if not blocked: result[direction] = point
	return result

func dock_position() -> Vector2:
	var tile := harbor()
	if tile.is_empty(): return position
	var available := berths(tile.cell)
	if available.is_empty(): return position
	if not available.has(home_direction):
		home_direction = game.harbor_visual.outward(tile.cell, game.island_tiles)
		if not available.has(home_direction): home_direction = available.keys()[0]
	if state == "returning":
		for direction in available:
			if position.distance_squared_to(available[direction]) < position.distance_squared_to(available[home_direction]):
				home_direction = direction
	return available[home_direction]

func load_weight() -> int:
	var total := 0
	for value in cargo.values(): total += int(value)
	return total

func capacity() -> int:
	return Rules.SHIP_CAPACITIES[int(game.development.tech.ship_capacity)]

func speed() -> float:
	return 150.0 / (1.0 + 2.0 * load_weight() / capacity())

func mass() -> float:
	return 2.0 * (1.0 + 2.0 * load_weight() / capacity())

func acceleration() -> float:
	return 120.0 / mass()

func terrain_velocity(terrain: Dictionary) -> Vector2:
	return game.island_velocity if terrain.get("home", false) else Vector2(terrain.get("velocity", Vector2.ZERO))

func mining_energy() -> float:
	return 12.0 * 24.0 / capacity()

func mining_interval() -> float:
	return 3.0 / Rules.PRODUCTION_MULTIPLIERS[int(game.development.tech.gathering)]

func cargo_state() -> int:
	var weight := load_weight()
	return 0 if weight == 0 else (2 if weight >= capacity() else 1)

func stranded() -> bool:
	return built and state != "docked" and charge <= 0.0

func port_ready() -> bool:
	var port := harbor()
	return not port.is_empty() and Rules.tile_health(port) >= 1.0 and not berths(port.cell).is_empty()

func rescue_cost() -> int:
	return 5000 + ceili(position.distance_to(dock_position()) / 80.0) * 100

func rescue_reason() -> String:
	if not stranded(): return "仅能源耗尽的飞船需要紧急救援"
	if not port_ready(): return "需要完好的港口，不能对接普通地块"
	if game.hook_state != game.HOOK_READY and not towed: return "请先结束当前抓钩作业"
	if game.coins < rescue_cost(): return "金币不足"
	return ""

func emergency_rescue(quoted_cost: int) -> bool:
	var reason := rescue_reason()
	if not reason.is_empty(): game.development.message(reason); return false
	if quoted_cost != rescue_cost():
		rescue_quote = -1
		game.development.message("距离已变化，请重新确认救援费用")
		return false
	if not game.development.pay({"coins": quoted_cost}): return false
	if towed: release_tow()
	position = dock_position()
	state = "docked"
	target = {}
	exhaust.clear()
	rescue_quote = -1
	game.development.message("飞船已救回港口，货物保留，等待卸货和充能")
	return true

func release_tow() -> void:
	towed = false
	game.hooked_target = -1
	game.hook_state = game.HOOK_READY
	game.hook_pos = game._hook_origin()
	game.hook_launch_energy_paid = 0.0
	game.grapple_state_changed.emit(game.hook_state)

func update_tow(delta: float) -> void:
	if not stranded() or not port_ready() or not game.development.has_facility("grapple"):
		release_tow()
		game.development.message("救援中断：需要完好的港口和抓钩小屋")
		return
	var weight := 1.0 + 2.0 * load_weight() / capacity()
	var settings = game.movement_settings
	var velocity: float = settings.hook_empty_retract_speed * settings.hook_loaded_retract_ratio / weight
	var distance := position.distance_to(dock_position())
	var seconds := minf(delta, distance / velocity)
	var cost: float = (settings.loaded_hook_energy_per_second + settings.loaded_hook_mass_energy_per_second * weight) * game._mass_energy_ratio() * game.development.hook_efficiency() * seconds
	if not game._consume_energy(cost, "抓钩救援"):
		game._warn_energy("抓钩救援暂停；R 补能后继续")
		return
	self.velocity = position.direction_to(dock_position()) * velocity
	move_with_collisions(position.direction_to(dock_position()) * velocity * seconds)
	if not built: return
	if not target.is_empty() and state in ["contact", "manual"]:
		release_tow()
		game.development.message("救援路径被地块阻挡，请移动主岛后重试")
		return
	game.hook_pos = position
	if position.distance_to(dock_position()) <= 0.01:
		state = "docked"
		target = {}
		release_tow()
		game.development.message("小飞船已由抓钩接回港口")

func construct(cell := Vector2i(999999, 999999)) -> bool:
	if not built and cell != Vector2i(999999, 999999): home_cell = cell
	if built or int(game.development.tech.exploration) == 0 or harbor().is_empty(): return false
	if Rules.tile_health(harbor()) < 1.0: game.development.message("请先修缮港口"); return false
	if berths(harbor().cell).is_empty(): game.development.message("港口周围没有可用泊位"); return false
	if not game.development.pay(Rules.SHIP_BUILD_COST): return false
	home_direction = Vector2i.ZERO
	built = true
	hp = MAX_HP
	charge = 0.0
	cargo.clear()
	target = {}
	state = "docked"
	velocity = Vector2.ZERO
	position = dock_position()
	game.development.message("探索飞船已建成，正在从浮岛吸收能源")
	return true

func repair_cost() -> Dictionary:
	var missing := ceili(MAX_HP - hp)
	return {"coins": missing * 10, "wood": ceili(missing / 10.0), "ore": ceili(missing / 10.0)}

func repair() -> bool:
	if not built or state != "docked" or not port_ready() or hp >= MAX_HP: return false
	if not game.development.pay(repair_cost()): return false
	hp = MAX_HP
	game.development.message("探索船已修复至100耐久")
	return true

func impact(impact_speed: float) -> void:
	if not built or impact_speed < SAFE_CONTACT_SPEED: return
	var damage := clampf(20.0 + (impact_speed - SAFE_CONTACT_SPEED) * 0.35, 20.0, 60.0)
	hp = maxf(0.0, hp - damage)
	game.development.message("探索船撞击：损失%.0f耐久，剩余%.0f / 100" % [damage, hp])
	if hp > 0.0: return
	if towed: release_tow()
	built = false
	state = "docked"
	charge = 0.0
	velocity = Vector2.ZERO
	cargo.clear()
	target = {}
	exhaust.clear()
	game.follow_ship = false
	game.development.message("探索船已毁坏，船上货物损失；可在港口重新建造")

func terrain_origin(terrain: Dictionary) -> Vector2:
	return terrain.pos - Tiles.bounds(terrain.tiles).get_center()

func clearance(terrain: Dictionary) -> float:
	if terrain.get("tiles", []).is_empty(): return INF
	var distance := INF
	var origin := terrain_origin(terrain)
	for tile in terrain.tiles:
		distance = minf(distance, Tiles.rect_clearance(Rect2(position - HULL * 0.5, HULL), Tiles.cell_rect(origin, tile.cell)))
	return distance

func separate_overlap(terrain: Dictionary) -> Vector2:
	var bounds := Tiles.bounds(terrain.tiles)
	var expanded := Rect2(Vector2(terrain.pos) - bounds.size * 0.5 - HULL * 0.5, bounds.size + HULL).grow(0.1)
	var exits := [Vector2(expanded.position.x, position.y), Vector2(expanded.end.x, position.y), Vector2(position.x, expanded.position.y), Vector2(position.x, expanded.end.y)]
	var nearest: Vector2 = exits[0]
	for point in exits:
		if position.distance_squared_to(point) < position.distance_squared_to(nearest): nearest = point
	var normal := position.direction_to(nearest)
	position = nearest
	return normal

func can_dock() -> bool:
	return built and state == "contact" and charge > 0.0 and not deposits(target).is_empty() and absf(clearance(target)) <= 1.5 and (velocity - terrain_velocity(target)).length() < DOCK_SPEED

func dock_island() -> bool:
	if not can_dock(): return false
	state = "mining"
	dock_offset = position - Vector2(target.pos)
	mining_left = mining_interval()
	game.development.message("已对接%s，开始采集；每趟最多%d份，满载返航" % [str(target.get("name", "矿岛")), capacity()])
	return true

func sweep_tile(rect: Rect2, movement: Vector2) -> Dictionary:
	# Sweep the hull center through the tile expanded by half the hull, so fast frames cannot tunnel.
	var expanded := Rect2(rect.position - HULL * 0.5, rect.size + HULL)
	var enter := -INF
	var leave := INF
	var normal := Vector2.ZERO
	for axis in range(2):
		if is_zero_approx(movement[axis]):
			if position[axis] <= expanded.position[axis] or position[axis] >= expanded.end[axis]: return {}
			continue
		var first := (expanded.position[axis] - position[axis]) / movement[axis]
		var last := (expanded.end[axis] - position[axis]) / movement[axis]
		var near := minf(first, last)
		if near > enter:
			enter = near
			normal = Vector2.ZERO
			normal[axis] = -signf(movement[axis])
		leave = minf(leave, maxf(first, last))
	if enter < -0.0001 or enter > 1.0 or enter >= leave or leave <= 0.0: return {}
	return {"time": maxf(0.0, enter), "normal": normal}

func move_with_collisions(movement: Vector2) -> void:
	var first: Dictionary = {}
	var candidates: Array = game.hazards.duplicate()
	candidates.append({"pos": game.island_pos + Tiles.bounds(game.island_tiles).get_center(), "tiles": game.island_tiles, "active": true, "shop": true, "home": true})
	if not target.is_empty() and not candidates.has(target): candidates.append(target)
	for terrain in candidates:
		if not terrain.get("active", false) or terrain.get("tiles", []).is_empty(): continue
		var bounds := Tiles.bounds(terrain.tiles)
		var origin: Vector2 = terrain.pos - bounds.get_center()
		var path := Rect2(position - HULL * 0.5, HULL).merge(Rect2(position + movement - HULL * 0.5, HULL)).grow(1.0)
		if not path.intersects(Rect2(origin + bounds.position, bounds.size)): continue
		if clearance(terrain) < -0.01:
			first = {"time": 0.0, "normal": separate_overlap(terrain), "terrain": terrain}
			break
		for tile in terrain.tiles:
			var hit := sweep_tile(Tiles.cell_rect(origin, tile.cell), movement)
			if not hit.is_empty() and (first.is_empty() or float(hit.time) < float(first.time)):
				first = hit
				first.terrain = terrain
	if first.is_empty():
		position += movement
		return
	position += movement * float(first.time) + Vector2(first.normal) * 0.1
	target = first.terrain
	var other_velocity := terrain_velocity(target)
	var closing_speed := maxf(0.0, -(velocity - other_velocity).dot(first.normal))
	var other_mass := Tiles.mass(target.tiles)
	var force := Physics.impulse(velocity, other_velocity, mass(), other_mass, first.normal)
	velocity += force / mass()
	if target.get("home", false):
		game.island_velocity -= force / other_mass
		if closing_speed >= SAFE_CONTACT_SPEED: game.development.damage_at(position, closing_speed)
	elif Physics.movable(target):
		target.velocity = other_velocity - force / other_mass
		Physics.damage(target, position, closing_speed, mass())
	else:
		velocity = velocity.slide(first.normal)
	state = "contact" if closing_speed < DOCK_SPEED else "manual"
	dock_offset = position - Vector2(target.pos)
	exhaust.clear()
	impact(closing_speed)
	if built and closing_speed < SAFE_CONTACT_SPEED and not deposits(target).is_empty():
		game.development.message("已轻触岛屿，点击船旁「对接并采集」")

func setup_ui(parent: Control) -> void:
	dock_button = game._make_small_button("对接并采集")
	dock_button.name = "ShipDockButton"
	dock_button.custom_minimum_size = Vector2(150, 36)
	dock_button.add_theme_font_size_override("font_size", 14)
	dock_button.pressed.connect(dock_island)
	dock_button.z_index = 5
	parent.add_child(dock_button)
	dock_button.hide()
	overflow_panel = game._make_panel(Vector2.ZERO, Vector2(300, 0), Color("#fff1d4"))
	overflow_panel.name = "ShipOverflowPrompt"
	overflow_panel.z_index = 5
	parent.add_child(overflow_panel)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 8)
	overflow_panel.add_child(game._with_margin(body, 12))
	overflow_label = Label.new()
	overflow_label.custom_minimum_size.x = 270
	overflow_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	overflow_label.add_theme_font_size_override("font_size", 14)
	overflow_label.add_theme_color_override("font_color", Color("#a14232"))
	body.add_child(overflow_label)
	overflow_confirm = game._make_small_button("继续采集，丢弃超出部分")
	overflow_confirm.add_theme_font_size_override("font_size", 14)
	overflow_confirm.pressed.connect(confirm_overflow)
	body.add_child(overflow_confirm)
	overflow_return = game._make_small_button("停止采集并返航")
	overflow_return.add_theme_font_size_override("font_size", 14)
	overflow_return.pressed.connect(recall)
	body.add_child(overflow_return)
	overflow_panel.hide()

func update_ui() -> void:
	if not is_instance_valid(dock_button): return
	var screen: Vector2 = game._world_to_screen(position)
	var visible: bool = built and not game.sky_map_open and not game.saves.is_open() and not game.development.modal.visible and not game.development.tile_menu.is_open() and Rect2(90, 95, 1060, 500).has_point(screen)
	dock_button.visible = visible and can_dock()
	if dock_button.visible:
		dock_button.position = (screen + Vector2(48, -18) * game.camera_zoom).clamp(Vector2(90, 95), game.VIEW_SIZE - Vector2(160, 50))
	overflow_panel.visible = visible and state == "overflow"
	if overflow_panel.visible:
		var batch := next_batch()
		overflow_label.text = "货舱空间不足：剩余%d格。\n继续采集将丢弃：%s。\n超出部分无法找回，是否继续？" % [maxi(0, capacity() - load_weight()), Rules.cost_text(batch.get("discarded", {}))]
		overflow_panel.reset_size()
		overflow_panel.position = (screen + Vector2(48, -32) * game.camera_zoom).clamp(Vector2(90, 95), game.VIEW_SIZE - overflow_panel.size - Vector2(10, 20))

func next_batch() -> Dictionary:
	var available := deposits(target)
	if available.is_empty(): return {}
	var tile: Dictionary = available[0]
	var kept: Dictionary = {}
	var discarded: Dictionary = {}
	var remaining := maxi(0, capacity() - load_weight())
	for key in Rules.YIELDS[tile.kind]:
		if key not in ["stone", "ore", "magma"]: continue
		var amount: int = Rules.YIELDS[tile.kind][key]
		var accepted := mini(amount, remaining)
		if accepted > 0: kept[key] = accepted
		if accepted < amount: discarded[key] = amount - accepted
		remaining -= accepted
	return {"tile": tile, "kept": kept, "discarded": discarded}

func confirm_overflow() -> bool:
	if state != "overflow": return false
	return mine_once(true)

func deposits(terrain: Dictionary) -> Array:
	var result: Array = []
	if int(terrain.get("size_class", 0)) >= int(game.development.tech.exploration): return result
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
	if target.is_empty(): game.development.message("雷达内 2000 px 范围没有当前探索等级可采集的矿岛；升级探索飞船或移动空岛后再试"); return false
	state = "outbound"
	game.development.message("探索飞船启航：" + str(target.name))
	return true

func recall() -> void:
	if built and state != "docked": state = "returning"

func manual_move(delta: float, direction: Vector2) -> void:
	if not built or towed: return
	var steps := maxi(1, ceili(delta / 0.05))
	for step in range(steps):
		var seconds := delta / steps
		state = "manual"
		target = {}
		var thrusting := not direction.is_zero_approx() and charge > 0.0
		var previous_velocity := velocity
		var desired := direction.limit_length() * speed() if thrusting else Vector2.ZERO
		velocity = velocity.move_toward(desired, acceleration() * (1.0 if thrusting else 0.75) * seconds)
		var approach_speed: float = (velocity - game.island_velocity).length()
		var previous := position
		move_with_collisions((previous_velocity + velocity) * 0.5 * seconds)
		if not built: return
		var travelled := previous.distance_to(position)
		if thrusting: charge = maxf(0.0, charge - travelled / speed() * 2.0)
		update_exhaust(seconds, direction.normalized(), thrusting and travelled > 0.0 and state == "manual")
		for port in game.island_tiles:
			if port.facility != "harbor" or Rules.tile_health(port) < 1.0: continue
			var cell: Vector2i = port.cell
			var available := berths(cell)
			for side in available:
				var berth: Vector2 = available[side]
				if position.distance_to(berth) <= 4.0 and approach_speed < DOCK_SPEED and (previous_velocity - game.island_velocity).dot(Vector2(side)) < 0.0:
					home_cell = cell
					home_direction = side
					position = berth
					state = "docked"
					target = {}
					velocity = Vector2.ZERO
					exhaust.clear()
					return
		if state == "contact": return

func update(delta: float) -> void:
	update_ui()
	if is_instance_valid(status_label): status_label.text = status_text()
	if state not in ["outbound", "returning", "manual"] or not built:
		exhaust.clear()
		exhaust_elapsed = 0.0
	if not built: return
	if game.follow_ship:
		var direction := Input.get_vector("move_left", "move_right", "move_up", "move_down")
		if not towed and (state in ["manual", "outbound", "returning"] or (not direction.is_zero_approx() and charge > 0.0)):
			manual_move(delta, direction)
			return
	if state == "manual":
		manual_move(delta, Vector2.ZERO)
		return
	if state == "docked":
		velocity = Vector2.ZERO
		var port := harbor()
		if port.is_empty(): return
		position = dock_position()
		if not port.is_empty() and Rules.tile_health(port) >= 1.0:
			for key in cargo: game.development.add_stock(key, int(cargo[key]))
			cargo.clear()
			var amount := minf(minf(25.0 * delta, BATTERY - charge), game.energy)
			if amount > 0.0:
				game.energy -= amount
				charge += amount
		return
	if towed:
		state = "returning"
		exhaust.clear()
		return
	if charge <= 0.0:
		manual_move(delta, Vector2.ZERO)
		if state == "manual": state = "returning"
		return
	if state in ["contact", "mining", "overflow"] and not target.is_empty():
		if not target.get("active", false) or target.get("tethered", false):
			recall()
		else:
			velocity = terrain_velocity(target)
			position = Vector2(target.pos) + dock_offset
			if absf(clearance(target)) > 1.5:
				state = "outbound"
	if state == "overflow":
		var batch := next_batch()
		if not batch.is_empty() and batch.discarded.is_empty():
			state = "mining"
			mining_left = mining_interval()
	# Reserve enough energy to return; a moving home can still strand the ship.
	var return_reserve := position.distance_to(dock_position()) / speed() * 2.0 + 20.0
	if state == "contact" and not target.is_empty() and deposits(target).is_empty(): return
	if charge <= return_reserve or target.is_empty() or deposits(target).is_empty(): state = "returning"
	if state in ["outbound", "returning"]:
		var destination: Vector2 = target.pos if state == "outbound" else dock_position()
		var distance := position.distance_to(destination)
		var flight_speed := speed()
		var remaining := maxf(0.0, clearance(target)) if state == "outbound" else distance
		flight_speed = minf(flight_speed, sqrt(2.0 * acceleration() * maxf(0.0, remaining - 8.0) + 100.0))
		var direction := position.direction_to(destination)
		var destination_velocity := terrain_velocity(target) if state == "outbound" else Vector2(game.island_velocity)
		velocity = velocity.move_toward(direction * flight_speed + destination_velocity, acceleration() * delta)
		var travel := minf(distance, minf(velocity.length() * delta, charge * speed() / 2.0))
		var previous := position
		var returning := state == "returning"
		move_with_collisions(velocity.normalized() * travel)
		if not built: return
		# Keep braking away from the mined island instead of latching onto it again.
		if returning and state == "contact" and position.direction_to(destination).dot(position - Vector2(target.pos)) > 0.0:
			state = "returning"
		var travelled := previous.distance_to(position)
		update_exhaust(delta, direction, travelled > 0.0 and charge > 0.0 and state in ["outbound", "returning"])
		charge = maxf(0.0, charge - travelled / speed() * 2.0)
		if state == "returning" and position.distance_to(destination) <= 4.0 and (velocity - game.island_velocity).length() < DOCK_SPEED and port_ready():
			state = "docked"
			target = {}
			velocity = Vector2.ZERO
			exhaust.clear()
			exhaust_elapsed = 0.0
		if charge <= 0.0: exhaust.clear()
	elif state == "mining":
		mining_left -= delta
		while mining_left <= 0.0 and state == "mining":
			mining_left += mining_interval()
			mine_once()

func update_exhaust(delta: float, direction: Vector2, moving: bool) -> void:
	if not moving:
		exhaust.clear()
		exhaust_elapsed = 0.0
		return
	for puff in exhaust: puff.age += delta
	while not exhaust.is_empty() and exhaust[0].age >= 0.48: exhaust.pop_front()
	exhaust_elapsed += delta
	if exhaust_elapsed >= 0.12:
		exhaust_elapsed = fmod(exhaust_elapsed, 0.12)
		var edge := 1.0 / maxf(absf(direction.x) / 40.0, absf(direction.y) / 32.0)
		exhaust.append({"pos": position - direction * (edge + 3.0), "age": 0.0})

func mine_once(allow_overflow := false) -> bool:
	if not built or (state != "mining" and not (state == "overflow" and allow_overflow)): return false
	if absf(clearance(target)) > 1.5: recall(); return false
	var batch := next_batch()
	if batch.is_empty() or charge < mining_energy(): state = "returning"; return false
	if not batch.discarded.is_empty() and not allow_overflow:
		state = "overflow"
		game.development.message("货舱将超载，已暂停采集；请确认是否丢弃多余资源")
		return false
	for key in batch.kept: cargo[key] = int(cargo.get(key, 0)) + int(batch.kept[key])
	charge -= mining_energy()
	var tile: Dictionary = batch.tile
	tile.kind = "grass"
	tile.depleted = true
	state = "mining"
	if not batch.discarded.is_empty():
		game.development.message("警告：货舱超出部分已丢弃，无法找回：" + Rules.cost_text(batch.discarded))
	if load_weight() >= capacity() or deposits(target).is_empty(): state = "returning"
	return true

func status_text() -> String:
	if not built: return "探索船已毁坏 · 货物损失，可重新建造" if hp <= 0.0 else "唯一探索飞船 · 尚未建造"
	var names := {"manual": "手动驾驶 / WASD", "docked": "停泊 / 自动充能", "outbound": "前往矿岛 / 自动减速", "contact": "接触岛屿 / 等待手动对接", "mining": "已对接 / 正在采矿", "overflow": "空间不足 / 等待确认是否丢弃超出资源", "returning": "返航"}
	if stranded(): names[state] = "抓钩救援中" if towed else "能源耗尽 · 等待救援"
	return "%s　耐久 %.0f / 100\n能源 %d / 500 E　货舱 %d / %d（%s）　飞行速度 %.0f px/s\n探索 Lv.%d：可采集%s岛\n%s" % [names[state], hp, charge, load_weight(), capacity(), ["空载", "未满", "满载"][cargo_state()], velocity.length(), game.development.tech.exploration, ["尚未解锁", "普通", "普通、大型", "普通、大型、超级"][int(game.development.tech.exploration)], "空货舱" if cargo.is_empty() else Rules.cost_text(cargo)]

func open_menu() -> void:
	rescue_quote = -1
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
	dev.text_row("返港只停靠锚标港口；外岛慢速接触后，点击船旁按钮对接采矿。\n高速碰撞损失耐久，归零毁坏；每趟最多%d份，货满或缺电返航。" % capacity(), 15)
	dev.button_row("飞船已建造（唯一）" if built else "建造飞船 · " + Rules.cost_text(Rules.SHIP_BUILD_COST), func() -> void: construct(); dev.render_menu(), built or int(dev.tech.exploration) == 0 or harbor().is_empty() or not dev.can_pay(Rules.SHIP_BUILD_COST))
	dev.button_row("派遣采矿" if launch_reason() == "" else "派遣采矿 · " + launch_reason(), func() -> void: launch(); dev.close_menu(), launch_reason() != "")
	dev.button_row("召回飞船", func() -> void: recall(); dev.close_menu(), not built or state == "docked" or stranded())
	if state == "overflow":
		dev.text_row("继续采集将永久丢弃：" + Rules.cost_text(next_batch().get("discarded", {})), 15)
		dev.button_row("继续采集并丢弃超出部分", func() -> void: confirm_overflow(); dev.close_menu())
	if built and hp < MAX_HP:
		dev.button_row("港口修理 · " + Rules.cost_text(repair_cost()), func() -> void: repair(); dev.render_menu(), state != "docked" or not port_ready() or not dev.can_pay(repair_cost()))
	if stranded():
		dev.text_row("能源耗尽：用抓钩拖至港口，或付费紧急救援。货物保留，救回后正常充能。", 15)
		if rescue_quote < 0:
			dev.button_row("紧急救援 · %d 金币" % rescue_cost(), func() -> void: rescue_quote = rescue_cost(); dev.render_menu(), not rescue_reason().is_empty())
		else:
			dev.button_row("确认支付 %d 金币，救回港口" % rescue_quote, func() -> void: emergency_rescue(rescue_quote); dev.render_menu(), not rescue_reason().is_empty())
			dev.button_row("取消付费救援", func() -> void: rescue_quote = -1; dev.render_menu())
		if not rescue_reason().is_empty(): dev.text_row(rescue_reason(), 15)
	dev.button_row("关闭并继续运行 · Esc", dev.close_menu)

func snapshot() -> Dictionary:
	return {"home_direction": home_direction, "velocity": velocity, "home_cell": home_cell, "built": built, "state": state, "charge": charge, "position": position, "cargo": cargo.duplicate(), "mining_left": mining_left, "target_key": target.get("world_key", Vector2i.ZERO), "target_index": target.get("world_index", -1), "towed": towed, "hp": hp, "dock_offset": dock_offset}

func restore(data: Dictionary) -> void:
	exhaust.clear()
	exhaust_elapsed = 0.0
	rescue_quote = -1
	hp = float(data.get("hp", MAX_HP))
	velocity = data.get("velocity", Vector2.ZERO)
	dock_offset = data.get("dock_offset", Vector2.ZERO)
	towed = bool(data.get("towed", false))
	home_cell = data.get("home_cell", Vector2i(999999, 999999))
	home_direction = data.get("home_direction", Vector2i.ZERO)
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
	if built and state not in ["docked", "manual"] and target.is_empty(): state = "returning"
	if state in ["mining", "contact", "overflow"] and not data.has("dock_offset"): state = "outbound"
	if built and state == "outbound" and not target.is_empty() and clearance(target) < 0.0:
		separate_overlap(target)
	if towed:
		game.hooked_target = -1
		game.hook_state = game.HOOK_RETRACT
		game.hook_pos = position

func draw_ship() -> void:
	if not built: return
	for puff in exhaust:
		var size := 3.0 + floorf(puff.age * 5.0)
		var origin: Vector2 = (puff.pos - Vector2.ONE * size * 0.5).round()
		var alpha: float = 0.8 * (1.0 - puff.age / 0.48)
		game.draw_rect(Rect2(origin, Vector2.ONE * size), Color(0.65, 0.70, 0.70, alpha))
		game.draw_rect(Rect2(origin, Vector2.ONE * (size - 1.0)), Color(0.91, 0.93, 0.92, alpha))
	ensure_visual()
	game.draw_texture_rect(visual_viewport.get_texture(), Rect2(position - Vector2(40, 32), Vector2(80, 64)), false)
	if game.follow_ship:
		game.draw_rect(Rect2(position + Vector2(-40, -70), Vector2(80, 35)), Color("#493e38"))
		game.draw_string(ThemeDB.fallback_font, position + Vector2(-38, -59), "血量 %.0f / %.0f" % [hp, MAX_HP], HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color("#fff5dc"))
		game.draw_rect(Rect2(position + Vector2(-39, -55), Vector2(78 * hp / MAX_HP, 3)), Color("#92b568") if hp > 30.0 else Color("#c15c47"))
		game.draw_string(ThemeDB.fallback_font, position + Vector2(-38, -43), "能量 %.0f / %.0f" % [charge, BATTERY], HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color("#fff5dc"))
		game.draw_rect(Rect2(position + Vector2(-39, -39), Vector2(78 * charge / BATTERY, 3)), Color("#6cc9db"))

func radar_rect() -> Rect2:
	var size := Vector2(1, 0.8) * clampf(80.0 * game.map_scale, 24.0, 40.0)
	return Rect2(game._world_to_map(position) - size * 0.5, size)

func ensure_visual() -> void:
	if visual_viewport == null:
		# Preserve the ship's existing sampling and placement in the world draw order.
		visual_viewport = SubViewport.new()
		visual_viewport.size = Vector2i(480, 384)
		visual_viewport.transparent_bg = true
		visual_viewport.disable_3d = true
		visual_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		game.add_child(visual_viewport)
		visual = preload("res://art_templates/complex_ui/collector_thrusters.gd").new()
		visual_viewport.add_child(visual)
		visual.set_process(false)
		visual.position = Vector2(240, 192)
		visual.scale *= 6.0
	visual.set_cargo_state(cargo_state())
