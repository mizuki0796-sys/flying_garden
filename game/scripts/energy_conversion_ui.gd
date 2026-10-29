extends Node2D
# Shared renderer for the standalone UI element and the in-game energy factory.
const SOURCE := "res://assets/ui/elements/energy_conversion_room_orange.png"
const PERIOD := 1.8
const GAME_REGION := Rect2(288, 16, 960, 960)
const CHANGE_RECT := Rect2i(1040, 654, 32, 138)
const COLLAR := Rect2i(1010, 691, 105, 29)
@export var playing := true
var time := 0.0
var texture: Texture2D
func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	texture = ImageTexture.create_from_image(Image.load_from_file(ProjectSettings.globalize_path(SOURCE)))
func _process(delta: float) -> void:
	if playing:
		time += delta
		queue_redraw()
func _draw() -> void:
	if texture != null: draw_element(self, texture, Rect2(0, 0, 1536, 1024), time)
static func draw_element(canvas: Node2D, source_texture: Texture2D, destination: Rect2, sample_time: float, region := Rect2(0, 0, 1536, 1024)) -> void:
	canvas.draw_texture_rect_region(source_texture, destination, region)
	var phase := fposmod(sample_time, PERIOD)
	if phase < 0.15 or phase >= 1.15: return
	var y := 657.0
	var h := 8.0
	if phase < 0.5:
		h = 8 + floor((phase - 0.15) / 0.35 * 2) * 4
	else:
		var t := clampf((phase - 0.5) / 0.6, 0.0, 1.0)
		y = 657 + floor(t * t * 120 / 4) * 4
		h = 16
	var bottom := minf(y + h, 790)
	_draw_liquid(canvas, Rect2(1048, y, 8, minf(4, bottom - y)), Color("#8fcd12"), destination, region)
	if bottom > y + 4:
		_draw_liquid(canvas, Rect2(1044, y + 4, 20, bottom - y - 4), Color("#8fcd12"), destination, region)
		_draw_liquid(canvas, Rect2(1044, y + 4, 8, minf(4, bottom - y - 4)), Color("#d5f664"), destination, region)
static func _draw_liquid(canvas: Node2D, rect: Rect2, color: Color, destination: Rect2, region: Rect2) -> void:
	for bounds in [Rect2(1040, 654, 32, 37), Rect2(1040, 720, 32, 72)]:
		var visible := rect.intersection(bounds)
		if visible.has_area():
			var factor := destination.size / region.size
			canvas.draw_rect(Rect2(destination.position + (visible.position - region.position) * factor, visible.size * factor), color)
