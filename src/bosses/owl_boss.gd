class_name OwlBoss
extends Boss
## Old Hoot, the island's boss by night (a Boss Battle's other choice there,
## Settings "boss"): a snowy owl with a wingspan as long as the Big Red Barn
## and a sliver of the Starfall Acorn in her left eye, glowing gold-green (the
## Gliding Snowy Owl model, rigged: assets/bosses/owl/, her wings on its arms'
## bones). The first boss that flies: she circles the fight up high and comes
## down out of the dark for it.
##   Snatch: a red ring on whoever she's after, then she drops out of the sky
##     onto it, carries off whoever's still in it and lets go from high up.
##     Caught, jump and keep jumping to wriggle free; hit her enough and she
##     lets go.
##   Talon Rake: a low pass along a red strip, talons out.
##   Feather Volley: hovering, a flurry of feathers onto red rings.
##   Hoot: she puffs up and hoots, and everyone in the ring below her is
##     knocked off their feet.
##   Perch: now and then she comes down to rest, low and still: go for the
##     eye. Shoot her wings as she dives and she comes down hard (grounded).
##
## She flies on her own (_vel, banking into her turns, her body pitched into
## a dive: the model tilts, the hitboxes with it), not along the navmesh like
## the walkers. Her pose is her flight's (wings beating or held out, talons
## tucked or reaching: _body_pose) or her perch's (wings drooped round her),
## and what she's doing adds to it. She moves like an owl: her head turning
## in quick snaps and holding still between them; perched, bobbing and
## swaying it to size you up, tilting it now and then, and shaking out her
## feathers once she's down.

const CRUISE := 30.0                ## metres over the ground she flies at (her feet)
const CRUISE_SPEED := 24.0          ## m/s
const ORBIT := 72.0                 ## metres round whoever she's after she circles at
const FLAP := 1.6                   ## wingbeats a second, cruising
const SNATCH_R := 9.0               ## her talons' reach at the bottom of a dive
const DROP_FROM := 30.0             ## how high she lets go of what she's caught
const RAKE_LEN := 80.0
const RAKE_W := 10.0
const HOOT_R := 34.0
const FEATHER_R := 5.0
const PERCH_R := 18.0               ## her wingbeats as she lands or takes off: everyone this near is blown back
const PERCH_FOR := 5.5              ## seconds she rests when she perches
const REST := 2.4                   ## seconds' cruising between two of her moves
const GROUND_AT := 7.0              ## hits on her wings in one dive that bring her down (yours count 1, a bot's 0.15)
const GROUNDED_FOR := 5.5
const LET_GO_AT := 9.0              ## hits while she's carrying someone that make her let go (yours count 1, a bot's 0.15)
const STRUGGLES := 4                ## jumps that wriggle you free of her talons
const WINGS := [&"l_upper_arm", &"l_lower_arm", &"l_hand", &"r_upper_arm", &"r_lower_arm", &"r_hand"]

var night := true                   ## (game.gd: her battle's by night)
var _air := false                   # flying (not perched, not down)
var _air_k := 0.0                   # (her posture: 0 perched … 1 flying)
var _vel := Vector3.ZERO            # (flying: her velocity)
var _cruising := false
var _orbit_a := 0.0                 # where she is round whoever she's after
var _orbit_dir := 1.0
var _flap := 0.0                    # wingbeat phase (radians)
var _flap_rate := FLAP
var _glide := 0.0                   # 1: wings held out (a glide, a dive)
var _talons := 0.0                  # 1: legs reaching forward, talons open
var _pitch := 0.0                   # (her body: nose down)
var _bank := 0.0
var _climb := 0.0
var _dive_pitch := 0.0              # (and more, into a dive)
var _dead_pitch := 0.0
var _perch_left := 0.0
var _rest_until := 0.0
var _hooted_at := -100.0
var _held: Critter                  # (in her talons: Snatch)
var _struggles := 0
var _carry_hits := 0.0
var _dropped: Array = []            # [critter, fastest it fell, seconds since]: till they land
var _diving := false
var _dive_hits := 0.0
var _landed_at := -100.0            # (her clock when she last came down: she shakes her feathers out)
var _tilt_at := -100.0              # (a tilt of her head, perched: curious)
var _tilt_next := 3.0
var _tilt_dir := 1.0
var _look_goal := Vector3.INF       # (where her head's snapped round to: held there a moment)
var _look_next := 0.0
var _fade_pose := {}                # (a move cut off: its pose, fading out instead of snapping away)
var _fade_t := 1.0


func _init() -> void:
	super()
	id = "owl"
	display_name = "Old Hoot"
	title = "the Night Watch"
	land_time = 4.0
	intro_scale = 1.25
	base_health = 32000.0
	turn_speed = 1.6
	weak_spots = {&"head": 2.2}
	limb_scale = 0.6                # (her wings are all feathers)
	solid_roles = [&"hips", &"spine", &"chest"]


func enrage_line() -> String:
	return "She's faster, and she isn't letting go. Shoot her wings as she dives."


func attack_name(what: StringName) -> String:
	return {&"talons": "Talons", &"drop": "Dropped", &"rake": "Talon Rake", &"feathers": "Feathers", &"hoot": "Hoot",
		&"gust": "Wingbeat", &"landing": "Landing"}.get(what, super(what))


## The sliver of the Acorn in her eye: gold-green, brighter when she's angry.
func eye_color(angry: bool) -> Color:
	return Color(0.92, 1.0, 0.42) if angry else Color(0.8, 1.0, 0.34)


func _physics_process(delta: float) -> void:
	if not _air and _clock >= _tilt_next:
		_tilt_next = _clock + randf_range(3.0, 6.5)
		_tilt_at = _clock
		_tilt_dir = 1.0 if randf() < 0.5 else -1.0
	super(delta)
	if state != State.WAITING:
		_tend_dropped(delta)


# ---- flying ------------------------------------------------------------------------------------------

