@tool
extends Control

const QuickLayoutCanvas = preload("res://addons/quick_layout/quick_layout_canvas.gd")
const QuickLayoutPaletteButton = preload("res://addons/quick_layout/palette_button.gd")
const QuickLayoutPalettePreview = preload("res://addons/quick_layout/palette_preview.gd")
const QuickLayoutRuler = preload("res://addons/quick_layout/ruler.gd")

const RULER_THICKNESS := 18.0

const TEMPLATES_DIR := "res://addons/quick_layout/templates/"

const PALETTE_TYPES := [
	"Control", "Panel", "PanelContainer", "VBoxContainer", "HBoxContainer",
	"GridContainer", "MarginContainer", "CenterContainer", "ScrollContainer",
	"Label", "Button", "LineEdit", "TextEdit", "CheckBox", "CheckButton",
	"ProgressBar", "TextureRect", "ColorRect", "RichTextLabel", "ItemList",
]

const TYPE_DESCRIPTIONS := {
	"Control": "The base UI node — invisible and unstyled by itself, doesn't auto-arrange children. Useful as a generic spacer or a plain positioning box (set its Custom Min Size to make a fixed-size spacer).",
	"Panel": "A plain background panel. Useful as a visual backdrop or grouping box; does not auto-arrange its children.",
	"PanelContainer": "Like Panel, but automatically sizes itself to fit a single child with padding — handy for a bordered wrapper around one control.",
	"VBoxContainer": "Stacks its children vertically, one below the other, evenly spaced.",
	"HBoxContainer": "Stacks its children horizontally, side by side.",
	"GridContainer": "Arranges children into a grid with a fixed number of columns, wrapping to new rows automatically.",
	"MarginContainer": "Adds margin/padding around a single child — commonly used to inset content from a panel's edges.",
	"CenterContainer": "Centers a single child both horizontally and vertically within itself.",
	"ScrollContainer": "Clips its content and adds scrollbars when the child is larger than the container — use for long lists or forms.",
	"Label": "Displays a single line (or wrapped block) of static text.",
	"Button": "A clickable push-button with a text label; connect its 'pressed' signal to trigger an action.",
	"LineEdit": "A single-line editable text field for user text input.",
	"TextEdit": "A multi-line editable text box for longer user input.",
	"CheckBox": "A toggleable checkbox with a text label, for boolean on/off options.",
	"CheckButton": "Like CheckBox, but styled as an iOS-style toggle switch.",
	"ProgressBar": "Shows a horizontal fill bar representing progress from a min to a max value.",
	"TextureRect": "Displays a Texture2D image; supports stretch modes like scale, tile, or keep-aspect.",
	"ColorRect": "A simple solid-color rectangle — useful as a placeholder or background swatch.",
	"RichTextLabel": "Displays text with BBCode-style formatting (bold, color, links, etc.) and optional scrolling.",
	"ItemList": "A scrollable list of selectable text/icon items.",
}

var _editor_interface: EditorInterface
var _undo_redo: EditorUndoRedoManager
var _canvas: QuickLayoutCanvas
var _top_ruler: QuickLayoutRuler
var _left_ruler: QuickLayoutRuler
var _target_label: Label
var _refresh_timer: Timer
var _snap_check: CheckButton
var _grid_spin: SpinBox
var _viewport_frame_check: CheckButton
var _info_title: Label
var _info_desc: Label
var _info_preview: QuickLayoutPalettePreview
var _template_option: OptionButton
var _template_paths: Array[String] = []
var _min_size_width_spin: SpinBox
var _min_size_height_spin: SpinBox
var _name_edit: LineEdit
var _separation_row: HBoxContainer
var _separation_spin: SpinBox
## The node whose editable fields (Name, Custom Min Size, Separation) are
## currently shown — set on selection change only, not on hover, so a quick
## mouse pass over other boxes can't clobber an in-progress edit.
var _info_target_node: Control = null
var _updating_min_size_ui: bool = false


