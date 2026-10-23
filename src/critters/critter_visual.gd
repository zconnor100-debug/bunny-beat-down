class_name CritterVisual
extends Node3D
## Everything you can see (and shoot) of a critter: the imported model, the
## procedural animator, per-bone hitboxes, the ragdoll, springy ears/tail,
## the held carrot gun and the acorn helmet.
##
## This node is top-level and interpolated between physics ticks, so movement
## stays smooth on high refresh-rate displays while gameplay runs at 60 Hz.

const HELMET_MODEL := "res://assets/props/acorn_helmet.glb"
const GLIDER_MODEL := "res://assets/props/dandelion_glider.glb"
## Big drop-in umbrellas (each critter gets one at random); authored full-size,
## origin at the paws. The small legacy dandelion is scaled up to match.
const GLIDER_VARIANTS := [
	"res://assets/props/glider_dandelion_plume.glb", "res://assets/props/glider_oak_leaf.glb",
	"res://assets/props/glider_maple_leaf.glb", "res://assets/props/glider_tulip.glb",
	"res://assets/props/glider_daisy.glb", "res://assets/props/glider_mushroom.glb",
]
const GOLD_SHADER := preload("res://src/fx/golden.gdshader")
const ENEMY_RIM_SHADER := preload("res://src/fx/enemy_rim.gdshader")
const NAME_TAG_RANGE := 45.0

static var _enemy_rim: ShaderMaterial

static var _gold_overlay: ShaderMaterial
const BASE_MASS := 12.0
## Carrot guns are drawn bigger than "real" proportions so they read clearly
## in third person (the holder already carries the critter's body scale).
const WEAPON_SCALE := 1.3
const RENDER_LAYER := 2   # decals skip this layer so blood only lands on the world

var critter: Node3D
var def: CritterDef
var model: Node3D
var skeleton: Skeleton3D
var rig: RigInfo
var poser: CritterPoser
var phys_sim: PhysicalBoneSimulator3D
var springs: SpringBoneSimulator3D
var limb_hider: LimbHider
var holder: Node3D
var weapon_model: Node3D
var muzzle: Node3D
var helmet: Node3D
var attachments: Dictionary = {}     # role -> BoneAttachment3D
var hitboxes: Dictionary = {}        # role -> Area3D
var physical_bones: Dictionary = {}  # role -> PhysicalBone3D
var hitbox_rids: Array[RID] = []
var meshes: Array[MeshInstance3D] = []
var _att_by_bone: Dictionary = {}    # bone index -> BoneAttachment3D
var ragdolled := false
var dismembered: Dictionary = {}     # role -> true

var trick: JumpTrick
var _model_base := Transform3D.IDENTITY
var _glider: Node3D
var _loaded_round: Node3D          ## the rocket sitting in the launcher's tube
var _prev_xf := Transform3D.IDENTITY
var _curr_xf := Transform3D.IDENTITY
var _interpolate := true


func build(critter_: Node3D, def_: CritterDef) -> bool:
	critter = critter_
	def = def_
	top_level = true
	model = ModelUtil.instantiate(def.resolved_model())
	if model == null:
		push_error("could not load critter model %s" % def.resolved_model())
		return false
	model.name = "Model"
	model.rotation.y = PI   # models face +Z, critters face -Z
	model.scale = Vector3.ONE * def.body_scale
	_model_base = model.transform
	add_child(model)
	for ap in ModelUtil.find_all(model, "AnimationPlayer"):
		(ap as AnimationPlayer).stop()
	skeleton = ModelUtil.find_first(model, "Skeleton3D") as Skeleton3D
	if skeleton == null:
		push_error("%s has no Skeleton3D" % def.resolved_model())
		return false
	rig = RigInfo.new()
	if not rig.bind(RigInfo.read_json(def.resolved_rig()), skeleton, def.body_scale):
		return false
	for mi in ModelUtil.find_all(model, "MeshInstance3D"):
		var m := mi as MeshInstance3D
		m.layers = RENDER_LAYER
		meshes.append(m)

	holder = Node3D.new()
	holder.name = "WeaponHolder"
	add_child(holder)

	poser = CritterPoser.new()
	poser.name = "Poser"
	poser.holder = holder
	poser.gait = def.gait
	skeleton.add_child(poser)
	poser.setup(rig)

	_build_hitboxes_and_ragdoll()
	_build_springs()

	limb_hider = LimbHider.new()
	limb_hider.name = "LimbHider"
	skeleton.add_child(limb_hider)

	if def.wears_acorn_helmet:
		_attach_helmet()
	return true


