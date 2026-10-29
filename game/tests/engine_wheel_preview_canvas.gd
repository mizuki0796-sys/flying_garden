extends "res://scripts/main.gd"

var baseline_mode := false
var transparent_background := false
var show_title := true
var preview_scale := 3.0
var preview_bottom_center := Vector2(240, 552)

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_load_pixel_v2_assets()
	wind_strength = 0.15

func _process(_delta: float) -> void:
	pass

func _physics_process(_delta: float) -> void:
	pass

func _unhandled_input(_event: InputEvent) -> void:
	pass

func _draw() -> void:
	if not transparent_background:
		draw_rect(Rect2(0, 0, 480, 600), Color("#a9d9d8"))
	draw_set_transform(preview_bottom_center, 0.0, Vector2.ONE * preview_scale)
	if baseline_mode:
		var size := Vector2(92.0, 92.0 * power_hut_texture.get_height() / power_hut_texture.get_width())
		var destination := Rect2(Vector2(-46, -size.y), size)
		draw_texture_rect(power_hut_texture, destination, false)
		_draw_chimney_smoke(destination.position + size * Vector2(0.88, 0.07), 0.0, true)
	else:
		_draw_building(power_hut_texture, Vector2.ZERO, 92.0, "power")
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if show_title:
		draw_string(ThemeDB.fallback_font, Vector2(20, 32), "POWER ROOM / FLYWHEEL", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color("#244d46"))
