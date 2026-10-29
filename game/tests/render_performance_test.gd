extends SceneTree

const Fixture = preload("res://tests/render_performance_fixture.gd")
const OUT := "res://../artifacts/game/render-optimization/"
var failures: Array[String] = []
var results: Array = []

func _init() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("This test requires actual GPU rendering")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	root.size = Vector2i(1152, 648)
	var game := Fixture.new()
	root.add_child(game)
	await process_frame
	game._start_demo()
	game.set_process(false)
	game.set_physics_process(false)
	game.get_node("HUD").hide()
	game.isolate_island = true
	game.configure(100)
	await visual_checks(game)
	game.free()
	await process_frame
	var visual_only := "--visual-only" in OS.get_cmdline_user_args()
	if not visual_only and failures.is_empty():
		await benchmark()
	var report := {"engine": Engine.get_version_info().string,
		"gpu": RenderingServer.get_video_adapter_name(), "cpu": OS.get_processor_name(),
		"resolution": [1152, 648], "vsync": "disabled", "results": results, "failures": failures}
	var file := FileAccess.open(OUT + ("visual-report.json" if visual_only else "report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	print("RENDER OPTIMIZATION: %d failures; %s" % [failures.size(), ProjectSettings.globalize_path(OUT)])
	quit(0 if failures.is_empty() else 1)

func capture(game: Node2D, optimized: bool) -> Image:
	game.optimized_rendering = optimized
	game.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()

func visual_checks(game: Node2D) -> void:
	for wind in [0.0, 0.34, 1.6]:
		game.wind_strength = wind
		var before := await capture(game, false)
		var after := await capture(game, true)
		before.save_png(ProjectSettings.globalize_path(OUT + "before-wind-%s.png" % wind))
		after.save_png(ProjectSettings.globalize_path(OUT + "after-wind-%s.png" % wind))
		var delta := compare(before, after)
		results.append({"test": "visual", "wind": wind, "changed_pixels": delta})
		print("VISUAL wind %.2f: %d changed pixels" % [wind, delta])
		check(delta <= 64, "Visual mismatch at wind %s: %d pixels" % [wind, delta])
	# Every growth stage and both crop types remain visible after changing in place.
	for stage in range(5):
		for plot in game.plots:
			plot.state = 2 if stage == 4 else 1
			plot.progress = 1.0 if stage == 4 else stage * 0.25
		game.wind_strength = 0.65
		var before := await capture(game, false)
		var after := await capture(game, true)
		var delta := compare(before, after)
		results.append({"test": "growth_stage", "stage": stage, "changed_pixels": delta})
		print("VISUAL stage %d: %d changed pixels" % [stage, delta])
		check(delta <= 64, "Growth stage %d differs at %d pixels" % [stage, delta])
	# Close view, hover lift, canopy transparency and off-screen cells use the
	# same draw order. Growing crops avoid wall-clock mature-badge pulses.
	for plot in game.plots:
		plot.state = 1
		plot.progress = 0.75
	game.selected_tool = game.TOOL_SEED
	game.hovered_plot = 0
	game.test_pointer = game.island_pos + Vector2(-80, -320)
	for zoom in [1.4, 2.0]:
		game.camera_zoom = zoom
		game.camera_world = game.island_pos + Vector2(-220, -160)
		var before := await capture(game, false)
		var after := await capture(game, true)
		var delta := compare(before, after)
		results.append({"test": "zoom_hover_culling", "zoom": zoom, "changed_pixels": delta})
		check(delta <= 250, "Zoom/hover/culling mismatch at %s: %d pixels" % [zoom, delta])
	game.configure(100)
	# No crops: terrain, machinery, smoke, trees, lamps must compare independently.
	game.plots.clear()
	var before := await capture(game, false)
	var after := await capture(game, true)
	var delta := compare(before, after)
	print("VISUAL protected non-crops: %d changed pixels" % delta)
	results.append({"test": "protected_scenery", "changed_pixels": delta})
	check(delta == 0, "Protected scenery differs at %d pixels" % delta)
	for zoom in [1.4, 2.0]:
		game.camera_zoom = zoom
		game.camera_world = game.island_pos + Vector2(-220, -160)
		before = await capture(game, false)
		after = await capture(game, true)
		delta = compare(before, after)
		results.append({"test": "protected_zoom_culling", "zoom": zoom, "changed_pixels": delta})
		check(delta == 0, "Protected close-up scenery differs at %s: %d pixels" % [zoom, delta])
	var builds: int = game.terrain_mesh_cache.ground_builds
	game.island_pos += Vector2(13, -7)
	game.camera_world += Vector2(13, -7)
	await capture(game, true)
	check(game.terrain_mesh_cache.ground_builds == builds, "Moving island rebuilds static geometry")
	game.island_tiles[0].kind = "sand"
	game.island_tiles[0].depleted = true
	before = await capture(game, false)
	after = await capture(game, true)
	check(game.terrain_mesh_cache.ground_builds == builds + 1, "In-place terrain changes must rebuild cache")
	check(compare(before, after) == 0, "Cache invalidation changes terrain appearance")
	check(game.crop_renderer.plots.is_empty(), "Removed plots retain instance resources")
	var shadow_builds: int = game.terrain_mesh_cache.shadow_builds
	game.island_tiles[0].cell += Vector2i(-1, 0)
	game.development.sync()
	before = await capture(game, false)
	after = await capture(game, true)
	check(game.terrain_mesh_cache.shadow_builds == shadow_builds + 1, "Same-size footprint change must rebuild shadow")
	check(compare(before, after) == 0, "Footprint changes alter cached appearance")

func compare(a: Image, b: Image) -> int:
	var changed := 0
	var bounds := Rect2i()
	var max_channel_delta := 0
	var examples: Array = []
	var da := a.get_data()
	var db := b.get_data()
	var stride := da.size() / (a.get_width() * a.get_height())
	for i in range(0, da.size(), stride):
		if da[i] != db[i] or da[i + 1] != db[i + 1] or da[i + 2] != db[i + 2]:
			changed += 1
			var point := Vector2i((i / stride) % a.get_width(), (i / stride) / a.get_width())
			bounds = Rect2i(point, Vector2i.ONE) if changed == 1 else bounds.merge(Rect2i(point, Vector2i.ONE))
			var distance := maxi(absi(da[i] - db[i]), maxi(absi(da[i + 1] - db[i + 1]), absi(da[i + 2] - db[i + 2])))
			max_channel_delta = maxi(max_channel_delta, distance)
			if examples.size() < 5: examples.append([point, distance])
	print("PIXEL DELTA bounds %s max channel %d examples %s" % [bounds, max_channel_delta, examples])
	return changed

func benchmark() -> void:
	# Fresh scenes prevent velocity, weather, camera, UI and timer state from
	# leaking between cases. Reverse A/B order in round 2 to expose warm-up bias.
	for round_index in range(2):
		for count in [25, 100]:
			for full_loop in [false, true]:
				for optimized in ([false, true] if round_index == 0 else [true, false]):
					await benchmark_case(count, full_loop, optimized, round_index)

func benchmark_case(count: int, full_loop: bool, optimized: bool, round_index: int) -> void:
	seed(20261028)
	var game := Fixture.new()
	root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	game._start_demo()
	game.configure(count)
	game.optimized_rendering = optimized
	game.set_process(true)
	game.set_physics_process(full_loop)
	var warm := Time.get_ticks_usec()
	while Time.get_ticks_usec() - warm < 2000000:
		await RenderingServer.frame_post_draw
	var samples: Array[float] = []
	var start := Time.get_ticks_usec()
	var previous := start
	while Time.get_ticks_usec() - start < 8000000:
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		samples.append(float(now - previous) / 1000.0)
		previous = now
	var sorted := samples.duplicate()
	sorted.sort()
	var result := {"test": "benchmark", "round": round_index + 1,
		"tiles": count, "farms": game.plots.size(), "optimized": optimized,
		"full_loop": full_loop, "frames": samples.size(), "warmup_seconds": 2, "sample_seconds": 8,
		"fps": float(samples.size()) * 1000000.0 / (previous - start),
		"p50_ms": sorted[int(sorted.size() * 0.5)], "p95_ms": sorted[int(sorted.size() * 0.95)],
		"p99_ms": sorted[int(sorted.size() * 0.99)], "max_ms": sorted[-1],
		"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), "frame_ms": samples}
	results.append(result)
	print("BENCH round %d tiles %d full_loop %s optimized %s: %.1f FPS p95 %.2f p99 %.2f ms" % [round_index + 1, count, full_loop, optimized, result.fps, result.p95_ms, result.p99_ms])
	game.set_process(false)
	game.set_physics_process(false)
	game.free()
	await process_frame
