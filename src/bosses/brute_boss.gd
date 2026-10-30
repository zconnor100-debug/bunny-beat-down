class_name BruteBoss
extends Boss
## Brutus, the island's boss: a bunny the size of a house, all muscle and
## teeth (the Thumpergeist model, re-rigged: assets/bosses/brute/).
##   Ground Pound: both fists down on whoever's close; a ring of dust and
##     broken critters. Jump as it lands and it misses you.
##   Boulder Toss: rips a rock out of the ground and lobs it at you.
##   Leap: far off? It jumps the whole way and lands on you.
##   Grab: in reach of its paw, it picks you up and bites. Bots don't come back.
##   Roar: enraged (or crowded), it roars everyone back off it.

const POUND_RADIUS := 25.0
const BOULDER_RADIUS := 11.0
const LEAP_RADIUS := 24.0
const BOULDER_MODEL := "res://assets/env/boulder_big/boulder_big.glb"
const BOULDER_SIZE := 6.0           ## metres across

var _held: Critter                  # (in its paw: Grab)
var _boulder: Node3D                # (in its paw, or flying)
var _roared_at := -100.0


func _init() -> void:
	super()
	id = "brute"
	display_name = "Brutus"
	title = "the Meadow's Nightmare"
	land_time = 2.4
	base_health = 36000.0
	walk_speed = 10.0
	turn_speed = 1.5
	weak_spots = {&"head": 2.0, &"jaw": 2.5}
	limb_scale = 0.7


func stride() -> float:
	return 0.2


## A hulking knuckle-dragger's walk: a lurch from side to side, heavy arms.
func walk_pose(phase: float, amount: float) -> Dictionary:
	var p := super(phase, amount)
	var s := sin(phase)
	p[&"hips"] = Vector3(0, 0, 6.0 * s * amount)
	p[&"chest"] = (p.get(&"chest", Vector3.ZERO) as Vector3) + Vector3(6.0 * amount, 0, -5.0 * s * amount)
	return p


func idle_pose(t: float) -> Dictionary:
	var b := sin(t * 1.3)
	return {&"chest": Vector3(3.0 * b, 0, 0), &"head": Vector3(-2.0 * b, 0, 0), &"jaw": Vector3(4.0 + 4.0 * maxf(b, 0.0), 0, 0),
		&"l_ear": Vector3(0, 0, 3.0 * sin(t * 2.3)), &"r_ear": Vector3(0, 0, -3.0 * sin(t * 2.1 + 1.0))}


func enrage_line() -> String:
	return "It's faster, it hits harder, and it isn't stopping. Aim for the head."


func attack_name(what: StringName) -> String:
	return {&"pound": "Ground Pound", &"boulder": "Boulder", &"leap": "Belly Flop", &"gobble": "Teeth",
		&"roar": "Roar", &"landing": "Landing"}.get(what, super(what))


# ---- choosing ----------------------------------------------------------------------------------

func _choose(t: Critter) -> BossAction:
	var d := Vector2(t.global_position.x - global_position.x, t.global_position.z - global_position.z).length()
	var crowd := foes_near(global_position, 30.0).size()
	if is_ready(&"roar") and crowd >= 5 and _clock - _roared_at > 25.0:
		return _roar_action()
	if d < 13.0 and is_ready(&"gobble") and t.is_on_floor():
		return _gobble(t)
	if (d < POUND_RADIUS + 4.0 or foes_near(global_position + forward() * 7.0, POUND_RADIUS).size() >= 2) and is_ready(&"pound"):
		return _pound()
	if d > 32.0 and d < 170.0 and is_ready(&"leap"):
		return _leap(t)
	if d > 22.0 and d < 140.0 and is_ready(&"boulder"):
		return _toss(t)
	return null


# ---- Ground Pound ----------------------------------------------------------------------------

