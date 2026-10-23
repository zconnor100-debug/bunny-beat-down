extends SceneTree
## A tour of a generated island: overhead view, each biome at critter height,
## and every big building from outside and in (needs a GPU window).
##   godot --path . -s tests/capture_island.gd -- <out_dir> [seed]


func _initialize() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	_start.call_deferred()


func _start() -> void:
	var stage: Node = load("res://tests/island_stage.gd").new()
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		stage.out_dir = a[0]
	if a.size() > 1:
		stage.seed_value = int(a[1])
	DirAccess.make_dir_recursive_absolute(stage.out_dir)
	root.add_child(stage)
	current_scene = stage
