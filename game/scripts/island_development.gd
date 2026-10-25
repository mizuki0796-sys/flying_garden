extends RefCounted

const Rules = preload("res://scripts/development_rules.gd")
const Tiles = preload("res://scripts/island_tiles.gd")
const MerchantMarket = preload("res://scripts/merchant_market.gd")
const TileActionMenu = preload("res://scripts/tile_action_menu.gd")
const NONE := Vector2i(999999, 999999)
var game
var materials := {"wood": 12, "stone": 8, "ore": 6, "magma": 0}
var tech: Dictionary = {}
var fuel_source := ""
var energy_open := false
var energy_status_label: Label
var action := "gather"
var move_from := NONE
var trim_pending := NONE
var modal: PanelContainer
var default_modal_style: StyleBox
var content: VBoxContainer
var tech_open := false
var selected_crop := 0
var selected_tech := "engine"
var energy_cycle_left := 12.0
var farm_cycle_left := Rules.FARM_CYCLE_SECONDS
var trade_open := false
var trade_source := ""
var market_ui
var tile_menu

func _init(owner_node) -> void:
	game = owner_node
	for key in Rules.TECH:
		tech[key] = 0

func stock(key: String) -> int:
	match key:
		"coins": return game.coins
		"food": return game.rice_stock
		"rice_seeds": return game.rice_seeds
		"tomato_seeds": return game.tomato_seeds
	return materials.get(key, 0)

func add_stock(key: String, amount: int) -> void:
	match key:
		"coins": game.coins += amount
		"food": game.rice_stock += amount
		"rice_seeds": game.rice_seeds += amount
		"tomato_seeds": game.tomato_seeds += amount
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
	game._show_notice(text, 4.0)

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

func facility_count(kind: String) -> int:
	var count := 0
	for tile in game.island_tiles:
		if str(tile.facility) == kind:
			count += 1
	return count

func has_facility(kind: String) -> bool:
	return facility_count(kind) > 0

func crop_yield() -> int:
	return 1

func forest_protection(cell: Vector2i) -> float:
	var protection := 0.0
	for tile in game.island_tiles:
		if tile.kind == "tree" and Vector2(tile.cell).distance_to(Vector2(cell)) <= Rules.FOREST_RADIUS:
			protection = maxf(protection, Rules.FOREST_PROTECTION[int(tech.shelter)] * clampf(float(tile.get("hp", 100.0)) / 100.0, 0.0, 1.0))
	return protection

func weather_damage_factor(cell: Vector2i) -> float:
	return maxf(0.20, (1.0 - 0.18 * int(tech.forecast)) * (1.0 - forest_protection(cell)))

func farm_radius(tile: Dictionary) -> int:
	return Rules.FARM_RADII[clampi(int(tile.get("level", 1)), 1, 3)]

func farm_manager(cell: Vector2i) -> Dictionary:
	if int(tech.agri_automation) == 0: return {}
	var nearest: Dictionary = {}
	var distance := INF
	for tile in game.island_tiles:
		if str(tile.facility) != "farm_hut" or not bool(tile.get("farm_enabled", true)) or float(tile.get("hp", 100.0)) < 100.0: continue
		var candidate := Vector2(tile.cell).distance_to(Vector2(cell))
		if candidate <= farm_radius(tile) and candidate < distance:
			nearest = tile
			distance = candidate
	return nearest

func manage_farms() -> int:
	var count := 0
	for index in range(game.plots.size()):
		var plot: Dictionary = game.plots[index]
		var farm := tile_at(plot.cell)
		if farm.is_empty() or farm.kind != "farm" or str(farm.facility) != "" or float(farm.get("hp", 100.0)) < 100.0: continue
		var hut := farm_manager(plot.cell)
		if hut.is_empty(): continue
		var crop := int(hut.get("farm_crop", 0))
		if int(plot.state) == 2:
			if game._work_plot(index, crop, true): count += 1
		if int(plot.state) == 0 and game.seed_stock(crop) > 0:
			if game._work_plot(index, crop, true): count += 1
	return count

func fuel_unlocked(source: String) -> bool:
	match source:
		"": return true
		"rice", "tomato": return int(tech.bioenergy) > 0
		"ore": return int(tech.mineral_energy) > 0
		"magma": return int(tech.geothermal) > 0
	return false