func setup(editor_interface: EditorInterface, undo_redo: EditorUndoRedoManager) -> void:
	_editor_interface = editor_interface
	_undo_redo = undo_redo
	_build_ui()
	_editor_interface.get_selection().selection_changed.connect(_on_selection_changed)
	_auto_select_scene_root()


## Godot toggles this panel's own `visible` off/on as its bottom-panel tab
## is switched away from/back to — NOTIFICATION_VISIBILITY_CHANGED is the
## reliable, self-contained way to know "the tab was just selected," rather
## than guessing at how the EditorPlugin-managed tab button behaves.
func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and is_visible_in_tree():
		_auto_select_scene_root()


func _auto_select_scene_root() -> void:
	if _canvas == null or (_canvas.build_target != null and is_instance_valid(_canvas.build_target)):
		return
	var root := _editor_interface.get_edited_scene_root()
	if root == null:
		return
	# The scene root itself often isn't a Control (a plain Node/Node2D named
	# "Main", with the UI nested under a CanvasLayer or similar) — so search
	# for the shallowest Control in the tree instead of requiring the root
	# itself to be one.
	var target: Control = root as Control
	if target == null:
		target = _find_first_control(root)
	if target == null:
		return
	_canvas.set_build_target(target)
	_target_label.text = "Target: %s  (auto-selected)" % target.name
	_redraw_canvas_area()


func _find_first_control(from: Node) -> Control:
	var queue: Array = [from]
	while not queue.is_empty():
		var n: Node = queue.pop_front()
		if n is Control:
			return n
		for child in n.get_children():
			queue.append(child)
	return null


