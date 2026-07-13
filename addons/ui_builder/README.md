# Quick Layout

A visual UI Builder and alignment toolkit for Godot 4.6+'s `Control`-based UI.
Build screens by dragging nodes onto a live schematic canvas instead of
hunting through the Create Node dialog, then align, distribute, snap, and
theme them from a dedicated dock — all fully undoable.

Two tools, one addon:

- **UI Builder** (bottom dock, floatable) — drag-and-drop node creation on a
  pan/zoomable canvas with rulers and a viewport outline, live resize and
  reposition, reusable UI/HUD templates, and a per-node info panel with
  inline editing.
- **Alignment Tools** (left dock) — align, distribute, match size, snap to
  grid, and apply theme presets to controls you've already placed.

## Installation

1. Copy `addons/ui_builder/` into your project's `addons/` folder, so you
   end up with `res://addons/ui_builder/plugin.cfg`.
2. In Godot: **Project → Project Settings → Plugins**, enable "UI Builder".
3. A **Quick Layout** dock appears on the left, and a **UI Builder** tab
   appears at the bottom — right-click its tab → **Make Floating** to pop it
   into its own resizable window if you want it out of the way.

## Quick Start

1. Open (or create) a scene with a `Control`-derived root node.
2. Open the **UI Builder** tab — your scene's root Control is auto-selected
   as the build target (shown in the **Target** label).
3. Drag **Button** (or anything else) from the palette on the left onto the
   canvas and drop it. A real Button node appears in your scene, selected and
   ready to move or resize.
4. Drag the box around to reposition it, or grab a corner handle to resize.
   The Scene tree and Inspector update in real time — everything here is a
   real node, not a preview.
5. Select two or more nodes in the Scene tree and switch to the **Quick
   Layout** dock on the left to align, distribute, or snap them to a grid.

That's the whole loop. See below for templates, keyboard shortcuts, and the
full toolset.

## UI Builder

### Getting started

1. Open the **UI Builder** tab. If a scene is already open, its root Control
   (or the shallowest Control found in its tree) is selected as the build
   target automatically. Otherwise, select any `Control` node in the Scene
   tree and click **Use Selected as Target**.
2. Drag any item from the palette on the left — Button, Label, Panel,
   VBoxContainer, and 30+ more — onto the canvas and drop it. A real node of
   that type is created as a child of whichever box you dropped it on (or
   the build target, if you dropped it on empty space), auto-selected, and
   ready to tweak.
3. Hover or click a palette item to see a description and, for layout
   containers, a small diagram of how it arranges children.

### Working with existing nodes

- **Select**: click a box to select it. If a container's children fill it
  completely, Alt+Click steps up to the parent (repeated Alt+Clicks keep
  walking up the tree), or right-click → **Select Parent**.
- **Move**: drag a box to reposition it, or drop it onto a different box to
  reparent into it. Dragging within the same layout container (VBoxContainer,
  HBoxContainer, etc.) reorders it among its siblings instead — a
  container recalculates its children's position every layout pass, so a
  raw position edit wouldn't actually stick at runtime; reordering is the
  one thing that does.
- **Resize**: select a single node and drag any of its 8 corner/edge
  handles. Not available for a layout container's children, for the same
  reason moving doesn't reposition them.
- **Delete**: right-click a box → **Delete**, or select one or more nodes
  and click **Delete Selected**.
- **Duplicate**: Ctrl+D, or right-click a box → **Duplicate**. Copies the
  node and its whole subtree, nudged slightly so it doesn't land exactly on
  top of the original.
- **Rename, resize, and space**: the info panel on the right shows live
  details for whatever's hovered or selected, including editable fields —
  **Name**, **Custom Min Size**, and whichever layout-relevant theme
  constants apply to the node's type (e.g. **Separation** for box/split
  containers and separators, **Margin Left/Top/Right/Bottom** for
  MarginContainer, **H/V Separation** for flow containers, **Side Margin**
  for TabContainer, **Text Outline Size** for ProgressBar) — with changes
  applied immediately through undo/redo.
- Click empty canvas space to deselect.

### The canvas

- Shows a **viewport outline** — the project's actual configured resolution
  (Project Settings → Display → Window → Viewport Width/Height) in
  viewport-frame mode, or your build target's own bounds in "fit" mode
  (toggle **Show Full Viewport** to switch) — the same idea as the game
  screen boundary the main 2D editor draws. Content always keeps its real
  aspect ratio regardless of the panel's own shape (letterboxed rather than
  stretched to fill).
