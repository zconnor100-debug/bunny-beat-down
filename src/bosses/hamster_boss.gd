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
## It moves like a hamster: scurrying on all fours, stopping to sit up on its
## haunches and sniff the air, rearing up to screech or to bite, galloping
## flat out when it charges, and washing its face when it's knocked silly.
## Rabid, it's never still: teeth chattering, its head jerking.

const CHARGE_SPEED := 36.0
const CHARGE_HIT := 9.0             ## metres either side of its path that get trampled
const BITE_RADIUS := 10.0
const FOAM_RADIUS := 9.0
const FOAM_DPS := 18.0
const FOAM_SECONDS := 10.0
const BURROW_RADIUS := 15.0
const GALLOP_HZ := 2.6              ## strides a second, charging
const DAZED := 2.6                  ## seconds it's knocked silly by a wall
const SIT_AFTER := 0.5              ## seconds stood still before it sits up on its haunches
const SNIFF_EVERY := Vector2(4.0, 7.0)   ## seconds of scurrying between stops to sit up and sniff the air (not enraged)

# Its poses (degrees per role, in its own space: BossPoser). The model sits
# up on its haunches with its forepaws held at its chest: a hamster's pose
# when it's looking round (its rest, {}). Moving, it's down on all fours.

## Down on all fours: its back level, its head forward, its paws under it.
const FOURS := {&"hips": Vector3(55, 0, 0), &"spine": Vector3(-5, 0, 0), &"neck": Vector3(-18, 0, 0), &"head": Vector3(-28, 0, 0),
	&"tail": Vector3(-50, 0, 0), &"l_upper_leg": Vector3(-33, 0, 0), &"r_upper_leg": Vector3(-33, 0, 0), &"l_lower_leg": Vector3(44, 0, 0),
	&"r_lower_leg": Vector3(44, 0, 0), &"l_upper_arm": Vector3(-35, 0, 0), &"r_upper_arm": Vector3(-35, 0, 0), &"l_lower_arm": Vector3(10, 0, 0),
	&"r_lower_arm": Vector3(10, 0, 0), &"root": Vector3(0, 0.069, 0)}
## Running flat out (its charge): lower and longer, its ears flat back, teeth bared.
const LOW := {&"hips": Vector3(60, 0, 0), &"spine": Vector3(-4, 0, 0), &"neck": Vector3(-12, 0, 0), &"head": Vector3(-30, 0, 0),
	&"jaw": Vector3(22, 0, 0), &"tail": Vector3(-55, 0, 0), &"l_upper_leg": Vector3(-24, 0, 0), &"r_upper_leg": Vector3(-24, 0, 0),
	&"l_lower_leg": Vector3(8, 0, 0), &"r_lower_leg": Vector3(8, 0, 0), &"l_upper_arm": Vector3(-30, 0, 0), &"r_upper_arm": Vector3(-30, 0, 0),
	&"l_lower_arm": Vector3(6, 0, 0), &"r_lower_arm": Vector3(6, 0, 0), &"l_ear": Vector3(-45, 0, 0), &"r_ear": Vector3(-45, 0, 0),
	&"long": Vector3(0.04, 0, 0), &"root": Vector3(0, 0.134, 0)}
## Gathering itself to charge: its front end down, its rump up, its ears flat.
const CROUCH := {&"hips": Vector3(62, 0, 0), &"spine": Vector3(4, 0, 0), &"chest": Vector3(2, 0, 0), &"neck": Vector3(-24, 0, 0),
	&"head": Vector3(-32, 0, 0), &"jaw": Vector3(16, 0, 0), &"tail": Vector3(-40, 0, 0), &"l_upper_leg": Vector3(-6, 0, 0),
	&"r_upper_leg": Vector3(-6, 0, 0), &"l_lower_leg": Vector3(-32, 0, 0), &"r_lower_leg": Vector3(-32, 0, 0), &"l_upper_arm": Vector3(-44, 0, 0),
	&"r_upper_arm": Vector3(-44, 0, 0), &"l_lower_arm": Vector3(30, 0, 0), &"r_lower_arm": Vector3(30, 0, 0), &"l_ear": Vector3(-50, 0, 0),
	&"r_ear": Vector3(-50, 0, 0), &"root": Vector3(0, 0.171, 0.02)}
## Pulling up short at the end of a charge: its forepaws braced out in
## front of it, its weight back on its haunches, its head up.
const SKID := {&"hips": Vector3(50, 0, 0), &"spine": Vector3(-6, 0, 0), &"neck": Vector3(-16, 0, 0), &"head": Vector3(-14, 0, 0),
	&"jaw": Vector3(20, 0, 0), &"tail": Vector3(-36, 0, 0), &"l_upper_leg": Vector3(-30, 0, 0), &"r_upper_leg": Vector3(-30, 0, 0),
	&"l_lower_leg": Vector3(20, 0, 0), &"r_lower_leg": Vector3(20, 0, 0), &"l_upper_arm": Vector3(-58, 0, 0), &"r_upper_arm": Vector3(-58, 0, 0),
	&"l_lower_arm": Vector3(-8, 0, 0), &"r_lower_arm": Vector3(-8, 0, 0), &"l_ear": Vector3(-40, 0, 0), &"r_ear": Vector3(-40, 0, 0),
	&"root": Vector3(0, 0.08, -0.02)}
## Stood right up on its hind legs, tall (screeching, rearing to bite).
const TALL := {&"hips": Vector3(-18, 0, 0), &"spine": Vector3(-4, 0, 0), &"neck": Vector3(8, 0, 0), &"head": Vector3(14, 0, 0),
	&"tail": Vector3(30, 0, 0), &"l_upper_leg": Vector3(48, 0, 0), &"r_upper_leg": Vector3(48, 0, 0), &"l_lower_leg": Vector3(-40, 0, 0),
	&"r_lower_leg": Vector3(-40, 0, 0), &"l_foot": Vector3(10, 0, 0), &"r_foot": Vector3(10, 0, 0), &"root": Vector3(0, 0.086, 0)}
