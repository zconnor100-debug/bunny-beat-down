extends SceneTree
## A Battle Royale or a Team Battle measured in the real game (needs a GPU
## window): runs tests/match_perf_stage.gd (loaded at runtime, so the
## autoloads exist).
##   BBD_TEST=1 godot --path . --resolution 1920x1080 -s tests/perf_match.gd -- <out.json> [royale|teams] [island|cage|toybox] [quality] [opponents]


func _initialize() -> void:
	_start.call_deferred()


func _start() -> void:
	root.add_child(load("res://tests/match_perf_stage.gd").new())
