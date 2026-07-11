# Quick Layout — Godot 4.7 Editor Plugin (starter scaffold)

Two tools in one addon, targeting Godot 4.7+:

1. **UI Builder** (bottom panel) — drag Control types from a palette onto a
   canvas to actually generate real nodes in your scene.
2. **Alignment tools** (left dock) — align, distribute, match size, grid-snap,
   and apply theme presets to nodes you've already placed.

## Install (for testing)

1. Copy the `addons/quick_layout/` folder into your project's `addons/`
   folder (so you end up with `res://addons/quick_layout/plugin.cfg`).
2. In Godot: Project -> Project Settings -> Plugins -> enable "Quick Layout".
3. A "Quick Layout" tab appears in the left dock area.

## UI Builder (bottom panel)

A "UI Builder" tab appears in the bottom panel area (next to Output, Debugger,
etc.) alongside the left-dock alignment tools.

1. In the Scene tree, select an existing `Control` node (e.g. a `Panel` or
   plain `Control` you've already added as a container) and click
   **"Use Selected as Target"** in the Builder panel. This is the node new
   UI elements get added into.
2. Drag any item from the palette on the left (Button, Label, Panel,
   VBoxContainer, etc.) onto the canvas on the right and drop it.
3. A real node of that type is instantiated as a child of your target,
   positioned roughly where you dropped it, and auto-selected so you can
   immediately tweak it in the Inspector. Ctrl+Z undoes the creation.
4. The canvas redraws a schematic (labeled boxes, not full rendering) of the
   target's current children every ~0.5s, so it stays roughly in sync as you
   edit things in the Inspector or Scene tree.

Notes:
- If the target is a `Container` (VBoxContainer, HBoxContainer, etc.), the
  container will reposition children itself — the drop position is only
  respected for non-Container parents (`Control`, `Panel`, etc.).
- The schematic view is intentionally simple (colored rectangles + node
  names), not a full preview — full visual fidelity would mean re-implementing
  theming/rendering, which is a bigger v0.3+ project.
- **Reposition existing nodes**: click-drag any existing box on the canvas
  (not just palette items) to move that node. It keeps the point you grabbed
  under your cursor, so it feels like dragging the actual widget. Also
  undo-able.
- **Resize handles**: with a single node selected, drag any of its 8
  corner/edge handles to resize it live. Respects "Snap to Grid" from the
  top bar the same way moving does — the edge you're dragging snaps, the
  opposite edge stays exactly fixed.
- The currently selected node's box is highlighted in yellow on the canvas,
  and stays in sync immediately (not just on the 0.5s poll).
- If the build target node is deleted while it's active, the panel notices
  (via `tree_exiting`) and clears itself instead of erroring — pick a new
  target with "Use Selected as Target".
- **Templates**: the "Template" row above the palette lets you instantiate a
  premade `.tscn` (ships with `main_menu_ui` and `health_score_hud`, in
  `addons/quick_layout/templates/`) as a child of the current build target
  via **Insert**. Unlike a normal Godot scene instance, the inserted nodes
  are fully flattened/owned by the edited scene rather than staying a linked
  sub-scene — so you can freely rename, restructure, or delete any part of
  it afterward, same as anything else you built by hand.
  Select any single Control (built via the tool or otherwise) and click
  **"Save Selected as Template..."** to pack it (and its children) into a
  new `.tscn` there, growing your own library over time. Both directions go
  through undo/redo.

## Using it (alignment tools, left dock)

- Select 2+ `Control` nodes in the Scene tree (or 2D viewport) -> click an
  Align button. The **first** node you selected is the reference the others
  align to.
- Select 3+ controls -> Distribute Horizontal/Vertical spaces them evenly
  between the two outer nodes.
- Match Size copies the first selected control's width/height/both to the
  rest.
- Grid Snap rounds selected controls' positions to the nearest multiple of
  the grid size (default 8px).
- Theme Preset: ships with `dark_ui` and `light_ui` presets out of the box
  (`addons/quick_layout/presets/`). Drop in more `.tres` Theme resources any
  time, hit Refresh, pick one, select controls, hit Apply.
- **Anchor-aware** checkbox (above the Align buttons, also applies to
  Distribute): when off, Align/Distribute just set `Control.position`
  directly, which is exact right now but can drift if the parent is resized
  later and the controls involved have different anchors. When on, it syncs
  the controls' anchor ratio on the relevant axis before positioning them,
  so the result stays aligned across future resizes too — scoped to
  point-anchored controls (not ones that intentionally stretch with their
  parent, which are left alone).
- Every operation goes through Godot's undo/redo manager — Ctrl+Z works.

## Known limitations (v0.1, intentionally scoped for a first pass)

- No live-drag snapping in the 2D viewport (only "snap selected now") — and
  intentionally staying that way: Godot's 2D viewport already has native
  live-drag snapping (magnet icon / View → Use Snap, with its own
  configurable step). Reimplementing that via `_forward_canvas_gui_input`
  would mean intercepting input for the *entire* 2D viewport, not just this
  plugin's nodes, for something the editor already does well — not worth
  the risk. Set Godot's built-in snap step to match this plugin's Grid Snap
  size if you want both to agree.
- Distribute assumes the outer two nodes (by position) stay fixed and
  spaces the rest evenly between them — standard behavior, matches Figma/
  Illustrator conventions.

## Next steps toward a publishable asset

1. ~~Test across a few real projects/anchor setups, tighten the anchor-aware~~
   ~~math.~~ Anchor-aware Align/Distribute shipped — see `align_tools.gd`
   (`_sync_anchor_x`/`_sync_anchor_y`). Still only handles point-anchored
   controls; stretching controls are intentionally left untouched.
2. ~~Add live-drag grid snapping via `_forward_canvas_gui_input`.~~ Decided
   against it — Godot's native 2D viewport snap already covers this; see
   Known Limitations above.
3. ~~Add a couple of shipped theme presets (dark/light) so the dropdown~~
   ~~isn't empty out of the box.~~ Done — see `presets/dark_ui.tres` and
   `presets/light_ui.tres`.
4. ~~Write a `plugin_icon.svg` (shown next to the dock tab) — currently uses~~
   ~~the default.~~ Done — `plugin_icon.svg` added, wired up via
   `@icon("res://addons/quick_layout/plugin_icon.svg")` on `plugin.gd`
   (Godot's documented mechanism for a plugin's icon in Project Settings →
   Plugins). Unverified whether this also affects the dock/bottom-panel tab
   icons specifically — check both spots after reloading.
5. Once stable: tag a GitHub release, then submit to the new Godot Asset
   Store (godotengine.org's revamped store, live since 4.7) — it now
   supports ratings and threaded browsing, so a clean README and a short
   demo GIF matter more than before for discoverability.
6. ~~Premade UI/HUD template dropdown.~~ Done — see "Templates" above and
   `addons/quick_layout/templates/`. Ships with two starter templates
   (`main_menu_ui`, `health_score_hud`), hand-authored as raw `.tscn` text
   since this session couldn't run the Godot editor to build/verify them
   visually — open each once in the editor to sanity-check it loads and
   looks right before relying on them.
