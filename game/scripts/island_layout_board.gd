extends Node2D

const Tiles = preload("res://scripts/island_tiles.gd")
var editor
var zoom := 0.6
var offset := Vector2.ZERO
var dragging := false
var boxing := false
var panning := false
var start_cell := Vector2i.ZERO
var start_point := Vector2.ZERO
var cursor := Vector2.ZERO

func fit() -> void:
	if editor.draft.is_empty(): return
	var bounds := Tiles.bounds(editor.draft).grow(120.0)
	var available: Vector2 = get_parent().size
	zoom = clampf(minf(available.x / bounds.size.x, available.y / bounds.size.y), 0.08, 1.4)
	offset = available * 0.5 - bounds.get_center() * zoom
	queue_redraw()

func cell_at(point: Vector2) -> Vector2i:
	var cell := (point - offset) / zoom / Tiles.CELL_SIZE
	return Vector2i(floori(cell.x + 0.5), floori(cell.y + 0.5))

func index_at(cell: Vector2i) -> int:
	for i in range(editor.draft.size()):
		if editor.draft[i].cell == cell: return i
	return -1

func input_event(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		cursor = event.position
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] and event.pressed:
			var world := (cursor - offset) / zoom
			zoom = clampf(zoom * (1.15 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.15), 0.06, 2.0)
			offset = cursor - world * zoom
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			panning = event.pressed
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				start_cell = cell_at(cursor)
				start_point = cursor
				var index := index_at(start_cell)
				boxing = index < 0 or event.shift_pressed
				dragging = not boxing
				if dragging and not editor.selected.has(index): editor.selected = [index]
				if boxing: editor.selected.clear()
			else:
				if dragging: editor.move_selection(cell_at(cursor) - start_cell)
				if boxing:
					var region := Rect2(start_point, cursor - start_point).abs()
					for i in range(editor.draft.size()):
						if editor.original[i].cell == Vector2i.ZERO: continue
						if region.has_point(offset + Vector2(editor.draft[i].cell) * Tiles.CELL_SIZE * zoom): editor.selected.append(i)
				dragging = false
				boxing = false
	elif event is InputEventMouseMotion:
		cursor = event.position
		if panning: offset += event.relative
	queue_redraw()

func _draw() -> void:
	var area: Vector2 = get_parent().size
	draw_rect(Rect2(Vector2.ZERO, area), Color("#b1d4d1"))
	if editor.draft.is_empty(): return
	var first := cell_at(Vector2.ZERO)
	var last := cell_at(area)
	for x in range(first.x, last.x + 2):
		var screen_x := offset.x + (x - 0.5) * Tiles.CELL_SIZE.x * zoom
		draw_line(Vector2(screen_x, 0), Vector2(screen_x, area.y), Color(0.2, 0.4, 0.4, 0.12))
	for y in range(first.y, last.y + 2):
		var screen_y := offset.y + (y - 0.5) * Tiles.CELL_SIZE.y * zoom
		draw_line(Vector2(0, screen_y), Vector2(area.x, screen_y), Color(0.2, 0.4, 0.4, 0.12))
	draw_set_transform(offset, 0, Vector2.ONE * zoom)
	var game = editor.game
	Tiles.draw_ground(self, Vector2.ZERO, editor.draft, Tiles.CELL_SIZE, game.terrain_textures)
	var ordered: Array = editor.draft.duplicate()
	var crop_positions: Dictionary = {}
	for i in range(editor.original.size()):
		var plot_index: int = game.development.plot_at(editor.original[i].cell)
		if plot_index >= 0: crop_positions[editor.draft[i].cell] = game.plots[plot_index]
	ordered.sort_custom(func(a, b): return a.cell.y < b.cell.y)
	for tile in ordered:
		if crop_positions.has(tile.cell): game._draw_crop_plants(self, crop_positions[tile.cell], Tiles.cell_rect(Vector2.ZERO, tile.cell))
		Tiles.draw_decor(self, Vector2.ZERO, [tile], Tiles.CELL_SIZE, false, game.tree_texture, true, game.animation_time, game.wind_strength, Vector2.INF)
		var center: Vector2 = Vector2(tile.cell) * Tiles.CELL_SIZE
		match str(tile.facility):
			"power": game._draw_building(game.power_hut_texture, center + Vector2(0, 20), 92.0, "power", self)
			"water", "energy": game._draw_building(game.water_grain_hut_texture, center + Vector2(6, 20), 88.0, tile.facility, self)
			"grapple": game._draw_building(game.grapple_hut_texture, center + Vector2(12, 20), 100.0, "grapple", self)
			"farm_hut": game._draw_building(game.farm_hut_texture(tile), center + Vector2(0, 20), 80.0, "farm_hut", self)
			"harbor": game._draw_harbor(self, center)
	for index in editor.selected:
		var rect := Tiles.cell_rect(Vector2.ZERO, editor.draft[index].cell)
		draw_rect(rect.grow(-2), Color("#ffe88d"), false, 3.0 / zoom)
		if dragging:
			var delta := cell_at(cursor) - start_cell
			draw_rect(Rect2(rect.position + Vector2(delta) * Tiles.CELL_SIZE, rect.size), Color(1, 0.9, 0.4, 0.4))
	draw_rect(Tiles.cell_rect(Vector2.ZERO, Vector2i.ZERO).grow(-6), Color("#f0aa55"), false, 3.0 / zoom)
	draw_set_transform(Vector2.ZERO)
	draw_string(ThemeDB.fallback_font, offset + Vector2(-14, 8), "核心", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#614026"))
	if boxing: draw_rect(Rect2(start_point, cursor - start_point).abs(), Color("#fff3aa"), false, 2)
