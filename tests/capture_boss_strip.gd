extends SceneTree
## A boss's moves shot as strips of stills, or filmed (see tests/boss_strip_stage.gd).
##   godot --path . -s tests/capture_boss_strip.gd -- <out_dir> <boss id> <move,move...> [step=0.1] [view=side|front|high|low|back] [walk=<s>] [bun=<x>,<z>] [dist=<k>] [hold=<s>] [air=<m>] [aim=<m>] [movie]
## (movie: run with --write-movie <dir>/f.png --fixed-fps 30, and it films instead.)


func _initialize() -> void:
	_start.call_deferred()


func _start() -> void:
	var stage: Node = load("res://tests/boss_strip_stage.gd").new()
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		stage.out_dir = a[0]
	if a.size() > 1:
		stage.id = a[1]
	if a.size() > 2:
		stage.moves = Array(a[2].split(","))
	for x in a.slice(3):
		if x.begins_with("step="):
			stage.step = float(x.trim_prefix("step="))
		elif x.begins_with("view="):
			stage.view = x.trim_prefix("view=")
		elif x.begins_with("walk="):
			stage.walk = float(x.trim_prefix("walk="))
		elif x.begins_with("bun="):
			var xz := x.trim_prefix("bun=").split(",")
			stage.bun_at = Vector3(float(xz[0]), 0.0, float(xz[1]))
		elif x.begins_with("dist="):
			stage.dist = float(x.trim_prefix("dist="))
		elif x.begins_with("hold="):
			stage.hold = float(x.trim_prefix("hold="))
		elif x.begins_with("air="):
			stage.air = float(x.trim_prefix("air="))
		elif x.begins_with("aim="):
			stage.aim = float(x.trim_prefix("aim="))
		elif x == "movie":
			stage.movie = true
	root.add_child(stage)
	current_scene = stage