func _build_ui() -> void:
	custom_minimum_size = Vector2(0, 260)
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	# Header row: target selector + refresh
	var header := HBoxContainer.new()
	root.add_child(header)

	var use_selected_btn := Button.new()
	use_selected_btn.text = "Use Selected as Target"
	use_selected_btn.pressed.connect(_on_use_selected_pressed)
	header.add_child(use_selected_btn)

	var delete_selected_btn := Button.new()
	delete_selected_btn.text = "Delete Selected"
	delete_selected_btn.tooltip_text = "Delete the selected node(s) from the build target (right-click a box on the canvas also works)"
	delete_selected_btn.pressed.connect(_on_delete_selected_pressed)
	header.add_child(delete_selected_btn)

	_snap_check = CheckButton.new()
	_snap_check.text = "Snap to Grid"
	_snap_check.tooltip_text = "Snap a moved node's landed position to the nearest grid multiple"
	_snap_check.toggled.connect(_on_snap_toggled)
	header.add_child(_snap_check)

	_grid_spin = SpinBox.new()
	_grid_spin.min_value = 1
	_grid_spin.max_value = 256
	_grid_spin.value = 8
	_grid_spin.custom_minimum_size = Vector2(60, 0)
	_grid_spin.tooltip_text = "Grid size in pixels"
	_grid_spin.value_changed.connect(_on_grid_size_changed)
	header.add_child(_grid_spin)

	_viewport_frame_check = CheckButton.new()
	_viewport_frame_check.text = "Show Full Viewport"
	_viewport_frame_check.button_pressed = true
	_viewport_frame_check.tooltip_text = "On: canvas shows the real project viewport size, with build_target positioned within it. Off: zoom to fill the canvas with just build_target (the original behavior)."
	_viewport_frame_check.toggled.connect(_on_viewport_frame_toggled)
	header.add_child(_viewport_frame_check)

	_target_label = Label.new()
	_target_label.text = "Target: (none)"
	_target_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_target_label)

	root.add_child(HSeparator.new())

	# Template row: pick a premade UI/HUD to instantiate, or save the
	# current selection as a new reusable one.
	var template_row := HBoxContainer.new()
	root.add_child(template_row)

	var template_label := Label.new()
	template_label.text = "Template:"
	template_row.add_child(template_label)

	_template_option = OptionButton.new()
	_template_option.custom_minimum_size = Vector2(160, 0)
	template_row.add_child(_template_option)

	var insert_template_btn := Button.new()
	insert_template_btn.text = "Insert"
	insert_template_btn.tooltip_text = "Instantiate the selected template as a child of the current build target"
	insert_template_btn.pressed.connect(_do_insert_template)
	template_row.add_child(insert_template_btn)

	var save_template_btn := Button.new()
	save_template_btn.text = "Save as Template..."
	save_template_btn.tooltip_text = "Save the currently selected node (and its children) as a reusable .tscn template"
	save_template_btn.pressed.connect(_do_save_template)
	template_row.add_child(save_template_btn)

	var refresh_templates_btn := Button.new()
	refresh_templates_btn.text = "Refresh"
	refresh_templates_btn.pressed.connect(_refresh_templates)
	template_row.add_child(refresh_templates_btn)

	template_row.add_child(VSeparator.new())

	var min_size_label := Label.new()
	min_size_label.text = "Min Size:"
	template_row.add_child(min_size_label)

	_min_size_width_spin = SpinBox.new()
	_min_size_width_spin.min_value = 0
	_min_size_width_spin.max_value = 4000
	_min_size_width_spin.step = 1
	_min_size_width_spin.custom_minimum_size = Vector2(70, 0)
	_min_size_width_spin.tooltip_text = "Selected node's Custom Minimum Size (width) — the smallest it'll ever be laid out at, even inside a Container. Handy for spacers."
	_min_size_width_spin.editable = false
	_min_size_width_spin.value_changed.connect(_on_min_size_spin_changed)
	template_row.add_child(_min_size_width_spin)

	var min_size_x_label := Label.new()
	min_size_x_label.text = "x"
	template_row.add_child(min_size_x_label)

	_min_size_height_spin = SpinBox.new()
	_min_size_height_spin.min_value = 0
	_min_size_height_spin.max_value = 4000
	_min_size_height_spin.step = 1
	_min_size_height_spin.custom_minimum_size = Vector2(70, 0)
	_min_size_height_spin.tooltip_text = "Selected node's Custom Minimum Size (height)"
	_min_size_height_spin.editable = false
	_min_size_height_spin.value_changed.connect(_on_min_size_spin_changed)
	template_row.add_child(_min_size_height_spin)

	root.add_child(HSeparator.new())

	# Body: palette (left) + canvas (right)
	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.split_offset = 140
	root.add_child(split)

	var palette_scroll := ScrollContainer.new()
	palette_scroll.custom_minimum_size = Vector2(140, 0)
	split.add_child(palette_scroll)

	var palette_box := VBoxContainer.new()
	palette_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	palette_scroll.add_child(palette_box)

	for type_name in PALETTE_TYPES:
		var btn := QuickLayoutPaletteButton.new()
		btn.control_type = type_name
		btn.text = type_name
		btn.tooltip_text = "Drag onto the canvas to add a %s" % type_name
		btn.mouse_entered.connect(_on_palette_item_focused.bind(type_name))
		btn.pressed.connect(_on_palette_item_focused.bind(type_name))
		palette_box.add_child(btn)

	# Nested split so the info panel gets a slice of the space to the right
	# of the canvas, without HSplitContainer's two-child limit getting in
	# the way of the outer palette/body split.
	var body_split := HSplitContainer.new()
	body_split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body_split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body_split.split_offset = -220
	split.add_child(body_split)

	_canvas = QuickLayoutCanvas.new()
	_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_canvas.custom_minimum_size = Vector2(300, 200)
	_canvas.editor_interface = _editor_interface
	_canvas.undo_redo = _undo_redo
	_canvas.node_created.connect(_on_node_created)
	_canvas.node_moved.connect(_on_node_moved)
	_canvas.node_resized.connect(_on_node_resized)
	_canvas.node_deleted.connect(_on_node_deleted)
	_canvas.target_lost.connect(_on_target_lost)
	_canvas.node_hover_changed.connect(_on_canvas_node_hover_changed)
	_canvas.snap_to_grid_enabled = _snap_check.button_pressed
	_canvas.grid_size = _grid_spin.value
	_canvas.viewport_frame_enabled = _viewport_frame_check.button_pressed

	# 2x2 grid: empty corner + top ruler on row 0, left ruler + canvas on
	# row 1, so the rulers stay aligned with the canvas as it resizes.
	var canvas_wrapper := GridContainer.new()
	canvas_wrapper.columns = 2
	canvas_wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	canvas_wrapper.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body_split.add_child(canvas_wrapper)

	var ruler_corner := Control.new()
	ruler_corner.custom_minimum_size = Vector2(RULER_THICKNESS, RULER_THICKNESS)
	canvas_wrapper.add_child(ruler_corner)

	_top_ruler = QuickLayoutRuler.new()
	_top_ruler.orientation = QuickLayoutRuler.Orientation.HORIZONTAL
	_top_ruler.canvas = _canvas
	_top_ruler.custom_minimum_size = Vector2(0, RULER_THICKNESS)
	_top_ruler.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	canvas_wrapper.add_child(_top_ruler)

	_left_ruler = QuickLayoutRuler.new()
	_left_ruler.orientation = QuickLayoutRuler.Orientation.VERTICAL
	_left_ruler.canvas = _canvas
	_left_ruler.custom_minimum_size = Vector2(RULER_THICKNESS, 0)
	_left_ruler.size_flags_vertical = Control.SIZE_EXPAND_FILL
	canvas_wrapper.add_child(_left_ruler)

	canvas_wrapper.add_child(_canvas)

	var info_scroll := ScrollContainer.new()
	info_scroll.custom_minimum_size = Vector2(180, 0)
	body_split.add_child(info_scroll)

	var info_box := VBoxContainer.new()
	info_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_scroll.add_child(info_box)

	_info_title = Label.new()
	_info_title.text = "Node Info"
	_info_title.add_theme_font_size_override("font_size", 14)
	info_box.add_child(_info_title)

	var name_row := HBoxContainer.new()
	info_box.add_child(name_row)

	var name_label := Label.new()
	name_label.text = "Name:"
	name_row.add_child(name_label)

	_name_edit = LineEdit.new()
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_edit.editable = false
	_name_edit.tooltip_text = "Rename the selected node — Enter or click away to commit"
	_name_edit.text_submitted.connect(_on_name_edit_submitted)
	_name_edit.focus_exited.connect(_on_name_edit_focus_exited)
	name_row.add_child(_name_edit)

	_separation_row = HBoxContainer.new()
	_separation_row.visible = false
	info_box.add_child(_separation_row)

	var separation_label := Label.new()
	separation_label.text = "Separation:"
	_separation_row.add_child(separation_label)

	_separation_spin = SpinBox.new()
	_separation_spin.min_value = 0
	_separation_spin.max_value = 200
	_separation_spin.step = 1
	_separation_spin.tooltip_text = "theme_override_constants/separation — the gap this VBoxContainer/HBoxContainer puts between its children"
	_separation_spin.value_changed.connect(_on_separation_spin_changed)
	_separation_row.add_child(_separation_spin)

	info_box.add_child(HSeparator.new())

	_info_desc = Label.new()
	_info_desc.text = "Hover or click a palette item on the left, or an existing box on the canvas, to see details about it."
	_info_desc.autowrap_mode = TextServer.AUTOWRAP_WORD
	info_box.add_child(_info_desc)

	_info_preview = QuickLayoutPalettePreview.new()
	_info_preview.visible = false
	info_box.add_child(_info_preview)

	# Cheap polling refresh so the schematic view stays roughly in sync with
	# the real scene tree (e.g. if you resize a node in the Inspector).
	_refresh_timer = Timer.new()
	_refresh_timer.wait_time = 0.5
	_refresh_timer.autostart = true
	_refresh_timer.timeout.connect(_redraw_canvas_area)
	add_child(_refresh_timer)

	_refresh_templates()


