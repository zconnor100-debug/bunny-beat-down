class_name HamsterBoss
extends Boss
## Nibbles, the Hamster Cage's boss: the cage's own hamster, grown huge and
## rabid (assets/bosses/hamster/: a golden hamster, its fur matted, blood on
## its teeth and paws, foam at the mouth, eyes gone red).
##   Frenzied Charge: head down, it runs at you flat out, trampling everyone
##     on the way. If it runs into a wall it knocks itself silly: hit it then.
##   Rabid Bite: up close it lunges, jaws first.
##   Foam Spit: globs of rabid foam that leave puddles: they burn, and they
##     slow you down.
##   Burrow (enraged): it dives into the bedding and comes up under you.

const CHARGE_SPEED := 36.0
const CHARGE_HIT := 9.0             ## metres either side of its path that get trampled
const BITE_RADIUS := 10.0
const FOAM_RADIUS := 9.0
const FOAM_DPS := 18.0
const FOAM_SECONDS := 10.0
const BURROW_RADIUS := 15.0

var _puddles: Array = []            # [centre, radius, until]
var _slowed: Dictionary = {}        # Critter -> true (in the foam: slow_factor down)
var _foam_t := 0.0                  # (foam dripping from its mouth, a drop at a time)
var _burn_t := 0.0


func _init() -> void:
	super()
	id = "hamster"
	display_name = "Nibbles"
	title = "the Rabid"
	base_health = 32000.0
	walk_speed = 12.0
	turn_speed = 1.9
	weak_spots = {&"head": 2.0, &"jaw": 2.0}
	limb_scale = 0.75
	solid_roles = [&"hips", &"spine", &"chest", &"neck"]


func stride() -> float:
	return 0.16


## A hamster's scurry: little legs going like mad, the body bobbing and
## rolling, leaning into it the faster it goes.
func walk_pose(phase: float, amount: float) -> Dictionary:
	var s := sin(phase * 2.0)
	var c := cos(phase * 2.0)
	return {
		&"l_upper_leg": Vector3(-30.0 * s * amount, 0, 0), &"r_upper_leg": Vector3(30.0 * s * amount, 0, 0),
		&"l_lower_leg": Vector3(maxf(0.0, c) * 30.0 * amount, 0, 0), &"r_lower_leg": Vector3(maxf(0.0, -c) * 30.0 * amount, 0, 0),
		&"l_upper_arm": Vector3(-20.0 * c * amount, 0, 0), &"r_upper_arm": Vector3(20.0 * c * amount, 0, 0),
		&"spine": Vector3(12.0 * amount, 0, 4.0 * s * amount), &"chest": Vector3(8.0 * amount, 0, 0),
		&"head": Vector3(-10.0 * amount, 0, 0), &"tail": Vector3(0, 15.0 * s * amount, 0),
		&"root": Vector3(0, absf(s) * 0.025 * amount, 0),
	}


## It never stops twitching: nose, ears, jaw chattering.
func idle_pose(t: float) -> Dictionary:
	var twitch := sin(t * 23.0) * maxf(0.0, sin(t * 1.3))
	return {&"head": Vector3(2.0 * twitch, 3.0 * sin(t * 0.9), 0), &"jaw": Vector3(6.0 + 6.0 * absf(sin(t * 11.0)), 0, 0),
		&"l_ear": Vector3(0, 0, 8.0 * twitch), &"r_ear": Vector3(0, 0, -8.0 * twitch), &"chest": Vector3(3.0 * sin(t * 2.4), 0, 0)}


func eye_color(angry: bool) -> Color:
	return Color(1.0, 0.0, 0.0) if angry else Color(0.95, 0.08, 0.04)


func enrage_line() -> String:
	return "Frothing mad: it can tunnel under the bedding now. Keep moving."


func attack_name(what: StringName) -> String:
	return {&"charge": "Frenzied Charge", &"bite": "Rabid Bite", &"foam": "Rabid Foam", &"burrow": "Ambush",
		&"screech": "Screech", &"landing": "Landing"}.get(what, super(what))


