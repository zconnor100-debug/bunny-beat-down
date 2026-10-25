class_name CritterPoser
extends SkeletonModifier3D
## Fully procedural animation — no keyframes. Every frame, starting from the
## rest pose, it:
##   1. advances a gait cycle from the critter's real velocity (run, or hop for bunnies)
##   2. moves/leans the hips (bob, forward lean, crouch, take-off and landing, hit flinch)
##   3. twists spine → chest → neck → head to follow the aim
##   4. layers life on top: breathing (panting after a sprint), weight shifting
##      from paw to paw, glances around, and each species' idle fidgets
##   5. places the held weapon: up at the aim when shooting or alert, lowered
##      when relaxed, across the chest at a sprint (recoil + reload tilt, and
##      it drags a little behind quick turns)
##   6. solves two-bone IK so both paws grip the gun's real grip markers (or
##      pump, hang, reach and stretch when the paws are empty)
##   7. solves two-bone IK for the legs to the gait's foot targets (planted
##      feet step round when the critter turns on the spot)
## Ears and tails are left to the SpringBoneSimulator3D that runs after this.
## Lying prone, CritterVisual tips the whole model onto its belly and this
## swaps the gait for an army crawl (elbows and knees, opposite arm and leg);
## under a glider the legs just hang.
##
## All maths happens in skeleton space. Models face +Z there, so the critter's
## right-hand side is −X.

const UP := Vector3.UP
const FWD := Vector3(0, 0, 1)
const RIGHT := Vector3(-1, 0, 0)
## Hop length = leg * (HOP_BASE + speed * HOP_PER_SPEED); the airborne share
## of each hop cycle is HOP_AIR (the rest is the crouch-and-push contact).
const HOP_BASE := 3.6
const HOP_PER_SPEED := 0.45
const HOP_AIR := 0.72
## Hoppers pitch nose-down this much as they push off (and level out in flight).
const HOP_PITCH := 0.3
## Running is a bound: an unhurried step rate (STEP_RATE + STEP_RATE_PER_HEIGHT
## per body-height-per-second of speed, so ~2.4 steps/s walking and ~3 at a
## sprint, whatever the species' leg length) and long strides. Each foot is
## planted for at most PLANT leg lengths of travel; the rest of every step is a
## little flight, so short-legged critters bound instead of pattering.
const STEP_RATE := 1.4
const STEP_RATE_PER_HEIGHT := 0.33
const PLANT := 1.1
## Forward lean at a flat-out run (radians; the neck and head take some of it
## back so the eyes stay on the road).
const RUN_LEAN := 0.32
## Army crawl: each paw is planted for CRAWL_STANCE of a cycle and drags the
## body CRAWL_PULL arm lengths forward (it stays put on the ground while the
## body slides past it), then lifts and reaches ahead again; the opposite knee
## draws up and pushes in step with it.
const CRAWL_STANCE := 0.6
const CRAWL_PULL := 0.9
## Hanging from a glider, short arms stretch (cartoon-style, up to this many
## times their length) so both paws really hold the handle.
const ARM_STRETCH_MAX := 2.6
## Turning on the spot: a planted foot stays where it is until the body has
## turned this far past it, then steps round (STEP_TIME seconds, one at a time).
const TURN_STEP := 0.5
const STEP_TIME := 0.2
## Guns held relaxed point this far below the aim (pistols a little more); a
## shoulder-fired launcher instead rests tipped up on the shoulder.
const LOW_PITCH := 0.42
const LOW_PITCH_PISTOL := 0.7
const LOW_PITCH_SHOULDER := -0.22
## At a sprint a relaxed long gun dips further and swings across the body.
const CARRY_PITCH := 0.62
const CARRY_YAW := 0.55
## Breaths per second at rest and when puffed out after a long sprint.
const BREATH_RATE := 0.3
const PANT_RATE := 1.0
## Each species' idle fidgets (by rig id; anything else just looks round and
## stretches). With a gun in the paws the ones that need free paws are skipped
## and the critter checks its gun instead.
const FIDGETS := {
	"bun": ["look", "thump", "scratch", "stretch", "chew"],
	"bandit_bunny": ["look", "thump", "stretch", "scratch"],
	"squirrel": ["look", "wiggle", "chew", "scratch"],
	"fox": ["look", "stretch", "wiggle", "scratch"],
	"raccoon": ["look", "scratch", "wiggle", "stretch"],
	"frog": ["look", "bounce", "stretch"],
	"beaver": ["look", "chew", "wiggle", "stretch"],
	"hamster": ["look", "chew", "scratch", "bounce"],
}
const FIDGET_TIME := {
	"look": 2.6, "stretch": 2.4, "scratch": 1.8, "thump": 1.3, "chew": 2.0,
	"wiggle": 1.4, "bounce": 1.5, "gun_check": 2.2,
}
const PAWS_FREE := ["stretch", "scratch"]
## A closed fist: how far each finger joint bends (radians, knuckle first).
const FINGER_CURL := [1.2, 1.35, 1.0]
## How far an arm too short for its gun may stretch to keep hold of it.
const GRIP_STRETCH_MAX := 3.2
## The trigger paw sits at most this share of the arm's length in front of
## the shoulder (a pistol held out one-handed, nearly straight).
const HOLD_REACH := 0.55
const PISTOL_REACH := 0.9
## How far a fist may turn round its handle to spare the wrist (radians).
const ROLL_RANGE := 1.1
const ROLL_STEPS := 7

signal footstep(hop: bool)

var rig: RigInfo
var holder: Node3D            ## weapon holder, placed by this modifier
var support_marker: Node3D    ## "SupportGrip" inside the weapon model (optional)
var glide_grip: Node3D        ## the glider, whose origin is its handle (while gliding)

# ---- inputs, written by CritterVisual every frame (world space) ------------------
var velocity := Vector3.ZERO
var grounded := true
var aim_dir := Vector3.FORWARD
var crouch := 0.0
var gait := CritterDef.Gait.RUN
var armed := false
var two_handed := true
var hold_distance := 0.26
var gliding := false
var reload_progress := -1.0   ## 0..1 while reloading, -1 otherwise
var club := false             ## holding the species' melee club instead of a gun
var prone := 0.0              ## 0 up … 1 lying on the belly (CritterVisual tips the model)
var melee := -1.0             ## 0..1 through a club swing, -1 otherwise
var recoil := 0.0             ## 0..1, decays in CritterVisual
var trick_tuck := 0.0         ## +1 tuck limbs in (flips, rolls), -1 stretch out (leaps)
var trick_active := false     ## mid-trick: stop tracking the aim, the body is spinning
var gun_up := 1.0             ## 1 gun up at the aim (aiming, shooting, alert), 0 relaxed
var sprinting := false        ## running flat out (a relaxed long gun goes across the chest)
var shouldered := false       ## a shoulder-fired launcher
var gun_box := AABB()         ## the held gun's bounds in its own frame (-Z = muzzle)
var paws: Dictionary = {}     ## PawGrip per side (&"l", &"r"): how each paw closes on a handle
## How well each paw holds its handle, last frame (per side, -1 when it holds
## none): how far the fist is from the handle (in body heights), and how far
## the wrist bends from the line of the forearm (radians). Only measured while
## `measuring` is on (tests and tools: it costs a few skeleton look-ups).
static var measuring := false
var grip_miss := {&"l": -1.0, &"r": -1.0}
var wrist_bend := {&"l": -1.0, &"r": -1.0}
var arm_stretch := {&"l": 1.0, &"r": 1.0}   ## how far each arm stretched to reach (1 = not at all)

