extends SceneTree

func _init() -> void:
	var source := Image.load_from_file("res://assets/pixel_v2/facilities/harbor_single_tile.png")
	var cutout := Image.load_from_file("res://../artifacts/game/harbor-overlay/generated-cutout.png")
	assert(source != null and cutout != null)
	assert(source.get_size() == cutout.get_size(), "Cutout must match the master canvas")
	var result: Image = source.duplicate()
	# Use only the edited silhouette below the lower beam, never regenerated deck RGB.
	for y in range(840, source.get_height()):
		for x in range(source.get_width()):
			var color := source.get_pixel(x, y)
			color.a = minf(color.a, cutout.get_pixel(x, y).a)
			if color.a < 0.1: color = Color.TRANSPARENT
			result.set_pixel(x, y, color)
	assert(result.get_region(Rect2i(0, 0, source.get_width(), 840)).get_data() == source.get_region(Rect2i(0, 0, source.get_width(), 840)).get_data(), "Upper deck must remain byte-identical")
	for y in range(920, source.get_height()):
		for x in range(source.get_width()):
			assert(result.get_pixel(x, y).a < 0.1, "Earth and stone foundation must be transparent")
	assert(result.save_png("res://assets/pixel_v2/facilities/harbor_overlay.png") == OK)
	print("HARBOR OVERLAY: original deck pixels preserved; foundation removed")
	quit()
