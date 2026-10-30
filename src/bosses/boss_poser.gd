class_name BossPoser
extends RefCounted
## A boss's procedural animation (Boss): its skeleton posed bone by bone from a
## few rotations per role, given in the boss's own space (x its left, y up,
## z its front), so one pose works on any rig (the <id>.boss.json names each
## role's bone). Each frame the boss clears it, adds its walk, its breathing,
## where it's looking and what it's doing (BossAction), and applies it.
##
## Rotations follow the right hand: about x, up tips toward the front (a
## bone hanging down swings back); about y, the front turns toward its left;
## about z, up leans toward its right (an arm hanging down swings out to its
## left).

var skeleton: Skeleton3D
var bones: Dictionary = {}          ## role -> bone index
var rot: Dictionary = {}            ## role -> Basis: this frame's turn, in the boss's space
var root_offset := Vector3.ZERO     ## the root bone moved (model units, the boss's space)
var _role_of: Dictionary = {}       # bone index -> role
var _order := PackedInt32Array()    # parents before children
var _rest_global: Array[Transform3D] = []
var _rest_local: Array[Transform3D] = []
var _glob: Array[Transform3D] = []  # this frame's pose, skeleton space
var _acc: Array[Basis] = []
var _tip: Dictionary = {}           # bone index -> its tip in its own rest space


## `tails`: each role's bone tip in the model (the boss.json's "tails").
func bind(skel: Skeleton3D, role_bones: Dictionary, tails := {}) -> void:
	skeleton = skel
	var n := skel.get_bone_count()
	_rest_global.resize(n)
	_rest_local.resize(n)
	_glob.resize(n)
	_acc.resize(n)
	for i in n:
		_rest_global[i] = skel.get_bone_global_rest(i)
		_rest_local[i] = skel.get_bone_rest(i)
		_glob[i] = _rest_global[i]
	for role in role_bones:
		var idx := skel.find_bone(String(role_bones[role]))
		if idx >= 0:
			bones[StringName(role)] = idx
			_role_of[idx] = StringName(role)
			if tails.has(role):
				var t: Array = tails[role]
				_tip[idx] = _rest_global[idx].affine_inverse() * Vector3(t[0], t[1], t[2])
	# (parents first: a bone's pose is built on its parent's)
	var depth := {}
	for i in n:
		var d := 0
		var p := skel.get_bone_parent(i)
		while p >= 0:
			d += 1
			p = skel.get_bone_parent(p)
		depth[i] = d
	var idxs := range(n)
	idxs.sort_custom(func(a, b): return depth[a] < depth[b])
	_order = PackedInt32Array(idxs)


func has(role: StringName) -> bool:
	return bones.has(role)


func clear() -> void:
	rot.clear()
	root_offset = Vector3.ZERO


## Turn `role` by `deg` (degrees about x, y, z of the boss's space), on top of
## what it already has this frame.
func add(role: StringName, deg: Vector3, weight := 1.0) -> void:
	if not bones.has(role) or weight == 0.0:
		return
	var b := Basis.from_euler(deg * (PI / 180.0) * weight)
	rot[role] = b * (rot.get(role, Basis.IDENTITY) as Basis)


## Every role of a pose ({role: Vector3 degrees}), times `weight`.
func add_pose(pose: Dictionary, weight := 1.0) -> void:
	if weight <= 0.0:
		return
	for role in pose:
		if role == &"root":
			root_offset += (pose[role] as Vector3) * weight
		else:
			add(role, pose[role], weight)


func apply() -> void:
	if skeleton == null:
		return
	for i in _order:
		var p := skeleton.get_bone_parent(i)
		var own: Basis = rot.get(_role_of[i], Basis.IDENTITY) if _role_of.has(i) else Basis.IDENTITY
		var a := own * (_acc[p] if p >= 0 else Basis.IDENTITY)
		_acc[i] = a
		var origin: Vector3 = _glob[p] * _rest_local[i].origin if p >= 0 else _rest_global[i].origin + root_offset
		_glob[i] = Transform3D(a * _rest_global[i].basis, origin)
		var local := _glob[p].affine_inverse() * _glob[i] if p >= 0 else _glob[i]
		skeleton.set_bone_pose_position(i, local.origin)
		skeleton.set_bone_pose_rotation(i, local.basis.get_rotation_quaternion())


## Where `role`'s bone is this frame (skeleton space).
func bone_pose(role: StringName) -> Transform3D:
	return _glob[bones[role]] if bones.has(role) else Transform3D.IDENTITY


## Where `role`'s bone ends this frame (skeleton space).
func bone_tip(role: StringName) -> Vector3:
	if not bones.has(role):
		return Vector3.ZERO
	var i: int = bones[role]
	if _tip.has(i):
		return _glob[i] * (_tip[i] as Vector3)
	for c in skeleton.get_bone_children(i):
		return _glob[c].origin
	return _glob[i].origin + _glob[i].basis.y * 0.05
