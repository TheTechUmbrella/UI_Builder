@tool
extends Control
class_name QuickLayoutCanvas

## Per-project opt-out for the Custom Min Size hint dialog, stored in
## project.godot so it sticks across editor restarts without needing a
## global (cross-project) editor setting.
const MIN_SIZE_HINT_SETTING := "ui_builder/hide_custom_min_size_hint"

## Per-project toggle for smart alignment guides (snapping + the guide line
## feedback together — disabling one without the other would just be
## confusing, either an invisible snap or a line that doesn't mean anything).
const ALIGN_GUIDES_SETTING := "ui_builder/enable_alignment_guides"

## Sensible starting sizes so a dropped node isn't zero-size/invisible.
const DEFAULT_SIZES := {
	"Button": Vector2(100, 40),
	"Label": Vector2(120, 24),
	"LineEdit": Vector2(160, 32),
	"TextEdit": Vector2(220, 100),
	"Panel": Vector2(220, 140),
	"PanelContainer": Vector2(220, 140),
	"VBoxContainer": Vector2(220, 160),
	"HBoxContainer": Vector2(220, 60),
	"GridContainer": Vector2(220, 160),
	"CenterContainer": Vector2(220, 160),
	"MarginContainer": Vector2(220, 160),
	"TextureRect": Vector2(100, 100),
	"ColorRect": Vector2(100, 100),
	"ProgressBar": Vector2(200, 24),
	"HSlider": Vector2(200, 24),
	"VSlider": Vector2(24, 160),
	"CheckBox": Vector2(140, 32),
	"CheckButton": Vector2(140, 32),
	"RichTextLabel": Vector2(220, 100),
	"ScrollContainer": Vector2(220, 160),
	"ItemList": Vector2(220, 140),
	"Tree": Vector2(220, 140),
	"TabContainer": Vector2(260, 160),
	"HSplitContainer": Vector2(220, 140),
	"VSplitContainer": Vector2(140, 220),
	"HFlowContainer": Vector2(220, 100),
	"VFlowContainer": Vector2(140, 220),
	"HSeparator": Vector2(200, 8),
	"VSeparator": Vector2(8, 200),
	"OptionButton": Vector2(140, 32),
	"MenuButton": Vector2(120, 32),
	"LinkButton": Vector2(100, 24),
	"TextureButton": Vector2(80, 80),
	"ColorPickerButton": Vector2(100, 32),
	"SpinBox": Vector2(100, 32),
	"TextureProgressBar": Vector2(100, 100),
	"NinePatchRect": Vector2(120, 80),
}

## Resize handle positions on a selected box, matching standard 8-point
## resize-handle layouts (corners + edge midpoints).
enum ResizeHandle { NONE, TOP_LEFT, TOP, TOP_RIGHT, RIGHT, BOTTOM_RIGHT, BOTTOM, BOTTOM_LEFT, LEFT }
const HANDLE_SIZE := 7.0
const HANDLE_GRAB_RADIUS := 7.0
const MIN_RESIZE_SIZE := 8.0

var build_target: Control = null
var undo_redo: EditorUndoRedoManager
var editor_interface: EditorInterface

## When enabled, dragging an existing box to move it snaps its landed
## position to the nearest multiple of grid_size.
var snap_to_grid_enabled: bool = false
var grid_size: float = 8.0

## When enabled (default), the canvas scales to the project's real viewport
## size and shows build_target positioned within that larger frame. When
## disabled, it reverts to the original behavior: zoom to fill the canvas
## with build_target's own bounds, ignoring the rest of the screen.
var viewport_frame_enabled: bool = true

## Canvas-space offset added on top of the normal scaling — lets you
## middle-click-drag to look at content beyond the canvas's own bounds,
## the same way the main 2D viewport pans.
var _pan_offset: Vector2 = Vector2.ZERO
var _panning: bool = false
var _pan_start_mouse: Vector2 = Vector2.ZERO
var _pan_start_offset: Vector2 = Vector2.ZERO

## Multiplier on top of the normal fit/viewport-frame scaling — scroll wheel
## zooms in/out, centered on the cursor (the point under it stays put).
const MIN_ZOOM := 0.1
const MAX_ZOOM := 8.0
const ZOOM_STEP := 1.15
var _zoom: float = 1.0

## Emitted on every pan/zoom change — lets the rulers redraw immediately
## instead of waiting for the next periodic poll (which would look laggy
## while actively scrolling/dragging).
signal view_changed()

signal node_created(node: Control)
signal node_moved(node: Control)
signal node_resized(node: Control)
signal node_deleted(node: Control)
signal target_lost()

## Emitted whenever the box under the cursor changes (null when hovering
## empty canvas space or the mouse leaves), so the info panel can show live
## details about an existing node, not just palette type descriptions.
signal node_hover_changed(node: Control)

var _target_watch: Control = null
var _drag_preview_rect: Rect2 = Rect2()
var _drag_preview_active: bool = false
var _drag_hover_parent: Control = null
var _context_menu: PopupMenu
var _context_menu_node: Control = null
var _context_menu_parent: Control = null
var _context_menu_paste_target: Control = null
## Orphaned (not-in-tree) duplicates made at Copy time, independent of the
## original nodes — pasting re-duplicates from these, so multiple pastes
## produce independent copies and deleting/undoing the original afterward
## doesn't affect what's on the clipboard.
var _clipboard: Array[Control] = []
var _min_size_hint_dialog: AcceptDialog
var _min_size_hint_label: Label
var _min_size_hint_dont_show_check: CheckBox
var _hovered_node: Control = null

var _resizing_node: Control = null
var _resize_handle: int = ResizeHandle.NONE
var _resize_start_mouse: Vector2 = Vector2.ZERO
var _resize_start_local_pos: Vector2 = Vector2.ZERO
var _resize_start_local_size: Vector2 = Vector2.ZERO
var _resize_preview_local_pos: Vector2 = Vector2.ZERO
var _resize_preview_local_size: Vector2 = Vector2.ZERO

## The click-vs-drag ambiguity: a mouse-down alone can't tell us whether the
## user wants to click-select (topmost box wins) or drag-move (the already-
## selected box should win, even if a child visually covers it). So the
## selection update on plain press is deferred to release-without-drag;
## _get_drag_data consults the still-unchanged prior selection instead.
var _press_chain: Array = []
var _press_alt: bool = false
var _press_position: Vector2 = Vector2.ZERO
## True only between a LEFT press that actually originated on this canvas and
## its matching release — distinguishes a real "nothing under the cursor"
## press-drag from motion events that merely pass over the canvas while an
## unrelated drag (e.g. a palette item) started elsewhere is hovering it,
## which would otherwise look identical to stale/empty _press_chain state.
var _press_active: bool = false
var _drag_started: bool = false

## Rubber-band multi-select: starts when a press-drag begins over empty
## canvas space (never over a node — that's a move instead). Shift held on
## release adds to the existing EditorSelection instead of replacing it.
const BOX_SELECT_START_THRESHOLD := 4.0
var _box_selecting: bool = false
var _box_select_start: Vector2 = Vector2.ZERO
var _box_select_current: Vector2 = Vector2.ZERO

