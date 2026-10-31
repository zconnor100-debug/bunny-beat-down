class_name RobotBoss
extends Boss
## The Tin Tyrant, the Toy Box's boss: a wind-up tin robot gone wrong
## (assets/bosses/robot/). Tin plate takes the sting out of carrots, but not
## at its wind-up key, and not while it's wound down.
##   Eye Lasers: two red beams swept across the floor. Anything solid
##     between you and its eyes keeps them off you.
##   Toy Missiles: a volley of little rockets from its head, each landing on
##     its own red ring.
##   Clamp Smash: both clamps down on whoever's in front of it.
##   Wind-Down: every so often its key runs out. It stands there, wound
##     down, taking double (the key, triple that) until it winds itself up
##     again with a blast of steam.

const LASER_DPS := 100.0
const LASER_TRACK := 12.0           ## m/s the beams chase their target at
const MISSILE_RADIUS := 6.5
const CLAMP_RADIUS := 12.0
const WIND_EVERY := 34.0
const WOUND_DOWN := 6.0

var _key_angle := 0.0
var _key_speed := 360.0             # degrees a second (it winds down, and up again)
var _beams: Array[MeshInstance3D] = []
var _laser_t := 0.0
var _scorch_t := 0.0
var _wind_at := WIND_EVERY
var _missile_mat: StandardMaterial3D


func _init() -> void:
	super()
	id = "robot"
	display_name = "Tin Tyrant"
	title = "the Wind-Up Warlord"
	base_health = 30000.0
	walk_speed = 8.0
	turn_speed = 1.2
	armor = 0.75
	weak_spots = {&"key": 2.8, &"head": 1.6}
	limb_scale = 0.8
	blood = Color(0.08, 0.07, 0.06)   # (oil)
	solid_roles = [&"hips", &"chest", &"l_upper_leg", &"r_upper_leg"]


func stride() -> float:
	return 0.12


func step_sound() -> StringName:
	return &"boss_clank"


## A wind-up toy's march: stiff legs, a rock from side to side, arms out.
func walk_pose(phase: float, amount: float) -> Dictionary:
	var s := sin(phase)
	return {
		&"l_upper_leg": Vector3(-24.0 * s * amount, 0, 0), &"r_upper_leg": Vector3(24.0 * s * amount, 0, 0),
		&"hips": Vector3(0, 0, 7.0 * s * amount), &"chest": Vector3(0, 4.0 * s * amount, -3.0 * s * amount),
		&"l_upper_arm": Vector3(-8.0 * s * amount, 0, 0), &"r_upper_arm": Vector3(8.0 * s * amount, 0, 0),
		&"root": Vector3(0, absf(sin(phase)) * 0.012 * amount, 0),
	}


func idle_pose(t: float) -> Dictionary:
	return {&"head": Vector3(0, 6.0 * sin(t * 0.7), 0), &"key": Vector3(_key_angle, 0, 0)}


func eye_color(angry: bool) -> Color:
	return Color(1.0, 0.05, 0.02) if angry else Color(1.0, 0.25, 0.1)


func enrage_line() -> String:
	return "OVERDRIVE: faster lasers, more missiles. Its key is still its weak spot."


func attack_name(what: StringName) -> String:
	return {&"lasers": "Eye Lasers", &"missile": "Toy Missile", &"clamp": "Clamp Smash", &"steam": "Steam",
		&"landing": "Landing"}.get(what, super(what))


func _hit_fx(info: DamageInfo) -> void:
	BossFX.sparks(last_hit_pos, -info.direction, clampf(info.amount / 40.0, 0.4, 1.4))
	if info.bone_role == &"key":
		Audio.play_at(&"armor_break", last_hit_pos, -4.0, 0.2)


func _physics_process(delta: float) -> void:
	_key_angle = fposmod(_key_angle + _key_speed * delta, 360.0)
	super(delta)


# ---- choosing ----------------------------------------------------------------------------------

func _choose(t: Critter) -> BossAction:
	if _clock >= _wind_at:
		return _wind_down()
	var d := Vector2(t.global_position.x - global_position.x, t.global_position.z - global_position.z).length()
	if d < CLAMP_RADIUS + 8.0 and is_ready(&"clamp"):
		return _clamp()
	if d > 18.0 and d < 110.0 and is_ready(&"lasers"):
		return _lasers(t)
	if d > 25.0 and d < 130.0 and is_ready(&"barrage"):
		return _barrage(t)
	return null


