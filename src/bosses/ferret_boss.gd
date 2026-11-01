class_name FerretBoss
extends Boss
## Noodle, the Burrow Hunter: the Hamster Cage's other boss (a Boss Battle's
## other choice there, Settings "boss"), the House's pet ferret, sable brown
## with a bandit's mask, grown as long as the Big Wheel is wide on Nibbles's
## larder (the Ferret model, rigged: assets/bosses/ferret/, her jaw opening on
## fangs and a tongue). Ferrets were bred to go down rabbit holes. She goes
## down the hamster's.
##   Pop Goes the Weasel: she digs in (flinging bedding at whoever's behind
##     her), and a music box tinkles the old rhyme under the bedding as she
##     goes: on POP! she comes up under whoever she's after, out of the red
##     ring (out of a burrow, if there's one near), stands up out of her hole
##     to look round, and goes down again for the next. Bop her on the nose
##     while she's up (enough, and she's dizzy: out of the hole and down).
##   Weasel War Dance: back arched, mouth open, dooking, she hops sideways at
##     you, each landing on its own red ring, and then she's danced herself
##     out: she sleeps like the dead (hit her!), and wakes with a poof of
##     musk that stings whoever's still close.
##   Lunge: up close she coils back and strikes along a red strip, jaws
##     first, and shakes whatever she catches.
## Enraged: more pops, quicker hops, a quicker lunge.

const POP_R := 12.0                 ## her coming up out of the ground: everyone in this ring goes flying
const POPS := 3                     ## times she comes up, per Pop Goes the Weasel (enraged: POPS_ENRAGED)
const POPS_ENRAGED := 5
const TUNE_POP := 2.5               ## seconds into ferret_tune its POP! comes (her first pop, her arrival)
const SHORT_POP := 1.25             ## and into ferret_tune_short (the pops after)
const DIG := 1.0                    ## seconds she digs in for
const UP_FOR := 1.4                 ## seconds she stands up out of a hole, looking round
const DOWN := 0.45                  ## seconds diving back down
const WARN_AT := 1.1                ## how long before a pop its ring shows (it's where she's headed, from then: < SHORT_POP)
const TRAVEL := 30.0                ## m/s under the bedding, following whoever she's after
const BURROW_NEAR := 18.0           ## a burrow's mouth this near where she'd come up: she comes up out of it
const WHACK_AT := 8.0               ## hits on her head while she's up (yours count 1, a bot's 0.15, a blast's 3x) that bop her
const DIZZY_FOR := 5.0
const SPRAY_LEN := 34.0             ## the bedding she flings back as she digs in: a cone behind her
const SPRAY_HALF := 0.6             ## (its half angle, radians)
const HOP_R := 11.0                 ## a War Dance hop landing
const HOPS := 4
const HOPS_ENRAGED := 6
const HOP_LEN := 24.0               ## metres a hop takes her, at most
const SLEEP_FOR := 5.0              ## seconds she sleeps after the dance
const MUSK_R := 16.0
const MUSK_DPS := 14.0
const MUSK_SECONDS := 7.0
const BITE_REACH := 40.0            ## the far end of her lunge's strip (from her middle)
const BITE_FROM := 12.0             ## its near end
const BITE_W := 11.0
const LUNGE := 10.0                 ## metres the lunge carries her
const BEDDING := Color(0.86, 0.79, 0.62)

## Down in the ground: her nose dipped, all of her under the floor.
const UNDER := {&"root": Vector3(0, -1.4, 0), &"hips": Vector3(35, 0, 0), &"head": Vector3(10, 0, 0)}
## Stood up out of a hole (Pop Goes the Weasel): upright from the hips, her
## head level, forepaws dangling, the rest of her still down the hole.
const POPPED := {&"root": Vector3(0, -0.95, 0), &"hips": Vector3(-78, 0, 0), &"neck": Vector3(30, 0, 0), &"head": Vector3(42, 0, 0),
	&"jaw": Vector3(12, 0, 0), &"l_upper_arm": Vector3(62, 0, 0), &"r_upper_arm": Vector3(62, 0, 0),
	&"l_lower_arm": Vector3(-35, 0, 0), &"r_lower_arm": Vector3(-35, 0, 0)}
## Reared up on her hind legs (her roar, her arrival): the hind legs and tail
## kept on the ground.
const REARED := {&"root": Vector3(0, -0.11, 0), &"hips": Vector3(-40, 0, 0), &"chest": Vector3(-4, 0, 0),
	&"l_upper_leg": Vector3(38, 0, 0), &"r_upper_leg": Vector3(38, 0, 0), &"tail": Vector3(32, 0, 0), &"neck": Vector3(20, 0, 0),
	&"head": Vector3(24, 0, 0), &"jaw": Vector3(38, 0, 0), &"l_upper_arm": Vector3(40, 0, 0), &"r_upper_arm": Vector3(40, 0, 0),
	&"l_lower_arm": Vector3(-40, 0, 0), &"r_lower_arm": Vector3(-40, 0, 0), &"l_ear": Vector3(-20, 0, 0), &"r_ear": Vector3(-20, 0, 0)}
## The War Dance: back arched high, head up, mouth open, tail up.
const ARCH := {&"hips": Vector3(-20, 0, 0), &"chest": Vector3(34, 0, 0), &"neck": Vector3(-14, 0, 0), &"head": Vector3(-12, 0, 0),
	&"jaw": Vector3(34, 0, 0), &"tail": Vector3(40, 0, 0), &"l_upper_arm": Vector3(-14, 0, 0), &"r_upper_arm": Vector3(-14, 0, 0),
	&"l_upper_leg": Vector3(20, 0, 0), &"r_upper_leg": Vector3(20, 0, 0), &"root": Vector3(0, 0.05, 0)}