func fuel_stock(source: String) -> int:
	match source:
		"rice": return game.rice_stock
		"tomato": return game.energy_crop_stock
		"ore", "magma": return int(materials[source])
	return 0

func fuel_energy(source: String) -> int:
	match source:
		"rice": return crop_energy(game.CROP_RICE)
		"tomato": return crop_energy(game.CROP_TOMATO)
		"ore": return ore_energy()
		"magma": return 60 if fuel_unlocked(source) else 0
	return 0

func select_fuel(source: String) -> bool:
	if not Rules.FUEL_NAMES.has(source) or not fuel_unlocked(source): return false
	fuel_source = source
	energy_cycle_left = 0.0
	if energy_open: render_menu()
	return true

func process_fuel() -> bool:
	if fuel_source == "" or not has_facility("energy") or int(tech.automatic) == 0 or not fuel_unlocked(fuel_source): return false
	if game.energy >= game.energy_capacity - 0.01 or fuel_stock(fuel_source) <= 0: return false
	match fuel_source:
		"rice": game.rice_stock -= 1
		"tomato": game.energy_crop_stock -= 1
		_: materials[fuel_source] -= 1
	game._add_energy(fuel_energy(fuel_source), "能源工厂消耗" + str(Rules.FUEL_NAMES[fuel_source]))
	return true

func fuel_status() -> String:
	if fuel_source == "": return "未选择来源 · 不自动补能"
	var prefix := "来源：%s · 库存 %d" % [Rules.FUEL_NAMES[fuel_source], fuel_stock(fuel_source)]
	if not has_facility("energy"): return prefix + " · 请建造能源工厂"
	if game.energy >= game.energy_capacity - 0.01: return prefix + " · 能源已满，暂停消耗"
	if fuel_stock(fuel_source) == 0: return prefix + " · 来源已耗尽，等待补货"
	return prefix + " · 持续补能中"

func harvest_coins(crop_type: int) -> int:
	return Rules.HARVEST_COINS if crop_type == game.CROP_RICE else Rules.TOMATO_HARVEST_COINS

func crop_energy(crop_type: int) -> int:
	var level := clampi(int(tech.bioenergy), 0, Rules.RICE_ENERGY_BY_LEVEL.size() - 1)
	return int(Rules.RICE_ENERGY_BY_LEVEL[level] if crop_type == game.CROP_RICE else Rules.ENERGY_CROP_ENERGY_BY_LEVEL[level])

func ore_energy() -> int:
	return int(Rules.ORE_ENERGY_BY_LEVEL[clampi(int(tech.mineral_energy), 0, Rules.ORE_ENERGY_BY_LEVEL.size() - 1)])

func radar_range() -> float:
	return [720.0, 1700.0, 3000.0, 5000.0][clampi(int(tech.radar), 0, 3)]

func weather_growth(kind: String, base: float) -> float:
	var level := int(tech.forecast)
	if level <= 0:
		return base
	if base >= 1.0:
		return 1.0 + (base - 1.0) * (1.0 + 0.10 * level)
	# Forecasting mitigates only part of a bad-weather penalty, even at max level.
	return 1.0 - (1.0 - base) * (1.0 - 0.22 * level)

func sync() -> void:
	var storage := 75.0
	var grapple_level := 0
	for tile in game.island_tiles:
		if str(tile.facility) == "water": storage += 75.0 * int(tile.get("level", 1))
		if str(tile.facility) == "grapple": grapple_level = int(tile.get("level", 1))
	game.energy_capacity = storage * (1.0 + 0.2 * int(tech.storage))
	game.energy = minf(game.energy, game.energy_capacity)
	game.hook_max_distance = 0.0 if grapple_level == 0 else game.movement_settings.hook_range_tiles * game.movement_settings.tile_size + 96.0 * (int(tech.hook) - 1) + 48.0 * (grapple_level - 1)
	game._refresh_island_shape()
	game._clamp_focus_offset()
	game._update_camera(0.0)

