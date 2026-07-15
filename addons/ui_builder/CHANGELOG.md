# Changelog

All notable changes to this addon are documented here. Format loosely follows
[Keep a Changelog](https://keepachangelog.com/), versions match `plugin.cfg`.

## [Unreleased]

- Added Escape to deselect, or cancel an in-progress resize or rubber-band
  select — same priority order as release-handling elsewhere (resize takes
  priority, then box-select, then deselect).
- Fixed: a node whose rendered bounds overflow its own parent's rect (e.g.
  an HSplitContainer wider than the plain Panel it's inside, which doesn't
  clip) was unreachable by click, drag, right-click, or Alt+Click anywhere
  outside the parent's own bounds — the hit-test only ever looked at a
  node's children if the node's own rect contained the click first, so an
  overflowing child was invisible to hit-testing entirely in that region.
  Affects selection, drag-source resolution, and drop-target resolution.
- Added group-drag: dragging one node of a multi-selection now moves every
  other selected node along with it, by the same amount, instead of moving
  just the one under the cursor. Skips Container children (can't be freely
  positioned) and reparenting/reordering only ever applies to the primary
  dragged node — the rest just shift in place within their own parents.
  Committed as its own undo step, and the full group stays selected
  afterward.
- Added an **Alignment Guides** checkbox to the UI Builder toolbar, mirroring
  the existing Project Settings toggle — a faster way to flip it mid-session
  than opening Project Settings, since it's great for aligning but can get in
  the way of free positioning.

## [1.1.0] - 2026-07-12

- Fixed: dragging the dock panel below the palette list's true minimum
  height didn't shrink it — the buttons kept rendering at full size past the
  panel's allocated space and visually overlapped the bottom tab strip
  (Output/Debugger/etc.) below it. The panel now clips its content to its
  own bounds, so an undersized panel just shows fewer buttons (already
  scrollable) instead of bleeding into the tabs.
- Added a small ✕ button next to Custom Min Size that resets both fields to
  0 in a single undo step.
- Fixed: the info panel's minimum width (180px) predated the Constants
  section and was too narrow for its longest label ("Text Outline Size:")
  plus a SpinBox, so dragging the panel down toward that minimum clipped the
  SpinBox's up/down arrows. Raised to 230px.
- Added a zoom percentage field next to Reset View — type an exact value
  (10-800%) instead of only scroll-wheel. Stays in sync with scroll-wheel
  zoom and Reset View in both directions.
- Added double-click on a canvas box as a rename shortcut — jumps straight
  into the sidebar Name field, selected and ready to type over.
- Added **Set as Build Target** to the right-click menu, for pointing the UI
  Builder at a node already on the canvas without going back to the Scene
  tree / Use Selected as Target.
- Added arrow-key nudge: moves the selected node(s) by 1px (Shift+arrow for
  a Grid Snap-size step). Works on a multi-selection, skips Container
  children (same reasoning as Resize), and holding a key down stays a single
  undo step instead of one per key-repeat.
- Added a filter box above the palette to narrow its 37 types down by name
  instead of scrolling.
- Palette buttons are now a fixed width (sized to the longest label) instead
  of stretching to fill the column, so they don't turn into oddly wide bars
  when the panel's floated into a large window; also fixes a horizontal
  scrollbar that could appear alongside the vertical one.
- Fixed: the palette's info-panel diagrams (VBoxContainer/GridContainer/etc.
  layout illustrations) stretched to fill the info panel's full width and
  looked distorted/sparse once the panel was wide (e.g. floated into a large
  window). Now capped to a fixed width, left-aligned, regardless of how wide
  the panel gets.
- Added rubber-band multi-select on the canvas: drag over empty space to
  select everything the band touches, Shift+click to add/remove a single
  box, Shift+drag to add a band to the existing selection. Feeds the same
  EditorSelection Align/Distribute/Match Size/Grid Snap already use, so
  multi-select no longer requires the Scene tree.
