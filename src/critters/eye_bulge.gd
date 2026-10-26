class_name EyeBulge
extends RefCounted
## Eyeballs put where they can be seen: the squirrel model's sit inside the
## head, above its eye sockets, so the sockets read as dark holes. rig.json
## "eye_bulge": {"material": the eyeballs' material, "to": [x, y, z] where the
## right eyeball's middle goes (the left one mirrored), or "out": how far to
## move each one out from between the eyes and forward; "scale": how much
## bigger}. Each eyeball (one per side) moves and grows about its own middle;
## the meshes are built once per model and shared.

static var _cache := {}   # model path -> {mesh index: ArrayMesh}


static func apply(visual: CritterVisual) -> void:
	var spec: Variant = visual.rig.data.get("eye_bulge")
	if not spec is Dictionary:
		return
	var key := visual.def.resolved_model()
	if not _cache.has(key):
		_cache[key] = _build(visual, spec)
	var meshes: Dictionary = _cache[key]
	for k in meshes:
		visual.meshes[k].mesh = meshes[k]


static func _build(visual: CritterVisual, spec: Dictionary) -> Dictionary:
	var out := {}
	var mat_name := String(spec.get("material", ""))
	var push := float(spec.get("out", 0.0))
	var grow := float(spec.get("scale", 1.0))
	for k in visual.meshes.size():
		var src := visual.meshes[k].mesh as ArrayMesh
		if src == null:
			continue
		var surfaces := []
		var touched := false
		for si in src.get_surface_count():
			var arr := src.surface_get_arrays(si)
			var mat := src.surface_get_material(si)
			if mat and mat.resource_name == mat_name:
				_bulge(arr, push, grow, _to_skeleton(visual.meshes[k], visual), spec.get("to"))
				touched = true
			surfaces.append([src.surface_get_primitive_type(si), arr, mat, src.surface_get_name(si)])
		if not touched:
			continue
		var mesh := ArrayMesh.new()
		for s in surfaces:
			mesh.add_surface_from_arrays(s[0], s[1])
			mesh.surface_set_material(mesh.get_surface_count() - 1, s[2])
			mesh.surface_set_name(mesh.get_surface_count() - 1, s[3])
		out[k] = mesh
	return out


## Where the eyeballs' vertices land in the skeleton's frame at rest: through
## the head bone's bind pose (it may turn the mesh's own axes: a Z-up mesh).
static func _to_skeleton(m: MeshInstance3D, visual: CritterVisual) -> Transform3D:
	var skel := visual.skeleton
	var head: int = visual.rig.bone[&"head"]
	if m.skin:
		for i in m.skin.get_bind_count():
			var b := m.skin.get_bind_bone(i)
			if (b if b >= 0 else skel.find_bone(m.skin.get_bind_name(i))) == head:
				return skel.get_bone_global_rest(head) * m.skin.get_bind_pose(i)
	return Transform3D.IDENTITY


## Move and grow the eyeballs in a surface's arrays (one each side of the
## middle), in the skeleton's frame (+Z the model's front).
static func _bulge(arr: Array, push: float, grow: float, to_skel: Transform3D, to: Variant) -> void:
	var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var back := to_skel.affine_inverse()
	for i in vs.size():
		vs[i] = to_skel * vs[i]
	var sums := {1: Vector3.ZERO, -1: Vector3.ZERO}
	var counts := {1: 0, -1: 0}
	for v in vs:
		var side := 1 if v.x >= 0.0 else -1
		sums[side] += v
		counts[side] += 1
	if counts[1] == 0 or counts[-1] == 0:
		return
	var c := {1: sums[1] / counts[1], -1: sums[-1] / counts[-1]}
	var between: Vector3 = (c[1] + c[-1]) * 0.5
	for i in vs.size():
		var side := 1 if vs[i].x >= 0.0 else -1
		var mid: Vector3 = c[side]
		# out from between the eyes, and forward
		var dir := ((mid - between).normalized() + Vector3(0, 0, 0.8)).normalized()
		var goal := mid + dir * push
		if to is Array:
			goal = Vector3(absf(float(to[0])) * signf(mid.x - between.x), float(to[1]), float(to[2]))
		vs[i] = back * (goal + (vs[i] - mid) * grow)
	arr[Mesh.ARRAY_VERTEX] = vs