# --- per-frame ---------------------------------------------------------------------

## Called by the critter at the end of each physics tick.
func physics_tick(xf: Transform3D, teleported := false) -> void:
	_prev_xf = xf if teleported else _curr_xf
	_curr_xf = xf
	if teleported:
		global_transform = xf


func _process(delta: float) -> void:
	if _interpolate and not ragdolled:
		global_transform = _prev_xf.interpolate_with(_curr_xf, Engine.get_physics_interpolation_fraction())
	if _glider and critter:
		_sway_glider(delta, (critter as CharacterBody3D).velocity)
	if _loaded_round and critter:
		_loaded_round.visible = Critter.round_chambered(critter)
	_update_trick(delta)


func set_first_person(on: bool) -> void:
	var mode := GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY if on else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	for m in meshes:
		m.cast_shadow = mode
	if helmet:
		for m in ModelUtil.find_all(helmet, "GeometryInstance3D"):
			(m as GeometryInstance3D).cast_shadow = mode
	if weapon_model:
		for m in ModelUtil.find_all(weapon_model, "GeometryInstance3D"):
			(m as GeometryInstance3D).cast_shadow = mode


func eye_position() -> Vector3:
	return global_transform * Vector3(0, rig.world_eye_height if rig else 0.85, 0)


## World position of a role's bone *as rendered*. Skeleton3D restores the
## un-modified pose after skinning, so get_bone_global_pose() outside the
## modifier stack would return the rest pose; ragdoll bodies and bone
## attachments always carry the final pose.
func bone_world_position(role: StringName) -> Vector3:
	var idx: int = rig.bone.get(role, -1)
	if idx < 0:
		return global_position
	return skeleton.global_transform * current_bone_global(idx).origin


## Skeleton-space transform of any bone as last rendered (see above).
func current_bone_global(idx: int) -> Transform3D:
	var att: BoneAttachment3D = _att_by_bone.get(idx)
	if att and is_instance_valid(att) and att.is_inside_tree():
		return skeleton.global_transform.affine_inverse() * att.global_transform
	var p := skeleton.get_bone_parent(idx)
	var local := skeleton.get_bone_pose(idx)
	return local if p < 0 else current_bone_global(p) * local


# --- weapon --------------------------------------------------------------------------

func set_weapon(w: WeaponInstance) -> void:
	if weapon_model:
		weapon_model.queue_free()
		weapon_model = null
	muzzle = null
	_loaded_round = null
	poser.support_marker = null
	poser.armed = w != null
	if w == null:
		return
	poser.two_handed = w.data.two_handed
	poser.hold_distance = w.data.hold_distance
	weapon_model = ModelUtil.instantiate(w.data.model_path)
	if weapon_model == null:
		weapon_model = _fallback_gun(w.data)
	holder.add_child(weapon_model)
	weapon_model.scale = Vector3.ONE * rig.scale * WEAPON_SCALE
	for gi in ModelUtil.find_all(weapon_model, "GeometryInstance3D"):
		(gi as GeometryInstance3D).layers = RENDER_LAYER
	if w.rarity == Rarity.Tier.GOLDEN:
		_gild(weapon_model)
	muzzle = ModelUtil.find_named(weapon_model, "Muzzle")
	poser.support_marker = ModelUtil.find_named(weapon_model, "SupportGrip")
	_loaded_round = ModelUtil.find_named(weapon_model, "Rocket")


# --- enemy readability ----------------------------------------------------------------------

var name_tag: Label3D
var _reveal_tween: Tween

## Warm rim light + a name tag above the head (only within NAME_TAG_RANGE, and
## hidden behind cover by the depth test) so opponents are easy to pick out.
func set_enemy_highlight(display_name: String) -> void:
	if _enemy_rim == null:
		_enemy_rim = ShaderMaterial.new()
		_enemy_rim.shader = ENEMY_RIM_SHADER
	for m in meshes:
		m.material_overlay = _enemy_rim
	if name_tag == null:
		name_tag = Label3D.new()
		name_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		name_tag.fixed_size = true
		name_tag.pixel_size = 0.0016
		name_tag.font_size = 30
		name_tag.outline_size = 10
		name_tag.modulate = Color(1.0, 0.42, 0.3)
		name_tag.outline_modulate = Color(0.1, 0.03, 0.02, 0.9)
		name_tag.no_depth_test = false
		name_tag.visibility_range_end = NAME_TAG_RANGE
		name_tag.visibility_range_end_margin = 4.0
		name_tag.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		name_tag.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(name_tag)
	name_tag.text = "▼ " + display_name
	name_tag.position = Vector3(0, (rig.world_head_top if rig else 1.2) + 0.35, 0)


