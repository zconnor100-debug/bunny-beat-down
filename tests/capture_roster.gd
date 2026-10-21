extends SceneTree
## In-engine roster shot: every species armed and posed by the procedural
## animator, plus a gore showcase (rocket blast on the line-up).
##   godot --path . -s tests/capture_roster.gd -- <out_dir>


func _initialize() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	_start.call_deferred()


func _start() -> void:
	var stage: Node = load("res://tests/roster_stage.gd").new()
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		stage.out_dir = a[0]
	DirAccess.make_dir_recursive_absolute(stage.out_dir)
	root.add_child(stage)
	current_scene = stage