func _pound() -> BossAction:
	cooldown(&"pound", 6.0)
	var r := POUND_RADIUS * (1.2 if enraged else 1.0)
	var hit_at := 1.05 if not enraged else 0.85
	var a := BossAction.new(&"pound", hit_at + 1.25)
	var centre := global_position + forward() * 7.0
	centre.y = ground_y(centre)
	a.key(0.0, {})
	a.key(hit_at * 0.75, {&"l_upper_arm": Vector3(-150, 0, 20), &"r_upper_arm": Vector3(-150, 0, -20),
		&"l_lower_arm": Vector3(-30, 0, 0), &"r_lower_arm": Vector3(-30, 0, 0), &"spine": Vector3(-18, 0, 0),
		&"chest": Vector3(-10, 0, 0), &"head": Vector3(-15, 0, 0), &"jaw": Vector3(25, 0, 0), &"root": Vector3(0, 0.03, 0)})
	a.key(hit_at, {&"l_upper_arm": Vector3(-35, 0, 10), &"r_upper_arm": Vector3(-35, 0, -10), &"spine": Vector3(38, 0, 0),
		&"chest": Vector3(15, 0, 0), &"head": Vector3(10, 0, 0), &"jaw": Vector3(30, 0, 0),
		&"l_upper_leg": Vector3(-25, 0, 0), &"r_upper_leg": Vector3(-25, 0, 0), &"l_lower_leg": Vector3(35, 0, 0), &"r_lower_leg": Vector3(35, 0, 0),
		&"root": Vector3(0, -0.06, 0)})
	a.key(hit_at + 0.5, {&"l_upper_arm": Vector3(-35, 0, 10), &"r_upper_arm": Vector3(-35, 0, -10), &"spine": Vector3(32, 0, 0),
		&"root": Vector3(0, -0.05, 0)})
	a.key(hit_at + 1.25, {})
	a.on(0.0, func(): warn(centre, r, hit_at))
	a.on(hit_at, func():
		hurt_ring(centre, r, 65.0, 20.0, 14.0, 9.0, &"pound")
		_quake(centre, r))
	return a


## The ground shakes where a blow lands: dust, a shockwave, the camera.
func _quake(at: Vector3, r: float) -> void:
	BossFX.shockwave(at, r)
	Events.explosion.emit(at, r * 0.6)   # (the camera shakes: CameraRig)
	Audio.play_at(&"boss_stomp", at, 8.0, 0.05, {"max_distance": 600.0, "unit_size": 40.0})


# ---- Boulder Toss ----------------------------------------------------------------------------

