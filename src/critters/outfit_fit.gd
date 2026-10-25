class_name OutfitFit
extends RefCounted
## Where clothes go on a model, measured once per model from its skinned mesh
## in the rest pose (skeleton space, model units, the model facing +Z): the
## skull (its middle, breadth at every height, the top of it), the eyes (from
## rig.json "eyes": [x, y] of one eye, read off a straight-on render by
## tests/capture_eyes.gd, and how far forward the face is there), the neck, and
## the body's outline at every height (how broad, how far forward the chest
## and how far back the back). Outfits fits every piece from these, so one hat
## sits right on a bunny, a fox and a hamster alike, glasses sit over the
## eyes, and capes and packs lie on the back instead of floating behind it.
## Ears that are bones of their own (bunnies, foxes, raccoons) don't count as
## skull, and the top of the skull is taken from the middle of the head only,
## so ears that are part of the head mesh don't lift a hat.

static var _cache := {}   # model path -> OutfitFit

const ROWS := 24          ## heights the outlines are kept at

var valid := false
var head_c := Vector3.ZERO      ## the skull's middle (x, z; y: halfway up it)
var head_w := 0.2               ## breadth of the skull (x)
var head_d := 0.2               ## depth of the skull (z)
var head_h := 0.2               ## from the neck joint to the crown
var crown_y := 1.0              ## top of the skull, in the middle
var crown_z := 0.0              ## where the top of the skull is, front to back
var eye_x := 0.05               ## how far each eye is from the middle
var eye_y := 0.85
var eye_z := 0.1                ## the front of the face at the eyes
var brow_y := 0.9               ## just over the eyes (as far down as a hat comes)
var bridge_z := 0.1             ## the front of the face between the eyes
var face_z := 0.1               ## the front of whatever glasses have to clear
var face_w := 0.15              ## breadth of the face at eye level
var muzzle_y := 0.75            ## where a mask's top edge goes (under the eyes)
var muzzle_z := 0.12            ## front of the face there
var chin_y := 0.7               ## bottom of the face (a scarf or a bow tie goes under it)
var muzzle_w := 0.12            ## breadth of the front of the face under the eyes (a bandana covers it)
var neck_y := 0.7
var neck_w := 0.12              ## breadth of the body where the neck meets it
var neck_front := 0.08          ## front of the body just under the neck
var chest_y := 0.6
var chest_w := 0.25
var chest_front := 0.1
var chest_back := -0.1
var shoulder_y := 0.65
var shoulder_w := 0.3           ## from shoulder joint to shoulder joint, plus the arms' thickness
var hip_y := 0.4
var hat_stretch := 1.0          ## hats this much taller (rig.json "hat_stretch": a beaver's head is a tall egg)
var tail_y := -1.0              ## where a big tail (a fox's, a squirrel's) leaves the body; -1: none
var _head_rows := PackedFloat32Array()   # skull breadth at ROWS heights, neck to crown
var _lo := 0.0                            # the body outline's heights: hips to crown
var _hi := 1.0
var _wide := PackedFloat32Array()        # body breadth at each row
var _front := PackedFloat32Array()       # how far forward the body is at each row
var _back := PackedFloat32Array()        # how far back


static func of(visual: CritterVisual) -> OutfitFit:
	var key := visual.def.resolved_model()
	if not _cache.has(key):
		var f := OutfitFit.new()
		f._measure(visual)
		_cache[key] = f
	return _cache[key]


## How broad the skull is at height y (a hat or a band goes round it there).
func head_width_at(y: float) -> float:
	return _row(_head_rows, neck_y, crown_y, y, head_w)


## How broad, how far forward and how far back the body (not its arms) is at y.
func body_width_at(y: float) -> float:
	return _row(_wide, _lo, _hi, y, chest_w)


func front_at(y: float) -> float:
	return _row(_front, _lo, _hi, y, chest_front)


func back_at(y: float) -> float:
	return _row(_back, _lo, _hi, y, chest_back)