## Thrown forward jaws first (its bite): long, low, its forepaws out.
const LUNGE := {&"hips": Vector3(66, 0, 0), &"spine": Vector3(-6, 0, 0), &"chest": Vector3(-4, 0, 0), &"neck": Vector3(-4, 0, 0),
	&"head": Vector3(-26, 0, 0), &"jaw": Vector3(2, 0, 0), &"tail": Vector3(-55, 0, 0), &"l_upper_leg": Vector3(-40, 0, 0),
	&"r_upper_leg": Vector3(-40, 0, 0), &"l_lower_leg": Vector3(-20, 0, 0), &"r_lower_leg": Vector3(-20, 0, 0), &"l_upper_arm": Vector3(-55, 0, 0),
	&"r_upper_arm": Vector3(-55, 0, 0), &"l_ear": Vector3(-40, 0, 0), &"r_ear": Vector3(-40, 0, 0), &"long": Vector3(0.06, 0, 0),
	&"root": Vector3(0, 0.109, 0.08)}
## Digging: nose down in the bedding, rump up, forepaws going.
const DIG := {&"hips": Vector3(64, 0, 0), &"spine": Vector3(6, 0, 0), &"chest": Vector3(6, 0, 0), &"neck": Vector3(-6, 0, 0),
	&"head": Vector3(-4, 0, 0), &"tail": Vector3(-40, 0, 0), &"l_upper_leg": Vector3(-12, 0, 0), &"r_upper_leg": Vector3(-12, 0, 0),
	&"l_lower_leg": Vector3(-36, 0, 0), &"r_lower_leg": Vector3(-36, 0, 0), &"l_upper_arm": Vector3(-30, 0, 0), &"r_upper_arm": Vector3(-30, 0, 0),
	&"l_lower_arm": Vector3(30, 0, 0), &"r_lower_arm": Vector3(30, 0, 0), &"root": Vector3(0, 0.236, 0)}
## Down in the bedding (burrowing): nose first, all of it under the floor.
const UNDER := {&"hips": Vector3(80, 0, 0), &"spine": Vector3(10, 0, 0), &"head": Vector3(10, 0, 0), &"root": Vector3(0, -1.1, 0.1)}
## Down in the bedding, upright (about to burst up out of it).
const UNDER_UP := {&"hips": Vector3(-24, 0, 0), &"head": Vector3(-14, 0, 0), &"jaw": Vector3(30, 0, 0), &"root": Vector3(0, -1.1, 0)}
## Bursting up out of the bedding: stood up tall, forepaws up and claws out,
## mouth wide.
const BURST := {&"hips": Vector3(-24, 0, 0), &"spine": Vector3(-6, 0, 0), &"neck": Vector3(-4, 0, 0), &"head": Vector3(-14, 0, 0),
	&"jaw": Vector3(45, 0, 0), &"tail": Vector3(30, 0, 0), &"l_upper_arm": Vector3(-80, 0, 40), &"r_upper_arm": Vector3(-80, 0, -40),
	&"l_lower_arm": Vector3(-20, 0, 0), &"r_lower_arm": Vector3(-20, 0, 0), &"l_upper_leg": Vector3(48, 0, 0), &"r_upper_leg": Vector3(48, 0, 0),
	&"l_lower_leg": Vector3(-40, 0, 0), &"r_lower_leg": Vector3(-40, 0, 0), &"l_ear": Vector3(-30, 0, 0), &"r_ear": Vector3(-30, 0, 0),
	&"root": Vector3(0, 0.09, 0)}
## Sat down hard on its rump (a crash): legs out in front of it, arms out,
## head lolling.
const SAT := {&"hips": Vector3(-34, 0, 0), &"spine": Vector3(6, 0, 0), &"chest": Vector3(8, 0, 0), &"neck": Vector3(10, 0, 0),
	&"head": Vector3(6, 0, 0), &"jaw": Vector3(24, 0, 0), &"tail": Vector3(30, 0, 0), &"l_upper_leg": Vector3(-20, 0, -14),
	&"r_upper_leg": Vector3(-20, 0, 14), &"l_lower_leg": Vector3(-40, 0, 0), &"r_lower_leg": Vector3(-40, 0, 0), &"l_foot": Vector3(-30, 0, 0),
	&"r_foot": Vector3(-30, 0, 0), &"l_upper_arm": Vector3(-10, 0, 30), &"r_upper_arm": Vector3(-10, 0, -30), &"root": Vector3(0, 0.049, 0)}
## Washing its face (coming round): sat up, head down a little, both
## forepaws up at its nose.
const WASH := {&"hips": Vector3(-6, 0, 0), &"neck": Vector3(10, 0, 0), &"head": Vector3(16, 0, 0), &"jaw": Vector3(8, 0, 0),
	&"l_upper_arm": Vector3(-62, 0, -8), &"r_upper_arm": Vector3(-62, 0, 8), &"l_lower_arm": Vector3(-40, 0, 0), &"r_lower_arm": Vector3(-40, 0, 0),
	&"l_hand": Vector3(-20, 0, 0), &"r_hand": Vector3(-20, 0, 0), &"root": Vector3(0, 0.01, 0)}

# Going down for good, rolling over onto its side. (Its hips' turn there is
# the on-all-fours pitch and then the roll about its length, as one turn:
# Basis.from_euler's order can't say "pitch, then roll" any other way.)

## Its front end gone from under it, its chin in the bedding, rump still up.
const BUCKLE := {&"hips": Vector3(64, 0, 0), &"spine": Vector3(6, 0, 0), &"chest": Vector3(6, 0, 0), &"neck": Vector3(-6, 0, 0),
	&"head": Vector3(-30, 0, 0), &"jaw": Vector3(14, 0, 0), &"tail": Vector3(-45, 0, 0), &"l_upper_leg": Vector3(-40, 0, 0),
	&"r_upper_leg": Vector3(-40, 0, 0), &"l_lower_leg": Vector3(30, 0, 0), &"r_lower_leg": Vector3(30, 0, 0), &"l_upper_arm": Vector3(40, 0, 0),
	&"r_upper_arm": Vector3(40, 0, 0), &"l_lower_arm": Vector3(-50, 0, 0), &"r_lower_arm": Vector3(-50, 0, 0), &"root": Vector3(0, 0.07, 0.02)}
## Half over, going onto its right side.
const ROLLING := {&"hips": Vector3(45.2, 35.5, 45.2), &"spine": Vector3(4, 0, 0), &"chest": Vector3(6, 0, 0), &"neck": Vector3(-4, 0, 0),
	&"head": Vector3(-12, 0, 8), &"jaw": Vector3(30, 0, 0), &"tail": Vector3(-45, 0, 0), &"l_upper_leg": Vector3(-36, 0, 10),
	&"r_upper_leg": Vector3(-36, 0, 0), &"l_upper_arm": Vector3(-20, 0, 20), &"r_upper_arm": Vector3(-20, 0, 0), &"root": Vector3(0, 0.02, 0)}