func engine_power() -> float:
	var output := 0.0
	for tile in game.island_tiles:
		if str(tile.facility) == "power":
			output += (1.0 + 0.5 * (int(tile.get("level", 1)) - 1)) * maxf(0.25, float(tile.get("hp", 100.0)) / 100.0)
	return output * (1.0 + 0.3 * int(tech.engine))

func efficiency() -> float:
	return 1.0 - 0.15 * int(tech.efficiency)

func hook_efficiency() -> float:
	# Higher grapple engineering improves both reach and the dedicated winch drive.
	return 1.0 - 0.12 * maxi(0, int(tech.hook) - 1)

func research_cost(key: String) -> Dictionary:
	return Rules.research_cost(key, int(tech[key]))

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
		message("选择种植工具管理农田，或建造自动化管理小屋")
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
	if float(tile.get("hp", 100.0)) < 100.0:
		message("请先修缮受损地块，再开垦或建造")
		return false
	if kind == "tree":
		if int(tech.forestry) == 0:
			message("先研究空岛林业")
			return false
		if str(tile.facility) != "" or tile.kind != "grass":
			message("林木只能种在空闲草地")
			return false
		if not pay(Rules.BUILD_COSTS.tree): return false
		tile.kind = "tree"
		tile.depleted = false
		sync()
		message("林木已种下；质量已计入浮岛")
		return true
	if str(tile.facility) != "" or tile.kind not in ["grass", "sand"]:
		message("请选一格没有设施的草地或沙地；林木、矿石须先采集")
		return false
	var required: String = {"power": "engine", "water": "storage", "grapple": "hook", "energy": "automatic", "farm_hut": "agri_automation"}.get(kind, "")
	if kind != "farm" and (required.is_empty() or int(tech[required]) < 1):
		message("先在 T 科技树研究" + str(Rules.TECH[required].name))
		return false
	if kind == "power" and facility_count("power") >= int(tech.engine):
		message("当前动力科技最多建造 %d 座引擎室" % int(tech.engine))
		return false
	if kind in ["grapple", "energy"] and has_facility(kind):
		message("%s只能建造一座" % Rules.FACILITY_NAMES[kind])
		return false
	if not pay(Rules.BUILD_COSTS[kind]): return false
	if kind == "farm":
		tile.kind = "farm"
		game.plots.append({"cell": cell, "state": 0, "progress": 0.0, "crop_type": selected_crop})
	else:
		tile.facility = kind
		tile.level = 1
		if kind == "farm_hut":
			tile.farm_crop = selected_crop
			tile.farm_enabled = true
	sync()
	message("建造完成：" + ("农田" if kind == "farm" else str(Rules.FACILITY_NAMES[kind])))
	return true

func upgrade_cost(cell: Vector2i) -> Dictionary:
	var tile := tile_at(cell)
	if tile.is_empty() or str(tile.facility) not in ["power", "water", "grapple", "farm_hut"]: return {}
	return Rules.scaled_cost({"coins": 20, "wood": 2, "ore": 1}, int(tile.get("level", 1)))

func upgrade(cell: Vector2i) -> bool:
	var tile := tile_at(cell)
	if tile.is_empty() or str(tile.facility) == "":
		message("请选择一座设施")
		return false
	if str(tile.facility) == "energy":
		message("能源工厂效率由作物能源与矿物能源科技决定")
		return false
	var branch: String = {"power": "engine", "water": "storage", "grapple": "hook", "farm_hut": "agri_automation"}[tile.facility]
	var level := int(tile.get("level", 1))
	var max_level := int(tech[branch]) if str(tile.facility) == "farm_hut" else int(tech[branch]) + 1
	if level >= max_level:
		message("请先提升%s研究等级；建筑当前 Lv.%d" % [Rules.TECH[branch].name, level])
		return false
	if not pay(upgrade_cost(cell)): return false
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
	if str(source.facility) == "farm_hut":
		destination.farm_crop = source.get("farm_crop", 0)
		destination.farm_enabled = source.get("farm_enabled", true)
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
		message("不能抛弃核心、设施或会切断主岛的地块")
		return false
	var index := plot_at(cell)
	if index >= 0: game.plots.remove_at(index)
	game.island_tiles.erase(tile_at(cell))
	sync()
	message("地块已抛弃；地形和未收获作物不返还")
	return true

