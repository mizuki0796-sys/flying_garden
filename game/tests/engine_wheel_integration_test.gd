extends SceneTree

const OUTPUT := "res://../artifacts/game/engine-wheel-clean/"

func _init() -> void:
	call_deferred("run")

func source_region(game: Node2D, source: Rect2) -> Rect2i:
	var bottom: Vector2 = game.IslandTiles.cell_rect(game.island_pos, Vector2i(0, -2)).get_center() + Vector2(0, 20)
	var world_start := bottom + (source.position - Vector2(774, 936)) * (92.0 / 958.0)
	var screen_start: Vector2 = game._world_to_screen(world_start)
	return Rect2i(Vector2i(screen_start.floor()), Vector2i((source.size * (92.0 / 958.0) * game.camera_zoom).floor()))

func run() -> void:
	assert(DisplayServer.get_name() != "headless", "This integration test needs the real renderer")
	root.size = Vector2i(1152, 648)
	root.content_scale_size = Vector2i(1152, 648)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game._start_demo()
	# Test-only construction resources; no user save or opening rules are changed.
	game.coins = 500
	game.development.materials = {"wood": 100, "stone": 100, "ore": 100, "magma": 2}
	assert(game.development.research("engine"), "Normal engine research succeeds")
	assert(game.development.build(Vector2i(0, -2), "power"), "Normal power-room construction succeeds")
	assert(game.development.has_facility("power"))
	# Hold only camera/world simulation still; normal _process drives the animation.
	game.set_physics_process(false)
	game._set_view_mode(game.VIEW_FOCUS)
	game.camera_zoom = 1.5
	game.camera_zoom_target = 1.5
	game.camera_world = game.island_pos + Vector2(0, -40)
	game.context_panel.hide()
	await process_frame
	await RenderingServer.frame_post_draw
	var first := root.get_texture().get_image()
	var first_time: float = game.animation_time
	assert(first.save_png(OUTPUT + "runtime-before.png") == OK)
	await create_timer(0.35).timeout
	await RenderingServer.frame_post_draw
	var second := root.get_texture().get_image()
	assert(second.save_png(OUTPUT + "runtime-after.png") == OK)
	assert(game.animation_time > first_time, "Main scene advances animation time without a preview clock")
	var wheel_region := source_region(game, Rect2(890, 523, 252, 288))
	var roof_region := source_region(game, Rect2(640, 280, 240, 100))
	assert(first.get_region(wheel_region).get_data() != second.get_region(wheel_region).get_data(), "Constructed power-room wheel visibly animates")
	assert(first.get_region(roof_region).get_data() == second.get_region(roof_region).get_data(), "Building roof stays still")
	var result := {
		"scene": "res://main.tscn", "normal_research_and_build": true,
		"normal_process_clock": true, "elapsed_animation_seconds": game.animation_time - first_time,
		"wheel_pixels_animate": true, "roof_pixels_unchanged": true,
		"preview_renderer_used": false, "user_save_written": false,
	}
	var file := FileAccess.open(OUTPUT + "integration.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "\t"))
	file.close()
	print("ENGINE WHEEL INTEGRATION PASS: main scene, normal construction, real-time wheel motion, fixed roof")
	game.queue_free()
	await process_frame
	quit()