## Redraws the canvas and its rulers together — the rulers' tick spacing
## depends on the canvas's current scale/target, so anything that changes
## those should refresh both, not just the canvas.
func _redraw_canvas_area() -> void:
	if _canvas:
		_canvas.queue_redraw()
	if _top_ruler:
		_top_ruler.queue_redraw()
	if _left_ruler:
		_left_ruler.queue_redraw()
	# Keep the Name/Custom Min Size fields in sync if changed some other way
	# (Inspector, undo/redo) while still selected.
	if _info_target_node != null and is_instance_valid(_info_target_node):
		_sync_info_target_ui(_info_target_node)


func _on_palette_item_focused(type_name: String) -> void:
	if _info_title == null or _info_desc == null:
		return
	_info_title.text = type_name
	_info_desc.text = TYPE_DESCRIPTIONS.get(type_name, "No description available.")
	if _info_preview != null:
		_info_preview.visible = QuickLayoutPalettePreview.SUPPORTED_TYPES.has(type_name)
		_info_preview.preview_type = type_name


## Same info panel the palette uses, but for a node that already exists on
## the canvas: live name/type/position/size instead of just a type
## description, driven by hovering a box (see _on_canvas_node_hover_changed)
## or selecting one (see _on_selection_changed).
func _show_node_info(node: Control) -> void:
	if node == null or not is_instance_valid(node) or _info_title == null or _info_desc == null:
		return
	var type_name := node.get_class()
	_info_title.text = "%s (%s)" % [node.name, type_name]
	var desc: String = TYPE_DESCRIPTIONS.get(type_name, "")
	var geometry_line := "Position: (%d, %d)   Size: %d x %d" % [node.position.x, node.position.y, node.size.x, node.size.y]
	_info_desc.text = (desc + "\n\n" if desc != "" else "") + geometry_line
	if _info_preview != null:
		_info_preview.visible = QuickLayoutPalettePreview.SUPPORTED_TYPES.has(type_name)
		_info_preview.preview_type = type_name


