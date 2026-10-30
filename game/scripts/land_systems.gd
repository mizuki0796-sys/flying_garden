extends RefCounted

const Rules = preload("res://scripts/development_rules.gd")
var game

func _init(owner_node) -> void:
	game = owner_node

func reinforce_reason(cell: Vector2i) -> String:
	var tile: Dictionary = game.development.tile_at(cell)
	if tile.is_empty(): return "请选择地块"
	var level := int(tile.get("reinforcement", 0))
	if level >= 15: return "地块已加固至满级"
	if level >= int(game.development.tech.reinforcement) * 3: return "需提升地块加固科技"
	if Rules.tile_health(tile) < 1.0: return "请先修缮地块"
	return ""

func reinforce(cell: Vector2i) -> bool:
	var reason := reinforce_reason(cell)
	if reason != "": game.development.message(reason); return false
	var tile: Dictionary = game.development.tile_at(cell)
	var cost := Rules.reinforcement_cost(int(tile.get("reinforcement", 0)))
	if not game.development.pay(cost): return false
	var spent: Dictionary = tile.get("reinforcement_spent", {})
	for key in cost: spent[key] = int(spent.get(key, 0)) + int(cost[key])
	tile.reinforcement_spent = spent
	tile.reinforcement = int(tile.get("reinforcement", 0)) + 1
	tile.hp = Rules.tile_max_hp(tile)
	game.development.message("地块加固 Lv.%d / 15 · 耐久 %d" % [tile.reinforcement, tile.hp])
	return true

func refund(cell: Vector2i) -> Dictionary:
	var tile: Dictionary = game.development.tile_at(cell)
	var level: int = game.development.tech.recycling
	if tile.is_empty() or level <= 0: return {}
	if int(tile.get("reinforcement", 0)) == 0: return {"stone": 1}
	var result: Dictionary = {}
	var spent: Dictionary = tile.get("reinforcement_spent", {})
	for key in spent:
		var amount := floori(int(spent[key]) * Rules.RECYCLE_RATIOS[level])
		if amount > 0: result[key] = amount
	return result

func recycle(cell: Vector2i) -> bool:
	var dev = game.development
	if int(dev.tech.recycling) == 0 or game.hook_state != game.HOOK_READY or not dev.can_trim(cell):
		dev.message("回收需对应科技，并保留核心、设施和地块连通性")
		return false
	var returns := refund(cell)
	if not dev.pay(Rules.TRIM_COST): return false
	dev.destroy_tile(cell)
	for key in returns: dev.add_stock(key, returns[key])
	dev.sync()
	dev.message("地块已回收：" + Rules.cost_text(returns))
	return true

func tree_health(tile: Dictionary) -> float:
	return clampf(float(tile.get("tree_hp", 100.0)) / Rules.tree_max_hp(tile), 0.0, 1.0)

func damage_tree(tile: Dictionary, amount: float) -> void:
	if tile.kind != "tree": return
	tile.tree_hp = maxf(0.0, float(tile.get("tree_hp", 100.0)) - amount)
	if float(tile.tree_hp) <= 0.0:
		tile.kind = "grass"
		tile.depleted = true
		tile.erase("tree_progress")
		tile.erase("tree_hp")
		game.development.message("林木枯死，地块保留；可重新扦插")
		game._refresh_island_shape()

func update_trees(delta: float) -> void:
	var kind: String = game._weather_kind()
	var rate: float = game._growth_multiplier()
	for tile in game.island_tiles:
		if tile.kind != "tree": continue
		var progress := float(tile.get("tree_progress", 1.0))
		if progress < 1.0:
			var previous_max := Rules.tree_max_hp(tile)
			tile.tree_progress = minf(1.0, progress + delta * rate * maxf(0.25, tree_health(tile)) / Rules.TREE_GROW_SECONDS)
			# New growth adds vitality without erasing existing damage.
			tile.tree_hp = float(tile.get("tree_hp", previous_max)) + Rules.tree_max_hp(tile) - previous_max
		if kind in ["snow", "storm", "cyclone"]:
			var damage: float = {"snow": 0.18, "storm": 0.4, "cyclone": 1.0}[kind]
			damage_tree(tile, delta * damage * game.development.weather_damage_factor(tile.cell))

func is_edge(cell: Vector2i) -> bool:
	for direction in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		if game.development.tile_at(cell + direction).is_empty(): return true
	return false
