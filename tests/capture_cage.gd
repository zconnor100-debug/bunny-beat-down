extends SceneTree
## A tour of the Hamster Cage map: overhead, the fridge, the lagoon, the toy
## plane, every landmark and inside the walk-in ones (needs a GPU window).
##   godot --path . -s tests/capture_cage.gd -- <out_dir> [seed] [landmark filter]


func _initialize() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	_start.call_deferred()


func _start() -> void:
	var stage: Node = load("res://tests/cage_stage.gd").new()
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		stage.out_dir = a[0]
	if a.size() > 1:
		stage.seed_value = int(a[1])
	if a.size() > 2:
		stage.only = a[2]
	DirAccess.make_dir_recursive_absolute(stage.out_dir)
	root.add_child(stage)
	current_scene = stage