## Where the gun would sit raised to the aim (world space). Shots leave from
## its muzzle even while the gun is lowered, so how a gun is carried never
## changes where it shoots from.
var raised_holder := Transform3D.IDENTITY
var has_raised := false

# ---- internal state ---------------------------------------------------------------
var _phase := 0.0
var _prev_phase := 0.0
var _move := 0.0
var _crawl := 0.0             # 0..1: how hard the limbs work at the army crawl
var _air := 0.0
var _land_amt := 0.0          # how hard the last landing was (0..1)
var _land_t := 9.0            # seconds since it
var _takeoff := 0.0           # 1 on leaving the ground, fading
var _was_grounded := true
var _flinch := Vector3.ZERO
var _flinch_vel := Vector3.ZERO
var _lean := 0.0
var _seg_len: Dictionary = {}
var _jaw := -1
var _rng := RandomNumberGenerator.new()
var _t := 0.0                 # this critter's own clock (scaled time, random start)
var _breath := 0.0            # breathing cycle (radians)
var _exert := 0.0             # 0..1: puffed out from sprinting
var _up := 1.0
var _carry := 0.0
var _still := 0.0             # 0..1: standing still on the ground
var _glance := Vector2.ZERO   # head turned away from the aim (yaw, pitch)
var _glance_to := Vector2.ZERO
var _glance_wait := 2.0
var _fidget := ""
var _fidget_p := 0.0
var _fidget_w := 0.0
var _fidget_dir := 1.0
var _fidget_wait := 3.0
var _sway := Vector2.ZERO     # the gun dragging behind a quick turn (yaw, pitch)
var _aim_prev := Vector2.ZERO
var _plant_yaw := {&"l": 0.0, &"r": 0.0}
var _step_side := &""
var _step_p := 0.0


func setup(rig_: RigInfo) -> void:
	rig = rig_
	for side in [&"l", &"r"]:
		_seg_len[side + "_arm1"] = _rest_dist(StringName(side + "_upper_arm"), StringName(side + "_lower_arm"))
		_seg_len[side + "_arm2"] = _rest_dist_end(StringName(side + "_lower_arm"), StringName(side + "_hand"))
		_seg_len[side + "_leg1"] = _rest_dist(StringName(side + "_upper_leg"), StringName(side + "_lower_leg"))
		_seg_len[side + "_leg2"] = _rest_dist_end(StringName(side + "_lower_leg"), StringName(side + "_foot"))
	var jaw: Variant = rig.data.get("bones", {}).get("jaw")
	_jaw = rig.skeleton.find_bone(jaw) if jaw is String else -1
	# every critter breathes and fidgets on its own beat, so a crowd never moves in step
	_rng.randomize()
	_t = _rng.randf_range(0.0, 100.0)
	_breath = _rng.randf_range(0.0, TAU)
	_fidget_wait = _rng.randf_range(2.0, 6.0)


## Called by the critter when it touches down.
func on_landed(impact_speed: float) -> void:
	_land_amt = clampf(impact_speed / 14.0, 0.0, 1.0)
	_land_t = 0.0


## A hit shoves the upper body away from the shot, then springs back.
func flinch(world_dir: Vector3, strength: float) -> void:
	var skel := get_skeleton()
	if skel == null:
		return
	var d := (skel.global_basis.inverse() * world_dir).normalized()
	# rotate about the axis perpendicular to the push and up
	var axis := UP.cross(d)
	if axis.length_squared() < 1e-4:
		axis = RIGHT
	_flinch_vel += axis.normalized() * clampf(strength, 0.0, 1.0) * 9.0


## How deep the hips sink after a landing: down fast, back up slower with a
## little bounce past standing height.
func _landing() -> float:
	if _land_t < 0.07:
		return _land_amt * smoothstep(0.0, 0.07, _land_t)
	var t := _land_t - 0.07
	return _land_amt * exp(-t * 6.0) * cos(t * 8.0)


## 0 → 1 → 0 over a fidget, easing in and out.
static func _envelope(p: float) -> float:
	return smoothstep(0.0, 0.22, p) * (1.0 - smoothstep(0.78, 1.0, p))