func _toss(t: Critter) -> BossAction:
	cooldown(&"boulder", 6.5)
	var a := BossAction.new(&"boulder", 2.7)
	a.key(0.0, {})
	a.key(0.6, {&"spine": Vector3(45, 0, 0), &"r_upper_arm": Vector3(-55, 0, 0), &"r_lower_arm": Vector3(-20, 0, 0),
		&"l_upper_leg": Vector3(-30, 0, 0), &"r_upper_leg": Vector3(-30, 0, 0), &"l_lower_leg": Vector3(45, 0, 0), &"r_lower_leg": Vector3(45, 0, 0),
		&"root": Vector3(0, -0.06, 0)})
	a.key(1.35, {&"spine": Vector3(-20, -15, 0), &"chest": Vector3(-10, -15, 0), &"r_upper_arm": Vector3(-170, 0, -10),
		&"r_lower_arm": Vector3(-50, 0, 0), &"l_upper_arm": Vector3(-40, 0, 25), &"jaw": Vector3(20, 0, 0)})
	a.key(1.6, {&"spine": Vector3(30, 20, 0), &"chest": Vector3(15, 15, 0), &"r_upper_arm": Vector3(-60, 0, 0),
		&"r_lower_arm": Vector3(-10, 0, 0), &"l_upper_arm": Vector3(10, 0, 20), &"jaw": Vector3(30, 0, 0)})
	a.key(2.7, {})
	a.tick = func(_t: float, delta: float):
		if is_instance_valid(t) and t.alive:
			face_toward(t.global_position, delta, 2.5)
		if _boulder and is_instance_valid(_boulder) and _boulder.has_meta(&"held"):
			_boulder.global_position = bone_point(&"r_hand", 0.8)
	a.on(0.6, func():
		_boulder = ModelUtil.instantiate(BOULDER_MODEL)
		if _boulder == null:
			_boulder = MeshInstance3D.new()
			(_boulder as MeshInstance3D).mesh = SphereMesh.new()
		get_parent().add_child(_boulder)
		var box := ModelUtil.aabb_of(_boulder)
		_boulder.scale = Vector3.ONE * BOULDER_SIZE / maxf(box.get_longest_axis_size(), 0.1)
		_boulder.set_meta(&"held", true)
		_boulder.global_position = bone_point(&"r_hand", 0.8)
		BossFX.chips(_boulder.global_position, 1.5, Color(0.45, 0.4, 0.33)))
	a.on(1.6, func():
		_throw_boulder(t)
		if enraged:   # (and a fistful of rubble after it, at whoever else is about)
			var others := foes().filter(func(c): return c != t and c.global_position.distance_to(global_position) < 140.0)
			for i in mini(2, others.size()):
				_lob_rock(bone_point(&"r_hand", 0.8) + Vector3.UP * 2.0, others[randi() % others.size()], 3.5, 7.0))
	a.data["cancel"] = func():
		if _boulder and is_instance_valid(_boulder) and _boulder.has_meta(&"held"):
			_boulder.queue_free()
		_boulder = null
	return a


func _throw_boulder(t: Critter) -> void:
	if _boulder == null or not is_instance_valid(_boulder):
		return
	var rock := _boulder
	_boulder = null
	rock.remove_meta(&"held")
	var from := rock.global_position
	var flight := 1.5
	var at := global_position + forward() * 60.0
	if is_instance_valid(t) and t.alive:
		at = t.global_position + Vector3(t.velocity.x, 0.0, t.velocity.z) * flight * 0.7   # (where they'll be)
	at.y = ground_y(at)
	warn(at, BOULDER_RADIUS, flight)
	var spin := Vector3(randf_range(-4, 4), randf_range(-4, 4), randf_range(-4, 4))
	var fly := func(u: float):
		if is_instance_valid(rock):
			rock.global_position = from.lerp(at, u) + Vector3.UP * sin(u * PI) * 30.0
			rock.rotation = spin * u * flight
	var tw := rock.create_tween()
	tw.tween_method(fly, 0.0, 1.0, flight)
	tw.tween_callback(func():
		if not is_instance_valid(rock):
			return
		hurt_ring(at, BOULDER_RADIUS, 80.0, 30.0, 12.0, 7.0, &"boulder", false)
		BossFX.shockwave(at, BOULDER_RADIUS * 1.4)
		BossFX.chips(at, 2.0, Color(0.42, 0.38, 0.32))
		Events.explosion.emit(at, BOULDER_RADIUS)
		var p := Audio.play_at(&"boss_stomp", at, 4.0, 0.05, {"max_distance": 400.0, "unit_size": 25.0})
		if p:
			p.pitch_scale = 1.3)
	tw.tween_interval(10.0)
	tw.tween_property(rock, "position:y", at.y - 8.0, 2.0)
	tw.tween_callback(rock.queue_free)


