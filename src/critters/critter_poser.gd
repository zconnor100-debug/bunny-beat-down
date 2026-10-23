class_name CritterPoser
extends SkeletonModifier3D
## Fully procedural animation — no keyframes. Every frame, starting from the
## rest pose, it:
##   1. advances a gait cycle from the critter's real velocity (run, or hop for bunnies)
##   2. moves/leans the hips (bob, crouch, landing squash, hit flinch)
##   3. twists spine → chest → neck → head to follow the aim
##   4. places the held weapon in front of the shoulder (recoil + reload tilt)
##   5. solves two-bone IK so both paws grip the gun's real grip markers
##   6. solves two-bone IK for the legs to the gait's foot targets
## Ears and tails are left to the SpringBoneSimulator3D that runs after this.
##
## All maths happens in skeleton space. Models face +Z there, so the critter's
## right-hand side is −X.

const UP := Vector3.UP
const FWD := Vector3(0, 0, 1)
const RIGHT := Vector3(-1, 0, 0)
## Hop length = leg * (HOP_BASE + speed * HOP_PER_SPEED); the airborne share
## of each hop cycle is HOP_AIR (the rest is the crouch-and-push contact).
const HOP_BASE := 3.2
const HOP_PER_SPEED := 0.35
const HOP_AIR := 0.72

signal footstep(hop: bool)

var rig: RigInfo
var holder: Node3D            ## weapon holder, placed by this modifier
var support_marker: Node3D    ## "SupportGrip" inside the weapon model (optional)

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
var melee := -1.0             ## 0..1 through a club swing, -1 otherwise
var recoil := 0.0             ## 0..1, decays in CritterVisual
var trick_tuck := 0.0         ## +1 tuck limbs in (flips, rolls), -1 stretch out (leaps)
var trick_active := false     ## mid-trick: stop tracking the aim, the body is spinning

# ---- internal state ---------------------------------------------------------------
var _phase := 0.0
var _prev_phase := 0.0
var _move := 0.0
var _air := 0.0
var _land := 0.0
var _flinch := Vector3.ZERO
var _flinch_vel := Vector3.ZERO
var _lean := 0.0
var _seg_len: Dictionary = {}


func setup(rig_: RigInfo) -> void:
	rig = rig_
	for side in [&"l", &"r"]:
		_seg_len[side + "_arm1"] = _rest_dist(StringName(side + "_upper_arm"), StringName(side + "_lower_arm"))
		_seg_len[side + "_arm2"] = _rest_dist_end(StringName(side + "_lower_arm"), StringName(side + "_hand"))
		_seg_len[side + "_leg1"] = _rest_dist(StringName(side + "_upper_leg"), StringName(side + "_lower_leg"))
		_seg_len[side + "_leg2"] = _rest_dist_end(StringName(side + "_lower_leg"), StringName(side + "_foot"))


## Called by the critter when it touches down.
func on_landed(impact_speed: float) -> void:
	_land = clampf(impact_speed / 14.0, 0.0, 1.0)


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