func _process_modification_with_delta(delta: float) -> void:
	var skel := get_skeleton()
	if skel == null or rig == null:
		return
	delta = minf(delta, 0.05)
	_t += delta
	var to_skel := skel.global_basis.orthonormalized().inverse()
	var v := to_skel * velocity / rig.size   # model units (the model node is scaled)
	var hv := Vector3(v.x, 0.0, v.z)
	# ground speed from the world velocity: lying prone (or mid-flip) the
	# skeleton is tipped over, and its own "horizontal" would read ~0
	var speed := Vector2(velocity.x, velocity.z).length() / rig.size
	var vy := velocity.y / rig.size
	var move_dir := hv.normalized() if hv.length() > 0.05 else FWD
	var S := rig.scale
	var leg: float = (rig.leg_length[&"l"] + rig.leg_length[&"r"]) * 0.5

	# under a glider the legs hang still instead of running on air
	_move = lerpf(_move, 0.0 if gliding else clampf(speed / (2.2 * S), 0.0, 1.0), IKMath.damp(10.0, delta))
	var up_k := 1.0 - prone       # gait effects that only make sense upright
	_air = lerpf(_air, 0.0 if grounded else 1.0, IKMath.damp(10.0, delta))
	if _was_grounded and not grounded and vy > 0.5 and not gliding:
		_takeoff = 1.0
	_was_grounded = grounded
	_takeoff = move_toward(_takeoff, 0.0, delta * 4.0)
	_land_t += delta
	var land := _landing()
	var rise := clampf(vy / (3.0 * S), 0.0, 1.0) * _air
	var fall := clampf(-vy / (3.0 * S), 0.0, 1.0) * _air
	# damped spring for the hit flinch
	_flinch_vel += (-_flinch * 120.0 - _flinch_vel * 14.0) * delta
	_flinch += _flinch_vel * delta
	_lean = lerpf(_lean, clampf(speed / (4.5 * S), 0.0, 1.0) * RUN_LEAN * up_k, IKMath.damp(6.0, delta))
	var crawling := prone > 0.5

	# ---- life: breathing, standing still, glances and fidgets --------------------------
	var running_hard := sprinting and _move > 0.5
	_exert = minf(1.0, _exert + delta * 0.25) if running_hard else maxf(0.0, _exert - delta * 0.07)
	_breath = fposmod(_breath + TAU * lerpf(BREATH_RATE, PANT_RATE, _exert) * delta, TAU)
	var breath := sin(_breath) * lerpf(1.0, 2.2, _exert)
	var still_now := grounded and not gliding and speed < 0.25 * S and not trick_active
	_still = move_toward(_still, 1.0 if still_now else 0.0, delta * (1.5 if still_now else 6.0))
	_up = move_toward(_up, clampf(gun_up, 0.0, 1.0), delta * (7.0 if gun_up > _up else 2.2))
	var relaxed := _up < 0.3
	_carry = move_toward(_carry, 1.0 if sprinting and relaxed and not shouldered and not club else 0.0,
		delta * 4.0)
	var calm := relaxed and _still > 0.9 and not crawling and crouch < 0.5 and melee < 0.0
	_update_fidget(delta, calm)
	var fk := _envelope(_fidget_p) * _fidget_w
	_update_glance(delta, calm, fk)
	var shift := sin(_t * 0.42) * _still * up_k   # weight from paw to paw

	# ---- gait clock -------------------------------------------------------------
	var step_rate := STEP_RATE + STEP_RATE_PER_HEIGHT * speed / rig.head_top
	# share of each step a foot spends planted (the rest is in the air)
	var on_ground := clampf(leg * PLANT * step_rate / maxf(speed, 0.01), 0.3, 0.95)
	var plant := speed * on_ground / step_rate   # how far a planted foot slides back
	# bunnies take long bounding hops (~2–3 per second), not a rapid patter
	var hop_len := leg * (HOP_BASE + speed * HOP_PER_SPEED / S)
	# crawling is slow, so its limbs go full stroke at a slow speed (the walk
	# measure `_move` would barely stir them, and the critter would just slide)
	_crawl = lerpf(_crawl, clampf(speed / (0.1 * S), 0.0, 1.0) if crawling else 0.0, IKMath.damp(8.0, delta))
	var arm_avg: float = (_seg_len["r_arm1"] + _seg_len["r_arm2"] + _seg_len["l_arm1"] + _seg_len["l_arm2"]) * 0.5
	if gliding:
		pass   # the legs dangle; the clock waits for the landing
	elif crawling:
		# one cycle per (planted share × pull length): planted paws keep still
		_phase = fposmod(_phase + speed / (arm_avg * CRAWL_PULL / CRAWL_STANCE) * TAU * delta, TAU)
	elif gait == CritterDef.Gait.HOP:
		_phase = fposmod(_phase + speed / hop_len * TAU * delta, TAU)
	else:
		_phase = fposmod(_phase + step_rate * 0.5 * TAU * delta, TAU)   # a cycle is two steps
	# a foot (or both, for a hop) touches down: tell the critter for footstep audio
	if grounded and speed > 0.8 and not gliding and not crawling:
		if gait == CritterDef.Gait.HOP:
			if _prev_phase < TAU * 0.72 and _phase >= TAU * 0.72:
				footstep.emit(true)
		elif floori(_prev_phase / PI) != floori(_phase / PI) or _phase < _prev_phase:
			footstep.emit(false)
	_prev_phase = _phase
	if speed < 0.05 and grounded:
		# settle back to a neutral phase so idle feet line up
		_phase = lerp_angle(_phase, 0.0, IKMath.damp(4.0, delta))

	# ---- hips -------------------------------------------------------------------
	var hips: int = rig.bone[&"hips"]
	var hip_pos: Vector3 = rig.rest[&"hips"].origin
	hip_pos.y -= leg * (0.05 + crouch * 0.28 + land * 0.22) * up_k
	var hop_air := 0.0
	var hip_twist := sin(_phase) * 0.12 * _move if gait == CritterDef.Gait.RUN and not crawling else 0.0
	# bare-pawed runners swing their shoulders against their hips (the head
	# stays steady); with a gun the shoulders hold still so the aim does too
	var shoulder_swing := sin(_phase) * 0.08 * _move * (0.0 if armed else 1.0) * up_k
	var hop_reach := 0.0          # hoppers' paws: -1 swung back (push-off) … +1 reaching ahead (landing)
	var hop_pitch := 0.0
	if crawling:
		# the body rolls a little toward each elbow as it pulls
		hip_pos += RIGHT * sin(_phase) * 0.03 * S * _crawl
	elif gait == CritterDef.Gait.HOP:
		var u := _phase / TAU
		var fly := u < HOP_AIR
		var k := u / HOP_AIR if fly else (u - HOP_AIR) / (1.0 - HOP_AIR)
		hop_air = sin(k * PI) if fly else 0.0
		var squash := 0.0 if fly else sin(k * PI)
		# longer hops arc higher; nose-down on the push-off, levelling out through
		# the flight and tipping back down through the crouch for the next one
		hip_pos.y += _move * (leg * 0.68 * hop_air - leg * 0.1 * squash) * (1.0 - _air) * up_k
		hop_reach = -cos(k * PI) if fly else cos(k * PI)
		hop_pitch = _move * up_k * (1.0 - _air) * HOP_PITCH * (0.5 - 0.5 * hop_reach)
	else:
		# dip a little on the planted foot, then float through the bound
		var step_u := fposmod(_phase / PI, 1.0)
		var air_t := (1.0 - on_ground) / step_rate
		var flight := minf(16.0 * air_t * air_t / 8.0 / rig.size, leg * 0.45)
		var up := sin((step_u - on_ground) / (1.0 - on_ground) * PI) if step_u >= on_ground else 0.0
		hip_pos.y += _move * (flight * up - leg * 0.04 * sin(step_u / on_ground * PI) * float(step_u < on_ground)) * up_k
		hip_pos += RIGHT * sin(_phase) * 0.012 * S * _move
	# breathing, and the weight shifting from one paw to the other
	hip_pos.y += breath * 0.003 * S * (1.0 - _move)
	hip_pos += RIGHT * shift * 0.02 * S
	hip_pos.y -= absf(shift) * 0.006 * S
	if _fidget == "bounce":   # three quick knee bobs
		hip_pos.y -= fk * leg * 0.1 * (0.5 - 0.5 * cos(_fidget_p * TAU * 3.0))
	_set_global_origin(hips, hip_pos)
	_rotate_global(hips, Quaternion(RIGHT, -(_lean + hop_pitch)))
	_rotate_global(hips, Quaternion(FWD, shift * 0.035))
	if crawling:
		_rotate_global(hips, Quaternion(UP, sin(_phase) * 0.16 * _crawl))
	elif gait == CritterDef.Gait.RUN:
		_rotate_global(hips, Quaternion(UP, hip_twist))
	if _fidget == "wiggle":   # a tail swish (the spring bones do the rest)
		_rotate_global(hips, Quaternion(UP, fk * sin(_fidget_p * TAU * 3.5) * 0.22))

	# ---- spine aims ---------------------------------------------------------------
	var a := FWD if trick_active else (to_skel * aim_dir).normalized()
	# lying down the body runs along the aim (skeleton +Y is "ahead"), so the
	# spine stays flat and the neck lifts the head to look where we're going
	var a_body := a.lerp(Vector3(a.x, -a.z, a.y), prone).normalized()
	var pitch := clampf(asin(clampf(a_body.y, -1.0, 1.0)), -1.3, 1.3)
	var yaw := clampf(atan2(-a_body.x, a_body.z) * -1.0, -1.0, 1.0)
	# [role, aim pitch share, aim yaw share, lean taken back]: the chest keeps
	# most of a run's forward lean, the neck and head level the eyes again
	var chain := [[&"spine", 0.25, 0.3, 0.2], [&"chest", 0.35, 0.4, 0.2], [&"neck", 0.15, 0.1, 0.25], [&"head", 0.25, 0.2, 0.35]]
	var done := {}
	var fl_len := _flinch.length()
	var lean := _lean + hop_pitch
	for item in chain:
		var idx: int = rig.bone.get(item[0], -1)
		if idx < 0 or done.has(idx) or idx == hips:
			continue
		done[idx] = true
		var lift := 0.0
		var pitch_w: float = item[1]
		if item[0] in [&"spine", &"chest"]:
			pitch_w *= up_k
		else:
			lift = prone * 0.65
		var q := Quaternion(UP, yaw * item[2]) * Quaternion(RIGHT, pitch * pitch_w + lean * item[3] + lift)
		if fl_len > 0.001 and item[0] in [&"spine", &"chest"]:
			q = Quaternion(_flinch / fl_len, fl_len * 0.5) * q
		_rotate_global(idx, q)
	var chest: int = rig.bone[&"chest"]
	if chest != hips:
		# breathing lifts the chest (and the shoulders with it), a landing folds
		# it forward, the shoulders swing against the hips on the run, and the
		# weight shift is balanced so the head stays over the feet
		var bend := breath * 0.022 * up_k - land * 0.3 * up_k
		if _fidget == "stretch":
			bend += fk * 0.3
		_rotate_global(chest, Quaternion(UP, -(hip_twist + shoulder_swing)) * Quaternion(RIGHT, bend) * Quaternion(FWD, -shift * 0.03))
	_look_around(fk, shoulder_swing)
	_update_sway(delta)

	# ---- weapon placement ------------------------------------------------------------
	var sh_r := _g(rig.bone[&"r_upper_arm"]).origin
	var sh_l := _g(rig.bone[&"l_upper_arm"]).origin
	var sh_mid := (sh_r + sh_l) * 0.5
	var grip := Vector3.ZERO
	# keep the gun upright in the world (also when the body is lying down)
	var up_s := (to_skel * Vector3.UP).normalized()
	if absf(a.dot(up_s)) > 0.98:   # (aiming straight up/down, or mid-flip)
		up_s = UP if absf(a.dot(UP)) < 0.98 else RIGHT
	var wbasis := Basis.looking_at(a, up_s)
	var reload_k := 0.0
	if reload_progress >= 0.0:
		reload_k = sin(clampf(reload_progress, 0.0, 1.0) * PI)
	if holder:
		holder.visible = armed and not gliding
	# army-crawl paw targets (the gun, if any, rides along in the right paw)
	var crawl_paw := {}
	if crawling:
		var depth: float = maxf(rig.radii.get(&"chest", 0.05), rig.radii.get(&"spine", 0.05))
		for side in [&"r", &"l"]:
			var shoulder_c := sh_r if side == &"r" else sh_l
			var len_c: float = _seg_len[side + "_arm1"] + _seg_len[side + "_arm2"]
			crawl_paw[side] = _crawl_paw(side, shoulder_c, len_c, depth, S)
	if armed and not gliding:
		var down := -wbasis.y
		var right := wbasis.x
		# (as far out as this critter's own arms reach comfortably: guns are
		# sized to the body, arms aren't — a hamster's are half a fox's)
		var arm_r: float = _seg_len["r_arm1"] + _seg_len["r_arm2"]
		# toward the middle of the body when the other arm is too short to
		# reach across to the right shoulder (a hamster hugs it to its tummy)
		var arm_l: float = _seg_len["l_arm1"] + _seg_len["l_arm2"]
		var mid_k := clampf(2.0 * (1.0 - 0.8 * arm_l / maxf(sh_r.distance_to(sh_l), 0.001)), 0.35, 1.0)
		var hold := minf(hold_distance * S, arm_r * (PISTOL_REACH if not two_handed and not club else HOLD_REACH))
		if club:
			# club: held up by the right shoulder; a swing winds it back over the
			# shoulder, then brings it down across the body
			grip = sh_r + a * hold * 0.6 + down * 0.04 * S + right * 0.06 * S
			wbasis = wbasis.rotated(right, _club_angle(melee))
			if melee >= 0.0:
				var strike := _club_strike(melee)
				grip += a * strike * 0.12 * S
				wbasis = wbasis.rotated(a, -0.5 * strike)
		elif two_handed:
			grip = sh_r.lerp(sh_mid, mid_k) + a * hold + down * 0.07 * S
		else:
			grip = sh_mid.lerp(sh_r, 0.4 * (1.0 - mid_k) / 0.65) + a * hold + down * 0.02 * S
		if not club:
			grip += _head_clearance(grip, wbasis, _seg_len["l_arm1"] + _seg_len["l_arm2"])
			grip += a * _torso_clearance(grip, a)
		grip -= a * recoil * 0.05 * S
		wbasis = wbasis.rotated(right, recoil * 0.25)
		if reload_k > 0.0:
			wbasis = wbasis.rotated(a, -reload_k * 0.6).rotated(right, -reload_k * 0.35)
			grip += down * reload_k * 0.05 * S
		raised_holder = skel.global_transform * Transform3D(wbasis, grip)
		has_raised = true
		if not club:
			var carried := _carried(grip, wbasis, a, up_s, sh_r, sh_mid, hold, S, fk)
			grip = carried.origin
			wbasis = carried.basis
		if crawling and _crawl > 0.01:
			grip = grip.lerp(crawl_paw[&"r"], _crawl)
		if holder:
			holder.global_transform = skel.global_transform * Transform3D(wbasis, grip)
	else:
		has_raised = false

	# ---- arms -------------------------------------------------------------------------
	var held := {}   # side -> [hand basis, finger curl] for a paw closed on a handle
	for side in [&"r", &"l"]:
		var sgn := 1.0 if side == &"r" else -1.0
		var up_i: int = rig.bone[StringName(side + "_upper_arm")]
		var lo_i: int = rig.bone[StringName(side + "_lower_arm")]
		var hand_i: int = rig.bone.get(StringName(side + "_hand"), -1)
		var shoulder := sh_r if side == &"r" else sh_l
		var arm_len: float = _seg_len[side + "_arm1"] + _seg_len[side + "_arm2"]
		var target: Vector3
		var pole := shoulder + RIGHT * sgn * 0.35 * S - UP * 0.45 * S - FWD * 0.25 * S
		var l1: float = _seg_len[side + "_arm1"]
		var l2: float = _seg_len[side + "_arm2"]
		if gliding and glide_grip and is_instance_valid(glide_grip):
			# both paws wrap the handle, one above the other; arms too short to
			# reach it stretch so the critter visibly hangs from its paws
			var handle := skel.global_transform.affine_inverse() * glide_grip.global_position
			target = handle + UP * sgn * 0.035 * S + RIGHT * sgn * 0.02 * S
			pole = shoulder + RIGHT * sgn * 0.5 * S - FWD * 0.2 * S
			var k := clampf(shoulder.distance_to(target) / (arm_len * 0.97), 1.0, ARM_STRETCH_MAX)
			if k > 1.0:
				_stretch_arm(lo_i, hand_i, k)
				l1 *= k
				l2 *= k
		elif gliding:
			target = sh_mid + UP * 0.5 * S + RIGHT * sgn * 0.1 * S
			pole = shoulder + RIGHT * sgn * 0.5 * S - FWD * 0.2 * S
		elif crawling and not armed:
			# army crawl: reach ahead (skeleton +Y is ahead), plant, drag forward
			target = crawl_paw[side]
			pole = shoulder + RIGHT * sgn * 0.5 * S - UP * 0.3 * S + FWD * 0.2 * S
		elif armed:
			if side == &"r":
				target = grip
			else:
				target = _support_point(skel, grip, wbasis, S)
				if crawling:
					target = target.lerp(crawl_paw[side], _crawl)
			if not crawling:
				# close the paw on the handle: turn the hand to it, then put the
				# wrist wherever puts the fist (not the wrist) on it
				var frame := _handle(side, grip, wbasis, skel, S)
				var g: PawGrip = paws.get(side)
				if not frame.is_empty() and g and g.valid:
					var at: Vector3 = frame[0]
					if frame[4] != null:
						# a fore-end: slide back along it until the paw can reach
						at += (frame[4] as Vector3) * _slide(at - g.hold.length() * (frame[2] as Vector3) - shoulder,
							frame[4], frame[5], arm_len * 1.05)
					var hb := _best_turn(side, g, at, frame, shoulder, l1, l2, pole)
					target = at - hb * g.hold
					held[side] = [hb, frame[3], at]
			# short arms reach a little further than they should rather than let
			# go of the gun (cartoon-style, as under the glider)
			var reach := clampf(shoulder.distance_to(target) / (arm_len * 0.98), 1.0, GRIP_STRETCH_MAX)
			arm_stretch[side] = reach
			if reach > 1.0:
				_stretch_arm(lo_i, hand_i, reach)
				l1 *= reach
				l2 *= reach
			if crawling:
				pole = pole.lerp(shoulder + RIGHT * sgn * 0.5 * S - UP * 0.3 * S + FWD * 0.2 * S, _crawl)
				if reload_k > 0.0:
					var pouch := (rig.rest[&"hips"] as Transform3D).origin + RIGHT * -0.12 * S + FWD * 0.05 * S
					var mag := grip - wbasis.y * 0.08 * S - wbasis.z * 0.06 * S
					var rp := clampf(reload_progress, 0.0, 1.0)
					target = target.lerp(mag, smoothstep(0.0, 0.25, rp)).lerp(pouch, smoothstep(0.3, 0.5, rp) * (1.0 - smoothstep(0.55, 0.8, rp)))
		else:
			var free := _free_paw(side, shoulder, arm_len, S, hop_reach, breath, rise, fall, land, fk)
			target = free[0]
			pole = free[1]
		_two_bone(up_i, lo_i, hand_i, l1, l2, target, pole)
		_close_paw(side, hand_i, held.get(side, []), 1.0 if gliding else 0.22)
		_measure_grip(side, lo_i, hand_i, held.get(side, []), S)

	# ---- legs -------------------------------------------------------------------------
	var turning := grounded and not gliding and not crawling and not trick_active and _move < 0.25
	var body_yaw := _turn_feet(skel, turning, delta)
	for side in [&"l", &"r"]:
		var sgn := 1.0 if side == &"r" else -1.0
		var ul: int = rig.bone[StringName(side + "_upper_leg")]
		var ll: int = rig.bone[StringName(side + "_lower_leg")]
		var ft: int = rig.bone.get(StringName(side + "_foot"), -1)
		var rest_foot: Vector3 = (rig.rest[StringName(side + "_foot")] as Transform3D).origin if ft >= 0 \
			else _g(ll).origin * Vector3(1, 0, 1) + UP * 0.05 * S
		var target := rest_foot
		if turning:
			# a planted foot keeps its place on the ground while the body turns
			# over it, then steps round to catch up
			var off := wrapf(body_yaw - _plant_yaw[side], -PI, PI)
			var lift := 0.0
			if _step_side == side:
				off *= 1.0 - smoothstep(0.0, 1.0, _step_p)
				lift = sin(_step_p * PI) * leg * 0.16
			var pivot := Vector3(hip_pos.x, rest_foot.y, hip_pos.z)
			target = pivot + Basis(UP, -off) * (rest_foot - pivot) + UP * lift
		if gait == CritterDef.Gait.HOP:
			# feet stay planted during contact (they slide back exactly as fast as the
			# body moves forward), then swing through to land ahead for the next hop
			var u := _phase / TAU
			var contact := hop_len * (1.0 - HOP_AIR)
			var along: float
			if u >= HOP_AIR:
				along = (0.5 - (u - HOP_AIR) / (1.0 - HOP_AIR)) * contact
			else:
				var hop_t := u / HOP_AIR
				along = lerpf(-0.5, 0.5, smoothstep(0.0, 1.0, hop_t)) * contact
				target += UP * sin(hop_t * PI) * leg * 0.35 * _move
			target += move_dir * along * _move
		else:
			# planted for the first `on_ground` of its step (sliding back exactly as
			# fast as the body goes forward), then swung through to land ahead
			var u := fposmod((_phase + (0.0 if side == &"l" else PI)) / TAU, 1.0)
			var stance := on_ground * 0.5
			var along: float
			if u < stance:
				along = lerpf(0.5, -0.5, u / stance)
			else:
				var t := (u - stance) / (1.0 - stance)
				along = lerpf(-0.5, 0.5, smoothstep(0.0, 1.0, t))
				target += UP * sin(t * PI) * leg * 0.3 * _move
			target += move_dir * along * plant * _move
		var hip := _g(ul).origin
		var pole := hip + FWD * leg + RIGHT * sgn * 0.08 * S
		if crawling:
			# frog-kick: each knee draws up and out to the side (with the opposite
			# paw's reach), then the leg pushes back out straight while that paw pulls
			var u := fposmod((_phase + (PI if side == &"r" else 0.0)) / TAU, 1.0)
			var draw: float
			var lift := 0.0
			if u < CRAWL_STANCE:
				draw = 1.0 - u / CRAWL_STANCE
			else:
				var t := (u - CRAWL_STANCE) / (1.0 - CRAWL_STANCE)
				draw = smoothstep(0.0, 1.0, t)
				lift = sin(t * PI)
			draw *= _crawl
			target = rest_foot + UP * leg * 0.45 * draw + RIGHT * sgn * leg * 0.35 * draw \
				+ FWD * 0.04 * S - FWD * lift * leg * 0.12 * _crawl
			pole = hip + RIGHT * sgn * leg + FWD * leg * 0.4
		elif gliding:
			# dangling: a slow, lazy swing from the hips
			target = rest_foot + FWD * sin(_t * 1.4 + sgn) * 0.06 * S + FWD * 0.05 * S
		# in the air: knees tuck up on the way up, and the feet reach down and a
		# little ahead for the ground on the way down; a take-off kicks them back
		target += UP * leg * _air * (0.2 + 0.14 * rise - 0.12 * fall) + FWD * S * (0.07 * fall - 0.05 * rise) * _air
		target -= FWD * 0.08 * S * _takeoff
		if trick_tuck > 0.0:
			target += UP * trick_tuck * leg * 0.3 + FWD * trick_tuck * 0.08 * S
		elif trick_tuck < 0.0:
			target += -FWD * -trick_tuck * leg * 0.45 - UP * -trick_tuck * leg * 0.15
		if _fidget == "thump" and side == &"r":   # a bunny's warning thumps
			target += UP * leg * 0.16 * fk * absf(sin(_fidget_p * PI * 3.0))
		_two_bone(ul, ll, ft, _seg_len[side + "_leg1"], _seg_len[side + "_leg2"], target, pole)
		if ft >= 0:
			# keep the foot at its rest orientation (flat), toes dipping in the air
			var fb: Basis = (rig.rest[StringName(side + "_foot")] as Transform3D).basis
			_set_global_basis(ft, fb.rotated(RIGHT, _air * (0.3 + 0.2 * rise)))

	# ---- the jaw: rodents nibble ---------------------------------------------------------
	if _jaw >= 0 and _fidget == "chew":
		_rotate_global(_jaw, Quaternion(RIGHT, -fk * (0.5 + 0.5 * sin(_t * 17.0)) * 0.14))


