extends RefCounted

const Tiles = preload("res://scripts/island_tiles.gd")
# shortcut: one fixed breach with prototype tuning; expand after the wall-shape design is settled.
const NEAR := -280.0
const THICKNESS := 640.0
const HALF_OPENING := 640.0
const MIN_SPEED := 35.0
const STAGES := [160.0, 320.0, 480.0, 640.0]
const RECORDS := [
	"夹层刻痕：旧缺口被后来的石层封住，墙并非一次建成。",
	"建造残页：记录称墙外是没有草木的静默云海。",
	"异质矿片：矿片嵌在朝外的一面，来源仍无法确认。",
	"最后的刻字：留下是家园，离开也要带着家园。通道已贯通。"
]
const RUMORS := ["旧航记：有人把墙称作庇护，也有人称它为牢笼。", "残缺地图：墙外只画着空白，旁注写着‘未见生命’。"]
var game
var enabled := true
var depth := 0.0
var rumors := 0
var crossed := false

func _init(owner_node) -> void:
	game = owner_node

func snapshot() -> Dictionary:
	return {"enabled": enabled, "depth": depth, "rumors": rumors, "crossed": crossed}

static func valid(data: Variant) -> bool:
	return data is Dictionary and data.get("enabled") is bool and data.get("depth") is float and is_finite(data.depth) and data.depth >= 0.0 and data.depth <= THICKNESS and data.get("rumors") is int and data.rumors >= 0 and data.rumors <= RUMORS.size() and data.get("crossed") is bool and (not data.crossed or data.depth == THICKNESS)

func restore(data: Dictionary) -> void:
	enabled = data.get("enabled", false) # Old worlds retain their original geography.
	depth = data.get("depth", 0.0)
	rumors = data.get("rumors", 0)
	crossed = data.get("crossed", false)

func solids(area: Rect2) -> Array[Rect2]:
	var result: Array[Rect2] = []
	if not enabled: return result
	var origin: Vector2 = game.world_origin
	var top: float = origin.y + NEAR - THICKNESS
	var left: float = origin.x - HALF_OPENING
	var right: float = origin.x + HALF_OPENING
	if area.position.x < left:
		result.append(Rect2(area.position.x - 100.0, top, left - area.position.x + 100.0, THICKNESS))
	if area.end.x > right:
		result.append(Rect2(right, top, area.end.x - right + 100.0, THICKNESS))
	if depth < THICKNESS:
		result.append(Rect2(left, top, HALF_OPENING * 2.0, THICKNESS - depth))
	return result

func keep_terrain(terrain: Dictionary) -> bool:
	if not enabled: return true
	return terrain.get("wall_allowed", float(terrain.pos.y) - Tiles.bounds(terrain.tiles).size.y * 0.5 > game.world_origin.y + NEAR + 32.0)

func beyond_inner(point: Vector2) -> bool:
	return point.y < game.world_origin.y + NEAR

static func separation(bounds: Rect2, solid: Rect2) -> Vector2:
	if not bounds.intersects(solid): return Vector2.ZERO
	var pushes := [Vector2(0, solid.end.y - bounds.position.y), Vector2(0, solid.position.y - bounds.end.y), Vector2(solid.position.x - bounds.end.x, 0), Vector2(solid.end.x - bounds.position.x, 0)]
	var push: Vector2 = pushes[0]
	for candidate in pushes:
		if candidate.length_squared() < push.length_squared(): push = candidate
	return push

func collide_terrain() -> void:
	if not enabled: return
	for terrain in game.hazards:
		if not terrain.get("active", false): continue
		var size := Tiles.bounds(terrain.tiles).size
		var bounds := Rect2(terrain.pos - size * 0.5, size)
		for solid in solids(bounds):
			var push := separation(bounds, solid)
			if push == Vector2.ZERO: continue
			terrain.pos += push + push.normalized() * 0.1
			terrain.velocity = Vector2(terrain.get("velocity", Vector2.ZERO)).slide(push.normalized())
			bounds.position = terrain.pos - size * 0.5

func discover() -> void:
	if not enabled or rumors >= RUMORS.size(): return
	game._show_notice(RUMORS[rumors] + "（帮助中可重读）", 8.0)
	rumors += 1

func journal() -> String:
	if not enabled: return ""
	var text := "\n\n厚墙：向北航行，在出生点正北缺口突破。\n先退开加速。反冲从迎撞地块向后逐格减半，加固可保护后排，受损后用 B 修缮。\n突破 %d/%d · %s" % [depth, THICKNESS, "已抵达墙外" if crossed else "尚未穿墙"]
	for i in range(rumors): text += "\n" + RUMORS[i]
	for i in range(STAGES.size()):
		if depth >= STAGES[i]: text += "\n" + RECORDS[i]
	return text