## Out cold on her right side (asleep after the dance, dizzy, beaten).
const FLOPPED := {&"root": Vector3(0, -0.28, 0), &"hips": Vector3(0, 0, 82), &"spine": Vector3(0, 10, 0), &"chest": Vector3(0, 12, 0),
	&"neck": Vector3(0, 10, 6), &"head": Vector3(-6, 8, 6), &"l_upper_arm": Vector3(-25, 0, 0), &"r_upper_arm": Vector3(-35, 0, 0),
	&"l_upper_leg": Vector3(20, 0, 0), &"r_upper_leg": Vector3(30, 0, 0), &"tail": Vector3(8, 0, -80)}   # (her tail rolled back flat)

var _under := false                 # down in the ground (Pop Goes the Weasel): not there to hit
var _popped := false                # stood up out of a hole: bop her on the nose
var _whacks := 0.0                  # (hits on her head while she's up)
var _asleep := false                # danced out, and fast asleep
var _dizzy := false                 # bopped, and seeing stars
var _clouds: Array = []             # [centre, radius, until]: her musk
var _musk_t := 0.0
var _dook_t := 4.0                  # (a chatter now and then, walking)
var _fell_from := &""               # (beaten while &"popped" up out of a hole, or &"flopped" asleep or dizzy)


func _init() -> void:
	super()
	id = "ferret"
	display_name = "Noodle"
	title = "the Burrow Hunter"
	from_below = true
	land_time = TUNE_POP
	base_health = 32000.0
	walk_speed = 13.0
	turn_speed = 2.2
	weak_spots = {&"head": 2.0, &"jaw": 2.0}
	limb_scale = 0.7
	solid_roles = [&"hips", &"spine", &"chest", &"neck"]


func stride() -> float:
	return 0.34


## Her eyes, lit violet: hot pink when she's angry, dark while she's asleep
## or down in the ground.
func eye_color(angry: bool) -> Color:
	return Color(1.0, 0.2, 0.55) if angry else Color(0.72, 0.38, 1.0)


func _tend_eyes() -> void:
	super()
	if _asleep or _under:
		for m in _eye_skin:
			m.emission_energy_multiplier = 0.0


func enrage_line() -> String:
	return "She's had enough: more pops, quicker hops. Bop her on the nose when she comes up."


func attack_name(what: StringName) -> String:
	return {&"pop": "Pop Goes the Weasel", &"spray": "Bedding Spray", &"dance": "Weasel War Dance", &"musk": "Musk",
		&"bite": "Lunge", &"hiss": "Bottle-Brush", &"landing": "Pop!"}.get(what, super(what))


## Up out of a hole, her nose is what to hit (bop it: WHACK_AT).
func role_scale(role: StringName) -> float:
	if _popped and role in [&"head", &"jaw"]:
		return 3.0
	return super(role)


func step_sound() -> StringName:
	return &"boss_stomp"


## Her paws coming down: lighter than a giant's boots.
func _footstep() -> void:
	Audio.play_at(step_sound(), global_position, -12.0, 0.15, {"max_distance": 260.0, "unit_size": 16.0})
	Events.explosion.emit(global_position, 3.0)


func _physics_process(delta: float) -> void:
	super(delta)
	_tend_musk(delta)
	if alive and state == State.FIGHTING and action == null and _speed > 3.0:
		_dook_t -= delta
		if _dook_t <= 0.0:
			_dook_t = randf_range(5.0, 9.0)
			Audio.play_at(&"ferret_dook", mouth_position(), 0.0, 0.08, {"max_distance": 420.0, "unit_size": 30.0})


## Her musk stings whoever's standing in it (a bit every half second).
func _tend_musk(delta: float) -> void:
	_clouds = _clouds.filter(func(m): return float(m[2]) > _clock)
	if _clouds.is_empty():
		return
	_musk_t += delta
	if _musk_t < 0.5:
		return
	_musk_t = 0.0
	var stung := {}
	for m in _clouds:
		for c in foes_near(m[0], m[1]):
			if not stung.has(c):
				stung[c] = true
				hurt(c, MUSK_DPS * 0.5, Vector3.UP, 0.0, 0.0, &"musk", DamageInfo.Kind.BLEED, 0.0)


# ---- moving: a ferret's bound --------------------------------------------------------------------

## A ferret's bound: front paws together, then the hind, her back arching and
## stretching out like a slinky, the bob going right through her, and her
## tail flicking along behind.
func walk_pose(phase: float, amount: float) -> Dictionary:
	var s := sin(phase)
	var c := cos(phase)
	return {
		&"l_upper_arm": Vector3(-34.0 * c * amount, 0, 0), &"r_upper_arm": Vector3(-30.0 * cos(phase - 0.35) * amount, 0, 0),
		&"l_lower_arm": Vector3(maxf(0.0, s) * 30.0 * amount, 0, 0), &"r_lower_arm": Vector3(maxf(0.0, sin(phase - 0.35)) * 30.0 * amount, 0, 0),
		&"l_upper_leg": Vector3(34.0 * c * amount, 0, 0), &"r_upper_leg": Vector3(30.0 * cos(phase - 0.35) * amount, 0, 0),
		&"l_lower_leg": Vector3(maxf(0.0, -s) * 28.0 * amount, 0, 0), &"r_lower_leg": Vector3(maxf(0.0, -sin(phase - 0.35)) * 28.0 * amount, 0, 0),
		&"hips": Vector3(-8.0 * s * amount, 0, 0), &"chest": Vector3(10.0 * s * amount, 0, 0), &"head": Vector3(-5.0 * s * amount, 0, 0),
		&"tail": Vector3(12.0 * s * amount, 0, 0), &"tail_tip": Vector3(10.0 * c * amount, 0, 0),
		&"root": Vector3(0, absf(s) * 0.05 * amount, 0),
	}


