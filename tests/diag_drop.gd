extends SceneTree
## Runs tests/diag_drop_stage.gd (loaded at runtime so autoloads exist).


func _initialize() -> void:
	_start.call_deferred()


func _start() -> void:
	var stage: Node = load("res://tests/diag_drop_stage.gd").new()
	root.add_child(stage)