## Smart alignment guides: while freely repositioning a node (not a
## Container-managed reorder), its candidate position snaps to a sibling's or
## the parent's own edge/center when within this many canvas pixels, and a
## guide line is drawn at the matched position for feedback. Cleared whenever
## a drag isn't actively eligible for it (reordering, drag end, etc.).
const ALIGN_SNAP_THRESHOLD := 6.0
var _align_guide_v_lines: Array[Dictionary] = []
var _align_guide_h_lines: Array[Dictionary] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	# Needed so Ctrl+D reaches _gui_input as InputEventKey — Controls only
	# get keyboard events while they hold focus, and a plain Control doesn't
	# accept it by default.
	focus_mode = Control.FOCUS_ALL
	add_theme_stylebox_override("focus", StyleBoxEmpty.new()) # no redundant focus ring — the canvas already draws its own border
	mouse_exited.connect(_on_mouse_exited)
	_context_menu = PopupMenu.new()
	_context_menu.id_pressed.connect(_on_context_menu_id_pressed)
	add_child(_context_menu)
	_min_size_hint_dialog = AcceptDialog.new()
	_min_size_hint_dialog.title = "Custom Min Size Set"
	# Left as its own VBoxContainer (label + checkbox) instead of using
	# dialog_text/get_label() directly — AcceptDialog's built-in label and a
	# directly-added extra child don't reliably stack with proper spacing,
	# they can overlap. Owning the whole content area avoids that.
	var hint_vbox := VBoxContainer.new()
	hint_vbox.add_theme_constant_override("separation", 1)
	_min_size_hint_dialog.add_child(hint_vbox)

	_min_size_hint_label = Label.new()
	_min_size_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_min_size_hint_label.custom_minimum_size = Vector2(380, 0)
	hint_vbox.add_child(_min_size_hint_label)

	_min_size_hint_dont_show_check = CheckBox.new()
	_min_size_hint_dont_show_check.text = "Don't remind me again for this project"
	_min_size_hint_dont_show_check.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	hint_vbox.add_child(_min_size_hint_dont_show_check)

	var settings_hint_label := Label.new()
	settings_hint_label.text = "Can be changed in Project Settings / UI Builder"
	settings_hint_label.add_theme_font_size_override("font_size", 11)
	settings_hint_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.5))
	settings_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	settings_hint_label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	hint_vbox.add_child(settings_hint_label)

	_min_size_hint_dialog.confirmed.connect(_on_min_size_hint_dialog_closed)
	_min_size_hint_dialog.canceled.connect(_on_min_size_hint_dialog_closed)
	add_child(_min_size_hint_dialog)

	# Register the setting so it's actually visible in Project Settings (a
	# bare set_setting() call alone stays hidden under "Advanced Settings"),
	# matching what the dialog's hint text tells the user.
	if not ProjectSettings.has_setting(MIN_SIZE_HINT_SETTING):
		ProjectSettings.set_setting(MIN_SIZE_HINT_SETTING, false)
	ProjectSettings.set_initial_value(MIN_SIZE_HINT_SETTING, false)
	ProjectSettings.set_as_basic(MIN_SIZE_HINT_SETTING, true)

	if not ProjectSettings.has_setting(ALIGN_GUIDES_SETTING):
		ProjectSettings.set_setting(ALIGN_GUIDES_SETTING, true)
	ProjectSettings.set_initial_value(ALIGN_GUIDES_SETTING, true)
	ProjectSettings.set_as_basic(ALIGN_GUIDES_SETTING, true)


func _exit_tree() -> void:
	# _clipboard holds orphaned (never added to any tree) duplicate nodes —
	# freeing this canvas doesn't free those on its own, so do it explicitly
	# to avoid leaking them across a plugin disable/reload.
	for node in _clipboard:
		if is_instance_valid(node):
			node.queue_free()
	_clipboard.clear()


func _on_min_size_hint_dialog_closed() -> void:
	if _min_size_hint_dont_show_check.button_pressed:
		ProjectSettings.set_setting(MIN_SIZE_HINT_SETTING, true)
		ProjectSettings.save()


func _on_mouse_exited() -> void:
	if _drag_preview_active:
		_drag_preview_active = false
		_drag_hover_parent = null
		queue_redraw()
	if _hovered_node != null:
		_hovered_node = null
		node_hover_changed.emit(null)


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		# _drop_data already clears _drag_preview_active itself (before this
		# notification fires), so that can't gate the alignment-guide
		# cleanup here — always clear on drag end, successful or cancelled.
		if _drag_preview_active:
			_drag_preview_active = false
			_drag_hover_parent = null
		if not _align_guide_v_lines.is_empty() or not _align_guide_h_lines.is_empty():
			_align_guide_v_lines = []
			_align_guide_h_lines = []
			queue_redraw()


func _target_ok() -> bool:
	return build_target != null and is_instance_valid(build_target)


func is_within_build_target(node: Node) -> bool:
	if not _target_ok():
		return false
	var n := node
	while n != null:
		if n == build_target:
			return true
		n = n.get_parent()
	return false


func set_build_target(target: Control) -> void:
	if _target_watch != null and is_instance_valid(_target_watch) \
			and _target_watch.tree_exiting.is_connected(_on_target_tree_exiting):
		_target_watch.tree_exiting.disconnect(_on_target_tree_exiting)

	build_target = target
	_target_watch = target
	if target != null:
		target.tree_exiting.connect(_on_target_tree_exiting)
	queue_redraw()


func _on_target_tree_exiting() -> void:
	# The node we were building into got deleted (or moved out of tree).
	build_target = null
	_target_watch = null
	target_lost.emit()
	queue_redraw()


# --- Drop target: accepts new nodes from the palette AND moved nodes from
#     this same canvas. A drop lands inside whichever existing box the
#     cursor is over (found via hit-test), falling back to build_target when
#     hovering empty canvas space — so nested containers don't require
#     re-picking "Use Selected as Target" for every drop. ---------------------

func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	if not _target_ok() or typeof(data) != TYPE_DICTIONARY \
			or not (data.has("quick_layout_type") or data.has("quick_layout_move_node")):
		if _drag_preview_active:
			_drag_preview_active = false
			_drag_hover_parent = null
			queue_redraw()
		return false

	_update_drag_preview_rect(at_position, data)
	queue_redraw()
	return true


func _drop_parent_for(at_position: Vector2, exclude: Node = null) -> Control:
	var hovered := _find_deepest_at(build_target, at_position, _target_to_canvas_ratio(), exclude)
	return hovered if hovered != null else build_target


func _maybe_snap_local_pos(local_pos: Vector2) -> Vector2:
	if not snap_to_grid_enabled or grid_size <= 0:
		return local_pos
	return Vector2(
		round(local_pos.x / grid_size) * grid_size,
		round(local_pos.y / grid_size) * grid_size
	)


## Resolves where a moved node would land: which node becomes its new
## parent, and its (grid-snapped, if enabled) local position within that
## parent. Shared by the live preview and the actual drop so they never
## disagree about where the node is about to go.
##
## If the drop stays within the same Container the node is already in,
## position is meaningless (the Container recalculates it every layout pass
## regardless) — the one thing that DOES actually change is sibling order,
## so that case resolves to a reorder instead, via reorder_index.
func _resolve_move_target(at_position: Vector2, ctrl: Control, grab_offset: Vector2) -> Dictionary:
	var ratio := _target_to_canvas_ratio()
	var parent := _drop_parent_for(at_position, ctrl)
	var parent_origin: Vector2 = _canvas_rect_for(parent, ratio).position
	var raw_local_pos: Vector2 = ((at_position - grab_offset) - parent_origin) / ratio
	var local_pos := _maybe_snap_local_pos(raw_local_pos)

	var is_reorder: bool = parent is Container and parent == ctrl.get_parent()
	var reorder_index := -1
	if is_reorder:
		reorder_index = _reorder_index_for(parent, ctrl, at_position, ratio)
		_align_guide_v_lines = []
		_align_guide_h_lines = []
	else:
		local_pos = _apply_alignment_guides(parent, ctrl, local_pos, ctrl.size, ratio, parent_origin)

	return {
		"parent": parent, "local_pos": local_pos, "parent_origin": parent_origin, "ratio": ratio,
		"is_reorder": is_reorder, "reorder_index": reorder_index,
	}


## Snaps a freely-positioned box's candidate position to align with a
## sibling's or the parent's own edge/center when within
## ALIGN_SNAP_THRESHOLD canvas pixels on either axis, and records the matched
## line(s) in _align_guide_v_lines/_align_guide_h_lines for _draw() to render
## as feedback. Used for both moving an existing node (exclude_node is that
## node, so it doesn't align against itself) and creating a brand new one
## from the palette (exclude_node is null — nothing to exclude yet).
func _apply_alignment_guides(parent: Control, exclude_node: Control, local_pos: Vector2, node_size: Vector2, ratio: Vector2, parent_origin: Vector2) -> Vector2:
	_align_guide_v_lines = []
	_align_guide_h_lines = []
	if not bool(ProjectSettings.get_setting(ALIGN_GUIDES_SETTING, true)):
		return local_pos

	var rect := Rect2(parent_origin + local_pos * ratio, node_size * ratio)

	var candidates: Array[Rect2] = [_canvas_rect_for(parent, ratio)]
	for sib in parent.get_children():
		if sib != exclude_node and sib is Control:
			candidates.append(_canvas_rect_for(sib as Control, ratio))

	var my_xs := [rect.position.x, rect.position.x + rect.size.x * 0.5, rect.position.x + rect.size.x]
	var best_dx := ALIGN_SNAP_THRESHOLD
	var best_offset_x := 0.0
	var best_line_x := 0.0
	var best_cand_x := Rect2()
	var found_x := false
	for cand in candidates:
		var their_xs := [cand.position.x, cand.position.x + cand.size.x * 0.5, cand.position.x + cand.size.x]
		for mx in my_xs:
			for tx in their_xs:
				var d: float = absf(mx - tx)
				if d < best_dx:
					best_dx = d
					best_offset_x = tx - mx
					best_line_x = tx
					best_cand_x = cand
					found_x = true

	var my_ys := [rect.position.y, rect.position.y + rect.size.y * 0.5, rect.position.y + rect.size.y]
	var best_dy := ALIGN_SNAP_THRESHOLD
	var best_offset_y := 0.0
	var best_line_y := 0.0
	var best_cand_y := Rect2()
	var found_y := false
	for cand in candidates:
		var their_ys := [cand.position.y, cand.position.y + cand.size.y * 0.5, cand.position.y + cand.size.y]
		for my in my_ys:
			for ty in their_ys:
				var d: float = absf(my - ty)
				if d < best_dy:
					best_dy = d
					best_offset_y = ty - my
					best_line_y = ty
					best_cand_y = cand
					found_y = true

	var snapped := rect.position
	if found_x:
		snapped.x += best_offset_x
		var y0: float = minf(rect.position.y, best_cand_x.position.y) - 10.0
		var y1: float = maxf(rect.position.y + rect.size.y, best_cand_x.position.y + best_cand_x.size.y) + 10.0
		_align_guide_v_lines.append({"x": best_line_x, "y0": y0, "y1": y1})
	if found_y:
		snapped.y += best_offset_y
		var x0: float = minf(rect.position.x, best_cand_y.position.x) - 10.0
		var x1: float = maxf(rect.position.x + rect.size.x, best_cand_y.position.x + best_cand_y.size.x) + 10.0
		_align_guide_h_lines.append({"y": best_line_y, "x0": x0, "x1": x1})

	return (snapped - parent_origin) / ratio


