extends SceneTree
## Writes the raw geometry of every kit that has a refined model (CageKit
## made_as) to tools/_cache/maps/raw/<id>.glb, materials named by key, for
## tools/maps/refine.py to rebuild clean in Blender, and Wildwood Island's
## buildings piece by piece to raw/island/<style>.json for tools/maps/island.py:
##   godot --headless --path . -s tests/export_kits.gd [-- ids... | cage | toy | island]


func _initialize() -> void:
	_start.call_deferred()


func _start() -> void:
	var stage: Node = load("res://tests/export_kits_stage.gd").new()
	stage.only = OS.get_cmdline_user_args()
	root.add_child(stage)