func _fight(delta: float) -> void:
	_retarget_t -= delta
	if target == null or not is_instance_valid(target) or not target.alive or _retarget_t <= 0.0:
		_retarget_t = RETARGET_EVERY
		target = _pick_target()
	if not _air:   # (perched: looking round, then off again)
		_perch_left -= delta
		if target:
			face_toward(target.global_position, delta)
		if _perch_left <= 0.0:
			start(_take_off())
		elif target and is_ready(&"hoot") and foes_near(global_position, HOOT_R).size() >= 4:
			start(_roar_action())
		return
	if target == null:
		_cruise(global_position, delta)
		return
	var next := _choose(target) if _clock >= _rest_until else null
	if next:
		_cruising = false
		start(next)
		return
	_cruise(target.global_position, delta)


## A crowd under her: a hoot. Otherwise any of her moves that's ready, at
## random (a snatch likelier, a perch once she's been at it a while).
func _choose(t: Critter) -> BossAction:
	if is_ready(&"hoot") and foes_near(_ground_below(), HOOT_R).size() >= 4 and _clock - _hooted_at > 20.0:
		return _roar_action()
	var options := []   # [weight, move]
	if is_ready(&"snatch") and t.state == Critter.State.GROUND and not t.swimming and t.held_by == null:
		options.append([3.0, _snatch])
	if is_ready(&"rake"):
		options.append([2.0, _rake])
	if is_ready(&"volley"):
		options.append([2.0, _volley])
	if is_ready(&"perch") and fight_time() > 20.0:
		options.append([1.5, _perch])
	var total := 0.0
	for o in options:
		total += float(o[0])
	var pick := randf() * total
	for o in options:
		pick -= float(o[0])
		if pick <= 0.0:
			return (o[1] as Callable).call(t)
	return null


## Round the fight, high up: circling `centre`, wings beating.
func _cruise(centre: Vector3, delta: float) -> void:
	if not _cruising:   # (picking up the circle from wherever she is)
		_cruising = true
		_orbit_a = atan2(global_position.z - centre.z, global_position.x - centre.x)
		if randf() < 0.3:
			_orbit_dir = -_orbit_dir
	var speed := CRUISE_SPEED * (1.3 if enraged else 1.0)
	_orbit_a += _orbit_dir * speed / ORBIT * delta
	var goal := centre + Vector3(cos(_orbit_a), 0.0, sin(_orbit_a)) * ORBIT
	goal.y = maxf(_surface_y(goal), _surface_y(global_position)) + CRUISE + sin(_clock * 0.5) * 4.0
	_flap_rate = FLAP * (1.25 if enraged else 1.0)
	_glide = move_toward(_glide, 0.25 if _vel.y < -1.0 else 0.0, delta)
	_steer(goal, speed, delta)


## Fly toward `goal` at `speed`, turning at most `turn` radians a second.
func _steer(goal: Vector3, speed: float, delta: float, turn := 1.4) -> void:
	var want := goal - global_position
	var dir := want.normalized() if want.length() > 0.5 else (_vel.normalized() if _vel.length() > 0.1 else forward())
	var v := _vel.normalized() if _vel.length() > 0.1 else forward()
	var ang := v.angle_to(dir)
	var nv := v.slerp(dir, clampf(turn * delta / ang, 0.0, 1.0)) if ang > 1e-3 else dir
	_vel = nv * move_toward(_vel.length(), speed, 18.0 * delta)
	global_position += _vel * delta
	_face_along(delta)


## Hold still in the air (a hover, wings beating hard).
func _hover(delta: float) -> void:
	_vel = _vel.move_toward(Vector3.ZERO, 26.0 * delta)
	global_position += _vel * delta
	_flap_rate = 2.6
	_glide = move_toward(_glide, 0.0, delta * 3.0)


## Turn the way she's flying, banking into the turn, nose up or down.
func _face_along(delta: float) -> void:
	var flat := Vector2(_vel.x, _vel.z)
	if flat.length() < 0.5:
		return
	var want := atan2(-_vel.x, -_vel.z)
	var turn := wrapf(want - rotation.y, -PI, PI)
	var k := clampf(delta * 5.0, 0.0, 1.0)
	rotation.y += turn * k
	_bank = lerpf(_bank, clampf(turn * 1.8, -0.6, 0.6), clampf(delta * 3.0, 0.0, 1.0))
	_climb = lerpf(_climb, atan2(_vel.y, flat.length()), clampf(delta * 3.0, 0.0, 1.0))


## The ground under `p`, or the water over it: she skims a lake, she
## doesn't dive into it.
func _surface_y(p: Vector3) -> float:
	var g := ground_y(p)
	return maxf(g, Terrain.WATER_LEVEL) if match_manager and "island" in match_manager and match_manager.island else g


func _ground_below() -> Vector3:
	return Vector3(global_position.x, _surface_y(global_position), global_position.z)


## Between her talons (where what she's caught hangs).
func _talons_point() -> Vector3:
	return (bone_point(&"l_foot", 0.8) + bone_point(&"r_foot", 0.8)) * 0.5


# ---- animating ------------------------------------------------------------------------------------

func _animate(delta: float) -> void:
	if skeleton == null or (state == State.DEAD and action == null):
		return
	_tilt(delta)
	var was := _flap
	_flap += delta * _flap_rate * (1.0 - _glide) * TAU
	if _air and alive and floor(was / TAU) != floor(_flap / TAU):
		Audio.play_at(&"owl_flap", get_chest_position(), -4.0, 0.12, {"max_distance": 260.0, "unit_size": 30.0})
	poser.clear()
	poser.add_pose(_body_pose(), 1.0)
	var aw := action.weight() if action else 0.0
	poser.add_pose(_perched_pose(), 1.0 - aw)
	_look_at_target(delta, 1.0 - aw)
	if action:
		poser.add_pose(action.pose(), aw)
		if action.layer.is_valid():
			poser.add_pose(action.layer.call(action.t), aw)
	_fade_t += delta
	if _fade_t < 0.35:
		poser.add_pose(_fade_pose, 1.0 - smoothstep(0.0, 0.35, _fade_t))
	poser.apply()
	_tend_eyes()


