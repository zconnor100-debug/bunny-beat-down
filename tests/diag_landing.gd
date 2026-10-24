extends SceneTree
## Where everyone ends up after the drop: counts by state after N seconds and
## lists anyone still falling, gliding or under the floor.
##   BBD_TEST=1 godot --headless --path . -s tests/diag_landing.gd -- <map> [opponents] [seconds]


func _initialize() -> void:
	_start.call_deferred()


func _start() -> void:
	root.add_child(load("res://tests/diag_landing_stage.gd").new())