func _process_modification_with_delta(delta: float) -> void:
	var skel := get_skeleton()
	if skel == null or rig == null:
		return
	delta = minf(delta, 0.05)
	var to_skel := skel.global_basis.orthonormalized().inverse()
	var v := to_skel * velocity / rig.size   # model units (the model node is scaled)
	var hv := Vector3(v.x, 0.0, v.z)
	var speed := hv.length()
	var move_dir := hv / speed if speed > 0.05 else FWD
	var S := rig.scale
	var leg: float = (rig.leg_length[&"l"] + rig.leg_length[&"r"]) * 0.5

	_move = lerpf(_move, clampf(speed / (2.2 * S), 0.0, 1.0), IKMath.damp(10.0, delta))
	_air = lerpf(_air, 0.0 if grounded else 1.0, IKMath.damp(10.0, delta))
	_land = move_toward(_land, 0.0, delta * 3.0)
	# damped spring for the hit flinch
	_flinch_vel += (-_flinch * 120.0 - _flinch_vel * 14.0) * delta
	_flinch += _flinch_vel * delta
	_lean = lerpf(_lean, clampf(speed / (9.0 * S), 0.0, 1.0) * 0.22, IKMath.damp(6.0, delta))

	# ---- gait clock -------------------------------------------------------------
	var stride := leg * (0.85 + speed * 0.06 / S)
	# bunnies take long bounding hops (~2.5–3.5 per second), not a rapid patter
	var hop_len := leg * (HOP_BASE + speed * HOP_PER_SPEED / S)
	if gait == CritterDef.Gait.HOP:
		_phase = fposmod(_phase + speed / hop_len * TAU * delta, TAU)
	else:
		_phase = fposmod(_phase + speed / (2.0 * stride) * TAU * delta, TAU)
	# a foot (or both, for a hop) touches down: tell the critter for footstep audio
	if grounded and speed > 0.8:
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
	hip_pos.y -= leg * (0.05 + crouch * 0.28 + _land * 0.22)
	var hop_air := 0.0
	if gait == CritterDef.Gait.HOP:
		var u := _phase / TAU
		hop_air = sin(u / HOP_AIR * PI) if u < HOP_AIR else 0.0
		var squash := sin((u - HOP_AIR) / (1.0 - HOP_AIR) * PI) if u >= HOP_AIR else 0.0
		# longer hops arc higher; a little forward pitch on take-off, nose-up on landing
		hip_pos.y += _move * (leg * 0.68 * hop_air - leg * 0.1 * squash) * (1.0 - _air)
	else:
		hip_pos.y -= _move * leg * (0.03 + 0.05 * (0.5 - 0.5 * cos(2.0 * _phase)))
		hip_pos += RIGHT * sin(_phase) * 0.012 * S * _move
	# idle breathing
	hip_pos.y += sin(Time.get_ticks_msec() * 0.0025) * 0.004 * S * (1.0 - _move)
	_set_global_origin(hips, hip_pos)
	_rotate_global(hips, Quaternion(RIGHT, -_lean))
	if gait == CritterDef.Gait.RUN:
		_rotate_global(hips, Quaternion(UP, sin(_phase) * 0.12 * _move))

	# ---- spine aims ---------------------------------------------------------------
	var a := FWD if trick_active else (to_skel * aim_dir).normalized()
	var pitch := clampf(asin(clampf(a.y, -1.0, 1.0)), -1.3, 1.3)
	var yaw := clampf(atan2(-a.x, a.z) * -1.0, -1.0, 1.0)
	var chain := [[&"spine", 0.25, 0.3], [&"chest", 0.35, 0.4], [&"neck", 0.15, 0.1], [&"head", 0.25, 0.2]]
	var done := {}
	var fl_len := _flinch.length()
	for item in chain:
		var idx: int = rig.bone.get(item[0], -1)
		if idx < 0 or done.has(idx) or idx == hips:
			continue
		done[idx] = true
		var q := Quaternion(UP, yaw * item[2]) * Quaternion(RIGHT, (pitch + _lean) * item[1])
		if fl_len > 0.001 and item[0] in [&"spine", &"chest"]:
			q = Quaternion(_flinch / fl_len, fl_len * 0.5) * q
		_rotate_global(idx, q)

	# ---- weapon placement ------------------------------------------------------------
	var sh_r := _g(rig.bone[&"r_upper_arm"]).origin
	var sh_l := _g(rig.bone[&"l_upper_arm"]).origin
	var sh_mid := (sh_r + sh_l) * 0.5
	var grip := Vector3.ZERO
	var wbasis := Basis.looking_at(a, UP if absf(a.y) < 0.98 else FWD)
	var reload_k := 0.0
	if reload_progress >= 0.0:
		reload_k = sin(clampf(reload_progress, 0.0, 1.0) * PI)
	if holder:
		holder.visible = armed and not gliding
	if armed and not gliding:
		var down := -wbasis.y
		var right := wbasis.x
		var hold := hold_distance * S
		if club:
			# club: held up by the right shoulder; a swing winds it back over the
			# shoulder, then brings it down across the body
			grip = sh_r + a * hold * 0.6 + down * 0.04 * S + right * 0.06 * S
			wbasis = wbasis.rotated(right, _club_angle(melee))
			if melee >= 0.0:
				var strike := sin(clampf(melee, 0.0, 1.0) * PI)
				grip += a * strike * 0.12 * S
				wbasis = wbasis.rotated(a, -0.5 * strike)
		elif two_handed:
			grip = sh_r.lerp(sh_mid, 0.35) + a * hold + down * 0.07 * S
		else:
			grip = sh_mid.lerp(sh_r, 0.4) + a * hold + down * 0.02 * S
		grip -= a * recoil * 0.05 * S
		wbasis = wbasis.rotated(right, recoil * 0.25)
		if reload_k > 0.0:
			wbasis = wbasis.rotated(a, -reload_k * 0.6).rotated(right, -reload_k * 0.35)
			grip += down * reload_k * 0.05 * S
		if holder:
			holder.global_transform = skel.global_transform * Transform3D(wbasis, grip)

	# ---- arms -------------------------------------------------------------------------
	var swing := sin(_phase) * 0.14 * S * _move
	for side in [&"r", &"l"]:
		var sgn := 1.0 if side == &"r" else -1.0
		var up_i: int = rig.bone[StringName(side + "_upper_arm")]
		var lo_i: int = rig.bone[StringName(side + "_lower_arm")]
		var hand_i: int = rig.bone.get(StringName(side + "_hand"), -1)
		var shoulder := sh_r if side == &"r" else sh_l
		var arm_len: float = _seg_len[side + "_arm1"] + _seg_len[side + "_arm2"]
		var target: Vector3
		var pole := shoulder + RIGHT * sgn * 0.35 * S - UP * 0.45 * S - FWD * 0.25 * S
		if gliding:
			target = sh_mid + UP * 0.5 * S + RIGHT * sgn * 0.1 * S
			pole = shoulder + RIGHT * sgn * 0.5 * S - FWD * 0.2 * S
		elif armed:
			if side == &"r":
				target = grip
			else:
				target = _support_point(skel, grip, wbasis, S)
				if reload_k > 0.0:
					var pouch := (rig.rest[&"hips"] as Transform3D).origin + RIGHT * -0.12 * S + FWD * 0.05 * S
					var mag := grip - wbasis.y * 0.08 * S - wbasis.z * 0.06 * S
					var rp := clampf(reload_progress, 0.0, 1.0)
					target = target.lerp(mag, smoothstep(0.0, 0.25, rp)).lerp(pouch, smoothstep(0.3, 0.5, rp) * (1.0 - smoothstep(0.55, 0.8, rp)))
		else:
			var s := swing * (-sgn) * (-1.0 if gait == CritterDef.Gait.HOP else 1.0)
			if gait == CritterDef.Gait.HOP:
				s = -hop_air * 0.12 * S * _move
			target = shoulder - UP * arm_len * 0.9 + FWD * s + RIGHT * sgn * 0.05 * S + UP * _air * arm_len * 0.5
		_two_bone(up_i, lo_i, hand_i, _seg_len[side + "_arm1"], _seg_len[side + "_arm2"], target, pole)

	# ---- legs -------------------------------------------------------------------------
	for side in [&"l", &"r"]:
		var sgn := 1.0 if side == &"r" else -1.0
		var ul: int = rig.bone[StringName(side + "_upper_leg")]
		var ll: int = rig.bone[StringName(side + "_lower_leg")]
		var ft: int = rig.bone.get(StringName(side + "_foot"), -1)
		var rest_foot: Vector3 = (rig.rest[StringName(side + "_foot")] as Transform3D).origin if ft >= 0 \
			else _g(ll).origin * Vector3(1, 0, 1) + UP * 0.05 * S
		var target := rest_foot
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
			var ph := _phase + (0.0 if side == &"l" else PI)
			target += move_dir * (-cos(ph) * stride * 0.5 * _move)
			target += UP * maxf(0.0, sin(ph)) * leg * 0.22 * _move
		# tuck in the air (harder for flips and rolls, stretched out for leaps)
		target += UP * _air * leg * 0.28 - FWD * _air * 0.04 * S
		if trick_tuck > 0.0:
			target += UP * trick_tuck * leg * 0.3 + FWD * trick_tuck * 0.08 * S
		elif trick_tuck < 0.0:
			target += -FWD * -trick_tuck * leg * 0.45 - UP * -trick_tuck * leg * 0.15
		var hip := _g(ul).origin
		var pole := hip + FWD * leg + RIGHT * sgn * 0.08 * S
		_two_bone(ul, ll, ft, _seg_len[side + "_leg1"], _seg_len[side + "_leg2"], target, pole)
		if ft >= 0:
			# keep the foot at its rest orientation (flat), tilted slightly by the gait
			var fb: Basis = (rig.rest[StringName(side + "_foot")] as Transform3D).basis
			_set_global_basis(ft, fb.rotated(RIGHT, _air * 0.3))


## Club tilt above the aim line through a swing (0..1; -1 = resting).
static func _club_angle(p: float) -> float:
	const REST := 1.15     # up and forward, ready
	const BACK := 2.5      # wound up over the shoulder
	const LOW := -0.6      # follow-through, low in front
	if p < 0.0:
		return REST
	if p < 0.35:
		return lerpf(REST, BACK, smoothstep(0.0, 0.35, p))
	if p < 0.5:
		return lerpf(BACK, LOW, smoothstep(0.35, 0.5, p))
	return lerpf(LOW, REST, smoothstep(0.5, 1.0, p))


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