func repair_cost(cell: Vector2i) -> Dictionary:
	var tile := tile_at(cell)
	if tile.is_empty(): return {}
	var damage := clampf(1.0 - float(tile.get("hp", 100.0)) / 100.0, 0.0, 1.0)
	if damage <= 0.0: return {}
	var facility := str(tile.get("facility", ""))
	if facility.is_empty() and tile.kind == "farm":
		return {"coins": maxi(1, ceili(damage * 3.0)), "wood": 1}
	var base: Dictionary = Rules.BUILD_COSTS[facility] if not facility.is_empty() else Rules.LAND_REPAIR_COST
	var ratio := 0.35 + damage * 0.40 if not facility.is_empty() else 0.25 + damage * 0.75
	var cost: Dictionary = {}
	for key in base:
		cost[key] = mini(int(base[key]), ceili(int(base[key]) * ratio))
	return cost

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

func restore_farmland(cell: Vector2i) -> bool:
	var tile := tile_at(cell)
	if tile.is_empty() or tile.kind != "farm" or str(tile.facility) != "":
		message("请选择没有设施的农田")
		return false
	var index := plot_at(cell)
	if index >= 0 and int(game.plots[index].state) != 0:
		message("请先收获作物，再将农田整平为普通土地")
		return false
	if not pay(Rules.RESTORE_FARM_COST): return false
	if index >= 0: game.plots.remove_at(index)
	game.selected_plot = -1
	game.hovered_plot = -1
	tile.kind = "grass"
	tile.hp = 100.0
	tile.depleted = true
	sync()
	message("农田已整平为普通土地，可建造房屋或重新开垦")
	return true

func damage_cell(cell: Vector2i, amount: float, reason := "受损", destroy_crop := true) -> bool:
	var tile := tile_at(cell)
	if tile.is_empty(): return false
	tile.hp = maxf(0.0, float(tile.get("hp", 100.0)) - amount)
	var plot_index := plot_at(cell)
	if destroy_crop and plot_index >= 0 and int(game.plots[plot_index].state) != 0:
		game.plots[plot_index].state = 0
		game.plots[plot_index].progress = 0.0
	message("%s：%s耐久 %d/100；农田受损时作物会损失" % [reason, Rules.TERRAIN_NAMES[tile.kind], tile.hp])
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
	damage_cell(nearest.cell, damage, "地块受损")
	game.screen_shake_time = 0.3
	game.screen_shake_strength = 5.0

func destroy_tile(cell: Vector2i) -> bool:
	var tile := tile_at(cell)
	if tile.is_empty() or cell == Vector2i.ZERO or game.island_tiles.size() <= 1:
		return false
	for index in range(game.plots.size() - 1, -1, -1):
		if game.plots[index].cell == cell:
			game.plots.remove_at(index)
	game.island_tiles.erase(tile)
	game.selected_plot = -1
	game.hovered_plot = -1
	return true

func collision_at(world_position: Vector2, speed: float, other_mass: float) -> int:
	var ordered: Array = []
	for tile in game.island_tiles:
		if tile.cell == Vector2i.ZERO:
			continue
		ordered.append({"tile": tile, "distance": (game.island_pos + Vector2(tile.cell) * Tiles.CELL_SIZE).distance_squared_to(world_position)})
	ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.distance) < float(b.distance))
	var ratio: float = maxf(game.island_mass, other_mass) / maxf(1.0, minf(game.island_mass, other_mass))
	var catastrophic: bool = (ratio >= 3.0 and maxf(game.island_mass, other_mass) >= 35.0) or (game.island_mass >= 45.0 and other_mass >= 45.0)
	var destroy_count: int = 3 if catastrophic and speed >= 70.0 else (2 if catastrophic or speed >= 105.0 else 1)
	var removed := 0
	for entry in ordered:
		if removed >= destroy_count:
			break
		if destroy_tile(entry.tile.cell):
			removed += 1
	for entry in ordered:
		if removed >= destroy_count and not tile_at(entry.tile.cell).is_empty():
			damage_cell(entry.tile.cell, clampf(speed * 0.35 + other_mass * 0.25, 10.0, 70.0), "撞击波及")
			break
	sync()
	message("猛烈撞击：崩落 %d 格%s" % [removed, "，质量差导致局部连锁坍塌" if catastrophic else ""])
	game.screen_shake_time = 0.3
	game.screen_shake_strength = clampf(speed / 7.0, 6.0, 16.0)
	return removed

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
	for key in total: value += int(total[key]) * int({"coins": 1, "wood": 3, "stone": 2, "ore": 5, "magma": 10, "food": 6, "rice_seeds": 2, "tomato_seeds": 4}[key])
	terrain.surveyed = true
	terrain.report = "%s · %s · 资源 %s · 参考估值 %d 金" % [terrain.name, str(terrain.get("rarity", "普通")), Rules.cost_text(total), value]
	message(terrain.report)
	return true