## Never still: her nose going, her ears turning, her tail swaying, and a
## breath through the whole long length of her.
func idle_pose(t: float) -> Dictionary:
	var sniff := sin(t * 19.0) * maxf(0.0, sin(t * 0.8))
	return {&"head": Vector3(2.5 * sniff, 0, 0), &"chest": Vector3(2.0 * sin(t * 1.6), 0, 0), &"spine": Vector3(-1.5 * sin(t * 1.6), 0, 0),
		&"l_ear": Vector3(0, 0, 6.0 * sin(t * 0.7)), &"r_ear": Vector3(0, 0, -6.0 * sin(t * 0.9)),
		&"tail": Vector3(0, 9.0 * sin(t * 1.1), 0), &"tail_tip": Vector3(0, 14.0 * sin(t * 1.1 - 0.8), 0)}


# ---- choosing --------------------------------------------------------------------------------

func _choose(t: Critter) -> BossAction:
	var d := Vector2(t.global_position.x - global_position.x, t.global_position.z - global_position.z).length()
	var ahead := forward().dot(Vector3(t.global_position.x - global_position.x, 0.0, t.global_position.z - global_position.z).normalized())
	if d > BITE_FROM * 0.6 and d < BITE_REACH - 3.0 and ahead > 0.5 and is_ready(&"bite"):   # (she whips round at them first)
		return _bite(t)
	if d > 30.0 and d < 260.0 and is_ready(&"popgoes"):
		return _pop_goes(t)
	if d > 20.0 and d < 110.0 and is_ready(&"dance"):
		return _dance(t)
	return null


# ---- Pop Goes the Weasel -------------------------------------------------------------------------

## She digs in, and goes after whoever she's after under the bedding, the
## rhyme playing as she goes; on POP! she comes up under them, stands up out
## of her hole to look round, and goes down for the next, POPS times.
func _pop_goes(t: Critter) -> BossAction:
	cooldown(&"popgoes", 18.0)
	var n := POPS_ENRAGED if enraged else POPS
	var up := UP_FOR * (0.8 if enraged else 1.0)
	var pops: Array[float] = [DIG + TUNE_POP]
	for i in range(1, n):
		pops.append(pops[i - 1] + up + DOWN + SHORT_POP)
	var out := 0.9
	var a := BossAction.new(&"popgoes", pops[n - 1] + up + out)
	a.interruptible = false
	a.blend_out = 0.5
	var dig := {&"hips": Vector3(28, 0, 0), &"chest": Vector3(12, 0, 0), &"head": Vector3(22, 0, 0), &"tail": Vector3(45, 0, 0),
		&"l_upper_arm": Vector3(-50, 0, 0), &"r_upper_arm": Vector3(20, 0, 0)}
	var dig2 := dig.duplicate()
	dig2[&"l_upper_arm"] = Vector3(20, 0, 0)
	dig2[&"r_upper_arm"] = Vector3(-50, 0, 0)
	a.key(0.0, {}).key(0.18, dig).key(0.3, dig2).key(0.42, dig).key(0.54, dig2).key(0.66, dig).key(DIG, UNDER)
	for i in n:
		var p := pops[i]
		var look := POPPED.duplicate()
		look[&"head"] = (POPPED[&"head"] as Vector3) + Vector3(0, 38, 0)
		var look2 := POPPED.duplicate()
		look2[&"head"] = (POPPED[&"head"] as Vector3) + Vector3(0, -38, 0)
		a.key(p - 0.12, UNDER).key(p + 0.1, POPPED).key(p + up * 0.4, look).key(p + up * 0.8, look2).key(p + up, POPPED)
		if i < n - 1:
			a.key(p + up + DOWN, UNDER)
	a.key(a.length, {})
	# where she's going, and where she'll come up (decided WARN_AT before: then the ring)
	var st := {"who": t, "spot": Vector3.INF, "at": 0.0, "trail": 0.0, "rumble": 0.0, "pop": 0}
	a.on(0.15, func(): Audio.play_at(&"ferret_dig", global_position, 6.0, 0.05, {"max_distance": 500.0, "unit_size": 35.0}))
	for k in 2:
		a.on(0.3 + 0.32 * k, func(): _spray())
	a.on(DIG - 0.25, func():
		BossFX.chips(global_position + forward() * 18.0, 2.2, BEDDING)
		BossFX.dust(global_position + forward() * 18.0, 14.0))
	a.on(DIG, func():
		_go_under()
		Audio.play_at(&"ferret_tune", global_position, 8.0, 0.0, {"max_distance": 900.0, "unit_size": 70.0}))
	for i in n:
		var p := pops[i]
		a.on(p - WARN_AT, func():
			st.at = p
			_commit_pop(st, WARN_AT))
		a.on(p, func():
			st.pop = i + 1
			_pop_up(st.spot, st.who if is_instance_valid(st.who) else null))
		if i < n - 1:
			a.on(p + up, func(): _popped = false)
			a.on(p + up + DOWN, func():
				_go_under()
				st.spot = Vector3.INF
				st.who = _next_victim(st.who if is_instance_valid(st.who) else null)
				Audio.play_at(&"ferret_tune_short", global_position, 8.0, 0.0, {"max_distance": 900.0, "unit_size": 70.0}))
	a.on(pops[n - 1] + up, func(): _popped = false)
	a.tick = func(time: float, delta: float):
		if time < DIG:
			face_toward(t.global_position if is_instance_valid(t) else global_position + forward(), delta, 2.0)
			return
		if not _under:
			return
		# under the bedding: after them (till the ring's down, then to it), a
		# trail of churned bedding behind her, the ground shaking over her
		var goal: Vector3 = st.spot
		if goal == Vector3.INF:
			var who: Variant = st.who   # (untyped: it may have been freed)
			goal = (who as Critter).global_position if is_instance_valid(who) and (who as Critter).alive else global_position + forward() * 20.0
		var to := goal - global_position
		to.y = 0.0
		if to.length() > 0.5:
			face_toward(goal, delta, 6.0)
			var speed := TRAVEL
			if st.spot != Vector3.INF:   # (headed for the ring: there by the POP!)
				speed = maxf(TRAVEL * 1.5, to.length() / maxf(float(st.at) - time, 0.05))
			var p := global_position + to.normalized() * minf(speed * delta, to.length())
			p.y = ground_y(p)
			global_position = p
		st.trail = float(st.trail) - delta
		if float(st.trail) <= 0.0:
			st.trail = 0.12
			BossFX.dust(global_position, 6.0, Color(BEDDING, 0.75))
		st.rumble = float(st.rumble) - delta
		if float(st.rumble) <= 0.0:
			st.rumble = 0.35
			Events.explosion.emit(global_position, 7.0)
	a.data["cancel"] = func(): _surface()
	return a


