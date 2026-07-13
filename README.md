# Quick Layout — Demo Project

This is a minimal Godot project (built with 4.7, works down to 4.6) for
developing and trying out the **Quick Layout** editor plugin, a visual UI
Builder and alignment toolkit for `Control`-based UI.

The addon itself lives in [`addons/ui_builder/`](addons/ui_builder/) —
see [its README](addons/ui_builder/README.md) for the full feature list,
usage guide, and known limitations.

## Try it

1. Open this project in Godot 4.6+.
2. **Project → Project Settings → Plugins**, enable "UI Builder".
3. Open any scene with a `Control` node (or start a new one) and use the
   **UI Builder** dock, or the **Quick Layout** dock on the left.

## Using just the addon in your own project

Copy `addons/ui_builder/` into your project's `addons/` folder and enable
it the same way — no dependency on anything else in this repo.

## License

MIT — see [LICENSE](LICENSE).
