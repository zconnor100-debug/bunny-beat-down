extends SceneTree
## Writes tools/voices/lines.json: every line the rogues can say (see
## tests/lines_stage.gd), for tools/voices/build_voices.py.
##   godot --headless --path . -s tests/export_lines.gd


func _initialize() -> void:
	_start.call_deferred()


func _start() -> void:
	var stage: Node = load("res://tests/lines_stage.gd").new()
	root.add_child(stage)