## A move cut off (shot out of the sky, beaten): what it had her doing fades
## away over a moment, instead of snapping back.
func _cancel_action() -> void:
	if action:
		var w := action.weight()
		_fade_pose = {}
		for pose in [action.pose(), action.layer.call(action.t) if action.layer.is_valid() else {}]:
			for r in pose:
				_fade_pose[r] = (_fade_pose.get(r, Vector3.ZERO) as Vector3) + (pose[r] as Vector3) * w
		_fade_t = 0.0
	super()


## Perched (or down): never quite still. Her head bobbing and swaying as she
## sizes you up (an owl working out how far off you are), tilted right over
## now and then, and a shake of all her feathers once she's down.
func _perched_pose() -> Dictionary:
	var k := 1.0 - _air_k
	if k <= 0.01 or not alive:
		return {}
	var t := _clock
	var out := {&"head": Vector3(6.0 * sin(t * 2.1), 0, 10.0 * sin(t * 1.3)) * k, &"neck": Vector3(-4.0 * sin(t * 2.1 - 0.4), 0, 0) * k}
	var tl := t - _tilt_at
	if tl >= 0.0 and tl < 1.6:
		var e := smoothstep(0.0, 0.18, tl) * (1.0 - smoothstep(1.1, 1.6, tl))
		out[&"head"] = (out[&"head"] as Vector3) + Vector3(0, 0, 40.0 * _tilt_dir * e * k)
	var since := t - _landed_at - 0.5
	if since > 0.0 and since < 0.8:   # (a rouse: fluffed up, shaking it all out)
		var env := sin(PI * since / 0.8) * k
		var ph := TAU * 5.5 * since
		out = _plus(out, {&"chest": Vector3(-6.0, 10.0 * sin(ph), 6.0 * sin(ph + 0.7)), &"spine": Vector3(0, -7.0 * sin(ph - 0.5), -5.0 * sin(ph)),
			&"head": Vector3(0, -12.0 * sin(ph - 1.0), 8.0 * sin(ph - 0.6)), &"tail": Vector3(0, 0, 14.0 * sin(ph - 1.4)),
			&"l_upper_arm": Vector3(0, 0, 10.0 + 6.0 * sin(ph)), &"r_upper_arm": Vector3(0, 0, -10.0 - 6.0 * sin(ph))}, env)
	return out


## Her whole body tilted (the model): pitched into her flight, banking into
## her turns; upright perched.
func _tilt(delta: float) -> void:
	_air_k = lerpf(_air_k, 1.0 if _air else 0.0, clampf(delta * 2.5, 0.0, 1.0))
	var fly := _air_k * (1.0 - _talons * 0.8)
	var want := -0.62 * fly + _climb * 0.6 * _air_k + _dive_pitch + _dead_pitch
	_pitch = lerpf(_pitch, want, clampf(delta * 3.0, 0.0, 1.0))
	if not _air:
		_bank = lerpf(_bank, 0.0, clampf(delta * 3.0, 0.0, 1.0))
	if model:
		model.basis = (Basis(Vector3.RIGHT, _pitch) * Basis(Vector3.BACK, _bank) * Basis(Vector3.UP, PI)).scaled(Vector3.ONE * size)


## What she's doing with her wings, legs, head and tail this frame (her
## moves add to it): flying, wings beating (held out in a glide) and talons
## tucked (reaching, when she's going for something); perched, wings drooped
## round her.
func _body_pose() -> Dictionary:
	var d := (1.0 - cos(_flap)) * 0.5            # (0 the top of a wingbeat, 1 the bottom)
	var lag := (1.0 - cos(_flap - 0.6)) * 0.5
	var lag2 := (1.0 - cos(_flap - 1.1)) * 0.5
	var air := _air_k
	var up := lerpf(lerpf(lerpf(18.0, -88.0, d), -38.0, _glide), -92.0, 1.0 - air)
	var mid := lerpf(lerpf(lerpf(14.0, -30.0, lag), -6.0, _glide), -12.0, 1.0 - air)
	var tip := lerpf(lerpf(lerpf(10.0, -26.0, lag2), 4.0, _glide), -8.0, 1.0 - air)
	var droop := 12.0 * (1.0 - air)
	var tuck := air * (1.0 - _talons)
	var p := {
		&"l_upper_arm": Vector3(droop, 0, up), &"r_upper_arm": Vector3(droop, 0, -up),
		&"l_lower_arm": Vector3(0, 0, mid), &"r_lower_arm": Vector3(0, 0, -mid),
		&"l_hand": Vector3(0, 0, tip), &"r_hand": Vector3(0, 0, -tip),
		&"l_upper_leg": Vector3(50.0 * tuck - 30.0 * _talons, 0, 0), &"r_upper_leg": Vector3(50.0 * tuck - 30.0 * _talons, 0, 0),
		&"l_lower_leg": Vector3(35.0 * tuck, 0, 0), &"r_lower_leg": Vector3(35.0 * tuck, 0, 0),
		&"l_foot": Vector3(45.0 * tuck - 25.0 * _talons, 0, 0), &"r_foot": Vector3(45.0 * tuck - 25.0 * _talons, 0, 0),
		# (her head kept level as her body pitches into her flight)
		&"neck": Vector3(-18.0 * air, 0, 0), &"head": Vector3(-22.0 * air, 0, 0),
		&"tail": Vector3(-10.0 * air + 6.0 * sin(_clock * 0.9), 0, rad_to_deg(_bank) * 0.3),
		&"chest": Vector3(1.5 * sin(_clock * 1.6), 0, 0),
		&"root": Vector3(0, 0.012 * (d - 0.5) * air * (1.0 - _glide), 0),
	}
	return p