## A smaller rock (`size` metres) lobbed from `from` at `t`, landing on its
## own red ring (`radius`).
func _lob_rock(from: Vector3, t: Critter, size: float, radius: float) -> void:
	var rock := ModelUtil.instantiate(BOULDER_MODEL)
	if rock == null:
		return
	get_parent().add_child(rock)
	rock.scale = Vector3.ONE * size / maxf(ModelUtil.aabb_of(rock).get_longest_axis_size() / maxf(rock.scale.x, 0.001), 0.1)
	rock.global_position = from
	var flight := randf_range(1.3, 1.8)
	var at := t.global_position + Vector3(t.velocity.x, 0.0, t.velocity.z) * flight * 0.6
	at.y = ground_y(at)
	warn(at, radius, flight)
	var spin := Vector3(randf_range(-5, 5), randf_range(-5, 5), randf_range(-5, 5))
	var fly := func(u: float):
		if is_instance_valid(rock):
			rock.global_position = from.lerp(at, u) + Vector3.UP * sin(u * PI) * 24.0
			rock.rotation = spin * u * flight
	var tw := rock.create_tween()
	tw.tween_method(fly, 0.0, 1.0, flight)
	tw.tween_callback(func():
		hurt_ring(at, radius, 60.0, 20.0, 10.0, 6.0, &"boulder", false)
		BossFX.chips(at, 1.3, Color(0.42, 0.38, 0.32))
		BossFX.dust(at, radius)
		Audio.play_at(&"boss_stomp", at, 0.0, 0.1, {"max_distance": 300.0, "unit_size": 20.0}))
	tw.tween_interval(6.0)
	tw.tween_callback(rock.queue_free)


# ---- Leap --------------------------------------------------------------------------------------

func _leap(t: Critter) -> BossAction:
	cooldown(&"leap", 11.0)
	var air := 1.7
	var crouch := 0.7
	var a := BossAction.new(&"leap", crouch + air + 1.0)
	a.interruptible = false
	var from := global_position
	var at := t.global_position + Vector3(t.velocity.x, 0.0, t.velocity.z) * 0.6
	at.y = ground_y(at)
	var r := LEAP_RADIUS * (1.2 if enraged else 1.0)
	a.key(0.0, {})
	a.key(crouch, {&"spine": Vector3(35, 0, 0), &"l_upper_leg": Vector3(-50, 0, 0), &"r_upper_leg": Vector3(-50, 0, 0),
		&"l_lower_leg": Vector3(80, 0, 0), &"r_lower_leg": Vector3(80, 0, 0), &"l_upper_arm": Vector3(40, 0, 10),
		&"r_upper_arm": Vector3(40, 0, -10), &"root": Vector3(0, -0.1, 0)})
	a.key(crouch + 0.25, {&"spine": Vector3(-15, 0, 0), &"l_upper_arm": Vector3(-150, 0, 30), &"r_upper_arm": Vector3(-150, 0, -30),
		&"l_upper_leg": Vector3(20, 0, 0), &"r_upper_leg": Vector3(20, 0, 0), &"jaw": Vector3(30, 0, 0)})
	a.key(crouch + air - 0.2, {&"spine": Vector3(10, 0, 0), &"l_upper_arm": Vector3(-120, 0, 30), &"r_upper_arm": Vector3(-120, 0, -30),
		&"l_upper_leg": Vector3(-40, 0, 0), &"r_upper_leg": Vector3(-40, 0, 0), &"l_lower_leg": Vector3(40, 0, 0), &"r_lower_leg": Vector3(40, 0, 0)})
	a.key(crouch + air, {&"spine": Vector3(40, 0, 0), &"l_upper_arm": Vector3(-30, 0, 20), &"r_upper_arm": Vector3(-30, 0, -20),
		&"l_upper_leg": Vector3(-55, 0, 0), &"r_upper_leg": Vector3(-55, 0, 0), &"l_lower_leg": Vector3(85, 0, 0), &"r_lower_leg": Vector3(85, 0, 0),
		&"root": Vector3(0, -0.12, 0)})
	a.key(crouch + air + 1.0, {})
	a.on(0.0, func(): warn(at, r, crouch + air))
	a.tick = func(time: float, delta: float):
		if time < crouch:
			face_toward(at, delta, 3.0)
			_speed = 0.0
			return
		var u := clampf((time - crouch) / air, 0.0, 1.0)
		var p := from.lerp(at, u)
		p.y = lerpf(from.y, at.y, u) + sin(u * PI) * 45.0
		global_position = p
	a.on(crouch + air, func():
		global_position = at
		hurt_ring(at, r, 95.0, 30.0, 16.0, 10.0, &"leap")
		_quake(at, r))
	return a


