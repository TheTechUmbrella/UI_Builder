@tool
extends Control
class_name QuickLayoutCanvas

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
	"CheckBox": Vector2(140, 32),
	"CheckButton": Vector2(140, 32),
	"RichTextLabel": Vector2(220, 100),
	"ScrollContainer": Vector2(220, 160),
	"ItemList": Vector2(220, 140),
	"Tree": Vector2(220, 140),
	"TabContainer": Vector2(260, 160),
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

signal node_created(node: Control)
signal node_moved(node: Control)
signal node_resized(node: Control)
signal node_deleted(node: Control)
signal target_lost()

var _target_watch: Control = null
var _drag_preview_rect: Rect2 = Rect2()
var _drag_preview_active: bool = false
var _drag_hover_parent: Control = null
var _context_menu: PopupMenu
var _context_menu_node: Control = null
var _context_menu_parent: Control = null

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
var _drag_started: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_exited.connect(_on_mouse_exited)
	_context_menu = PopupMenu.new()
	_context_menu.id_pressed.connect(_on_context_menu_id_pressed)
	add_child(_context_menu)


func _on_mouse_exited() -> void:
	if _drag_preview_active:
		_drag_preview_active = false
		_drag_hover_parent = null
		queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END and _drag_preview_active:
		_drag_preview_active = false
		_drag_hover_parent = null
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
func _resolve_move_target(at_position: Vector2, ctrl: Control, grab_offset: Vector2) -> Dictionary:
	var ratio := _target_to_canvas_ratio()
	var parent := _drop_parent_for(at_position, ctrl)
	var parent_origin: Vector2 = Vector2.ZERO if parent == build_target else _canvas_rect_for(parent, ratio).position
	var raw_local_pos: Vector2 = ((at_position - grab_offset) - parent_origin) / ratio
	var local_pos := _maybe_snap_local_pos(raw_local_pos)
	return {"parent": parent, "local_pos": local_pos, "parent_origin": parent_origin, "ratio": ratio}


func _update_drag_preview_rect(at_position: Vector2, data: Dictionary) -> void:
	var ratio := _target_to_canvas_ratio()
	if data.has("quick_layout_type"):
		var target_size: Vector2 = DEFAULT_SIZES.get(data["quick_layout_type"], Vector2(100, 40))
		var canvas_size: Vector2 = target_size * ratio
		_drag_preview_rect = Rect2(at_position - canvas_size / 2.0, canvas_size)
		_drag_hover_parent = _drop_parent_for(at_position)
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
		var parent := _drop_parent_for(at_position)
		_create_node(data["quick_layout_type"], at_position, parent)
	elif data.has("quick_layout_move_node"):
		var node: Object = data["quick_layout_move_node"]
		if not (node is Control) or not is_instance_valid(node):
			return
		var ctrl: Control = node
		var grab_offset: Vector2 = data.get("grab_offset", Vector2.ZERO)
		var resolved := _resolve_move_target(at_position, ctrl, grab_offset)
		_move_node(ctrl, resolved["parent"], resolved["local_pos"])


func _canvas_to_target_ratio() -> Vector2:
	if size.x <= 0 or size.y <= 0 or not _target_ok() \
			or build_target.size.x <= 0 or build_target.size.y <= 0:
		return Vector2.ONE
	return build_target.size / size


func _target_to_canvas_ratio() -> Vector2:
	if not _target_ok() or build_target.size.x <= 0 or build_target.size.y <= 0:
		return Vector2.ONE
	return size / build_target.size


# --- Canvas-space geometry of nested descendants: accumulate local
#     positions up to (but not including) build_target, then scale. ---------

func _canvas_rect_for(node: Control, ratio: Vector2) -> Rect2:
	var pos := Vector2.ZERO
	var n: Node = node
	while n != null and n != build_target:
		if n is Control:
			pos += (n as Control).position
		n = n.get_parent()
	return Rect2(pos * ratio, node.size * ratio)


## Same as _canvas_rect_for, but uses override_pos/override_size for node's
## own contribution instead of its real position/size — used to preview a
## resize in progress before it's committed.
func _canvas_rect_for_override(node: Control, ratio: Vector2, override_pos: Vector2, override_size: Vector2) -> Rect2:
	var pos := override_pos
	var n: Node = node.get_parent()
	while n != null and n != build_target:
		if n is Control:
			pos += (n as Control).position
		n = n.get_parent()
	return Rect2(pos * ratio, override_size * ratio)


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
	if node is Control and node != build_target and is_within_build_target(node):
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
			_drag_started = false
			accept_event()
		elif not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			if _resizing_node != null:
				_commit_resize()
				accept_event()
			elif not _drag_started:
				if not _press_chain.is_empty():
					var target: Control = _press_chain[_press_chain.size() - 1]
					if _press_alt:
						target = _step_up_chain(_press_chain)
					editor_interface.get_selection().clear()
					editor_interface.get_selection().add_node(target)
					queue_redraw()
				elif not editor_interface.get_selection().get_selected_nodes().is_empty():
					# Clicked empty canvas space — deselect, same as clicking
					# off any shape in a design tool.
					editor_interface.get_selection().clear()
					queue_redraw()
				accept_event()
			_press_chain = []
			_drag_started = false
		elif event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
			var node := _node_at_position(event.position)
			if node != null:
				editor_interface.get_selection().clear()
				editor_interface.get_selection().add_node(node)
				queue_redraw()
				_context_menu_node = node
				_context_menu_parent = null
				_context_menu.clear()
				_context_menu.add_item("Delete %s" % node.name, 0)
				var parent := node.get_parent()
				if parent is Control:
					_context_menu_parent = parent
					_context_menu.add_item("Select Parent (%s)" % parent.name, 1)
				_context_menu.position = Vector2i(event.global_position)
				_context_menu.popup()
				accept_event()
	elif event is InputEventMouseMotion:
		if _resizing_node != null and is_instance_valid(_resizing_node):
			_update_resize_preview(event.position)
			queue_redraw()
			accept_event()
		else:
			mouse_default_cursor_shape = _cursor_for_handle(_handle_at_position(event.position))