# ---- Eye Lasers --------------------------------------------------------------------------------

func _lasers(t: Critter) -> BossAction:
	cooldown(&"lasers", 8.0)
	var aim := 1.0
	var fire := 3.0 if enraged else 2.6
	var a := BossAction.new(&"lasers", aim + fire + 0.6)
	var to := t.global_position - global_position
	to.y = 0.0
	var side := to.normalized().cross(Vector3.UP) * (1.0 if randf() < 0.5 else -1.0)
	var start := t.global_position - side * 12.0   # (it starts off to one side and comes for you)
	start.y = ground_y(start)
	var track := LASER_TRACK * (1.35 if enraged else 1.0)
	var beam := {"at": start}
	a.key(0.0, {}).key(aim, {&"head": Vector3(12, 0, 0), &"chest": Vector3(6, 0, 0)}).key(aim + fire, {&"head": Vector3(12, 0, 0)}).key(aim + fire + 0.6, {})
	a.on(0.0, func(): warn_strip(start, t.global_position, 5.0, aim))
	a.on(maxf(aim - 0.7, 0.0), func():   # (the sound's charge-up whine runs into the beams)
		Audio.play_at(&"boss_laser", get_eye_position(), 8.0, 0.0, {"max_distance": 450.0, "unit_size": 30.0}))
	a.on(aim, func(): _beams_on())
	a.on(aim + fire, func(): _beams_off())
	a.tick = func(time: float, delta: float):
		var at: Vector3 = beam["at"]
		if time >= aim and time < aim + fire:
			# the beams chase whoever it's after (a sprint just outruns them: get behind something)
			var goal := t.global_position if is_instance_valid(t) and t.alive else at
			var flat := Vector3(goal.x - at.x, 0.0, goal.z - at.z)
			at += flat.limit_length(track * delta)
			at.y = ground_y(at)
			beam["at"] = at
			_fire_beams(at, delta)
		face_toward(at, delta, 0.9)
	a.data["cancel"] = func(): _beams_off()
	return a


func _beams_on() -> void:
	_beams_off()
	for e in eye_positions():
		var b := BossFX.beam()
		if b:
			_beams.append(b)
	_laser_t = 0.0


func _beams_off() -> void:
	for b in _beams:
		if is_instance_valid(b):
			b.queue_free()
	_beams.clear()


## Both beams on `point` (or on whatever's in the way), burning anyone there.
func _fire_beams(point: Vector3, delta: float) -> void:
	var eyes := eye_positions()
	var ends: Array[Vector3] = []
	var space := get_world_3d().direct_space_state
	for i in eyes.size():
		var e: Vector3 = eyes[i]
		var dir := (point - e).normalized()
		var q := PhysicsRayQueryParameters3D.create(e, point + dir * 6.0, Layers.WORLD)
		var hit := space.intersect_ray(q)
		var end: Vector3 = hit.position if hit else point
		ends.append(end)
		if i < _beams.size():
			BossFX.set_beam(_beams[i], e, end, 0.55 if enraged else 0.45)
	_laser_t += delta
	if _laser_t >= 0.1:
		_laser_t = 0.0
		for c in foes():
			for i in eyes.size():
				var cp := c.get_chest_position()
				var on_beam := Geometry3D.get_closest_point_to_segment(cp, eyes[i], ends[i]).distance_to(cp) < 2.0
				if on_beam or Vector2(cp.x - ends[i].x, cp.z - ends[i].z).length() < 3.5 and absf(cp.y - ends[i].y) < 4.0:
					hurt(c, LASER_DPS * 0.1, (cp - ends[i]).normalized(), 0.0, 0.0, &"lasers", DamageInfo.Kind.BULLET, 0.2)
					break
	_scorch_t += delta
	if _scorch_t >= 0.12 and not ends.is_empty():
		_scorch_t = 0.0
		for end in ends:
			BossFX.sparks(end, Vector3.UP, 0.8)
			if FX.instance:
				FX.instance._decal(end, Vector3.UP, 3.0, FXTextures.scorch())


# ---- Toy Missiles ------------------------------------------------------------------------------

