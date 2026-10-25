extends SceneTree
## Frame strips of every species standing, walking, sprinting, jumping,
## turning, strafing and shooting (see tests/anim_stage.gd).
##   BBD_TEST=1 godot --path . -s tests/capture_anims.gd -- <out_dir> [scene prefix]


func _initialize() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	_start.call_deferred()


func _start() -> void:
	var stage: Node = load("res://tests/anim_stage.gd").new()
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		stage.out_dir = a[0]
	if a.size() > 1:
		stage.only = a[1]
	DirAccess.make_dir_recursive_absolute(stage.out_dir)
	root.add_child(stage)
	current_scene = stage
