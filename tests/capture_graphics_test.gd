extends SceneTree
## A picture of the graphics check (GraphicsTest) as it opens.
##   BBD_TEST=1 godot --path . -s tests/capture_graphics_test.gd -- <out.png>


func _initialize() -> void:
	_start.call_deferred()


func _start() -> void:
	for action in InputMap.get_actions():   # (pads drive every Godot window here)
		for e in InputMap.action_get_events(action):
			if e is InputEventJoypadButton or e is InputEventJoypadMotion:
				InputMap.action_erase_event(action, e)
	root.gui_disable_input = true
	var test: Control = load("res://src/ui/graphics_test.gd").new()
	root.add_child(test)
	for i in 120:
		await process_frame
	var a := OS.get_cmdline_user_args()
	test.get_viewport().get_texture().get_image().save_png(a[0] if a.size() > 0 else "user://graphics_test.png")
	quit()