# ---- life ------------------------------------------------------------------------------

## Start, run and end idle fidgets. They only start while the critter stands
## calmly (relaxed, still, upright), and fade out the moment it isn't.
func _update_fidget(delta: float, calm: bool) -> void:
	if _fidget == "":
		_fidget_wait -= delta if calm else 0.0
		if not calm:
			_fidget_wait = maxf(_fidget_wait, 1.5)
		if _fidget_wait <= 0.0:
			var choices := _fidget_choices()
			_fidget = choices[_rng.randi() % choices.size()]
			_fidget_p = 0.0
			_fidget_w = 0.0
			_fidget_dir = 1.0 if _rng.randf() < 0.5 else -1.0
			_fidget_wait = _rng.randf_range(4.0, 9.0)
		return
	_fidget_w = move_toward(_fidget_w, 1.0 if calm else 0.0, delta * (3.0 if calm else 6.0))
	_fidget_p += delta / float(FIDGET_TIME.get(_fidget, 2.0))
	if _fidget_p >= 1.0 or (not calm and _fidget_w <= 0.0):
		_fidget = ""


func _fidget_choices() -> Array:
	var list: Array = FIDGETS.get(rig.id, ["look", "stretch"])
	if not armed:
		return list
	var out := list.filter(func(f): return not PAWS_FREE.has(f))
	if not club:
		out.append("gun_check")
	return out


