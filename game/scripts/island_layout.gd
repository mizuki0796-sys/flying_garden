extends RefCounted

const Rules = preload("res://scripts/development_rules.gd")
const Tiles = preload("res://scripts/island_tiles.gd")
const Board = preload("res://scripts/island_layout_board.gd")
var game
var draft: Array = []
var original: Array = []
var presets: Array = [{}, {}, {}]
var history: Array = []
var selected: Array = []
var board
var status: Label
var apply_button: Button
var confirmation := false
var feedback := ""

func _init(owner_node) -> void:
	game = owner_node

func ensure_ids() -> void:
	var next_id := 1
	for preset in presets:
		for id in preset: next_id = maxi(next_id, int(id) + 1)
	for tile in game.island_tiles: next_id = maxi(next_id, int(tile.get("layout_id", 0)) + 1)
	for tile in game.island_tiles:
		if not tile.has("layout_id"):
			tile.layout_id = next_id
			next_id += 1

func begin() -> void:
	ensure_ids()
	original = game.island_tiles.duplicate(true)
	draft = original.duplicate(true)
	history.clear()
	selected.clear()
	confirmation = false
	feedback = ""

func open() -> void:
	if int(game.development.tech.layout) == 0:
		game.development.message("先在 T 科技树研究整岛规划")
		return
	var busy := busy_reason()
	if not busy.is_empty(): game.development.message(busy); return
	game.development.close_menu()
	game.development.tile_menu.close()
	game.sky_map_open = false
	begin()
	game.development.layout_open = true
	game.development.render_menu()
	game.development.modal.show()

func busy_reason() -> String:
	if game.hook_state != game.HOOK_READY: return "请先收回抓钩并完成岛屿对接"
	if game.explorer.state != "docked": return "请等待探索飞船返航停泊"
	return ""

func moved_count() -> int:
	var count := 0
	for i in range(draft.size()):
		if draft[i].cell != original[i].cell: count += 1
	return count

func quote() -> Dictionary:
	if moved_count() == 0: return {}
	var result := Rules.LAYOUT_BASE_COST.duplicate()
	for key in result: result[key] += Rules.LAYOUT_TILE_COST[key] * moved_count()
	return result

func validate_layout(tiles: Array) -> String:
	if tiles.size() != original.size() or tiles.is_empty(): return "地块数量已变化，请重新打开布局"
	var occupied: Dictionary = {}
	for i in range(tiles.size()):
		var tile: Dictionary = tiles[i]
		if not tile.get("cell") is Vector2i: return "布局坐标无效"
		if original[i].cell == Vector2i.ZERO and tile.cell != Vector2i.ZERO: return "核心地块必须保留在原点"
		if occupied.has(tile.cell): return "地块不能重叠"
		if absi(tile.cell.x) > 100 or absi(tile.cell.y) > 100: return "布局超出规划范围"
		occupied[tile.cell] = true
	if not occupied.has(Vector2i.ZERO): return "布局必须保留核心"
	var queue: Array = [Vector2i.ZERO]
	var seen := {Vector2i.ZERO: true}
	var cursor := 0
	while cursor < queue.size():
		var cell: Vector2i = queue[cursor]
		cursor += 1
		for direction in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var neighbor: Vector2i = cell + direction
			if occupied.has(neighbor) and not seen.has(neighbor):
				seen[neighbor] = true
				queue.append(neighbor)
	if seen.size() != tiles.size(): return "有地块与核心断开；请连接后再应用"
	for tile in tiles:
		if tile.facility != "harbor": continue
		var edge := false
		for direction in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			if not occupied.has(tile.cell + direction): edge = true
		if not edge: return "探索港口必须位于岛屿外围"
	return ""

func placement_reason() -> String:
	var reason := validate_layout(draft)
	if not reason.is_empty(): return reason
	for hazard in game.hazards:
		if not bool(hazard.active) or not hazard.has("tiles"): continue
		var origin: Vector2 = hazard.pos - Tiles.bounds(hazard.tiles).get_center()
		if not Tiles.contact(draft, game.island_pos, hazard.tiles, origin).is_empty():
			return "新布局与附近浮岛重叠，请先驶离后再布置"
	return ""

func move_selection(delta: Vector2i) -> bool:
	if delta == Vector2i.ZERO or selected.is_empty(): return false
	var candidate := draft.duplicate(true)
	for index in selected:
		if original[index].cell == Vector2i.ZERO: feedback = "核心固定；请框选其他地块"; refresh(); return false
		candidate[index].cell += delta
	# A single occupied destination swaps complete tiles, including their contents.
	if selected.size() == 1:
		var index: int = selected[0]
		for other in range(draft.size()):
			if other != index and draft[other].cell == candidate[index].cell:
				if original[other].cell == Vector2i.ZERO: feedback = "不能交换核心地块"; refresh(); return false
				candidate[other].cell = draft[index].cell
	var occupied: Dictionary = {}
	for tile in candidate:
		if occupied.has(tile.cell) or absi(tile.cell.x) > 100 or absi(tile.cell.y) > 100:
			feedback = "目标重叠或超出范围；请放到空闲区域"
			refresh()
			return false
		occupied[tile.cell] = true
	history.append(draft.duplicate(true))
	draft = candidate
	confirmation = false
	feedback = ""
	refresh()
	return true