## Resolves where a brand new node (dragged from the palette) would land:
## which existing box becomes its parent, and its (grid + alignment snapped)
## local position within that parent. Shared by the live preview and the
## actual drop, same reasoning as _resolve_move_target.
func _resolve_create_target(at_position: Vector2, type_name: String) -> Dictionary:
	var ratio := _target_to_canvas_ratio()
	var target_size: Vector2 = DEFAULT_SIZES.get(type_name, Vector2(100, 40))
	var canvas_size: Vector2 = target_size * ratio
	var parent := _drop_parent_for(at_position)
	var parent_origin: Vector2 = _canvas_rect_for(parent, ratio).position
	var raw_local_pos: Vector2 = (at_position - canvas_size / 2.0 - parent_origin) / ratio
	var local_pos := _maybe_snap_local_pos(raw_local_pos)
	local_pos = _apply_alignment_guides(parent, null, local_pos, target_size, ratio, parent_origin)
	return {
		"parent": parent, "local_pos": local_pos, "parent_origin": parent_origin,
		"ratio": ratio, "target_size": target_size,
	}


## Which sibling slot a drop position corresponds to, for reordering within
## a Container — compares against the midpoint of each sibling's box along
## whichever axis that Container type actually lays out on.
func _reorder_index_for(parent: Control, node: Control, at_position: Vector2, ratio: Vector2) -> int:
	var vertical := not (parent is HBoxContainer)
	var siblings := parent.get_children()
	for sib in siblings:
		if sib == node or not (sib is Control):
			continue
		var sib_r := _canvas_rect_for(sib as Control, ratio)
		var mid: float = sib_r.position.y + sib_r.size.y / 2.0 if vertical else sib_r.position.x + sib_r.size.x / 2.0
		var cursor: float = at_position.y if vertical else at_position.x
		if cursor < mid:
			return (sib as Node).get_index()
	return siblings.size() - 1


func _update_drag_preview_rect(at_position: Vector2, data: Dictionary) -> void:
	var ratio := _target_to_canvas_ratio()
	if data.has("quick_layout_type"):
		var resolved := _resolve_create_target(at_position, data["quick_layout_type"])
		var preview_canvas_pos: Vector2 = (resolved["parent_origin"] as Vector2) \
				+ (resolved["local_pos"] as Vector2) * (resolved["ratio"] as Vector2)
		_drag_preview_rect = Rect2(preview_canvas_pos, (resolved["target_size"] as Vector2) * ratio)
		_drag_hover_parent = resolved["parent"]
		_drag_preview_active = true
	elif data.has("quick_layout_move_node"):
		var node: Object = data["quick_layout_move_node"]
		if node is Control and is_instance_valid(node):
			var ctrl: Control = node
			var grab_offset: Vector2 = data.get("grab_offset", Vector2.ZERO)
			var resolved := _resolve_move_target(at_position, ctrl, grab_offset)
			var preview_canvas_pos: Vector2 = (resolved["parent_origin"] as Vector2) \
					+ (resolved["local_pos"] as Vector2) * (resolved["ratio"] as Vector2)
			_drag_preview_rect = Rect2(preview_canvas_pos, ctrl.size * ratio)
			_drag_hover_parent = resolved["parent"]
			_drag_preview_active = true
		else:
			_drag_preview_active = false
			_drag_hover_parent = null


func _drop_data(at_position: Vector2, data: Variant) -> void:
	_drag_preview_active = false
	_drag_hover_parent = null
	if not _target_ok():
		return
	if data.has("quick_layout_type"):
		var resolved := _resolve_create_target(at_position, data["quick_layout_type"])
		_create_node(data["quick_layout_type"], resolved["parent"], resolved["local_pos"], resolved["target_size"])
	elif data.has("quick_layout_move_node"):
		var node: Object = data["quick_layout_move_node"]
		if not (node is Control) or not is_instance_valid(node):
			return
		var ctrl: Control = node
		var grab_offset: Vector2 = data.get("grab_offset", Vector2.ZERO)
		var resolved := _resolve_move_target(at_position, ctrl, grab_offset)
		if resolved["is_reorder"]:
			_reorder_node(ctrl, resolved["parent"], resolved["reorder_index"])
		else:
			_move_node(ctrl, resolved["parent"], resolved["local_pos"])
	# _resolve_move_target/_resolve_create_target repopulate the alignment
	# guides for this final commit, but the drag is over now, so there's
	# nothing left to show them against — NOTIFICATION_DRAG_END also clears
	# these, but doing it here too avoids a stray redraw with stale lines.
	_align_guide_v_lines = []
	_align_guide_h_lines = []


## The project's configured design resolution (Project Settings -> Display
## -> Window -> Viewport Width/Height) — the same reference size Godot's own
## UI scaling uses. This is what the canvas treats as "the screen," so the
## schematic shows where things really sit on the actual game viewport,
## instead of always zooming to fill the canvas with just build_target.
func _get_viewport_reference_size() -> Vector2:
	var w: float = ProjectSettings.get_setting("display/window/size/viewport_width", 1152)
	var h: float = ProjectSettings.get_setting("display/window/size/viewport_height", 648)
	return Vector2(w, h)


## Reference size the canvas scales against: the project's real viewport
## when viewport_frame_enabled, or build_target's own size otherwise (the
## original "zoom to fill with just build_target" behavior).
func _reference_size() -> Vector2:
	if viewport_frame_enabled:
		return _get_viewport_reference_size()
	if _target_ok() and build_target.size.x > 0 and build_target.size.y > 0:
		return build_target.size
	# A full-rect-anchored root Control's size only resolves against its
	# "parent" (the viewport) once actually running — while just editing the
	# scene it can report as (0, 0) or otherwise degenerate. Falling back to
	# Vector2.ONE here (the old behavior) meant a 1:1 target-to-canvas ratio,
	# which pushes almost everything off the edge of a canvas that's only a
	# few hundred pixels wide. The project's configured viewport size is a
	# much more sensible fallback — it's what a full-rect root is for.
	return _get_viewport_reference_size()


## A single uniform scale factor (not independent x/y) so content keeps its
## real aspect ratio regardless of the panel's own shape — a square button
## stays square instead of stretching into a rectangle whenever the panel's
## aspect ratio doesn't match the reference size's. The smaller of the two
## axis-fits is used so the whole reference frame stays visible
## (letterboxed on the other axis) rather than overflowing it.
func _target_to_canvas_ratio() -> Vector2:
	var ref_size := _reference_size()
	if ref_size.x <= 0 or ref_size.y <= 0:
		return Vector2.ONE
	var uniform: float = min(size.x / ref_size.x, size.y / ref_size.y) * _zoom
	return Vector2(uniform, uniform)


func _canvas_to_target_ratio() -> Vector2:
	var ratio := _target_to_canvas_ratio()
	if ratio.x <= 0 or ratio.y <= 0:
		return Vector2.ONE
	return Vector2.ONE / ratio


## Public accessor so external Controls (the rulers) can align their tick
## spacing to the same scale the canvas is currently drawing at, without
## reaching into a "private" (underscore) method by name.
func get_target_to_canvas_ratio() -> Vector2:
	return _target_to_canvas_ratio()