## The head wanders off the aim while the critter stands about relaxed: a
## glance here and there (or a long look round, the "look" fidget). Any sign
## of trouble snaps it back to the aim.
func _update_glance(delta: float, calm: bool, fk: float) -> void:
	if not calm:
		_glance_to = Vector2.ZERO
		_glance_wait = maxf(_glance_wait, 1.0)
	else:
		_glance_wait -= delta
		if _glance_wait <= 0.0:
			_glance_wait = _rng.randf_range(1.8, 4.5)
			_glance_to = Vector2.ZERO if _rng.randf() < 0.35 else \
				Vector2(_rng.randf_range(-0.5, 0.5), _rng.randf_range(-0.12, 0.08))
	var want := _glance_to
	if _fidget == "look":
		want = Vector2(_fidget_dir * 0.95, -0.06).lerp(want, 1.0 - fk)
	elif _fidget == "gun_check":
		want = want.lerp(Vector2(-0.35, -0.35), fk)
	elif _fidget == "stretch":
		want = want.lerp(Vector2(0.0, 0.3), fk)
	_glance = _glance.lerp(want, IKMath.damp(4.5 if calm else 10.0, delta))


## Turn the head off the aim by the glance (`steady` undoes the shoulders' run swing).
func _look_around(fk: float, steady: float) -> void:
	var tilt := 0.0
	if _fidget == "scratch":
		tilt = 0.25 * fk   # leaning into the scratch
	if _glance.length_squared() < 1e-6 and tilt == 0.0 and steady == 0.0:
		return
	var neck: int = rig.bone[&"neck"]
	var head: int = rig.bone[&"head"]
	if neck != head:
		_rotate_global(neck, Quaternion(UP, _glance.x * 0.4 + steady))
		steady = 0.0
	_rotate_global(head, Quaternion(UP, _glance.x * (0.6 if neck != head else 1.0) + steady) * Quaternion(RIGHT, _glance.y) * Quaternion(FWD, -tilt))


