extends SceneTree
## Pause → Quit to menu with a gamepad, in a real match (headless):
##   BBD_TEST=1 godot --headless --path . -s tests/diag_quit.gd -- [map]


func _initialize() -> void:
	_start.call_deferred()


func _start() -> void:
	root.add_child(load("res://tests/diag_quit_stage.gd").new())
