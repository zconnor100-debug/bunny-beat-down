class_name PawKnuckles
extends RefCounted
## Mitten paws (rigs whose hands have no finger bones: the frog, the raccoon,
## the beaver) can't close on a handle. This gives them knuckles at load time:
## two bones added under each hand, one across the paw where the fingers start
## and one halfway down them, with the fingers' skin reweighted onto them on a
## smooth ramp so the paw bends round instead of creasing. CritterPoser then
## curls them like any other fingers (PawGrip finds them as a finger chain).
##
## The reworked meshes and skins are built once per model and shared; every
## critter of that model gets the same bones, in the same order, so the bone
## indices match. Nothing is written to the model files.

const NAMES := {&"l": ["bbd_knuckle_l", "bbd_finger_l"], &"r": ["bbd_knuckle_r", "bbd_finger_r"]}
const KNUCKLE := 0.5     ## share of the paw's length (wrist → fingertip) where the fingers start
const FINGER := 0.76     ## where the fingers' second joint is
const BLEND := 0.08      ## share of the paw's length each joint's skin bends over

## model path -> {"bones": [[name, parent name, rest]], "meshes": {index in CritterVisual.meshes: [mesh, skin]}}
## ({} when the model's paws already have fingers)
static var _cache := {}


## Give this critter's skeleton knuckles (if its paws have none) and its
## meshes the skin that bends with them.
static func apply(visual: CritterVisual) -> void:
	var key := visual.def.resolved_model()
	if not _cache.has(key):
		_cache[key] = _plan(visual)
	var plan: Dictionary = _cache[key]
	if plan.is_empty():
		return
	var skel := visual.skeleton
	for b in plan.bones:
		var i := skel.get_bone_count()
		skel.add_bone(b[0])
		skel.set_bone_parent(i, skel.find_bone(b[1]))
		skel.set_bone_rest(i, b[2])
		skel.reset_bone_pose(i)
	for k in plan.meshes:
		var m: MeshInstance3D = visual.meshes[k]
		m.mesh = plan.meshes[k][0]
		m.skin = plan.meshes[k][1]


static func _plan(visual: CritterVisual) -> Dictionary:
	var skel := visual.skeleton
	var sides := {}   # side -> {"hand": name, "along", "mid", "len"}
	for side in [&"l", &"r"]:
		var hand: int = visual.rig.bone.get(StringName(side + "_hand"), -1)
		if hand >= 0 and skel.get_bone_children(hand).is_empty():
			sides[side] = {"hand": skel.get_bone_name(hand), "pts": []}
	if sides.is_empty():
		return {}
	# the paws' shape, in each hand bone's own frame (bind pose * vertex)
	var skinned := []
	for k in visual.meshes.size():
		var m: MeshInstance3D = visual.meshes[k]
		if m.mesh == null or m.skin == null:
			continue
		skinned.append(k)
		var binds := _hand_binds(m.skin, sides)
		for si in m.mesh.get_surface_count():
			var arr := m.mesh.surface_get_arrays(si)
			if arr[Mesh.ARRAY_WEIGHTS] == null:
				continue
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
			var per := weights.size() / maxi(verts.size(), 1)
			for vi in verts.size():
				for side in binds:
					if _weight(bones, weights, vi, per, binds[side][0]) >= 0.5:
						(sides[side].pts as Array).append((binds[side][1] as Transform3D) * verts[vi])
	var plan := {"bones": [], "meshes": {}}
	for side in sides.keys():
		var pts: Array = sides[side].pts
		if pts.size() < 8:
			sides.erase(side)
			continue
		var c := Vector3.ZERO
		for p: Vector3 in pts:
			c += p
		c /= pts.size()
		var along := c.normalized()
		var length := 0.0
		for p: Vector3 in pts:
			length = maxf(length, p.dot(along))
		var mid := c - along * c.dot(along)   # the paw's middle, square to its length
		sides[side].along = along
		sides[side].len = length
		var knuckle := Transform3D(Basis(), mid + along * KNUCKLE * length)
		var finger := Transform3D(Basis(), along * (FINGER - KNUCKLE) * length)
		sides[side].rests = [knuckle, knuckle * finger]
		plan.bones.append([NAMES[side][0], sides[side].hand, knuckle])
		plan.bones.append([NAMES[side][1], NAMES[side][0], finger])
	if sides.is_empty():
		return {}
	for k in skinned:
		var m: MeshInstance3D = visual.meshes[k]
		var made := _reskin(m.mesh, m.skin, sides)
		if not made.is_empty():
			plan.meshes[k] = made
	return plan