func update(delta := 0.0) -> void:
	if tile_menu != null: tile_menu.update()
	if market_ui != null: market_ui.update()
	if energy_open and is_instance_valid(energy_status_label): energy_status_label.text = fuel_status()
	if delta > 0.0:
		energy_cycle_left -= delta
		while energy_cycle_left <= 0.0:
			energy_cycle_left += Rules.FUEL_CYCLE_SECONDS
			if not process_fuel():
				energy_cycle_left = Rules.FUEL_CYCLE_SECONDS
				break
		farm_cycle_left -= delta
		if farm_cycle_left <= 0.0:
			farm_cycle_left = Rules.FARM_CYCLE_SECONDS
			manage_farms()

func open_trade(source: String) -> bool:
	if source not in ["流浪商人", "漂流商店岛"]: return false
	if source == "流浪商人" and not game.merchant_available:
		message("流浪商人尚未到访")
		return false
	if source == "漂流商店岛" and int(tech.docking) == 0:
		message("需要岛屿对接 I 才能与商店岛交易")
		return false
	if tile_menu != null: tile_menu.close()
	trade_open = true
	energy_open = false
	trade_source = source
	market_ui.mode = "buy"
	tech_open = false
	game.sky_map_open = false
	render_menu()
	modal.show()
	market_ui.update()
	return true

func merchant_state_changed() -> void:
	if trade_open and trade_source == "流浪商人" and not game.merchant_available:
		close_menu()
	if market_ui != null: market_ui.update()

func close_menu() -> void:
	trade_open = false
	energy_open = false
	trade_source = ""
	modal.hide()

func can_trade() -> bool:
	if not trade_open or modal == null or not modal.visible: return false
	if trade_source == "流浪商人": return game.merchant_available
	return trade_source == "漂流商店岛" and int(tech.docking) > 0

func _require_trade() -> bool:
	if can_trade(): return true
	message("商人已离开或交易已结束，请等待下次到访")
	return false

func trade_buy_mineral(key: String, amount: int = 1) -> bool:
	if not Rules.MINERAL_BUY_PRICES.has(key) or amount not in [1, 5]: return false
	return trade_buy(int(Rules.MINERAL_BUY_PRICES[key]) * amount, {key: amount}, "%s ×%d" % [Rules.RESOURCE_NAMES[key], amount])

func trade_buy(cost: int, goods: Dictionary, label: String) -> bool:
	if not _require_trade() or cost <= 0 or goods.is_empty(): return false
	for key in goods:
		if not Rules.RESOURCE_NAMES.has(key) or int(goods[key]) <= 0: return false
	if not pay({"coins": cost}):
		render_menu()
		return false
	for key in goods:
		add_stock(key, int(goods[key]))
	message("交易完成：" + label)
	render_menu()
	return true

func trade_sell_ore() -> bool:
	if not _require_trade(): return false
	if materials.ore < 3:
		message("至少需要 3 矿物")
		return false
	materials.ore -= 3
	game.coins += 35
	message("售出 3 矿物，获得 35 金币")
	render_menu()
	return true

func trade_sell_crop(crop_type: int, amount: int = 1) -> bool:
	if not _require_trade(): return false
	if crop_type not in [game.CROP_RICE, game.CROP_TOMATO] or amount <= 0: return false
	var available: int = game.rice_stock if crop_type == game.CROP_RICE else game.energy_crop_stock
	if available < amount:
		message("库存不足，无法出售")
		return false
	if crop_type == game.CROP_RICE: game.rice_stock -= amount
	else: game.energy_crop_stock -= amount
	var income: int = int(Rules.CROP_SELL_COINS[crop_type]) * amount
	game.coins += income
	message("售出%s ×%d，获得 %d 金币" % [game._crop_name(crop_type), amount, income])
	render_menu()
	return true

