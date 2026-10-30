extends RefCounted

const Rules = preload("res://scripts/development_rules.gd")
const COUNT := 5
const VERSION := 1
const FIELDS := ["island_pos", "world_origin", "island_velocity", "energy", "coins", "rice_seeds", "tomato_seeds", "rice_stock", "energy_crop_stock", "harvested", "gathered", "day_minutes", "day_number", "weather_elapsed", "weather_refresh", "weather_tint", "lightning_left", "lightning_next", "weather_hazard_left", "merchant_arrival_left", "merchant_stay_left", "merchant_available", "collision_cooldown", "worker_slow_time", "control_stun_time", "emergency_braking", "view_mode", "selected_tool", "camera_world", "camera_zoom", "camera_zoom_target", "focus_offset", "map_destination", "map_destination_set", "autopilot_active", "autopilot_state", "autopilot_reason", "hook_state", "hook_pos", "hook_dir", "hook_dangle_left", "hook_launch_energy_paid", "hook_fixing_left", "merge_offset"]
var game
var directory := "user://saves"
var overlay: ColorRect
var panel: PanelContainer
var content: VBoxContainer
var exit_pending := false
var pending_action := ""
var pending_slot := 0
var feedback := ""

func _init(owner_node) -> void:
	game = owner_node

func path_for(slot: int) -> String:
	return directory.path_join("slot_%d.fgs" % slot)

func snapshot() -> Dictionary:
	var state: Dictionary = {}
	for key in FIELDS: state[key] = game.get(key)
	var hooked: Dictionary = {}
	if game.hooked_target >= 0 and game.hooked_target < game.targets.size():
		var terrain: Dictionary = game.targets[game.hooked_target].get("island", {})
		if not terrain.is_empty(): hooked = {"key": terrain.world_key, "index": terrain.world_index}
	return {"version": VERSION, "saved_at": Time.get_datetime_string_from_system(), "state": state,
		"tiles": game.island_tiles.duplicate(true), "plots": game.plots.duplicate(true),
		"tech": game.development.tech.duplicate(), "materials": game.development.materials.duplicate(),
		"layout_presets": game.development.layout.presets.duplicate(true),
		"fuel_source": game.development.fuel_source, "energy_cycle": game.development.energy_cycle_left,
		"farm_cycle": game.development.farm_cycle_left, "selected_crop": game.development.selected_crop, "action": game.development.action,
		"sectors": game.sector_pool.snapshot(game.world_sectors), "hooked": hooked,
		"weather_rng": game.weather_rng.state, "ship": game.explorer.snapshot()}