## Into the ground: gone from sight, and from harm.
func _go_under() -> void:
	_under = true
	_popped = false
	_set_hittable(false)
	if model:
		model.visible = false
	BossFX.dust(global_position, 18.0, Color(BEDDING, 0.8))
	BossFX.chips(global_position, 2.0, BEDDING)


## Out of the ground (her pops, a cancel, a rewind).
func _surface() -> void:
	_under = false
	_popped = false
	_set_hittable(alive and state != State.WAITING)
	if model:
		model.visible = true


## Where she'll come up, WARN_AT before she does: under whoever she's after,
## a little ahead of where they're running, or out of a burrow's mouth if
## one's near. The ring goes down there, and she's headed for it.
func _commit_pop(st: Dictionary, lead: float) -> void:
	var who: Critter = st.who if is_instance_valid(st.who) and (st.who as Critter).alive else null
	if who == null:
		who = _next_victim(null)
		st.who = who
	var at := global_position + forward() * 20.0
	if who:
		at = who.global_position + Vector3(who.velocity.x, 0.0, who.velocity.z) * lead * 0.5
	at = _inside(at)
	var mouth := _burrow_near(at)
	if mouth != Vector3.INF:
		at = mouth
	st.spot = at
	warn(at, POP_R, lead)


## The mouth of the hamster's burrow nearest `at`, if one's within BURROW_NEAR
## (the Hamster Cage's: HamsterCage.burrows); INF if not.
func _burrow_near(at: Vector3) -> Vector3:
	var isl: Node = match_manager.island if match_manager and "island" in match_manager else null
	var burrows: Array = isl.get("burrows") if isl and "burrows" in isl else []
	var best := Vector3.INF
	var best_d := BURROW_NEAR
	for b in burrows:
		var m: Vector3 = b.mouth
		var d := Vector2(m.x - at.x, m.z - at.z).length()
		if d < best_d:
			best_d = d
			best = m
	return best


## Who's next, after `last`: someone else near if there's anyone (she pops
## up all over), or whoever's nearest.
func _next_victim(last: Critter) -> Critter:
	var near := foes().filter(func(c): return c != last and c.global_position.distance_to(global_position) < 140.0)
	if not near.is_empty():
		var you := near.filter(func(c): return c.is_player)
		if not you.is_empty() and randf() < 0.4:
			return you[0]
		return near[randi() % near.size()]
	return last if is_instance_valid(last) and last.alive else _pick_target()


## POP! Up out of the ground at `at`, facing `who` (whoever she was after):
## whoever's on the ring goes flying.
func _pop_up(at: Vector3, who: Critter = null) -> void:
	if at == Vector3.INF:
		at = global_position
	at.y = ground_y(at)
	global_position = at
	var face := who if is_instance_valid(who) else target
	if is_instance_valid(face):
		var to := face.global_position - at
		if Vector2(to.x, to.z).length() > 1.0:
			rotation.y = atan2(-to.x, -to.z)
	_surface()
	_popped = true
	_whacks = 0.0
	hurt_ring(at, POP_R, 70.0, 22.0, 10.0, 16.0, &"pop", false)
	BossFX.shockwave(at, POP_R)
	BossFX.chips(at + Vector3.UP * 2.0, 2.6, BEDDING)
	Events.explosion.emit(at, POP_R)
	Audio.play_at(&"boss_stomp", at, 2.0, 0.05, {"max_distance": 600.0, "unit_size": 40.0})


