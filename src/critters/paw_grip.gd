class_name PawGrip
extends RefCounted
## How a critter's paw closes on a handle, measured once per model from its
## skinned mesh: the paw's vertices (everything weighted to the hand bone and
## its fingers), in the hand bone's own frame. From them: which way the paw
## runs (wrist → fingertips), which way across the knuckles (little finger →
## index), which side the palm is on, how thick the paw is, the point a
## handle should run through (the hole of the fist, or the middle of a
## mitten paw), and the finger chains to curl. CritterPoser turns the hand
## to the handle, puts that point on it and curls the fingers round.
##
## Rigs differ (named fingers, a single finger bone, no fingers at all): the
## knuckle direction comes from the index and little fingers when the bones
## are named, otherwise from the shape of the paw, with the palm taken to
## face down in the rest pose (the way characters are rigged).

const INDEX := ["index", "pointer", "indice"]
const LITTLE := ["pinky", "little", "menique", "meñique"]
const THUMB := ["thumb", "pulgar"]

static var _cache := {}   # model path -> {&"l": PawGrip, &"r": PawGrip}

var valid := false
var along := Vector3.UP          ## wrist → fingertips (unit, hand-bone space)
var across := Vector3.RIGHT      ## little finger → index (unit, ⟂ along)
var palm := Vector3.FORWARD      ## out of the palm (unit)
var thickness := 0.03            ## the paw's depth, back to palm (model units)
var width := 0.06                ## the fist's breadth across the knuckles (model units)
var hold := Vector3.ZERO         ## where a handle runs through (hand-bone space)
var fingers: Array = []          ## [PackedInt32Array] proximal → distal, thumb apart
var thumb := PackedInt32Array()
## Per finger (and thumb) bone: its rest rotation, and the axis that curls it
## toward the palm in its own frame (every joint of a fist turns about the
## same line, so it's worked out once and the poser just sets rotations).
var rest_rot := {}
var curl_axis := {}


## Both paws of this visual's model (measured on first use, then shared).
static func paws(visual: CritterVisual) -> Dictionary:
	var key := visual.def.resolved_model()
	if not _cache.has(key):
		_cache[key] = _measure_both(visual)
	return _cache[key]


static func _measure_both(visual: CritterVisual) -> Dictionary:
	var out := {}
	var skel := visual.skeleton
	var groups := {}
	for side in [&"l", &"r"]:
		var g := PawGrip.new()
		out[side] = g
		var hand: int = visual.rig.bone.get(StringName(side + "_hand"), -1)
		if hand < 0:
			continue
		var members := {}
		for b in visual.rig.subtree(hand):
			members[b] = true
		groups[side] = [hand, members, [], skel.get_bone_global_rest(hand).affine_inverse()]   # (a plain Array: a packed one would copy on append)
	# the paws' vertices, in each hand bone's rest frame
	for m in visual.meshes:
		if m.mesh == null or m.skin == null:
			continue
		var bind_bone := PackedInt32Array()
		for k in m.skin.get_bind_count():
			var b := m.skin.get_bind_bone(k)
			bind_bone.append(b if b >= 0 else skel.find_bone(m.skin.get_bind_name(k)))
		var to_skel := skel.global_transform.affine_inverse() * m.global_transform
		for si in m.mesh.get_surface_count():
			var arr := m.mesh.surface_get_arrays(si)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES] if arr[Mesh.ARRAY_BONES] != null else PackedInt32Array()
			var weights: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS] if arr[Mesh.ARRAY_WEIGHTS] != null else PackedFloat32Array()
			if verts.is_empty() or weights.is_empty():
				continue
			var per := weights.size() / verts.size()
			for vi in verts.size():
				for side in groups:
					var grp: Array = groups[side]
					var w := 0.0
					for j in per:
						var bi := bones[vi * per + j]
						if bi < bind_bone.size() and grp[1].has(bind_bone[bi]):
							w += weights[vi * per + j]
					if w >= 0.5:
						(grp[2] as Array).append(grp[3] * (to_skel * verts[vi]))
	for side in groups:
		var grp: Array = groups[side]
		(out[side] as PawGrip)._fit(visual, side, grp[0], grp[2])
	return out