## With a uniform ratio, the reference frame (see _reference_size) won't
## generally fill the canvas exactly on both axes — this centers it
## (letterboxed on whichever axis has slack) rather than leaving it pinned
## to the top-left corner.
func _center_offset(ratio: Vector2) -> Vector2:
	return (size - _reference_size() * ratio) / 2.0


## Public accessor combining manual pan (middle-drag) with the automatic
## centering offset above — this is the actual canvas-space offset any
## external consumer (the rulers) needs, not just the raw manual pan delta.
## Takes ratio explicitly since callers already have it on hand.
func get_effective_pan(ratio: Vector2) -> Vector2:
	return _pan_offset + _center_offset(ratio)


func reset_view() -> void:
	_pan_offset = Vector2.ZERO
	_zoom = 1.0
	queue_redraw()
	view_changed.emit()


## Zooms in/out by factor, keeping canvas_pos (the cursor) fixed on-screen —
## standard "zoom to cursor" so scrolling doesn't send the content sliding
## away from wherever you're actually pointing. Has to account for the
## centering offset also shifting with ratio (uniform scale, so a single
## scalar k relates the old and new ratio), not just the raw pan delta.
func _zoom_at(canvas_pos: Vector2, factor: float) -> void:
	var old_zoom := _zoom
	var new_zoom: float = clamp(_zoom * factor, MIN_ZOOM, MAX_ZOOM)
	if is_equal_approx(new_zoom, old_zoom):
		return

	var old_ratio := _target_to_canvas_ratio()
	var old_center := _center_offset(old_ratio)

	_zoom = new_zoom
	var new_ratio := _target_to_canvas_ratio()
	var new_center := _center_offset(new_ratio)

	var k: float = new_ratio.x / old_ratio.x
	_pan_offset = canvas_pos - (canvas_pos - old_center - _pan_offset) * k - new_center

	queue_redraw()
	view_changed.emit()


## The topmost Control reachable by walking straight up build_target's
## ancestor chain — treated as sitting at the viewport's (0, 0), same
## assumption as the rest of this plugin's "good enough schematic" scoping
## (exact for a typical full-rect-anchored root UI Control). When
## viewport_frame_enabled is off, build_target itself is the origin instead
## (the original behavior), so its own box always fills the canvas exactly.
func _viewport_root() -> Control:
	if not _target_ok():
		return null
	if not viewport_frame_enabled:
		return build_target
	var top: Control = build_target
	var n: Node = build_target.get_parent()
	while n is Control:
		top = n
		n = n.get_parent()
	return top


# --- Canvas-space geometry of nested descendants: accumulate local
#     positions up to (but not including) the viewport root, then scale. ---

func _canvas_rect_for(node: Control, ratio: Vector2) -> Rect2:
	var vp_root := _viewport_root()
	var pos := Vector2.ZERO
	var n: Node = node
	while n != null and n != vp_root:
		if n is Control:
			pos += (n as Control).position
		n = n.get_parent()
	return Rect2(pos * ratio + get_effective_pan(ratio), node.size * ratio)


## Same as _canvas_rect_for, but uses override_pos/override_size for node's
## own contribution instead of its real position/size — used to preview a
## resize in progress before it's committed.
func _canvas_rect_for_override(node: Control, ratio: Vector2, override_pos: Vector2, override_size: Vector2) -> Rect2:
	var vp_root := _viewport_root()
	var pos := override_pos
	var n: Node = node.get_parent()
	while n != null and n != vp_root:
		if n is Control:
			pos += (n as Control).position
		n = n.get_parent()
	return Rect2(pos * ratio + get_effective_pan(ratio), override_size * ratio)


# --- Resize handles: shown on the single selected node (if it's part of
#     build_target's subtree) so it can be dragged straight from its box
#     instead of typing exact sizes in the Inspector. -----------------------

func _get_selected_resizable_node() -> Control:
	if editor_interface == null or not _target_ok():
		return null
	var selected := editor_interface.get_selection().get_selected_nodes()
	if selected.size() != 1:
		return null
	var node: Node = selected[0]
	# A Container recalculates its children's size every layout pass, so a
	# manual resize here wouldn't actually stick at runtime — no handles for
	# those rather than let you "resize" something that snaps right back.
	if node is Control and node != build_target and is_within_build_target(node) \
			and not (node.get_parent() is Container):
		return node
	return null


func _handle_positions(r: Rect2) -> Dictionary:
	return {
		ResizeHandle.TOP_LEFT: r.position,
		ResizeHandle.TOP: r.position + Vector2(r.size.x / 2.0, 0),
		ResizeHandle.TOP_RIGHT: r.position + Vector2(r.size.x, 0),
		ResizeHandle.RIGHT: r.position + Vector2(r.size.x, r.size.y / 2.0),
		ResizeHandle.BOTTOM_RIGHT: r.position + r.size,
		ResizeHandle.BOTTOM: r.position + Vector2(r.size.x / 2.0, r.size.y),
		ResizeHandle.BOTTOM_LEFT: r.position + Vector2(0, r.size.y),
		ResizeHandle.LEFT: r.position + Vector2(0, r.size.y / 2.0),
	}


func _handle_at_position(at_position: Vector2) -> int:
	var node := _get_selected_resizable_node()
	if node == null:
		return ResizeHandle.NONE
	var r := _canvas_rect_for(node, _target_to_canvas_ratio())
	var handles := _handle_positions(r)
	for handle_id in handles:
		if (handles[handle_id] as Vector2).distance_to(at_position) <= HANDLE_GRAB_RADIUS:
			return handle_id
	return ResizeHandle.NONE


func _cursor_for_handle(handle: int) -> Control.CursorShape:
	match handle:
		ResizeHandle.TOP_LEFT, ResizeHandle.BOTTOM_RIGHT:
			return Control.CURSOR_FDIAGSIZE
		ResizeHandle.TOP_RIGHT, ResizeHandle.BOTTOM_LEFT:
			return Control.CURSOR_BDIAGSIZE
		ResizeHandle.TOP, ResizeHandle.BOTTOM:
			return Control.CURSOR_VSIZE
		ResizeHandle.LEFT, ResizeHandle.RIGHT:
			return Control.CURSOR_HSIZE
		_:
			return Control.CURSOR_ARROW


## Handles that drag the left/top edge, as opposed to leaving it fixed and
## only moving the right/bottom edge.
const LEFT_MOVING_HANDLES := [ResizeHandle.TOP_LEFT, ResizeHandle.BOTTOM_LEFT, ResizeHandle.LEFT]
const TOP_MOVING_HANDLES := [ResizeHandle.TOP_LEFT, ResizeHandle.TOP_RIGHT, ResizeHandle.TOP]


func _snap_scalar(value: float) -> float:
	if not snap_to_grid_enabled or grid_size <= 0:
		return value
	return round(value / grid_size) * grid_size


func _update_resize_preview(mouse_pos: Vector2) -> void:
	var ratio := _target_to_canvas_ratio()
	var delta_local: Vector2 = (mouse_pos - _resize_start_mouse) / ratio

	# Work in edges (left/top/right/bottom), not pos/size: only the edge(s)
	# the active handle actually drags should ever move or get snapped — the
	# opposite edge must stay exactly where it started, snapped or not.
	var left := _resize_start_local_pos.x
	var top := _resize_start_local_pos.y
	var right := _resize_start_local_pos.x + _resize_start_local_size.x
	var bottom := _resize_start_local_pos.y + _resize_start_local_size.y

	if _resize_handle in LEFT_MOVING_HANDLES:
		left = _snap_scalar(left + delta_local.x)
	elif _resize_handle in [ResizeHandle.TOP_RIGHT, ResizeHandle.RIGHT, ResizeHandle.BOTTOM_RIGHT]:
		right = _snap_scalar(right + delta_local.x)

	if _resize_handle in TOP_MOVING_HANDLES:
		top = _snap_scalar(top + delta_local.y)
	elif _resize_handle in [ResizeHandle.BOTTOM_LEFT, ResizeHandle.BOTTOM, ResizeHandle.BOTTOM_RIGHT]:
		bottom = _snap_scalar(bottom + delta_local.y)

	var pos := Vector2(left, top)
	var sz := Vector2(right - left, bottom - top)

	# Enforce the minimum without letting the fixed edge move: if a
	# left/top-moving handle got clamped, recompute that edge from the
	# clamped size so the opposite (fixed) edge stays exactly put.
	if sz.x < MIN_RESIZE_SIZE:
		sz.x = MIN_RESIZE_SIZE
		if _resize_handle in LEFT_MOVING_HANDLES:
			pos.x = right - sz.x
	if sz.y < MIN_RESIZE_SIZE:
		sz.y = MIN_RESIZE_SIZE
		if _resize_handle in TOP_MOVING_HANDLES:
			pos.y = bottom - sz.y

	_resize_preview_local_pos = pos
	_resize_preview_local_size = sz