func collide_island() -> void:
	if not enabled: return
	var bounds := Rect2(game.island_pos + game.island_bounds.position, game.island_bounds.size)
	for solid in solids(bounds):
		if not bounds.intersects(solid): continue
		var push := separation(bounds, solid)
		var normal := push.normalized()
		var speed := maxf(0.0, -Vector2(game.island_velocity).dot(normal))
		var front: float = game.world_origin.y + NEAR - depth
		var can_break: bool = normal == Vector2.DOWN and is_equal_approx(solid.end.y, front) and bounds.position.x >= game.world_origin.x - HALF_OPENING and bounds.end.x <= game.world_origin.x + HALF_OPENING
		game.island_pos += push + normal * 0.1
		game.island_velocity = Vector2(game.island_velocity).slide(normal)
		if can_break and speed >= MIN_SPEED and game.collision_cooldown <= 0.0:
			strike(speed)
			if game.game_over: return
		bounds = Rect2(game.island_pos + game.island_bounds.position, game.island_bounds.size)
	if not crossed and depth == THICKNESS and bounds.end.y < game.world_origin.y + NEAR - THICKNESS:
		crossed = true
		game._show_notice("你带着家园穿过了厚墙。眼前只有静默的云海；仍可返航。", 10.0)

func apply_recoil(front_cells: Array, direction: Vector2i, speed: float) -> void:
	var reach := mini(5, 1 + floori((speed - MIN_SPEED) / 20.0))
	var wave := {}
	for cell in front_cells:
		wave[cell] = 13.0 + (speed - MIN_SPEED) * 0.5
	var hit := {}
	for step in range(reach):
		var next_wave := {}
		for cell: Vector2i in wave:
			if hit.has(cell): continue
			var tile: Dictionary = game.development.tile_at(cell)
			if tile.is_empty(): continue
			var damage := float(wave[cell]) / (1.0 + 0.15 * int(tile.get("reinforcement", 0)))
			if roundi(damage) == 0: continue
			hit[cell] = true
			game.development.damage_cell(cell, roundi(damage), "撞墙反冲")
			if game.game_over: return
			next_wave[cell + direction] = damage * 0.5
		wave = next_wave

func strike(speed: float) -> void:
	game.collision_cooldown = 2.0
	var paid := 0.0
	var possible := 0.0
	var leading: float = game.island_bounds.position.y + Tiles.CELL_SIZE.y * 0.5
	var impact_mass: float = game.island_mass
	var front_cells := []
	for tile in game.island_tiles:
		if not is_equal_approx(Vector2(tile.cell).y * Tiles.CELL_SIZE.y, leading): continue
		var amount := (8.0 + speed * 0.15) / (1.0 + 0.15 * int(tile.get("reinforcement", 0)))
		if game.development.tile_at(tile.cell).is_empty(): continue
		paid += minf(float(tile.hp), amount)
		possible += amount
		front_cells.append(tile.cell)
	apply_recoil(front_cells, Vector2i.DOWN, speed)
	if game.game_over: return
	if paid <= 0.0:
		game._show_notice("迎撞地块已耗尽耐久，请先用 B 修缮，再退开加速。", 6.0)
		return
	var previous := depth
	depth = minf(THICKNESS, depth + clampf(impact_mass * speed / 60.0, 8.0, 80.0) * paid / possible)
	var notice := "厚墙深入 %d/%d；迎撞地块受损，退开后可再次撞击。" % [depth, THICKNESS]
	for i in range(STAGES.size()):
		if previous < STAGES[i] and depth >= STAGES[i]: notice += "\n" + RECORDS[i]
	game._show_notice(notice, 8.0)

func draw_world() -> void:
	var area := Rect2(game._screen_to_world(Vector2.ZERO), game.VIEW_SIZE / game.camera_zoom)
	for solid in solids(area):
		var visible := solid.intersection(area)
		if not visible.has_area(): continue
		game.draw_rect(visible, Color("#66706c"))
		for y in range(floori(visible.position.y / 64.0), ceili(visible.end.y / 64.0)):
			for x in range(floori(visible.position.x / 80.0), ceili(visible.end.x / 80.0)):
				var brick := Rect2(x * 80.0 + 2.0, y * 64.0 + 2.0, 76.0, 60.0).intersection(visible)
				if brick.has_area(): game.draw_rect(brick, Color("#879083") if posmod(x + y, 3) == 0 else Color("#737d72"))
	if enabled:
		game.draw_string(ThemeDB.fallback_font, game.world_origin + Vector2(-450, NEAR - depth - 15), "厚墙 · 深入 %d / %d" % [depth, THICKNESS], HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("#f6e8ba"))

func draw_map() -> void:
	var area := Rect2(game._map_to_world(game.MAP_RECT.position), game.MAP_RECT.size / game.map_scale)
	for solid in solids(area):
		var visible := solid.intersection(area)
		if visible.has_area(): game.map_ink.draw_rect(Rect2(game._world_to_map(visible.position), visible.size * game.map_scale), Color("#879083"))
