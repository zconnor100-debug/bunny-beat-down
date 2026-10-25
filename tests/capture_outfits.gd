extends SceneTree
## Outfit pictures (see tests/outfits_stage.gd): every piece on its own, or
## every rogue dressed.
##   godot --path . -s tests/capture_outfits.gd -- <out_dir> [pieces|cast|cast:<species>]


func _initialize() -> void:
	_start.call_deferred()


func _start() -> void:
	var stage: Node = load("res://tests/outfits_stage.gd").new()
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		stage.out_dir = a[0]
	if a.size() > 1:
		stage.only = a[1]
	DirAccess.make_dir_recursive_absolute(stage.out_dir)
	root.add_child(stage)
	current_scene = stage