static func _row(rows: PackedFloat32Array, lo: float, hi: float, y: float, fallback: float) -> float:
	if rows.size() < 2:
		return fallback
	var t := clampf((y - lo) / maxf(hi - lo, 0.001), 0.0, 1.0) * (rows.size() - 1)
	var i := mini(int(t), rows.size() - 2)
	return lerpf(rows[i], rows[i + 1], t - i)


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
	# the body: everything but the arms, legs, tail and ears
	var limbs := {}
	for role in [&"l_upper_arm", &"r_upper_arm", &"l_upper_leg", &"r_upper_leg"]:
		for b in rig.subtree(rig.bone[role]):
			limbs[b] = true
	for chain_name in rig.chains:
		if chain_name == &"tail" and (rig.chains[chain_name] as PackedInt32Array).size() < 3:
			continue   # (a bunny's puff is part of its back: a cape hangs over it)
		for b in rig.chains[chain_name]:
			for e in rig.subtree(b):
				limbs[e] = true
	var head: Array = []
	var trunk: Array = []
	var head_tris := PackedVector3Array()    # (triangles, three points each: the outlines are
	var trunk_tris := PackedVector3Array()   # cut through them, however sparse the vertices)
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
			var kind := PackedByteArray()   # per vertex: 1 skull, 2 body, 3 both
			kind.resize(verts.size())
			var at := PackedVector3Array()
			at.resize(verts.size())
			for vi in verts.size():
				var best := -1
				var best_w := 0.0
				for j in per:
					var w := weights[vi * per + j]
					if w > best_w:
						best_w = w
						var bi := bones[vi * per + j]
						best = bind_bone[bi] if bi < bind_bone.size() else -1
				var p := to_skel * verts[vi]
				at[vi] = p
				if head_bones.has(best):
					head.append(p)
					kind[vi] |= 1
				if not limbs.has(best):
					trunk.append(p)
					kind[vi] |= 2
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array(range(verts.size()))
			for t in idx.size() / 3:
				var a := idx[t * 3]
				var b := idx[t * 3 + 1]
				var c := idx[t * 3 + 2]
				var k := kind[a] & kind[b] & kind[c]
				if k & 1:
					head_tris.append_array([at[a], at[b], at[c]])
				if k & 2:
					trunk_tris.append_array([at[a], at[b], at[c]])
	if head.size() < 20 or trunk.size() < 20:
		return
	var mid := Vector3.ZERO
	for p: Vector3 in head:
		mid += p
	mid /= head.size()
	head_w = _spread(head, 0, 0.04, 0.96)
	head_d = _spread(head, 2, 0.04, 0.96)
	var neck_at: float = (rig.rest[&"neck"] as Transform3D).origin.y if rig.rest.has(&"neck") else _pct(head, 1, 0.02)
	# the top of the skull: the highest of the head's middle third (not the ears)
	var top := -INF
	var tops := []
	for p: Vector3 in head:
		if absf(p.x - mid.x) < head_w * 0.17:
			top = maxf(top, p.y)
	crown_y = top if top > -INF else _pct(head, 1, 0.99)
	for p: Vector3 in head:
		if absf(p.x - mid.x) < head_w * 0.17 and p.y > crown_y - (crown_y - neck_at) * 0.08:
			tops.append(p.z)
	tops.sort()
	crown_z = tops[tops.size() / 2] if not tops.is_empty() else mid.z
	head_h = maxf(crown_y - neck_at, 0.05)
	head_c = Vector3(mid.x, (crown_y + neck_at) * 0.5, _middle(head, 2))
	neck_y = neck_at
	# the skull's breadth at every height (and the body's outline where the
	# skull is thinly weighted: a frog's head is mostly mouth)
	var skull_cut := _sections(head_tris, neck_at, crown_y, mid.x, 0.0)
	var body_cut := _sections(trunk_tris, neck_at, crown_y, mid.x, 0.0)
	for i in ROWS:
		_head_rows.append(maxf(skull_cut[i][1] - skull_cut[i][0], (body_cut[i][1] - body_cut[i][0]) * 0.92))
	# the eyes, as measured (rig.json), and the face in front of them
	var eyes: Variant = rig.data.get("eyes")
	eye_x = float(eyes[0]) if eyes is Array else head_w * 0.22
	eye_y = float(eyes[1]) if eyes is Array else rig.eye_height
	var r := head_h * 0.1
	brow_y = minf(eye_y + r, crown_y)
	eye_z = maxf(_front_near(head, mid.x + eye_x, eye_y, r), _front_near(head, mid.x - eye_x, eye_y, r))
	bridge_z = _front_near(head, mid.x, eye_y + r * 0.5, r)
	face_z = maxf(eye_z, bridge_z)
	face_w = maxf(_width_at(trunk, eye_y, head_h * 0.05), eye_x * 2.6)
	muzzle_y = eye_y - head_h * 0.12
	muzzle_z = _front_near(head, mid.x, muzzle_y - head_h * 0.1, r * 1.5)
	var snout: Array = head.filter(func(p): return absf(p.y - muzzle_y) < head_h * 0.1 and p.z > muzzle_z - head_d * 0.15)
	muzzle_w = clampf(_width_at(snout, muzzle_y, head_h * 0.1), eye_x * 1.6, head_w)
	# the chin: the bottom of the front half of the head, down the middle
	var chin: Array = head.filter(func(p): return p.z > mid.z and absf(p.x - mid.x) < head_w * 0.25)
	chin_y = _pct(chin, 1, 0.03) if chin.size() > 10 else neck_at
	# the body's outline, hips to crown
	hip_y = (rig.rest[&"hips"] as Transform3D).origin.y
	_lo = hip_y
	_hi = crown_y
	# (front and back down the middle: a shoulder blade or a cheek off to the side
	# doesn't count)
	var cut := _sections(trunk_tris, _lo, _hi, mid.x, head_w * 0.3)
	for i in ROWS:
		var row: Array = cut[i]
		_wide.append(row[1] - row[0])
		_front.append(row[3] if row[3] > -INF else mid.z + head_d * 0.5)
		_back.append(row[2] if row[2] < INF else mid.z - head_d * 0.5)
	shoulder_y = (rig.rest[&"r_upper_arm"] as Transform3D).origin.y
	shoulder_w = (rig.rest[&"r_upper_arm"] as Transform3D).origin.distance_to((rig.rest[&"l_upper_arm"] as Transform3D).origin) \
		+ float(rig.radii.get(&"r_upper_arm", 0.03)) * 2.0
	chest_y = (rig.rest[&"chest"] as Transform3D).origin.y if rig.rest.has(&"chest") else lerpf(hip_y, neck_y, 0.6)
	chest_w = body_width_at(chest_y)
	chest_front = front_at(chest_y)
	chest_back = back_at(chest_y)
	hat_stretch = float(rig.data.get("hat_stretch", 1.0))
	var tail: PackedInt32Array = rig.chains.get(&"tail", PackedInt32Array())
	if tail.size() >= 3:   # (a bunny's puff doesn't count)
		tail_y = skel.get_bone_global_rest(tail[0]).origin.y
	neck_w = maxf(body_width_at(neck_y - head_h * 0.12), head_w * 0.3)
	neck_front = front_at(neck_y - head_h * 0.12)
	valid = true


