extends Node
## Stage for tests/perf_match.gd: a Battle Royale or a Team Battle in the real
## game, measured frame by frame: the balloon (or plane), the landings (the
## whole lobby on the ground and after loot at once), and the fighting after,
## with where the time goes (the CPU's game code, the GPU). Writes a JSON
## summary per phase. (physics_ms and navigation_ms are Godot's worst tick in each
## second, not an average.) split_* splits the average frame: the game's code
## in physics ticks and in the frame, what was deferred to after each (the
## skeletons' poses, freed nodes), the physics engine (Jolt's step, after each
## tick), and the rendering (CPU side, after the frame's code).
## With "breakdown" (the 6th argument) it also times the game's code script by
## script: each script's nodes run in a band of priorities of their own, with a
## marker node before each band, so the time from one marker to the next is
## that script's (scripts_* in each phase: CPU ms per second of play, physics
## ticks and frames; "unscripted" is the engine's own nodes at priority 0).

const LANDING := 20.0   ## seconds measured after you land...
const PLAY := 40.0      ## ...and after that

var out_path := "user://match_perf.json"
var mode := "royale"
var map := "island"
var quality := 4
var opponents := 49
var _rows: Array = []
var _phase := ""
var _last := 0
var _split := {}      ## phase -> bucket -> usec
var _mark := ""       ## the last edge passed, and when
var _mark_t := 0
var _nav_polygons := 0
var _spikes: Array = []    ## [phase, seconds into it, ms] for frames over 50 ms
var _phase_t := 0
var _jump_t := 0
var breakdown := false
var _bands := {}           ## script -> band index (its nodes' priority: 2 * index + 3)
var _band_names: Array = []
var _band_mark := {true: [-1, 0], false: [-1, 0]}   ## physics? -> [the last marker passed, when]
var _band_ms := {}         ## phase -> "physics:<script>" / "frame:<script>" -> usec
var _draw_t := 0           ## (breakdown) when RenderingServer began drawing this frame
var _counts := {}          ## phase -> kind -> [sum, samples]: how many of each engine node there were
var _count_t := 0


## A breakdown marker: the start of band `index` (its scripts' nodes run
## right after it, at the next priority up).
class Band extends Node:
	var stage: Node
	var index := 0

	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		process_priority = 2 * index + 2
		process_physics_priority = process_priority

	func _process(_delta: float) -> void:
		stage.band(index, false)

	func _physics_process(_delta: float) -> void:
		stage.band(index, true)


## The first (or last) thing to run in each physics tick and each frame.
class Edge extends Node:
	var stage: Node
	var last := false

	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		process_priority = 1_000_000 if last else -1_000_000
		process_physics_priority = process_priority

	func _process(_delta: float) -> void:
		stage.edge("p_end" if last else "p_start")
		if last:
			stage.edge.call_deferred("p_flushed")

	func _physics_process(_delta: float) -> void:
		stage.edge("ph_end" if last else "ph_start")
		if last:
			stage.edge.call_deferred("ph_flushed")


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		out_path = a[0]
	if a.size() > 1:
		mode = a[1]
	if a.size() > 2:
		map = a[2]
	if a.size() > 3:
		quality = int(a[3])
	if a.size() > 4:
		opponents = int(a[4])
	breakdown = "breakdown" in a
	if breakdown:
		RenderingServer.frame_pre_draw.connect(_pre_draw)
		RenderingServer.frame_post_draw.connect(_post_draw)
		get_tree().node_added.connect(_band_node)
		for n in get_tree().root.find_children("*", "", true, false):
			_band_node(n)
	for last in [false, true]:
		var e := Edge.new()
		e.stage = self
		e.last = last
		add_child(e)
	_run.call_deferred()


## (breakdown) The render bucket split: waiting on the last frames (sync,
## from the frame's code to RenderingServer starting to draw), drawing (its
## CPU side: culling, skeletons, particles, the command lists), and after it.
func _pre_draw() -> void:
	_draw_t = Time.get_ticks_usec()
	if _phase != "" and _mark == "p_flushed":
		var b: Dictionary = _split.get_or_add(_phase, {})
		b["render_sync"] = int(b.get("render_sync", 0)) + _draw_t - _mark_t


func _post_draw() -> void:
	if _phase != "" and _draw_t > 0:
		var b: Dictionary = _split.get_or_add(_phase, {})
		b["render_draw"] = int(b.get("render_draw", 0)) + Time.get_ticks_usec() - _draw_t
	_draw_t = 0