## Show the name tag at any distance for a while (this one is shooting at
## you). It still hides behind cover.
func reveal_name_tag(seconds: float) -> void:
	if name_tag == null:
		return
	name_tag.visibility_range_end = 0.0   # 0 = no limit
	name_tag.modulate = Color(1.0, 0.25, 0.2)
	if _reveal_tween:
		_reveal_tween.kill()
	_reveal_tween = create_tween()
	_reveal_tween.tween_interval(seconds)
	_reveal_tween.tween_callback(func():
		if name_tag:
			name_tag.visibility_range_end = NAME_TAG_RANGE
			name_tag.modulate = Color(1.0, 0.42, 0.3))


func clear_enemy_highlight() -> void:
	for m in meshes:
		m.material_overlay = null
	if name_tag:
		name_tag.queue_free()
		name_tag = null


# --- skins --------------------------------------------------------------------------------

var skin_id := "default"

## Swap albedo textures per material name, as listed in the species' skins.json.
func apply_skin(id: String) -> void:
	skin_id = id
	var entry := def.skin(id)
	var swaps: Dictionary = entry.get("albedo", {})
	var base_dir := def.model_path.get_base_dir()
	for m in meshes:
		for s in m.mesh.get_surface_count():
			var mat := m.mesh.surface_get_material(s) as BaseMaterial3D
			if mat == null:
				continue
			var rel: Variant = swaps.get(mat.resource_name)
			if rel == null:
				m.set_surface_override_material(s, null)
				continue
			var tex_path := base_dir.path_join(String(rel))
			if not ResourceLoader.exists(tex_path):
				continue
			var copy := mat.duplicate() as BaseMaterial3D
			copy.albedo_texture = load(tex_path)
			m.set_surface_override_material(s, copy)


# --- jump tricks ------------------------------------------------------------------------

## Start this species' airborne move. local_vel is the critter's velocity in its
## own frame (x right, -z forward); airtime is the predicted time to touchdown.
func start_jump_trick(local_vel: Vector3, airtime: float) -> void:
	if ragdolled:
		return
	trick = JumpTrick.make(def.jump_style, local_vel, airtime)


func trick_landed() -> void:
	if trick:
		trick.land()


func _update_trick(delta: float) -> void:
	if trick == null or ragdolled:
		if poser:
			poser.trick_tuck = 0.0
			poser.trick_active = false
		return
	trick.step(delta)
	# rotate the whole body about its centre of mass
	var pivot := Vector3(0, (rig.world_head_top if rig else 1.0) * 0.5, 0)
	var r := trick.rotation()
	model.transform = Transform3D(r, pivot - r * pivot) * _model_base
	poser.trick_tuck = trick.tuck()
	poser.trick_active = trick.active
	if trick.finished():
		trick = null
		model.transform = _model_base