func _on_canvas_node_hover_changed(node: Control) -> void:
	if node != null:
		_show_node_info(node)
		return
	# Hover cleared — fall back to showing the current selection, if any,
	# rather than leaving stale hover info on screen.
	var selected := _editor_interface.get_selection().get_selected_nodes()
	if selected.size() == 1 and selected[0] is Control and _canvas.is_within_build_target(selected[0]):
		_show_node_info(selected[0])


func _on_use_selected_pressed() -> void:
	var selected := _editor_interface.get_selection().get_selected_nodes()
	if selected.is_empty():
		_target_label.text = "Target: (none) — select a Control node first"
		return
	var node: Node = selected[0]
	if not (node is Control):
		_target_label.text = "Target: (none) — selected node isn't a Control"
		return
	_canvas.set_build_target(node)
	_target_label.text = "Target: %s" % node.name
	_redraw_canvas_area()


func _on_selection_changed() -> void:
	if _canvas == null:
		return
	_canvas.queue_redraw() # keep the yellow "selected" highlight in sync
	var selected := _editor_interface.get_selection().get_selected_nodes()
	if selected.size() == 1 and selected[0] is Control and _canvas.is_within_build_target(selected[0]):
		_show_node_info(selected[0])
		_sync_info_target_ui(selected[0])
	else:
		_sync_info_target_ui(null)


func _on_node_created(node: Control) -> void:
	var parent := node.get_parent()
	var parent_name: String = parent.name if parent != null else "?"
	_target_label.text = "Target: %s  (added %s into %s)" % [_canvas.build_target.name, node.name, parent_name]


func _on_node_moved(node: Control) -> void:
	if _canvas.build_target != null and is_instance_valid(_canvas.build_target):
		var parent := node.get_parent()
		var parent_name: String = parent.name if parent != null else "?"
		_target_label.text = "Target: %s  (moved %s into %s)" % [_canvas.build_target.name, node.name, parent_name]


func _on_node_resized(node: Control) -> void:
	if _canvas.build_target != null and is_instance_valid(_canvas.build_target):
		_target_label.text = "Target: %s  (resized %s to %dx%d)" % [_canvas.build_target.name, node.name, node.size.x, node.size.y]