## Digging in: the bedding she flings back behind her stings whoever's there
## (a cone, SPRAY_LEN long), and knocks them back.
func _spray() -> void:
	var back := -forward()
	back.y = 0.0
	back = back.normalized()
	var from := global_position - forward() * 6.0
	FX.burst(from + Vector3.UP * 4.0, (back + Vector3.UP * 0.5).normalized(), {"amount": 46, "lifetime": 1.4,
		"speed": Vector2(14.0, 34.0), "spread": 28.0, "gravity": 14.0, "size": 0.9, "scale": Vector2(0.5, 1.6),
		"color": BEDDING, "fade": false, "shape": "chip", "aabb": 60.0})
	for c in foes_near(from, SPRAY_LEN):
		var off := c.global_position - from
		off.y = 0.0
		if off.length() < 1.0 or off.normalized().dot(back) < cos(SPRAY_HALF):
			continue
		hurt(c, 22.0, back, 12.0, 4.0, &"spray", DamageInfo.Kind.EXPLOSION, 0.0)


## Bopped on the nose enough while she's up: dizzy. She flops out of her
## hole onto her side, stars round her head, and takes double for a while.
func _bop() -> void:
	_cancel_action()
	start(_dizzy_action())


func _dizzy_action() -> BossAction:
	var a := BossAction.new(&"dizzy", 0.5 + DIZZY_FOR + 1.0)
	a.interruptible = false
	a.blend_in = 0.0
	var wob := FLOPPED.duplicate()
	wob[&"head"] = (FLOPPED[&"head"] as Vector3) + Vector3(0, 0, 14)
	wob[&"jaw"] = Vector3(28, 0, 0)
	var wob2 := FLOPPED.duplicate()
	wob2[&"head"] = (FLOPPED[&"head"] as Vector3) + Vector3(0, 0, -10)
	wob2[&"jaw"] = Vector3(18, 0, 0)
	a.key(0.0, POPPED).key(0.5, FLOPPED)
	var k := 0
	var tt := 0.5
	while tt < 0.5 + DIZZY_FOR - 0.4:
		tt += 0.6
		a.key(tt, wob if k % 2 == 0 else wob2)
		k += 1
	a.key(0.5 + DIZZY_FOR, FLOPPED).key(a.length, {})
	_dizzy = true
	vulnerable_until = _clock + 0.5 + DIZZY_FOR
	vulnerable_k = VULNERABLE
	Events.announce.emit("NOODLE IS SEEING STARS!", "Bopped right on the nose. Hit her while she's down!")
	Audio.play_at(&"ferret_hiss", mouth_position(), 4.0, 0.1, {"max_distance": 500.0, "unit_size": 35.0})
	a.on(0.5, func():
		BossFX.dust(global_position, 20.0)
		Events.explosion.emit(global_position, 14.0)
		Audio.play_at(&"body_fall", global_position, 8.0, 0.0, {"max_distance": 600.0, "unit_size": 45.0}))
	var st := {"stars": 0.0}
	a.tick = func(time: float, delta: float):
		st.stars = float(st.stars) - delta
		if time > 0.5 and time < 0.5 + DIZZY_FOR and float(st.stars) <= 0.0:
			st.stars = 0.45
			_stars()
	a.on(0.5 + DIZZY_FOR, func(): _dizzy = false)
	a.data["cancel"] = func(): _dizzy = false
	return a


## Stars round her head (dizzy).
func _stars() -> void:
	FX.burst(get_eye_position() + Vector3.UP * 5.0, Vector3.UP, {"amount": 5, "lifetime": 1.1, "speed": Vector2(3.0, 6.0),
		"spread": 80.0, "gravity": 0.5, "size": 2.2, "scale": Vector2(0.6, 1.2), "color": Color(1.0, 0.92, 0.45),
		"fade": true, "additive": true, "damping": 2.0, "shape": "star", "aabb": 20.0})


## Hits on her head while she's stood up out of a hole count toward bopping
## her (yours most, and a blast three times over). Down the hole she can't be hit.
func take_damage(info: DamageInfo) -> void:
	if _under:
		return
	var before := health
	super(info)
	if not alive or health >= before or not _popped or info.bone_role not in [&"head", &"jaw", &"neck", &"l_ear", &"r_ear"]:
		return
	var by := info.attacker as Critter
	_whacks += (1.0 if by and by.is_player else 0.15) * (3.0 if info.kind == DamageInfo.Kind.EXPLOSION else 1.0)
	if _whacks >= WHACK_AT and state == State.FIGHTING:
		_bop()


# ---- Weasel War Dance ----------------------------------------------------------------------------

