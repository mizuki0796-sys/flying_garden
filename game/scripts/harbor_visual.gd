extends RefCounted

const SOURCE = preload("res://assets/pixel_v2/facilities/harbor_special_tile.png")
var texture: Texture2D

static func outward(cell: Vector2i, tiles: Array) -> Vector2i:
	var preferred := Vector2i(signi(cell.x), 0) if absi(cell.x) > absi(cell.y) else Vector2i(0, signi(cell.y))
	for direction in [preferred, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]:
		if direction == Vector2i.ZERO: continue
		var occupied := false
		for tile in tiles:
			if tile.cell == cell + direction: occupied = true; break
		if not occupied: return direction
	return Vector2i.UP

func draw(canvas: Node2D, center: Vector2, _direction: Vector2i) -> void:
	if texture == null:
		var image := SOURCE.get_image().get_region(Rect2i(64, 64, 1280, 992))
		# Four-sided mooring keeps the anchor upright and the light fixed at upper left.
		image.resize(80, 64, Image.INTERPOLATE_NEAREST)
		texture = ImageTexture.create_from_image(image)
	# Project the deck onto the ground; reuse its front edge for thickness.
	canvas.draw_texture_rect_region(texture, Rect2(center + Vector2(-40, 22), Vector2(80, 4)), Rect2(0, 59, 80, 5), Color(0.72, 0.72, 0.72))
	canvas.draw_texture_rect(texture, Rect2(center - Vector2(40, 30), Vector2(80, 52)), false)