func _on_snap_toggled(pressed: bool) -> void:
	if _canvas:
		_canvas.snap_to_grid_enabled = pressed


func _on_grid_size_changed(value: float) -> void:
	if _canvas:
		_canvas.grid_size = value


func _on_viewport_frame_toggled(pressed: bool) -> void:
	if _canvas:
		_canvas.viewport_frame_enabled = pressed
		_redraw_canvas_area()


## Shows the currently selected node's Name and Custom Minimum Size in the
## editable fields (disabled/cleared when there's no single selected node),
## without triggering the commit handlers as if the user had edited them.
## Skips overwriting a field the user is actively typing in, so a periodic
## re-sync (see _redraw_canvas_area) can't clobber an in-progress edit.
func _sync_info_target_ui(node: Control) -> void:
	if _min_size_width_spin == null or _min_size_height_spin == null or _name_edit == null:
		return
	_info_target_node = node
	_updating_min_size_ui = true
	if node != null and is_instance_valid(node):
		if not _min_size_width_spin.has_focus() and not _min_size_height_spin.has_focus():
			_min_size_width_spin.value = node.custom_minimum_size.x
			_min_size_height_spin.value = node.custom_minimum_size.y
		_min_size_width_spin.editable = true
		_min_size_height_spin.editable = true
		if not _name_edit.has_focus():
			_name_edit.text = node.name
		_name_edit.editable = true
		if node is BoxContainer:
			_separation_row.visible = true
			if not _separation_spin.has_focus():
				_separation_spin.value = node.get_theme_constant("separation")
		else:
			_separation_row.visible = false
	else:
		_min_size_width_spin.value = 0
		_min_size_height_spin.value = 0
		_min_size_width_spin.editable = false
		_min_size_height_spin.editable = false
		_name_edit.text = ""
		_name_edit.editable = false
		_separation_row.visible = false
	_updating_min_size_ui = false


func _on_min_size_spin_changed(_value: float) -> void:
	if _updating_min_size_ui or _info_target_node == null or not is_instance_valid(_info_target_node):
		return
	if _min_size_width_spin == null or _min_size_height_spin == null or _undo_redo == null:
		return
	var new_size := Vector2(_min_size_width_spin.value, _min_size_height_spin.value)
	if new_size == _info_target_node.custom_minimum_size:
		return
	_undo_redo.create_action("Quick Layout: Set Custom Min Size %s" % _info_target_node.name)
	_undo_redo.add_do_property(_info_target_node, "custom_minimum_size", new_size)
	_undo_redo.add_undo_property(_info_target_node, "custom_minimum_size", _info_target_node.custom_minimum_size)
	_undo_redo.commit_action()
	if _canvas:
		_canvas.queue_redraw()


func _on_separation_spin_changed(value: float) -> void:
	if _updating_min_size_ui or _info_target_node == null or not is_instance_valid(_info_target_node):
		return
	if not (_info_target_node is BoxContainer) or _undo_redo == null:
		return
	var new_value := int(value)
	if _info_target_node.has_theme_constant_override("separation") \
			and _info_target_node.get_theme_constant("separation") == new_value:
		return

	_undo_redo.create_action("Quick Layout: Set Separation %s" % _info_target_node.name)
	_undo_redo.add_do_method(_info_target_node, "add_theme_constant_override", "separation", new_value)
	if _info_target_node.has_theme_constant_override("separation"):
		_undo_redo.add_undo_method(_info_target_node, "add_theme_constant_override", "separation", _info_target_node.get_theme_constant("separation"))
	else:
		_undo_redo.add_undo_method(_info_target_node, "remove_theme_constant_override", "separation")
	_undo_redo.commit_action()
	if _canvas:
		_canvas.queue_redraw()


func _on_name_edit_submitted(new_name: String) -> void:
	_commit_node_rename(new_name)
	_name_edit.release_focus()


func _on_name_edit_focus_exited() -> void:
	_commit_node_rename(_name_edit.text)