## Down on its side, its legs out stiff (the throes).
const THROES := {&"hips": Vector3(8.2, 54.6, 84.2), &"spine": Vector3(2, 0, 0), &"neck": Vector3(-8, 0, 0), &"head": Vector3(-16, 0, 10),
	&"jaw": Vector3(38, 0, 0), &"tail": Vector3(-40, 0, 0), &"l_upper_leg": Vector3(-50, 0, -10), &"r_upper_leg": Vector3(-50, 0, -10),
	&"l_lower_leg": Vector3(-10, 0, 0), &"r_lower_leg": Vector3(-10, 0, 0), &"l_upper_arm": Vector3(-50, 0, -10), &"r_upper_arm": Vector3(-50, 0, -10),
	&"root": Vector3(0, -0.01, 0)}
## Gone: limp on its side, its legs fallen slack, its jaw hanging.
const DEAD := {&"hips": Vector3(8.2, 54.6, 84.2), &"spine": Vector3(0, 0, 4), &"chest": Vector3(0, 0, 4), &"neck": Vector3(-4, 0, 6),
	&"head": Vector3(-10, 0, 16), &"jaw": Vector3(26, 0, 0), &"tail": Vector3(-36, 0, 0), &"l_upper_leg": Vector3(-24, 0, -40),
	&"r_upper_leg": Vector3(-40, 0, -6), &"l_lower_leg": Vector3(16, 0, 0), &"r_lower_leg": Vector3(8, 0, 0), &"l_upper_arm": Vector3(-30, 0, -40),
	&"r_upper_arm": Vector3(-36, 0, -6), &"l_lower_arm": Vector3(20, 0, 0), &"r_lower_arm": Vector3(10, 0, 0), &"root": Vector3(0, -0.02, 0)}

var _puddles: Array = []            # [centre, radius, until]
var _slowed: Dictionary = {}        # Critter -> true (in the foam: slow_factor down)
var _foam_t := 0.0                  # (foam dripping from its mouth, a drop at a time)
var _burn_t := 0.0
var _fours := 0.0                   # (how far down on all fours it is: 1 scurrying, 0 sat up on its haunches)
var _still_t := 0.0                 # (how long it's stood still)
var _walked := 0.0                  # (how long it's been scurrying since it last stopped)
var _sniff_after := 5.0
var _turn := 0.0                    # (how fast it's turning, rad/s, smoothed: its body bends into it)
var _last_yaw := 0.0
var _tic_at := -10.0                # (rabid: a jerk of its head now and then)
var _tic_next := 2.0
var _tic := Vector3.ZERO


func _init() -> void:
	super()
	id = "hamster"
	from_below = true
	display_name = "Nibbles"
	title = "the Rabid"
	base_health = 32000.0
	walk_speed = 12.0
	turn_speed = 1.9
	weak_spots = {&"head": 2.0, &"jaw": 2.0}
	limb_scale = 0.75
	solid_roles = [&"hips", &"spine", &"chest", &"neck"]
	blend_from_pose = true   # (each move flows on from wherever it was)
	_sniff_after = randf_range(SNIFF_EVERY.x, SNIFF_EVERY.y)


func stride() -> float:
	return 0.1


## Its paws pattering down: a thump, not a giant's boots.
func _footstep() -> void:
	Audio.play_at(step_sound(), global_position, -12.0, 0.15, {"max_distance": 260.0, "unit_size": 16.0})
	Events.explosion.emit(global_position, 3.0)


## A hamster's scurry: down on all fours, its legs going in diagonal pairs
## (a quick trot), its round body bobbing and rolling with each step and its
## rump wagging, its head held steady. Stood still a moment, it sits up on
## its haunches (_fours).
func walk_pose(phase: float, amount: float) -> Dictionary:
	var f := smoothstep(0.0, 1.0, _fours)
	var out := {}
	for r in FOURS:
		out[r] = (FOURS[r] as Vector3) * f
	var a := minf(amount, 1.3) * f
	if a <= 0.0:
		return out
	# (forward is -x for a leg hanging down; a paw's off the ground as it swings forward)
	for leg in [[&"l_upper_arm", &"l_lower_arm", phase, 26.0, 34.0], [&"r_upper_leg", &"r_lower_leg", phase, 30.0, -30.0],
			[&"r_upper_arm", &"r_lower_arm", phase + PI, 26.0, 34.0], [&"l_upper_leg", &"l_lower_leg", phase + PI, 30.0, -30.0]]:
		var s := sin(float(leg[2]))
		var c := cos(float(leg[2]))
		out[leg[0]] = (out.get(leg[0], Vector3.ZERO) as Vector3) + Vector3(-float(leg[3]) * s * a, 0, 0)
		out[leg[1]] = (out.get(leg[1], Vector3.ZERO) as Vector3) + Vector3(float(leg[4]) * maxf(0.0, c) * a, 0, 0)
	var bob := 0.5 - 0.5 * cos(phase * 2.0)
	out[&"root"] = (out[&"root"] as Vector3) + Vector3(0, 0.012 * bob * a, 0)
	out[&"hips"] = (out[&"hips"] as Vector3) + Vector3(-2.0 * bob * a, 4.0 * sin(phase) * a, 5.0 * sin(phase) * a)
	out[&"spine"] = (out[&"spine"] as Vector3) + Vector3(0, -3.0 * sin(phase) * a, 0)
	out[&"head"] = (out[&"head"] as Vector3) + Vector3(2.0 * bob * a, -2.0 * sin(phase) * a, -3.0 * sin(phase) * a)
	out[&"tail"] = (out[&"tail"] as Vector3) + Vector3(0, 12.0 * sin(phase) * a, 0)
	out[&"l_ear"] = Vector3(-20.0 * a, 0, 0)
	out[&"r_ear"] = Vector3(-20.0 * a, 0, 0)
	return out


