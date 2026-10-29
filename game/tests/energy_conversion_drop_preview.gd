extends SceneTree
const Component = preload("res://art_templates/complex_ui/energy_conversion_drop.gd")
const OUTPUT := "res://../artifacts/game/energy-conversion-warm/"
func _init() -> void:
	call_deferred("run")
func run() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1536, 1024)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var sprite := Component.new()
	sprite.animate = false
	viewport.add_child(sprite)
	await process_frame
	await RenderingServer.frame_post_draw
	var baseline := viewport.get_texture().get_image()
	baseline.save_png(OUTPUT + "energy-conversion-connected.png")
	# Validate against the actual base-only renderer, avoiding color-space conversion assumptions.
	var base_only := Sprite2D.new()
	base_only.texture = sprite.base_texture
	base_only.centered = false
	viewport.add_child(base_only)
	sprite.hide()
	await process_frame
	await RenderingServer.frame_post_draw
	var original := viewport.get_texture().get_image()
	for y in range(1024):
		for x in range(1536):
			if not Component.PATCH.has_point(Vector2(x,y)):
				assert(original.get_pixel(x,y) == baseline.get_pixel(x,y), "Outside connector changed")
	base_only.queue_free()
	sprite.show()
	var changed := false
	for frame in range(32):
		sprite.time = float(frame) / 20.0
		sprite.queue_redraw()
		await process_frame
		await RenderingServer.frame_post_draw
		var current := viewport.get_texture().get_image()
		# Byte-level outside-scope comparison, with authorized reagent region normalized.
		var checked := current.duplicate()
		checked.blit_rect(baseline, Rect2i(1042, 691, 18, 44), Vector2i(1042, 691))
		assert(checked.get_data() == baseline.get_data(), "Animation escaped glass tube")
		if current.get_data() != baseline.get_data(): changed = true
		current.save_png(OUTPUT + "frames/frame-%03d.png" % frame)
	assert(changed, "Reagent must visibly animate")
	sprite.time = Component.PERIOD
	sprite.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	assert(viewport.get_texture().get_image().get_data() == baseline.get_data(), "Loop must return exactly")
	print("ENERGY CONVERSION: connector scope verified; 32 frames confined to glass tube; exact 1.6s loop")
	quit()
