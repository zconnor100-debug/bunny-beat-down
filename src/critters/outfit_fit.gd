class_name OutfitFit
extends RefCounted
## Where clothes go on a model, measured once per model from its skinned mesh
## in the rest pose (skeleton space, model units, the model facing +Z): the
## skull (its middle, breadth, crown and the front of the face at eye level
## and at the muzzle), the neck, and the chest (breadth, front and back).
## Outfits fit every piece from these, so one hat sits right on a bunny, a
## fox and a hamster alike. Ears that are their own bones (bunnies, foxes,
## raccoons) don't count as skull, and the crown is taken from the middle of
## the head only, so ears that are part of the head mesh don't lift a hat.

static var _cache := {}   # model path -> OutfitFit

var valid := false
var head_c := Vector3.ZERO      ## the skull's middle (x, z; y: halfway up it)
var head_w := 0.2               ## breadth of the skull (x)
var head_d := 0.2               ## depth of the skull (z)
var head_h := 0.2               ## from the neck joint to the crown
var crown_y := 1.0              ## top of the skull, in the middle
var eye_y := 0.85
var face_z := 0.1               ## front of the face at eye level
var face_w := 0.15              ## breadth of the face at eye level
var muzzle_z := 0.12            ## front of the face below the eyes
var neck_y := 0.7
var neck_w := 0.12              ## breadth of the body where the neck meets it
var neck_front := 0.08          ## front of the body just under the neck
var chest_y := 0.6
var chest_w := 0.25
var chest_front := 0.1
var chest_back := -0.1
var shoulder_y := 0.65
var _widths := PackedFloat32Array()   # the skull's breadth at 12 heights, neck to crown


## How broad the skull is at height y (a band goes round it there).
func head_width_at(y: float) -> float:
	if _widths.is_empty():
		return head_w
	var t := clampf((y - neck_y) / maxf(crown_y - neck_y, 0.001), 0.0, 1.0) * (_widths.size() - 1)
	var i := mini(int(t), _widths.size() - 2)
	return lerpf(_widths[i], _widths[i + 1], t - i)


static func of(visual: CritterVisual) -> OutfitFit:
	var key := visual.def.resolved_model()
	if not _cache.has(key):
		var f := OutfitFit.new()
		f._measure(visual)
		_cache[key] = f
	return _cache[key]


