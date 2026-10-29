extends Node2D
# Standalone sprite component. Only connector overlay and reagent are dynamic-scope pixels.
const BASE := "res://../artifacts/game/energy-conversion-warm/generated.png"
const CONNECTOR := "res://../artifacts/game/energy-conversion-warm/connected-source.png"
const PATCH := Rect2(1000, 610, 110, 150)
const LIQUID := Rect2(1042, 691, 18, 44)
const PERIOD := 1.6
var time := 0.0
var animate := true
var base_texture: Texture2D
var connector_texture: Texture2D
func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	base_texture = ImageTexture.create_from_image(Image.load_from_file(ProjectSettings.globalize_path(BASE)))
	connector_texture = ImageTexture.create_from_image(Image.load_from_file(ProjectSettings.globalize_path(CONNECTOR)))
func _process(delta: float) -> void:
	if animate:
		time += delta
		queue_redraw()
func _draw() -> void:
	draw_texture(base_texture, Vector2.ZERO)
	# Overlay ONLY the authorized connection; retain the original reservoir and bracket.
	draw_texture_rect_region(connector_texture, PATCH, PATCH)
	var phase := fposmod(time, PERIOD) / PERIOD
	if phase < 0.22 or phase >= 0.72: return
	var travel := (phase - 0.22) / 0.5
	var y := 691 + int(floor(travel * 4.0)) * 8
	# Hard-edged reagent slug descends inside the fixed glass tube; no splash or glow.
	draw_rect(Rect2(1044, y, 14, 10), Color("#8cce0b"))
	draw_rect(Rect2(1044, y, 5, 5), Color("#d7f65c"))
