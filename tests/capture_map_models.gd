extends SceneTree
## Close-ups of the Hamster Cage / Toy Box models, each with the game's own
## materials (CageKit.model), for visual QA:
##   godot --path . -s tests/capture_map_models.gd -- <out_dir> cage/plant cage_seed ...
## "cage/plant" = assets/maps/cage/plant.glb (tools/maps/models.py);
## "cage_seed" = assets/env/cage_seed/cage_seed.glb (tools/env, downloaded).


func _initialize() -> void:
	_start.call_deferred()


func _start() -> void:
	var stage: Node = load("res://tests/map_models_stage.gd").new()
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		stage.out_dir = a[0]
		stage.ids = a.slice(1)
	DirAccess.make_dir_recursive_absolute(stage.out_dir)
	root.add_child(stage)
	current_scene = stage
