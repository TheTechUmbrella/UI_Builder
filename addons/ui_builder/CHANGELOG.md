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