func validate(data: Variant) -> bool:
	if not data is Dictionary or data.get("version", -1) != VERSION: return false
	for key in ["state", "tech", "materials", "sectors", "hooked", "ship"]:
		if not data.get(key) is Dictionary: return false
	if not data.get("tiles") is Array or not data.get("plots") is Array or data.tiles.is_empty(): return false
	for key in FIELDS:
		if not data.state.has(key) or typeof(data.state[key]) != typeof(game.get(key)): return false
		if data.state[key] is float and not is_finite(data.state[key]): return false
		if data.state[key] is Vector2 and not data.state[key].is_finite(): return false
	for key in ["coins", "rice_seeds", "tomato_seeds", "rice_stock", "energy_crop_stock"]:
		if int(data.state[key]) < 0: return false
	if data.state.day_number < 1 or data.state.day_minutes < 0 or data.state.day_minutes >= 1440 or data.state.energy < 0: return false
	if data.state.hook_state not in [0, 1, 2, 3, 4] or data.state.view_mode not in [0, 1] or data.state.selected_tool not in [0, 1, 2]: return false
	if data.get("action", "") not in ["gather", "farm", "tree", "power", "water", "grapple", "energy", "farm_hut", "harbor", "reinforce", "recycle", "upgrade", "move", "repair", "restore", "trim", "survey"]: return false
	for key in Rules.TECH:
		if key == "layout" and not data.tech.has(key): continue # Older version-1 saves predate this branch.
		if not data.tech.get(key) is int or data.tech[key] < 0 or data.tech[key] > Rules.TECH[key].max: return false
	var presets: Variant = data.get("layout_presets", [{}, {}, {}])
	if not presets is Array or presets.size() != 3: return false
	for preset in presets:
		if not preset is Dictionary: return false
		for id in preset:
			if not id is int or id <= 0 or not preset[id] is Vector2i: return false
	for key in ["wood", "stone", "ore", "magma"]:
		if not data.materials.get(key) is int or data.materials[key] < 0: return false
	var cells: Dictionary = {}
	var layout_ids: Dictionary = {}
	for tile in data.tiles:
		if not valid_tile(tile) or cells.has(tile.cell): return false
		if tile.has("layout_id"):
			if not tile.layout_id is int or tile.layout_id <= 0 or layout_ids.has(tile.layout_id): return false
			layout_ids[tile.layout_id] = true
		cells[tile.cell] = tile
	if not cells.has(Vector2i.ZERO): return false
	var plots_seen: Dictionary = {}
	for plot in data.plots:
		if not plot is Dictionary or not plot.get("cell") is Vector2i or not cells.has(plot.cell): return false
		if cells[plot.cell].kind != "farm" or plots_seen.has(plot.cell): return false
		if plot.get("state", -1) not in [0, 1, 2] or plot.get("crop_type", -1) not in [0, 1]: return false
		if not plot.get("progress") is float or not is_finite(plot.progress) or plot.progress < 0 or plot.progress > 1: return false
		plots_seen[plot.cell] = true
	for key in data.sectors:
		if not key is Vector2i or not data.sectors[key] is Dictionary: return false
		var record: Dictionary = data.sectors[key]
		if not record.get("hazards") is Array: return false
		for terrain in record.hazards:
			if not terrain is Dictionary or not terrain.get("tiles") is Array or terrain.tiles.is_empty(): return false
			for field in ["pos", "radius", "biome", "name", "variant", "active", "tethered", "world_key", "world_index"]:
				if not terrain.has(field): return false
			if not terrain.pos is Vector2 or not terrain.pos.is_finite() or not terrain.world_key is Vector2i: return false
			for tile in terrain.tiles:
				if not valid_tile(tile): return false
	if not Rules.FUEL_NAMES.has(data.get("fuel_source", "invalid")): return false
	for key in ["energy_cycle", "farm_cycle"]:
		if not data.get(key) is float or not is_finite(data[key]): return false
	if data.get("selected_crop", -1) not in [0, 1] or not data.get("weather_rng") is int: return false
	var ship: Dictionary = data.ship
	if not ship.get("built") is bool or ship.get("state", "") not in ["docked", "outbound", "mining", "returning"]: return false
	if not ship.get("charge") is float or not is_finite(ship.charge) or ship.charge < 0 or ship.charge > 500: return false
	if not ship.get("position") is Vector2 or not ship.position.is_finite() or not ship.get("cargo") is Dictionary: return false
	for key in ship.cargo:
		if key not in ["stone", "ore", "magma"] or not ship.cargo[key] is int or ship.cargo[key] < 0: return false
	if not ship.get("target_key") is Vector2i or not ship.get("target_index") is int or not ship.get("mining_left") is float: return false
	if not data.hooked.is_empty():
		if not data.hooked.get("key") is Vector2i or not data.hooked.get("index") is int: return false
		if not data.sectors.has(data.hooked.key): return false
		if data.hooked.index < 0 or data.hooked.index >= data.sectors[data.hooked.key].hazards.size(): return false
	return true

func valid_tile(tile: Variant) -> bool:
	if not tile is Dictionary or not tile.get("cell") is Vector2i: return false
	if not Rules.TERRAIN_NAMES.has(tile.get("kind", "")): return false
	if tile.get("facility", "invalid") != "" and not Rules.FACILITY_NAMES.has(tile.get("facility")): return false
	if not tile.get("hp") is float or not is_finite(tile.hp) or tile.hp < 0 or tile.hp > Rules.tile_max_hp(tile): return false
	if not tile.get("level") is int or tile.level < 1 or tile.level > 4: return false
	if int(tile.get("reinforcement", 0)) < 0 or int(tile.get("reinforcement", 0)) > 15: return false
	return true