## Never still: breathing quick, its nose going, its teeth chattering, its
## ears turning, and now and then a jerk of its head (it's rabid). Turning,
## its head leads and its body bends after it. Sat up with nothing to do, it
## looks round, sniffing the air.
func idle_pose(t: float) -> Dictionary:
	if not alive:
		return {}
	var free := 1.0 - (action.weight() if action else 0.0)
	var breath := sin(t * 2.8)
	var sniff := sin(t * 21.0) * maxf(0.0, sin(t * 1.1))
	var chatter := maxf(0.0, sin(t * 0.7 + 1.0))
	var bend := clampf(_turn * 5.0, -12.0, 12.0) * free
	var out := {&"chest": Vector3(2.0 * breath, bend * 0.5, 0), &"spine": Vector3(-1.0 * breath, bend * 0.7, 0),
		&"neck": Vector3(0, bend * 0.6, 0), &"head": Vector3(2.0 * sniff - 1.0 * breath, bend + 3.0 * sin(t * 0.9), 0),
		&"jaw": Vector3(3.0 + 10.0 * absf(sin(t * 13.0)) * chatter, 0, 0),
		&"l_ear": Vector3(-6.0 * maxf(0.0, sin(t * 0.6)), 0, 8.0 * sniff), &"r_ear": Vector3(-6.0 * maxf(0.0, sin(t * 0.6 + 2.0)), 0, -8.0 * sniff)}
	var up := (1.0 - smoothstep(0.0, 1.0, _fours)) * free
	if up > 0.0:   # (sat up: nose in the air, looking round)
		out[&"head"] = (out[&"head"] as Vector3) + Vector3(-12.0 + 4.0 * sniff, 24.0 * sin(t * 0.7), 4.0 * sin(t * 0.5)) * up
		out[&"neck"] = (out[&"neck"] as Vector3) + Vector3(-6.0, 10.0 * sin(t * 0.7 - 0.4), 0) * up
		out[&"l_ear"] = (out[&"l_ear"] as Vector3) + Vector3(14.0, 0, 0) * up
		out[&"r_ear"] = (out[&"r_ear"] as Vector3) + Vector3(14.0, 0, 0) * up
	var k := t - _tic_at
	if k >= 0.0 and k < 0.7:   # (rabid: a jerk of its head, there and gone)
		var env := clampf(k / 0.05, 0.0, 1.0) * exp(-maxf(0.0, k - 0.05) * 8.0)
		out[&"head"] = (out[&"head"] as Vector3) + _tic * env
		out[&"neck"] = (out[&"neck"] as Vector3) + _tic * env * 0.5
		out[&"l_ear"] = (out[&"l_ear"] as Vector3) + Vector3(0, 0, 14.0) * env
	return out


func eye_color(angry: bool) -> Color:
	return Color(1.0, 0.0, 0.0) if angry else Color(0.95, 0.08, 0.04)


func enrage_line() -> String:
	return "Frothing mad: it can tunnel under the bedding now. Keep moving."


func attack_name(what: StringName) -> String:
	return {&"charge": "Frenzied Charge", &"bite": "Rabid Bite", &"foam": "Rabid Foam", &"burrow": "Ambush",
		&"screech": "Screech", &"landing": "Landing"}.get(what, super(what))


func _physics_process(delta: float) -> void:
	var dyaw := wrapf(rotation.y - _last_yaw, -PI, PI)
	if delta > 0.0 and absf(dyaw) < 0.5:   # (not a jump round on arriving)
		_turn = lerpf(_turn, dyaw / delta, IKMath.damp(6.0, delta))
	_last_yaw = rotation.y
	if alive and action == null:
		_still_t = _still_t + delta if _speed < 2.0 else 0.0
		if _speed >= 2.0:   # (off: down on all fours)
			_fours = move_toward(_fours, 1.0, delta / 0.3)
		elif _still_t > SIT_AFTER:   # (stopped a moment: sitting up)
			_fours = move_toward(_fours, 0.0, delta / 0.45)
		if _speed > 3.0:
			_walked += delta
	if _clock >= _tic_next:
		_tic_next = _clock + randf_range(1.2, 3.5) * (0.6 if enraged else 1.0)
		_tic_at = _clock
		_tic = Vector3(randf_range(-12, 12), randf_range(-26, 26), randf_range(-14, 14))
	super(delta)
	if not alive:
		return
	_foam_t -= delta
	if _foam_t <= 0.0 and state != State.WAITING and visible:
		_foam_t = 0.35
		FX.burst(mouth_position(), Vector3.DOWN, {"amount": 5, "lifetime": 1.4, "speed": Vector2(0.5, 2.5), "spread": 40.0,
			"gravity": 9.0, "size": 0.7, "scale": Vector2(0.5, 1.4), "color": Color(0.95, 0.97, 0.9, 0.9), "fade": true, "aabb": 30.0})
	_tend_puddles(delta)


## A move done: it's down on all fours after most (some leave it sat up).
func _action_done(a: BossAction) -> void:
	_fours = float(a.data.get("fours", 1.0))
	_walked = 0.0
	super(a)


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
	if not enraged and _walked >= _sniff_after and d > 30.0:
		return _sniff()
	return null


## It stops, sits up on its haunches and sniffs the air, looking round
## (nose going, whiskers, ears up), and drops back down to go on.
func _sniff() -> BossAction:
	_walked = 0.0
	_sniff_after = randf_range(SNIFF_EVERY.x, SNIFF_EVERY.y)
	var a := BossAction.new(&"sniff", 1.6)
	a.flow = true
	a.blend_in = 0.3   # (from however it was to sat up)
	a.blend_out = 0.25
	var up := {&"neck": Vector3(-8, 0, 0), &"head": Vector3(-14, 0, 0), &"l_ear": Vector3(12, 0, 0), &"r_ear": Vector3(12, 0, 0)}
	a.key(0.32, up).key(0.7, _plus(up, {&"neck": Vector3(0, 14, 0), &"head": Vector3(0, 22, 0)}))
	a.key(1.05, _plus(up, {&"neck": Vector3(0, -12, 0), &"head": Vector3(0, -20, 0)})).key(1.25, up).key(1.6, FOURS)
	a.layer = func(time: float) -> Dictionary:   # (its nose going like mad)
		var w := clampf(minf(time - 0.25, 1.3 - time) / 0.15, 0.0, 1.0)
		return {&"head": Vector3(3.0 * sin(time * TAU * 7.0), 0, 0) * w, &"jaw": Vector3(2.0 * absf(sin(time * TAU * 7.0)), 0, 0) * w}
	return a


# ---- Frenzied Charge -----------------------------------------------------------------------------