func select_action(value: String) -> void:
	if tile_menu != null: tile_menu.close()
	action = value
	move_from = NONE
	trim_pending = NONE
	close_menu()
	game.selected_tool = 2
	game._update_tool_styles()
	message("%s：点击地块；右键/Esc 取消。" % {"gather": "采集", "farm": "开垦", "tree": "种树", "power": "建引擎", "water": "建储能", "grapple": "建抓钩", "energy": "建能源厂", "farm_hut": "建管理小屋", "upgrade": "升级设施", "move": "搬迁", "repair": "修缮", "restore": "农田整平", "trim": "剪裁", "survey": "勘探"}[action])

func click(world_position: Vector2) -> void:
	if action == "survey":
		for target in game.targets:
			if not target.has("island") or not bool(target.active) or game.view_mode == game.VIEW_FOCUS or not game._radar_visible(target.pos): continue
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
		"farm", "tree", "power", "water", "grapple", "energy", "farm_hut": build(cell, action)
		"upgrade": upgrade(cell)
		"repair": repair(cell)
		"restore": restore_farmland(cell)
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
	market_ui = MerchantMarket.new(game)
	market_ui.create_badge(root)
	modal = game._make_panel(Vector2(56, 96), Vector2(1040, 510), Color("#fff1ce"))
	default_modal_style = modal.get_theme_stylebox("panel")
	root.add_child(modal)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	modal.add_child(game._with_margin(scroll, 14))
	content = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 7)
	scroll.add_child(content)
	modal.hide()
	tile_menu = TileActionMenu.new(game)
	tile_menu.create_ui(root)
	update()

func toggle(show_tech: bool) -> void:
	if tile_menu != null: tile_menu.close()
	if modal.visible and not trade_open and not energy_open and tech_open == show_tech:
		close_menu()
		return
	trade_open = false
	energy_open = false
	trade_source = ""
	tech_open = show_tech
	game.sky_map_open = false
	render_menu()
	modal.show()

func toggle_energy() -> void:
	if modal.visible and energy_open:
		close_menu()
		return
	if tile_menu != null: tile_menu.close()
	trade_open = false
	energy_open = true
	tech_open = false
	game.sky_map_open = false
	render_menu()
	modal.show()

func render_energy() -> void:
	modal.position = Vector2(276, 112)
	modal.size = Vector2(600, 420)
	var title := Label.new()
	title.text = "能源来源"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", game.INK)
	content.add_child(title)
	energy_status_label = Label.new()
	energy_status_label.text = fuel_status()
	energy_status_label.add_theme_color_override("font_color", game.INK)
	content.add_child(energy_status_label)
	var hint := Label.new()
	hint.text = "每 12 秒消耗 1 份所选来源；满能或缺料时暂停。\n能量下降或补货后继续；不会改用其他库存。"
	hint.add_theme_font_size_override("font_size", 14)
	hint.add_theme_color_override("font_color", game.INK)
	content.add_child(hint)
	for source in Rules.FUEL_NAMES:
		var caption := ("● " if fuel_source == source else "○ ") + str(Rules.FUEL_NAMES[source])
		if source != "": caption += " · %d 份 · %d E/份" % [fuel_stock(source), fuel_energy(source)]
		if not fuel_unlocked(source): caption += " · 需对应能源科技"
		button_row(caption, select_fuel.bind(source), not fuel_unlocked(source))
	button_row("关闭 · Esc", close_menu)

func text_row(text: String, size := 14) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", game.INK)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 940
	content.add_child(label)

func button_row(text: String, callback: Callable, disabled := false) -> void:
	var button: Button = game._make_small_button(text)
	button.disabled = disabled
	button.pressed.connect(callback)
	content.add_child(button)

func _tech_position(key: String) -> Vector2:
	var rule: Dictionary = Rules.TECH[key]
	return Vector2(14.0 + float(rule.column) * 198.0, 12.0 + float(rule.row) * 58.0)

func _select_tech(key: String) -> void:
	selected_tech = key
	render_menu()