func _barrage(t: Critter) -> BossAction:
	cooldown(&"barrage", 9.0)
	var n := 16 if enraged else 12
	var a := BossAction.new(&"barrage", 1.0 + n * 0.16 + 0.8)
	var up := {&"l_upper_arm": Vector3(-70, 0, 15), &"r_upper_arm": Vector3(-70, 0, -15), &"head": Vector3(-15, 0, 0),
		&"l_claw_a": Vector3(-35, 0, 0), &"l_claw_b": Vector3(35, 0, 0), &"r_claw_a": Vector3(-35, 0, 0), &"r_claw_b": Vector3(35, 0, 0)}
	a.key(0.0, {}).key(0.6, up).key(1.0 + n * 0.16, up).key(a.length, {})
	for i in n:
		a.on(0.8 + i * 0.16, func(): _launch(t))
	a.tick = func(_t: float, delta: float):
		if is_instance_valid(t) and t.alive:
			face_toward(t.global_position, delta, 1.0)
	return a


func _launch(t: Critter) -> void:
	var from := bone_point(&"head", 1.0) + Vector3.UP * 2.0
	var aim := global_position + forward() * 50.0
	if is_instance_valid(t) and t.alive:
		aim = t.global_position + Vector3(t.velocity.x, 0.0, t.velocity.z) * 1.2
	var at := aim + Vector3(randf_range(-1, 1), 0.0, randf_range(-1, 1)).normalized() * randf_range(0.0, 9.0)
	at.y = ground_y(at)
	var flight := randf_range(1.7, 2.3)
	warn(at, MISSILE_RADIUS, flight)
	var m := _missile()
	get_parent().add_child(m)
	m.global_position = from
	var trail := FX.smoke_trail(m)
	var mid := (from + at) * 0.5 + Vector3.UP * randf_range(55.0, 75.0)
	var fly := func(u: float):
		if not is_instance_valid(m):
			return
		var p := from.lerp(mid, u).lerp(mid.lerp(at, u), u)   # (a curve up and over)
		var ahead := from.lerp(mid, minf(u + 0.02, 1.0)).lerp(mid.lerp(at, minf(u + 0.02, 1.0)), minf(u + 0.02, 1.0))
		m.global_position = p
		if ahead.distance_to(p) > 0.01:
			m.look_at(ahead, Vector3.UP if absf((ahead - p).normalized().y) < 0.98 else Vector3.RIGHT)
	var tw := m.create_tween()
	tw.tween_method(fly, 0.0, 1.0, flight)
	tw.tween_callback(func():
		if trail and is_instance_valid(trail):
			trail.reparent(get_parent())
			trail.emitting = false
			Despawner.after(trail, 2.0, func(n: Node): n.queue_free())
		hurt_ring(at, MISSILE_RADIUS, 55.0, 18.0, 9.0, 7.0, &"missile", false)
		FX.explosion(at, 4.5)
		Audio.play_at(&"explosion", at, 0.0, 0.12, {"max_distance": 250.0})
		m.queue_free())
	Audio.play_at(&"rocket_fire", from, -2.0, 0.15, {"max_distance": 250.0})


## A little toy rocket: red, white-nosed, finned.
func _missile() -> Node3D:
	if _missile_mat == null:
		_missile_mat = StandardMaterial3D.new()
		_missile_mat.albedo_color = Color(0.85, 0.12, 0.08)
		_missile_mat.roughness = 0.35
	var root := Node3D.new()
	root.name = "ToyMissile"
	var body := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.35
	cm.bottom_radius = 0.35
	cm.height = 2.4
	body.mesh = cm
	body.material_override = _missile_mat
	body.rotation.x = -PI * 0.5   # (along -Z: the way it flies)
	root.add_child(body)
	var nose := MeshInstance3D.new()
	var nm := CylinderMesh.new()
	nm.top_radius = 0.0
	nm.bottom_radius = 0.35
	nm.height = 0.8
	nose.mesh = nm
	var white := StandardMaterial3D.new()
	white.albedo_color = Color(0.95, 0.93, 0.88)
	nose.material_override = white
	nose.rotation.x = -PI * 0.5
	nose.position.z = -1.6
	root.add_child(nose)
	return root


# ---- Clamp Smash ---------------------------------------------------------------------------------