## The dandelion-seed parachute held overhead while gliding in from the balloon.
func set_glider(on: bool) -> void:
	if on and _glider == null:
		var choices: Array = GLIDER_VARIANTS.filter(func(p): return ResourceLoader.exists(p))
		var path: String = choices.pick_random() if not choices.is_empty() else GLIDER_MODEL
		_glider = ModelUtil.instantiate(path)
		if _glider == null:
			return
		add_child(_glider)
		var full := Vector3.ONE * rig.world_scale * (1.4 if path == GLIDER_MODEL else 1.0)
		# origin = where the paws grip it, just above the head with arms raised
		_glider.position = Vector3(0, rig.world_head_top + 0.12 * rig.world_scale, 0)
		_glider.scale = full * 0.2
		var tw := _glider.create_tween()
		tw.tween_property(_glider, "scale", full, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	elif not on and _glider:
		var g := _glider
		_glider = null
		var tw := g.create_tween()
		tw.tween_property(g, "scale", Vector3.ONE * 0.01, 0.25)
		tw.tween_callback(g.queue_free)


func _sway_glider(delta: float, velocity: Vector3) -> void:
	if _glider == null:
		return
	# the seed head leans into the wind and bobs gently
	var local_v := global_basis.inverse() * velocity
	var target := Vector3(clampf(local_v.z * 0.03, -0.35, 0.35), 0.0, clampf(-local_v.x * 0.03, -0.35, 0.35))
	_glider.rotation = _glider.rotation.lerp(target, IKMath.damp(4.0, delta))


func muzzle_position() -> Vector3:
	if muzzle and is_instance_valid(muzzle):
		return muzzle.global_position
	if holder:
		return holder.global_transform * Vector3(0, 0.04, -0.35 * rig.scale)
	return eye_position()


func _gild(root: Node) -> void:
	# Golden guns get an additive gold sheen + sweeping glint (works on any model,
	# including single-atlas ones whose carrots and metal share one material)
	if _gold_overlay == null:
		_gold_overlay = ShaderMaterial.new()
		_gold_overlay.shader = GOLD_SHADER
	for gi in ModelUtil.find_all(root, "GeometryInstance3D"):
		(gi as GeometryInstance3D).material_overlay = _gold_overlay


func _fallback_gun(data: WeaponData) -> Node3D:
	# Fallback only — shown until assets/weapons/<id>.glb exists.
	var root := Node3D.new()
	var body := MeshInstance3D.new()
	var box := BoxMesh.new()
	var length: float = {&"carrot_pistol": 0.26, &"carrot_smg": 0.45, &"carrot_shotgun": 0.7, &"carrot_rifle": 0.8,
		&"carrot_lmg": 0.85, &"carrot_sniper": 1.15, &"carrot_rocket_launcher": 0.95}.get(data.id, 0.5)
	box.size = Vector3(0.05, 0.08, length)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = data.icon_color
	box.material = mat
	body.mesh = box
	body.position = Vector3(0, 0.04, -length * 0.35)
	root.add_child(body)
	var mz := Node3D.new()
	mz.name = "Muzzle"
	mz.position = Vector3(0, 0.05, -length * 0.85)
	root.add_child(mz)
	if data.two_handed:
		var sg := Node3D.new()
		sg.name = "SupportGrip"
		sg.position = Vector3(0, -0.02, -length * 0.45)
		root.add_child(sg)
	return root


# --- hitboxes & ragdoll -------------------------------------------------------------------

func _build_hitboxes_and_ragdoll() -> void:
	phys_sim = PhysicalBoneSimulator3D.new()
	phys_sim.name = "Ragdoll"
	phys_sim.active = false
	skeleton.add_child(phys_sim)
	var total_mass := BASE_MASS * pow(rig.world_scale, 3.0)
	for role in RigInfo.BODY_SEGMENTS:
		if not rig.segments.has(role) or not rig.has_role(role):
			continue
		var idx: int = rig.bone[role]
		# spine may alias hips/chest on simple rigs — one body per bone
		if role == &"spine" and (idx == rig.bone[&"hips"] or idx == rig.bone[&"chest"]):
			continue
		if role == &"chest" and idx == rig.bone[&"hips"]:
			continue
		var seg: Dictionary = rig.segments[role]
		var rest_inv: Transform3D = (rig.rest[role] as Transform3D).affine_inverse()
		var a: Vector3 = rest_inv * (seg["start"] as Vector3)
		var b: Vector3 = rest_inv * (seg["end"] as Vector3)
		var radius: float = seg["radius"]
		var shape_xf := _capsule_xform(a, b)
		var height := maxf(a.distance_to(b) + radius * 2.0, radius * 2.0 + 0.01)

		# hitbox (follows the animated bone while alive)
		var att := _add_attachment(role, idx)
		var area := Area3D.new()
		area.name = "Hit_" + role
		area.collision_layer = Layers.HITBOXES
		area.collision_mask = 0
		area.monitoring = false
		area.monitorable = false
		area.set_meta(&"critter", critter)
		area.set_meta(&"role", role)
		var cs := CollisionShape3D.new()
		var cap := CapsuleShape3D.new()
		var hs := def.hitbox_scale
		cap.radius = radius * hs
		cap.height = maxf(height + radius * 0.3 + radius * (hs - 1.0) * 2.0, cap.radius * 2.0 + 0.001)
		cs.shape = cap
		cs.transform = shape_xf
		area.add_child(cs)
		att.add_child(area)
		hitboxes[role] = area
		hitbox_rids.append(area.get_rid())

		# ragdoll body (dormant until death)
		var pb := PhysicalBone3D.new()
		pb.name = "Phys_" + role
		pb.bone_name = skeleton.get_bone_name(idx)
		pb.collision_layer = 0
		pb.collision_mask = Layers.WORLD | Layers.DEBRIS
		pb.mass = maxf(total_mass * RigInfo.BODY_SEGMENTS[role], 0.05)
		pb.friction = 0.8
		pb.linear_damp = 0.15
		pb.angular_damp = 1.5
		pb.set_meta(&"critter", critter)
		pb.set_meta(&"role", role)
		if role == &"hips":
			pb.joint_type = PhysicalBone3D.JOINT_TYPE_NONE
		else:
			pb.joint_type = PhysicalBone3D.JOINT_TYPE_CONE
			# cone twist axis is the joint's X; bones run along their local Y
			pb.joint_rotation = Vector3(0, 0, PI / 2.0)
			var swing := 35.0
			var twist := 25.0
			if role.ends_with("upper_arm"):
				swing = 85.0
				twist = 45.0
			elif role.ends_with("lower_arm") or role.ends_with("lower_leg"):
				swing = 70.0
				twist = 10.0
			elif role.ends_with("upper_leg"):
				swing = 60.0
				twist = 20.0
			elif role == &"head":
				swing = 40.0
				twist = 35.0
			pb.set("joint_constraints/swing_span", swing)
			pb.set("joint_constraints/twist_span", twist)
			pb.set("joint_constraints/softness", 0.8)
			pb.set("joint_constraints/relaxation", 1.0)
		var pcs := CollisionShape3D.new()
		var pcap := CapsuleShape3D.new()
		pcap.radius = radius
		pcap.height = height
		pcs.shape = pcap
		pcs.transform = shape_xf
		pb.add_child(pcs)
		phys_sim.add_child(pb)
		physical_bones[role] = pb


	# paws and feet get attachments too, so their rendered pose can be read
	for role in [&"l_hand", &"r_hand", &"l_foot", &"r_foot", &"neck"]:
		var idx: int = rig.bone.get(role, -1)
		if idx >= 0 and not _att_by_bone.has(idx):
			_add_attachment(role, idx)


func _add_attachment(role: StringName, idx: int) -> BoneAttachment3D:
	var att := BoneAttachment3D.new()
	att.name = "Att_" + role
	att.bone_idx = idx
	skeleton.add_child(att)
	attachments[role] = att
	_att_by_bone[idx] = att
	return att


static func _capsule_xform(a: Vector3, b: Vector3) -> Transform3D:
	var dir := b - a
	var basis := Basis(IKMath.from_to(Vector3.UP, dir)) if dir.length_squared() > 1e-8 else Basis.IDENTITY
	return Transform3D(basis, (a + b) * 0.5)


func _build_springs() -> void:
	if rig.chains.is_empty():
		return
	springs = SpringBoneSimulator3D.new()
	springs.name = "Springs"
	skeleton.add_child(springs)
	springs.setting_count = rig.chains.size()
	var i := 0
	for chain_name in rig.chains:
		var chain: PackedInt32Array = rig.chains[chain_name]
		springs.set_root_bone(i, chain[0])
		springs.set_end_bone(i, chain[chain.size() - 1])
		springs.set_extend_end_bone(i, true)
		springs.set_end_bone_length(i, 0.06 * rig.scale)
		var is_tail := String(chain_name).begins_with("tail")
		springs.set_stiffness(i, 1.4 if is_tail else 1.0)
		springs.set_drag(i, 0.35)
		springs.set_gravity(i, 0.5 if is_tail else 0.35)
		springs.set_radius(i, 0.015 * rig.scale)
		i += 1


func _attach_helmet() -> void:
	var head_idx: int = rig.bone[&"head"]
	var att := BoneAttachment3D.new()
	att.name = "HelmetMount"
	att.bone_idx = head_idx
	skeleton.add_child(att)
	helmet = ModelUtil.instantiate(HELMET_MODEL)
	if helmet == null:
		return   # no helmet model yet — the bunny goes bare-headed
	var head_rest: Transform3D = rig.rest[&"head"]
	# The helmet is authored around the hero's skull: its origin (centre of the
	# opening) sits just above the eyes. rig.json may override the seat/scale.
	var seat_arr: Array = rig.data.get("helmet_origin", [0.0, rig.eye_height + 0.02, -0.01])
	var seat := Vector3(seat_arr[0], seat_arr[1], seat_arr[2])
	var s := float(rig.data.get("helmet_scale", 1.0))
	helmet.transform = Transform3D(head_rest.basis.inverse().scaled(Vector3.ONE * s), head_rest.affine_inverse() * seat)
	for gi in ModelUtil.find_all(helmet, "GeometryInstance3D"):
		(gi as GeometryInstance3D).layers = RENDER_LAYER
	att.add_child(helmet)


# --- death ------------------------------------------------------------------------------------

func go_ragdoll(velocity: Vector3) -> void:
	if ragdolled:
		return
	ragdolled = true
	poser.active = false
	clear_enemy_highlight()
	for area in hitboxes.values():
		(area as Area3D).collision_layer = 0
	for pb in physical_bones.values():
		(pb as PhysicalBone3D).collision_layer = Layers.RAGDOLL
	phys_sim.active = true
	phys_sim.physical_bones_start_simulation()
	for pb in physical_bones.values():
		(pb as PhysicalBone3D).linear_velocity = velocity
	if holder:
		holder.visible = false


func push_bone(role: StringName, impulse: Vector3, at: Vector3) -> void:
	var pb: PhysicalBone3D = physical_bones.get(role)
	if pb == null or not is_instance_valid(pb):
		pb = physical_bones.get(&"chest", physical_bones.get(&"hips"))
	if pb and is_instance_valid(pb):
		pb.apply_impulse(impulse, at - pb.global_position)


func pop_helmet(impulse: Vector3) -> void:
	if helmet == null or not is_instance_valid(helmet):
		return
	var body := RigidBody3D.new()
	body.collision_layer = Layers.DEBRIS
	body.collision_mask = Layers.WORLD | Layers.DEBRIS
	body.mass = 0.4
	var cs := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 0.12 * rig.world_scale
	cs.shape = sph
	cs.position = Vector3(0, 0.08 * rig.world_scale, 0)
	body.add_child(cs)
	var xf := helmet.global_transform
	get_tree().current_scene.add_child(body)
	body.global_transform = Transform3D(xf.basis.orthonormalized(), xf.origin)
	helmet.reparent(body, true)
	body.apply_central_impulse(impulse + Vector3.UP * 1.2)
	body.angular_velocity = Vector3(randf_range(-12, 12), randf_range(-6, 6), randf_range(-12, 12))
	helmet = null
	Despawner.schedule(body, 45.0)


## Removes the limb starting at `role` from the corpse and launches it as a gib.
func dismember(role: StringName, impulse: Vector3) -> void:
	if dismembered.has(role) or not rig.has_role(role):
		return
	var idx: int = rig.bone[role]
	for hidden_idx in limb_hider.hidden:
		if _is_ancestor(hidden_idx, idx):
			return
	dismembered[role] = true
	var sub := rig.subtree(idx)
	var gib := Gore.spawn_limb_gib(self, idx, impulse)
	limb_hider.hidden.append(idx)
	for r in physical_bones.keys():
		if sub.has(rig.bone.get(r, -1)):
			var pb: PhysicalBone3D = physical_bones[r]
			physical_bones.erase(r)
			if is_instance_valid(pb):
				pb.queue_free()
	Gore.make_stump(self, idx)
	# the limb is gone: drop its attachments (hitboxes, stuck carrots and all)
	for r in attachments.keys():
		var att_idx: int = rig.bone.get(r, -1)
		if sub.has(att_idx):
			hitboxes.erase(r)
			_att_by_bone.erase(att_idx)
			(attachments[r] as Node).queue_free()
			attachments.erase(r)
	if role == &"head" and helmet:
		pop_helmet(impulse * 0.5)
	if gib:
		Gore.make_gib_stump(gib, self, idx)


func _is_ancestor(ancestor: int, idx: int) -> bool:
	var i := idx
	while i >= 0:
		if i == ancestor:
			return true
		i = skeleton.get_bone_parent(i)
	return false
