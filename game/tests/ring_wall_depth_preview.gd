extends SceneTree

const Ring = preload("res://scripts/ring_wall.gd")
const OUT := "res://../artifacts/game/wall-block-depth/"
var game

func _init() -> void:
	call_deferred("run")

func capture(label: String) -> void:
	game.queue_redraw()
	for i in range(4):
		await process_frame
		await RenderingServer.frame_post_draw
	var image: Image = game.wall.viewport.get_texture().get_image()
	assert(image.save_png(OUT + label + ".png") == OK)

func run() -> void:
	assert(DisplayServer.get_name() != "headless")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game._start_demo()
	game.set_process(false)
	game.set_physics_process(false)
	var origin: Vector2 = game.wall.ring_center()
	game.camera_world = origin + Vector2(10007.5, 1.5) * Ring.SIZE
	game.camera_zoom = 0.85
	# A continuous front edge, five isolated blocks and a continuous back edge.
	for y in range(4):
		for x in range(10000, 10015):
			if y == 2 and x in [10001, 10006, 10010, 10012, 10014]: continue
			game.wall.hp_left[Vector2i(x, y)] = 0.0
	game.wall.mask_dirty = true
	var label := "after" if OS.get_cmdline_user_args().is_empty() else OS.get_cmdline_user_args()[0]
	await capture(label)
	game.camera_world = origin + Vector2(0,-10000) * Ring.SIZE
	game.camera_zoom = 1.0
	await capture(label + "-north")
	quit()