func _commit_resize() -> void:
	var node := _resizing_node
	_resizing_node = null
	_resize_handle = ResizeHandle.NONE
	if not is_instance_valid(node) or undo_redo == null:
		queue_redraw()
		return
	if _resize_preview_local_pos == _resize_start_local_pos \
			and _resize_preview_local_size == _resize_start_local_size:
		queue_redraw()
		return

	undo_redo.create_action("Quick Layout: Resize %s" % node.name)
	undo_redo.add_do_property(node, "position", _resize_preview_local_pos)
	undo_redo.add_do_property(node, "size", _resize_preview_local_size)
	undo_redo.add_undo_property(node, "position", _resize_start_local_pos)
	undo_redo.add_undo_property(node, "size", _resize_start_local_size)
	undo_redo.commit_action()

	if editor_interface != null:
		editor_interface.get_selection().clear()
		editor_interface.get_selection().add_node(node)

	node_resized.emit(node)
	queue_redraw()


# --- Click-to-select ---------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if not _target_ok() or editor_interface == null:
		return

	if event is InputEventMouseButton:
		if event.pressed:
			# Ctrl+D only reaches _gui_input while this control holds
			# keyboard focus — grab it on any click so the shortcut works
			# right after interacting with the canvas.
			grab_focus()
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			var handle := _handle_at_position(event.position)
			if handle != ResizeHandle.NONE:
				var resize_node := _get_selected_resizable_node()
				if resize_node != null:
					_resizing_node = resize_node
					_resize_handle = handle
					_resize_start_mouse = event.position
					_resize_start_local_pos = resize_node.position
					_resize_start_local_size = resize_node.size
					_resize_preview_local_pos = resize_node.position
					_resize_preview_local_size = resize_node.size
					accept_event()
					return
			# Don't change selection yet — a plain click should pick the
			# topmost box, but a drag starting here should move whatever's
			# already selected if it's under the cursor (see _drag_source_for).
			# Which one this is isn't known until release/drag-start, so the
			# actual selection update happens then.
			_press_chain = _hit_chain_at(event.position)
			_press_alt = event.alt_pressed
			_press_position = event.position
			_press_active = true
			_drag_started = false
			accept_event()
		elif not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			if _resizing_node != null:
				_commit_resize()
				accept_event()
			elif _box_selecting:
				_commit_box_select(event.shift_pressed)
				_box_selecting = false
				queue_redraw()
				accept_event()
			elif not _drag_started:
				if not _press_chain.is_empty():
					var target: Control = _press_chain[_press_chain.size() - 1]
					if _press_alt:
						target = _step_up_chain(_press_chain)
					var sel := editor_interface.get_selection()
					if event.shift_pressed:
						# EditorSelection has no is_selected() — check
						# membership in get_selected_nodes() instead.
						if sel.get_selected_nodes().has(target):
							sel.remove_node(target)
						else:
							sel.add_node(target)
					else:
						sel.clear()
						sel.add_node(target)
					queue_redraw()
				elif not editor_interface.get_selection().get_selected_nodes().is_empty() \
						and not event.shift_pressed:
					# Clicked empty canvas space — deselect, same as clicking
					# off any shape in a design tool. Shift+click on empty
					# space leaves the existing selection alone rather than
					# risking an accidental wipe.
					editor_interface.get_selection().clear()
					queue_redraw()
				accept_event()
			_press_chain = []
			_press_active = false
			_drag_started = false
		elif event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
			var node := _node_at_position(event.position)
			if node != null:
				# Right-clicking a node that's already part of a multi-
				# selection keeps the whole selection (so "Delete Selected"
				# can act on all of it) instead of collapsing down to just
				# the clicked one, same as Explorer/Finder-style behavior.
				var current_selected := editor_interface.get_selection().get_selected_nodes()
				var is_multi := current_selected.size() > 1 and current_selected.has(node)
				if not is_multi:
					editor_interface.get_selection().clear()
					editor_interface.get_selection().add_node(node)
					queue_redraw()
				_context_menu_node = node
				_context_menu_parent = null
				_context_menu_paste_target = node
				_context_menu.clear()
				if is_multi:
					_context_menu.add_item("Duplicate Selected (%d)  (Ctrl+D)" % current_selected.size(), 4)
					_context_menu.add_item("Copy Selected (%d)  (Ctrl+C)" % current_selected.size(), 5)
					_context_menu.add_item("Delete Selected (%d)" % current_selected.size(), 3)
				else:
					_context_menu.add_item("Delete %s" % node.name, 0)
					_context_menu.add_item("Duplicate %s  (Ctrl+D)" % node.name, 2)
					_context_menu.add_item("Copy %s  (Ctrl+C)" % node.name, 5)
					var parent := node.get_parent()
					if parent is Control:
						_context_menu_parent = parent
						_context_menu.add_item("Select Parent (%s)" % parent.name, 1)
				if not _clipboard.is_empty():
					_context_menu.add_item("Paste into %s  (Ctrl+V)" % node.name, 6)
				# event.global_position is relative to whichever window
				# received the click, not true desktop coordinates — normally
				# harmless since the editor's one window starts near the
				# screen origin, but once this panel is floated into its own
				# window (see plugin.gd's add_control_to_dock) that window
				# can sit anywhere, including a second monitor to the left
				# with negative screen coordinates. Popup.position expects
				# real desktop-absolute coordinates, so query the OS cursor
				# position directly instead.
				_context_menu.position = DisplayServer.mouse_get_position()
				_context_menu.popup()
				accept_event()
			elif _target_ok() and not _clipboard.is_empty():
				# Right-clicking empty canvas space with something on the
				# clipboard: paste into build_target, same as how a plain
				# drop on empty space falls back to it elsewhere.
				_context_menu_node = null
				_context_menu_parent = null
				_context_menu_paste_target = build_target
				_context_menu.clear()
				_context_menu.add_item("Paste into %s  (Ctrl+V)" % build_target.name, 6)
				_context_menu.position = DisplayServer.mouse_get_position()
				_context_menu.popup()
				accept_event()
		elif event.pressed and event.button_index == MOUSE_BUTTON_MIDDLE:
			_panning = true
			_pan_start_mouse = event.position
			_pan_start_offset = _pan_offset
			mouse_default_cursor_shape = Control.CURSOR_MOVE
			accept_event()
		elif not event.pressed and event.button_index == MOUSE_BUTTON_MIDDLE:
			_panning = false
			mouse_default_cursor_shape = Control.CURSOR_ARROW
			accept_event()
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_at(event.position, ZOOM_STEP)
			accept_event()
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_at(event.position, 1.0 / ZOOM_STEP)
			accept_event()
	elif event is InputEventMouseMotion:
		if _panning:
			_pan_offset = _pan_start_offset + (event.position - _pan_start_mouse)
			queue_redraw()
			view_changed.emit()
			accept_event()
		elif _resizing_node != null and is_instance_valid(_resizing_node):
			_update_resize_preview(event.position)
			queue_redraw()
			accept_event()
		elif _box_selecting:
			_box_select_current = event.position
			queue_redraw()
			accept_event()
		elif _press_active and _press_chain.is_empty() \
				and event.position.distance_to(_press_position) > BOX_SELECT_START_THRESHOLD:
			# A press-drag that started over empty canvas space (never over a
			# node — that always means "move it" instead) becomes a
			# rubber-band multi-select.
			_box_selecting = true
			_box_select_start = _press_position
			_box_select_current = event.position
			queue_redraw()
			accept_event()
		else:
			mouse_default_cursor_shape = _cursor_for_handle(_handle_at_position(event.position))
			var hovered := _node_at_position(event.position)
			if hovered != _hovered_node:
				_hovered_node = hovered
				node_hover_changed.emit(hovered)
	elif event is InputEventKey:
		if event.pressed and not event.echo and event.keycode == KEY_D and event.ctrl_pressed:
			var selected := editor_interface.get_selection().get_selected_nodes()
			if selected.size() == 1 and selected[0] is Control:
				duplicate_node(selected[0])
				accept_event()
			elif selected.size() > 1:
				duplicate_selected(selected)
				accept_event()
		elif event.pressed and not event.echo and event.keycode == KEY_C and event.ctrl_pressed:
			var selected := editor_interface.get_selection().get_selected_nodes()
			if not selected.is_empty():
				copy_to_clipboard(selected)
				accept_event()
		elif event.pressed and not event.echo and event.keycode == KEY_V and event.ctrl_pressed:
			if not _clipboard.is_empty():
				paste_clipboard(_get_paste_target())
				accept_event()