func _measure(v: CritterVisual) -> void:
	var rig := v.rig
	var skel := v.skeleton
	# the skull: the head bone and everything under it (eyes, jaw, tongue),
	# except the ears that swing on their own (rig chains "ear_*")
	var head_bones := {}
	for b in rig.subtree(rig.bone[&"head"]):
		head_bones[b] = true
	for chain_name in rig.chains:
		if String(chain_name).begins_with("ear"):
			for b in rig.chains[chain_name]:
				for e in rig.subtree(b):
					head_bones.erase(e)
	var body_bones := {}
	for role in [&"chest", &"spine", &"neck"]:
		if rig.bone.get(role, -1) >= 0:
			body_bones[rig.bone[role]] = true
	# everything but the limbs and the swinging bits: the critter's outline
	var limbs := {}
	for role in [&"l_upper_arm", &"r_upper_arm", &"l_upper_leg", &"r_upper_leg"]:
		for b in rig.subtree(rig.bone[role]):
			limbs[b] = true
	for chain_name in rig.chains:
		for b in rig.chains[chain_name]:
			for e in rig.subtree(b):
				limbs[e] = true
	# eyeballs that are bones of their own (the fox's) say exactly where the eyes are
	var eye_bones := {}
	for b in head_bones:
		var bn := skel.get_bone_name(b).to_lower()
		if bn.contains("eye") and not (bn.contains("lid") or bn.contains("brow") or bn.contains("lash")):
			eye_bones[b] = true
	var head: Array = []
	var body: Array = []
	var trunk: Array = []
	var eyes: Array = []
	for m in v.meshes:
		if m.mesh == null or m.skin == null:
			continue
		var bind_bone := PackedInt32Array()
		for k in m.skin.get_bind_count():
			var b := m.skin.get_bind_bone(k)
			bind_bone.append(b if b >= 0 else skel.find_bone(m.skin.get_bind_name(k)))
		var to_skel := skel.global_transform.affine_inverse() * m.global_transform
		for si in m.mesh.get_surface_count():
			var arr := m.mesh.surface_get_arrays(si)
			if arr[Mesh.ARRAY_WEIGHTS] == null:
				continue
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
			var per := weights.size() / maxi(verts.size(), 1)
			for vi in verts.size():
				# the bone with the most say over this vertex
				var best := -1
				var best_w := 0.0
				for j in per:
					var w := weights[vi * per + j]
					if w > best_w:
						best_w = w
						var bi := bones[vi * per + j]
						best = bind_bone[bi] if bi < bind_bone.size() else -1
				var p := to_skel * verts[vi]
				if eye_bones.has(best):
					eyes.append(p)
				if head_bones.has(best):
					head.append(p)
				elif body_bones.has(best):
					body.append(p)
				if not limbs.has(best):
					trunk.append(p)
	if head.size() < 20:
		return
	var lo := Vector3.INF
	var hi := -Vector3.INF
	var mid := Vector3.ZERO
	for p: Vector3 in head:
		lo = lo.min(p)
		hi = hi.max(p)
		mid += p
	mid /= head.size()
	head_w = _spread(head, 0, 0.04, 0.96)
	head_d = _spread(head, 2, 0.04, 0.96)
	var neck_at: float = (rig.rest[&"neck"] as Transform3D).origin.y if rig.rest.has(&"neck") else lo.y
	# the crown: the top of the head's middle third (not the ear tips)
	var top := -INF
	for p: Vector3 in head:
		if absf(p.x - mid.x) < head_w * 0.17:
			top = maxf(top, p.y)
	crown_y = top if top > -INF else hi.y
	head_h = maxf(crown_y - neck_at, 0.05)
	head_c = Vector3(mid.x, (crown_y + neck_at) * 0.5, _middle(head, 2))
	eye_y = rig.eye_height
	# a skull weighted thinly to the head bone (the frog's) reads narrow: the
	# outline at eye level says how broad the head really is
	head_w = maxf(head_w, maxf(_width_at(trunk, eye_y, head_h * 0.12, head_w),
		_width_at(trunk, lerpf(neck_at, crown_y, 0.45), head_h * 0.12, head_w)) * 0.92)
	# the front of the face at the eyes (either side of the middle: a long
	# snout sticks out further, and glasses don't sit on the nose tip)
	face_w = maxf(_width_at(head, eye_y, head_h * 0.1, head_w), head_w * 0.8)
	var eye_cols := head.filter(func(p): return absf(p.x - mid.x) > face_w * 0.12 and absf(p.x - mid.x) < face_w * 0.4)
	face_z = _front(eye_cols, eye_y, head_h * 0.1, mid.x, face_w, head_c.z + head_d * 0.3)
	if eyes.size() >= 8:
		var ey := 0.0
		var front := -INF
		var lo_x := INF
		var hi_x := -INF
		for p: Vector3 in eyes:
			ey += p.y
			front = maxf(front, p.z)
			lo_x = minf(lo_x, p.x)
			hi_x = maxf(hi_x, p.x)
		eye_y = ey / eyes.size()
		face_z = front
		face_w = maxf(hi_x - lo_x, face_w * 0.5) * 1.15
	muzzle_z = _front(head, eye_y - head_h * 0.22, head_h * 0.1, mid.x, head_w * 0.25, face_z)
	neck_y = neck_at
	for i in 12:
		var y := lerpf(neck_at, crown_y, i / 11.0)
		_widths.append(_width_at(head, y, head_h * 0.05, head_w))
	shoulder_y = (rig.rest[&"r_upper_arm"] as Transform3D).origin.y
	if body.size() >= 20:
		var by := []
		for p: Vector3 in body:
			by.append(p.y)
		by.sort()
		chest_y = (rig.rest[&"chest"] as Transform3D).origin.y if rig.rest.has(&"chest") else by[by.size() / 2]
		chest_w = maxf(_width_at(body, chest_y, head_h * 0.35, head_w), _width_at(trunk, chest_y, head_h * 0.2, head_w) * 0.9)
		neck_w = maxf(_width_at(body, neck_y - head_h * 0.15, head_h * 0.15, chest_w), _width_at(trunk, neck_y - head_h * 0.15, head_h * 0.1, chest_w) * 0.85)
		neck_front = _front(body, neck_y - head_h * 0.2, head_h * 0.15, mid.x, chest_w * 0.3, head_c.z)
		chest_front = _front(body, chest_y, head_h * 0.25, mid.x, chest_w * 0.3, head_c.z)
		chest_back = -_front(body.map(func(p): return p * Vector3(1, 1, -1)), chest_y, head_h * 0.3, mid.x, chest_w * 0.3, -head_c.z)
	else:
		chest_w = head_w * 1.1
		neck_w = head_w * 0.7
		chest_y = neck_y - head_h * 0.6
		neck_front = head_c.z + head_d * 0.35
		chest_front = neck_front
		chest_back = head_c.z - head_d * 0.5
	valid = true


## The spread of the points along an axis between two percentiles.
static func _spread(pts: Array, axis: int, a: float, b: float) -> float:
	var vals := []
	for p: Vector3 in pts:
		vals.append(p[axis])
	vals.sort()
	return maxf(vals[int((vals.size() - 1) * b)] - vals[int((vals.size() - 1) * a)], 0.01)


static func _middle(pts: Array, axis: int) -> float:
	var vals := []
	for p: Vector3 in pts:
		vals.append(p[axis])
	vals.sort()
	return (vals[int((vals.size() - 1) * 0.04)] + vals[int((vals.size() - 1) * 0.96)]) * 0.5


## The front (largest z) of the points in a band around height y and near
## the middle x; `fallback` if there are none.
static func _front(pts: Array, y: float, band: float, x: float, half: float, fallback: float) -> float:
	var z := -INF
	for p: Vector3 in pts:
		if absf(p.y - y) < band and absf(p.x - x) < half:
			z = maxf(z, p.z)
	return z if z > -INF else fallback


static func _width_at(pts: Array, y: float, band: float, fallback: float) -> float:
	var lo := INF
	var hi := -INF
	for p: Vector3 in pts:
		if absf(p.y - y) < band:
			lo = minf(lo, p.x)
			hi = maxf(hi, p.x)
	return hi - lo if hi > lo else fallback
