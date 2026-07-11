@tool
@icon("res://addons/ui_builder/plugin_icon.svg")
extends EditorPlugin

const QuickLayoutDock = preload("res://addons/ui_builder/quick_layout_dock.gd")
const QuickLayoutBuilderPanel = preload("res://addons/ui_builder/builder_panel.gd")

var dock: Control
var builder_panel: Control


func _enter_tree() -> void:
	dock = QuickLayoutDock.new()
	dock.name = "Quick Layout"
	dock.setup(get_editor_interface(), get_undo_redo())
	add_control_to_dock(DOCK_SLOT_LEFT_UR, dock)

	builder_panel = QuickLayoutBuilderPanel.new()
	builder_panel.name = "UI Builder"
	builder_panel.setup(get_editor_interface(), get_undo_redo())
	add_control_to_bottom_panel(builder_panel, "UI Builder")


func _exit_tree() -> void:
	if dock:
		remove_control_from_docks(dock)
		dock.queue_free()
		dock = null
	if builder_panel:
		remove_control_from_bottom_panel(builder_panel)
		builder_panel.queue_free()
		builder_panel = null