func _physics_process(delta: float) -> void:
	super(delta)
	if not alive:
		return
	_foam_t -= delta
	if _foam_t <= 0.0 and state != State.WAITING and visible:
		_foam_t = 0.35
		FX.burst(mouth_position(), Vector3.DOWN, {"amount": 5, "lifetime": 1.4, "speed": Vector2(0.5, 2.5), "spread": 40.0,
			"gravity": 9.0, "size": 0.7, "scale": Vector2(0.5, 1.4), "color": Color(0.95, 0.97, 0.9, 0.9), "fade": true, "aabb": 30.0})
	_tend_puddles(delta)


## Foam burns whoever's standing in it (a bit every half second), and slows them down.
func _tend_puddles(delta: float) -> void:
	_puddles = _puddles.filter(func(p): return float(p[2]) > _clock)
	_burn_t += delta
	var burn := _burn_t >= 0.5
	if burn:
		_burn_t = 0.0
	var now_in := {}
	for p in _puddles:
		for c in foes_near(p[0], p[1]):
			if c.is_on_floor() and not now_in.has(c):
				now_in[c] = true
				c.slow_factor = 0.5
				if burn:
					hurt(c, FOAM_DPS * 0.5, Vector3.UP, 0.0, 0.0, &"foam", DamageInfo.Kind.BLEED, 0.0)
	for c in _slowed.keys():
		if not now_in.has(c) and is_instance_valid(c):
			(c as Critter).slow_factor = 1.0
	_slowed = now_in


# ---- choosing ----------------------------------------------------------------------------------

func _choose(t: Critter) -> BossAction:
	var d := Vector2(t.global_position.x - global_position.x, t.global_position.z - global_position.z).length()
	if d < BITE_RADIUS + 6.0 and is_ready(&"bite"):
		return _bite(t)
	if enraged and d > 40.0 and d < 220.0 and is_ready(&"burrow"):
		return _burrow(t)
	if d > 25.0 and d < 120.0 and is_ready(&"charge"):
		return _charge(t)
	if d > 18.0 and d < 90.0 and is_ready(&"spit"):
		return _spit(t)
	return null


# ---- Frenzied Charge -----------------------------------------------------------------------------

func _charge(t: Critter) -> BossAction:
	cooldown(&"charge", 7.0 if not enraged else 5.0)
	var wind := 0.9
	var dir := t.global_position - global_position
	dir.y = 0.0
	dir = dir.normalized()
	var reach := minf(global_position.distance_to(t.global_position) + 30.0, 140.0)
	var stop := _wall_ahead(global_position, dir, reach)
	var run := maxf(stop - 2.0, 10.0)
	var end := global_position + dir * run
	var a := BossAction.new(&"charge", wind + run / CHARGE_SPEED + 0.6)
	a.interruptible = false
	var low := {&"spine": Vector3(45, 0, 0), &"chest": Vector3(20, 0, 0), &"head": Vector3(10, 0, 0), &"jaw": Vector3(25, 0, 0),
		&"l_upper_arm": Vector3(-40, 0, 0), &"r_upper_arm": Vector3(-40, 0, 0), &"root": Vector3(0, -0.06, 0)}
	a.key(0.0, {}).key(wind, low).key(a.length - 0.5, low).key(a.length, {})
	var trampled := {}
	var crashed := stop < reach
	a.on(0.0, func():
		warn_strip(global_position, end, CHARGE_HIT * 2.0, wind + run / CHARGE_SPEED)
		Audio.play_at(&"boss_screech", mouth_position(), 10.0, 0.05, {"max_distance": 700.0, "unit_size": 45.0}))
	a.tick = func(time: float, delta: float):
		if time < wind:
			face_toward(global_position + dir, delta, 4.0)
			_speed = 0.0
			return
		var left := end - global_position
		left.y = 0.0
		if left.length() < 1.0:
			_speed = 0.0
			return
		var step := minf(CHARGE_SPEED * delta, left.length())
		move_by(dir * step)
		_speed = CHARGE_SPEED
		for c in foes_near(global_position, CHARGE_HIT + 6.0):
			if trampled.has(c):
				continue
			var off := c.global_position - global_position
			off.y = 0.0
			if off.dot(dir) > -4.0 and absf(off.dot(dir.cross(Vector3.UP))) < CHARGE_HIT:
				trampled[c] = true
				var side := dir.cross(Vector3.UP) * signf(off.dot(dir.cross(Vector3.UP)) + 0.01)
				hurt(c, 85.0, (side + dir).normalized(), 16.0, 10.0, &"charge")
	a.on(wind + run / CHARGE_SPEED, func():
		_speed = 0.0
		if crashed:
			_crash())
	return a