func _commit_node_rename(new_name: String) -> void:
	if _info_target_node == null or not is_instance_valid(_info_target_node) or _undo_redo == null:
		return
	new_name = new_name.strip_edges()
	var old_name := String(_info_target_node.name)
	if new_name == "" or new_name == old_name:
		_name_edit.text = old_name # discard an empty/unchanged edit, don't blank the node's name
		return
	_undo_redo.create_action("Quick Layout: Rename %s" % old_name)
	_undo_redo.add_do_property(_info_target_node, "name", new_name)
	_undo_redo.add_undo_property(_info_target_node, "name", old_name)
	_undo_redo.commit_action()
	_name_edit.text = _info_target_node.name # reflect any auto-uniquification Godot applied
	_redraw_canvas_area()


func _on_delete_selected_pressed() -> void:
	if _canvas.build_target == null or not is_instance_valid(_canvas.build_target):
		return
	var selected := _editor_interface.get_selection().get_selected_nodes()
	for node in selected:
		if node is Control and node != _canvas.build_target and _canvas.is_within_build_target(node):
			_canvas.delete_node(node)


func _on_node_deleted(node: Control) -> void:
	if _canvas.build_target != null and is_instance_valid(_canvas.build_target):
		_target_label.text = "Target: %s  (deleted %s)" % [_canvas.build_target.name, node.name]


func _on_target_lost() -> void:
	_target_label.text = "Target: (none) — previous target was deleted"


# --- Templates: instantiate a premade .tscn as a child of the build target,
#     or pack the current selection into a new reusable .tscn. -------------

func _refresh_templates() -> void:
	if _template_option == null:
		return
	_template_paths.clear()
	_template_option.clear()
	var dir := DirAccess.open(TEMPLATES_DIR)
	if dir == null:
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.ends_with(".tscn"):
			_template_paths.append(TEMPLATES_DIR + file_name)
			_template_option.add_item(file_name.get_basename())
		file_name = dir.get_next()
	dir.list_dir_end()


func _do_insert_template() -> void:
	if _template_option.selected < 0 or _template_option.selected >= _template_paths.size():
		_target_label.text = "Target: (none)  (no template selected)"
		return
	var template_path: String = _template_paths[_template_option.selected]

	if _canvas.build_target != null and is_instance_valid(_canvas.build_target):
		_insert_template_into(template_path, _canvas.build_target, false)
		return

	var edited_root := _editor_interface.get_edited_scene_root()
	if edited_root != null:
		# A scene is open but nothing's targeted yet (e.g. no Control
		# anywhere in it) — fall back to the scene root itself. Any Node can
		# parent a Control structurally, and this becomes the new build
		# target going forward.
		_insert_template_into(template_path, edited_root, true)
		return

	# No scene open at all — nothing to fall back to, so create one from the
	# template instead of just erroring.
	_create_scene_from_template(template_path)


func _insert_template_into(template_path: String, parent: Node, become_new_target: bool) -> void:
	var packed := load(template_path)
	if not (packed is PackedScene):
		return
	var instance: Node = (packed as PackedScene).instantiate()
	if not (instance is Control):
		instance.queue_free()
		return

	var edited_root := _editor_interface.get_edited_scene_root()
	if edited_root == null:
		instance.queue_free()
		return

	_undo_redo.create_action("Quick Layout: Insert Template %s" % instance.name)
	_undo_redo.add_do_method(parent, "add_child", instance, true)
	_undo_redo.add_do_method(self, "_set_owner_recursive_including_root", instance, edited_root)
	_undo_redo.add_do_reference(instance)
	_undo_redo.add_undo_method(parent, "remove_child", instance)
	_undo_redo.commit_action()

	if become_new_target:
		_canvas.set_build_target(instance)

	_editor_interface.get_selection().clear()
	_editor_interface.get_selection().add_node(instance)
	_redraw_canvas_area()
	var target_name: String = instance.name if become_new_target else parent.name
	_target_label.text = "Target: %s  (inserted template %s)" % [target_name, instance.name]