func undo() -> void:
	if history.is_empty(): return
	draft = history.pop_back()
	selected.clear()
	confirmation = false
	feedback = "已撤销"
	refresh()

func reset() -> void:
	history.append(draft.duplicate(true))
	draft = original.duplicate(true)
	selected.clear()
	confirmation = false
	feedback = "已恢复当前岛屿布局"
	refresh()

func save_preset(slot: int) -> bool:
	var reason := validate_layout(draft)
	if not reason.is_empty(): feedback = reason; refresh(); return false
	var positions: Dictionary = {}
	for tile in draft: positions[tile.layout_id] = tile.cell
	presets[slot] = positions
	confirmation = false
	feedback = "已保存预设 %d；随游戏存档保存，应用时才扣费" % (slot + 1)
	refresh()
	return true

func load_preset(slot: int) -> bool:
	var positions: Dictionary = presets[slot]
	if positions.size() != draft.size(): feedback = "预设为空或岛屿地块已增减，请重新保存预设"; refresh(); return false
	var candidate := draft.duplicate(true)
	for tile in candidate:
		if not positions.has(tile.layout_id): feedback = "预设对应的地块已变化，请重新保存"; refresh(); return false
		tile.cell = positions[tile.layout_id]
	var reason := validate_layout(candidate)
	if not reason.is_empty(): feedback = reason; refresh(); return false
	history.append(draft.duplicate(true))
	draft = candidate
	selected.clear()
	confirmation = false
	feedback = "已载入预设 %d，尚未应用" % (slot + 1)
	refresh()
	return true

func apply() -> bool:
	if int(game.development.tech.layout) == 0: feedback = "尚未研究整岛规划"; refresh(); return false
	if game.island_tiles != original: feedback = "岛屿状态已变化，请重新打开布局"; refresh(); return false
	var reason := busy_reason()
	if reason.is_empty(): reason = placement_reason()
	if not reason.is_empty(): feedback = reason; refresh(); return false
	if moved_count() == 0: feedback = "布局没有变化，不扣资源"; refresh(); return false
	if not game.development.pay(quote()): feedback = "资源不足，布局未应用"; refresh(); return false
	var remap: Dictionary = {}
	for i in range(original.size()): remap[original[i].cell] = draft[i].cell
	for plot in game.plots: plot.cell = remap[plot.cell]
	game.island_tiles = draft.duplicate(true)
	game.selected_plot = -1
	game.hovered_plot = -1
	game.development.move_from = game.development.NONE
	game.development.trim_pending = game.development.NONE
	game.development.sync()
	game.development.close_menu()
	game._show_notice("岛屿重新布置完成；建筑、作物、耐久与加固均已保留", 5.0)
	return true

func request_apply() -> void:
	if confirmation:
		apply()
		return
	confirmation = true
	feedback = "确认将消耗：" + Rules.cost_text(quote())
	refresh()

func add_button(row: HBoxContainer, caption: String, callback: Callable) -> Button:
	var button: Button = game._make_small_button(caption)
	button.pressed.connect(callback)
	row.add_child(button)
	return button

func render(content: VBoxContainer) -> void:
	game.development.text_row("岛屿剪裁 · 整岛布局", 21)
	game.development.text_row("拖动地块 / 单格落在占用格可交换 · 空白处拖框多选，再拖动整片 · 滚轮缩放 / 中键平移", 13)
	var row := HBoxContainer.new()
	content.add_child(row)
	add_button(row, "撤销", undo)
	add_button(row, "重置", reset)
	add_button(row, "全岛适配", func(): board.fit())
	for slot in range(3):
		add_button(row, "保存 %d" % (slot + 1), save_preset.bind(slot))
		add_button(row, "载入 %d" % (slot + 1), load_preset.bind(slot))
	var surface := Control.new()
	surface.custom_minimum_size = Vector2(980, 270)
	surface.clip_contents = true
	surface.mouse_filter = Control.MOUSE_FILTER_STOP
	content.add_child(surface)
	board = Board.new()
	board.editor = self
	surface.add_child(board)
	surface.gui_input.connect(board.input_event)
	surface.resized.connect(board.fit)
	board.call_deferred("fit")
	status = Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.custom_minimum_size.y = 48
	status.add_theme_font_size_override("font_size", 13)
	status.add_theme_color_override("font_color", game.INK)
	content.add_child(status)
	var footer := HBoxContainer.new()
	content.add_child(footer)
	apply_button = add_button(footer, "应用布局", request_apply)
	add_button(footer, "取消 / Esc（不扣费）", game.development.close_menu)
	refresh()

func refresh() -> void:
	if is_instance_valid(board): board.queue_redraw()
	if not is_instance_valid(status): return
	var reason := placement_reason()
	var price := "无改动，不扣费" if quote().is_empty() else Rules.cost_text(quote())
	if not game.development.can_pay(quote()): reason = "资源不足；请先准备足够的金币、木材、石材和矿物"
	var detail := feedback
	if not reason.is_empty(): detail = reason + (" · " + feedback if not feedback.is_empty() else "")
	if detail.is_empty(): detail = "布局有效。预设仅记录位置，不会恢复资源、作物或耐久。"
	status.text = "移动 %d 格 · 费用：%s\n%s" % [moved_count(), price, detail]
	apply_button.text = "确认扣费并重新布置" if confirmation else "应用布局…"
	apply_button.disabled = moved_count() == 0 or not reason.is_empty() or not game.development.can_pay(quote())
