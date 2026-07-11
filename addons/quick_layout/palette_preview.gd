@tool
extends Control
class_name QuickLayoutPalettePreview

## Tiny hand-drawn diagrams of how each container type arranges its
## children — shown in the UI Builder's info panel alongside the text
## description, for the types where a picture says more than the words do.
## Colors match the actual canvas boxes (quick_layout_canvas.gd) so the
## preview reads as "this is what you'll see," not a generic illustration.

const CHILD_FILL := Color(0.3, 0.6, 1.0, 0.22)
const CHILD_BORDER := Color(0.3, 0.6, 1.0, 0.9)
const CONTAINER_BORDER := Color(1, 1, 1, 0.35)

## Which palette types get a diagram at all — the rest have nothing
## meaningfully spatial to show (a Button/Label preview would just be a box).
const SUPPORTED_TYPES := [
	"VBoxContainer", "HBoxContainer", "GridContainer", "CenterContainer",
	"MarginContainer", "PanelContainer", "ScrollContainer",
]

var preview_type: String = "":
	set(value):
		preview_type = value
		queue_redraw()


func _ready() -> void:
	custom_minimum_size = Vector2(0, 90)
	clip_contents = true


func _draw() -> void:
	if not SUPPORTED_TYPES.has(preview_type):
		return

	var r := Rect2(Vector2(4, 4), size - Vector2(8, 8))
	if r.size.x <= 0 or r.size.y <= 0:
		return
	draw_rect(r, CONTAINER_BORDER, false, 1.0)

	match preview_type:
		"VBoxContainer":
			_draw_stack(r, true)
		"HBoxContainer":
			_draw_stack(r, false)
		"GridContainer":
			_draw_grid(r)
		"CenterContainer":
			_draw_centered(r)
		"MarginContainer":
			_draw_margin(r)
		"PanelContainer":
			_draw_panel_container(r)
		"ScrollContainer":
			_draw_scroll(r)


func _draw_box(r: Rect2) -> void:
	draw_rect(r, CHILD_FILL, true)
	draw_rect(r, CHILD_BORDER, false, 1.5)


func _draw_stack(r: Rect2, vertical: bool) -> void:
	var count := 3
	var gap := 6.0
	if vertical:
		var h := (r.size.y - gap * (count - 1)) / count
		var y := r.position.y
		for i in count:
			_draw_box(Rect2(r.position.x, y, r.size.x, h))
			y += h + gap
	else:
		var w := (r.size.x - gap * (count - 1)) / count
		var x := r.position.x
		for i in count:
			_draw_box(Rect2(x, r.position.y, w, r.size.y))
			x += w + gap


func _draw_grid(r: Rect2) -> void:
	var cols := 3
	var rows := 2
	var gap := 6.0
	var w := (r.size.x - gap * (cols - 1)) / cols
	var h := (r.size.y - gap * (rows - 1)) / rows
	for row in rows:
		for col in cols:
			var pos := r.position + Vector2(col * (w + gap), row * (h + gap))
			_draw_box(Rect2(pos, Vector2(w, h)))


func _draw_centered(r: Rect2) -> void:
	var s := Vector2(r.size.x * 0.4, r.size.y * 0.4)
	var pos := r.position + (r.size - s) / 2.0
	_draw_box(Rect2(pos, s))


func _draw_margin(r: Rect2) -> void:
	var inset := 10.0
	_draw_box(Rect2(r.position + Vector2(inset, inset), r.size - Vector2(inset, inset) * 2))


func _draw_panel_container(r: Rect2) -> void:
	var inset := 6.0
	draw_rect(r, Color(1, 1, 1, 0.06), true)
	_draw_box(Rect2(r.position + Vector2(inset, inset), r.size - Vector2(inset, inset) * 2))


func _draw_scroll(r: Rect2) -> void:
	# A stack taller than the frame, clipped by clip_contents, plus a
	# scrollbar hint — suggests "more content than fits, scroll for it."
	var count := 4
	var gap := 6.0
	var h := (r.size.y - gap) / 1.8
	var y := r.position.y
	for i in count:
		_draw_box(Rect2(r.position.x, y, r.size.x - 6.0, h))
		y += h + gap
	draw_rect(Rect2(r.position.x + r.size.x - 3, r.position.y, 3, r.size.y * 0.4), Color(1, 1, 1, 0.5), true)
