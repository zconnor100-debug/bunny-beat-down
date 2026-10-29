extends SceneTree
## Renders the HUD's item pictures (tests/item_icons_stage.gd) to
## assets/ui/item_<name>.png (needs a GPU window).
##   godot --path . -s tests/capture_item_icons.gd


func _initialize() -> void:
	_start.call_deferred()


func _start() -> void:
	var stage: Node = load("res://tests/item_icons_stage.gd").new()
	root.add_child(stage)
	current_scene = stage