## The mesh cut across at ROWS heights from lo to hi: at each, [left, right,
## back, front] of the cut (back and front only within `strip` of mid_x down
## the middle, when strip > 0). Triangles are cut, not just vertices counted,
## so a big low-poly skull reads as round as it looks.
static func _sections(tris: PackedVector3Array, lo: float, hi: float, mid_x: float, strip: float) -> Array:
	var out := []
	for i in ROWS:
		out.append([INF, -INF, INF, -INF])
	var step := maxf(hi - lo, 0.001) / (ROWS - 1)
	for t in tris.size() / 3:
		var a := tris[t * 3]
		var b := tris[t * 3 + 1]
		var c := tris[t * 3 + 2]
		var y0 := minf(a.y, minf(b.y, c.y))
		var y1 := maxf(a.y, maxf(b.y, c.y))
		var i0 := maxi(ceili((y0 - lo) / step), 0)
		var i1 := mini(floori((y1 - lo) / step), ROWS - 1)
		for i in range(i0, i1 + 1):
			var y := lo + step * i
			var row: Array = out[i]
			for e in [[a, b], [b, c], [c, a]]:
				var p: Vector3 = e[0]
				var q: Vector3 = e[1]
				if (p.y - y) * (q.y - y) > 0.0 or p.y == q.y:
					continue
				var x := p.lerp(q, (y - p.y) / (q.y - p.y))
				row[0] = minf(row[0], x.x)
				row[1] = maxf(row[1], x.x)
				if strip <= 0.0 or absf(x.x - mid_x) < strip:
					row[2] = minf(row[2], x.z)
					row[3] = maxf(row[3], x.z)
	for row: Array in out:
		if row[0] == INF:
			row[0] = 0.0
			row[1] = 0.0
	return out


## The spread of the points along an axis between two percentiles.
static func _spread(pts: Array, axis: int, a: float, b: float) -> float:
	var vals := []
	for p: Vector3 in pts:
		vals.append(p[axis])
	vals.sort()
	return maxf(vals[int((vals.size() - 1) * b)] - vals[int((vals.size() - 1) * a)], 0.01)


static func _pct(pts: Array, axis: int, q: float) -> float:
	var vals := []
	for p: Vector3 in pts:
		vals.append(p[axis])
	vals.sort()
	return vals[int((vals.size() - 1) * q)]


static func _middle(pts: Array, axis: int) -> float:
	return (_pct(pts, axis, 0.04) + _pct(pts, axis, 0.96)) * 0.5


## The front (largest z) of the points within r of (x, y) seen from the front.
static func _front_near(pts: Array, x: float, y: float, r: float) -> float:
	var z := -INF
	for p: Vector3 in pts:
		if absf(p.y - y) < r and absf(p.x - x) < r:
			z = maxf(z, p.z)
	return z if z > -INF else 0.0


static func _width_at(pts: Array, y: float, band: float) -> float:
	var lo := INF
	var hi := -INF
	for p: Vector3 in pts:
		if absf(p.y - y) < band:
			lo = minf(lo, p.x)
			hi = maxf(hi, p.x)
	return hi - lo if hi > lo else 0.0
