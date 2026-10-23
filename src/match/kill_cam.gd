class_name KillCam
extends Node
## The final shot: when the last-but-one critter goes down, time slows to a
## crawl, then the world freezes and the shot plays again from three angles
## (over the shooter's shoulder, riding the carrot, close on the beat-down)
## before the end screen.
##
## Once only a few critters are left standing it starts recording the last
## few seconds, over and over: every one of them, body and bones (ReplayPose,
## the last modifier on each skeleton), the carrots in flight, rockets, gibs
## and helmets flying off, the blood and dust, and the sounds. The replay
## puts all of that back frame by frame with the world paused, so nothing in
## the match moves on underneath it.

signal finished

const RECORD_WHEN_ALIVE := 4      ## start recording with this many left
const KEEP := 5.0                 ## seconds of history kept while recording
const PRE := 1.3                  ## replay this long before the kill...
const POST := 1.2                 ## ...and this long after
const SLOW_SCALE := 0.2           ## time scale for the slow motion at the kill
const SLOW_REAL := 1.4            ## real seconds of slow motion
const RAMP_REAL := 0.5            ## and of easing back to full speed

static var instance: KillCam
static var recording := false     ## (the hooks check this, cheaply)

var match_manager: MatchManager
var clock := 0.0                  ## game seconds since recording began
var kill_time := -1.0
var victim: Critter
var shooter: Critter
var playing := false              ## the replay is on screen
var _poses: Dictionary = {}       # Critter -> ReplayPose
var _shots: Dictionary = {}       # Projectiles.Shot -> {t0, t1, origin, vel, g, data, own}
var _nodes: Array = []            # {node, t0, frames: [[t, xf]], ghost, live_xf, live_visible}
var _decals: Array = []           # [t, decal, old_xf, old_visible, new_xf]
var _events: Array = []           # [t, "fx", pos, dir, cfg] / [t, "sound", key, pos, volume] / [t, "flash", pos, radius]
var _cam: Camera3D
var _ui: CanvasLayer
var _caption: Label
var _flash: ColorRect
var _skip := false
var _replay_fx: Array[GPUParticles3D] = []
var _ghosts: Dictionary = {}      # entry index -> Node3D
var _last_event_t := -INF         # effects and sounds up to here have played


func _enter_tree() -> void:
	instance = self
	process_mode = Node.PROCESS_MODE_ALWAYS


func _exit_tree() -> void:
	if instance == self:
		instance = null
		recording = false
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	AudioServer.playback_speed_scale = 1.0


func _ready() -> void:
	Events.critter_died.connect(_on_critter_died)


func _process(delta: float) -> void:
	if playing or get_tree().paused:
		return
	if not recording:
		if match_manager and match_manager.phase == MatchManager.Phase.PLAYING and match_manager.alive_critters().size() <= RECORD_WHEN_ALIVE:
			start_recording()
		return
	clock += delta
	var old := clock - KEEP
	for n in _nodes:
		var frames: Array = n.frames
		if n.moves and is_instance_valid(n.node) and (n.node as Node3D).is_inside_tree():
			frames.append([clock, (n.node as Node3D).global_transform])
		while frames.size() > 2 and float(frames[1][0]) < old:
			frames.pop_front()
	# forget what's long gone (a rocket that went off a while ago)
	_nodes = _nodes.filter(func(n): return is_instance_valid(n.node) or _last_t(n) >= old)
	_decals = _decals.filter(func(d): return float(d[0]) >= old)
	while not _events.is_empty() and float(_events[0][0]) < old:
		_events.pop_front()
	for s in _shots.keys():
		if float(_shots[s].t1) < old:
			_shots.erase(s)


## Begin keeping the last few seconds (the KillCam does this by itself once
## RECORD_WHEN_ALIVE critters are left).
func start_recording() -> void:
	recording = true
	for c in match_manager.alive_critters():
		track(c)


## Keep a critter's body and bones in the recording.
func track(c: Critter) -> void:
	if _poses.has(c) or c.visual == null or c.visual.skeleton == null:
		return
	var rp := ReplayPose.new()
	rp.name = "ReplayPose"
	rp.visual = c.visual
	c.visual.skeleton.add_child(rp)   # last in the stack: sees the final pose
	_poses[c] = rp


func is_tracked(c: Critter) -> bool:
	return _poses.has(c)


# ---- hooks (projectiles, rockets, gore, effects and sounds report in) -----------------------------