## Her head turns toward whoever she's after: an owl's, a long way round
## (perched, nearly over her shoulder).
func _look_at_target(delta: float, w: float) -> void:
	if target == null or not is_instance_valid(target) or not poser.has(&"head"):
		return
	var want := target.get_eye_position()
	# (an owl's head: a quick snap round to where you are, and held there,
	# not a slow follow)
	if _look_goal == Vector3.INF or _clock >= _look_next or _look_goal.distance_to(want) > 30.0:
		_look_goal = want
		_look_next = _clock + randf_range(0.5, 1.3)
	_look = _look_goal if _look == Vector3.INF else _look.lerp(_look_goal, IKMath.damp(14.0, delta))
	var local := global_transform.affine_inverse() * _look
	var reach := lerpf(110.0, 60.0, _air_k)
	var yaw := clampf(rad_to_deg(atan2(-local.x, -local.z)), -reach, reach)
	var head_h := (get_eye_position() - global_position).y
	var pitch := clampf(rad_to_deg(atan2(local.y - head_h, Vector2(local.x, local.z).length())), -45.0, 20.0)
	poser.add(&"neck", Vector3(-pitch * 0.3, yaw * 0.3, 0), w)
	poser.add(&"head", Vector3(-pitch * 0.7, yaw * 0.7, 0), w)


func _action_done(a: BossAction) -> void:
	if a.name == &"death":
		# down for good: she keeps the last of her fall, and stops
		poser.clear()
		poser.add_pose(_body_pose(), 1.0)
		poser.add_pose(a.keys.back()[1] if not a.keys.is_empty() else {}, 1.0)
		poser.apply()
		_update_bones()
		set_physics_process(false)
		_fallen()
		return
	super(a)
	_rest_until = _clock + REST
	_cruising = false
	_diving = false
	_dive_pitch = 0.0
	if a.name != &"perch":
		_talons = 0.0


# ---- Snatch -----------------------------------------------------------------------------------------

func _snatch(t: Critter) -> BossAction:
	cooldown(&"snatch", 12.0)
	var line_up := 1.1
	var dive := 1.3
	var climb := 2.4
	var a := BossAction.new(&"snatch", line_up + dive + climb)
	# where she'll strike: her prey, followed while she lines up (shared by the
	# action's lambdas), then fixed, and the ring shown, as she dives
	var aim := {"spot": _snatch_spot(t)}
	var start := Vector3.INF
	var away := Vector3.ZERO
	a.on(0.0, func():
		_dive_start()
		Audio.play_at(&"owl_screech", get_eye_position(), 8.0, 0.05, {"max_distance": 700.0, "unit_size": 50.0}))
	a.on(line_up, func(): warn(aim.spot, SNATCH_R, dive))
	a.tick = func(time: float, delta: float):
		var spot: Vector3 = aim.spot
		if time < line_up:   # up over it, banking round to where the dive starts
			if is_instance_valid(t) and t.alive:
				aim.spot = _snatch_spot(t)
				spot = aim.spot
			var from_it := Vector3(global_position.x - spot.x, 0.0, global_position.z - spot.z)
			var over := spot + (from_it.normalized() if from_it.length() > 1.0 else -forward()) * 34.0
			over.y = spot.y + CRUISE + 6.0
			_flap_rate = 2.2
			_steer(over, CRUISE_SPEED * 1.4, delta, 2.6)
			return
		if time < line_up + dive:   # down on it, faster and faster
			if start == Vector3.INF:
				start = global_position
			var u := (time - line_up) / dive
			var e := u * u
			var ctrl := Vector3(spot.x, spot.y + CRUISE * 0.5, spot.z)
			var p := start.lerp(ctrl, e).lerp(ctrl.lerp(spot, e), e)
			_vel = (p - global_position) / maxf(delta, 1e-3)
			global_position = p
			_face_along(delta)
			_glide = 1.0
			_talons = smoothstep(0.5, 0.95, u)
			_dive_pitch = -0.5 * (1.0 - _talons)
			return
		# up and away with whatever she's caught
		if away == Vector3.ZERO:
			away = Vector3(forward().x, 0.0, forward().z).normalized()
			_vel = away * 14.0 + Vector3.UP * 12.0
			_dive_end()
		_glide = 0.0
		_flap_rate = 3.2
		_talons = 0.55 if _held else maxf(0.0, _talons - delta * 2.0)
		var goal := spot + away * 70.0
		goal.y = spot.y + DROP_FROM + 6.0
		_steer(goal, CRUISE_SPEED, delta, 1.2)
		_carry()
	a.on(line_up + dive, func(): _strike(aim.spot))
	a.on(line_up + dive + climb - 0.05, func(): _let_go())
	a.data["cancel"] = func():
		_let_go()
		_dive_end()
	return a


## Where a snatch at `t` comes down: just ahead of it, on the ground (or the
## water).
func _snatch_spot(t: Critter) -> Vector3:
	var spot := t.global_position + Vector3(t.velocity.x, 0.0, t.velocity.z) * 0.6
	spot.y = _surface_y(spot)
	return spot


## At the bottom of the dive: whoever's still in the ring, caught (the
## nearest); nobody, and her talons rake the ground.
func _strike(spot: Vector3) -> void:
	var caught: Critter = null
	for c in foes_near(spot, SNATCH_R):
		if c.held_by == null and absf(c.global_position.y - spot.y) < 6.0 \
				and (caught == null or c.global_position.distance_to(spot) < caught.global_position.distance_to(spot)):
			caught = c
	BossFX.dust(spot, SNATCH_R * 1.4)
	if caught == null:
		hurt_ring(spot, SNATCH_R, 60.0, 20.0, 8.0, 4.0, &"talons", false)   # (her blows as hard as the others': she was the softest by half)
		Audio.play_at(&"boss_stomp", spot, -2.0, 0.1, {"max_distance": 300.0, "unit_size": 20.0})
		return
	_held = caught
	_struggles = 0
	_carry_hits = 0.0
	caught.end_knock()   # (picked up off the floor if it was knocked down)
	caught.held_by = self
	hurt(caught, 25.0, forward(), 0.0, 0.0, &"talons", DamageInfo.Kind.MELEE, 0.0)
	Audio.play_at(&"gore_splat", spot, 2.0, 0.1, {"max_distance": 200.0, "unit_size": 20.0})
	if caught.is_player:
		Events.headline.emit("Old Hoot's got you! Jump, and keep jumping, to wriggle free.")


