# Changelog

All notable changes to this addon are documented here. Format loosely follows
[Keep a Changelog](https://keepachangelog.com/), versions match `plugin.cfg`.

## [Unreleased]

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
