@tool
extends Control
class_name QuickLayoutRuler

## Pixel-tick ruler strip for one edge of the UI Builder canvas — a thin
## Control drawn along its top or left, showing target-space coordinates
## (not raw canvas pixels) so the numbers mean the same thing as the
## position/size values you'd see in the Inspector.

enum Orientation { HORIZONTAL, VERTICAL }

## "Nice" round tick spacings to choose from, in target-space pixels.
const NICE_STEPS := [10.0, 20.0, 25.0, 50.0, 100.0, 200.0, 250.0, 500.0, 1000.0]
const MIN_TICK_SPACING := 40.0
const TICK_COLOR := Color(1, 1, 1, 0.4)
const LABEL_COLOR := Color(1, 1, 1, 0.6)
const BG_COLOR := Color(1, 1, 1, 0.03)

## Typed int, not Orientation: Godot 4.7's GDScript type checker treats a
## class_name script's own nested enum, referenced by bare name, as an
## "external" qualified type that doesn't unify with itself — same reason
## quick_layout_canvas.gd types _resize_handle as int rather than
## ResizeHandle. Using Orientation directly here fails to parse.
var orientation: int = Orientation.HORIZONTAL
var canvas: QuickLayoutCanvas = null


func _ready() -> void:
	clip_contents = true
	resized.connect(queue_redraw)


func _pick_step(ratio_component: float) -> float:
	if ratio_component <= 0:
		return NICE_STEPS[-1]
	for step in NICE_STEPS:
		if step * ratio_component >= MIN_TICK_SPACING:
			return step
	return NICE_STEPS[-1]


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BG_COLOR, true)
	if canvas == null:
		return

	var ratio := canvas.get_target_to_canvas_ratio()
	var font := ThemeDB.fallback_font

	if orientation == Orientation.HORIZONTAL:
		if ratio.x <= 0:
			return
		var step := _pick_step(ratio.x)
		var max_target: float = size.x / ratio.x
		var t := 0.0
		while t <= max_target:
			var x := t * ratio.x
			draw_line(Vector2(x, size.y - 7), Vector2(x, size.y), TICK_COLOR, 1.0)
			draw_string(font, Vector2(x + 2, size.y - 9), str(int(t)), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, LABEL_COLOR)
			t += step
	else:
		if ratio.y <= 0:
			return
		var step := _pick_step(ratio.y)
		var max_target: float = size.y / ratio.y
		var t := 0.0
		while t <= max_target:
			var y := t * ratio.y
			draw_line(Vector2(size.x - 7, y), Vector2(size.x, y), TICK_COLOR, 1.0)
			draw_string(font, Vector2(2, y - 2), str(int(t)), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, LABEL_COLOR)
			t += step
