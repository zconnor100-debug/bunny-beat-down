extends SceneTree
## Screenshots of the drop in a real match (needs a GPU window): riding the
## balloon / toy plane / paper plane, then skydiving after jumping, with the
## bots that jump with you.
##   BBD_TEST=1 godot --path . -s tests/capture_drop.gd -- <out_dir> [map]


func _initialize() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	_start.call_deferred()


func _start() -> void:
	var stage: Node = load("res://tests/drop_stage.gd").new()
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		stage.out_dir = a[0]
	if a.size() > 1:
		stage.map = a[1]
	DirAccess.make_dir_recursive_absolute(stage.out_dir)
	root.add_child(stage)