# ---- Grab ----------------------------------------------------------------------------------------

func _gobble(t: Critter) -> BossAction:
	cooldown(&"gobble", 10.0)
	var a := BossAction.new(&"gobble", 3.6)
	var reach := 0.6
	a.key(0.0, {})
	a.key(reach, {&"spine": Vector3(40, 0, 0), &"r_upper_arm": Vector3(-75, 0, -10), &"r_lower_arm": Vector3(-15, 0, 0),
		&"head": Vector3(10, 0, 0), &"jaw": Vector3(20, 0, 0), &"root": Vector3(0, -0.04, 0)})
	a.key(1.5, {&"spine": Vector3(5, 0, 0), &"r_upper_arm": Vector3(-125, 25, -35), &"r_lower_arm": Vector3(-95, 0, 0),
		&"head": Vector3(15, 0, 0), &"jaw": Vector3(35, 0, 0)})
	a.key(1.8, {&"spine": Vector3(10, 0, 0), &"r_upper_arm": Vector3(-125, 25, -35), &"r_lower_arm": Vector3(-95, 0, 0),
		&"head": Vector3(25, 0, 0), &"jaw": Vector3(0, 0, 0)})
	a.key(2.4, {&"spine": Vector3(25, 0, 0), &"r_upper_arm": Vector3(-150, 0, -10), &"r_lower_arm": Vector3(-20, 0, 0), &"jaw": Vector3(15, 0, 0)})
	a.key(2.7, {&"spine": Vector3(30, 0, 0), &"r_upper_arm": Vector3(-30, 0, 0), &"r_lower_arm": Vector3(0, 0, 0)})
	a.key(3.6, {})
	var spot := t.global_position
	a.on(0.0, func(): warn(spot, 7.0, reach))
	a.tick = func(time: float, delta: float):
		if time < reach and is_instance_valid(t) and t.alive:
			face_toward(t.global_position, delta, 3.0)
		if _held and is_instance_valid(_held) and _held.alive:
			_held.global_position = bone_point(&"r_hand", 0.9) - Vector3.UP * _held.chest_height()
			_held.velocity = Vector3.ZERO
			_held.visual.physics_tick(_held.global_transform, true)
	a.on(reach, func():
		var hand := bone_point(&"r_hand", 0.8)
		var grabbed: Critter = null
		for c in foes_near(hand, 9.0):
			if c.is_on_floor() and (grabbed == null or c.global_position.distance_to(hand) < grabbed.global_position.distance_to(hand)):
				grabbed = c
		if grabbed:
			_held = grabbed
			_held.held_by = self
		else:
			hurt_ring(spot, 7.0, 40.0, 25.0, 10.0, 5.0, &"gobble"))
	a.on(1.8, func(): _bite())
	a.on(2.6, func(): _fling())
	a.data["cancel"] = func(): _fling()
	return a


## Chomp: a bot loses its head; you lose a chunk (and live, this time).
func _bite() -> void:
	if _held == null or not is_instance_valid(_held) or not _held.alive:
		return
	var c := _held
	var mouth := mouth_position()
	if c.is_player:
		hurt(c, 45.0, forward(), 0.0, 0.0, &"gobble", DamageInfo.Kind.MELEE, 0.0)
	else:
		var info := DamageInfo.make(500.0, DamageInfo.Kind.MELEE, self, &"gobble")
		info.position = mouth
		info.direction = Vector3.UP
		info.bone_role = &"head"
		info.headshot = true
		info.impulse = 6.0
		info.dismember_power = 1.0 if gore_ok else 0.0
		c.held_by = null
		c.take_damage(info)
		if not c.alive:
			kills += 1
		if gore_ok:
			FX.gore_burst(mouth, 1.6, c.def.fur_color if c.def else Color.WHITE)
	Audio.play_at(&"gore_splat", mouth, 6.0, 0.05, {"max_distance": 200.0, "unit_size": 20.0})


