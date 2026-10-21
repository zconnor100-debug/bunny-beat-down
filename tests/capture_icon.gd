extends SceneTree
## Renders the app icon (tests/icon_stage.gd) to the given PNG path.
##   godot --path . --resolution 1024x1024 -s tests/capture_icon.gd -- /abs/path/icon.png


func _initialize() -> void:
	_start.call_deferred()


func _start() -> void:
	var stage: Node = load("res://tests/icon_stage.gd").new()
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		stage.out_path = a[0]
	root.add_child(stage)
	current_scene = stage