## (breakdown) How many of the engine's own busy nodes there are (once a second).
func _count_nodes() -> void:
	var c := {}
	for n in get_tree().root.find_children("*", "", true, false):
		var k := ""
		if n is AudioStreamPlayer3D:
			k = "audio3d_playing" if (n as AudioStreamPlayer3D).playing else "audio3d_idle"
		elif n is GPUParticles3D:
			k = "particles"
		elif n is OmniLight3D or n is SpotLight3D:
			k = "lights"
		elif n is PhysicalBone3D:
			k = "physical_bones"
		elif n is RigidBody3D:
			k = "rigid_bodies"
		elif n is Area3D:
			k = "areas"
		elif n is Skeleton3D:
			k = "skeletons"
		elif n is Decal:
			k = "decals"
		elif n is MeshInstance3D:
			k = "meshes"
		if k != "":
			c[k] = int(c.get(k, 0)) + 1
	var ph: Dictionary = _counts.get_or_add(_phase, {})
	for k in c:
		var e: Array = ph.get_or_add(k, [0, 0])
		e[0] += c[k]
		e[1] += 1


## Puts a scripted node in its script's band (a new band, and its marker,
## for a script not seen yet).
func _band_node(n: Node) -> void:
	if n is Band or n is Edge or n == self:
		return
	var sc: Script = n.get_script()
	if sc == null or not (n.has_method("_process") or n.has_method("_physics_process")):
		return
	var key := sc.resource_path.get_file().get_basename() if sc.resource_path != "" else String(sc.get_global_name())
	if key == "":
		key = str(sc)
	if not _bands.has(key):
		_bands[key] = _band_names.size()
		_band_names.append(key)
		var m := Band.new()
		m.stage = self
		m.index = _bands[key]
		add_child.call_deferred(m)
	n.process_priority = 2 * int(_bands[key]) + 3
	n.process_physics_priority = n.process_priority


## Band marker `index` passed: the time since the marker before goes to the
## band before (or, since the tick's or frame's first edge, to "unscripted").
func band(index: int, physics: bool) -> void:
	var now := Time.get_ticks_usec()
	var last: Array = _band_mark[physics]
	if _phase != "" and int(last[0]) >= -1 and int(last[1]) > 0 and index > int(last[0]):
		var key := ("physics:" if physics else "frame:") + ("unscripted" if int(last[0]) < 0 else String(_band_names[int(last[0])]))
		var b: Dictionary = _band_ms.get_or_add(_phase, {})
		b[key] = int(b.get(key, 0)) + now - int(last[1])
	_band_mark[physics] = [index, now]


func edge(what: String) -> void:
	var now := Time.get_ticks_usec()
	if breakdown:
		match what:
			"ph_start":
				_band_mark[true] = [-1, now]
			"p_start":
				_band_mark[false] = [-1, now]
			"ph_end", "p_end":
				band(1_000_000, what == "ph_end")
				_band_mark[what == "ph_end"] = [-2, 0]
	if _phase != "" and _mark != "":
		var bucket := ""
		match [_mark, what]:
			["ph_start", "ph_end"]:
				bucket = "game_physics"
			["p_start", "p_end"]:
				bucket = "game_frame"
			["ph_end", "ph_flushed"]:
				bucket = "physics_deferred"
			["ph_flushed", "ph_start"], ["ph_flushed", "p_start"], ["ph_end", "ph_start"], ["ph_end", "p_start"]:
				bucket = "physics_engine"
			["p_end", "p_flushed"]:
				bucket = "frame_deferred"
			["p_flushed", "ph_start"], ["p_flushed", "p_start"], ["p_end", "ph_start"], ["p_end", "p_start"]:
				bucket = "render"
		if bucket != "":
			var b: Dictionary = _split.get_or_add(_phase, {})
			b[bucket] = int(b.get(bucket, 0)) + now - _mark_t
	_mark = what
	_mark_t = now


func _process(_delta: float) -> void:
	if _phase == "":
		return
	var now := Time.get_ticks_usec()
	if breakdown and now - _count_t > 1_000_000:
		_count_t = now
		_count_nodes()
	if _last > 0:
		var vp := get_viewport().get_viewport_rid()
		_rows.append([_phase, (now - _last) / 1000.0, Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
			Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, RenderingServer.viewport_get_measured_render_time_cpu(vp),
			RenderingServer.viewport_get_measured_render_time_gpu(vp), Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			get_tree().get_nodes_in_group(&"critters").filter(func(c): return c.alive).size(),
			Performance.get_monitor(Performance.TIME_NAVIGATION_PROCESS) * 1000.0])
		if (now - _last) / 1000.0 > 50.0:
			_spikes.append([_phase, snappedf((now - _phase_t) / 1e6, 0.01), snappedf((now - _last) / 1000.0, 0.1)])
	_last = now