func _create_scene_from_template(template_path: String) -> void:
	var packed := load(template_path)
	if not (packed is PackedScene):
		return
	var instance: Node = (packed as PackedScene).instantiate()
	if not (instance is Control):
		instance.queue_free()
		return

	var file_dialog := EditorFileDialog.new()
	file_dialog.file_mode = EditorFileDialog.FILE_MODE_SAVE_FILE
	file_dialog.access = EditorFileDialog.ACCESS_RESOURCES
	file_dialog.add_filter("*.tscn", "Scene")
	file_dialog.current_file = instance.name + ".tscn"
	file_dialog.file_selected.connect(func(path: String) -> void:
		_finish_create_scene_from_template(path, instance)
		file_dialog.queue_free())
	file_dialog.canceled.connect(func() -> void:
		instance.queue_free()
		file_dialog.queue_free())
	add_child(file_dialog)
	file_dialog.popup_centered_ratio()
	_target_label.text = "Target: (none)  (no scene open — choose where to save a new one from this template)"


func _finish_create_scene_from_template(path: String, instance: Node) -> void:
	instance.owner = null
	_set_owner_recursive_children(instance, instance)

	var packed := PackedScene.new()
	var err := packed.pack(instance)
	if err != OK:
		_target_label.text = "Failed to create scene (error %d)." % err
		instance.queue_free()
		return

	err = ResourceSaver.save(packed, path)
	instance.queue_free()
	if err != OK:
		_target_label.text = "Failed to save new scene (error %d)." % err
		return

	_editor_interface.open_scene_from_path(path)
	var new_root := _editor_interface.get_edited_scene_root()
	if new_root != null:
		_canvas.set_build_target(new_root)
		_redraw_canvas_area()
		_target_label.text = "Target: %s  (new scene created from template)" % new_root.name
	else:
		_target_label.text = "Created and opened %s — switch tabs and back to pick it up as the target." % path.get_file()


func _do_save_template() -> void:
	var selected := _editor_interface.get_selection().get_selected_nodes()
	if selected.size() != 1 or not (selected[0] is Control):
		_target_label.text = "Select exactly one Control node to save as a template."
		return
	var source_node: Control = selected[0]

	var addon_dir := DirAccess.open("res://addons/quick_layout/")
	if addon_dir != null and not addon_dir.dir_exists("templates"):
		addon_dir.make_dir("templates")

	var file_dialog := EditorFileDialog.new()
	file_dialog.file_mode = EditorFileDialog.FILE_MODE_SAVE_FILE
	file_dialog.access = EditorFileDialog.ACCESS_RESOURCES
	file_dialog.add_filter("*.tscn", "Scene")
	file_dialog.current_dir = TEMPLATES_DIR
	file_dialog.current_file = source_node.name + ".tscn"
	file_dialog.file_selected.connect(func(path: String) -> void:
		_save_template_to_path(path, source_node)
		file_dialog.queue_free())
	file_dialog.canceled.connect(file_dialog.queue_free)
	add_child(file_dialog)
	file_dialog.popup_centered_ratio()


func _save_template_to_path(path: String, source_node: Control) -> void:
	if not is_instance_valid(source_node):
		return
	var duplicate: Node = source_node.duplicate()
	duplicate.owner = null
	_set_owner_recursive_children(duplicate, duplicate)

	var packed := PackedScene.new()
	var err := packed.pack(duplicate)
	duplicate.queue_free()
	if err != OK:
		_target_label.text = "Failed to pack template (error %d)." % err
		return

	err = ResourceSaver.save(packed, path)
	if err != OK:
		_target_label.text = "Failed to save template (error %d)." % err
		return

	_refresh_templates()
	_target_label.text = "Saved template: %s" % path.get_file()


func _set_owner_recursive_including_root(node: Node, owner: Node) -> void:
	node.owner = owner
	for child in node.get_children():
		_set_owner_recursive_including_root(child, owner)


func _set_owner_recursive_children(node: Node, owner: Node) -> void:
	for child in node.get_children():
		child.owner = owner
		_set_owner_recursive_children(child, owner)