## How far it can run along `dir` before something big stops it (the glass,
## the water bowls, Tube Town...), up to `reach`.
func _wall_ahead(from: Vector3, dir: Vector3, reach: float) -> float:
	if not is_inside_tree():
		return reach
	var space := get_world_3d().direct_space_state
	var best := reach
	for h: float in [4.0, 9.0]:
		var o := from + Vector3.UP * h
		var q := PhysicsRayQueryParameters3D.create(o, o + dir * reach, Layers.WORLD)
		var hit := space.intersect_ray(q)
		if hit:
			best = minf(best, o.distance_to(hit.position))
	return best


## Head first into a wall: stunned, stars and all.
func _crash() -> void:
	var at := global_position + forward() * 8.0 + Vector3.UP * 6.0
	BossFX.chips(at, 2.0, Color(0.85, 0.8, 0.7))
	BossFX.dust(global_position, 18.0)
	Events.explosion.emit(at, 14.0)
	Audio.play_at(&"body_fall", at, 10.0, 0.0, {"max_distance": 500.0, "unit_size": 40.0})
	Audio.play_at(&"boss_stomp", at, 6.0, 0.0, {"max_distance": 500.0, "unit_size": 40.0})
	stun(2.6, {&"spine": Vector3(-10, 0, 12), &"head": Vector3(-25, 0, 20), &"jaw": Vector3(30, 0, 0),
		&"l_upper_arm": Vector3(-30, 0, 30), &"r_upper_arm": Vector3(-30, 0, -30), &"root": Vector3(0, -0.02, 0.02)}, 1.6)
	Events.announce.emit("NIBBLES IS DAZED!", "It ran into a wall. Hit it now!")


# ---- Rabid Bite ----------------------------------------------------------------------------------

func _bite(t: Critter) -> BossAction:
	cooldown(&"bite", 4.5 if not enraged else 3.0)
	var lunge := 0.55
	var a := BossAction.new(&"bite", lunge + 0.95)
	var centre := global_position + forward() * 9.0
	centre.y = ground_y(centre)
	a.key(0.0, {}).key(lunge * 0.8, {&"spine": Vector3(-15, 0, 0), &"head": Vector3(-25, 0, 0), &"jaw": Vector3(40, 0, 0),
		&"l_upper_arm": Vector3(-60, 0, 20), &"r_upper_arm": Vector3(-60, 0, -20)})
	a.key(lunge, {&"spine": Vector3(50, 0, 0), &"chest": Vector3(15, 0, 0), &"head": Vector3(15, 0, 0), &"jaw": Vector3(0, 0, 0),
		&"root": Vector3(0, -0.05, 0.08)})
	a.key(lunge + 0.4, {&"spine": Vector3(40, 0, 0), &"root": Vector3(0, -0.04, 0.06)}).key(a.length, {})
	a.on(0.0, func(): warn(centre, BITE_RADIUS, lunge))
	a.tick = func(time: float, delta: float):
		if time < lunge and is_instance_valid(t) and t.alive:
			face_toward(t.global_position, delta, 3.5)
	a.on(lunge, func():
		for c in foes_near(centre, BITE_RADIUS):
			hurt(c, 80.0, forward(), 10.0, 6.0, &"bite", DamageInfo.Kind.MELEE, 0.9)
		Audio.play_at(&"melee_hit", mouth_position(), 10.0, 0.05, {"max_distance": 300.0, "unit_size": 25.0}))
	return a


# ---- Foam Spit -----------------------------------------------------------------------------------

func _spit(t: Critter) -> BossAction:
	cooldown(&"spit", 8.0)
	var a := BossAction.new(&"spit", 1.9)
	a.key(0.0, {}).key(0.6, {&"head": Vector3(-35, 0, 0), &"spine": Vector3(-15, 0, 0), &"jaw": Vector3(10, 0, 0)})
	a.key(0.85, {&"head": Vector3(20, 0, 0), &"spine": Vector3(25, 0, 0), &"jaw": Vector3(40, 0, 0)}).key(1.9, {})
	a.tick = func(time: float, delta: float):
		if time < 0.8 and is_instance_valid(t) and t.alive:
			face_toward(t.global_position, delta, 2.5)
	a.on(0.85, func():
		for i in (5 if enraged else 3):
			var at := t.global_position if is_instance_valid(t) else global_position + forward() * 40.0
			at += Vector3(randf_range(-1, 1), 0.0, randf_range(-1, 1)).normalized() * (0.0 if i == 0 else randf_range(8.0, 16.0))
			_glob(at))
	return a


