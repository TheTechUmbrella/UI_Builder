@tool
extends Control

const AlignTools = preload("res://addons/quick_layout/align_tools.gd")
const PRESETS_DIR := "res://addons/quick_layout/presets/"

var _editor_interface: EditorInterface
var _undo_redo: EditorUndoRedoManager

var _grid_spin: SpinBox
var _preset_option: OptionButton
var _status_label: Label
var _preset_paths: Array[String] = []
var _anchor_aware_check: CheckBox


func setup(editor_interface: EditorInterface, undo_redo: EditorUndoRedoManager) -> void:
	_editor_interface = editor_interface
	_undo_redo = undo_redo
	_build_ui()
	_refresh_presets()
	_editor_interface.get_selection().selection_changed.connect(_on_selection_changed)
	_on_selection_changed()


func _build_ui() -> void:
	custom_minimum_size = Vector2(0, 0)
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	root.add_child(_section_label("Align (relative to first selected)"))
	_anchor_aware_check = CheckBox.new()
	_anchor_aware_check.text = "Anchor-aware (also Distribute)"
	_anchor_aware_check.tooltip_text = "Sync anchors between controls before aligning/distributing them, so the result stays correct if the parent is resized later — not just at the moment you click. Only applies to point-anchored controls (not ones that stretch with their parent)."
	root.add_child(_anchor_aware_check)
	var align_grid := GridContainer.new()
	align_grid.columns = 3
	root.add_child(align_grid)
	align_grid.add_child(_button("Left", func(): _do_align("left")))
	align_grid.add_child(_button("Center H", func(): _do_align("h_center")))
	align_grid.add_child(_button("Right", func(): _do_align("right")))
	align_grid.add_child(_button("Top", func(): _do_align("top")))
	align_grid.add_child(_button("Center V", func(): _do_align("v_center")))
	align_grid.add_child(_button("Bottom", func(): _do_align("bottom")))

	root.add_child(HSeparator.new())
	root.add_child(_section_label("Distribute (3+ selected)"))
	var dist_row := HBoxContainer.new()
	root.add_child(dist_row)
	dist_row.add_child(_button("Horizontal", func(): _do_distribute("horizontal")))
	dist_row.add_child(_button("Vertical", func(): _do_distribute("vertical")))

	root.add_child(HSeparator.new())
	root.add_child(_section_label("Match Size"))
	var size_row := HBoxContainer.new()
	root.add_child(size_row)
	size_row.add_child(_button("Width", func(): _do_match_size("width")))
	size_row.add_child(_button("Height", func(): _do_match_size("height")))
	size_row.add_child(_button("Both", func(): _do_match_size("both")))

	root.add_child(HSeparator.new())
	root.add_child(_section_label("Grid Snap"))
	var grid_row := HBoxContainer.new()
	root.add_child(grid_row)
	_grid_spin = SpinBox.new()
	_grid_spin.min_value = 1
	_grid_spin.max_value = 256
	_grid_spin.value = 8
	_grid_spin.custom_minimum_size = Vector2(70, 0)
	grid_row.add_child(_grid_spin)
	grid_row.add_child(_button("Snap Selected", func(): _do_snap()))

	root.add_child(HSeparator.new())
	root.add_child(_section_label("Theme Preset"))
	var theme_row := HBoxContainer.new()
	root.add_child(theme_row)
	_preset_option = OptionButton.new()
	_preset_option.custom_minimum_size = Vector2(140, 0)
	theme_row.add_child(_preset_option)
	theme_row.add_child(_button("Apply", func(): _do_apply_theme()))
	var refresh_btn := _button("Refresh", func(): _refresh_presets())
	theme_row.add_child(refresh_btn)

	root.add_child(HSeparator.new())
	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	root.add_child(_status_label)


func _section_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 12)
	return l


func _button(text: String, callback: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(callback)
	return b


func _selected_controls() -> Array:
	var result: Array = []
	for n in _editor_interface.get_selection().get_selected_nodes():
		if n is Control:
			result.append(n)
	return result


func _on_selection_changed() -> void:
	var count := _selected_controls().size()
	if _status_label:
		_status_label.text = "%d Control node(s) selected." % count


func _do_align(edge: String) -> void:
	var controls := _selected_controls()
	if controls.size() < 2:
		_status_label.text = "Select at least 2 Control nodes to align."
		return
	AlignTools.align(controls, edge, _undo_redo, _anchor_aware_check.button_pressed)


func _do_distribute(axis: String) -> void:
	var controls := _selected_controls()
	if controls.size() < 3:
		_status_label.text = "Select at least 3 Control nodes to distribute."
		return
	AlignTools.distribute(controls, axis, _undo_redo, _anchor_aware_check.button_pressed)


func _do_match_size(dimension: String) -> void:
	var controls := _selected_controls()
	if controls.size() < 2:
		_status_label.text = "Select at least 2 Control nodes to match size."
		return
	AlignTools.match_size(controls, dimension, _undo_redo)


func _do_snap() -> void:
	var controls := _selected_controls()
	if controls.is_empty():
		_status_label.text = "Select at least 1 Control node to snap."
		return
	var g := Vector2(_grid_spin.value, _grid_spin.value)
	AlignTools.snap_to_grid(controls, g, _undo_redo)


func _refresh_presets() -> void:
	_preset_paths.clear()
	_preset_option.clear()
	var dir := DirAccess.open(PRESETS_DIR)
	if dir == null:
		_status_label.text = "No presets/ folder found."
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.ends_with(".tres") or file_name.ends_with(".res"):
			_preset_paths.append(PRESETS_DIR + file_name)
			_preset_option.add_item(file_name.get_basename())
		file_name = dir.get_next()
	dir.list_dir_end()
	if _preset_paths.is_empty():
		_status_label.text = "No .tres Theme resources in presets/."


func _do_apply_theme() -> void:
	if _preset_option.selected < 0 or _preset_option.selected >= _preset_paths.size():
		_status_label.text = "No theme preset selected."
		return
	var controls := _selected_controls()
	if controls.is_empty():
		_status_label.text = "Select at least 1 Control node to apply a theme."
		return
	var path := _preset_paths[_preset_option.selected]
	var theme_res := load(path)
	if not (theme_res is Theme):
		_status_label.text = "Selected resource is not a Theme."
		return

	_undo_redo.create_action("Quick Layout: Apply Theme Preset")
	for c in controls:
		var ctrl: Control = c
		_undo_redo.add_do_property(ctrl, "theme", theme_res)
		_undo_redo.add_undo_property(ctrl, "theme", ctrl.theme)
	_undo_redo.commit_action()
