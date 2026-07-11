@tool
extends RefCounted
class_name QuickLayoutAlignTools

## Operates on Control.position / Control.size directly by default, which is
## exact for default (top-left) anchors and fine for a quick layout pass
## regardless of anchors. align()/distribute() also accept an anchor_aware
## flag: when on, they sync anchors between controls first so the alignment
## survives the parent resizing later, not just at the moment you click the
## button — see the comment above _sync_anchor_x/_y for how and why.

const ACTION_PREFIX := "Quick Layout: "


static func _begin(undo_redo: EditorUndoRedoManager, label: String) -> void:
	undo_redo.create_action(ACTION_PREFIX + label)


static func _track_position(undo_redo: EditorUndoRedoManager, c: Control, new_pos: Vector2) -> void:
	undo_redo.add_do_property(c, "position", new_pos)
	undo_redo.add_undo_property(c, "position", c.position)


static func _track_size(undo_redo: EditorUndoRedoManager, c: Control, new_size: Vector2) -> void:
	undo_redo.add_do_property(c, "size", new_size)
	undo_redo.add_undo_property(c, "size", c.size)


## --- Anchor-aware alignment -------------------------------------------------
## Control.position/size are derived from anchor_*(0-1 fraction of the
## parent's size) + offset_*(pixels from that anchor point). Setting
## `position` directly (as _track_position does) only guarantees the right
## screen position for the parent's *current* size — if the parent later
## resizes, each control's anchor point moves independently, and controls
## with different anchors will drift apart even though nothing "moved" them.
## The only way two controls stay aligned across a future resize is if they
## share the same anchor ratio on the aligned axis, so anchor-aware mode
## syncs that first (then _track_position sets the correct offset for it).
##
## Scoped to "point-anchored" controls (anchor_left == anchor_right, or
## anchor_top == anchor_bottom — the common non-stretching case: pinned to a
## corner/edge/center). A control that intentionally stretches with its
## parent on that axis is left alone rather than silently rewriting its
## stretch behavior.

static func _is_point_anchored_x(c: Control) -> bool:
	return is_equal_approx(c.anchor_left, c.anchor_right)


static func _is_point_anchored_y(c: Control) -> bool:
	return is_equal_approx(c.anchor_top, c.anchor_bottom)


static func _sync_anchor_x(undo_redo: EditorUndoRedoManager, c: Control, reference: Control) -> void:
	if not (_is_point_anchored_x(c) and _is_point_anchored_x(reference)):
		return
	if is_equal_approx(c.anchor_left, reference.anchor_left):
		return
	undo_redo.add_do_property(c, "anchor_left", reference.anchor_left)
	undo_redo.add_do_property(c, "anchor_right", reference.anchor_left)
	undo_redo.add_undo_property(c, "anchor_left", c.anchor_left)
	undo_redo.add_undo_property(c, "anchor_right", c.anchor_right)


static func _sync_anchor_y(undo_redo: EditorUndoRedoManager, c: Control, reference: Control) -> void:
	if not (_is_point_anchored_y(c) and _is_point_anchored_y(reference)):
		return
	if is_equal_approx(c.anchor_top, reference.anchor_top):
		return
	undo_redo.add_do_property(c, "anchor_top", reference.anchor_top)
	undo_redo.add_do_property(c, "anchor_bottom", reference.anchor_top)
	undo_redo.add_undo_property(c, "anchor_top", c.anchor_top)
	undo_redo.add_undo_property(c, "anchor_bottom", c.anchor_bottom)