func note_shot(s: Projectiles.Shot) -> void:
	var own := s.shooter is Critter and (s.shooter as Critter).is_player
	_shots[s] = {"t0": clock, "t1": INF, "origin": s.pos, "vel": s.vel, "g": s.gravity, "data": s.data, "own": own, "shooter": s.shooter}


func end_shot(s: Projectiles.Shot) -> void:
	if _shots.has(s):
		_shots[s].t1 = clock


## Something that appears mid-fight and may move (a gib, a helmet, a rocket,
## a stump): hidden in the replay until its moment, then where it was. A
## rocket is gone by replay time, so it leaves `ghost` (a model path) behind.
func note_node(node: Node3D, ghost := "", moves := true) -> void:
	if not node.is_inside_tree():
		return
	_nodes.append({"node": node, "t0": clock, "frames": [[clock, node.global_transform]], "ghost": ghost, "moves": moves})


func note_decal(d: Decal, old_xf: Transform3D, old_visible: bool) -> void:
	_decals.append([clock, d, old_xf, old_visible, d.global_transform])


func note_fx(pos: Vector3, dir: Vector3, cfg: Dictionary) -> void:
	_events.append([clock, "fx", pos, dir, cfg])


func note_flash(pos: Vector3, radius: float) -> void:
	_events.append([clock, "flash", pos, radius])


func note_sound(key: StringName, pos: Variant, volume_db: float) -> void:
	_events.append([clock, "sound", key, pos, volume_db])


# ---- the final shot -------------------------------------------------------------------------------

## (Without a match, e.g. in tests: the last tracked critter standing wins.)
func _on_critter_died(victim_: Node, info: DamageInfo) -> void:
	if match_manager != null:
		return   # the match tells us itself, before it announces the winner
	var standing := _poses.keys().filter(func(c): return is_instance_valid(c) and c.alive)
	if standing.size() <= 1:
		note_final(victim_ as Critter, info)


## The match's last beat-down just happened (MatchManager calls this before
## it announces the winner, so the end screen can wait for the replay).
func note_final(victim_: Critter, info: DamageInfo) -> void:
	if not recording or playing or kill_time >= 0.0:
		return
	kill_time = clock
	victim = victim_
	shooter = info.attacker as Critter if info and info.attacker is Critter and info.attacker != victim_ else null


## Is there a final shot on tape to show?
func has_final() -> bool:
	return kill_time >= 0.0 and victim != null and _poses.has(victim)


## The slow motion at the kill, the rest of the fall at full speed, then the
## replay. Emits `finished` (and returns) when it's over or skipped.
func play_final() -> void:
	if not has_final():
		finished.emit()
		return
	# slow motion: physics ticks faster so the ragdolls stay smooth
	Engine.physics_ticks_per_second = int(60.0 / SLOW_SCALE)
	Engine.time_scale = SLOW_SCALE
	AudioServer.playback_speed_scale = 0.6
	await get_tree().create_timer(SLOW_REAL, true, false, true).timeout
	var tw := create_tween().set_ignore_time_scale(true)
	tw.tween_method(func(v: float):
		Engine.time_scale = v
		AudioServer.playback_speed_scale = lerpf(0.6, 1.0, (v - SLOW_SCALE) / (1.0 - SLOW_SCALE)), SLOW_SCALE, 1.0, RAMP_REAL)
	await tw.finished
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	AudioServer.playback_speed_scale = 1.0
	while clock < kill_time + POST and is_inside_tree():
		await get_tree().process_frame
	recording = false
	await _replay()
	finished.emit()


# ---- the replay -------------------------------------------------------------------------------------

func _replay() -> void:
	playing = true
	_skip = false
	var tree := get_tree()
	tree.paused = true
	var prev_cam := get_viewport().get_camera_3d()
	_freeze_scene(true)
	_build_ui()
	_cam = Camera3D.new()
	_cam.far = 2500.0
	var view := get_viewport().get_visible_rect().size
	_cam.fov = 60.0 if view.x >= view.y else 85.0   # (a tall window needs a wider lens)
	add_child(_cam)
	_cam.make_current()
	var shot := _killing_shot()
	var whose := "your" if shooter and shooter.is_player else ("%s's" % shooter.display_name if shooter else "the winner's")
	var angles := [["THE SHOT", "over %s shoulder" % whose],
		["THE CARROT" if not shot.is_empty() else "SIDE ON", "riding the carrot" if not shot.is_empty() else "the whole picture"],
		["THE BEAT DOWN", "%s goes down" % victim.display_name]]
	for i in 3:
		if _skip:
			break
		_caption.text = "●  REPLAY  %d/3   %s — %s" % [i + 1, angles[i][0], angles[i][1]]
		_flash_cut()
		await _play_angle(i, shot)
	# put the world back exactly as the replay found it
	_show(INF)
	_freeze_scene(false)
	_cam.clear_current(false)
	_cam.queue_free()
	_cam = null
	if prev_cam and is_instance_valid(prev_cam):
		prev_cam.make_current()
	_ui.queue_free()
	_ui = null
	tree.paused = false
	playing = false


