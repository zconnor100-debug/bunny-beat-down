extends SceneTree
## Screenshots of a rewind and of the final shot (slow motion, the three
## replay angles, the end screen) in a real match (needs a GPU window).
##   BBD_TEST=1 godot --path . --resolution 1280x720 -s tests/capture_finale.gd -- <out_dir> [map] [wardrobe ids,]


func _initialize() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	_start.call_deferred()


func _start() -> void:
	var stage: Node = load("res://tests/finale_stage.gd").new()
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		stage.out_dir = a[0]
	if a.size() > 1:
		stage.map = a[1]
	if a.size() > 2:
		stage.wear = a[2]
	DirAccess.make_dir_recursive_absolute(stage.out_dir)
	root.add_child(stage)