func read_packet(slot: int) -> Dictionary:
	if slot < 1 or slot > COUNT: return {}
	var path := path_for(slot)
	if not FileAccess.file_exists(path): return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > 32 * 1024 * 1024 or file.get_length() < 40: return {}
	var digest := file.get_buffer(32)
	var bytes := file.get_buffer(file.get_length() - 32)
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(bytes)
	if hashing.finish() != digest: return {}
	var packet: Variant = bytes_to_var(bytes)
	return packet if validate(packet) else {}

func save_slot(slot: int) -> bool:
	if slot < 1 or slot > COUNT or not game.demo_started: return false
	var packet := snapshot()
	if not validate(packet): feedback = "当前状态未通过存档检查，原存档已保留"; return false
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory)) != OK: feedback = "无法创建存档目录"; return false
	var path := path_for(slot)
	var temporary := path + ".tmp"
	var bytes := var_to_bytes(packet)
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(bytes)
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null: feedback = "存档写入失败，原存档已保留"; return false
	file.store_buffer(hashing.finish())
	file.store_buffer(bytes)
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK: feedback = "存档写入失败，原存档已保留"; return false
	var previous := path + ".bak"
	if FileAccess.file_exists(previous): DirAccess.remove_absolute(previous)
	var had_previous := FileAccess.file_exists(path)
	if had_previous and DirAccess.rename_absolute(path, previous) != OK: feedback = "原存档被占用，未覆盖"; return false
	if DirAccess.rename_absolute(temporary, path) != OK:
		if had_previous: DirAccess.rename_absolute(previous, path)
		feedback = "无法替换存档，已保留原文件"
		return false
	feedback = "已保存到存档 %d" % slot
	return true

func load_slot(slot: int) -> bool:
	var packet := read_packet(slot)
	if packet.is_empty(): feedback = "存档为空、损坏或版本不兼容；当前游戏保持不变"; return false
	game.development.close_menu()
	game.development.tile_menu.close()
	game.world_sectors.clear()
	game.targets.clear()
	game.hazards.clear()
	game.hooked_target = -1
	game.sector_pool.free_records.clear()
	game.sector_pool.journal = packet.sectors.duplicate(true)
	for key in FIELDS: game.set(key, packet.state[key])
	# Old saves may contain an active route. Restore its marker, never its driver.
	game._cancel_autopilot("手动驾驶")
	game.view_mode = game.VIEW_GOD
	game.navigation_view.clear_hover()
	game.navigation_view.queue_redraw()
	game.map_center = game.island_pos
	game.island_tiles = packet.tiles.duplicate(true)
	game.plots = packet.plots.duplicate(true)
	game.development.tech = packet.tech.duplicate()
	if not game.development.tech.has("layout"): game.development.tech.layout = 0
	game.development.layout.presets = packet.get("layout_presets", [{}, {}, {}]).duplicate(true)
	game.development.materials = packet.materials.duplicate()
	game.development.fuel_source = packet.fuel_source
	game.development.energy_cycle_left = packet.energy_cycle
	game.development.farm_cycle_left = packet.farm_cycle
	game.development.selected_crop = packet.selected_crop
	game.development.action = packet.action
	game.development.move_from = game.development.NONE
	game.development.trim_pending = game.development.NONE
	game.explorer.target = {}
	game.active_sector = Vector2i(2147483647, 2147483647)
	game._update_world_stream()
	if int(packet.ship.target_index) >= 0 and not game.world_sectors.has(packet.ship.target_key):
		game.world_sectors[packet.ship.target_key] = game.sector_pool.acquire(packet.ship.target_key, game.world_origin)
	game.explorer.restore(packet.ship)
	if not packet.hooked.is_empty():
		var key: Vector2i = packet.hooked.key
		if not game.world_sectors.has(key): game.world_sectors[key] = game.sector_pool.acquire(key, game.world_origin)
		var target: Dictionary = game.world_sectors[key].island_targets[packet.hooked.index]
		game.hooked_target = game.targets.find(target)
		if game.hooked_target < 0: game.targets.append(target); game.hooked_target = game.targets.size() - 1
	game.weather_rng.state = packet.weather_rng
	game.weather_refresh = 0.0
	game._update_zones(0.0)
	game.selected_plot = -1
	game.hovered_plot = -1
	game.sky_map_open = false
	game.middle_dragging = false
	game.development.sync()
	game.demo_started = true
	game.intro_panel.hide()
	game._update_hud()
	game._update_tool_styles()
	game.context_panel.hide()
	game.queue_redraw()
	feedback = "已读取存档 %d" % slot
	close()
	game._show_notice(feedback)
	return true