func _on_context_menu_id_pressed(id: int) -> void:
	if id == 0 and _context_menu_node != null:
		delete_node(_context_menu_node)
	elif id == 1 and _context_menu_parent != null and editor_interface != null:
		editor_interface.get_selection().clear()
		editor_interface.get_selection().add_node(_context_menu_parent)
		queue_redraw()
	_context_menu_node = null
	_context_menu_parent = null


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

func _create_node(type_name: String, drop_pos: Vector2, parent: Control) -> void:
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

	var target_size: Vector2 = DEFAULT_SIZES.get(type_name, Vector2(100, 40))
	var ratio := _target_to_canvas_ratio()
	var parent_origin: Vector2 = Vector2.ZERO if parent == build_target else _canvas_rect_for(parent, ratio).position
	var canvas_size: Vector2 = target_size * ratio
	var local_pos: Vector2 = (drop_pos - canvas_size / 2.0 - parent_origin) / ratio

	var edited_root := editor_interface.get_edited_scene_root()
	if edited_root == null:
		return

	undo_redo.create_action("Quick Layout: Add %s" % type_name)
	undo_redo.add_do_method(parent, "add_child", new_node, true)
	undo_redo.add_do_property(new_node, "owner", edited_root)
	undo_redo.add_do_property(new_node, "position", local_pos)
	undo_redo.add_do_property(new_node, "size", target_size)
	undo_redo.add_do_reference(new_node)
	undo_redo.add_undo_method(parent, "remove_child", new_node)
	undo_redo.commit_action()

	editor_interface.get_selection().clear()
	editor_interface.get_selection().add_node(new_node)

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
			undo_redo.add_do_property(node, "owner", edited_root)
		undo_redo.add_undo_method(new_parent, "remove_child", node)
		undo_redo.add_undo_method(old_parent, "add_child", node, true)
		undo_redo.add_undo_method(old_parent, "move_child", node, old_index)
		undo_redo.add_undo_property(node, "position", node.position)
		if edited_root != null:
			undo_redo.add_undo_property(node, "owner", edited_root)
	else:
		undo_redo.add_do_property(node, "position", new_local_pos)
		undo_redo.add_undo_property(node, "position", node.position)
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
		undo_redo.add_undo_property(node, "owner", edited_root)
	undo_redo.add_undo_reference(node)
	undo_redo.commit_action()

	editor_interface.get_selection().clear()
	node_deleted.emit(node)
	queue_redraw()


# --- Drawing ----------------------------------------------------------------

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.04), true)
	draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.25), false, 1.0)

	if not _target_ok():
		var font := ThemeDB.fallback_font
		draw_string(font, Vector2(12, 24), "No canvas target set.", HORIZONTAL_ALIGNMENT_LEFT, -1, 14)
		draw_string(font, Vector2(12, 44), "Select a Control node and click 'Use Selected as Target'.", HORIZONTAL_ALIGNMENT_LEFT, -1, 12)
		return

	var ratio := _target_to_canvas_ratio()
	var selected_nodes := []
	if editor_interface != null:
		selected_nodes = editor_interface.get_selection().get_selected_nodes()

	_draw_children_recursive(build_target, ratio, selected_nodes)

	if _drag_preview_active:
		if _drag_hover_parent != null and is_instance_valid(_drag_hover_parent) and _drag_hover_parent != build_target:
			# Highlight the box the drop will land inside, so it's obvious
			# before you let go which node becomes the new parent.
			var parent_r := _canvas_rect_for(_drag_hover_parent, ratio)
			draw_rect(parent_r, Color(0.3, 1.0, 0.4, 0.9), false, 3.0)
		draw_rect(_drag_preview_rect, Color(1, 1, 1, 0.12), true)
		draw_rect(_drag_preview_rect, Color(1, 1, 1, 0.95), false, 2.0)

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
			draw_string(ThemeDB.fallback_font, r.position + Vector2(4, 14), c.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 12)
			_draw_children_recursive(c, ratio, selected_nodes)