## edge: "left", "h_center", "right", "top", "v_center", "bottom"
## Reference is the first control in the array (the one selected first).
static func align(controls: Array, edge: String, undo_redo: EditorUndoRedoManager, anchor_aware: bool = false) -> void:
	if controls.size() < 2:
		return
	var reference: Control = controls[0]
	_begin(undo_redo, "Align " + edge)

	for i in range(1, controls.size()):
		var c: Control = controls[i]
		# Anchor sync must happen before _track_position: it's queued as an
		# earlier "do" step, so by the time position is set, Godot solves
		# the offset against the *new* anchor rather than the old one.
		if anchor_aware:
			if edge in ["left", "h_center", "right"]:
				_sync_anchor_x(undo_redo, c, reference)
			else:
				_sync_anchor_y(undo_redo, c, reference)
		var p := c.position
		match edge:
			"left":
				p.x = reference.position.x
			"h_center":
				p.x = reference.position.x + (reference.size.x - c.size.x) / 2.0
			"right":
				p.x = reference.position.x + reference.size.x - c.size.x
			"top":
				p.y = reference.position.y
			"v_center":
				p.y = reference.position.y + (reference.size.y - c.size.y) / 2.0
			"bottom":
				p.y = reference.position.y + reference.size.y - c.size.y
		_track_position(undo_redo, c, p)

	undo_redo.commit_action()


## axis: "horizontal" or "vertical". Distributes evenly between the two
## extreme controls, sorted along that axis, keeping the outer two fixed.
static func distribute(controls: Array, axis: String, undo_redo: EditorUndoRedoManager, anchor_aware: bool = false) -> void:
	if controls.size() < 3:
		return

	var sorted: Array = controls.duplicate()
	if axis == "horizontal":
		sorted.sort_custom(func(a, b): return a.position.x < b.position.x)
	else:
		sorted.sort_custom(func(a, b): return a.position.y < b.position.y)

	_begin(undo_redo, "Distribute " + axis)

	var first: Control = sorted[0]
	var last: Control = sorted[sorted.size() - 1]

	# Same reasoning as align(): the whole row/column only stays evenly
	# spaced after a resize if every control shares one anchor ratio on the
	# distributed axis, so sync everyone to the first (outermost) control.
	if anchor_aware:
		for c in sorted:
			if axis == "horizontal":
				_sync_anchor_x(undo_redo, c, first)
			else:
				_sync_anchor_y(undo_redo, c, first)

	if axis == "horizontal":
		var total_span: float = (last.position.x + last.size.x) - first.position.x
		var total_width := 0.0
		for c in sorted:
			total_width += (c as Control).size.x
		var gap := (total_span - total_width) / float(sorted.size() - 1)
		var cursor: float = first.position.x
		for c in sorted:
			var ctrl: Control = c
			var p := ctrl.position
			p.x = cursor
			_track_position(undo_redo, ctrl, p)
			cursor += ctrl.size.x + gap
	else:
		var total_span: float = (last.position.y + last.size.y) - first.position.y
		var total_height := 0.0
		for c in sorted:
			total_height += (c as Control).size.y
		var gap := (total_span - total_height) / float(sorted.size() - 1)
		var cursor: float = first.position.y
		for c in sorted:
			var ctrl: Control = c
			var p := ctrl.position
			p.y = cursor
			_track_position(undo_redo, ctrl, p)
			cursor += ctrl.size.y + gap

	undo_redo.commit_action()


## dimension: "width", "height", "both". Matches to the first control's size.
static func match_size(controls: Array, dimension: String, undo_redo: EditorUndoRedoManager) -> void:
	if controls.size() < 2:
		return
	var reference: Control = controls[0]
	_begin(undo_redo, "Match Size " + dimension)

	for i in range(1, controls.size()):
		var c: Control = controls[i]
		var s := c.size
		match dimension:
			"width":
				s.x = reference.size.x
			"height":
				s.y = reference.size.y
			"both":
				s = reference.size
		_track_size(undo_redo, c, s)

	undo_redo.commit_action()


static func snap_to_grid(controls: Array, grid_size: Vector2, undo_redo: EditorUndoRedoManager) -> void:
	if controls.is_empty() or grid_size.x <= 0 or grid_size.y <= 0:
		return
	_begin(undo_redo, "Snap to Grid")

	for c in controls:
		var ctrl: Control = c
		var p := ctrl.position
		p.x = round(p.x / grid_size.x) * grid_size.x
		p.y = round(p.y / grid_size.y) * grid_size.y
		_track_position(undo_redo, ctrl, p)

	undo_redo.commit_action()
