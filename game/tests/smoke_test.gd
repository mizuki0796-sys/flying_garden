extends SceneTree

var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed: PackedScene = load("res://main.tscn")
	var game := packed.instantiate()
	root.add_child(game)
	await process_frame

	_expect(game.icon_atlas != null, "UI icon atlas loads")
	_expect(game.rice_atlas != null and game.tomato_atlas != null, "rice and tomato atlases load")
	_expect(game.island_tiles.size() == 25, "modular floating-island terrain initializes")
	_expect(game.power_hut_texture != null and game.grapple_hut_texture != null and game.water_grain_hut_texture != null, "three reusable hut textures load")
	_expect(game.movement_settings != null, "movement tuning resource loads")
	_expect(is_equal_approx(game.energy_capacity, 150.0), "base energy capacity follows movement design")
	_expect(game.plots.size() == 9, "3x3 farm grid is initialized")
	_expect(int(game.plots[0].crop_type) != int(game.plots[1].crop_type), "rice and tomato plots alternate")
	_expect(game._engine_thrust() == 0.0 and not game.development.has_facility("grapple"), "opening phase starts without propulsion or grapple")
	_expect(game.targets.size() >= 3, "hook targets are initialized")
	game._start_demo()

	# Collision warnings only appear while the island is actually closing on a hazard.
	var warning_hazard := {"active": true, "tethered": false, "pos": game.island_pos + Vector2(240, 0), "radius": 30.0}
	game.hazards = [warning_hazard]
	game.island_velocity = Vector2.LEFT * 80.0
	game._update_warning()
	_expect(is_inf(game.warning_distance), "receding hazards do not trigger collision warnings")
	game.island_velocity = Vector2.RIGHT * 80.0
	game._update_warning()
	_expect(not is_inf(game.warning_distance), "an actual closing trajectory triggers a collision warning")
	game.island_velocity = Vector2.ZERO
	game._update_warning()
	_expect(is_inf(game.warning_distance), "stationary islands do not show collision warnings")
	game.hazards = []

	# Plant, mature, and harvest one crop.
	var initial_seeds: int = game.seeds
	var plot_center: Vector2 = game._plot_rect(0).get_center()
	game._select_tool(game.TOOL_SEED)
	game._interact_with_plot(plot_center)
	_expect(game.seeds == initial_seeds - 1, "planting consumes one seed")
	_expect(int(game.plots[0].state) == 1, "planted crop enters growing state")
	_expect(game.selected_plot == 0, "clicking a farm tile keeps its local UI selected")
	game._set_plot_context(0)
	_expect("农田地块" in game.context_title_label.text and "水稻" in game.context_label.text, "farm tile card exposes crop and plot state")
	var planted: Dictionary = game.plots[0]
	planted.progress = 0.99
	game.plots[0] = planted
	game._update_crops(1.0)
	_expect(int(game.plots[0].state) == 2, "crop matures through growth update")
	var coins_before_harvest: int = game.coins
	game._interact_with_plot(plot_center)
	_expect(game.harvested == 1, "mature crop can be harvested")
	_expect(game.coins == coins_before_harvest + game.Development.Rules.HARVEST_COINS, "harvest pays the configured coin reward")
	_expect(game.rice_stock == 1, "harvest stores a crop that can be converted to energy")
	_expect(game.Development.Rules.HARVEST_COINS == 2, "each plant only grants a small direct coin reward")
	game._select_crop_tool(game.CROP_TOMATO)
	game._interact_with_plot(game._plot_rect(2).get_center())
	_expect(int(game.plots[2].state) == 1 and int(game.plots[2].crop_type) == game.CROP_TOMATO, "crop buttons directly choose what an empty field plants")

	# Research and construction turn the grounded garden into a travelling island.
	game.coins = 500
	game.development.materials = {"wood": 100, "stone": 100, "ore": 100, "magma": 2}
	_expect(game.development.research("engine") and game.development.build(Vector2i(0, -2), "power"), "engine research and construction unlock propulsion")
	_expect(game.development.research("hook") and game.development.build(Vector2i(2, 0), "grapple"), "hook research and construction unlock island capture")

	# Only islands are hookable now; use the real reachable starter island.
	game._select_tool(game.TOOL_HOOK)
	_expect(game.selected_plot == -1, "leaving the seed tool dismisses the pinned farm tile UI")
	var target: Dictionary = {}
	for candidate in game.targets:
		if candidate.pos.distance_to(game.world_origin + Vector2(450, -100)) < 1.0:
			target = candidate
	var tiles_before: int = game.island_tiles.size()
	game._fire_hook(target.pos)
	for step in range(500):
		game._update_hook(0.04)
		if game.hook_state == game.HOOK_READY:
			break
	_expect(game.hook_state == game.HOOK_READY, "hook returns to ready state")
	_expect(game.island_tiles.size() == tiles_before + target.island.tiles.size(), "hooked island adds its resource tiles")

	# Input-driven movement must spend energy and change the island position.
	var position_before: Vector2 = game.island_pos
	var energy_before: float = game.energy
	Input.action_press("move_right")
	game._physics_process(0.5)
	Input.action_release("move_right")
	_expect(game.island_pos.x > position_before.x, "movement input moves the floating island")
	_expect(game.energy < energy_before, "movement consumes energy")

	# Energy never regenerates by itself; crops require the researched factory.
	game.island_velocity = Vector2.ZERO
	game.energy = 100.0
	game._physics_process(1.0)
	_expect(is_equal_approx(game.energy, 100.0), "idle island does not regenerate energy")
	game.energy = 0.0
	_expect(game.development.research("bioenergy") and game.development.research("automatic") and game.development.build(Vector2i(1, -2), "energy"), "crop conversion requires an energy factory")
	game._refuel_from_crops()
	_expect(is_equal_approx(game.energy, 8.0), "level-one crop energy converts rice at the researched rate")

	# The same thrust produces less acceleration at higher mass.
	game.energy = 150.0
	game.island_velocity = Vector2.ZERO
	game.island_mass = 28.0
	game._apply_movement(1.0, Vector2.RIGHT, true)
	var light_speed: float = game.island_velocity.length()
	game.energy = 150.0
	game.island_velocity = Vector2.ZERO
	game.island_mass = 42.0
	game._apply_movement(1.0, Vector2.RIGHT, true)
	var heavy_speed: float = game.island_velocity.length()
	_expect(heavy_speed < light_speed * 0.75, "mass reduces acceleration according to thrust over mass")
	game.island_mass = 28.0

	# Initial-island timing stays inside the design acceptance bands.
	game.energy = 150.0
	game.island_pos = game.world_origin
	game.island_velocity = Vector2.ZERO
	var acceleration_time := 0.0
	while game.island_velocity.length() < game._max_speed() * 0.8 and acceleration_time < 15.0:
		game._apply_movement(0.05, Vector2.RIGHT, true)
		acceleration_time += 0.05
	_expect(acceleration_time >= 7.0 and acceleration_time <= 12.0, "first engine reaches cruise speed gradually")
	game.energy = 150.0
	game.island_velocity = Vector2.RIGHT * game._max_speed()
	var braking_time := 0.0
	while game.island_velocity.length() > 0.5 and braking_time < 8.0:
		game._apply_movement(0.05, Vector2.ZERO, false)
		braking_time += 0.05
	_expect(braking_time >= 3.5 and braking_time <= 5.5, "passive braking stops the initial island in 3.5-5.5 seconds")

	# Movement is unbounded and the camera mode yields immediately to driving input.
	game.island_pos = game.world_origin + Vector2(4000.0, 0.0)
	game.island_velocity = Vector2.RIGHT * 10.0
	game._apply_movement(0.1, Vector2.ZERO, false)
	_expect(game.island_pos.x > game.world_origin.x + 3900.0, "movement has no hard world boundary")
	_expect(game.soft_boundary_active, "soft-boundary slowdown activates outside 150x150 tiles")
	game.island_velocity = Vector2.ZERO
	game._set_view_mode(game.VIEW_FOCUS)
	Input.action_press("move_right")
	game._physics_process(0.1)
	Input.action_release("move_right")
	_expect(game.view_mode == game.VIEW_GOD, "driving from focus view switches to god view")

	# A map destination starts autopilot, which moves and spends its extra energy budget.
	game.island_pos = game.world_origin
	game.island_velocity = Vector2.ZERO
	game.energy = 150.0
	game.map_destination = game.island_pos + Vector2(220.0, 0.0)
	game.map_destination_set = true
	# Navigation thrust is isolated from obstacle avoidance (covered separately).
	game.hazards = []
	game._start_autopilot()
	var energy_before_autopilot: float = game.energy
	game._physics_process(0.5)
	_expect(game.autopilot_active, "confirmed map destination starts autopilot")
	_expect(game.island_velocity.length() > 0.0 and game.energy < energy_before_autopilot, "autopilot moves and consumes energy")
	game._cancel_autopilot("test complete")

	# Emergency braking charges energy and applies its crop-loss consequence.
	for crop_index in range(3):
		var emergency_plot: Dictionary = game.plots[crop_index]
		emergency_plot.state = 1
		emergency_plot.progress = 0.5
		game.plots[crop_index] = emergency_plot
	game.energy = 150.0
	game.island_velocity = Vector2.RIGHT * game._max_speed()
	game._emergency_stop()
	var remaining_crops := 0
	for emergency_plot_value in game.plots:
		if int(emergency_plot_value.state) != 0:
			remaining_crops += 1
	_expect(is_equal_approx(game.energy, 125.0), "emergency stop consumes the configured 25 energy")
	_expect(remaining_crops == 2 and game.worker_slow_time > 0.0, "emergency stop loses 30 percent crops and disrupts workers")

	# Mechanical actions are gated at zero energy.
	game.energy = 0.0
	game.hook_state = game.HOOK_READY
	game._fire_hook(game._hook_origin() + Vector2.RIGHT * 100.0)
	_expect(game.hook_state == game.HOOK_READY, "hook launch is rejected at zero energy")

	game.queue_free()
	await process_frame
	if failures.is_empty():
		print("SMOKE TEST PASSED: farming, hook, movement, energy, and UI initialization")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)


func _expect(condition: bool, description: String) -> void:
	if condition:
		print("PASS: %s" % description)
	else:
		failures.append("FAIL: %s" % description)