## {side: [bind index of the hand, its bind pose]} for the sides this skin binds.
static func _hand_binds(skin: Skin, sides: Dictionary) -> Dictionary:
	var out := {}
	for b in skin.get_bind_count():
		for side in sides:
			if skin.get_bind_name(b) == sides[side].hand:
				out[side] = [b, skin.get_bind_pose(b)]
	return out


static func _weight(bones: PackedInt32Array, weights: PackedFloat32Array, vi: int, per: int, bind: int) -> float:
	var w := 0.0
	for j in per:
		if bones[vi * per + j] == bind:
			w += weights[vi * per + j]
	return w


## A copy of `mesh` whose fingers are weighted onto the knuckle bones, and a
## copy of `skin` that binds them. [] if nothing in this mesh is on a paw.
static func _reskin(mesh: Mesh, skin: Skin, sides: Dictionary) -> Array:
	var binds := _hand_binds(skin, sides)
	if binds.is_empty():
		return []
	var new_skin: Skin = skin.duplicate()
	var new_bind := {}   # side -> [knuckle bind, finger bind]
	for side in binds:
		var hand_bind: Transform3D = binds[side][1]
		var r: Array = sides[side].rests
		new_bind[side] = [new_skin.get_bind_count(), new_skin.get_bind_count() + 1]
		new_skin.add_named_bind(NAMES[side][0], (r[0] as Transform3D).affine_inverse() * hand_bind)
		new_skin.add_named_bind(NAMES[side][1], (r[1] as Transform3D).affine_inverse() * hand_bind)
	var out := ArrayMesh.new()
	var am := mesh as ArrayMesh
	if am:
		out.blend_shape_mode = am.blend_shape_mode
		for i in am.get_blend_shape_count():
			out.add_blend_shape(am.get_blend_shape_name(i))
	for si in mesh.get_surface_count():
		var arr := mesh.surface_get_arrays(si)
		if arr[Mesh.ARRAY_WEIGHTS] != null:
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
			var per := weights.size() / maxi(verts.size(), 1)
			for vi in verts.size():
				for side in binds:
					_ramp(bones, weights, vi, per, binds[side], new_bind[side], sides[side], verts[vi])
			arr[Mesh.ARRAY_BONES] = bones
			arr[Mesh.ARRAY_WEIGHTS] = weights
		var flags := Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS if mesh.surface_get_format(si) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS else 0
		out.add_surface_from_arrays(mesh.surface_get_primitive_type(si), arr, mesh.surface_get_blend_shape_arrays(si), {}, flags)
		out.surface_set_material(si, mesh.surface_get_material(si))
		if am:
			out.surface_set_name(si, am.surface_get_name(si))
	return [out, new_skin]


## Move a vertex's share of the hand onto the knuckle and finger bones by how
## far down the paw it lies.
static func _ramp(bones: PackedInt32Array, weights: PackedFloat32Array, vi: int, per: int, hand: Array,
		knuckles: Array, side: Dictionary, v: Vector3) -> void:
	var wh := _weight(bones, weights, vi, per, hand[0])
	if wh <= 0.0:
		return
	var length: float = side.len
	var d := ((hand[1] as Transform3D) * v).dot(side.along)
	var s1 := smoothstep((KNUCKLE - BLEND) * length, (KNUCKLE + BLEND) * length, d)
	if s1 <= 0.0:
		return
	var s2 := smoothstep((FINGER - BLEND) * length, (FINGER + BLEND) * length, d)
	var pairs := []
	for j in per:
		var b := bones[vi * per + j]
		var w := weights[vi * per + j]
		if b != hand[0] and w > 0.0:
			pairs.append([b, w])
	for e in [[hand[0], wh * (1.0 - s1)], [knuckles[0], wh * s1 * (1.0 - s2)], [knuckles[1], wh * s1 * s2]]:
		if e[1] > 1e-4:
			pairs.append(e)
	pairs.sort_custom(func(x, y): return x[1] > y[1])
	var total := 0.0
	for j in mini(per, pairs.size()):
		total += pairs[j][1]
	for j in per:
		var keep := j < pairs.size() and total > 0.0
		bones[vi * per + j] = pairs[j][0] if keep else 0
		weights[vi * per + j] = pairs[j][1] / total if keep else 0.0