## Head down, rump up and wiggling, a forepaw raking the bedding; then off,
## galloping flat out (_gallop), and pulling up short at the end, forepaws
## braced (or straight into a wall: _crash).
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
	var stop_at := wind + run / CHARGE_SPEED
	var a := BossAction.new(&"charge", stop_at + 0.6)
	a.interruptible = false
	a.flow = true
	a.key(0.0, FOURS).key(wind * 0.35, CROUCH).key(wind * 0.85, _plus(CROUCH, {&"hips": Vector3(6, 0, 0), &"root": Vector3(0, 0.02, -0.02)}))
	a.key(wind, _plus(LOW, {&"hips": Vector3(-8, 0, 0), &"long": Vector3(0.04, 0, 0)})).key(wind + 0.25, LOW).key(stop_at, LOW)
	a.key(stop_at + 0.2, SKID).key(stop_at + 0.45, FOURS).key(a.length, FOURS)
	a.layer = func(time: float) -> Dictionary:
		if time < wind:   # (its rump wiggling, a forepaw raking the bedding)
			var w := sin(PI * clampf(time / wind, 0.0, 1.0))
			var s := sin(time * TAU * 4.5)
			var rake := maxf(0.0, sin(time * TAU * 3.0))
			return {&"hips": Vector3(0, 7.0 * s, 4.0 * s) * w, &"spine": Vector3(0, -6.0 * s, 0) * w, &"tail": Vector3(0, -14.0 * s, 0) * w,
				&"r_upper_arm": Vector3(28.0 * rake, 0, 0) * w, &"r_lower_arm": Vector3(30.0 * rake, 0, 0) * w}
		if time < stop_at:
			return _gallop((time - wind) * GALLOP_HZ * TAU, clampf(minf(time - wind, stop_at - time) / 0.15, 0.0, 1.0))
		return {}
	var trampled := {}
	var crashed := stop < reach
	a.on(0.0, func():
		warn_strip(global_position, end, CHARGE_HIT * 2.0, wind + run / CHARGE_SPEED)
		Audio.play_at(&"boss_screech", mouth_position(), 10.0, 0.05, {"max_distance": 700.0, "unit_size": 45.0}))
	a.tick = func(time: float, delta: float):
		if time < wind:
			face_toward(global_position + dir, delta, 4.0)
			_speed = 0.0
			if randf() < 0.15:
				BossFX.dust(global_position + forward() * 8.0, 6.0, Color(0.85, 0.8, 0.68, 0.7))
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
	a.on(stop_at, func():
		_speed = 0.0
		if crashed:
			_crash()
		else:
			BossFX.dust(global_position + forward() * 6.0, 14.0, Color(0.85, 0.8, 0.68, 0.8)))
	return a


## Flat out: a bound, its forepaws reaching out together (the left a beat
## ahead) as its hind legs drive back, then gathering under it, its round
## body rocking front to back and stretching out with each stride, bouncing;
## `q` where it is in its stride (radians), `w` how much.
static func _gallop(q: float, w: float) -> Dictionary:
	var s := sin(q)
	var s2 := sin(q - 0.4)
	var c := cos(q)
	var c2 := cos(q - 0.4)
	return {
		&"l_upper_arm": Vector3(-40.0 * s, 0, 0) * w, &"r_upper_arm": Vector3(-40.0 * s2, 0, 0) * w,
		&"l_lower_arm": Vector3(44.0 * maxf(0.0, -c), 0, 0) * w, &"r_lower_arm": Vector3(44.0 * maxf(0.0, -c2), 0, 0) * w,
		&"l_upper_leg": Vector3(40.0 * s, 0, 0) * w, &"r_upper_leg": Vector3(40.0 * s2, 0, 0) * w,
		&"l_lower_leg": Vector3(-30.0 * maxf(0.0, c), 0, 0) * w, &"r_lower_leg": Vector3(-30.0 * maxf(0.0, c2), 0, 0) * w,
		&"hips": Vector3(-8.0 * sin(q + 0.8), 0, 0) * w, &"spine": Vector3(5.0 * s, 0, 0) * w, &"chest": Vector3(-5.0 * s, 0, 0) * w,
		&"head": Vector3(8.0 * sin(q + 0.8), 0, 0) * w, &"tail": Vector3(10.0 * s, 0, 0) * w,
		&"long": Vector3(0.04 * s, 0, 0) * w, &"root": Vector3(0, 0.03 * maxf(0.0, sin(q + 0.5)), 0) * w,
	}


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


## Head first into a wall: it bounces off and sits down hard, dazed (its head
## going round, stars and all), then shakes it off and washes its face. Hit it
## then: it takes 1.6 times as much.
func _crash() -> void:
	var at := global_position + forward() * 8.0 + Vector3.UP * 6.0
	BossFX.chips(at, 2.0, Color(0.85, 0.8, 0.7))
	BossFX.dust(global_position, 18.0)
	Events.explosion.emit(at, 14.0)
	Audio.play_at(&"body_fall", at, 10.0, 0.0, {"max_distance": 500.0, "unit_size": 40.0})
	Audio.play_at(&"boss_stomp", at, 6.0, 0.0, {"max_distance": 500.0, "unit_size": 40.0})
	_cancel_action()
	vulnerable_until = _clock + DAZED
	vulnerable_k = 1.6
	start(_dazed())
	Events.headline.emit("%s is stunned: hit it now!" % display_name)
	Events.announce.emit("NIBBLES IS DAZED!", "It ran into a wall. Hit it now!")