## One camera angle: plays its stretch of the recording at its own speed.
func _play_angle(i: int, shot: Dictionary) -> void:
	var t0 := kill_time - 1.0
	var t1 := kill_time + 0.8
	var speed := func(t: float) -> float:
		return lerpf(0.45, 1.0, smoothstep(0.1, 0.7, absf(t - kill_time)))
	match i:
		1:
			if not shot.is_empty():
				# from the moment the carrot is clear of the shooter, in bullet time
				t0 = maxf(float(shot.t0) + _clear_of_muzzle(shot), kill_time - PRE)
				t1 = kill_time + 0.7
				speed = func(t: float) -> float: return 0.15 if t < float(shot.t1) else 0.45
			else:
				t0 = kill_time - 0.8
				t1 = kill_time + 0.8
				speed = func(_t: float) -> float: return 0.5
		2:
			t0 = kill_time - 0.2
			t1 = kill_time + 1.0
			speed = func(_t: float) -> float: return 0.45
	t0 = maxf(t0, _earliest())   # (never before the tape starts)
	var t := t0
	_last_event_t = t0 - 0.0001
	var first := true
	var clock := RealClock.new()
	clock.start()
	while t <= t1 and not _skip:
		_show(t)
		_aim_camera(i, t, shot, first)
		first = false
		var s: float = speed.call(t)
		for p in _replay_fx:
			if is_instance_valid(p):
				p.speed_scale = s
		await get_tree().process_frame
		t += clock.step(get_process_delta_time()) * s
	_clear_replay_fx()


func _aim_camera(i: int, t: float, shot: Dictionary, snap: bool) -> void:
	var v_focus := _focus(victim, t)
	var want_pos := Vector3.ZERO
	var want_look := v_focus
	var size := victim.visual.rig.world_head_top if victim.visual and victim.visual.rig else 2.0
	match i:
		0:
			# behind the shooter's shoulder, at head height, both of them in frame
			var s_size := shooter.visual.rig.world_head_top if shooter and shooter.visual and shooter.visual.rig else size
			var from := _focus(shooter, t) + Vector3.UP * s_size * 0.3 if shooter else v_focus + Vector3(6, 2, 6)
			var flat := v_focus - from
			flat.y = 0.0
			var dir := flat.normalized() if flat.length() > 0.1 else Vector3.FORWARD
			var right := dir.cross(Vector3.UP).normalized()
			want_pos = from - dir * (s_size * 1.2 + 1.5) + right * s_size * 0.8 + Vector3.UP * s_size * 0.3
			want_look = v_focus.lerp(from, 0.1)
		1:
			if not shot.is_empty() and t < float(shot.t1):
				# just behind the carrot and off to one side, looking where it goes
				var p := _shot_pos(shot, maxf(t, float(shot.t0)))
				var vel: Vector3 = (shot.vel as Vector3).normalized()
				var side := vel.cross(Vector3.UP).normalized()
				want_pos = p - vel * 1.4 + side * 0.7 + Vector3.UP * 0.35
				want_look = p + vel * 8.0
			else:
				var from := _focus(shooter, t) if shooter else v_focus + Vector3(8, 0, 0)
				var mid := (from + v_focus) * 0.5
				var across := (v_focus - from).cross(Vector3.UP).normalized()
				var dist := maxf(7.0, from.distance_to(v_focus) * 0.55)
				want_pos = mid + across * dist + Vector3.UP * size * 1.2
				want_look = mid.lerp(v_focus, 0.4)
				if not shot.is_empty():
					var hit := _shot_pos(shot, float(shot.t1))
					want_pos = hit + (hit - (shot.origin as Vector3)).normalized() * -3.0 + across * 2.5 + Vector3.UP * 1.2
					want_look = v_focus
		2:
			var a := (t - kill_time) * 0.9 + 0.6
			want_pos = v_focus + Vector3(cos(a), 0, sin(a)) * size * 1.8 + Vector3.UP * size * 0.45
	if snap:
		_cam.global_position = want_pos
	else:
		_cam.global_position = _cam.global_position.lerp(want_pos, 0.35)
	if _cam.global_position.distance_to(want_look) > 0.1:
		_cam.look_at(want_look, Vector3.UP)


