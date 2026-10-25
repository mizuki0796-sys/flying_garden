extends Control

# Sky-glass resting on a narrow moss-and-stone floating-island ledge.
# This is decoration only; the existing HUD owns all input and layout.
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func _draw() -> void:
	var width := size.x
	var face := Rect2(0, 0, width, 70)
	var plate := StyleBoxFlat.new()
	plate.bg_color = Color("#e6f0df")
	plate.border_color = Color("#527b71")
	plate.set_border_width_all(2)
	plate.set_corner_radius_all(12)
	plate.shadow_color = Color(0.17, 0.30, 0.31, 0.22)
	plate.shadow_size = 5
	plate.shadow_offset = Vector2(1, 5)
	draw_style_box(plate, face)

	# A distinct sky-blue weather canvas at the left; light enough for red and
	# green effects to stay legible in every weather state.
	var weather := StyleBoxFlat.new()
	weather.bg_color = Color("#d0e8e4")
	weather.set_corner_radius_all(9)
	draw_style_box(weather, Rect2(5, 5, 191, 59))
	draw_line(Vector2(201, 12), Vector2(201, 58), Color("#a6c6b4"), 1.0)
	draw_line(Vector2(width - 188, 15), Vector2(width - 188, 55), Color("#b4cbb6"), 1.0)

	# Keep the clouds along the rim, away from the central line of numbers.
	_cloud(Vector2(152, 14), 0.65, 0.32)
	_cloud(Vector2(326, 13), 0.80, 0.40)
	_cloud(Vector2(576, 60), 1.10, 0.38)
	_cloud(Vector2(width - 244, 12), 0.88, 0.38)
	_cloud(Vector2(width - 40, 60), 0.70, 0.32)
	draw_line(Vector2(17, 5), Vector2(width - 17, 5), Color(1.0, 1.0, 0.89, 0.70), 1.0)

	# A shallow stepped cliff gives the strip a floating silhouette without
	# taking another row away from the game world.
	var cliff := PackedVector2Array([Vector2(12, 70), Vector2(width - 12, 70), Vector2(width - 16, 77)])
	for index in range(28, -1, -1):
		var x := lerpf(17.0, width - 17.0, float(index) / 28.0)
		cliff.append(Vector2(x, 76.0 + float(posmod(index * 7, 4))))
	cliff.append(Vector2(12, 73))
	draw_colored_polygon(cliff, Color("#739184"))
	draw_line(Vector2(14, 70), Vector2(width - 14, 70), Color("#739e65"), 3.0)
	draw_line(Vector2(17, 69), Vector2(width - 17, 69), Color("#bdd694"), 1.0)
	for index in range(37):
		var x := 22.0 + index * (width - 44.0) / 37.0
		draw_rect(Rect2(x, 73, 9 + posmod(index, 3) * 3, 2), Color("#abc1a6"))
	for x in [28.0, 190.0, width - 194.0, width - 25.0]:
		_vine(Vector2(x, 71))


func _cloud(center: Vector2, scale_value: float, opacity: float) -> void:
	var shape := PackedVector2Array([
		Vector2(-27, 4), Vector2(-27, -1), Vector2(-22, -6),
		Vector2(-14, -6), Vector2(-10, -13), Vector2(1, -13),
		Vector2(7, -7), Vector2(16, -7), Vector2(21, -2),
		Vector2(27, -2), Vector2(31, 3), Vector2(27, 7), Vector2(-23, 7)])
	var points := PackedVector2Array()
	for point in shape: points.append(center + point * scale_value)
	draw_colored_polygon(points, Color(1.0, 1.0, 0.96, opacity))


func _vine(origin: Vector2) -> void:
	draw_line(origin, origin + Vector2(1, 10), Color("#587e5d"), 1.5)
	draw_colored_polygon(PackedVector2Array([origin + Vector2(1, 5), origin + Vector2(-5, 1), origin + Vector2(-5, 6)]), Color("#93b977"))
	draw_colored_polygon(PackedVector2Array([origin + Vector2(1, 9), origin + Vector2(7, 4), origin + Vector2(6, 10)]), Color("#769f66"))