func _dazed() -> BossAction:
	var a := BossAction.new(&"stunned", DAZED)
	a.flow = true
	a.blend_in = 0.06
	var recoil := _plus(LOW, {&"hips": Vector3(-34, 0, 0), &"neck": Vector3(-20, 0, 0), &"head": Vector3(-30, 0, 0), &"jaw": Vector3(20, 0, 0),
		&"root": Vector3(0, 0.0, -0.14)})
	var wash := DAZED - 0.95
	a.key(0.0, LOW).key(0.14, recoil).key(0.42, SAT).key(0.6, _plus(SAT, {&"root": Vector3(0, 0.012, 0)})).key(wash - 0.15, SAT)
	a.key(wash + 0.15, WASH).key(DAZED - 0.38, WASH).key(DAZED, FOURS)
	# dazed: its head going round and round, swaying; then washing its face,
	# its forepaws scrubbing at its nose by turns
	a.layer = func(time: float) -> Dictionary:
		var out := {}
		var w := clampf(minf(time - 0.4, wash - time) / 0.3, 0.0, 1.0)
		if w > 0.0:
			var r := TAU * 0.9 * time
			out = {&"head": Vector3(-7.0 * sin(r), 14.0 * cos(r), 10.0 * sin(r)) * w, &"neck": Vector3(-4.0 * sin(r - 0.5), 6.0 * cos(r - 0.5), 0) * w,
				&"spine": Vector3(0, 0, 5.0 * sin(r * 0.5)) * w, &"chest": Vector3(0, 0, -4.0 * sin(r * 0.5 - 0.6)) * w}
		var v := clampf(minf(time - wash, DAZED - 0.3 - time) / 0.15, 0.0, 1.0)
		if v > 0.0:
			var p := TAU * 4.0 * time
			out = _plus(out, {&"l_upper_arm": Vector3(-14.0 * sin(p), 0, 0), &"r_upper_arm": Vector3(14.0 * sin(p), 0, 0),
				&"l_lower_arm": Vector3(-12.0 * cos(p), 0, 0), &"r_lower_arm": Vector3(12.0 * cos(p), 0, 0),
				&"head": Vector3(4.0 * sin(p * 0.5), 4.0 * sin(p), 0)}, v)
		return out
	var st := {"stars": 0.0}
	a.tick = func(time: float, delta: float):
		st.stars = float(st.stars) - delta
		if time > 0.3 and time < wash and float(st.stars) <= 0.0:
			st.stars = 0.45
			_stars()
	a.on(0.4, func():
		BossFX.dust(global_position, 14.0)
		Audio.play_at(&"body_fall", global_position, 4.0, 0.1, {"max_distance": 400.0, "unit_size": 35.0}))
	return a


# ---- Rabid Bite ----------------------------------------------------------------------------------

## It rears up on its hind legs, forepaws up, jaws wide; throws itself
## forward and down, jaws first, snapping them shut; and worries whatever
## it got, head shaking, before it lets go.
func _bite(t: Critter) -> BossAction:
	cooldown(&"bite", 4.5 if not enraged else 3.0)
	var lunge := 0.55
	var a := BossAction.new(&"bite", lunge + 0.95)
	a.flow = true
	var centre := global_position + forward() * 9.0
	centre.y = ground_y(centre)
	var rear := _plus(TALL, {&"hips": Vector3(-8, 0, 0), &"neck": Vector3(-10, 0, 0), &"head": Vector3(-24, 0, 0), &"jaw": Vector3(42, 0, 0),
		&"l_upper_arm": Vector3(-70, 0, 20), &"r_upper_arm": Vector3(-70, 0, -20), &"l_lower_arm": Vector3(-20, 0, 0), &"r_lower_arm": Vector3(-20, 0, 0),
		&"l_ear": Vector3(-40, 0, 0), &"r_ear": Vector3(-40, 0, 0)})
	var open := _plus(LUNGE, {&"jaw": Vector3(40, 0, 0), &"head": Vector3(-14, 0, 0), &"root": Vector3(0, 0.02, -0.04)})
	a.blend_in = 0.3   # (rearing up from however it was)
	a.key(lunge * 0.72, rear).key(lunge * 0.9, open).key(lunge, LUNGE)
	a.key(lunge + 0.12, _plus(LUNGE, {&"head": Vector3(4, 0, 0), &"jaw": Vector3(-2, 0, 0)})).key(lunge + 0.55, _plus(LUNGE, {&"head": Vector3(2, 0, 0)}))
	a.key(lunge + 0.8, FOURS).key(a.length, FOURS)
	a.layer = func(time: float) -> Dictionary:   # (worrying it: its head shaking side to side)
		var w := clampf(minf(time - lunge - 0.08, lunge + 0.6 - time) / 0.1, 0.0, 1.0)
		if w <= 0.0:
			return {}
		var s := sin((time - lunge) * TAU * 4.5)
		return {&"head": Vector3(0, 18.0 * s, 10.0 * s) * w, &"neck": Vector3(0, 10.0 * s, 0) * w, &"hips": Vector3(0, 0, -3.0 * s) * w}
	a.on(0.0, func(): warn(centre, BITE_RADIUS, lunge))
	a.tick = func(time: float, delta: float):
		if time < lunge and is_instance_valid(t) and t.alive:
			face_toward(t.global_position, delta, 3.5)
	a.on(lunge, func():
		for c in foes_near(centre, BITE_RADIUS):
			hurt(c, 80.0, forward(), 10.0, 6.0, &"bite", DamageInfo.Kind.MELEE, 0.9)
		BossFX.dust(centre, 10.0)
		Audio.play_at(&"melee_hit", mouth_position(), 10.0, 0.05, {"max_distance": 300.0, "unit_size": 25.0}))
	return a


# ---- Foam Spit -----------------------------------------------------------------------------------

## It sits up and heaves (once, twice: bringing up the foam), and spits it
## at you with a toss of its head.
func _spit(t: Critter) -> BossAction:
	cooldown(&"spit", 8.0)
	var a := BossAction.new(&"spit", 1.9)
	a.flow = true
	var back := {&"hips": Vector3(-6, 0, 0), &"neck": Vector3(-14, 0, 0), &"head": Vector3(-26, 0, 0), &"jaw": Vector3(8, 0, 0),
		&"l_upper_arm": Vector3(-20, 0, 10), &"r_upper_arm": Vector3(-20, 0, -10)}
	var spat := {&"hips": Vector3(8, 0, 0), &"spine": Vector3(6, 0, 0), &"chest": Vector3(4, 0, 0), &"neck": Vector3(2, 0, 0),
		&"head": Vector3(4, 0, 0), &"jaw": Vector3(44, 0, 0), &"l_upper_arm": Vector3(20, 0, 14), &"r_upper_arm": Vector3(20, 0, -14),
		&"root": Vector3(0, 0, 0.03)}
	a.blend_in = 0.3
	a.key(0.3, {}).key(0.62, back).key(0.85, spat).key(1.15, _plus(spat, {&"jaw": Vector3(-24, 0, 0), &"head": Vector3(-6, 0, 0)}))
	a.key(1.45, {}).key(1.9, FOURS)
	a.layer = func(time: float) -> Dictionary:
		if time < 0.8:   # (heaving: its chest pumping, bringing it up)
			var w := clampf(minf(time - 0.2, 0.8 - time) / 0.12, 0.0, 1.0)
			var h := maxf(0.0, sin((time - 0.2) * TAU * 3.4))
			return {&"chest": Vector3(9.0 * h, 0, 0) * w, &"spine": Vector3(6.0 * h, 0, 0) * w, &"neck": Vector3(-8.0 * h, 0, 0) * w,
				&"jaw": Vector3(12.0 * h, 0, 0) * w}
		var w2 := clampf(minf(time - 0.9, 1.35 - time) / 0.08, 0.0, 1.0)   # (a shake of its head: foam flying)
		return {&"head": Vector3(0, 14.0 * sin((time - 0.9) * TAU * 5.0), 0) * w2}
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