func _fit(visual: CritterVisual, side: StringName, hand: int, pts: Array) -> void:
	var skel := visual.skeleton
	var rest_inv := skel.get_bone_global_rest(hand).affine_inverse()
	var idx_root := Vector3.INF
	var little_root := Vector3.INF
	var roots := []
	for c in skel.get_bone_children(hand):
		var chain := PackedInt32Array([c])
		while not skel.get_bone_children(chain[chain.size() - 1]).is_empty():
			chain.append(skel.get_bone_children(chain[chain.size() - 1])[0])
		var name := skel.get_bone_name(c).to_lower()
		var at := rest_inv * skel.get_bone_global_rest(c).origin
		if THUMB.any(func(n): return name.contains(n)):
			thumb = chain
			continue
		fingers.append(chain)
		roots.append(at)
		# (where a finger lies: the middle of its joints, not its root; some rigs
		# start every finger from one point in the palm)
		var mid := Vector3.ZERO
		for b in chain:
			mid += rest_inv * skel.get_bone_global_rest(b).origin
		mid /= chain.size()
		if INDEX.any(func(n): return name.contains(n)):
			idx_root = mid
		elif LITTLE.any(func(n): return name.contains(n)):
			little_root = mid
	if pts.size() < 8:
		return
	var centre := Vector3.ZERO
	for p: Vector3 in pts:
		centre += p
	centre /= pts.size()
	if centre.length() < 1e-4:
		return
	along = centre.normalized()
	# across the knuckles: named fingers if there are any, else the paw's widest
	# direction square to `along` (2-D principal axis of the paw's outline)
	if idx_root != Vector3.INF and little_root != Vector3.INF:
		across = _reject(idx_root - little_root, along)
	else:
		var u := _reject(Vector3.UP if absf(along.y) < 0.9 else Vector3.RIGHT, along)
		var v := along.cross(u)
		var cuu := 0.0
		var cvv := 0.0
		var cuv := 0.0
		for p: Vector3 in pts:
			var q := p - centre
			var a := q.dot(u)
			var b := q.dot(v)
			cuu += a * a
			cvv += b * b
			cuv += a * b
		var ang := 0.5 * atan2(2.0 * cuv, cuu - cvv)
		across = (u * cos(ang) + v * sin(ang)).normalized()
	palm = _palm_of(side, along, across)
	if idx_root == Vector3.INF or little_root == Vector3.INF:
		# no named fingers: the palm faces down (and in) in the rest pose
		var rest_basis := skel.get_bone_global_rest(hand).basis
		var inward := Vector3(-signf(skel.get_bone_global_rest(hand).origin.x), 0, 0)
		if (rest_basis * palm).dot(Vector3.DOWN + inward * 0.7) < 0.0:
			across = -across
			palm = _palm_of(side, along, across)
	var lo := INF
	var hi := -INF
	for p: Vector3 in pts:
		lo = minf(lo, p.dot(palm))
		hi = maxf(hi, p.dot(palm))
	thickness = maxf(hi - lo, 0.005)
	var a_lo := INF
	var a_hi := -INF
	for p: Vector3 in pts:
		a_lo = minf(a_lo, p.dot(across))
		a_hi = maxf(a_hi, p.dot(across))
	width = maxf(a_hi - a_lo, 0.01)
	if idx_root != Vector3.INF and little_root != Vector3.INF:
		# closed, a fist is as broad as its knuckles (splayed fingers and a
		# thumb sticking out made the outline far wider)
		width = minf(width, idx_root.distance_to(little_root) * 1.5)
	# where a handle runs through. A paw with fingers closes round it: with the
	# first two joints bent about square, the hole of the fist is half the first
	# segment out from the knuckles toward the palm side, and half the second
	# back toward the wrist. A mitten paw can't close, so the handle sits
	# against the middle of its palm instead of running through it.
	if not roots.is_empty():
		var k := Vector3.ZERO
		var first := 0.0
		var second := 0.0
		for i in fingers.size():
			k += roots[i]
			var segs := _segments(skel, rest_inv, fingers[i], centre.length())
			first += segs[0]
			second += segs[1]
		k /= roots.size()
		first /= fingers.size()
		second /= fingers.size()
		hold = k + palm * first * 0.5 - along * second * 0.5
	else:
		hold = centre + palm * (hi - centre.dot(palm) + thickness * 0.3)
	var axis := along.cross(palm).normalized()
	var hand_rest := skel.get_bone_global_rest(hand)
	for chain in fingers + [thumb]:
		for b in (chain as PackedInt32Array):
			var in_hand := (hand_rest.affine_inverse() * skel.get_bone_global_rest(b)).basis.orthonormalized()
			rest_rot[b] = skel.get_bone_rest(b).basis.orthonormalized().get_rotation_quaternion()
			curl_axis[b] = (in_hand.inverse() * axis).normalized()
	valid = true


## A finger's first two segment lengths (hand-bone space); a finger with one
## bone gets a share of the paw's length.
static func _segments(skel: Skeleton3D, rest_inv: Transform3D, chain: PackedInt32Array, paw: float) -> Array:
	var at := []
	for b in chain:
		at.append(rest_inv * skel.get_bone_global_rest(b).origin)
	var first: float = (at[1] as Vector3).distance_to(at[0]) if at.size() > 1 else paw * 0.35
	var second: float = (at[2] as Vector3).distance_to(at[1]) if at.size() > 2 else first * 0.8
	return [first, second]


## Out of the palm, from the paw's two directions (the right paw is the
## mirror image of the left).
static func _palm_of(side: StringName, along_: Vector3, across_: Vector3) -> Vector3:
	return (across_.cross(along_) if side == &"r" else along_.cross(across_)).normalized()


static func _reject(v: Vector3, axis: Vector3) -> Vector3:
	return (v - axis * v.dot(axis)).normalized()


## The hand bone's global basis (skeleton space) that runs the knuckles along
## `knuckles`, the fingers along `fingers_to` and the palm along `palm_to`.
func hand_basis(fingers_to: Vector3, knuckles: Vector3, palm_to: Vector3) -> Basis:
	var have := Basis(along, across, palm)
	var want := Basis(fingers_to, knuckles, palm_to)
	return (want * have.inverse()).orthonormalized()
