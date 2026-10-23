class_name Gore
## Dismemberment. A limb gib is a second copy of the critter's own model whose
## skeleton is re-rooted at the severed bone: every bone outside that limb is
## collapsed to zero scale, so only the real, skinned limb remains — wearing the
## exact pose it had when it came off. No pre-cut meshes are needed, so any
## model in the roster can lose any limb.

const GIB_LIFETIME := 30.0
const STUMP_BLOOD := Color(0.5, 0.03, 0.04)
const STUMP_BONE := Color(0.95, 0.92, 0.85)


static func spawn_limb_gib(visual: CritterVisual, bone_idx: int, impulse: Vector3) -> RigidBody3D:
	if Settings.gore == Settings.Gore.OFF:
		return null
	var src: Skeleton3D = visual.skeleton
	var copy := ModelUtil.instantiate(visual.def.resolved_model())
	if copy == null:
		return null
	for ap in ModelUtil.find_all(copy, "AnimationPlayer"):
		(ap as Node).queue_free()
	var skel := ModelUtil.find_first(copy, "Skeleton3D") as Skeleton3D
	if skel == null:
		copy.free()
		return null
	var sub := visual.rig.subtree(bone_idx)
	var globals := {}
	for i in sub:
		globals[i] = visual.current_bone_global(i)
	# re-root the limb and collapse everything else — into the cut itself, so
	# skin weighted partly to the body (around the joint) is pinched shut at
	# the stump instead of being dragged off in long spikes toward the hips
	skel.set_bone_parent(bone_idx, -1)
	var cut: Vector3 = (globals[bone_idx] as Transform3D).origin
	for i in skel.get_bone_count():
		if skel.get_bone_parent(i) < 0 and i != bone_idx:
			skel.set_bone_pose_position(i, cut)
			skel.set_bone_pose_scale(i, Vector3(0.0001, 0.0001, 0.0001))
	for i in sub:
		var g: Transform3D = globals[i]
		var local := g if i == bone_idx else (globals[skel.get_bone_parent(i)] as Transform3D).affine_inverse() * g
		skel.set_bone_pose_position(i, local.origin)
		skel.set_bone_pose_rotation(i, local.basis.orthonormalized().get_rotation_quaternion())
	for mi in ModelUtil.find_all(copy, "MeshInstance3D"):
		(mi as MeshInstance3D).layers = CritterVisual.RENDER_LAYER

	# physics body in the limb's bone frame
	var body := RigidBody3D.new()
	body.name = "Gib"
	body.collision_layer = Layers.DEBRIS
	body.collision_mask = Layers.WORLD | Layers.DEBRIS
	body.set_meta(&"gib", true)
	var role := visual.rig.role_of_bone(bone_idx)
	var bone_world: Transform3D = src.global_transform * (globals[bone_idx] as Transform3D)
	var seg_len := 0.0
	var radius := 0.05
	var k := visual.rig.size   # rig data is in model units; the gib body is not scaled
	var cs := CollisionShape3D.new()
	if role == &"head":
		var sph := SphereShape3D.new()
		var seg: Dictionary = visual.rig.segments[&"head"]
		radius = seg["radius"]
		sph.radius = radius * k
		cs.shape = sph
		var mid: Vector3 = ((seg["start"] as Vector3) + (seg["end"] as Vector3)) * 0.5
		cs.position = (visual.rig.rest[&"head"] as Transform3D).affine_inverse() * mid * k
		body.mass = 1.2
	else:
		# capsule spanning the limb (upper + lower segments when the cut is high)
		var a := Vector3.ZERO
		var b := Vector3.ZERO
		for r in [role, StringName(String(role).replace("upper", "lower"))]:
			if visual.rig.segments.has(r) and sub.has(visual.rig.bone.get(r, -1)):
				var seg: Dictionary = visual.rig.segments[r]
				radius = maxf(radius, seg["radius"])
				b = (visual.rig.rest[role] as Transform3D).affine_inverse() * (seg["end"] as Vector3)
		b *= k
		radius *= k
		seg_len = a.distance_to(b)
		var cap := CapsuleShape3D.new()
		cap.radius = radius
		cap.height = maxf(seg_len + radius * 2.0, radius * 2.0 + 0.01)
		cs.shape = cap
		cs.transform = CritterVisual._capsule_xform(a, b)
		body.mass = 0.4 + seg_len * 2.0
	body.add_child(cs)
	body.add_child(copy)
	Despawner.debris_parent(visual).add_child(body)
	body.global_transform = Transform3D(bone_world.basis.orthonormalized(), bone_world.origin)
	skel.global_transform = src.global_transform
	body.apply_central_impulse(impulse * body.mass * 0.8 + Vector3.UP * randf_range(1.0, 2.5) * body.mass)
	body.angular_velocity = Vector3(randf_range(-14, 14), randf_range(-10, 10), randf_range(-14, 14))
	Despawner.schedule(body, GIB_LIFETIME)
	if KillCam.recording and not KillCam.instance.playing:
		KillCam.instance.note_node(body)
	return body


