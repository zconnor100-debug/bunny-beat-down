extends SceneTree
## Frame cost of each map from fixed viewpoints: GPU and CPU time, triangles
## and draw calls (the camera views and shadow passes apart). Needs a GPU
## window; vsync is off so the times are the real cost.
##   godot --path . -s tests/perf_bench.gd -- <out.json> [island,cage,toybox] [quality] [lod_threshold] [breakdown]


func _initialize() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	_start.call_deferred()


func _start() -> void:
	var stage: Node = load("res://tests/perf_stage.gd").new()
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		stage.out_path = a[0]
	if a.size() > 1:
		stage.maps = a[1].split(",")
	if a.size() > 2:
		stage.quality = int(a[2])
	if a.size() > 3:
		stage.lod_threshold = float(a[3])
	stage.breakdown = "breakdown" in a
	root.add_child(stage)
	current_scene = stage
