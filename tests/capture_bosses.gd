extends SceneTree
## Renders of the bosses (see tests/boss_stage.gd).
##   godot --path . -s tests/capture_bosses.gd -- <out_dir> [brute robot hamster] [faces]


func _initialize() -> void:
	_start.call_deferred()


func _start() -> void:
	var stage: Node = load("res://tests/boss_stage.gd").new()
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		stage.out_dir = a[0]
	if a.size() > 1:
		stage.ids = Array(a.slice(1)).filter(func(x): return x != "faces")
	stage.faces = a.has("faces")
	root.add_child(stage)
	current_scene = stage