## Whoever she's caught, hanging from her talons as she climbs (you can
## wriggle: jump).
func _carry() -> void:
	if _held == null:
		return
	if not is_instance_valid(_held) or not _held.alive:
		_held = null
		return
	_held.global_position = _talons_point() - Vector3.UP * _held.chest_height()
	_held.velocity = Vector3.ZERO
	_held.visual.physics_tick(_held.global_transform, true)
	if _held.is_player and _held.want_jump:   # (its physics is hers while she has it: the jump waits for us)
		_held.want_jump = false
		_struggles += 1
		if _struggles >= STRUGGLES:
			Events.headline.emit("You wriggled free!")
			_let_go()


## Whoever she's carrying off (null: nobody), for the rogues to yell about.
func holding() -> Critter:
	return _held if _held and is_instance_valid(_held) else null


## Let go: whoever she had falls, and takes the fall when they land (_tend_dropped).
func _let_go() -> void:
	if _held == null:
		return
	var c := _held
	_held = null
	if not is_instance_valid(c):
		return
	c.held_by = null
	if c.alive:
		c.velocity = Vector3(_vel.x, minf(_vel.y, 0.0), _vel.z) * 0.5
		_dropped.append([c, 0.0, 0.0])


## Everyone she's dropped, till they land: the harder, the worse (into
## water, nothing). A bot from high up doesn't get up again; you do.
func _tend_dropped(delta: float) -> void:
	for d in _dropped.duplicate():
		var c := d[0] as Critter
		d[2] = float(d[2]) + delta
		if c == null or not is_instance_valid(c) or not c.alive or float(d[2]) > 8.0:
			_dropped.erase(d)
			continue
		d[1] = maxf(float(d[1]), -c.velocity.y)
		if float(d[2]) < 0.15 or not (c.is_on_floor() or c.swimming):
			continue
		_dropped.erase(d)
		var speed := float(d[1])
		if c.swimming or speed < 12.0:
			continue
		var amount := (speed - 10.0) * (2.0 if c.is_player else 5.5)
		if c.is_player:
			amount = minf(amount, 45.0)
		hurt(c, amount, Vector3(c.velocity.x, 0.0, c.velocity.z).normalized(), 4.0, 5.0, &"drop", DamageInfo.Kind.FALL, 0.4)
		BossFX.dust(c.global_position, 3.0)


# ---- Talon Rake -------------------------------------------------------------------------------------

func _rake(t: Critter) -> BossAction:
	cooldown(&"rake", 10.0)
	var mid := t.global_position
	mid.y = _surface_y(mid)
	var along := Vector3(mid.x - global_position.x, 0.0, mid.z - global_position.z)
	if along.length() < 20.0:
		along = Vector3(_vel.x, 0.0, _vel.z)
	along = along.normalized() if along.length() > 0.1 else Vector3(forward().x, 0.0, forward().z).normalized()
	var a0 := mid - along * RAKE_LEN * 0.5
	var b0 := mid + along * RAKE_LEN * 0.5
	var line_up := 1.4
	var pass_for := 1.6
	var a := BossAction.new(&"rake", line_up + pass_for + 1.4)
	var hit := {}
	var start := Vector3.INF
	a.on(0.0, func():
		_dive_start()
		Audio.play_at(&"owl_screech", get_eye_position(), 6.0, 0.08, {"max_distance": 700.0, "unit_size": 50.0}))
	a.on(line_up * 0.5, func(): warn_strip(a0, b0, RAKE_W, line_up * 0.5 + pass_for * 0.4))   # (as she swoops: shown from the start, everyone was long gone)
	a.tick = func(time: float, delta: float):
		if time < line_up:   # down to the start of the strip
			if start == Vector3.INF:
				start = global_position
			var u := smoothstep(0.0, 1.0, time / line_up)
			var to := a0 + Vector3.UP * 3.0
			var p := start.lerp(to, u)
			p.y = lerpf(start.y, to.y, u * u)
			_vel = (p - global_position) / maxf(delta, 1e-3)
			global_position = p
			_face_along(delta)
			_glide = 1.0
			_talons = smoothstep(0.5, 1.0, u)
			return
		if time < line_up + pass_for:   # along it, low, talons out
			var p := a0.lerp(b0, (time - line_up) / pass_for)
			p.y = _surface_y(p) + 3.0
			_vel = (p - global_position) / maxf(delta, 1e-3)
			global_position = p
			_face_along(delta)
			_talons = 1.0
			var claws := _talons_point()
			for c in foes_near(claws, RAKE_W * 0.75):
				if hit.has(c) or absf(c.global_position.y - claws.y) > 7.0:
					continue
				hit[c] = true
				hurt(c, 70.0, along, 12.0, 6.0, &"rake", DamageInfo.Kind.MELEE, 0.8)
			return
		# and back up
		_dive_end()
		_talons = maxf(0.0, _talons - delta * 2.0)
		_glide = maxf(0.0, _glide - delta * 2.0)
		_flap_rate = 2.6
		_steer(global_position + along * 40.0 + Vector3.UP * 30.0, CRUISE_SPEED * 1.2, delta, 2.0)
	a.data["cancel"] = func(): _dive_end()
	return a


# ---- Feather Volley ---------------------------------------------------------------------------------

func _volley(t: Critter) -> BossAction:
	cooldown(&"volley", 8.0)
	var n := 10 if enraged else 8
	var a := BossAction.new(&"volley", 2.2)
	a.flow = true
	a.key(0.0, {}).key(0.45, {&"l_upper_arm": Vector3(0, 0, 35), &"r_upper_arm": Vector3(0, 0, -35), &"chest": Vector3(-8, 0, 0)})
	a.key(0.8, {&"l_upper_arm": Vector3(-30, 0, -45), &"r_upper_arm": Vector3(-30, 0, 45), &"chest": Vector3(10, 0, 0)}).key(2.2, {})
	a.tick = func(_time: float, delta: float):
		_hover(delta)
		if is_instance_valid(t) and t.alive:
			face_toward(t.global_position, delta, 2.0)
	a.on(0.7, func():
		Audio.play_at(&"feather_volley", get_chest_position(), 6.0, 0.05, {"max_distance": 500.0, "unit_size": 35.0}))
	a.on(0.8, func():
		var aim := t.global_position if is_instance_valid(t) and t.alive else _ground_below() + forward() * 30.0
		var lead := t.velocity * 1.0 if is_instance_valid(t) else Vector3.ZERO
		for i in n:
			var at := aim + Vector3(lead.x, 0.0, lead.z) * (0.5 if i == 0 else 1.0)
			if i > 0:
				at += Vector3(randf_range(-1, 1), 0.0, randf_range(-1, 1)).normalized() * randf_range(4.0, 12.0)
			_feather(at, 0.85 + 0.08 * i))
	return a