func _tech_blocked(key: String) -> bool:
	for required in Rules.TECH[key].needs:
		if int(tech[required]) < int(Rules.TECH[key].needs[required]):
			return true
	return false

func render_tech_tree() -> void:
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 14)
	content.add_child(body)
	var graph := Control.new()
	graph.custom_minimum_size = Vector2(620, 424)
	graph.draw.connect(func() -> void:
		for key in Rules.TECH_ORDER:
			for required in Rules.TECH[key].needs:
				var start := _tech_position(required) + Vector2(154, 23)
				var finish := _tech_position(key) + Vector2(0, 23)
				graph.draw_line(start, finish, Color("#7f916d") if int(tech[required]) >= int(Rules.TECH[key].needs[required]) else Color("#b9aa91"), 3.0)
	)
	body.add_child(graph)
	for key in Rules.TECH_ORDER:
		var rule: Dictionary = Rules.TECH[key]
		var button: Button = game._make_small_button("%s  %d/%d" % [rule.name, tech[key], rule.max])
		button.position = _tech_position(key)
		button.size = Vector2(154, 44)
		button.icon = game._icon(int(rule.icon))
		button.expand_icon = true
		button.add_theme_constant_override("icon_max_width", 25)
		button.tooltip_text = str(rule.effect)
		if key == selected_tech:
			button.add_theme_stylebox_override("normal", game._button_style(Color("#ffd875"), Color("#7c512f")))
		button.pressed.connect(_select_tech.bind(key))
		graph.add_child(button)
		var progress := ProgressBar.new()
		progress.position = _tech_position(key) + Vector2(4, 45)
		progress.size = Vector2(146, 8)
		progress.max_value = int(rule.max)
		progress.value = int(tech[key])
		progress.show_percentage = false
		progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
		graph.add_child(progress)
	var detail := VBoxContainer.new()
	detail.custom_minimum_size = Vector2(300, 410)
	detail.add_theme_constant_override("separation", 12)
	body.add_child(detail)
	var rule: Dictionary = Rules.TECH[selected_tech]
	var title := Label.new()
	title.text = "%s　Lv.%d/%d" % [rule.name, tech[selected_tech], rule.max]
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", game.INK)
	detail.add_child(title)
	var description := Label.new()
	var needs: PackedStringArray = []
	for required in rule.needs:
		needs.append("%s Lv.%d" % [Rules.TECH[required].name, rule.needs[required]])
	var next_cost: Dictionary = research_cost(selected_tech)
	description.text = "%s\n\n前置：%s\n\n下一级：%s\n\n研究消耗每级 ×%d（基础 ×1 / ×3 / ×9）" % [rule.effect, "无" if needs.is_empty() else " + ".join(needs), "已满级" if int(tech[selected_tech]) >= int(rule.max) else Rules.cost_text(next_cost), Rules.TECH_COST_GROWTH]
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.add_theme_font_size_override("font_size", 15)
	description.add_theme_color_override("font_color", game.INK)
	description.custom_minimum_size.y = 230
	detail.add_child(description)
	var research_button: Button = game._make_small_button("已满级" if int(tech[selected_tech]) >= int(rule.max) else "研究下一级")
	research_button.custom_minimum_size = Vector2(280, 42)
	research_button.disabled = int(tech[selected_tech]) >= int(rule.max) or _tech_blocked(selected_tech) or not can_pay(next_cost)
	research_button.pressed.connect(func() -> void:
		research(selected_tech)
		render_menu())
	detail.add_child(research_button)

func _add_action(grid: GridContainer, label: String, action_key: String, disabled := false) -> void:
	var button: Button = game._make_small_button(label)
	button.custom_minimum_size = Vector2(300, 34)
	button.disabled = disabled
	button.pressed.connect(select_action.bind(action_key))
	grid.add_child(button)