## Meaty cap + a spurting fountain where the limb used to be.
static func make_stump(visual: CritterVisual, bone_idx: int) -> void:
	var src := visual.skeleton
	var parent_idx := src.get_bone_parent(bone_idx)
	var bone_g := visual.current_bone_global(bone_idx)
	var pos_world: Vector3 = src.global_transform * bone_g.origin
	var role := visual.rig.role_of_bone(bone_idx)
	var radius: float = visual.rig.segments.get(role, {}).get("radius", 0.05)
	FX.gore_burst(pos_world, 0.9, visual.def.fur_color)
	Audio.play_at(&"gore_limb_pop", pos_world, 0.0, 0.12)
	if Settings.gore == Settings.Gore.OFF or parent_idx < 0:
		return
	var att := BoneAttachment3D.new()
	att.bone_idx = parent_idx
	src.add_child(att)
	var holder := Node3D.new()
	att.add_child(holder)
	holder.global_position = pos_world
	if KillCam.recording and not KillCam.instance.playing:
		KillCam.instance.note_node(holder, "", false)
	var limb_dir: Vector3 = src.global_basis * bone_g.basis.y
	_add_cap(holder, radius * 0.95, att.global_basis.inverse() * limb_dir)
	FX.stump_fountain(holder, att.global_basis.inverse() * limb_dir)
	FX.splat_decal(pos_world + Vector3.DOWN * 0.2, Vector3.UP, 0.9)


## The severed end of the flying limb gets a cap and a short spurt too.
static func make_gib_stump(gib: RigidBody3D, visual: CritterVisual, bone_idx: int) -> void:
	if Settings.gore == Settings.Gore.OFF:
		return
	var role := visual.rig.role_of_bone(bone_idx)
	var radius: float = visual.rig.segments.get(role, {}).get("radius", 0.05) * visual.rig.size
	var holder := Node3D.new()
	gib.add_child(holder)
	# the gib's origin is the severed joint; the limb runs along local +Y
	_add_cap(holder, radius * 0.95, Vector3.DOWN)
	FX.stump_fountain(holder, Vector3.DOWN)


static func _add_cap(parent: Node3D, radius: float, outward_local: Vector3) -> void:
	var cap := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = radius
	sph.height = radius * 0.9
	sph.radial_segments = 12
	sph.rings = 6
	var mat := StandardMaterial3D.new()
	if Settings.gore == Settings.Gore.BLOOD:
		mat.albedo_color = STUMP_BLOOD
		mat.roughness = 0.25
		mat.clearcoat_enabled = true
		mat.clearcoat = 0.6
	else:
		mat.albedo_color = FX.STUFFING
		mat.roughness = 1.0
	sph.material = mat
	cap.mesh = sph
	cap.layers = CritterVisual.RENDER_LAYER
	parent.add_child(cap)
	if outward_local.length_squared() > 1e-6:
		cap.basis = Basis(IKMath.from_to(Vector3.UP, outward_local))
	if Settings.gore == Settings.Gore.BLOOD:
		# a little white bone nub poking out of the middle
		var nub := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = radius * 0.22
		cyl.bottom_radius = radius * 0.28
		cyl.height = radius * 0.7
		var bm := StandardMaterial3D.new()
		bm.albedo_color = STUMP_BONE
		bm.roughness = 0.5
		cyl.material = bm
		nub.mesh = cyl
		nub.position = Vector3.UP * radius * 0.3
		nub.layers = CritterVisual.RENDER_LAYER
		cap.add_child(nub)
