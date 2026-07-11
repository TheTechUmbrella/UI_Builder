@tool
extends Button
class_name QuickLayoutPaletteButton

## The Control class name this button spawns, e.g. "Button", "VBoxContainer".
var control_type: String = ""


func _get_drag_data(_at_position: Vector2) -> Variant:
	var preview := Label.new()
	preview.text = control_type
	preview.add_theme_color_override("font_color", Color(1, 1, 1))
	preview.modulate = Color(1, 1, 1, 0.85)
	set_drag_preview(preview)
	return {"quick_layout_type": control_type}
