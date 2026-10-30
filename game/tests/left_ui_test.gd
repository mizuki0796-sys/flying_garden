extends SceneTree

var failures := 0
var checks := 0

func _init() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)

func capture(game, name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	game.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://../artifacts/game/left-ui-" + name + ".png")

func run() -> void:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game._start_demo()
	game.set_process(false)
	game.set_physics_process(false)
	game._update_context_card()
	check(not game.context_panel.visible, "Observation card does not open automatically")
	check(game.tool_sidebar.position.x == 8 and game.tool_sidebar.size.x <= 64 and game.navigation_buttons.get_parent().get_parent().get_parent() == game.tool_sidebar, "Navigation lives in narrow left sidebar")
	game.merchant_available = true
	game.merchant_stay_left = 60.0
	game.development.update()
	await process_frame
	game.development.update()
	var badge: Button = game.development.market_ui.badge
	check(badge.visible and badge.position.x == 8 and badge.size.x <= 64 and badge.text.is_empty(), "Merchant prompt stays icon-only on left")
	check(not badge.get_global_rect().intersects(game.tool_sidebar.get_global_rect()), "Merchant and tools do not overlap")
	check(badge.get_global_rect().end.y < 588, "Merchant stays clear of notices")
	await capture(game, "normal")
	var island := {"active": true, "pos": game.island_pos + Vector2(480, 0), "tiles": [{"cell": Vector2i(-1, 0), "kind": "grass", "facility": ""}, {"cell": Vector2i(1, 0), "kind": "rock", "facility": ""}], "name": "测试浮岛", "rarity": "普通"}
	game.hazards = [island]
	island.biome = 0
	island.radius = 160.0
	game.targets = []
	game.view_mode = game.VIEW_GOD
	game.development.tech.radar = 3
	check(game._island_at_pointer(island.pos).is_empty(), "Empty gap inside island bounds is not a hover hit")
	check(not game._island_at_pointer(island.pos + Vector2(80, 0)).is_empty(), "Outer occupied tile can be inspected")
	game._toggle_island_details(island.pos + Vector2(80, 0))
	check(game.context_panel.visible and not badge.visible, "E explicitly expands details and suppresses prompt")
	game._update_context_card()
	check(game.context_panel.visible and game.context_panel.position.x == 8, "Details remain open on left after pointer moves")
	await capture(game, "details")
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	game._unhandled_input(esc)
	check(not game.context_panel.visible and game.tool_sidebar.visible, "Escape closes details and restores tools")
	game.inspected_island = island
	island.active = false
	game._update_context_card()
	check(game.inspected_island.is_empty(), "Merged or inactive island closes details")
	game.development.toggle(false)
	await process_frame
	game._update_context_card()
	check(game.development.modal.position.x == 8 and game.development.modal.size.x == 426 and not game.tool_sidebar.visible, "Development opens as left drawer")
	await capture(game, "development")
	game.development.close_menu()
	game.development.tile_menu.open_at(Vector2i(1, 0))
	await process_frame
	game.development.tile_menu.update()
	check(game.development.tile_menu.cell == Vector2i(1, 0) and game.development.tile_menu.panel.position.x > 80, "Tile operations open beside the selected tile")
	game.development.tile_menu.close()
	game.queue_free()
	await process_frame
	print("LEFT UI: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