## Back arched, mouth open, dooking, she hops sideways at whoever she's
## after, each landing on its own red ring; then she's danced herself out
## and sleeps like the dead (hit her!), and wakes with a poof of musk.
func _dance(t: Critter) -> BossAction:
	cooldown(&"dance", 24.0)
	var n := HOPS_ENRAGED if enraged else HOPS
	var hop := 0.5 if enraged else 0.62
	var wind := 0.8
	var flop := 0.6
	var sleep_at := wind + n * hop + flop
	var wake := 0.9
	var a := BossAction.new(&"dance", sleep_at + SLEEP_FOR + wake)
	a.interruptible = false
	a.key(0.0, {}).key(wind, ARCH)
	for i in n:
		var air := ARCH.duplicate()
		air[&"root"] = Vector3(0, 0.12, 0)
		air[&"l_upper_arm"] = Vector3(-40, 0, 0)
		air[&"r_upper_arm"] = Vector3(-40, 0, 0)
		air[&"l_upper_leg"] = Vector3(45, 0, 0)
		air[&"r_upper_leg"] = Vector3(45, 0, 0)
		air[&"hips"] = (ARCH[&"hips"] as Vector3) + Vector3(0, 0, 14.0 if i % 2 == 0 else -14.0)
		a.key(wind + i * hop + hop * 0.5, air).key(wind + (i + 1) * hop, ARCH)
	var drowsy := FLOPPED.duplicate()
	drowsy[&"jaw"] = Vector3(10, 0, 0)
	var stir := FLOPPED.duplicate()
	stir[&"head"] = (FLOPPED[&"head"] as Vector3) + Vector3(-18, 0, -10)
	stir[&"l_ear"] = Vector3(-25, 0, 0)
	stir[&"r_ear"] = Vector3(-25, 0, 0)
	a.key(sleep_at, FLOPPED).key(sleep_at + SLEEP_FOR - 0.7, drowsy).key(sleep_at + SLEEP_FOR, stir).key(a.length, {})
	var st := {"from": global_position, "to": global_position, "side": 1.0 if randf() < 0.5 else -1.0, "z": 0.0, "hop": -1}
	a.on(0.0, func(): Audio.play_at(&"ferret_dook", mouth_position(), 6.0, 0.05, {"max_distance": 600.0, "unit_size": 40.0}))
	for i in n:
		var t0 := wind + i * hop
		a.on(t0 + 0.001, func():   # (after the last hop's landing, at the same moment)
			st.hop = i
			st.from = global_position
			st.side = -float(st.side)
			var spot := _hop_spot(t, float(st.side))
			st.to = spot
			warn(spot, HOP_R, hop))
		a.on(t0 + hop, func():
			var at: Vector3 = st.to
			hurt_ring(at, HOP_R, 65.0 if enraged else 55.0, 15.0, 12.0, 9.0, &"dance")
			BossFX.shockwave(at, HOP_R)
			Events.explosion.emit(at, HOP_R)
			Audio.play_at(&"boss_stomp", at, -2.0, 0.1, {"max_distance": 500.0, "unit_size": 35.0})
			if i % 2 == 1:
				Audio.play_at(&"ferret_dook", mouth_position(), 4.0, 0.08, {"max_distance": 500.0, "unit_size": 35.0}))
	a.on(sleep_at - 0.2, func():
		Audio.play_at(&"body_fall", global_position, 8.0, 0.0, {"max_distance": 600.0, "unit_size": 45.0})
		BossFX.dust(global_position, 22.0))
	a.on(sleep_at, func():
		_asleep = true
		vulnerable_until = _clock + SLEEP_FOR
		vulnerable_k = VULNERABLE
		Events.announce.emit("NOODLE IS ASLEEP!", "She's danced herself out. Hit her, and get clear before she wakes!")
		Audio.play_at(&"ferret_snore", mouth_position(), 4.0, 0.0, {"max_distance": 400.0, "unit_size": 30.0}))
	a.on(sleep_at + 2.6, func():
		if _asleep:
			Audio.play_at(&"ferret_snore", mouth_position(), 4.0, 0.0, {"max_distance": 400.0, "unit_size": 30.0}))
	a.on(sleep_at + SLEEP_FOR, func():
		_asleep = false
		_poof())
	a.tick = func(time: float, delta: float):
		if time < wind:
			if is_instance_valid(t) and t.alive:
				face_toward(t.global_position, delta, 3.0)
			return
		if time < wind + n * hop:
			if int(st.hop) < 0:
				return
			var u := clampf((time - wind - int(st.hop) * hop) / hop, 0.0, 1.0)
			var from: Vector3 = st.from
			var to: Vector3 = st.to
			var p := from.lerp(to, u)
			p.y = lerpf(from.y, to.y, u) + sin(u * PI) * 9.0
			global_position = p
			if is_instance_valid(t) and t.alive:
				face_toward(t.global_position, delta, 4.0)   # (she hops sideways, facing you)
			return
		if _asleep:
			st.z = float(st.z) - delta
			if float(st.z) <= 0.0:
				st.z = 0.55
				_zzz()
	a.data["cancel"] = func(): _asleep = false
	return a


## Where a hop lands: toward whoever she's after, zigzagging (`side`: which
## way), and onto them once they're within a hop.
func _hop_spot(t: Critter, side: float) -> Vector3:
	var goal := t.global_position if is_instance_valid(t) and t.alive else global_position + forward() * 30.0
	var to := goal - global_position
	to.y = 0.0
	var d := to.length()
	var fwd := to / d if d > 0.1 else forward()
	var across := fwd.cross(Vector3.UP)
	return _inside(global_position + fwd * minf(HOP_LEN, d) + across * side * minf(HOP_LEN * 0.5, d * 0.25))


## A "Z" drifting up off her head as she sleeps (one at a time: Zzz).
func _zzz() -> void:
	FX.burst(get_eye_position() + Vector3.UP * 4.0, Vector3.UP, {"amount": 1, "lifetime": 2.4, "speed": Vector2(2.5, 3.5),
		"spread": 25.0, "gravity": -0.4, "size": 3.8, "scale": Vector2(0.8, 1.2), "color": Color(0.82, 0.88, 1.0),
		"fade": true, "damping": 0.5, "shape": "zee", "upright": true, "aabb": 24.0})