## It digs like mad (forepaws scooping by turns, hind legs kicking the bedding
## back), dives in nose first, tunnels after you, and bursts up under you:
## stood up tall, claws out, shaking the bedding off.
func _burrow(t: Critter) -> BossAction:
	cooldown(&"burrow", 16.0)
	var dive := 1.0
	var travel := clampf(global_position.distance_to(t.global_position) / 26.0, 1.2, 7.0)
	var rise := 0.9
	var up_at := dive + travel + rise
	var a := BossAction.new(&"burrow", up_at + 1.4)
	a.interruptible = false
	a.flow = true
	a.key(0.0, FOURS).key(0.18, DIG).key(0.72, DIG).key(0.86, _plus(DIG, {&"hips": Vector3(16, 0, 0), &"root": Vector3(0, -0.3, 0.08)}))
	a.key(dive, UNDER).key(up_at - rise * 0.7, UNDER).key(up_at - rise * 0.45, UNDER_UP).key(up_at, BURST)
	a.key(up_at + 0.55, _plus(BURST, {&"l_upper_arm": Vector3(40, 0, -20), &"r_upper_arm": Vector3(40, 0, 20), &"jaw": Vector3(-25, 0, 0)}))
	a.key(up_at + 1.0, {}).key(a.length, FOURS)
	a.layer = func(time: float) -> Dictionary:
		if time < dive:   # (digging: forepaws scooping by turns, hind legs kicking it back)
			var w := clampf(minf(time - 0.12, 0.84 - time) / 0.1, 0.0, 1.0)
			var p := time * TAU * 6.0
			var k := time * TAU * 3.0
			return {&"l_upper_arm": Vector3(36.0 * sin(p), 0, 0) * w, &"r_upper_arm": Vector3(36.0 * sin(p + PI), 0, 0) * w,
				&"l_lower_arm": Vector3(30.0 * maxf(0.0, cos(p)), 0, 0) * w, &"r_lower_arm": Vector3(30.0 * maxf(0.0, -cos(p)), 0, 0) * w,
				&"l_upper_leg": Vector3(30.0 * maxf(0.0, sin(k)), 0, 0) * w, &"r_upper_leg": Vector3(30.0 * maxf(0.0, -sin(k)), 0, 0) * w,
				&"hips": Vector3(0, 0, 4.0 * sin(k)) * w, &"head": Vector3(6.0 * sin(p * 0.5), 0, 0) * w}
		return _shake(time - up_at - 0.5)
	var state_ := {"at": t.global_position, "warned": false, "trail": 0.0, "fling": 0.0}
	a.on(dive, func(): _set_hittable(false))
	a.tick = func(time: float, delta: float):
		if time < dive:
			state_.fling = float(state_.fling) - delta
			if time > 0.15 and float(state_.fling) <= 0.0:   # (bedding flung out behind it)
				state_.fling = 0.18
				var back := -forward()
				FX.burst(global_position - forward() * 6.0 + Vector3.UP * 3.0, (back + Vector3.UP * 0.7).normalized(), {"amount": 14,
					"lifetime": 1.1, "speed": Vector2(8.0, 18.0), "spread": 30.0, "gravity": 14.0, "size": 0.8, "scale": Vector2(0.5, 1.4),
					"color": Color(0.88, 0.82, 0.68), "fade": false, "shape": "chip", "aabb": 40.0})
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
	a.on(up_at, func():
		_set_hittable(true)
		hurt_ring(global_position, BURROW_RADIUS, 90.0, 25.0, 14.0, 14.0, &"burrow")
		BossFX.shockwave(global_position, BURROW_RADIUS)
		BossFX.chips(global_position, 2.5, Color(0.88, 0.82, 0.68))
		Events.explosion.emit(global_position, BURROW_RADIUS))
	a.data["cancel"] = func(): _set_hittable(true)
	return a


## Shaking the bedding off, `t` seconds in: a shudder that runs through it
## from its head to its rump, side to side, its ears flapping, gone in about
## half a second.
static func _shake(t: float) -> Dictionary:
	if t <= 0.0 or t >= 0.55:
		return {}
	var env := sin(PI * t / 0.55)
	var out := {}
	var chain := [&"head", &"neck", &"chest", &"spine", &"hips"]
	for k in chain.size():
		var ph := TAU * 6.0 * t - k * 0.8
		out[chain[k]] = Vector3(0, 10.0 * sin(ph), 8.0 * sin(ph + 0.6)) * env * (0.5 if chain[k] == &"hips" else 1.0)
	out[&"l_ear"] = Vector3(0, 0, 22.0 * sin(TAU * 6.0 * t)) * env
	out[&"r_ear"] = Vector3(0, 0, -22.0 * sin(TAU * 6.0 * t)) * env
	return out