- **Pan**: middle-click-drag. **Zoom**: scroll wheel, centered on the
  cursor. **Reset View** snaps back to centered, 100% zoom.
- Pixel-tick rulers run along the top and left in target-space coordinates
  (the same numbers the Inspector shows), and stay correct through panning
  and zooming. Gridlines appear whenever **Snap to Grid** is on.
- The schematic is intentionally simple — labeled, colored boxes, not a
  full render — so it stays fast and predictable regardless of theme or
  content.
- If the build target is deleted while active, the panel notices and clears
  itself; pick a new one with **Use Selected as Target**.

### Templates

The **Template** row lets you drop in a whole premade layout instead of
building one node at a time:

- **Insert** instantiates the selected `.tscn` as a child of the current
  build target. Unlike a normal scene instance, the inserted nodes are
  fully owned by the edited scene rather than staying a linked sub-scene —
  freely rename, restructure, or delete any part of it afterward. If
  nothing's targeted yet, it falls back to the scene root, or — if no scene
  is open at all — prompts to save a brand-new scene built from the
  template.
- **Save Selected as Template...** packs the selected node (and its
  children) into a new `.tscn` in `addons/ui_builder/templates/`, growing
  your own library over time.

Ships with three starters: `main_menu_ui`, `health_score_hud`, and
`example` (a title-screen mockup).

### Shortcuts

| Action | Input |
| --- | --- |
| Select topmost box | Click |
| Select parent (repeatable) | Alt+Click |
| Context menu (Delete / Duplicate / Select Parent) | Right-click |
| Move / reorder / reparent | Drag |
| Resize | Drag a handle on a selected box |
| Duplicate | Ctrl+D |
| Deselect | Click empty canvas space |
| Pan | Middle-click-drag |
| Zoom | Scroll wheel |

## Alignment Tools (left dock)

- Select 2+ `Control` nodes → click an **Align** button. The first node
  selected is the reference the others align to.
- Select 3+ nodes → **Distribute** Horizontal/Vertical spaces them evenly
  between the two outermost nodes.
- **Match Size** copies the first selected node's width/height/both to the
  rest.
- **Grid Snap** rounds selected nodes' positions to the nearest multiple of
  the grid size.
- **Theme Preset** applies a `.tres` Theme to selected nodes (and their
  children). Ships with `dark_ui` and `light_ui`; drop more into
  `addons/ui_builder/presets/` and hit Refresh.
- **Anchor-aware** checkbox (applies to both Align and Distribute): syncs
  the anchor ratio between controls before positioning them, so the result
  stays aligned even if the parent is resized later — not just at the
  moment you click. Off by default since it only matters for controls with
  non-default anchors.

Every operation goes through Godot's undo/redo manager.

## Known limitations

- The UI Builder's canvas is a schematic, not a full render — no theming,
  fonts, or textures shown, by design (keeps it fast and simple).
- Anchor-aware alignment only handles point-anchored controls (pinned to a
  corner/edge/center); controls that intentionally stretch with their
  parent are left untouched rather than having their stretch behavior
  rewritten.
- No live-drag snapping in the main 2D viewport — Godot's own viewport
  already has this natively (magnet icon / View → Use Snap); set its step
  to match this addon's Grid Snap size if you want both to agree.
- Distribute keeps the two outermost nodes fixed and spaces the rest evenly
  between them, matching standard design-tool conventions.
- If you drag the **UI Builder** tab out of its default bottom slot into a
  side dock, Godot's drag-and-drop dock repositioning doesn't offer a way to
  drop it back into the bottom slot — that's a Godot editor limitation, not
  this addon. Fix: **Project → Project Settings → Plugins**, disable then
  re-enable "UI Builder" to reset it back to the bottom.

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for release notes and bug fix history.

## Support

This addon is provided as-is with no guaranteed support. If you hit an issue
on the **unmodified** latest release, feel free to open a GitHub issue with
steps to reproduce. If you've made your own changes, please debug against
your fork first — issues that only reproduce on a modified version won't be
prioritized, since I have no visibility into what was changed.

## License

MIT — see [LICENSE](../../LICENSE).
