extends SceneTree
## Runs tests/diag_brawl_stage.gd (loaded at runtime so autoloads exist).
##   godot --headless --path . -s tests/diag_brawl.gd -- <map> <seed> [seconds]


func _initialize() -> void:
	_start.call_deferred()


func _start() -> void:
	var stage: Node = load("res://tests/diag_brawl_stage.gd").new()
	root.add_child(stage)
