extends SceneTree

var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene: PackedScene = load("res://main.tscn")
	var game := scene.instantiate()
	root.add_child(game)
	await process_frame
	game.set_physics_process(false)
	game.set_process(false)
	game._start_demo()
	_expect(game.island_tiles.size() == 25 and is_equal_approx(game.island_mass, 28.0), "25 independent starting tiles determine the starting mass")
	var initial_tiles: Array = game.island_tiles.duplicate(true)
	var nearby_islands := 0
	var view := Rect2(game.island_pos - Vector2(1050, 590), Vector2(2100, 1180))
	for target in game.targets:
		_expect(target.has("island"), "resources never spawn independently of islands")
	for terrain in game.hazards:
		if view.has_point(terrain.pos):
			nearby_islands += 1
		_expect(game._hazard_clearance(terrain) > 0.0, "spawn does not intersect terrain")
	_expect(nearby_islands >= 4, "ordinary flight view contains dense resource islands")
	print("Initial neighborhood: %d resource islands" % nearby_islands)

	var starter: Dictionary = {}
	for target in game.targets:
		if target.has("island") and target.pos.distance_to(game.world_origin + Vector2(450, -100)) < 1.0:
			starter = target
	_expect(not starter.is_empty(), "a reachable starter island exists")
	if not starter.is_empty():
		var initial_count: int = game.island_tiles.size()
		var initial_mass: float = game.island_mass
		var added_count: int = starter.island.tiles.size()
		var signal_count := [0]
		game.merge_ready.connect(func(_terrain: Dictionary) -> void: signal_count[0] += 1)
		game._fire_hook(starter.pos)
		var saw_fixing := false
		for step in range(640):
			game._update_hook(0.025)
			if game.hook_state == game.HOOK_FIXING:
				saw_fixing = true
			if game.hook_state == game.HOOK_READY:
				break
		_expect(saw_fixing and game.hook_state == game.HOOK_READY, "hooking a real island completes dragging and worker attachment")
		_expect(game.island_tiles.size() == initial_count + added_count, "attachment adds every captured tile")
		_expect(is_equal_approx(game.island_mass, initial_mass + float(starter.weight)), "expanded mass includes all incoming terrain")
		_expect(signal_count[0] == 1 and not bool(starter.active) and not bool(starter.island.active), "merge emits once and removes the free-floating source")
		for index in range(initial_tiles.size()):
			_expect(game.island_tiles[index] == initial_tiles[index], "existing terrain and facilities survive attachment")
		var cells: Dictionary = {}
		for tile in game.island_tiles:
			cells[tile.cell] = true
		_expect(cells.size() == game.island_tiles.size(), "snapped terrain never overlaps an occupied cell")
		var reached: Dictionary = {Vector2i.ZERO: true}
		var queue: Array[Vector2i] = [Vector2i.ZERO]
		while not queue.is_empty():
			var cell: Vector2i = queue.pop_front()
			for direction in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var neighbor: Vector2i = cell + direction
				if cells.has(neighbor) and not reached.has(neighbor):
					reached[neighbor] = true
					queue.append(neighbor)
		_expect(reached.size() == cells.size(), "expanded island remains edge-connected")

		# Streaming cannot duplicate attached terrain or lose a currently hooked load.
		var second: Dictionary = {}
		for target in game.targets:
			if target.has("island") and bool(target.active):
				second = target
				break
		game.hooked_target = game.targets.find(second)
		game.hook_state = game.HOOK_RETRACT
		second.island.tethered = true
		game.island_pos += Vector2(4500, -2500)
		game._update_world_stream()
		_expect(game.hooked_target >= 0 and game.targets[game.hooked_target] == second, "a hooked island retains its identity across sector changes")
		var far_view := Rect2(game.island_pos - Vector2(1050, 590), Vector2(2100, 1180))
		var far_islands := 0
		for target in game.targets:
			if target.has("island") and far_view.has_point(target.pos):
				far_islands += 1
		_expect(far_islands >= 4, "faraway regions retain resource island density")
		game.island_pos = game.world_origin
		game._update_world_stream()
		_expect(not bool(starter.active) and not bool(starter.island.active), "returning to a sector does not respawn merged islands")

	game.queue_free()
	await process_frame
	for failure in failures:
		push_error(failure)
	if failures.is_empty():
		print("ISLAND TEST PASSED: modular terrain, density, hook expansion, streaming persistence")
	quit(0 if failures.is_empty() else 1)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		failures.append("FAIL: %s" % description)
