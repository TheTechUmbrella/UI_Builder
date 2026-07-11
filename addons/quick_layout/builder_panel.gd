@tool
extends Control

const QuickLayoutCanvas = preload("res://addons/quick_layout/quick_layout_canvas.gd")
const QuickLayoutPaletteButton = preload("res://addons/quick_layout/palette_button.gd")
const QuickLayoutPalettePreview = preload("res://addons/quick_layout/palette_preview.gd")

const TEMPLATES_DIR := "res://addons/quick_layout/templates/"

const PALETTE_TYPES := [
	"Panel", "PanelContainer", "VBoxContainer", "HBoxContainer",
	"GridContainer", "MarginContainer", "CenterContainer", "ScrollContainer",
	"Label", "Button", "LineEdit", "TextEdit", "CheckBox", "CheckButton",
	"ProgressBar", "TextureRect", "ColorRect", "RichTextLabel", "ItemList",
]

const TYPE_DESCRIPTIONS := {
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
var _target_label: Label
var _refresh_timer: Timer
var _snap_check: CheckButton
var _grid_spin: SpinBox
var _info_title: Label
var _info_desc: Label
var _info_preview: QuickLayoutPalettePreview
var _template_option: OptionButton
var _template_paths: Array[String] = []


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
	save_template_btn.text = "Save Selected as Template..."
	save_template_btn.tooltip_text = "Save the currently selected node (and its children) as a reusable .tscn template"
	save_template_btn.pressed.connect(_do_save_template)
	template_row.add_child(save_template_btn)

	var refresh_templates_btn := Button.new()
	refresh_templates_btn.text = "Refresh"
	refresh_templates_btn.pressed.connect(_refresh_templates)
	template_row.add_child(refresh_templates_btn)

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
	_canvas.snap_to_grid_enabled = _snap_check.button_pressed
	_canvas.grid_size = _grid_spin.value
	body_split.add_child(_canvas)

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
	info_box.add_child(HSeparator.new())

	_info_desc = Label.new()
	_info_desc.text = "Hover or click a palette item on the left to see what it does."
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
	_refresh_timer.timeout.connect(func(): _canvas.queue_redraw())
	add_child(_refresh_timer)

	_refresh_templates()


func _on_palette_item_focused(type_name: String) -> void:
	if _info_title == null or _info_desc == null:
		return
	_info_title.text = type_name
	_info_desc.text = TYPE_DESCRIPTIONS.get(type_name, "No description available.")
	if _info_preview != null:
		_info_preview.visible = QuickLayoutPalettePreview.SUPPORTED_TYPES.has(type_name)
		_info_preview.preview_type = type_name


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


func _on_selection_changed() -> void:
	if _canvas:
		_canvas.queue_redraw() # keep the yellow "selected" highlight in sync


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
	_canvas.queue_redraw()
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
