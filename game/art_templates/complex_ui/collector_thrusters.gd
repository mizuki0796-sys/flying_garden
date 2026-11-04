extends Sprite2D

var cargo_textures: Array[Texture2D] = []

func _ready() -> void:
	for source in [preload("res://assets/pixel_v2/vehicles/collector_cargo_empty.png"), preload("res://assets/pixel_v2/vehicles/collector_cargo_partial.png"), preload("res://assets/pixel_v2/vehicles/collector_box_depth.png")]:
		var image: Image = source.get_image().get_region(Rect2i(154, 128, 1094, 896))
		image.resize(80, 64, Image.INTERPOLATE_NEAREST)
		cargo_textures.append(ImageTexture.create_from_image(image))
	set_cargo_state(0)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

func set_cargo_state(state: int) -> void:
	texture = cargo_textures[state]