func _clamp() -> BossAction:
	cooldown(&"clamp", 5.0)
	var hit_at := 0.85 if enraged else 1.0
	var a := BossAction.new(&"clamp", hit_at + 1.0)
	var centre := global_position + forward() * 11.0
	centre.y = ground_y(centre)
	a.key(0.0, {})
	a.key(hit_at * 0.8, {&"l_upper_arm": Vector3(-75, 0, 0), &"r_upper_arm": Vector3(-75, 0, 0), &"chest": Vector3(-8, 0, 0),
		&"l_claw_a": Vector3(-40, 0, 0), &"l_claw_b": Vector3(40, 0, 0), &"r_claw_a": Vector3(-40, 0, 0), &"r_claw_b": Vector3(40, 0, 0)})
	a.key(hit_at, {&"l_upper_arm": Vector3(55, 0, 0), &"r_upper_arm": Vector3(55, 0, 0), &"chest": Vector3(14, 0, 0),
		&"root": Vector3(0, -0.02, 0)})
	a.key(hit_at + 0.5, {&"l_upper_arm": Vector3(50, 0, 0), &"r_upper_arm": Vector3(50, 0, 0), &"chest": Vector3(12, 0, 0)})
	a.key(hit_at + 1.0, {})
	a.on(0.0, func(): warn(centre, CLAMP_RADIUS, hit_at))
	a.on(hit_at, func():
		hurt_ring(centre, CLAMP_RADIUS, 75.0, 25.0, 12.0, 8.0, &"clamp")
		BossFX.shockwave(centre, CLAMP_RADIUS)
		BossFX.sparks(centre + Vector3.UP, Vector3.UP, 2.0)
		Events.explosion.emit(centre, CLAMP_RADIUS * 0.6)
		Audio.play_at(&"boss_clank", centre, 10.0, 0.05, {"max_distance": 500.0, "unit_size": 30.0}))
	return a


# ---- Wind-Down ---------------------------------------------------------------------------------

func _wind_down() -> BossAction:
	_wind_at = _clock + WIND_EVERY + WOUND_DOWN
	var a := BossAction.new(&"winddown", WOUND_DOWN + 2.2)
	a.interruptible = false
	var slump := {&"chest": Vector3(28, 0, 6), &"head": Vector3(22, 0, 8), &"l_upper_arm": Vector3(70, 0, 8),
		&"r_upper_arm": Vector3(70, 0, -8), &"root": Vector3(0, -0.03, 0)}
	a.key(0.0, {}).key(1.2, slump).key(WOUND_DOWN, slump)
	a.key(WOUND_DOWN + 0.5, {&"chest": Vector3(-12, 0, 0), &"head": Vector3(-10, 0, 0)}).key(WOUND_DOWN + 2.2, {})
	a.on(0.0, func():
		Events.announce.emit("THE TIN TYRANT IS WINDING DOWN!", "Shoot its wind-up key: everything hurts it more now.")
		vulnerable_until = _clock + WOUND_DOWN)
	a.tick = func(time: float, _delta: float):
		if time < WOUND_DOWN:
			_key_speed = lerpf(360.0, 0.0, clampf(time / 1.2, 0.0, 1.0))
		else:
			_key_speed = lerpf(0.0, 1800.0, clampf((time - WOUND_DOWN) / 0.5, 0.0, 1.0)) if time < WOUND_DOWN + 1.2 else 360.0
	a.on(WOUND_DOWN + 0.5, func():
		hurt_ring(global_position, 15.0, 25.0, 8.0, 14.0, 6.0, &"steam", false)
		BossFX.dust(global_position + Vector3.UP * 8.0, 15.0, Color(0.92, 0.92, 0.9, 0.55))
		Events.explosion.emit(global_position, 12.0))
	a.data["cancel"] = func(): _key_speed = 360.0
	return a


## OVERDRIVE (enraged): a burst of steam, eyes red.
func _roar_action() -> BossAction:
	var a := BossAction.new(&"overdrive", 1.8)
	var pose := {&"chest": Vector3(-14, 0, 0), &"head": Vector3(-18, 0, 0), &"l_upper_arm": Vector3(-110, 0, 25),
		&"r_upper_arm": Vector3(-110, 0, -25)}
	a.key(0.0, {}).key(0.5, pose).key(1.3, pose).key(1.8, {})
	a.on(0.5, func():
		_key_speed = 900.0
		hurt_ring(global_position, 30.0, 10.0, 4.0, 10.0, 5.0, &"steam", false)
		BossFX.dust(global_position + Vector3.UP * 10.0, 25.0, Color(0.92, 0.92, 0.9, 0.55))
		Events.explosion.emit(global_position, 20.0)
		var p := Audio.play_at(&"storm_loop", global_position, 6.0, 0.0, {"max_distance": 500.0})
		if p:
			p.pitch_scale = 2.0)
	return a


