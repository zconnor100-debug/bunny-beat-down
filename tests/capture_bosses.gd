extends SceneTree
## Renders of the bosses (see tests/boss_stage.gd).
##   godot --path . -s tests/capture_bosses.gd -- <out_dir> [brute robot hamster]


func _initialize() -> void:
	_start.call_deferred()


func _start() -> void:
	var stage: Node = load("res://tests/boss_stage.gd").new()
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		stage.out_dir = a[0]
	if a.size() > 1:
		stage.ids = a.slice(1)
	root.add_child(stage)
	current_scene = stage
