extends SceneTree
## Lists solid things generated inside each other (props in props, props in
## walk-in toys, loot inside solids) on a map:
##   godot --headless --path . -s tests/diag_overlaps.gd -- <island|cage|toybox> [seed] [min depth m]


func _initialize() -> void:
	_start.call_deferred()


func _start() -> void:
	var stage: Node = load("res://tests/diag_overlaps_stage.gd").new()
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		stage.map = a[0]
	if a.size() > 1:
		stage.seed_value = int(a[1])
	if a.size() > 2:
		stage.min_depth = float(a[2])
	root.add_child(stage)
