extends SceneTree

const Rules = preload("res://scripts/scale_rules.gd")
var failures: Array[String] = []
var checks := 0

func _init() -> void:
	call_deferred("_run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func tiles(count: int) -> Array:
	var result: Array = []
	for i in range(count):
		result.append({"cell": Vector2i(i % 10, i / 10), "kind": "grass", "facility": "", "hp": 100.0, "level": 1, "depleted": false})
	return result

func target(count: int, shop := false) -> Dictionary:
	return {"active": true, "type": "容量测试岛", "weight": float(count), "pos": Vector2(2000, 350), "island": {"tiles": tiles(count), "shop": shop, "size_class": 0, "active": true, "tethered": true}}

func _run() -> void:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.set_physics_process(false)
	game._start_demo()
	game.plots = []
	game.hazards = []
	game.development.tech.docking = 2
	check(game.player_tile_limit() == 100, "Default play is capped at 100")
	check(Rules.player_limit(999, false) == 100, "Release builds ignore debug override")
	check(Rules.player_limit(999, true) == 144, "Debug override cannot exceed 144")
	check(Rules.player_limit(0, true) == 100, "Debug override cannot reduce normal capacity")
	check(Rules.available_combat_tiles(100) == 60, "Full player island leaves 60 combat terrain cells")
	check(Rules.available_combat_tiles(81) == 79, "Typical island leaves 79 combat terrain cells")

	game.island_tiles = tiles(98)
	game._refresh_island_shape()
	var incoming := target(2)
	game.targets = [incoming]
	game.hooked_target = 0
	check(game._target_lock_reason(incoming).is_empty(), "Exact capacity target is hookable")
	game._begin_island_attachment(incoming)
	check(game.hook_state == game.HOOK_FIXING, "Exact capacity enters fixing")
	game._finish_hook()
	check(game.island_tiles.size() == 100, "98 plus 2 reaches exactly 100")
	check(not incoming.active and not incoming.island.active, "Successful merge consumes source once")
	var cells: Dictionary = {}
	for tile in game.island_tiles: cells[tile.cell] = true
	check(cells.size() == 100, "Capacity merge preserves non-overlapping cells")

	var excess := target(1)
	game.targets = [excess]
	game.hooked_target = 0
	check(not game._target_lock_reason(excess).is_empty(), "Full island refuses target at hook contact")
	var energy_before: float = game.energy
	game._begin_island_attachment(excess)
	check(game.island_tiles.size() == 100 and game.hook_state == game.HOOK_READY, "Over-capacity fixing is refused")
	check(excess.active and excess.island.active and not excess.island.tethered, "Rejected source remains available and untethered")
	check(game.hooked_target == -1 and game.energy == energy_before, "Rejection clears target without extra energy charge")

	game.island_tiles = tiles(99)
	game._refresh_island_shape()
	var late := target(1)
	game.targets = [late]
	game.hooked_target = 0
	game._begin_island_attachment(late)
	check(game.hook_state == game.HOOK_FIXING, "99 plus 1 initially enters fixing")
	game.island_tiles.append(tiles(100)[99])
	game._finish_hook()
	check(game.island_tiles.size() == 100 and late.active and not late.island.tethered, "Final commit rechecks capacity if island changed during fixing")

	var shop := target(30, true)
	game.targets = [shop]
	game.hooked_target = 0
	check(game._target_lock_reason(shop).is_empty(), "Full island can hook a shop")
	game._begin_island_attachment(shop)
	check(game.development.trade_open and game.island_tiles.size() == 100, "Shop opens trade without consuming land capacity")
	game.development.close_menu()
	game.development.tech.terraform = 1
	check(game.development.trim(Vector2i(9, 9)), "Full island can trim an edge tile")
	check(game.island_tiles.size() == 99 and game._target_lock_reason(target(1)).is_empty(), "Trimming restores room to merge")
	game._update_hud()
	check(game.resource_labels.land.text == "99/100", "HUD shows used and maximum capacity")
	check("剩余 1 格" in game.resource_labels.land.tooltip_text, "HUD tooltip shows remaining capacity")

	if DisplayServer.get_name() != "headless":
		game.camera_zoom = game._god_zoom_limit()
		game.camera_world = game.island_pos + game.island_bounds.get_center()
		game.targets = []
		game.context_panel.hide()
		game.queue_redraw()
		await process_frame
		await RenderingServer.frame_post_draw
		check(game.header_row.get_global_rect().end.x <= 1152, "Capacity HUD fits viewport")
		var land: Label = game.resource_labels.land
		check(land.size.x >= land.get_theme_font("font").get_string_size("100/100", HORIZONTAL_ALIGNMENT_LEFT, -1, land.get_theme_font_size("font_size")).x, "Full capacity text fits without clipping")
		check(root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../artifacts/game/island-capacity-preview.png")) == OK, "Capacity preview saved")
	game.queue_free()
	await process_frame
	print("SCALE LIMITS TEST: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