func _on_context_menu_id_pressed(id: int) -> void:
	if id == 0 and _context_menu_node != null:
		delete_node(_context_menu_node)
	elif id == 1 and _context_menu_parent != null and editor_interface != null:
		editor_interface.get_selection().clear()
		editor_interface.get_selection().add_node(_context_menu_parent)
		queue_redraw()
	elif id == 2 and _context_menu_node != null:
		duplicate_node(_context_menu_node)
	elif id == 3 and editor_interface != null:
		# Each delete_node() call commits its own undo/redo action, same as
		# the "Delete Selected" toolbar button — not a single batched step.
		for node in editor_interface.get_selection().get_selected_nodes():
			if node is Control and node != build_target and is_within_build_target(node):
				delete_node(node)
	elif id == 4 and editor_interface != null:
		duplicate_selected(editor_interface.get_selection().get_selected_nodes())
	elif id == 5 and editor_interface != null:
		copy_to_clipboard(editor_interface.get_selection().get_selected_nodes())
	elif id == 6 and _context_menu_paste_target != null:
		paste_clipboard(_context_menu_paste_target)
	_context_menu_node = null
	_context_menu_parent = null
	_context_menu_paste_target = null


# --- Hit-testing / drag source: finds the deepest nested box under a point,
#     so both click-to-select and drag operations can target nested
#     containers directly, not just build_target's direct children. --------

func _node_at_position(at_position: Vector2) -> Control:
	if not _target_ok():
		return null
	return _find_deepest_at(build_target, at_position, _target_to_canvas_ratio(), null)


## Full parent-to-child chain of boxes under at_position (e.g. a
## VBoxContainer whose children fill it entirely, then the Button on top).
## Lets click-to-select reach a fully-covered container that a plain
## deepest-hit test could never pick.
func _hit_chain_at(at_position: Vector2) -> Array:
	var chain: Array = []
	if not _target_ok():
		return chain
	var ratio := _target_to_canvas_ratio()
	var parent: Node = build_target
	while true:
		var next: Control = null
		var children := parent.get_children()
		for i in range(children.size() - 1, -1, -1):
			var c: Node = children[i]
			if c is Control:
				var r := _canvas_rect_for(c, ratio)
				if r.has_point(at_position):
					next = c
					break
		if next == null:
			break
		chain.append(next)
		parent = next
	return chain


## Applies a completed rubber-band selection to the real EditorSelection —
## additive (Shift held) adds to whatever was already selected, otherwise
## replaces it.
func _commit_box_select(additive: bool) -> void:
	if not _target_ok() or editor_interface == null:
		return
	var band := Rect2(_box_select_start, _box_select_current - _box_select_start).abs()
	var ratio := _target_to_canvas_ratio()
	var hits: Array[Control] = []
	_collect_box_select_hits(build_target, band, ratio, hits)

	# Skip any hit whose ancestor is also in the hit set, so dragging a band
	# over a container and its children doesn't select both — just the
	# outermost one, matching how you'd expect a single rubber-band pass to
	# resolve overlapping nesting.
	var top_hits: Array[Control] = []
	for node in hits:
		var has_selected_ancestor := false
		for other in hits:
			if other != node and _is_descendant_of(node, other):
				has_selected_ancestor = true
				break
		if not has_selected_ancestor:
			top_hits.append(node)

	var sel := editor_interface.get_selection()
	if not additive:
		sel.clear()
	var already_selected := sel.get_selected_nodes()
	for node in top_hits:
		if not already_selected.has(node):
			sel.add_node(node)


func _collect_box_select_hits(parent: Node, band: Rect2, ratio: Vector2, out: Array[Control]) -> void:
	for child in parent.get_children():
		if child is Control:
			var r := _canvas_rect_for(child as Control, ratio)
			if band.intersects(r):
				out.append(child)
			_collect_box_select_hits(child, band, ratio, out)


## Alt+Click target: one level up from whatever's currently selected, if
## that selection is part of this click's hit chain (so repeated Alt+Clicks
## on the same spot walk further up each time); otherwise one level up from
## the deepest hit, same as a first Alt+Click would give.
func _step_up_chain(chain: Array) -> Control:
	var selected := editor_interface.get_selection().get_selected_nodes()
	if selected.size() == 1 and chain.has(selected[0]):
		var idx: int = chain.find(selected[0])
		return chain[idx - 1] if idx > 0 else chain[0]
	return chain[chain.size() - 2] if chain.size() >= 2 else chain[0]


func _find_deepest_at(parent: Node, at_position: Vector2, ratio: Vector2, exclude: Node) -> Control:
	var children := parent.get_children()
	# Reverse order: last child draws on top, so it should be hit-tested first.
	for i in range(children.size() - 1, -1, -1):
		var c: Node = children[i]
		if c is Control and c != exclude and not _is_descendant_of(c, exclude):
			var ctrl: Control = c
			var r := _canvas_rect_for(ctrl, ratio)
			if r.has_point(at_position):
				var deeper := _find_deepest_at(ctrl, at_position, ratio, exclude)
				return deeper if deeper != null else ctrl
	return null


func _is_descendant_of(node: Node, ancestor: Node) -> bool:
	if ancestor == null:
		return false
	var n := node.get_parent()
	while n != null:
		if n == ancestor:
			return true
		n = n.get_parent()
	return false


func _get_drag_data(at_position: Vector2) -> Variant:
	if _resizing_node != null or _handle_at_position(at_position) != ResizeHandle.NONE:
		return null
	_drag_started = true
	var ctrl := _drag_source_for(at_position)
	if ctrl == null:
		return null
	var preview := Label.new()
	preview.text = "Move: " + ctrl.name
	preview.modulate = Color(1, 1, 1, 0.85)
	set_drag_preview(preview)
	var r := _canvas_rect_for(ctrl, _target_to_canvas_ratio())
	var grab_offset: Vector2 = at_position - r.position
	return {"quick_layout_move_node": ctrl, "grab_offset": grab_offset}


## Whatever's already selected takes priority for dragging, as long as it's
## part of the chain under the press — this is what lets you move a
## VBoxContainer whose buttons fill it completely: select it first (e.g. via
## Alt+Click or "Select Parent"), then drag from anywhere inside it. Falls
## back to the topmost/deepest box under the cursor otherwise.
func _drag_source_for(at_position: Vector2) -> Control:
	var chain: Array = _press_chain if not _press_chain.is_empty() else _hit_chain_at(at_position)
	if chain.is_empty():
		return null
	if editor_interface != null:
		var selected := editor_interface.get_selection().get_selected_nodes()
		if selected.size() == 1 and chain.has(selected[0]):
			return selected[0]
	return chain[chain.size() - 1]


# --- Node creation / movement ----------------------------------------------

## parent/local_pos/target_size come pre-resolved from _resolve_create_target
## (shared with the live drag preview) so the node lands exactly where the
## preview showed it, alignment-guide snapping included, instead of this
## recomputing its own answer independently.
func _create_node(type_name: String, parent: Control, local_pos: Vector2, target_size: Vector2) -> void:
	if not _target_ok() or undo_redo == null or editor_interface == null:
		return
	if not ClassDB.class_exists(type_name) or not ClassDB.can_instantiate(type_name):
		return
	if parent == null or not is_instance_valid(parent):
		parent = build_target

	var new_node: Control = ClassDB.instantiate(type_name)
	if new_node == null:
		return
	new_node.name = type_name

	var edited_root := editor_interface.get_edited_scene_root()
	if edited_root == null:
		return

	undo_redo.create_action("Quick Layout: Add %s" % type_name)
	undo_redo.add_do_method(parent, "add_child", new_node, true)
	undo_redo.add_do_property(new_node, "owner", edited_root)
	undo_redo.add_do_property(new_node, "position", local_pos)
	undo_redo.add_do_property(new_node, "size", target_size)
	if parent is Container:
		# A Container ignores a child's plain size and recomputes it from
		# get_combined_minimum_size() every layout pass — for a freshly
		# created, childless container (e.g. an empty VBoxContainer) that's
		# zero, collapsing it to an invisible dot. custom_minimum_size is the
		# floor Containers actually respect. Only doing this for Container
		# parents keeps free resize-drag untouched elsewhere (already
		# unavailable for Container children regardless — see
		# _get_selected_resizable_node — so this doesn't add a new "why
		# won't it shrink" trap, just makes the existing Custom Min Size
		# field actually matter from the start instead of defaulting to 0x0.
		undo_redo.add_do_property(new_node, "custom_minimum_size", target_size)
	undo_redo.add_do_reference(new_node)
	undo_redo.add_undo_method(parent, "remove_child", new_node)
	undo_redo.commit_action()

	editor_interface.get_selection().clear()
	editor_interface.get_selection().add_node(new_node)

	if parent is Container and not bool(ProjectSettings.get_setting(MIN_SIZE_HINT_SETTING, false)):
		_min_size_hint_label.text = "%s has no content of its own yet, so it would collapse to an invisible 0x0 box inside a container without a floor size. Its Custom Min Size was set to %d x %d — change it in the info panel's Custom Min Size field if you need something different." % [type_name, int(target_size.x), int(target_size.y)]
		_min_size_hint_dont_show_check.button_pressed = false
		_min_size_hint_dialog.popup_centered()

	node_created.emit(new_node)
	queue_redraw()