## Let go: whoever's in its paw is flung away.
func _fling() -> void:
	if _held == null:
		return
	var c := _held
	_held = null
	if not is_instance_valid(c):
		return
	c.held_by = null
	var away := forward().rotated(Vector3.UP, randf_range(-0.6, 0.6)) * 18.0 + Vector3.UP * 12.0
	if c.alive:
		c.velocity = away
	else:
		c.visual.push_bone(&"chest", away * 8.0, c.get_chest_position())


# ---- Roar ----------------------------------------------------------------------------------------

func _roar_action() -> BossAction:
	_roared_at = _clock
	cooldown(&"roar", 25.0)
	var a := BossAction.new(&"roar", 2.4)
	var open := {&"spine": Vector3(-20, 0, 0), &"chest": Vector3(-10, 0, 0), &"head": Vector3(-30, 0, 0), &"jaw": Vector3(40, 0, 0),
		&"l_upper_arm": Vector3(-20, 0, 70), &"r_upper_arm": Vector3(-20, 0, -70), &"l_lower_arm": Vector3(-40, 0, 0),
		&"r_lower_arm": Vector3(-40, 0, 0), &"l_ear": Vector3(-30, 0, 15), &"r_ear": Vector3(-30, 0, -15)}
	a.key(0.0, {}).key(0.5, open).key(1.9, open).key(2.4, {})
	a.on(0.55, func():
		var at := global_position
		hurt_ring(at, 40.0, 12.0, 4.0, 10.0, 5.0, &"roar", false)
		Events.explosion.emit(mouth_position(), 30.0)
		BossFX.dust(at, 30.0)
		Audio.play_at(&"boss_roar", mouth_position(), 12.0, 0.03, {"max_distance": 900.0, "unit_size": 60.0}))
	return a


# ---- arriving, and going down -------------------------------------------------------------------

## It drops out of the sky and lands in a crouch.
func _entrance() -> BossAction:
	var at := global_position
	var drop := land_time
	var a := BossAction.new(&"entrance", drop + 2.6)
	a.interruptible = false
	var landed := {&"spine": Vector3(40, 0, 0), &"l_upper_leg": Vector3(-55, 0, 0), &"r_upper_leg": Vector3(-55, 0, 0),
		&"l_lower_leg": Vector3(85, 0, 0), &"r_lower_leg": Vector3(85, 0, 0), &"l_upper_arm": Vector3(-30, 0, 20),
		&"r_upper_arm": Vector3(-30, 0, -20), &"root": Vector3(0, -0.12, 0)}
	a.key(0.0, {&"l_upper_arm": Vector3(-160, 0, 30), &"r_upper_arm": Vector3(-160, 0, -30), &"spine": Vector3(-10, 0, 0)})
	a.key(drop, landed).key(drop + 0.8, landed).key(drop + 2.6, {})
	a.on(0.0, func(): warn(at, 30.0, drop))
	a.tick = func(time: float, _delta: float):
		if time < drop:
			var u := time / drop
			global_position = at + Vector3.UP * 220.0 * (1.0 - u * u)
	a.on(drop, func():
		global_position = at
		hurt_ring(at, 30.0, 60.0, 10.0, 15.0, 10.0, &"landing")
		_quake(at, 30.0))
	return a


func _after_entrance() -> void:
	if foes_near(global_position, 60.0).size() >= 2:
		start(_roar_action())


func _fallen() -> void:
	if gore_ok:
		FX.gore_burst(get_chest_position(), 3.0, Color(0.9, 0.88, 0.85))
	BossFX.dust(global_position, 30.0)