func _glob(at: Vector3) -> void:
	at.y = ground_y(at)
	var from := mouth_position()
	var flight := 1.2
	warn(at, FOAM_RADIUS, flight)
	var g := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.4
	sm.height = 2.8
	g.mesh = sm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.88, 0.95, 0.75)
	m.roughness = 0.2
	g.material_override = m
	get_parent().add_child(g)
	g.global_position = from
	var fly := func(u: float):
		if is_instance_valid(g):
			g.global_position = from.lerp(at, u) + Vector3.UP * sin(u * PI) * 18.0
	var tw := g.create_tween()
	tw.tween_method(fly, 0.0, 1.0, flight)
	tw.tween_callback(func():
		_puddles.append([at, FOAM_RADIUS, _clock + FOAM_SECONDS])
		BossFX.foam(at, FOAM_RADIUS, FOAM_SECONDS)
		FX.burst(at, Vector3.UP, {"amount": 20, "lifetime": 0.8, "speed": Vector2(3.0, 8.0), "spread": 70.0, "gravity": 12.0,
			"size": 0.8, "scale": Vector2(0.5, 1.4), "color": Color(0.9, 0.97, 0.8), "fade": true, "aabb": 20.0})
		Audio.play_at(&"gore_splat", at, 2.0, 0.1, {"max_distance": 200.0})
		g.queue_free())


# ---- Burrow --------------------------------------------------------------------------------------

func _burrow(t: Critter) -> BossAction:
	cooldown(&"burrow", 16.0)
	var dive := 1.0
	var travel := clampf(global_position.distance_to(t.global_position) / 26.0, 1.2, 7.0)
	var rise := 0.9
	var a := BossAction.new(&"burrow", dive + travel + rise + 1.4)
	a.interruptible = false
	var under := {&"spine": Vector3(60, 0, 0), &"head": Vector3(30, 0, 0), &"root": Vector3(0, -1.1, 0.1)}
	var up := {&"spine": Vector3(-20, 0, 0), &"head": Vector3(-30, 0, 0), &"jaw": Vector3(40, 0, 0),
		&"l_upper_arm": Vector3(-120, 0, 30), &"r_upper_arm": Vector3(-120, 0, -30), &"root": Vector3(0, 0.05, 0)}
	a.key(0.0, {}).key(dive, under).key(dive + travel + rise * 0.5, under).key(dive + travel + rise, up).key(a.length, {})
	var state_ := {"at": t.global_position, "warned": false, "trail": 0.0}
	a.on(dive, func(): _set_hittable(false))
	a.tick = func(time: float, delta: float):
		if time < dive:
			if randf() < 0.2:
				BossFX.dust(global_position, 8.0)
			return
		if time < dive + travel:
			if is_instance_valid(t) and t.alive:
				state_["at"] = t.global_position   # (it tracks you down there)
			var to: Vector3 = state_["at"] - global_position
			to.y = 0.0
			if to.length() > 1.0:
				face_toward(state_["at"], delta, 4.0)
				move_by(to.normalized() * minf(26.0 * delta, to.length()))
			state_["trail"] = float(state_["trail"]) - delta
			if float(state_["trail"]) <= 0.0:
				state_["trail"] = 0.15
				BossFX.dust(global_position, 6.0, Color(0.85, 0.8, 0.68, 0.7))
			return
		if not state_["warned"]:
			state_["warned"] = true
			warn(global_position, BURROW_RADIUS, rise)
	a.on(dive + travel + rise, func():
		_set_hittable(true)
		hurt_ring(global_position, BURROW_RADIUS, 90.0, 25.0, 14.0, 14.0, &"burrow")
		BossFX.shockwave(global_position, BURROW_RADIUS)
		BossFX.chips(global_position, 2.5, Color(0.88, 0.82, 0.68))
		Events.explosion.emit(global_position, BURROW_RADIUS))
	a.data["cancel"] = func(): _set_hittable(true)
	return a


