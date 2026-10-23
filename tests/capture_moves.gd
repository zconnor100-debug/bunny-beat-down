extends SceneTree
## Screenshots of how critters move: the army crawl, legs hanging under the
## glider while it leans into a steer, a mid-stride bound, giant glowing lucky
## clovers and the first-person club.
##   godot --path . -s tests/capture_moves.gd -- <out_dir>


func _initialize() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	_start.call_deferred()


func _start() -> void:
	var stage: Node = load("res://tests/moves_stage.gd").new()
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		stage.out_dir = a[0]
	DirAccess.make_dir_recursive_absolute(stage.out_dir)
	root.add_child(stage)
	current_scene = stage
