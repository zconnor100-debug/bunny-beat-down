extends SceneTree
## The roguelike layer, for a look: scars on every species, an acorn shrine,
## a boon draft and the Trail (tests/roguelike_stage.gd; the test profile).
##   BBD_TEST=1 godot --path . -s tests/capture_roguelike.gd -- <out_dir>


func _initialize() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	_start.call_deferred()


func _start() -> void:
	var stage: Node = load("res://tests/roguelike_stage.gd").new()
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		stage.out_dir = a[0]
	DirAccess.make_dir_recursive_absolute(stage.out_dir)
	root.add_child(stage)
	current_scene = stage