func render_menu() -> void:
	for child in content.get_children():
		content.remove_child(child)
		child.queue_free()
	if trade_open:
		market_ui.render(content)
		return
	modal.position = Vector2(56, 96)
	modal.size = Vector2(1040, 510)
	modal.add_theme_stylebox_override("panel", default_modal_style)
	if energy_open:
		render_energy()
		return
	text_row("科技树" if tech_open else "岛屿开发", 21)
	text_row("金 %d　粮 %d　木 %d　石 %d　矿 %d　岩浆 %d　稻种 %d　番茄种 %d" % [game.coins, game.rice_stock, materials.wood, materials.stone, materials.ore, materials.magma, game.rice_seeds, game.tomato_seeds], 13)
	if tech_open:
		render_tech_tree()
	else:
		var grid := GridContainer.new()
		grid.columns = 3
		grid.add_theme_constant_override("h_separation", 8)
		grid.add_theme_constant_override("v_separation", 8)
		content.add_child(grid)
		_add_action(grid, "采集地形", "gather")
		_add_action(grid, "开垦农田 · " + Rules.cost_text(Rules.BUILD_COSTS.farm), "farm")
		_add_action(grid, "林木扦插 · " + Rules.cost_text(Rules.BUILD_COSTS.tree), "tree", int(tech.forestry) == 0)
		_add_action(grid, "建引擎 %d/%d" % [facility_count("power"), int(tech.engine)], "power", int(tech.engine) == 0)
		_add_action(grid, "建储能室", "water", int(tech.storage) == 0)
		_add_action(grid, "建抓钩小屋 %d/1" % facility_count("grapple"), "grapple", int(tech.hook) == 0 or has_facility("grapple"))
		_add_action(grid, "建能源工厂 %d/1" % facility_count("energy"), "energy", int(tech.automatic) == 0 or has_facility("energy"))
		_add_action(grid, "建自动化管理小屋 · 半径 2 格", "farm_hut", int(tech.agri_automation) == 0)
		_add_action(grid, "升级设施", "upgrade")
		_add_action(grid, "搬迁设施 · 5 金", "move")
		_add_action(grid, "修缮 · 农田低价 / 地基高价", "repair")
		_add_action(grid, "农田整平为土地 · 2 金", "restore")
		_add_action(grid, "剪裁地块", "trim", int(tech.terraform) == 0)
		_add_action(grid, "勘探浮岛", "survey")
		text_row("管理小屋每 6 秒播种、收获半径内农田；右键小屋可选择作物、暂停和升级。", 13)
		button_row(fuel_status() + " · 选择来源", toggle_energy)
		if game.merchant_available:
			button_row("流浪商人已到访 · 交易", open_trade.bind("流浪商人"))
	button_row("关闭 · Esc", close_menu)

func tile_description(cell: Vector2i) -> String:
	var tile := tile_at(cell)
	if tile.is_empty(): return ""
	var facility := str(tile.facility)
	var text := "%s%s · 耐久 %d/100\n" % [Rules.TERRAIN_NAMES[tile.kind], " / %s Lv.%d" % [Rules.FACILITY_NAMES[facility], tile.get("level", 1)] if facility != "" else "", tile.get("hp", 100.0)]
	if float(tile.get("hp", 100.0)) < 100.0: text += "修缮：" + Rules.cost_text(repair_cost(cell)) + "\n"
	if facility == "power": text += "引擎叠加推力，升级增加单格动力；受损会降低输出。\n"
	elif facility == "water": text += "每级提供 75 E 储量，再叠加储能科技。\n"
	elif facility == "grapple": text += "发射点随建筑位置移动；科技和建筑升级扩大射程。\n"
	elif facility == "energy": text += fuel_status() + "；R 选择来源。\n"
	elif facility == "farm_hut": text += "管理半径 %d 格 · %s · %s\n仅播种与收获，受损后暂停。" % [farm_radius(tile), game._crop_name(int(tile.get("farm_crop", 0))), "运行" if bool(tile.get("farm_enabled", true)) else "暂停"]
	elif tile.kind == "farm":
		text += "林木减灾 %d%% · %s\n" % [roundi(forest_protection(cell) * 100), "小屋管理中" if not farm_manager(cell).is_empty() else "手动管理"]
		text += "B → 农田整平：2 金恢复普通土地，请先收获作物。\n"
	elif tile.kind != "farm": text += "资源已采尽，可开发。\n" if bool(tile.get("depleted", false)) else "可采集：" + Rules.cost_text(Rules.YIELDS[tile.kind]) + "\n"
	return text + "右键地块操作 / T 科技"