# ---- arriving, and going down -------------------------------------------------------------------

## Dropped into the room like any toy, it lands with a clang and winds itself
## up. (Or, with `entrance_from`, it jumps: off the bookshelf, in a long arc
## over the room, arms up, and comes down the same way.)
func _entrance() -> BossAction:
	var at := global_position
	var drop := land_time
	var from := entrance_from
	var a := BossAction.new(&"entrance", drop + 3.0)
	a.interruptible = false
	_key_speed = 0.0 if from == Vector3.INF else 900.0
	var flying := {&"chest": Vector3(20, 0, 0)} if from == Vector3.INF else \
		{&"chest": Vector3(-8, 0, 0), &"l_upper_arm": Vector3(-150, 0, 20), &"r_upper_arm": Vector3(-150, 0, -20),
			&"l_upper_leg": Vector3(-25, 0, 0), &"r_upper_leg": Vector3(20, 0, 0)}
	a.key(0.0, flying).key(drop * 0.85, flying).key(drop, {&"chest": Vector3(20, 0, 0), &"root": Vector3(0, -0.03, 0)})
	a.key(drop + 2.2, {&"chest": Vector3(-10, 0, 0), &"head": Vector3(-12, 0, 0)}).key(drop + 3.0, {})
	a.on(0.0, func(): warn(at, 24.0, drop))
	a.tick = func(time: float, _delta: float):
		if time < drop:
			var u := time / drop
			if from == Vector3.INF:
				global_position = at + Vector3.UP * 200.0 * (1.0 - u * u)
			else:
				# a long arc: up a little off the shelf, then down onto the floor
				var top := maxf(from.y, at.y) + 40.0
				var p := from.lerp(at, u)
				p.y = lerpf(from.y, at.y, u) + (top - maxf(from.y, at.y)) * 4.0 * u * (1.0 - u)
				global_position = p
		else:
			_key_speed = lerpf(0.0, 720.0, clampf((time - drop) / 2.0, 0.0, 1.0))
	a.on(drop, func():
		global_position = at
		hurt_ring(at, 24.0, 50.0, 10.0, 14.0, 9.0, &"landing")
		BossFX.shockwave(at, 24.0)
		Events.explosion.emit(at, 16.0)
		Audio.play_at(&"boss_clank", at, 12.0, 0.0, {"max_distance": 700.0, "unit_size": 45.0})
		Audio.play_at(&"boss_stomp", at, 6.0, 0.0, {"max_distance": 700.0, "unit_size": 45.0}))
	return a


## It topples onto its face, sparking.
func _death_action() -> BossAction:
	_beams_off()
	var a := BossAction.new(&"death", 2.4)
	a.blend_out = 0.0
	a.interruptible = false
	a.key(0.0, {}).key(0.7, {&"hips": Vector3(8, 0, 0), &"head": Vector3(20, 0, 0)})
	a.key(1.6, {&"hips": Vector3(84, 0, 0), &"head": Vector3(10, 0, 0), &"l_upper_arm": Vector3(-60, 0, 30),
		&"r_upper_arm": Vector3(-60, 0, -30), &"root": Vector3(0, -0.2, 0)})
	a.key(2.4, {&"hips": Vector3(84, 0, 0), &"head": Vector3(10, 0, 0), &"l_upper_arm": Vector3(-60, 0, 30),
		&"r_upper_arm": Vector3(-60, 0, -30), &"root": Vector3(0, -0.21, 0)})
	a.tick = func(_t: float, delta: float): _key_speed = maxf(0.0, _key_speed - 400.0 * delta)
	a.on(1.6, func():
		BossFX.shockwave(global_position + forward() * HEIGHT * 0.5, HEIGHT)
		BossFX.sparks(get_chest_position(), Vector3.UP, 3.0)
		Events.explosion.emit(global_position, 20.0)
		Audio.play_at(&"boss_clank", global_position, 12.0, 0.0, {"max_distance": 700.0, "unit_size": 45.0})
		Audio.play_at(&"explosion", global_position, 6.0, 0.0, {"max_distance": 600.0, "unit_size": 40.0}))
	return a


func _fallen() -> void:
	BossFX.chips(get_chest_position(), 2.5, Color(0.35, 0.45, 0.6))
	BossFX.dust(global_position, 25.0, Color(0.92, 0.92, 0.9, 0.5))
