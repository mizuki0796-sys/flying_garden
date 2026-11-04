extends SceneTree

const REGIONS := [Rect2i(145, 470, 180, 380), Rect2i(1077, 470, 180, 380)]

func _init() -> void:
	var source := Image.load_from_file("res://assets/pixel_v2/vehicles/collector_single_tile.png")
	var edited := Image.load_from_file("res://../artifacts/game/collector-thrusters/generated-edit.png")
	assert(source != null and edited != null)
	assert(source.get_size() == Vector2i(1402, 1122) and edited.get_size() == source.get_size())
	source.convert(Image.FORMAT_RGBA8)
	edited.convert(Image.FORMAT_RGBA8)
	var result: Image = source.duplicate()
	for region in REGIONS:
		result.blit_rect(edited, region, region.position)
		assert(result.get_region(region).get_data() != source.get_region(region).get_data(), "Both propulsion assemblies must change")
	var protected_source: Image = source.duplicate()
	var protected_result: Image = result.duplicate()
	for region in REGIONS:
		protected_source.fill_rect(region, Color.TRANSPARENT)
		protected_result.fill_rect(region, Color.TRANSPARENT)
	assert(protected_result.get_data() == protected_source.get_data(), "All pixels outside propulsion assemblies must remain identical")
	assert(result.get_pixel(0, 0).a == 0.0, "Preserve transparent canvas")
	assert(result.save_png("res://assets/pixel_v2/vehicles/collector_thrusters.png") == OK)
	print("COLLECTOR THRUSTERS: both pods replaced; all pixels outside side regions unchanged; alpha PASS")
	quit()