## Startled awake: a poof of musk all round her that knocks back whoever's
## close and hangs there, stinging, for MUSK_SECONDS.
func _poof() -> void:
	var at := global_position
	hurt_ring(at, MUSK_R, 20.0, 8.0, 15.0, 7.0, &"musk", false)
	_clouds.append([at, MUSK_R, _clock + MUSK_SECONDS])
	danger.append([at, MUSK_R, _clock + MUSK_SECONDS, _clock])   # (the bots keep out of it)
	BossFX.musk(at, MUSK_R, MUSK_SECONDS)
	Events.explosion.emit(at, MUSK_R * 0.6)
	Audio.play_at(&"ferret_poof", at, 8.0, 0.0, {"max_distance": 600.0, "unit_size": 40.0})


# ---- Lunge ---------------------------------------------------------------------------------------

## She whips round at whoever she's after, coils back, then strikes along
## a red strip, jaws first, and gives whatever she caught a shake. (She
## strikes where the strip showed: no turning once it's down.)
func _bite(t: Critter) -> BossAction:
	cooldown(&"bite", 5.0)
	var aim := 0.3
	var coil := 0.45 if enraged else 0.55
	var strike := 0.2
	var hit_at := aim + coil + strike
	var a := BossAction.new(&"bite", hit_at + 0.55 + 0.45)
	var drawn := {&"spine": Vector3(6, 0, 0), &"chest": Vector3(-8, 0, 0), &"neck": Vector3(-18, 0, 0), &"head": Vector3(14, 0, 0),
		&"jaw": Vector3(34, 0, 0), &"l_upper_arm": Vector3(-20, 0, 0), &"r_upper_arm": Vector3(-20, 0, 0), &"root": Vector3(0, -0.02, -0.12),
		&"l_ear": Vector3(-30, 0, 0), &"r_ear": Vector3(-30, 0, 0)}
	var struck := {&"spine": Vector3(-6, 0, 0), &"chest": Vector3(14, 0, 0), &"neck": Vector3(8, 0, 0), &"head": Vector3(6, 0, 0),
		&"jaw": Vector3(-2, 0, 0), &"l_upper_arm": Vector3(-55, 0, 0), &"r_upper_arm": Vector3(-55, 0, 0), &"root": Vector3(0, -0.04, 0.1)}
	var shake_l := struck.duplicate()
	shake_l[&"head"] = Vector3(6, 26, 10)
	var shake_r := struck.duplicate()
	shake_r[&"head"] = Vector3(6, -26, -10)
	a.key(0.0, {}).key(aim, {}).key(aim + coil, drawn).key(hit_at, struck)
	a.key(hit_at + 0.14, shake_l).key(hit_at + 0.28, shake_r).key(hit_at + 0.42, shake_l)
	a.key(hit_at + 0.55, struck).key(a.length, {})
	var st := {"fwd": forward()}
	a.on(aim, func():
		st.fwd = forward()
		warn_strip(global_position + forward() * BITE_FROM, global_position + forward() * BITE_REACH, BITE_W, coil + strike)
		Audio.play_at(&"ferret_hiss", mouth_position(), 4.0, 0.08, {"max_distance": 500.0, "unit_size": 35.0}))
	a.on(aim + coil + strike * 0.7, func():
		var fwd: Vector3 = st.fwd
		var from := global_position + fwd * (BITE_FROM - LUNGE * 0.7)
		var to := global_position + fwd * (BITE_REACH - LUNGE * 0.7)
		for c in foes():
			var cp := c.global_position
			var q := Geometry3D.get_closest_point_to_segment(Vector3(cp.x, from.y, cp.z), from, to)
			if Vector2(cp.x - q.x, cp.z - q.z).length() > BITE_W * 0.5 + 1.0:
				continue
			var was := c.alive
			hurt(c, 100.0 if enraged else 85.0, fwd, 10.0, 8.0, &"bite", DamageInfo.Kind.MELEE, 0.9)
			if was and not c.alive and gore_ok:
				FX.gore_burst(c.get_chest_position(), 1.4, c.def.fur_color if c.def else Color.WHITE)
		Audio.play_at(&"melee_hit", mouth_position(), 10.0, 0.05, {"max_distance": 400.0, "unit_size": 30.0}))
	a.tick = func(time: float, delta: float):
		if time < aim:
			if is_instance_valid(t) and t.alive:
				face_toward(t.global_position, delta, 6.0)
		elif time >= aim + coil and time < hit_at:
			move_by((st.fwd as Vector3) * LUNGE / strike * delta)
	return a


# ---- Bottle-Brush (enraged) ------------------------------------------------------------------------

## Reared up on her hind legs, puffed up, hissing: everyone near knocked back.
## (Her arrival's flourish for the camera, too.)
func _roar_action() -> BossAction:
	var a := BossAction.new(&"hiss", 2.3)
	var loud := REARED.duplicate()
	loud[&"jaw"] = Vector3(44, 0, 0)
	loud[&"head"] = (REARED[&"head"] as Vector3) + Vector3(-10, 0, 0)
	a.key(0.0, {}).key(0.45, REARED).key(0.6, loud).key(1.7, loud).key(2.3, {})
	a.on(0.6, func():
		hurt_ring(global_position, 30.0, 12.0, 4.0, 11.0, 6.0, &"hiss", false)
		BossFX.dust(global_position, 30.0)
		Events.explosion.emit(global_position, 22.0)
		Audio.play_at(&"ferret_hiss", mouth_position(), 10.0, 0.0, {"max_distance": 900.0, "unit_size": 60.0}))
	return a