func _move_node(node: Control, new_parent: Control, new_local_pos: Vector2) -> void:
	if not is_instance_valid(node) or undo_redo == null:
		return
	var old_parent := node.get_parent()
	if new_parent == null or not is_instance_valid(new_parent):
		new_parent = old_parent

	undo_redo.create_action("Quick Layout: Move %s" % node.name)
	if new_parent != old_parent:
		var edited_root: Node = editor_interface.get_edited_scene_root() if editor_interface != null else null
		var old_index := node.get_index()
		undo_redo.add_do_method(old_parent, "remove_child", node)
		undo_redo.add_do_method(new_parent, "add_child", node, true)
		undo_redo.add_do_property(node, "position", new_local_pos)
		if edited_root != null:
			# Reaffirm owner on the WHOLE subtree, not just node itself —
			# reparenting a node with children only fixing up its own owner
			# left descendants' owner untouched, and if that was ever stale
			# for any reason, they'd silently stop appearing in (and saving
			# with) the scene, since the Scene tree only shows/saves nodes
			# whose owner correctly traces back to the scene root.
			undo_redo.add_do_method(self, "_set_owner_recursive_including_root", node, edited_root)
		undo_redo.add_undo_method(new_parent, "remove_child", node)
		undo_redo.add_undo_method(old_parent, "add_child", node, true)
		undo_redo.add_undo_method(old_parent, "move_child", node, old_index)
		undo_redo.add_undo_property(node, "position", node.position)
		if edited_root != null:
			undo_redo.add_undo_method(self, "_set_owner_recursive_including_root", node, edited_root)
	else:
		undo_redo.add_do_property(node, "position", new_local_pos)
		undo_redo.add_undo_property(node, "position", node.position)
	undo_redo.commit_action()

	if editor_interface != null:
		editor_interface.get_selection().clear()
		editor_interface.get_selection().add_node(node)

	node_moved.emit(node)
	queue_redraw()


func _set_owner_recursive_including_root(node: Node, owner: Node) -> void:
	node.owner = owner
	for child in node.get_children():
		_set_owner_recursive_including_root(child, owner)


## Reorders a node among its current siblings within the same Container —
## the one thing that actually changes a Container child's real layout
## position, since the Container ignores its raw position/size otherwise.
func _reorder_node(node: Control, parent: Control, target_index: int) -> void:
	if not is_instance_valid(node) or undo_redo == null:
		return
	var old_index := node.get_index()
	if target_index == old_index:
		return

	undo_redo.create_action("Quick Layout: Reorder %s" % node.name)
	undo_redo.add_do_method(parent, "move_child", node, target_index)
	undo_redo.add_undo_method(parent, "move_child", node, old_index)
	undo_redo.commit_action()

	if editor_interface != null:
		editor_interface.get_selection().clear()
		editor_interface.get_selection().add_node(node)

	node_moved.emit(node)
	queue_redraw()


func delete_node(node: Control) -> void:
	if not is_instance_valid(node) or undo_redo == null or not _target_ok() or editor_interface == null:
		return
	var parent := node.get_parent()
	if parent == null:
		return
	var edited_root := editor_interface.get_edited_scene_root()
	var index := node.get_index()

	undo_redo.create_action("Quick Layout: Delete %s" % node.name)
	undo_redo.add_do_method(parent, "remove_child", node)
	undo_redo.add_undo_method(parent, "add_child", node, true)
	undo_redo.add_undo_method(parent, "move_child", node, index)
	if edited_root != null:
		# Same reasoning as _move_node: reaffirm owner on the whole subtree
		# being restored, not just the deleted node itself, so undoing the
		# delete of a node with children doesn't leave those children with
		# stale owner (invisible in / unsaved with the Scene tree).
		undo_redo.add_undo_method(self, "_set_owner_recursive_including_root", node, edited_root)
	undo_redo.add_undo_reference(node)
	undo_redo.commit_action()

	editor_interface.get_selection().clear()
	node_deleted.emit(node)
	queue_redraw()


## Duplicates a node (and its children) as a new sibling right after it,
## nudged slightly so it's visually distinguishable from the original
## instead of landing exactly on top of it.
func duplicate_node(node: Control) -> void:
	var dup_ctrl := _duplicate_node_internal(node)
	if dup_ctrl == null:
		return
	editor_interface.get_selection().clear()
	editor_interface.get_selection().add_node(dup_ctrl)
	node_created.emit(dup_ctrl)
	queue_redraw()


## Duplicates every given node independently (each gets its own undo/redo
## action, same granularity as deleting multiple selected nodes), then
## selects all the new copies together at the end — calling duplicate_node()
## in a loop instead would leave only the last copy selected, since each
## call re-selects on its own.
func duplicate_selected(nodes: Array) -> void:
	if editor_interface == null:
		return
	var new_nodes: Array[Control] = []
	for node in nodes:
		if node is Control:
			var dup_ctrl := _duplicate_node_internal(node)
			if dup_ctrl != null:
				new_nodes.append(dup_ctrl)
	if new_nodes.is_empty():
		return
	editor_interface.get_selection().clear()
	for dup_ctrl in new_nodes:
		editor_interface.get_selection().add_node(dup_ctrl)
	node_created.emit(new_nodes[-1])
	queue_redraw()


func _duplicate_node_internal(node: Control) -> Control:
	if not is_instance_valid(node) or undo_redo == null or not _target_ok() or editor_interface == null:
		return null
	if node == build_target or not is_within_build_target(node):
		return null
	var parent := node.get_parent()
	if parent == null:
		return null
	var edited_root := editor_interface.get_edited_scene_root()
	if edited_root == null:
		return null

	var dup: Node = node.duplicate()
	if not (dup is Control):
		dup.queue_free()
		return null
	var dup_ctrl: Control = dup
	var nudge: float = grid_size if snap_to_grid_enabled and grid_size > 0 else 16.0
	dup_ctrl.position = node.position + Vector2(nudge, nudge)
	var target_index := node.get_index() + 1

	undo_redo.create_action("Quick Layout: Duplicate %s" % node.name)
	undo_redo.add_do_method(parent, "add_child", dup_ctrl, true)
	undo_redo.add_do_method(parent, "move_child", dup_ctrl, target_index)
	undo_redo.add_do_method(self, "_set_owner_recursive_including_root", dup_ctrl, edited_root)
	undo_redo.add_do_reference(dup_ctrl)
	undo_redo.add_undo_method(parent, "remove_child", dup_ctrl)
	undo_redo.commit_action()

	return dup_ctrl


## Copies the given nodes to an in-memory clipboard as orphaned duplicates —
## independent of the originals, so deleting or undoing them afterward
## doesn't affect what's on the clipboard, and pasting re-duplicates from
## these each time so multiple pastes don't share the same instance.
func copy_to_clipboard(nodes: Array) -> void:
	for old in _clipboard:
		if is_instance_valid(old):
			old.queue_free()
	_clipboard.clear()
	for node in nodes:
		if node is Control and node != build_target and is_within_build_target(node):
			var dup: Node = (node as Control).duplicate()
			if dup is Control:
				_clipboard.append(dup)
			else:
				dup.queue_free()


## Which node Ctrl+V should paste into when there's no right-click position
## to anchor it: the single selected node if there is exactly one, otherwise
## build_target.
func _get_paste_target() -> Control:
	if editor_interface != null:
		var selected := editor_interface.get_selection().get_selected_nodes()
		if selected.size() == 1 and selected[0] is Control and is_within_build_target(selected[0]):
			return selected[0]
	return build_target