# ---- paws -------------------------------------------------------------------------------

## Where an empty paw goes (and where its elbow points): relaxed by the side
## standing about, pumping at the run, swinging with a hopper's bounds, up and
## out in the air, and the stretch and scratch fidgets.
func _free_paw(side: StringName, shoulder: Vector3, arm_len: float, S: float, hop_reach: float,
		breath: float, rise: float, fall: float, land: float, fk: float) -> Array:
	var sgn := 1.0 if side == &"r" else -1.0
	# (by the sides, not out in front: a club or a carrot finds whatever body
	# part is nearest, and forearms held forward would shield the chest)
	var target := shoulder - UP * arm_len * (0.86 + breath * 0.012) + FWD * arm_len * 0.04 + RIGHT * sgn * 0.06 * S
	var pole := shoulder + RIGHT * sgn * 0.3 * S - UP * 0.4 * S - FWD * 0.35 * S
	var swing: float
	if gait == CritterDef.Gait.HOP:
		swing = hop_reach            # both paws together
	else:
		swing = sin(_phase) * -sgn   # opposite to the legs
	var run := shoulder - UP * arm_len * (0.6 - 0.12 * swing) + FWD * arm_len * (0.12 + 0.38 * swing) + RIGHT * sgn * 0.04 * S
	target = target.lerp(run, _move)
	pole = pole.lerp(shoulder - FWD * 0.6 * S - UP * 0.25 * S + RIGHT * sgn * 0.15 * S, _move)
	# balance in the air: up and out, wider on the way down; a landing dips them
	target += (UP * arm_len * 0.35 + RIGHT * sgn * arm_len * 0.28) * (_air * 0.5 + rise * 0.2 + fall * 0.4)
	target += UP * arm_len * 0.3 * _takeoff
	target += (FWD * 0.12 * S - UP * 0.06 * S) * land
	if _fidget == "stretch":
		target = target.lerp(shoulder + UP * arm_len * 0.92 + RIGHT * sgn * 0.12 * S - FWD * 0.04 * S, fk)
		pole = pole.lerp(shoulder + RIGHT * sgn * 0.5 * S - FWD * 0.3 * S, fk)
	elif _fidget == "scratch" and side == &"r":
		var head := _g(rig.bone[&"head"]).origin
		var r: float = rig.radii.get(&"head", 0.1)
		var itch := head + RIGHT * r * 1.15 + UP * r * 0.5 + UP * sin(_t * 26.0) * 0.015 * S
		target = target.lerp(itch, fk)
		pole = pole.lerp(shoulder + RIGHT * 0.5 * S - UP * 0.1 * S, fk)
	return [target, pole]


# ---- guns -------------------------------------------------------------------------------

## How far the gun has to come forward so the trigger paw closes on its grip
## in front of the body, not inside a round tummy: the grip has to be a fist's
## depth outside the chest, spine and hip capsules.
func _torso_clearance(grip: Vector3, a: Vector3) -> float:
	var g: PawGrip = paws.get(&"r")
	var fist := (g.thickness if g and g.valid else 0.03 * rig.scale) * 0.8
	var push := 0.0
	# (the trunk where the hips put it: the spine bends too little to matter)
	var hips: int = rig.bone[&"hips"]
	var now := _g(hips) * (rig.rest[&"hips"] as Transform3D).affine_inverse()
	for role in [&"hips", &"spine", &"chest"]:
		var seg: Dictionary = rig.segments.get(role, {})
		if seg.is_empty():
			continue
		var p0: Vector3 = now * (seg["start"] as Vector3)
		var p1: Vector3 = now * (seg["end"] as Vector3)
		var c := Geometry3D.get_closest_point_to_segment(grip, p0, p1)
		var off := grip - c
		var ahead := off.dot(a)
		var side := (off - a * ahead).length()
		var reach: float = float(seg["radius"]) + fist
		if side < reach:
			push = maxf(push, sqrt(reach * reach - side * side) - ahead)
	return push


## Move a raised gun clear of the head, so long guns sit against the cheek
## and launchers on the shoulder instead of through the face: out to the
## right, or down under the chin if the other paw couldn't follow. The head is
## its capsule (neck joint to crown), sampled at three points. Returns the
## offset to add to the grip (skeleton space).
func _head_clearance(grip: Vector3, wb: Basis, arm_l: float) -> Vector3:
	var seg: Dictionary = rig.segments.get(&"head", {})
	if gun_box.size == Vector3.ZERO or seg.is_empty():
		return Vector3.ZERO
	var now := _g(rig.bone[&"head"]) * (rig.rest[&"head"] as Transform3D).affine_inverse()
	var a: Vector3 = now * (seg["start"] as Vector3)
	var b: Vector3 = now * (seg["end"] as Vector3)
	var r: float = seg["radius"] * 0.8   # (the capsule is a generous fit, for hits)
	var box := gun_box.grow(r)
	var out := 0.0
	var under := 0.0
	for k in 3:
		var c := wb.inverse() * (a.lerp(b, k * 0.5) - grip)   # in the gun's frame
		if box.has_point(c):
			out = maxf(out, c.x - box.position.x)
			under = maxf(under, box.end.y - c.y)
	if out <= 0.0:
		return Vector3.ZERO
	# out to the cheek is how a gun is shouldered, as far as the other paw can
	# follow it across; past that a gun drops under the chin instead. A
	# launcher always rides on the shoulder, beside the head (under the chin
	# its fat tube would be down at the tummy).
	if shouldered or out <= minf(r * 1.2, arm_l * 0.45):
		return wb.x * out
	return -wb.y * minf(under, r * 2.0)