# ---- arriving, and going down ---------------------------------------------------------------------

## The rhyme tinkling under the bedding, the ground heaving, and on POP! she
## comes up out of it, reared up to her full height, and drops onto all fours.
func _entrance() -> BossAction:
	var at := global_position
	var a := BossAction.new(&"entrance", land_time + 2.2)
	a.interruptible = false
	a.blend_in = 0.0
	var up := REARED.duplicate()
	up[&"jaw"] = Vector3(30, 0, 0)
	a.key(0.0, UNDER).key(land_time - 0.15, UNDER).key(land_time + 0.15, up).key(land_time + 1.1, up).key(a.length, {})
	_under = true
	if model:
		model.visible = false
	_set_hittable(false)
	a.on(0.0, func():
		warn(at, 24.0, land_time)
		Audio.play_at(&"ferret_tune", at, 10.0, 0.0, {"max_distance": 1200.0, "unit_size": 80.0}))
	a.tick = func(time: float, _delta: float):
		if time < land_time - 0.2 and randf() < 0.3:
			BossFX.dust(at + Vector3(randf_range(-9, 9), 0, randf_range(-9, 9)), 9.0, Color(BEDDING, 0.75))
	a.on(land_time - 0.15, func(): _surface())
	a.on(land_time, func():
		hurt_ring(at, 24.0, 50.0, 10.0, 14.0, 12.0, &"landing")
		BossFX.shockwave(at, 24.0)
		BossFX.chips(at + Vector3.UP * 2.0, 3.0, BEDDING)
		Events.explosion.emit(at, 20.0)
		Audio.play_at(&"boss_stomp", at, 4.0, 0.0, {"max_distance": 700.0, "unit_size": 40.0}))
	a.on(land_time + 0.6, func():
		Audio.play_at(&"ferret_dook", mouth_position(), 8.0, 0.0, {"max_distance": 700.0, "unit_size": 45.0}))
	a.data["cancel"] = func(): _surface()
	return a


func _after_entrance() -> void:
	cooldown(&"popgoes", 9.0)
	cooldown(&"dance", 5.0)
	if foes_near(global_position, 60.0).size() >= 2:
		start(_roar_action())


## How she was beaten (_death_action): up out of a hole, or flat out asleep or dizzy.
func _die(info: DamageInfo) -> void:
	_fell_from = &"popped" if _popped else (&"flopped" if _asleep or _dizzy else &"")
	super(info)


## She staggers, and goes over onto her side, tongue out, tail curling round.
## Asleep or seeing stars already, she just doesn't get up; beaten up out of
## a hole, she slumps out of it onto the bedding.
func _death_action() -> BossAction:
	_clouds.clear()
	_asleep = false
	_dizzy = false
	var gone := FLOPPED.duplicate()
	gone[&"jaw"] = Vector3(36, 0, 0)
	gone[&"head"] = (FLOPPED[&"head"] as Vector3) + Vector3(10, 0, 8)
	var a := BossAction.new(&"death", 2.4)
	a.blend_out = 0.0
	a.interruptible = false
	match _fell_from:
		&"flopped":
			a.length = 1.4
			a.blend_in = 0.0
			a.key(0.0, FLOPPED).key(1.0, gone).key(1.4, gone)
			a.on(0.3, func():
				if gore_ok:
					FX.gore_burst(mouth_position(), 1.6, Color(0.42, 0.28, 0.18)))
			return a
		&"popped":
			a.blend_in = 0.0
			a.key(0.0, POPPED).key(0.4, POPPED).key(1.5, gone).key(2.4, gone)
		_:
			var reel := {&"hips": Vector3(-12, 0, -10), &"neck": Vector3(-20, 0, 0), &"head": Vector3(-25, 0, 10), &"jaw": Vector3(40, 0, 0),
				&"root": Vector3(0, 0.03, 0)}
			a.key(0.0, {}).key(0.7, reel).key(1.5, gone).key(2.4, gone)
	a.on(0.2, func(): Audio.play_at(&"ferret_hiss", mouth_position(), 6.0, 0.0, {"max_distance": 700.0, "unit_size": 45.0}))
	a.on(1.5, func():
		BossFX.shockwave(global_position, HEIGHT)
		Events.explosion.emit(global_position, 20.0)
		Audio.play_at(&"body_fall", global_position, 12.0, 0.0, {"max_distance": 600.0, "unit_size": 50.0}))
	return a


func _fallen() -> void:
	for m in _eye_skin:   # (the light gone out of her eyes)
		m.emission_energy_multiplier = 0.0
	if gore_ok:
		FX.gore_burst(mouth_position(), 2.2, Color(0.42, 0.28, 0.18))
	BossFX.dust(global_position, 26.0, Color(BEDDING, 0.7))


## A point kept inside the cage (a hop's landing, a pop: never out past the glass).
func _inside(p: Vector3) -> Vector3:
	var isl: Island = match_manager.island if match_manager and "island" in match_manager else null
	if isl:
		var r := isl.play_bounds().grow(-25.0)
		p.x = clampf(p.x, r.position.x, r.end.x)
		p.z = clampf(p.z, r.position.y, r.end.y)
	p.y = ground_y(p)
	return p


# ---- rewind (TimeKeeper) -----------------------------------------------------------------------------

func restore(s: Dictionary) -> void:
	super(s)
	_whacks = 0.0
	_fell_from = &""
	_asleep = false
	_dizzy = false
	_clouds.clear()
	_surface()