## When the recording of the final fight starts.
func _earliest() -> float:
	var t := INF
	for c in [victim, shooter]:
		if c and _poses.has(c) and not (_poses[c] as ReplayPose).frames.is_empty():
			t = minf(t, float((_poses[c] as ReplayPose).frames[0][0]))
	return t if t < INF else kill_time


## Where a critter's chest was at time t (from its recording).
func _focus(c: Critter, t: float) -> Vector3:
	if c == null or not _poses.has(c):
		return victim.visual.global_position if victim else Vector3.ZERO
	var f: Array = (_poses[c] as ReplayPose).sample(t)
	return f[4] if not f.is_empty() else (_poses[c] as ReplayPose).focus_now()


## How long the carrot takes to get a few metres clear of whoever fired it
## (a camera behind it would be inside their head before that).
func _clear_of_muzzle(shot: Dictionary) -> float:
	return 3.0 / maxf((shot.vel as Vector3).length(), 1.0)


func _shot_pos(shot: Dictionary, t: float) -> Vector3:
	var dt := t - float(shot.t0)
	return (shot.origin as Vector3) + (shot.vel as Vector3) * dt + Vector3.DOWN * 0.5 * float(shot.g) * dt * dt


## The carrot that did it: the shooter's last shot to land near the victim
## around the moment of the kill.
func _killing_shot() -> Dictionary:
	var best: Dictionary = {}
	var best_d := 4.0
	for s in _shots:
		var r: Dictionary = _shots[s]
		if r.shooter != shooter or shooter == null or absf(float(r.t1) - kill_time) > 0.2:
			continue
		var d := _shot_pos(r, float(r.t1)).distance_to(_focus(victim, kill_time))
		if d < best_d:
			best_d = d
			best = r
	return best


## Put the whole recorded world at time t (INF: as it is now, for real).
func _show(t: float) -> void:
	for c in _poses:
		var rp: ReplayPose = _poses[c]
		if not is_instance_valid(rp):
			continue
		if t == INF:
			rp.play_at = -1.0
			if rp.frames.size() > 0:
				var last: Array = rp.frames[rp.frames.size() - 1]
				rp.visual.global_transform = last[1]
				rp.visual.model.transform = last[2]
			continue
		var f := rp.sample(t)
		if f.is_empty():
			continue
		rp.play_at = t
		rp.visual.global_transform = f[0]
		rp.visual.model.transform = f[1]
	for idx in _nodes.size():
		var n: Dictionary = _nodes[idx]
		var node: Node3D = n.node if is_instance_valid(n.node) else _ghost(idx)
		if node == null:
			continue
		if t == INF:
			if is_instance_valid(n.node):
				if n.moves:
					node.global_transform = n.live_xf
				node.visible = n.live_visible
			else:
				node.visible = false
			continue
		# (a ghost is only there while its rocket was)
		node.visible = t >= float(n.t0) and (is_instance_valid(n.node) or t <= _last_t(n))
		if node.visible and n.moves:
			node.global_transform = _xf_at(n.frames, t)
	for d in _decals:
		var decal: Decal = d[1]
		if not is_instance_valid(decal):
			continue
		var on := t >= float(d[0])
		decal.global_transform = d[4] if on else d[2]
		decal.visible = true if on else d[3]
	if t == INF:
		if Projectiles.instance:
			Projectiles.instance.draw_shots(Projectiles.instance.live_shots())
		return
	# carrots in flight
	var flying: Array[Projectiles.Shot] = []
	for s in _shots:
		var r: Dictionary = _shots[s]
		if t >= float(r.t0) and t < float(r.t1):
			var dt := t - float(r.t0)
			var shot := Projectiles.Shot.new()
			shot.pos = _shot_pos(r, t)
			shot.vel = (r.vel as Vector3) + Vector3.DOWN * float(r.g) * dt
			shot.data = r.data
			shot.shooter = r.shooter
			shot.travelled = shot.pos.distance_to(r.origin)
			flying.append(shot)
	if Projectiles.instance:
		Projectiles.instance.draw_shots(flying)
	# effects and sounds whose moment has come since the last frame
	for e in _events:
		var et := float(e[0])
		if et > t or et <= _last_event_t:
			continue
		match e[1]:
			"fx":
				var p: GPUParticles3D = FX.instance._burst(e[2], e[3], e[4]) if FX.instance else null
				if p:
					p.process_mode = Node.PROCESS_MODE_ALWAYS
					_replay_fx.append(p)
			"flash":
				if FX.instance:
					FX.instance._flash(e[2], e[3])
			"sound":
				var pl: Node = Audio.play_at(e[2], e[3], e[4], 0.0) if e[3] is Vector3 else Audio.play(e[2], e[4], 0.0)
				if pl:
					pl.pitch_scale = 0.75
	_last_event_t = t


