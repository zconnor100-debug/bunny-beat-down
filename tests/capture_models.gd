extends SceneTree
## Eye-level renders of individual env models (see tests/model_stage.gd).
##   godot --path . -s tests/capture_models.gd -- <out_dir> stump_a log_mossy ...


func _initialize() -> void:
	_start.call_deferred()


func _start() -> void:
	var stage: Node = load("res://tests/model_stage.gd").new()
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		stage.out_dir = a[0]
		stage.ids = a.slice(1)
	root.add_child(stage)
	current_scene = stage