func _run() -> void:
	var settings: Node = get_tree().root.get_node("Settings")
	settings.set_value(&"quality", quality, false)
	settings.set_value(&"map", map, false)
	settings.set_value(&"mode", mode, false)
	settings.set_value(&"seed", 4321, false)
	settings.set_value(&"opponents", opponents, false)
	settings.set_value(&"vsync", 0, false)
	settings.set_value(&"max_fps", 0, false)
	seed(4321)   # (the bots' choices: where they land, who they go for; runs still drift apart, fights are chaotic)
	get_tree().change_scene_to_file("res://scenes/game.tscn")
	var g: Node = null
	while g == null or g.get("match_manager") == null or g.match_manager.phase == MatchManager.Phase.LOADING:
		await get_tree().process_frame
		g = get_tree().current_scene
	var mm: MatchManager = g.match_manager
	var p := mm.player
	if Island.current:
		for r in Island.current.nav_regions:
			_nav_polygons += r.navigation_mesh.get_polygon_count() if r.navigation_mesh else 0
	p.max_health = 100000.0
	p.health = p.max_health
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	_phase = "balloon"
	_phase_t = Time.get_ticks_usec()
	while mm.dropship and is_instance_valid(mm.dropship) and mm.dropship.progress < 0.35:
		await get_tree().process_frame
	_jump_t = Time.get_ticks_usec()
	print("PERF jump at balloon+%.2f s" % ((_jump_t - _phase_t) / 1e6))
	mm.player_jump()
	while p.state != Critter.State.GROUND:
		p.want_jump = p.state == Critter.State.FREEFALL
		await get_tree().process_frame
	_phase = "landing"
	_phase_t = Time.get_ticks_usec()
	print("PERF landed %.2f s after the jump" % ((Time.get_ticks_usec() - _jump_t) / 1e6))
	await _seconds(LANDING)
	_phase = "play"
	_phase_t = Time.get_ticks_usec()
	await _seconds(PLAY)
	_phase = ""
	if breakdown:   # (the busiest kinds of particles left at the end, by parent and settings)
		var by := {}
		for n in get_tree().root.find_children("*", "GPUParticles3D", true, false):
			var gp := n as GPUParticles3D
			var k := "%s/%s one_shot=%s emitting=%s amount=%d" % [String(gp.get_parent().name).left(18), String(gp.name).left(18), gp.one_shot, gp.emitting, gp.amount]
			by[k] = int(by.get(k, 0)) + 1
		var keys := by.keys()
		keys.sort_custom(func(x, y): return by[x] > by[y])
		for k in keys.slice(0, 12):
			print("PARTICLES %5d  %s" % [by[k], k])
	_write()
	get_tree().quit()


func _seconds(s: float) -> void:
	var start := Time.get_ticks_msec()
	while (Time.get_ticks_msec() - start) / 1000.0 < s:
		await get_tree().process_frame


func _write() -> void:
	var out := {"mode": mode, "map": map, "quality": quality, "size": [get_viewport().size.x, get_viewport().size.y],
		"nav_polygons": _nav_polygons, "spikes": _spikes, "phases": {}}
	for ph in ["balloon", "landing", "play"]:
		var rows := _rows.filter(func(r): return r[0] == ph)
		if rows.is_empty():
			continue
		var frames: Array = rows.map(func(r): return r[1])
		frames.sort()
		var n := frames.size()
		var avg := func(i: int) -> float: return rows.reduce(func(acc, r): return acc + float(r[i]), 0.0) / n
		out.phases[ph] = {"frames": n, "fps": 1000.0 / avg.call(1), "ms_p50": frames[n / 2], "ms_p95": frames[int(n * 0.95)],
			"ms_p99": frames[mini(n - 1, int(n * 0.99))], "ms_worst": frames[n - 1], "frames_over_33ms": frames.filter(func(f): return f > 33.3).size(),
			"process_ms": avg.call(2), "physics_ms": avg.call(3), "render_cpu_ms": avg.call(4), "render_gpu_ms": avg.call(5),
			"draw_calls": avg.call(6), "alive": avg.call(7), "navigation_ms": avg.call(8)}
		var b: Dictionary = _split.get(ph, {})
		for k in b:
			out.phases[ph]["split_" + k] = b[k] / 1000.0 / n
		if breakdown:
			var secs: float = frames.reduce(func(acc, f): return acc + f, 0.0) / 1000.0
			var bm: Dictionary = _band_ms.get(ph, {})
			var keys := bm.keys()
			keys.sort_custom(func(x, y): return bm[x] > bm[y])
			var per_s := {}
			for k in keys:
				per_s[k] = snappedf(bm[k] / 1000.0 / secs, 0.01)
			out.phases[ph]["scripts_ms_per_s"] = per_s
			var counts := {}
			for k in _counts.get(ph, {}):
				var e: Array = _counts[ph][k]
				counts[k] = snappedf(float(e[0]) / maxf(e[1], 1), 0.1)
			out.phases[ph]["nodes"] = counts
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(out, "  "))
	f.close()
	print("MATCH_PERF ", JSON.stringify(out))
