extends SceneTree
## Every carrot gun on its own, large: side and three-quarter views, and the
## whole armoury in a row (checks the look of tools/weapons builds in game).
##   godot --path . -s tests/capture_guns.gd -- <out_dir> [weapon ids...]


func _initialize() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	_start.call_deferred()


func _start() -> void:
	var stage: Node = load("res://tests/guns_stage.gd").new()
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		stage.out_dir = a[0]
		stage.ids = a.slice(1)
	DirAccess.make_dir_recursive_absolute(stage.out_dir)
	root.add_child(stage)
	current_scene = stage