## One feather, flung from her chest, coming down quill first at `at`.
func _feather(at: Vector3, flight: float) -> void:
	at.y = _surface_y(at)
	warn(at, FEATHER_R, flight)
	var from := get_chest_position() + Vector3(randf_range(-6, 6), randf_range(-2, 2), randf_range(-3, 3))
	var f := MeshInstance3D.new()
	f.mesh = _feather_mesh()
	f.material_override = _feather_mat()
	f.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_parent().add_child(f)
	f.global_position = from
	var shape := Vector3(0.9, 6.0, 0.14)
	var arc := func(u: float):
		if not is_instance_valid(f):
			return
		var lift := func(x: float) -> Vector3: return from.lerp(at, x) + Vector3.UP * sin(x * PI) * 6.0
		var p: Vector3 = lift.call(u)
		var ahead: Vector3 = lift.call(minf(u + 0.02, 1.0))
		f.global_position = p
		if ahead.distance_to(p) > 0.001:
			f.basis = Basis(IKMath.from_to(Vector3.DOWN, (ahead - p).normalized())) * Basis.from_scale(shape)
	var tw := f.create_tween()
	tw.tween_method(arc, 0.0, 1.0, flight)
	tw.tween_callback(func():
		hurt_ring(at, FEATHER_R, 45.0, 15.0, 6.0, 4.0, &"feathers", false)
		BossFX.dust(at, 3.5, Color(0.6, 0.62, 0.66, 0.6))
		Audio.play_at(&"carrot_impact_dirt", at, 2.0, 0.1, {"max_distance": 200.0})
		f.global_position = at + Vector3.UP * 2.2)   # (stuck in the ground, quill first)
	tw.tween_interval(5.0)
	tw.tween_property(f, "global_position:y", at.y - 4.0, 1.2)
	tw.tween_callback(f.queue_free)


static var _fmesh: Mesh
static var _fmat: StandardMaterial3D


static func _feather_mesh() -> Mesh:
	if _fmesh == null:
		var m := SphereMesh.new()
		m.radius = 0.5
		m.height = 1.0
		m.radial_segments = 8
		m.rings = 6
		_fmesh = m
	return _fmesh


static func _feather_mat() -> StandardMaterial3D:
	if _fmat == null:
		_fmat = StandardMaterial3D.new()
		_fmat.albedo_color = Color(0.92, 0.93, 0.96)
		_fmat.roughness = 0.85
		_fmat.emission_enabled = true   # (pale enough to see coming by night)
		_fmat.emission = Color(0.55, 0.6, 0.7)
		_fmat.emission_energy_multiplier = 0.35
	return _fmat


# ---- Hoot --------------------------------------------------------------------------------------------

## She puffs up and hoots: everyone in the ring below her is knocked off their
## feet (her roar: enraged, crowded, and for the camera as she arrives).
func _roar_action() -> BossAction:
	_hooted_at = _clock
	cooldown(&"hoot", 18.0)
	var a := BossAction.new(&"hoot", 2.4)
	var puff := {&"chest": Vector3(-14, 0, 0), &"neck": Vector3(-8, 0, 0), &"head": Vector3(-18, 0, 0), &"jaw": Vector3(22, 0, 0),
		&"l_upper_arm": Vector3(0, 0, 14), &"r_upper_arm": Vector3(0, 0, -14)}
	a.flow = true
	a.key(0.0, {}).key(0.55, puff).key(1.7, puff).key(2.4, {})
	a.layer = func(time: float) -> Dictionary:   # (hooting: her head bobbing with it, her throat swelling, her tail cocked)
		var u := time - 0.68
		if u < 0.0 or u > 0.9:
			return {}
		var e := sin(PI * u / 0.9)
		return {&"head": Vector3(10.0 * sin(u * TAU * 2.2), 0, 0) * e, &"neck": Vector3(-6.0 * sin(u * TAU * 2.2 - 0.5), 0, 0) * e,
			&"chest": Vector3(-5.0, 0, 0) * e, &"tail": Vector3(-14.0, 0, 0) * e}
	var centre := _ground_below()
	a.on(0.0, func():
		centre = _ground_below()
		if _clock >= _quiet_until:
			warn(centre, HOOT_R, 0.75))
	a.tick = func(_time: float, delta: float):
		if _air:
			_hover(delta)
	a.on(0.75, func():
		Audio.play_at(&"owl_hoot", mouth_position(), 12.0, 0.03, {"max_distance": 1200.0, "unit_size": 80.0})
		BossFX.shockwave(centre, HOOT_R, Color(0.72, 0.8, 1.0, 0.8))
		Events.explosion.emit(mouth_position(), 18.0)   # (the camera shakes: CameraRig)
		hurt_ring(centre, HOOT_R, 14.0, 4.0, 8.0, 6.0, &"hoot", false))
	return a


# ---- Perch, and off again ---------------------------------------------------------------------------