func create_ui(root: Control) -> void:
	overlay = ColorRect.new()
	overlay.name = "SaveSlotsOverlay"
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0.06, 0.13, 0.17, 0.65)
	overlay.z_index = 30
	root.add_child(overlay)
	panel = game._make_panel(Vector2(8, 90), Vector2(760, 480), Color("#fff9e9"))
	overlay.add_child(panel)
	content = VBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	panel.add_child(game._with_margin(content, 20))
	overlay.hide()

func is_open() -> bool:
	return overlay != null and overlay.visible

func open_menu() -> void:
	exit_pending = false
	pending_action = ""
	feedback = ""
	game.development.close_menu()
	game.development.tile_menu.close()
	render()
	overlay.show()

func request_exit() -> void:
	if not game.demo_started: game.get_tree().quit(); return
	open_menu()
	exit_pending = true
	render()

func close() -> void:
	overlay.hide()
	exit_pending = false
	pending_action = ""

func label(text: String, size := 16) -> void:
	var item := Label.new()
	item.text = text
	item.add_theme_color_override("font_color", game.INK)
	item.add_theme_font_size_override("font_size", size)
	content.add_child(item)

func button(parent: Node, text: String, action: Callable, disabled := false) -> void:
	var item: Button = game._make_small_button(text)
	item.custom_minimum_size = Vector2(110, 38)
	item.disabled = disabled
	item.pressed.connect(action)
	parent.add_child(item)

func choose(action: String, slot: int) -> void:
	if (action == "save" and FileAccess.file_exists(path_for(slot))) or (action == "load" and game.demo_started):
		pending_action = action
		pending_slot = slot
		render()
		return
	execute(action, slot)

func execute(action: String, slot: int) -> void:
	pending_action = ""
	if action == "save":
		if save_slot(slot) and exit_pending: game.get_tree().quit(); return
	elif action == "load":
		if load_slot(slot): return
	render()

func render() -> void:
	for child in content.get_children(): content.remove_child(child); child.queue_free()
	label("离开前保存这段旅程？" if exit_pending else "空岛日志 · 五个独立存档", 25)
	label("选择一个位置保存并退出，也可取消退出继续游戏。" if exit_pending else "保存当前空岛，或读取之前的旅程。", 14)
	if pending_action != "":
		label("覆盖存档 %d？该位置原有进度将被替换。" % pending_slot if pending_action == "save" else "读取存档 %d？当前未保存进度将丢失。" % pending_slot, 17)
		button(content, "确认" , execute.bind(pending_action, pending_slot))
		button(content, "返回", func() -> void: pending_action = ""; render())
		return
	for slot in range(1, COUNT + 1):
		var packet := read_packet(slot)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		content.add_child(row)
		var info := Label.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_theme_color_override("font_color", game.INK)
		info.add_theme_font_size_override("font_size", 14)
		info.text = "%02d　空存档" % slot
		if not packet.is_empty(): info.text = "%02d　第 %d 天 · %d 格 · %d 金\n　　 %s" % [slot, packet.state.day_number, packet.tiles.size(), packet.state.coins, str(packet.saved_at).replace("T", " ")]
		elif FileAccess.file_exists(path_for(slot)): info.text = "%02d　存档损坏 / 版本不兼容" % slot
		row.add_child(info)
		button(row, "保存并退出" if exit_pending else "保存", choose.bind("save", slot), not game.demo_started)
		if not exit_pending: button(row, "读取", choose.bind("load", slot), packet.is_empty())
	label(feedback, 13)
	var footer := HBoxContainer.new()
	content.add_child(footer)
	button(footer, "取消退出" if exit_pending else "返回 · Esc", close)
	if exit_pending: button(footer, "不保存退出", func() -> void: game.get_tree().quit())
	elif game.demo_started: button(footer, "退出游戏", request_exit)