## Pastes everything on the clipboard as new children of parent, each an
## independent re-duplication (so the clipboard itself stays intact for
## further pastes), as one undo/redo action covering the whole paste.
func paste_clipboard(parent: Control) -> void:
	if _clipboard.is_empty() or undo_redo == null or not _target_ok() or editor_interface == null:
		return
	if parent == null or not is_instance_valid(parent):
		parent = build_target
	var edited_root := editor_interface.get_edited_scene_root()
	if edited_root == null:
		return

	var nudge: float = grid_size if snap_to_grid_enabled and grid_size > 0 else 16.0
	var new_nodes: Array[Control] = []
	undo_redo.create_action("Quick Layout: Paste %d node(s) into %s" % [_clipboard.size(), parent.name])
	for clip_node in _clipboard:
		if not is_instance_valid(clip_node):
			continue
		var dup: Node = clip_node.duplicate()
		if not (dup is Control):
			dup.queue_free()
			continue
		var dup_ctrl: Control = dup
		dup_ctrl.position = clip_node.position + Vector2(nudge, nudge)
		undo_redo.add_do_method(parent, "add_child", dup_ctrl, true)
		undo_redo.add_do_method(self, "_set_owner_recursive_including_root", dup_ctrl, edited_root)
		undo_redo.add_do_reference(dup_ctrl)
		undo_redo.add_undo_method(parent, "remove_child", dup_ctrl)
		new_nodes.append(dup_ctrl)
	if new_nodes.is_empty():
		return
	undo_redo.commit_action()

	editor_interface.get_selection().clear()
	for n in new_nodes:
		editor_interface.get_selection().add_node(n)
	node_created.emit(new_nodes[-1])
	queue_redraw()


# --- Drawing ----------------------------------------------------------------

func _draw() -> void:
	# Neutral workspace background for the whole visible canvas — this is
	# just the "window" you're looking through, not the viewport itself, now
	# that pan/zoom let you look anywhere; see the outline below for that.
	draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.02), true)

	if not _target_ok():
		var font := ThemeDB.fallback_font
		draw_string(font, Vector2(12, 24), "No canvas target set.", HORIZONTAL_ALIGNMENT_LEFT, -1, 14)
		draw_string(font, Vector2(12, 44), "Select a Control node and click 'Use Selected as Target'.", HORIZONTAL_ALIGNMENT_LEFT, -1, 12)
		return

	var ratio := _target_to_canvas_ratio()
	var selected_nodes := []
	if editor_interface != null:
		selected_nodes = editor_interface.get_selection().get_selected_nodes()

	if snap_to_grid_enabled and grid_size > 0:
		_draw_grid(ratio)

	# The reference frame — the project's real viewport in viewport-frame
	# mode, or build_target's own bounds in fit mode — drawn as its own
	# outline, the same idea as the game-screen boundary the main 2D editor
	# draws. Tracks pan/zoom like everything else, so it stays anchored to
	# the actual content instead of just being the canvas's own edge.
	var ref_size := _reference_size()
	var viewport_r := Rect2(get_effective_pan(ratio), ref_size * ratio)
	draw_rect(viewport_r, Color(1, 1, 1, 0.04), true)
	draw_rect(viewport_r, Color(1, 1, 1, 0.3), false, 1.5)

	# Highlight build_target's own bounds within that frame, so it's obvious
	# which region is actually the active editing area. Skipped in "fit"
	# mode, where build_target's box always exactly matches the reference
	# frame drawn above anyway.
	if viewport_frame_enabled:
		var target_r := _canvas_rect_for(build_target, ratio)
		draw_rect(target_r, Color(1, 1, 1, 0.05), true)
		draw_rect(target_r, Color(1, 1, 1, 0.45), false, 1.5)

	_draw_children_recursive(build_target, ratio, selected_nodes)

	if _drag_preview_active:
		if _drag_hover_parent != null and is_instance_valid(_drag_hover_parent):
			# Highlight the box the drop will land inside, so it's obvious
			# before you let go which node becomes the new parent.
			var parent_r := _canvas_rect_for(_drag_hover_parent, ratio)
			draw_rect(parent_r, Color(0.3, 1.0, 0.4, 0.9), false, 3.0)
		draw_rect(_drag_preview_rect, Color(1, 1, 1, 0.12), true)
		draw_rect(_drag_preview_rect, Color(1, 1, 1, 0.95), false, 2.0)

	# Smart alignment guides — bright, distinct from every other canvas color
	# so they read clearly as "snap happened here" against the node boxes.
	const GUIDE_COLOR := Color(1.0, 0.2, 0.45, 0.95)
	for line: Dictionary in _align_guide_v_lines:
		draw_line(Vector2(line["x"], line["y0"]), Vector2(line["x"], line["y1"]), GUIDE_COLOR, 1.0)
	for line: Dictionary in _align_guide_h_lines:
		draw_line(Vector2(line["x0"], line["y"]), Vector2(line["x1"], line["y"]), GUIDE_COLOR, 1.0)

	if _box_selecting:
		var band := Rect2(_box_select_start, _box_select_current - _box_select_start).abs()
		draw_rect(band, Color(0.4, 0.7, 1.0, 0.15), true)
		draw_rect(band, Color(0.4, 0.7, 1.0, 0.9), false, 1.0)

	var resizable := _get_selected_resizable_node()
	if resizable != null:
		var handle_r: Rect2
		if _resizing_node == resizable:
			handle_r = _canvas_rect_for_override(resizable, ratio, _resize_preview_local_pos, _resize_preview_local_size)
		else:
			handle_r = _canvas_rect_for(resizable, ratio)
		_draw_resize_handles(handle_r)


func _draw_resize_handles(r: Rect2) -> void:
	var handles := _handle_positions(r)
	for handle_id in handles:
		var p: Vector2 = handles[handle_id]
		var handle_rect := Rect2(p - Vector2(HANDLE_SIZE, HANDLE_SIZE) / 2.0, Vector2(HANDLE_SIZE, HANDLE_SIZE))
		draw_rect(handle_rect, Color(1, 1, 1, 1.0), true)
		draw_rect(handle_rect, Color(0, 0, 0, 0.8), false, 1.0)


## Faint reference lines every grid_size (target-space) pixels, so "Snap to
## Grid" has something visible to snap *to* instead of being an invisible
## effect you only notice after dragging.
func _draw_grid(ratio: Vector2) -> void:
	var pan := get_effective_pan(ratio)
	var color := Color(1, 1, 1, 0.08)
	var step_x: float = grid_size * ratio.x
	if step_x >= 2.0:
		# Lines sit at k*step_x + pan.x for every integer k, same as any
		# node's canvas position — normalize into [0, step_x) so panning
		# shifts the grid instead of leaving it static under moving content.
		var x: float = fmod(pan.x, step_x)
		if x < 0:
			x += step_x
		while x < size.x:
			draw_line(Vector2(x, 0), Vector2(x, size.y), color, 1.0)
			x += step_x
	var step_y: float = grid_size * ratio.y
	if step_y >= 2.0:
		var y: float = fmod(pan.y, step_y)
		if y < 0:
			y += step_y
		while y < size.y:
			draw_line(Vector2(0, y), Vector2(size.x, y), color, 1.0)
			y += step_y


func _draw_children_recursive(parent: Node, ratio: Vector2, selected_nodes: Array) -> void:
	for child in parent.get_children():
		if child is Control:
			var c: Control = child
			var r: Rect2
			if c == _resizing_node:
				r = _canvas_rect_for_override(c, ratio, _resize_preview_local_pos, _resize_preview_local_size)
			else:
				r = _canvas_rect_for(c, ratio)
			var is_selected: bool = selected_nodes.has(c)
			var fill := Color(1.0, 0.75, 0.2, 0.3) if is_selected else Color(0.3, 0.6, 1.0, 0.22)
			var border := Color(1.0, 0.75, 0.2, 1.0) if is_selected else Color(0.3, 0.6, 1.0, 0.9)
			draw_rect(r, fill, true)
			draw_rect(r, border, false, is_selected and 2.0 or 1.0)
			# A child sitting right at its parent's top-left corner (e.g. the
			# first item in a VBoxContainer) would otherwise draw its label on
			# top of the parent's own, garbling both — skip the parent's label
			# wherever a child box already claims that spot; only the
			# frontmost box's name should show there.
			var label_pos := r.position + Vector2(4, 14)
			if not _label_covered_by_child(c, label_pos, ratio):
				draw_string(ThemeDB.fallback_font, label_pos, c.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 12)
			_draw_children_recursive(c, ratio, selected_nodes)


func _label_covered_by_child(node: Control, label_pos: Vector2, ratio: Vector2) -> bool:
	for child in node.get_children():
		if child is Control:
			var child_r := _canvas_rect_for(child as Control, ratio)
			if child_r.has_point(label_pos):
				return true
	return false