func _perch(t: Critter) -> BossAction:
	cooldown(&"perch", 30.0)
	var spot := _perch_spot(t)
	var down := 2.2
	var a := BossAction.new(&"perch", down + 0.8)
	var start := Vector3.INF
	a.on(0.0, func(): warn(spot, PERCH_R, down))
	a.tick = func(time: float, delta: float):
		if not _air:
			return
		if start == Vector3.INF:
			start = global_position
		var u := clampf(time / down, 0.0, 1.0)
		var e := 1.0 - (1.0 - u) * (1.0 - u)   # (slowing as she comes in)
		var p := start.lerp(spot, e)
		_vel = (p - global_position) / maxf(delta, 1e-3)
		global_position = p
		if u < 0.85:
			_face_along(delta)
		_talons = smoothstep(0.45, 0.9, u)
		_glide = 1.0 - smoothstep(0.6, 0.9, u)   # (beating her wings to stop)
		_flap_rate = 3.0
	a.on(down, func():
		global_position = spot
		_land(spot)
		_perch_left = PERCH_FOR)
	return a


## Where she comes down to rest: near whoever she's after, on her side of
## them, on open, dry ground (her wings spread over it: not in a wood).
func _perch_spot(t: Critter) -> Vector3:
	var off := Vector3(global_position.x - t.global_position.x, 0.0, global_position.z - t.global_position.z)
	off = off.normalized() if off.length() > 1.0 else Vector3(forward().x, 0.0, forward().z).normalized()
	var spot := t.global_position + off * 28.0
	var isl: Island = match_manager.island if match_manager and "island" in match_manager else null
	if isl and isl.scatter:
		for k in 16:   # (round toward either side of her, and further out)
			var d := off.rotated(Vector3.UP, (1.0 if k % 2 == 0 else -1.0) * float(k / 2) * 0.45)
			var q := t.global_position + d * (28.0 + float(k % 3) * 9.0)
			if not isl.scatter.blocked(Vector2(q.x, q.z), PERCH_R * 0.8, false) and ground_y(q) > Terrain.WATER_LEVEL + 0.5:
				spot = q
				break
	spot.y = ground_y(spot)
	return spot


## Down on the ground (perched, or from her entrance): her wingbeats blow
## back everyone close.
func _land(spot: Vector3) -> void:
	_air = false
	_landed_at = _clock
	_vel = Vector3.ZERO
	_talons = 0.0
	_glide = 0.0
	hurt_ring(spot, PERCH_R, 8.0, 2.0, 11.0, 5.0, &"gust", false)
	BossFX.dust(spot, PERCH_R * 1.2)
	Audio.play_at(&"boss_stomp", spot, 0.0, 0.1, {"max_distance": 500.0, "unit_size": 30.0})


func _take_off() -> BossAction:
	var a := BossAction.new(&"take_off", 1.8)
	a.on(0.0, func():
		_air = true
		_vel = Vector3(forward().x, 0.0, forward().z) * 6.0 + Vector3.UP * 10.0
		hurt_ring(global_position, PERCH_R, 6.0, 2.0, 11.0, 5.0, &"gust", false)
		BossFX.dust(global_position, PERCH_R * 1.2)
		Audio.play_at(&"owl_flap", global_position, 6.0, 0.05, {"max_distance": 400.0, "unit_size": 40.0}))
	a.tick = func(_time: float, delta: float):
		_flap_rate = 3.2
		_glide = 0.0
		_steer(global_position + Vector3(forward().x, 0.0, forward().z) * 30.0 + Vector3.UP * 25.0, CRUISE_SPEED, delta, 1.0)
	return a


# ---- getting hurt ------------------------------------------------------------------------------------

func take_damage(info: DamageInfo) -> void:
	var before := health
	super(info)
	if not alive or health >= before:
		return
	var by := info.attacker as Critter
	var count := (1.0 if by and by.is_player else 0.15) * (3.0 if info.kind == DamageInfo.Kind.EXPLOSION else 1.0)
	if _held:   # (hit hard enough, she lets go)
		_carry_hits += count
		if _carry_hits >= LET_GO_AT:
			if _held.is_player:
				Events.headline.emit("She let go of you!")
			_let_go()
	if _diving and info.bone_role in WINGS:
		_dive_hits += count
		if _dive_hits >= GROUND_AT and _air and (action == null or action.interruptible):
			_ground()


func _dive_start() -> void:
	_diving = true
	_dive_hits = 0.0


func _dive_end() -> void:
	_diving = false
	_dive_pitch = 0.0


## Shot out of the sky: she tumbles down, and lies there stunned a while
## (and takes VULNERABLE times as much), wings out across the ground.
func _ground() -> void:
	_let_go()
	_cancel_action()
	_dive_end()
	Events.announce.emit("OLD HOOT IS GROUNDED!", "You shot her out of the sky. Go for the eye!")
	Audio.play_at(&"owl_screech", get_eye_position(), 10.0, 0.05, {"max_distance": 800.0, "unit_size": 60.0})
	var a := BossAction.new(&"grounded", 3.0)
	a.interruptible = false
	var down := false
	var spin := signf(_bank) if _bank != 0.0 else 1.0
	a.tick = func(_time: float, delta: float):
		if down:
			return
		_vel = Vector3(_vel.x * 0.98, _vel.y - 40.0 * delta, _vel.z * 0.98)
		var p := global_position + _vel * delta
		var g := _surface_y(p)
		_bank += spin * delta * 2.0
		_glide = 1.0
		if p.y <= g:
			p.y = g
			down = true
			global_position = p
			_air = false
			_bank = 0.0
			_vel = Vector3.ZERO
			BossFX.shockwave(p, PERCH_R * 1.4)
			BossFX.dust(p, PERCH_R * 1.6)
			Events.explosion.emit(p, 14.0)
			Audio.play_at(&"boss_stomp", p, 8.0, 0.05, {"max_distance": 700.0, "unit_size": 50.0})
			_perch_left = 1.0
			stun(GROUNDED_FOR, {&"l_upper_arm": Vector3(0, 0, 48), &"r_upper_arm": Vector3(0, 0, -48),
				&"neck": Vector3(20, 0, 0), &"head": Vector3(30, 40, 0)})
			if action:   # (dazed: her head rolling, her wings twitching as she tries to get them under her, stars)
				action.layer = func(time: float) -> Dictionary:
					var w := clampf(time / 0.3, 0.0, 1.0) * clampf((GROUNDED_FOR - time) / 0.5, 0.0, 1.0)
					var r := TAU * 0.7 * time
					var f := maxf(0.0, sin(time * TAU * 1.1)) * maxf(0.0, sin(time * 0.9))
					return {&"head": Vector3(-8.0 * sin(r), 12.0 * cos(r), 10.0 * sin(r)) * w, &"neck": Vector3(0, 6.0 * cos(r - 0.6), 0) * w,
						&"l_upper_arm": Vector3(0, 0, -16.0 * f) * w, &"r_upper_arm": Vector3(0, 0, 16.0 * f) * w}
				var st := {"stars": 0.0}
				action.tick = func(time: float, dt: float):
					st.stars = float(st.stars) - dt
					if time < GROUNDED_FOR - 0.6 and float(st.stars) <= 0.0:
						st.stars = 0.5
						_stars()
			return
		global_position = p
	start(a)


