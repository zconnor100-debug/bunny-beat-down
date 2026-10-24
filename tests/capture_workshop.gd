extends SceneTree
## The Workshop's gun upgrades and looks: every skin with a sight and laser,
## the view through the red dot, flash colours and smoke, beat-down bursts,
## every reticle, and the Burrow's Workshop rows.
##   godot --path . -s tests/capture_workshop.gd -- <out_dir>


func _initialize() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	_start.call_deferred()


func _start() -> void:
	var stage: Node = load("res://tests/workshop_stage.gd").new()
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		stage.out_dir = a[0]
	DirAccess.make_dir_recursive_absolute(stage.out_dir)
	root.add_child(stage)
	current_scene = stage
