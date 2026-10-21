extends SceneTree
## Runs tests/tricks_stage.gd (loaded at runtime so autoloads exist).
## Use with --write-movie to record the README jump-tricks GIF.


func _initialize() -> void:
	Engine.max_fps = 0
	_start.call_deferred()


func _start() -> void:
	var stage: Node = load("res://tests/tricks_stage.gd").new()
	root.add_child(stage)
	current_scene = stage
