extends SceneTree
## Screenshots of the Kernel Hunt's prologue in the real game (needs a GPU
## window): runs tests/kernel_shots_stage.gd (loaded at runtime so the
## autoloads exist). With "boss", a Boss Battle won on the island and the
## Gazette's special edition it makes.
##   BBD_TEST=1 godot --path . --resolution 1920x1080 -s tests/capture_kernel.gd -- <out_dir> [boss]
## (Its waits are game time: on a slow GPU, --gpu-index 1, it takes longer but shoots the same.)


func _initialize() -> void:
	_start.call_deferred()


func _start() -> void:
	root.add_child(load("res://tests/kernel_shots_stage.gd").new())