## The screech (enraged): stood up tall, claws out, mouth wide, shaking with
## rage; everyone near is blown back.
func _roar_action() -> BossAction:
	var a := BossAction.new(&"screech", 2.0)
	a.flow = true
	var pose := _plus(TALL, {&"hips": Vector3(-6, 0, 0), &"neck": Vector3(-10, 0, 0), &"head": Vector3(-22, 0, 0), &"jaw": Vector3(46, 0, 0),
		&"l_upper_arm": Vector3(-78, 0, 42), &"r_upper_arm": Vector3(-78, 0, -42), &"l_lower_arm": Vector3(-24, 0, 0), &"r_lower_arm": Vector3(-24, 0, 0),
		&"l_ear": Vector3(-45, 0, 0), &"r_ear": Vector3(-45, 0, 0)})
	a.blend_in = 0.3
	a.key(0.32, _plus(pose, {&"head": Vector3(10, 0, 0), &"jaw": Vector3(-20, 0, 0)})).key(0.5, pose).key(1.5, pose)
	a.key(1.75, {}).key(2.0, FOURS)
	a.layer = func(time: float) -> Dictionary:   # (shaking with rage as it screeches)
		var w := clampf(minf(time - 0.45, 1.55 - time) / 0.1, 0.0, 1.0)
		if w <= 0.0:
			return {}
		var s := sin(time * TAU * 13.0)
		return {&"head": Vector3(2.5 * s, 3.0 * sin(time * TAU * 9.0), 0) * w, &"chest": Vector3(1.5 * s, 0, 0) * w,
			&"jaw": Vector3(4.0 * sin(time * TAU * 17.0), 0, 0) * w, &"l_upper_arm": Vector3(4.0 * s, 0, 0) * w, &"r_upper_arm": Vector3(-4.0 * s, 0, 0) * w}
	a.on(0.5, func():
		hurt_ring(global_position, 36.0, 12.0, 4.0, 11.0, 6.0, &"screech", false)
		Events.explosion.emit(mouth_position(), 26.0)
		BossFX.dust(global_position, 28.0)
		Audio.play_at(&"boss_screech", mouth_position(), 14.0, 0.0, {"max_distance": 900.0, "unit_size": 60.0}))
	return a


# ---- arriving, and going down -------------------------------------------------------------------

## It bursts up out of the bedding, shakes it off, and sits up to have a look
## round (then it screeches: Boss.show_off).
func _entrance() -> BossAction:
	var a := BossAction.new(&"entrance", land_time + 1.4)
	a.interruptible = false
	a.flow = true
	a.key(0.0, UNDER_UP).key(land_time - 0.6, UNDER_UP).key(land_time, BURST).key(land_time + 0.45, _plus(BURST, {&"l_upper_arm": Vector3(40, 0, -20),
		&"r_upper_arm": Vector3(40, 0, 20), &"jaw": Vector3(-25, 0, 0)})).key(land_time + 1.0, {}).key(land_time + 1.4, {})
	a.layer = func(time: float) -> Dictionary: return _shake(time - land_time - 0.4)
	a.data["fours"] = 0.0   # (sat up, looking round)
	a.on(0.0, func(): warn(global_position, 26.0, land_time))
	a.tick = func(time: float, _delta: float):
		if time < land_time - 0.2 and randf() < 0.3:
			BossFX.dust(global_position + Vector3(randf_range(-8, 8), 0, randf_range(-8, 8)), 10.0, Color(0.85, 0.8, 0.68, 0.7))
	a.on(land_time, func():
		hurt_ring(global_position, 26.0, 55.0, 10.0, 15.0, 12.0, &"landing")
		BossFX.shockwave(global_position, 26.0)
		BossFX.chips(global_position, 3.0, Color(0.88, 0.82, 0.68))
		Events.explosion.emit(global_position, 20.0)
		Audio.play_at(&"boss_screech", mouth_position(), 14.0, 0.0, {"max_distance": 900.0, "unit_size": 60.0})
		Audio.play_at(&"boss_stomp", global_position, 4.0, 0.0, {"max_distance": 700.0, "unit_size": 40.0}))
	return a


## It rears up with a last screech, staggers, its front end goes out from
## under it, and it rolls over onto its side, its legs kicking (weaker, and
## weaker), and then it's still.
func _death_action() -> BossAction:
	for c in _slowed.keys():
		if is_instance_valid(c):
			(c as Critter).slow_factor = 1.0
	_slowed.clear()
	var a := BossAction.new(&"death", 3.6)
	a.blend_out = 0.0
	a.interruptible = false
	a.flow = true
	var shriek := _plus(TALL, {&"hips": Vector3(-8, 0, 0), &"neck": Vector3(-14, 0, 0), &"head": Vector3(-30, 0, 0), &"jaw": Vector3(46, 0, 0),
		&"l_upper_arm": Vector3(-74, 0, 36), &"r_upper_arm": Vector3(-74, 0, -36), &"l_ear": Vector3(-40, 0, 0), &"r_ear": Vector3(-40, 0, 0)})
	var stagger := _plus(TALL, {&"hips": Vector3(-4, 10, 14), &"spine": Vector3(0, 0, 6), &"neck": Vector3(6, 14, 10), &"head": Vector3(10, 18, 14),
		&"jaw": Vector3(36, 0, 0), &"l_upper_arm": Vector3(-40, 0, 40), &"r_upper_arm": Vector3(-20, 0, -10), &"l_upper_leg": Vector3(0, 0, -10)})
	a.blend_in = 0.3
	a.key(0.35, shriek).key(0.85, stagger).key(1.25, BUCKLE).key(1.6, ROLLING).key(1.9, THROES)
	a.key(2.9, THROES).key(3.6, DEAD)
	# the throes: its legs kicking and paddling (weaker and weaker), a
	# shudder through it, its jaw working; and its last breath
	a.layer = func(time: float) -> Dictionary:
		var w := clampf((time - 1.85) / 0.1, 0.0, 1.0) * clampf((3.2 - time) / 1.2, 0.0, 1.0)
		if w <= 0.0:
			return {}
		var p := (time - 1.9) * TAU * 3.2
		return {&"l_upper_leg": Vector3(26.0 * sin(p), 0, 0) * w, &"r_upper_leg": Vector3(22.0 * sin(p + 2.2), 0, 0) * w,
			&"l_lower_leg": Vector3(-20.0 * maxf(0.0, sin(p + 0.8)), 0, 0) * w, &"r_lower_leg": Vector3(-18.0 * maxf(0.0, sin(p + 3.0)), 0, 0) * w,
			&"l_upper_arm": Vector3(18.0 * sin(p + 1.3), 0, 0) * w, &"r_upper_arm": Vector3(14.0 * sin(p + 3.5), 0, 0) * w,
			&"spine": Vector3(0, 0, 3.0 * sin(p * 1.7)) * w, &"head": Vector3(4.0 * sin(p * 1.3), 0, 0) * w,
			&"jaw": Vector3(10.0 * absf(sin(p * 0.7)), 0, 0) * w}
	a.on(1.9, func():
		BossFX.shockwave(global_position, HEIGHT)
		Events.explosion.emit(global_position, 20.0)
		Audio.play_at(&"body_fall", global_position, 12.0, 0.0, {"max_distance": 600.0, "unit_size": 50.0}))
	return a


func _fallen() -> void:
	if gore_ok:
		FX.gore_burst(mouth_position(), 2.5, Color(0.85, 0.6, 0.3))