## The screech (enraged): everyone near is blown back.
func _roar_action() -> BossAction:
	var a := BossAction.new(&"screech", 2.0)
	var pose := {&"spine": Vector3(-25, 0, 0), &"head": Vector3(-40, 0, 0), &"jaw": Vector3(45, 0, 0),
		&"l_upper_arm": Vector3(-130, 0, 35), &"r_upper_arm": Vector3(-130, 0, -35)}
	a.key(0.0, {}).key(0.45, pose).key(1.5, pose).key(2.0, {})
	a.on(0.5, func():
		hurt_ring(global_position, 36.0, 12.0, 4.0, 11.0, 6.0, &"screech", false)
		Events.explosion.emit(mouth_position(), 26.0)
		BossFX.dust(global_position, 28.0)
		Audio.play_at(&"boss_screech", mouth_position(), 14.0, 0.0, {"max_distance": 900.0, "unit_size": 60.0}))
	return a


# ---- arriving, and going down -------------------------------------------------------------------

## It bursts up out of the bedding.
func _entrance() -> BossAction:
	var a := BossAction.new(&"entrance", 3.6)
	a.interruptible = false
	var under := {&"spine": Vector3(60, 0, 0), &"head": Vector3(30, 0, 0), &"root": Vector3(0, -1.1, 0.1)}
	var up := {&"spine": Vector3(-20, 0, 0), &"head": Vector3(-35, 0, 0), &"jaw": Vector3(45, 0, 0),
		&"l_upper_arm": Vector3(-130, 0, 35), &"r_upper_arm": Vector3(-130, 0, -35), &"root": Vector3(0, 0.05, 0)}
	a.key(0.0, under).key(1.6, under).key(2.2, up).key(3.0, up).key(3.6, {})
	a.on(0.0, func(): warn(global_position, 26.0, 2.2))
	a.tick = func(time: float, _delta: float):
		if time < 2.0 and randf() < 0.3:
			BossFX.dust(global_position + Vector3(randf_range(-8, 8), 0, randf_range(-8, 8)), 10.0, Color(0.85, 0.8, 0.68, 0.7))
	a.on(2.2, func():
		hurt_ring(global_position, 26.0, 55.0, 10.0, 15.0, 12.0, &"landing")
		BossFX.shockwave(global_position, 26.0)
		BossFX.chips(global_position, 3.0, Color(0.88, 0.82, 0.68))
		Events.explosion.emit(global_position, 20.0)
		Audio.play_at(&"boss_screech", mouth_position(), 14.0, 0.0, {"max_distance": 900.0, "unit_size": 60.0})
		Audio.play_at(&"boss_stomp", global_position, 4.0, 0.0, {"max_distance": 700.0, "unit_size": 40.0}))
	return a


## It keels over onto its side, legs in the air.
func _death_action() -> BossAction:
	for c in _slowed.keys():
		if is_instance_valid(c):
			(c as Critter).slow_factor = 1.0
	_slowed.clear()
	var a := BossAction.new(&"death", 2.6)
	a.blend_out = 0.0
	a.interruptible = false
	var down := {&"hips": Vector3(0, 0, -80), &"spine": Vector3(10, 0, 0), &"head": Vector3(10, 0, -15), &"jaw": Vector3(35, 0, 0),
		&"l_upper_leg": Vector3(-50, 0, 0), &"r_upper_leg": Vector3(-30, 0, 0), &"l_upper_arm": Vector3(-60, 0, 20),
		&"r_upper_arm": Vector3(-70, 0, -20), &"tail": Vector3(0, 0, 20), &"root": Vector3(0.0, -0.1, 0)}
	a.key(0.0, {}).key(0.8, {&"spine": Vector3(-20, 0, 0), &"head": Vector3(-40, 0, 0), &"jaw": Vector3(45, 0, 0)})
	a.key(1.9, down).key(2.6, down)
	a.on(1.9, func():
		BossFX.shockwave(global_position, HEIGHT)
		Events.explosion.emit(global_position, 20.0)
		Audio.play_at(&"body_fall", global_position, 12.0, 0.0, {"max_distance": 600.0, "unit_size": 50.0}))
	return a


func _fallen() -> void:
	if gore_ok:
		FX.gore_burst(mouth_position(), 2.5, Color(0.85, 0.6, 0.3))