- Added smart alignment guides: dragging a freely-positioned node (not a
  Container reorder) now snaps to, and shows a guide line for, a sibling's
  or the parent's own edge/center when close, like Figma/Sketch-style guides.
  Also applies while dragging a brand new node in from the palette, not just
  when repositioning an existing one. Can be turned off in **Project
  Settings → UI Builder → Enable Alignment Guides** (persisted per project).
- Right-click menu now handles multi-selections: **Duplicate Selected (N)**
  and **Delete Selected (N)** act on the whole selection instead of just the
  clicked node, and right-clicking a node that's already part of a
  multi-selection keeps the whole selection instead of collapsing it down to
  just the one clicked (Explorer/Finder-style).
- Added Copy (Ctrl+C) / Paste (Ctrl+V), also in the right-click menu. Unlike
  Duplicate, Paste can target a different parent than the original —
  right-click a different box (or empty canvas space, for the build target)
  → **Paste into...**. Each paste is an independent copy, so pasting
  multiple times doesn't reuse the same node.
- Lowered the claimed minimum engine version from Godot 4.7 to **4.6** —
  nothing in the addon actually requires 4.7 specifically (FoldableContainer,
  used for the Constants section, only needs 4.5+), and manual testing on
  4.6 turned up no issues.
- UI Builder now registers via add_control_to_dock(DOCK_SLOT_BOTTOM) instead
  of add_control_to_bottom_panel() — same wide, full-editor-width placement
  at the bottom as before, but now supports Godot's native "Make Floating"
  (right-click its tab), since add_control_to_bottom_panel() panels are a
  separate, more restricted mechanism that doesn't support floating at all.
- Fixed: the canvas's right-click context menu (Delete/Duplicate/Select
  Parent) could pop up far from the cursor — even off in a second monitor —
  once the panel was floated into its own window, since it used a
  window-relative coordinate as if it were desktop-absolute. Now queries the
  real OS cursor position instead.
- Info panel now shows editable theme constant fields for more node types,
  grouped into a collapsible **Constants** section (like the Inspector's own
  Theme Overrides category) instead of sitting flat under Name: **Margin
  Left/Top/Right/Bottom** (MarginContainer), **Separation** (HSplitContainer,
  VSplitContainer, HSeparator, VSeparator — same field VBoxContainer/
  HBoxContainer already had), **H/V Separation** (HFlowContainer,
  VFlowContainer), **Side Margin** (TabContainer), and **Text Outline Size**
  (ProgressBar). Fields are grid-aligned so labels and values line up in
  columns.
- Fixed: inserting a template into an empty build target now automatically
  switches the target to the newly inserted template's root, instead of
  leaving it pointed at the (now-populated) outer wrapper — previously,
  drops/clicks meant for the template's own content could land as siblings
  of it instead. Targets with existing content are left alone, since that
  may be a deliberate composition.
- Fixed: a newly created container node (e.g. VBoxContainer) dropped inside
  another container (e.g. CenterContainer) collapsed to an invisible 0x0 dot,
  since Containers ignore a child's plain size and only respect
  Custom Min Size. New nodes now get their default size applied as
  Custom Min Size too, but only when their parent is a Container — resize-
  drag on non-Container parents is untouched.
- Added a popup explaining when/why Custom Min Size got auto-set on a new
  container child, with a "Don't remind me again for this project" checkbox
  (persisted in project.godot) instead of silently happening with no
  explanation.

## [1.0.0] - 2026-07-12

Initial release.

- **UI Builder** (bottom panel): drag-and-drop node creation on a pan/zoomable
  schematic canvas with rulers and a viewport outline, live resize/reposition/
  reorder, a 37-type node palette, reusable UI/HUD templates, per-node info
  panel with inline editing, and duplication.
- **Alignment Tools** (left dock): align, distribute, match size, grid snap,
  and theme presets (dark_ui, light_ui), with anchor-aware positioning.
- Full undo/redo support throughout, via Godot's `EditorUndoRedoManager`.
- MIT licensed.