# ---- arriving, and going down -----------------------------------------------------------------------

## She glides in out of the dark from beyond where she lands (the camera's
## side is yours: you see her coming), flares, and comes down on it.
func _entrance() -> BossAction:
	var at := global_position
	var toward := Vector3(forward().x, 0.0, forward().z).normalized()
	var from := at - toward * 170.0 + Vector3.UP * 80.0
	var a := BossAction.new(&"entrance", land_time + 1.4)
	a.interruptible = false
	_air = true
	_air_k = 1.0
	_glide = 1.0
	_vel = (at - from) / land_time
	visible = false   # (till her glide's first step: she's where she lands for now, which is where BossIntro sets up)
	a.on(0.0, func(): warn(at, 22.0, land_time))
	a.tick = func(time: float, delta: float):
		visible = true
		if time >= land_time:
			return
		var u := time / land_time
		var p := from.lerp(at, u)
		p.y = lerpf(from.y, at.y, smoothstep(0.0, 1.0, u))
		_vel = (p - global_position) / maxf(delta, 1e-3)
		global_position = p
		if u < 0.8:
			_face_along(delta)
		else:   # (flaring: talons out, beating her wings to stop)
			face_toward(at + toward * 10.0, delta, 2.0)
			_talons = smoothstep(0.8, 0.98, u)
			_glide = 1.0 - smoothstep(0.8, 0.95, u)
			_flap_rate = 3.0
	a.on(land_time, func():
		global_position = at
		_land(at)
		hurt_ring(at, 22.0, 20.0, 5.0, 12.0, 6.0, &"landing")
		Events.explosion.emit(at, 12.0))
	return a


func _after_entrance() -> void:
	_perch_left = 1.5
	cooldown(&"snatch", 5.0)
	cooldown(&"rake", 9.0)
	cooldown(&"volley", 6.0)
	cooldown(&"perch", 28.0)
	if foes_near(global_position, 60.0).size() >= 2:
		start(_roar_action())


## Down: out of the sky if she's up there, wings limp, and she lies where
## she falls.
func _death_action() -> BossAction:
	_let_go()
	var a := BossAction.new(&"death", 3.4)
	a.blend_out = 0.0
	a.interruptible = false
	a.flow = true
	a.key(0.0, {}).key(1.0, {&"head": Vector3(-30, 0, 0), &"l_upper_arm": Vector3(0, 0, 40), &"r_upper_arm": Vector3(0, 0, -40)})
	a.layer = func(time: float) -> Dictionary:   # (her wings beating feebly as she goes down, then still)
		var w := clampf(1.0 - time / 1.5, 0.0, 1.0)
		if w <= 0.0:
			return {}
		var f := sin(time * TAU * 2.2)
		return {&"l_upper_arm": Vector3(0, 0, 24.0 * f) * w, &"r_upper_arm": Vector3(0, 0, -24.0 * f) * w,
			&"l_lower_arm": Vector3(0, 0, 12.0 * sin(time * TAU * 2.2 - 0.7)) * w, &"r_lower_arm": Vector3(0, 0, -12.0 * sin(time * TAU * 2.2 - 0.7)) * w,
			&"head": Vector3(0, 8.0 * sin(time * 3.0), 0) * w}
	a.key(3.0, {&"spine": Vector3(20, 0, 0), &"neck": Vector3(30, 0, 0), &"head": Vector3(35, 55, 0), &"l_upper_arm": Vector3(0, 0, 40),
		&"r_upper_arm": Vector3(0, 0, -40), &"tail": Vector3(-15, 0, 0)})
	var down := false
	var spin := randf_range(-1.0, 1.0)
	a.tick = func(_time: float, delta: float):
		_flap_rate = 0.0
		if down:
			return
		_vel = Vector3(_vel.x * 0.985, _vel.y - 36.0 * delta, _vel.z * 0.985)
		var p := global_position + _vel * delta
		var g := _surface_y(p)
		_bank += spin * delta
		if p.y <= g + 0.1:
			p.y = g
			down = true
			_air = false
			_vel = Vector3.ZERO
			_dead_pitch = -0.45
			BossFX.shockwave(p, PERCH_R * 1.5)
			BossFX.dust(p, PERCH_R * 1.8)
			Events.explosion.emit(p, 16.0)
			Audio.play_at(&"boss_stomp", p, 8.0, 0.05, {"max_distance": 700.0, "unit_size": 50.0})
		global_position = p
	return a


func _fallen() -> void:
	if gore_ok:
		FX.gore_burst(get_chest_position(), 3.0, Color(0.93, 0.94, 0.96))
	BossFX.dust(global_position, 30.0)


# ---- rewind (TimeKeeper) -----------------------------------------------------------------------------

func snapshot() -> Dictionary:
	var s := super()
	s["air"] = _air
	s["vel"] = _vel
	s["perch"] = _perch_left
	return s


func restore(s: Dictionary) -> void:
	_let_go()
	super(s)
	if not alive:
		return
	_air = bool(s.get("air", _air))
	_vel = s.get("vel", Vector3.ZERO)
	_perch_left = float(s.get("perch", 0.0))
	_talons = 0.0
	_glide = 0.0
	_dive_end()
	_cruising = false
