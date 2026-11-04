extends SceneTree

const HOLD := Rect2i(438, 334, 528, 480)

func _init() -> void:
	var full := Image.load_from_file("res://assets/pixel_v2/vehicles/collector_box_depth.png")
	var empty := Image.load_from_file("res://../artifacts/game/collector-states/generated-empty.png")
	assert(full != null and empty != null and full.get_size() == empty.get_size())
	full.convert(Image.FORMAT_RGBA8)
	empty.convert(Image.FORMAT_RGBA8)
	for state in ["empty", "partial"]:
		var result: Image = full.duplicate()
		var region := HOLD if state == "empty" else Rect2i(702, 334, 264, 480)
		result.blit_rect(empty, region, region.position)
		var protected: Image = result.duplicate()
		protected.blit_rect(full, HOLD, HOLD.position)
		assert(protected.get_data() == full.get_data(), "Outside cargo hold must be byte-identical")
		assert(result.get_region(HOLD).get_data() != full.get_region(HOLD).get_data())
		assert(result.save_png("res://assets/pixel_v2/vehicles/collector_cargo_%s.png" % state) == OK)
	print("CARGO ASSETS: empty/partial created; protected pixels PASS")
	quit()
