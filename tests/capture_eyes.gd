extends SceneTree
## Each species' head on a grid of its own coordinates, straight on and from
## the side (see tests/eyes_stage.gd), to read off where its eyes are.
##   godot --path . -s tests/capture_eyes.gd -- <out_dir>


func _initialize() -> void:
	_start.call_deferred()


func _start() -> void:
	var stage: Node = load("res://tests/eyes_stage.gd").new()
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		stage.out_dir = a[0]
	DirAccess.make_dir_recursive_absolute(stage.out_dir)
	root.add_child(stage)
	current_scene = stage
