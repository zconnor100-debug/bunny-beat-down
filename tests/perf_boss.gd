extends SceneTree
## A Boss Battle measured in the real game (needs a GPU window): runs
## tests/boss_perf_stage.gd (loaded at runtime, so the autoloads exist).
##   BBD_TEST=1 godot --path . --resolution 1920x1080 -s tests/perf_boss.gd -- <out.json> [island|toybox|cage] [quality]


func _initialize() -> void:
	_start.call_deferred()


func _start() -> void:
	root.add_child(load("res://tests/boss_perf_stage.gd").new())
