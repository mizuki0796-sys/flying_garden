extends SceneTree
const Component = preload("res://scripts/energy_conversion_ui.gd")
const OUTPUT := "res://../artifacts/game/reagent-drip/"
func _init() -> void:
	call_deferred("run")
func run() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1536, 1024)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var sprite := Component.new()
	sprite.playing = false
	viewport.add_child(sprite)
	await process_frame
	await RenderingServer.frame_post_draw
	var baseline := viewport.get_texture().get_image()
	var changes := 0
	for frame in range(36):
		sprite.time = float(frame) / 20.0
		sprite.queue_redraw()
		await process_frame
		await RenderingServer.frame_post_draw
		var current := viewport.get_texture().get_image()
		var checked := current.duplicate()
		checked.blit_rect(baseline, Component.CHANGE_RECT, Component.CHANGE_RECT.position)
		assert(checked.get_data() == baseline.get_data(), "Pixels outside reagent changed")
		assert(current.get_region(Component.COLLAR).get_data() == baseline.get_region(Component.COLLAR).get_data(), "Copper collar changed")
		if current.get_data() != baseline.get_data(): changes += 1
		current.save_png(OUTPUT + "frames/frame-%03d.png" % frame)
	assert(changes > 5)
	sprite.time = Component.PERIOD
	sprite.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	assert(viewport.get_texture().get_image().get_data() == baseline.get_data())
	print("REAGENT DRIP: 36 frames; outside scope + collar unchanged; exact loop; %d moving frames" % changes)
	quit()
