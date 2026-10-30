extends SceneTree
const TechUI = preload("res://scripts/technology_tree_ui.gd")
var failures := 0
var checks := 0
var game
var ui
func _init() -> void:
	call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func capture(filename: String) -> void:
	game._update_hud()
	await process_frame
	await process_frame
	if is_instance_valid(ui.card): ui._place_card()
	await process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../artifacts/game/technology-tree/" + filename + ".png"))
func run() -> void:
	root.size = Vector2i(1152, 648)
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game._start_demo()
	game.set_physics_process(false)
	game.notice_label.text = ""
	var dev = game.development
	dev.toggle(true)
	ui = dev.content.get_node("TechnologyTree")
	ui.set_process(false)
	await process_frame
	var all_keys: Array = []
	for i in range(TechUI.GROUPS.size()):
		ui.surface.get_node("Category_%d" % i).pressed.emit()
		check(ui.group_index == i, "category button switches branches")
		for key in TechUI.GROUPS[i].keys:
			check(ui.nodes.has(key) and not all_keys.has(key), "every technology occurs exactly once")
			all_keys.append(key)
	check(all_keys.size() == dev.Rules.TECH.size(), "all technologies remain reachable")
	ui.select_group(0)
	await capture("01-energy")
	check(ui.nodes.engine.size == Vector2(76, 76), "technology nodes keep approved dimensions")
	check(ui.surface.get_node("Category_0").size == Vector2(64, 54), "category buttons stay inside sidebar")
	var point: Vector2 = ui.nodes.engine.get_global_rect().get_center()
	ui.poll_hover(0.49, point)
	check(ui.card == null, "hover delay prevents immediate popup")
	ui.poll_hover(0.02, point)
	check(is_instance_valid(ui.card) and ui.active_key == "engine", "hover opens adjacent detail after half a second")
	await capture("02-hover-research")
	ui.poll_hover(0.3, ui.card.get_global_rect().get_center())
	check(is_instance_valid(ui.card), "moving into detail keeps research accessible")
	var before: int = game.coins
	ui.research_button.pressed.emit()
	check(dev.tech.engine == 1 and game.coins == before - 25, "research button pays real cost and raises actual level")
	check(dev.research_cost("engine").coins == 75 and ui.research_button.disabled, "next level uses scaled cost and checks resources")
	await capture("03-upgraded")
	ui.poll_hover(0.2, Vector2(1100, 620))
	check(ui.card == null, "leaving card closes it")
	ui.select_group(1)
	ui.nodes.layout.pressed.emit()
	check(ui.research_button.disabled, "locked technology cannot be researched")
	await capture("04-island-locked")
	check(ui.get_global_rect().encloses(ui.card.get_global_rect()), "bottom detail stays inside unclipped panel")
	ui.select_group(2)
	check(ui.card == null, "category switch clears stale popup")
	ui.nodes.agri_automation.pressed.emit()
	await capture("05-farming")
	ui.select_group(3)
	ui.nodes.shelter.pressed.emit()
	await capture("06-protection")
	ui.card.find_child("Requires_forestry", true, false).pressed.emit()
	check(ui.group_index == 2 and ui.active_key == "forestry", "cross-category prerequisite opens its actual branch")
	ui.select_group(4)
	await capture("07-navigation")
	ui.select_group(5)
	ui.nodes.exploration.pressed.emit()
	await capture("08-exploration")
	check(ui.research_button.disabled, "multiple prerequisite requirements remain enforced")
	for key in dev.tech: dev.tech[key] = int(dev.Rules.TECH[key].max)
	ui.select_group(0)
	ui.nodes.engine.pressed.emit()
	check(ui.research_button.disabled and ui.research_button.text == "已满级", "max level disables purchase")
	await capture("09-completed")
	dev.close_menu()
	ui._process(0.01)
	check(ui.card == null and not dev.modal.visible, "closing menu removes popup")
	dev.toggle_energy()
	check(dev.energy_open and dev.modal.size.x == 326, "energy panel layout is preserved")
	game.queue_free()
	await process_frame
	print("TECHNOLOGY UI: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
