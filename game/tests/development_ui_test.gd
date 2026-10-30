extends SceneTree

var failures := 0
var checks := 0
var game

func _init() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func capture(filename: String) -> void:
	await process_frame
	await process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../artifacts/game/development-ui/" + filename + ".png"))

func run() -> void:
	root.size = Vector2i(1152, 648)
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game._start_demo()
	game.set_physics_process(false)
	game.set_process(false)
	game.notice_label.text = ""
	var dev = game.development
	dev.toggle(false)
	await capture("01-locked")
	for entry in preload("res://scripts/development_ui.gd").ACTIONS:
		var item: Button = dev.content.find_child("Development_" + entry[0], true, false)
		check(item != null and item.icon != null and item.tooltip_text.length() > item.text.length(), "action retains icon and full hint: " + entry[0])
		check(dev.modal.get_global_rect().encloses(item.get_global_rect()), "action fits visible panel: " + entry[0])
	var tree: Button = dev.content.find_child("Development_tree", true, false)
	check(tree.disabled and tree.tooltip_text.contains("空岛林业"), "locked planting explains research requirement")
	var cell := Vector2i(1, -2)
	var wood_before: int = dev.materials.wood
	check(not dev.build(cell, "tree") and dev.materials.wood == wood_before, "locked planting does not spend resources")
	game.coins = 500
	game.rice_stock = 100
	dev.materials.wood = 100
	check(dev.research("forestry"), "forestry unlocks through actual research")
	dev.render_menu()
	await capture("02-planting")
	tree = dev.content.find_child("Development_tree", true, false)
	check(not tree.disabled and tree.tooltip_text.contains("180") and tree.tooltip_text.contains("消耗"), "planting exposes duration and cost")
	var motion := InputEventMouseMotion.new()
	motion.position = tree.get_global_rect().get_center()
	root.push_input(motion)
	await create_timer(1.0).timeout
	await capture("03-forestry-hover")
	tree.pressed.emit()
	check(not dev.modal.visible and dev.action == "tree" and game.selected_tool == 2, "planting selects real world tool")
	wood_before = dev.materials.wood
	var food_before: int = game.rice_stock
	dev.click(game.island_pos + Vector2(cell) * dev.Tiles.CELL_SIZE)
	check(dev.tile_at(cell).kind == "tree" and dev.tile_at(cell).tree_progress == 0.0, "world click creates sapling")
	check(dev.materials.wood == wood_before - 3 and game.rice_stock == food_before - 1, "planting spends cost exactly once")
	check(not dev.build(cell, "tree") and dev.materials.wood == wood_before - 3, "occupied ground rejects repeat payment")
	check(not dev.gather(cell), "saplings cannot be harvested early")
	game.current_weather = -1
	game.day_minutes = 720.0
	game.land.update_trees(180.0)
	check(dev.tile_at(cell).tree_progress == 1.0, "sapling matures")
	wood_before = dev.materials.wood
	check(dev.gather(cell) and dev.materials.wood == wood_before + 6, "mature tree yields wood")
	check(dev.build(cell, "tree"), "harvested plot supports replanting")
	dev.materials.wood = 0
	dev.toggle(false)
	tree = dev.content.find_child("Development_tree", true, false)
	check(tree.disabled and tree.tooltip_text.contains("资源不足"), "insufficient resources have a visible hover explanation")
	dev.close_menu()
	dev.toggle_energy()
	check(dev.energy_open and dev.modal.size.x == 326, "energy panel remains unchanged")
	game.queue_free()
	await process_frame
	print("DEVELOPMENT UI: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
