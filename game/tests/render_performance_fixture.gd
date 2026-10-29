extends "res://scripts/main.gd"

# Same island/plot/building functions as play, with wall-clock sky and badges
# excluded ONLY for deterministic pixel comparisons.
var isolate_island := false
var test_pointer := Vector2.INF

func _tree_pointer() -> Vector2:
	return test_pointer if isolate_island else super._tree_pointer()

func _draw() -> void:
	if not isolate_island:
		super._draw()
		return
	material = crop_renderer.material if optimized_rendering else null
	crop_renderer.begin_frame(animation_time, wind_strength)
	draw_set_transform(VIEW_CENTER - camera_world * camera_zoom, 0.0, Vector2(camera_zoom, camera_zoom))
	_draw_island()
	draw_set_transform(Vector2.ZERO)
	crop_renderer.end_frame()

func configure(count: int, mature := true) -> void:
	island_tiles = []
	plots = []
	var columns := ceili(sqrt(float(count)))
	var rows := ceili(float(count) / columns)
	for i in range(count):
		var cell := Vector2i(i % columns - columns / 2, i / columns - rows / 2)
		var kind := "grass"
		var facility := ""
		var pattern := i % 10
		if pattern < 4: kind = "farm"
		elif pattern == 4: kind = "tree"
		elif pattern == 5: kind = "rock"
		elif pattern == 6: kind = "sand"
		elif pattern == 7: kind = "gold"
		elif pattern == 8: kind = "lava"
		if i in [9, 19, 29, 39, 49]: facility = ["power", "water", "grapple", "farm_hut", "energy"][i / 10]
		island_tiles.append({"cell": cell, "kind": kind, "facility": facility, "level": 1, "hp": 100.0, "depleted": false})
		if kind == "farm":
			plots.append({"cell": cell, "state": 2 if mature else 0, "progress": 1.0 if mature else 0.0, "crop_type": i % 2, "weather_penalty": 1.0})
	development.sync()
	selected_tool = TOOL_HOOK
	hovered_plot = -1
	selected_plot = -1
	camera_zoom = _god_zoom_limit()
	camera_zoom_target = camera_zoom
	camera_world = island_pos + _island_visual_bounds().get_center()
	energy = energy_capacity
	rice_seeds = 1000
	tomato_seeds = 1000
	day_minutes = 600.0
	current_weather = -1
	weather_tint = 0.0
	wind_strength = 0.34
	animation_time = 2.35
	_update_hud()