func _last_t(n: Dictionary) -> float:
	var fr: Array = n.frames
	return float(fr[fr.size() - 1][0])


static func _xf_at(frames: Array, t: float) -> Transform3D:
	var i := frames.size() - 1
	while i > 0 and float(frames[i][0]) > t:
		i -= 1
	var a: Array = frames[i]
	var b: Array = frames[mini(i + 1, frames.size() - 1)]
	var span := float(b[0]) - float(a[0])
	return (a[1] as Transform3D).interpolate_with(b[1], clampf((t - float(a[0])) / span, 0.0, 1.0) if span > 1e-5 else 0.0)


## A stand-in for something that's gone by now (a rocket that went off).
func _ghost(idx: int) -> Node3D:
	if _ghosts.has(idx):
		return _ghosts[idx]
	var n: Dictionary = _nodes[idx]
	if String(n.ghost) == "":
		return null
	var g := ModelUtil.instantiate(n.ghost)
	if g == null:
		return null
	add_child(g)
	FX.smoke_trail(g)
	_ghosts[idx] = g
	return g


## Freeze/unfreeze the world for the replay: skeletons and effects keep
## running (so recorded poses and replayed sparks show), name tags and the
## HUD hide, and everything's live state is noted to put back afterwards.
func _freeze_scene(on: bool) -> void:
	for c in _poses:
		if not is_instance_valid(c) or c.visual == null:
			continue
		var v: CritterVisual = c.visual
		v.skeleton.process_mode = Node.PROCESS_MODE_ALWAYS if on else Node.PROCESS_MODE_INHERIT
		if v.name_tag:
			if on:
				v.set_meta(&"tag_was", v.name_tag.visible)
			v.name_tag.visible = false if on else bool(v.get_meta(&"tag_was", true))
		if c.is_player:
			# the replay shows your critter, even if you play in first person
			if on:
				v.set_meta(&"fp_was", v._first_person)
			v.set_first_person(false if on else bool(v.get_meta(&"fp_was", false)))
	if on:
		for n in _nodes:
			if is_instance_valid(n.node):
				n.live_xf = (n.node as Node3D).global_transform
				n.live_visible = (n.node as Node3D).visible
	if FX.instance:
		FX.instance.process_mode = Node.PROCESS_MODE_ALWAYS if on else Node.PROCESS_MODE_INHERIT
	if not on:
		for g in _ghosts.values():
			if is_instance_valid(g):
				g.queue_free()
		_ghosts.clear()


func _clear_replay_fx() -> void:
	for p in _replay_fx:
		if is_instance_valid(p):
			p.queue_free()
	_replay_fx.clear()


func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = 14
	add_child(_ui)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UITheme.theme()
	_ui.add_child(root)
	for top in [true, false]:
		var bar := ColorRect.new()
		bar.color = Color.BLACK
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.set_anchors_preset(Control.PRESET_TOP_WIDE if top else Control.PRESET_BOTTOM_WIDE)
		bar.custom_minimum_size.y = 90.0
		if not top:
			bar.offset_top = -90.0
		root.add_child(bar)
	_caption = UITheme.label("", 30, UITheme.CREAM, true)
	_caption.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_caption.position = Vector2(40, 24)
	root.add_child(_caption)
	var skip := UITheme.label("Skip: %s" % GameInput.prompt(&"jump"), 22, Color(UITheme.CREAM, 0.7))
	skip.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	skip.position = Vector2(-220, -64)
	root.add_child(skip)
	_flash = ColorRect.new()
	_flash.color = Color(1, 1, 1, 0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(_flash)


func _flash_cut() -> void:
	if _flash == null:
		return
	_flash.color.a = 0.85
	var tw := _flash.create_tween()
	tw.tween_property(_flash, "color:a", 0.0, 0.3)
	Audio.play(&"glider_open", -8.0, 0.0)


func _input(event: InputEvent) -> void:
	if not playing:
		return
	var pressed: bool = (event is InputEventKey and event.pressed and not event.echo) or (event is InputEventJoypadButton and event.pressed) \
		or (event is InputEventMouseButton and event.pressed)
	if pressed:
		_skip = true
		get_viewport().set_input_as_handled()