## The gun as carried: lowered when relaxed (a launcher rests tipped up on
## the shoulder), across the chest at a sprint, nudged by breathing, dragging
## a little behind quick turns, and turned to look at in the gun-check fidget.
func _carried(grip: Vector3, wb: Basis, a: Vector3, up_s: Vector3, sh_r: Vector3, sh_mid: Vector3,
		hold: float, S: float, fk: float) -> Transform3D:
	var right := wb.x
	var low := maxf(1.0 - _up, _carry)
	if low > 0.001:
		# long guns tip down about the butt (it stays at the shoulder), pistols
		# about the paw, and both settle a little lower and in toward the middle;
		# at a sprint the muzzle also swings across in front of the body
		var dip := LOW_PITCH_SHOULDER if shouldered else (LOW_PITCH if two_handed else LOW_PITCH_PISTOL)
		dip = lerpf(dip, CARRY_PITCH, _carry)
		var pivot := Vector3(0, 0, gun_box.end.z * 0.7) if two_handed and not shouldered else Vector3.ZERO
		var lb := wb.rotated(up_s, CARRY_YAW * _carry * float(two_handed)).rotated(right, -dip)
		var lg := grip + wb * pivot - lb * pivot - up_s * (0.02 if shouldered else 0.05) * S + (sh_mid - sh_r) * 0.1
		if not two_handed:
			lg -= a * hold * (0.25 + 0.3 * _carry)   # a pistol comes in toward the chest
		grip = grip.lerp(lg, low)
		wb = wb.slerp(lb, low)
	if _fidget == "gun_check" and fk > 0.0:
		grip = grip.lerp(grip + (sh_mid - sh_r) * 0.35 + up_s * 0.05 * S - a * hold * 0.2, fk)
		wb = wb.slerp(wb.rotated(a, 0.9).rotated(right, 0.2), fk)
	grip += up_s * sin(_breath) * 0.006 * S * _still
	return Transform3D(wb.rotated(up_s, _sway.x).rotated(right, _sway.y), grip)


## How the gun lags a quick turn of the aim and swings back (call per frame).
func _update_sway(delta: float) -> void:
	var yaw := atan2(aim_dir.x, aim_dir.z)
	var pitch := asin(clampf(aim_dir.y, -1.0, 1.0))
	var now := Vector2(yaw, pitch)
	if delta > 0.0:
		var rate := Vector2(wrapf(now.x - _aim_prev.x, -PI, PI), now.y - _aim_prev.y) / delta
		var want := Vector2(clampf(-rate.x * 0.025, -0.14, 0.14), clampf(-rate.y * 0.025, -0.1, 0.1))
		_sway = _sway.lerp(want, IKMath.damp(9.0, delta))
	_aim_prev = now


## The critter's facing in the world, and the planted feet's bookkeeping for
## turning on the spot: when the body has turned TURN_STEP past a foot, that
## foot steps round (one foot at a time).
func _turn_feet(skel: Skeleton3D, turning: bool, delta: float) -> float:
	var f := skel.global_basis * FWD
	var yaw := atan2(f.x, f.z)
	if not turning:
		_plant_yaw[&"l"] = yaw
		_plant_yaw[&"r"] = yaw
		_step_side = &""
		return yaw
	if _step_side != &"":
		_step_p += delta / STEP_TIME
		if _step_p >= 1.0:
			_plant_yaw[_step_side] = yaw
			_step_side = &""
	else:
		var off_l := absf(wrapf(yaw - _plant_yaw[&"l"], -PI, PI))
		var off_r := absf(wrapf(yaw - _plant_yaw[&"r"], -PI, PI))
		if maxf(off_l, off_r) > TURN_STEP:
			_step_side = &"l" if off_l > off_r else &"r"
			_step_p = 0.0
	return yaw


## Where a paw goes in the army crawl (skeleton space; the body lies on its
## belly, so +Y points ahead and +Z down at the ground `depth` below the spine).
## Planted for CRAWL_STANCE of the cycle, sliding back exactly as fast as the
## body moves forward; then lifted and swung ahead to plant again.
func _crawl_paw(side: StringName, shoulder: Vector3, arm_len: float, depth: float, S: float) -> Vector3:
	var sgn := 1.0 if side == &"r" else -1.0
	var u := fposmod((_phase + (0.0 if side == &"r" else PI)) / TAU, 1.0)
	var along: float
	var lift := 0.0
	if u < CRAWL_STANCE:
		along = lerpf(0.5, -0.5, u / CRAWL_STANCE)
	else:
		var t := (u - CRAWL_STANCE) / (1.0 - CRAWL_STANCE)
		along = lerpf(-0.5, 0.5, smoothstep(0.0, 1.0, t))
		lift = sin(t * PI)
	var ahead := arm_len * 0.35 + along * arm_len * CRAWL_PULL * _crawl
	var down := minf(depth, arm_len * 0.8) - lift * arm_len * 0.22 * _crawl
	return shoulder + UP * ahead + FWD * down + RIGHT * sgn * 0.1 * S


## Club tilt above the aim line through a swing (0..1; -1 = resting). A quick
## wind-up, then the club whips down through level with the chest exactly at
## Critter.MELEE_HIT_AT (when the hit lands), and a slower recovery.
const CLUB_WIND_END := 0.18
const CLUB_STRIKE_END := 0.34


static func _club_angle(p: float) -> float:
	const REST := 1.15     # up and forward, ready
	const BACK := 2.5      # wound up over the shoulder
	const LOW := -0.6      # follow-through, low in front
	if p < 0.0:
		return REST
	if p < CLUB_WIND_END:
		return lerpf(REST, BACK, smoothstep(0.0, CLUB_WIND_END, p))
	if p < CLUB_STRIKE_END:
		return lerpf(BACK, LOW, smoothstep(CLUB_WIND_END, CLUB_STRIKE_END, p))
	return lerpf(LOW, REST, smoothstep(CLUB_STRIKE_END, 1.0, p))


## 0..1: how far into the blow the swing is (lunge and twist), peaking on impact.
static func _club_strike(p: float) -> float:
	if p < 0.0:
		return 0.0
	return smoothstep(CLUB_WIND_END - 0.06, 0.29, p) * (1.0 - smoothstep(CLUB_STRIKE_END, 0.8, p))


## The handle a paw closes on (skeleton space): [where it runs through the
## fist, the knuckle line (little finger → index), out of the palm, finger
## curl] (and for a fore-end, the way back along it and how far); [] for none. The trigger paw wraps the pistol grip (raked back like
## the guns' grips, palm on its right side, fingers round the front), or the
## club's handle; the other paw cups the fore-end from below (palm up,
## fingers up its far side), or wraps the trigger paw on a pistol.
func _handle(side: StringName, grip: Vector3, wb: Basis, skel: Skeleton3D, S: float) -> Array:
	if side == &"r":
		if club:
			return [grip, -wb.z, _square(-wb.x, -wb.z), 1.0, null, 0.0, -0.6, 0.6]
		var rake := (wb * Vector3(0.0, 0.975, -0.22)).normalized()   # up the grip
		return [grip, rake, _square(-wb.x * 0.85 - wb.z * 0.3, rake), 1.0, null, 0.0, -0.45, 0.45]
	if club:
		return []
	var g: PawGrip = paws.get(&"l")
	var depth := g.thickness if g else 0.03 * S
	if not two_handed:
		var other: PawGrip = paws.get(&"r")
		var gap := ((other.thickness if other else 0.03 * S) + depth) * 0.55
		var rake := (wb * Vector3(0.0, 0.975, -0.22)).normalized()
		return [grip - wb.x * gap - rake * depth * 0.4, rake, _square(wb.x, rake), 0.8, null, 0.0, -0.9, 0.9]
	var at := _support_point(skel, grip, wb, S)
	# (+ which way the paw can slide back along the fore-end, and how far
	# before it bumps into the trigger paw; then how far it may turn: from
	# cupping it from below, palm up, round to the left side, palm in)
	var fists := ((paws[&"r"] as PawGrip).width if paws.has(&"r") else 0.06 * S) * 0.5 + (g.width if g else 0.06 * S) * 0.5
	# (turning about the barrel, forward, a positive turn rolls the palm from up to the gun's left side)
	return [at + wb.y * depth * 0.3, -wb.z, wb.y, 0.7, wb.z, maxf(0.0, (grip - at).dot(wb.z) - fists * 1.1), -0.25, 1.35]


