extends Node
## Stage for tests/perf_boss.gd: a Boss Battle in the real game, measured
## (physics_ms is Godot's worst physics tick in each second, not an average)
## frame by frame through the boss's arrival (its cinematic, BossIntro) and
## the fight after, with where the time goes: the CPU's game code (process,
## physics) and rendering, and the GPU's. Writes a JSON summary per phase.

const FIGHT := 25.0     ## seconds of fight measured

var out_path := "user://boss_perf.json"
var map := "island"
var quality := 4
var probe := false      ## then: the fight again with one thing at a time switched off
var _rows: Array = []
var _phase := ""
var _last := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		out_path = a[0]
	if a.size() > 1:
		map = a[1]
	if a.size() > 2:
		quality = int(a[2])
	probe = a.has("probe")
	if a.has("noragdoll"):   # (A/B: a corpse's ragdoll stops a moment after it falls)
		Events.critter_died.connect(func(v, _i):
			get_tree().create_timer(0.3).timeout.connect(func():
				if is_instance_valid(v) and v.visual and v.visual.phys_sim:
					v.visual.phys_sim.physical_bones_stop_simulation()
					v.visual.phys_sim.active = false))
	_run.call_deferred()


func _process(_delta: float) -> void:
	if _phase == "":
		return
	var now := Time.get_ticks_usec()
	if _last > 0:
		var vp := get_viewport().get_viewport_rid()
		_rows.append([_phase, (now - _last) / 1000.0, Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
			Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, RenderingServer.viewport_get_measured_render_time_cpu(vp),
			RenderingServer.viewport_get_measured_render_time_gpu(vp), Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
			get_tree().get_nodes_in_group(&"critters").filter(func(c): return not c.alive).size()])
	_last = now


func _run() -> void:
	var settings: Node = get_tree().root.get_node("Settings")
	settings.set_value(&"quality", quality, false)
	settings.set_value(&"map", map, false)
	settings.set_value(&"mode", "boss", false)
	settings.set_value(&"boss_intro", true, false)
	settings.set_value(&"seed", 4321, false)
	settings.set_value(&"vsync", 0, false)
	settings.set_value(&"max_fps", 0, false)
	get_tree().change_scene_to_file("res://scenes/game.tscn")
	var g: Node = null
	while g == null or g.get("match_manager") == null or g.match_manager.phase == MatchManager.Phase.LOADING:
		await get_tree().process_frame
		g = get_tree().current_scene
	var mm: MatchManager = g.match_manager
	var p := mm.player
	p.max_health = 100000.0
	p.health = p.max_health
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	mm.player_jump()
	while p.state != Critter.State.GROUND:
		p.want_jump = p.state == Critter.State.FREEFALL
		await get_tree().process_frame
	while mm.phase != MatchManager.Phase.PLAYING:
		await get_tree().process_frame
	_phase = "before"
	await _seconds(4.0)
	_phase = "arrival"
	mm.release_boss()
	var b := mm.boss
	await get_tree().process_frame
	var intro: Node = g.get_node_or_null("BossIntro")
	while intro and is_instance_valid(intro) and intro.get("playing"):
		await get_tree().process_frame
	# the fight: you 40 m off, facing it, the bots at it
	_phase = "fight"
	var t := 0.0
	while t < FIRST_LOOK:
		await get_tree().process_frame
		t += get_process_delta_time()
	var start := Time.get_ticks_msec()
	while (Time.get_ticks_msec() - start) / 1000.0 < FIGHT and mm.phase == MatchManager.Phase.PLAYING and b.alive:
		var to := b.get_chest_position() - p.get_eye_position()
		g.rig.yaw = atan2(-to.x, -to.z)
		g.rig.pitch = atan2(to.y, Vector2(to.x, to.z).length()) * 0.7
		await get_tree().process_frame
	if probe and b.alive:
		await _probe(mm, b, g, p)
	_phase = ""
	_write()
	get_tree().quit()


## Five seconds each, the boss standing still (so nobody's beaten down mid-way):
## the carrots in flight not moving; the boss not hittable (carrots fly through);
## the bots not moving (they still shoot); then all of it on again.
func _probe(mm: MatchManager, b: Boss, g: Node, p: Critter) -> void:
	b.thinking = false
	b.health = b.max_health * 100.0
	var proj: Node = get_tree().current_scene.find_child("Projectiles", true, false)
	var bots := mm.critters.filter(func(c): return c != p and c.alive)
	_phase = "idle_boss"
	await _seconds(5.0)
	_phase = "no_carrots"
	proj.set_physics_process(false)
	await _seconds(5.0)
	proj.set_physics_process(true)
	_phase = "not_hittable"
	b._set_hittable(false)
	await _seconds(5.0)
	b._set_hittable(true)
	_phase = "bots_still"
	for c in bots:
		c.set_physics_process(false)
	await _seconds(5.0)
	for c in bots:
		c.set_physics_process(true)
	_phase = "all_on"
	await _seconds(5.0)


func _probe_old(mm: MatchManager, b: Boss, g: Node, p: Critter) -> void:
	var brains := mm.critters.map(func(c): return c.get_node_or_null("AIBrain")).filter(func(n): return n != null)
	_phase = "boss_frozen"
	b.set_physics_process(false)
	await _seconds(6.0)
	b.set_physics_process(true)
	_phase = "brains_off"
	for br in brains:
		br.set_physics_process(false)
	await _seconds(6.0)
	for br in brains:
		br.set_physics_process(true)
	_phase = "bones_still"
	var keep: Dictionary = b._anchors
	b._anchors = {}
	await _seconds(6.0)
	b._anchors = keep
	_phase = "not_solid"
	b._set_hittable(false)
	await _seconds(6.0)
	b._set_hittable(true)
	_phase = "fight_again"
	await _seconds(6.0)


const FIRST_LOOK := 0.5


func _seconds(s: float) -> void:
	var start := Time.get_ticks_msec()
	while (Time.get_ticks_msec() - start) / 1000.0 < s:
		await get_tree().process_frame


func _write() -> void:
	var out := {"map": map, "quality": quality, "size": [get_viewport().size.x, get_viewport().size.y], "phases": {}}
	for ph in ["before", "arrival", "fight", "idle_boss", "no_carrots", "not_hittable", "bots_still", "all_on"]:
		var rows := _rows.filter(func(r): return r[0] == ph)
		if rows.is_empty():
			continue
		var frames: Array = rows.map(func(r): return r[1])
		frames.sort()
		var n := frames.size()
		var avg := func(i: int) -> float: return rows.reduce(func(acc, r): return acc + float(r[i]), 0.0) / n
		var peak := func(i: int) -> float: return rows.reduce(func(acc, r): return maxf(acc, float(r[i])), 0.0)
		out.phases[ph] = {"frames": n, "fps": 1000.0 / avg.call(1), "ms_p50": frames[n / 2], "ms_p95": frames[int(n * 0.95)],
			"ms_p99": frames[mini(n - 1, int(n * 0.99))], "ms_worst": frames[n - 1], "frames_over_33ms": frames.filter(func(f): return f > 33.3).size(),
			"process_ms": avg.call(2), "physics_ms": avg.call(3), "render_cpu_ms": avg.call(4), "render_gpu_ms": avg.call(5),
			"render_gpu_ms_peak": peak.call(5), "process_ms_peak": peak.call(2), "physics_ms_peak": peak.call(3),
			"draw_calls": avg.call(6), "primitives": avg.call(7), "dead": avg.call(8)}
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(out, "  "))
	f.close()
	print("BOSS_PERF ", JSON.stringify(out))
