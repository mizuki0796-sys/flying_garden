extends Sprite2D

const SOURCE := "res://assets/pixel_v2/vehicles/collector_single_tile.png"
const SHADER = preload("res://art_templates/complex_ui/collector_propellers.gdshader")
const LEFT_REGION := Rect2i(125, 440, 245, 420)
const RIGHT_REGION := Rect2i(1032, 440, 245, 420)
const SOURCE_CENTER := Vector2(701, 585)
const LEFT_HUB := Vector2(246, 646)
const RIGHT_HUB := Vector2(1156, 646)
const PERIOD := 0.8
const MAX_SIZE := Vector2(80, 64)
const BLADE_OUTLINE := [
	Vector2(215, 497), Vector2(248, 497), Vector2(269, 530),
	Vector2(269, 574), Vector2(257, 602), Vector2(246, 646),
	Vector2(223, 610), Vector2(184, 580), Vector2(177, 550), Vector2(183, 532),
]
const HUB := [
	Vector2(225, 612), Vector2(262, 612), Vector2(283, 631),
	Vector2(283, 663), Vector2(262, 684), Vector2(222, 684),
	Vector2(200, 664), Vector2(200, 632),
]
var parts_mask: Image
var blade_image: Image
var source: Image
var elapsed := 0.0

func _ready() -> void:
	source = preload("res://assets/pixel_v2/vehicles/collector_single_tile.png").get_image()
	assert(source != null and source.get_size() == Vector2i(1402, 1122), "Rotor coordinates require the single-cell master")
	texture = ImageTexture.create_from_image(source)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	parts_mask = Image.create(1402, 1122, false, Image.FORMAT_RGBA8)
	blade_image = Image.create(1402, 1122, false, Image.FORMAT_RGBA8)
	var hub_polygon := PackedVector2Array(HUB)
	var blade_polygon := PackedVector2Array(BLADE_OUTLINE)
	for region in [LEFT_REGION, RIGHT_REGION]:
		for y in range(region.position.y, region.end.y):
			for x in range(region.position.x, region.end.x):
				var point := Vector2(x + 0.5 if x < 701 else 1401.5 - x, y + 0.5)
				var in_foreground := Geometry2D.is_point_in_polygon(point, hub_polygon) or Rect2(270, 595, 110, 110).has_point(point)
				var protected := in_foreground and source.get_pixel(x, y).a > 0.5
				var blade := Geometry2D.is_point_in_polygon(point, blade_polygon)
				var erase := not protected and Rect2(160, 480, 125, 335).has_point(point)
				parts_mask.set_pixel(x, y, Color(1.0 if blade else 0.0, 1.0 if protected else 0.0, 1.0 if erase else 0.0, 1))
				if blade:
					var color := source.get_pixel(x, y)
					# Continue wood to the axle behind the fixed cap; never rotate its cutout.
					if y >= 606:
						color = source.get_pixel(233 if x < 701 else 1168, 575)
					elif color.a <= 0.5:
						color = Color("#39251f")
					color.a = 1.0
					blade_image.set_pixel(x, y, color)
	var effect := ShaderMaterial.new()
	effect.shader = SHADER
	effect.set_shader_parameter("parts_mask", ImageTexture.create_from_image(parts_mask))
	effect.set_shader_parameter("blade_texture", ImageTexture.create_from_image(blade_image))
	material = effect
	region_enabled = true
	region_rect = Rect2(120, 140, 1162, 890)
	scale = Vector2.ONE * minf(MAX_SIZE.x / region_rect.size.x, MAX_SIZE.y / region_rect.size.y)
	set_time(0.0)

func set_time(seconds: float) -> void:
	elapsed = seconds
	material.set_shader_parameter("angle", fposmod(seconds, PERIOD) / PERIOD * TAU)

func _process(delta: float) -> void:
	set_time(elapsed + delta)