## The paw's orientation on its handle: a fist can turn round the handle, so
## try turns within its range and keep the one whose wrist bends least from
## the line the forearm will take (solved with the same IK the arm uses),
## with a mild preference for the handle's natural hold.
func _best_turn(side: StringName, g: PawGrip, at: Vector3, frame: Array, shoulder: Vector3, l1: float, l2: float,
		pole: Vector3) -> Basis:
	var w: Vector3 = frame[1]
	var lo: float = frame[6] if frame.size() > 6 else -ROLL_RANGE
	var hi: float = frame[7] if frame.size() > 7 else ROLL_RANGE
	var best := Basis()
	var best_cost := INF
	for i in ROLL_STEPS:
		var roll := lerpf(lo, hi, float(i) / float(ROLL_STEPS - 1))
		var pl := Basis(w, roll) * (frame[2] as Vector3)
		var hb := g.hand_basis((pl.cross(w) if side == &"r" else w.cross(pl)).normalized(), w, pl)
		var wrist := at - hb * g.hold
		var sol := IKMath.solve_two_bone(shoulder, l1, l2, wrist, pole)
		var cost := (sol[1] - sol[0]).angle_to(hb * g.along) + absf(roll) * 0.15
		if cost < best_cost:
			best_cost = cost
			best = hb
	return best


## How far back along `axis` (at most `most`) a wrist `d` from the shoulder
## must slide to come within `reach` of it (or as close as the line gets).
static func _slide(d: Vector3, axis: Vector3, most: float, reach: float) -> float:
	var dz := d.dot(axis)
	var disc := dz * dz - d.length_squared() + reach * reach
	return clampf(-dz - sqrt(disc) if disc >= 0.0 else -dz, 0.0, most)


## `v` made square to `axis` (unit).
static func _square(v: Vector3, axis: Vector3) -> Vector3:
	return (v - axis * v.dot(axis)).normalized()


## Turn a paw closed on a handle (`held`: [hand basis, curl]) and curl its
## fingers round; an empty paw just relaxes, its fingers loosely bent.
func _measure_grip(side: StringName, lower: int, hand: int, held: Array, S: float) -> void:
	if not measuring:
		return
	var g: PawGrip = paws.get(side)
	if held.is_empty() or hand < 0 or g == null or not g.valid:
		grip_miss[side] = -1.0
		wrist_bend[side] = -1.0
		return
	var h := _g(hand)
	var hb := h.basis.orthonormalized()
	grip_miss[side] = (h.origin + hb * g.hold).distance_to(held[2]) / (rig.head_top * S / rig.scale)
	wrist_bend[side] = (h.origin - _g(lower).origin).angle_to(hb * g.along)


func _close_paw(side: StringName, hand: int, held: Array, relaxed: float) -> void:
	var g: PawGrip = paws.get(side)
	if hand < 0 or g == null or not g.valid:
		return
	var curl := relaxed
	if not held.is_empty():
		_set_global_basis(hand, held[0])
		curl = held[1]
	# (each joint turns toward the palm in its own frame: PawGrip.curl_axis)
	var skel := get_skeleton()
	for chain in g.fingers:
		for j in (chain as PackedInt32Array).size():
			var b: int = chain[j]
			skel.set_bone_pose_rotation(b, g.rest_rot[b] * Quaternion(g.curl_axis[b], FINGER_CURL[mini(j, 2)] * curl))
	for b in g.thumb:
		skel.set_bone_pose_rotation(b, g.rest_rot[b] * Quaternion(g.curl_axis[b], 0.45 * curl))


func _support_point(skel: Skeleton3D, grip: Vector3, wbasis: Basis, S: float) -> Vector3:
	if two_handed and support_marker and is_instance_valid(support_marker):
		return skel.global_transform.affine_inverse() * support_marker.global_position
	if two_handed:
		return grip - wbasis.z * 0.22 * S + wbasis.y * 0.02 * S
	# one-handed pistol: the other paw cups the grip
	return grip + wbasis.x * -0.035 * S - wbasis.y * 0.03 * S


# ---- skeleton helpers (skeleton space) ---------------------------------------------

func _g(idx: int) -> Transform3D:
	return get_skeleton().get_bone_global_pose(idx)


func _rotate_global(idx: int, q: Quaternion) -> void:
	_set_global_basis(idx, Basis(q) * _g(idx).basis.orthonormalized())


func _set_global_basis(idx: int, b: Basis) -> void:
	var skel := get_skeleton()
	var p := skel.get_bone_parent(idx)
	var pb := _g(p).basis.orthonormalized() if p >= 0 else Basis.IDENTITY
	skel.set_bone_pose_rotation(idx, (pb.inverse() * b.orthonormalized()).get_rotation_quaternion())


func _set_global_origin(idx: int, pos: Vector3) -> void:
	var skel := get_skeleton()
	var p := skel.get_bone_parent(idx)
	var local := pos if p < 0 else _g(p).affine_inverse() * pos
	skel.set_bone_pose_position(idx, local)


## Lengthen a whole arm k times by sliding the elbow and the paw out along
## their bones (no bone scale: hitboxes ride on the bones, and the physics
## engine wants them unscaled). The skin between stretches like taffy.
## The skeleton restores the rest pose every frame, so this lasts one frame.
## (Every bone between the elbow and the paw stretches: some rigs have two
## forearm bones.)
func _stretch_arm(lower: int, hand: int, k: float) -> void:
	var skel := get_skeleton()
	skel.set_bone_pose_position(lower, skel.get_bone_rest(lower).origin * k)
	var i := hand
	while i >= 0 and i != lower:
		skel.set_bone_pose_position(i, skel.get_bone_rest(i).origin * k)
		i = skel.get_bone_parent(i)


func _two_bone(upper: int, lower: int, end: int, l1: float, l2: float, target: Vector3, pole: Vector3) -> void:
	var root := _g(upper).origin
	var sol := IKMath.solve_two_bone(root, l1, l2, target, pole)
	var cur_mid := _g(lower).origin
	_rotate_global(upper, IKMath.from_to(cur_mid - root, sol[0] - root))
	var mid := _g(lower).origin
	var cur_end := _end_pos(lower, end, l2)
	_rotate_global(lower, IKMath.from_to(cur_end - mid, sol[1] - mid))


func _end_pos(lower: int, end: int, l2: float) -> Vector3:
	if end >= 0:
		return _g(end).origin
	var g := _g(lower)
	return g.origin + g.basis.y.normalized() * l2


func _rest_dist(a: StringName, b: StringName) -> float:
	return (rig.rest[a] as Transform3D).origin.distance_to((rig.rest[b] as Transform3D).origin)


func _rest_dist_end(a: StringName, b: StringName) -> float:
	if rig.has_role(b):
		return _rest_dist(a, b)
	var seg: Dictionary = rig.segments.get(a, {})
	return (seg.get("end", Vector3.ZERO) as Vector3).distance_to(seg.get("start", Vector3.ZERO)) if seg else 0.2
