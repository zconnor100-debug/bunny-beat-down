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
const XRAY_SHADER := preload("res://src/fx/xray.gdshader")
const SINGED_SHADER := preload("res://src/fx/singed.gdshader")
const NAME_TAG_RANGE := 45.0
static var name_tag_range_scale := 1.0     ## the Hawk Eye perk doubles it
## Name tags keep their size on screen this close, and shrink further off (to
## NAME_TAG_MIN_SCALE) so a far-away critter isn't hidden under its own name.
const NAME_TAG_FULL_SIZE := 10.0
const NAME_TAG_MIN_SCALE := 0.35

static var _enemy_rim: ShaderMaterial
static var _ally_rim: ShaderMaterial
static var _xray: ShaderMaterial       # (Pack Sense: reveal)
var _reveal_until := 0

static var _gold_overlay: ShaderMaterial
static var _soot: ShaderMaterial
var singed := false   ## sooty fur (RivalBook "singed"), kept through a change of skin
const BASE_MASS := 12.0
## Carrot guns are drawn bigger than "real" proportions so they read clearly
## in third person (the holder already carries the critter's body scale).
const WEAPON_SCALE := 1.3
## Clubs are huge so you can see them coming: three quarters of the critter's
## height, and twice as thick as a gun-sized prop would be.
const CLUB_LENGTH := 0.75
const CLUB_THICKNESS := 2.0
const RENDER_LAYER := 2   # decals skip this layer so blood only lands on the world

var critter: Node3D
var def: CritterDef
var model: Node3D
var skeleton: Skeleton3D
var rig: RigInfo
var poser: CritterPoser
var phys_sim: PhysicalBoneSimulator3D
var knocked := false               ## off its feet for now (Critter.knock_down): the ragdoll's on
var springs: SpringBoneSimulator3D
var limb_hider: LimbHider
var holder: Node3D
var weapon_model: Node3D
## The player's Workshop kit for the guns it holds (GunKit: sight, laser, skin).
var kit: Dictionary = {}
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
var outfit: Array[Node3D] = []       ## a rogue's outfit pieces (Outfits), riding on the bones

var trick: JumpTrick
var _model_base := Transform3D.IDENTITY
var _glider: Node3D
var _glider_path := ""
var _gun_two_handed := true
var _tilt := Vector3.ZERO          # glider lean: rotation axis * angle (this node's frame)
var _glide_t := 0.0
var _loaded_round: Node3D          ## the rocket sitting in the launcher's tube
var _prev_xf := Transform3D.IDENTITY
var _curr_xf := Transform3D.IDENTITY
var _interpolate := true
## Posing (the animator, the springs, the ragdoll, then the skin) is the
## dearest thing a critter does each frame, so the skeleton is advanced from
## here: not while the critter can't be seen (riding in the balloon), every
## frame up close, every other frame further off and every third beyond that
## (or behind the camera). The critters take turns.
const POSE_FULL := 30.0
const POSE_HALF := 70.0
var _pose_dt := 0.0
var _pose_wait := 0


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
	skeleton.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_MANUAL
	_pose_wait = randi() % 3
	rig = RigInfo.new()
	if not rig.bind(RigInfo.read_json(def.resolved_rig()), skeleton, def.body_scale):
		return false
	for mi in ModelUtil.find_all(model, "MeshInstance3D"):
		var m := mi as MeshInstance3D
		m.layers = RENDER_LAYER
		meshes.append(m)

	# mitten paws get knuckles, so they can close on a handle too
	PawKnuckles.apply(self)
	# deep-set eyeballs brought out where they can be seen (rig.json eye_bulge)
	EyeBulge.apply(self)

	holder = Node3D.new()
	holder.name = "WeaponHolder"
	add_child(holder)

	poser = CritterPoser.new()
	poser.name = "Poser"
	poser.holder = holder
	poser.gait = def.gait
	skeleton.add_child(poser)
	poser.setup(rig)
	poser.paws = PawGrip.paws(self)

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
	_update_body_xf()
	_size_name_tag()
	if (ragdolled or knocked) and not _loose.is_empty():
		_follow_loose_bones()
	_advance_pose(delta)


func _advance_pose(delta: float) -> void:
	_pose_dt += delta
	if not is_visible_in_tree():
		return
	_pose_wait -= 1
	if _pose_wait > 0:
		return
	_pose_wait = _pose_interval()
	skeleton.advance(minf(_pose_dt, 0.1))
	_pose_dt = 0.0


## Frames from one pose to the next: 1 up close (or with no camera to judge by).
func _pose_interval() -> int:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return 1
	var at := global_position
	var d := cam.global_position.distance_to(at)
	if d < POSE_FULL:
		return 1
	return 3 if d > POSE_HALF or cam.is_position_behind(at) else 2


## The KillCam's replay runs with the match paused, this node too: meanwhile
## the skeleton advances itself, every frame.
func pose_every_frame(on: bool) -> void:
	skeleton.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_IDLE if on \
		else Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_MANUAL


func set_first_person(on: bool) -> void:
	_first_person = on
	for m in meshes:
		m.cast_shadow = _shadow_mode()
	for n in [helmet, weapon_model, club_model] + outfit:
		_match_first_person(n)


## Looking out of this critter's eyes, its body and whatever it holds only
## cast shadows (the camera draws its own viewmodel). Anything put in its
## paws later — a gun picked up, the club — follows the same rule.
func _match_first_person(n: Node) -> void:
	if n and is_instance_valid(n):
		for m in ModelUtil.find_all(n, "GeometryInstance3D"):
			(m as GeometryInstance3D).cast_shadow = _shadow_mode()


func match_first_person(n: Node) -> void:
	_match_first_person(n)


func _shadow_mode() -> GeometryInstance3D.ShadowCastingSetting:
	return GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY if _first_person else GeometryInstance3D.SHADOW_CASTING_SETTING_ON


var _first_person := false


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
	poser.gun_box = AABB()
	if w != null:
		set_club(false)   # a gun in the paws puts the club away
	poser.armed = w != null or club_model != null
	if w == null:
		return
	_gun_two_handed = w.data.two_handed
	poser.two_handed = w.data.two_handed
	poser.hold_distance = w.data.hold_distance
	poser.shouldered = w.data.projectile == WeaponData.ProjectileKind.ROCKET
	weapon_model = ModelUtil.instantiate(w.data.model_path)
	if weapon_model == null:
		weapon_model = _fallback_gun(w.data)
	holder.add_child(weapon_model)
	weapon_model.scale = Vector3.ONE * rig.scale * WEAPON_SCALE
	GunKit.dress(weapon_model, kit, weapon_model.global_transform.basis.get_scale().x, w.rarity == Rarity.Tier.GOLDEN)
	for gi in ModelUtil.find_all(weapon_model, "GeometryInstance3D"):
		(gi as GeometryInstance3D).layers = RENDER_LAYER
	if w.rarity == Rarity.Tier.GOLDEN:
		_gild(weapon_model)
	_match_first_person(weapon_model)
	muzzle = ModelUtil.find_named(weapon_model, "Muzzle")
	poser.support_marker = ModelUtil.find_named(weapon_model, "SupportGrip")
	# its size in the paws, so the poser can keep it out of the critter's face
	poser.gun_box = weapon_model.transform * ModelUtil.aabb_of(weapon_model)
	_loaded_round = ModelUtil.find_named(weapon_model, "Rocket")


# --- melee club ---------------------------------------------------------------------------

var club_model: Node3D


## Pull out (or put away) the species' own club. A gun in the paws is
## stowed (hidden) while the club is out and comes back when it's put away.
func set_club(on: bool) -> void:
	if on and club_model == null:
		club_model = make_club()
		holder.add_child(club_model)
		for gi in ModelUtil.find_all(club_model, "GeometryInstance3D"):
			(gi as GeometryInstance3D).layers = RENDER_LAYER
		_match_first_person(club_model)
	elif not on and club_model:
		club_model.queue_free()
		club_model = null
	poser.club = club_model != null
	if weapon_model:
		weapon_model.visible = club_model == null
	if club_model:
		poser.armed = true
		poser.two_handed = false
	else:
		poser.armed = weapon_model != null
		poser.two_handed = _gun_two_handed


## A new instance of this species' club, sized for the paws: CLUB_LENGTH of
## the critter's height from grip to tip, CLUB_THICKNESS times as thick as a
## gun-scale prop. (Its scale is in model units: the holder carries body_scale.)
func make_club() -> Node3D:
	var club: Node3D = null
	if def.melee_model != "" and ResourceLoader.exists(def.melee_model):
		club = ModelUtil.instantiate(def.melee_model)
	if club == null:
		club = _fallback_club()
	club.name = "Club"
	var box := ModelUtil.aabb_of(club)
	var length := maxf(-box.position.z, 0.05)   # grip at the origin, tip toward -Z
	var thick := rig.scale * WEAPON_SCALE * CLUB_THICKNESS
	club.scale = Vector3(thick, thick, CLUB_LENGTH * rig.head_top / length)
	return club


## World-space length of the club from grip to tip (for reach and tests).
func club_length() -> float:
	return CLUB_LENGTH * rig.world_head_top


func _fallback_club() -> Node3D:
	# Fallback only — shown until assets/weapons/melee_*.glb exists.
	var root := Node3D.new()
	var body := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.018
	cone.bottom_radius = 0.045
	cone.height = 0.5
	var mat := StandardMaterial3D.new()
	mat.albedo_color = def.fur_color.darkened(0.3)
	cone.material = mat
	body.mesh = cone
	body.rotation.x = -PI / 2.0   # thick end forward (-Z)
	body.position = Vector3(0, 0, -0.22)
	root.add_child(body)
	return root


# --- enemy readability ----------------------------------------------------------------------

var name_tag: Label3D
var _reveal_tween: Tween

## Warm rim light + a name tag above the head (only within NAME_TAG_RANGE, and
## hidden behind cover by the depth test) so opponents are easy to pick out.
## `heat`: how radical you've made this bot (Cast.heat): its tag turns hotter.
func set_enemy_highlight(display_name: String, rival := false, heat := 0) -> void:
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
		name_tag.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM   # (a second line, the gang, goes up, not over the critter)
		name_tag.visibility_range_end = NAME_TAG_RANGE * name_tag_range_scale
		name_tag.visibility_range_end_margin = 4.0
		name_tag.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		name_tag.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(name_tag)
	name_tag.text = ("⚔ RIVAL %s" if rival else "▼ %s") % display_name
	name_tag.modulate = Cast.HEAT_COLORS[clampi(heat, 0, Cast.HEAT_COLORS.size() - 1)]
	if heat >= 3:
		name_tag.font_size = 34
	if rival:
		name_tag.modulate = Color(0.85, 0.45, 1.0)
	name_tag.position = Vector3(0, (rig.world_head_top if rig else 1.2) + 0.35, 0)


## On your side (a Team Battle or a Boss Battle): a cool blue rim and a blue
## name tag you see through walls, so you know who not to shoot.
func set_ally_tag(display_name: String) -> void:
	if _ally_rim == null:
		_ally_rim = ShaderMaterial.new()
		_ally_rim.shader = ENEMY_RIM_SHADER
		_ally_rim.set_shader_parameter(&"rim_color", Color(0.25, 0.62, 1.0))
		_ally_rim.set_shader_parameter(&"strength", 0.7)
	for m in meshes:
		if m.material_overlay == null or m.material_overlay == _enemy_rim:
			m.material_overlay = _ally_rim
	if name_tag == null:
		name_tag = Label3D.new()
		name_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		name_tag.fixed_size = true
		name_tag.pixel_size = 0.0014
		name_tag.font_size = 26
		name_tag.outline_size = 10
		name_tag.outline_modulate = Color(0.02, 0.06, 0.14, 0.9)
		name_tag.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		name_tag.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(name_tag)
	name_tag.no_depth_test = true   # (a team mate shows through walls)
	name_tag.visibility_range_end = NAME_TAG_RANGE * 3.0 * name_tag_range_scale
	name_tag.text = "◆ %s" % display_name
	name_tag.modulate = Color(0.45, 0.78, 1.0)
	_tag_color = name_tag.modulate
	name_tag.position = Vector3(0, (rig.world_head_top if rig else 1.2) + 0.35, 0)


## A speech bubble over this critter's head for a few seconds (a taunt).
func say(text: String, seconds := 3.5) -> void:
	var bubble := Label3D.new()
	bubble.text = text
	bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	bubble.fixed_size = true
	bubble.pixel_size = 0.0014
	bubble.font_size = 30
	bubble.outline_size = 12
	bubble.modulate = Color(1.0, 0.97, 0.88)
	bubble.outline_modulate = Color(0.25, 0.1, 0.35, 0.95)
	bubble.no_depth_test = true
	bubble.width = 420.0
	bubble.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bubble.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(bubble)
	bubble.position = Vector3(0, (rig.world_head_top if rig else 1.2) + 1.1, 0)
	var tw := bubble.create_tween()
	tw.tween_interval(seconds)
	tw.tween_property(bubble, "modulate:a", 0.0, 0.5)
	tw.tween_callback(bubble.queue_free)


## Show the name tag at any distance for a while (this one is shooting at
## you). It still hides behind cover.
func reveal_name_tag(seconds: float) -> void:
	if name_tag == null:
		return
	if _reveal_tween and _reveal_tween.is_valid():
		_reveal_tween.kill()
	else:
		_tag_color = name_tag.modulate   # (its own colour: heat, rival, nemesis)
	name_tag.visibility_range_end = 0.0   # 0 = no limit
	name_tag.modulate = Color(1.0, 0.25, 0.2)
	_reveal_tween = create_tween()
	_reveal_tween.tween_interval(seconds)
	_reveal_tween.tween_callback(func():
		if name_tag:
			name_tag.visibility_range_end = NAME_TAG_RANGE * name_tag_range_scale
			name_tag.modulate = _tag_color)


var _tag_color := Color(1.0, 0.42, 0.3)


## Full size up close; past NAME_TAG_FULL_SIZE it shrinks with distance (more
## slowly than the critter does, so it stays readable).
func _size_name_tag() -> void:
	if name_tag == null or not name_tag.visible:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var d := cam.global_position.distance_to(name_tag.global_position)
	name_tag.scale = Vector3.ONE * clampf(pow(NAME_TAG_FULL_SIZE / maxf(d, 0.01), 0.6), NAME_TAG_MIN_SCALE, 1.0)


## Seen through walls for `seconds` (your Pack Sense boon): an x-ray glow
## over the body, then back to how it looked.
func reveal(seconds: float) -> void:
	if _xray == null:
		_xray = ShaderMaterial.new()
		_xray.shader = XRAY_SHADER
	for m in meshes:
		if m.material_overlay != _xray:
			m.set_meta(&"overlay_before", m.material_overlay)
			m.material_overlay = _xray
	_reveal_until = maxi(_reveal_until, Time.get_ticks_msec() + int(seconds * 1000.0))
	get_tree().create_timer(seconds, false).timeout.connect(_end_reveal)


func revealed() -> bool:
	return meshes.any(func(m): return m.material_overlay == _xray) if _xray else false


func _end_reveal() -> void:
	if Time.get_ticks_msec() < _reveal_until - 30:
		return   # (revealed again since: that one ends it)
	for m in meshes:
		if is_instance_valid(m) and m.material_overlay == _xray:
			m.material_overlay = m.get_meta(&"overlay_before", null)


func clear_enemy_highlight() -> void:
	for m in meshes:
		if m.material_overlay and (m.material_overlay == _enemy_rim or m.material_overlay == _xray):
			m.material_overlay = null   # (a coat or a cracked mirror stays on)
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
	if singed:
		_singe()


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
	# (the body spins about its centre of mass: see _update_body_xf)
	poser.trick_tuck = trick.tuck()
	poser.trick_active = trick.active
	if trick.finished():
		trick = null


## The dandelion-seed parachute held overhead while gliding in from the balloon.
func set_glider(on: bool) -> void:
	if on and _glider == null:
		if _glider_path == "":
			# (one glider a drop: opened again, it's the same one)
			var choices: Array = GLIDER_VARIANTS.filter(func(p): return ResourceLoader.exists(p))
			_glider_path = choices.pick_random() if not choices.is_empty() else GLIDER_MODEL
		var path := _glider_path
		_glider = ModelUtil.instantiate(path)
		if _glider == null:
			return
		add_child(_glider)
		var full := Vector3.ONE * rig.world_scale * (1.4 if path == GLIDER_MODEL else 1.0)
		# origin = where the paws grip it, above the head with arms raised
		_glider.position = Vector3(0, rig.world_head_top + 0.12 * rig.world_scale, 0)
		poser.glide_grip = _glider
		_glider.scale = full * 0.2
		var tw := _glider.create_tween()
		tw.tween_property(_glider, "scale", full, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	elif not on and _glider:
		var g := _glider
		_glider = null
		poser.glide_grip = null
		var tw := g.create_tween()
		tw.tween_property(g, "scale", Vector3.ONE * 0.01, 0.25)
		tw.tween_callback(g.queue_free)


## Hanging under the glider: critter and canopy lean together around the
## grip toward whichever way you steer (as you see it: stick right, lean
## right), with a slow pendulum sway on top. The legs just dangle (CritterPoser).
const GLIDE_LEAN := 0.38          ## radians at full stick


func _sway_glider(delta: float, _velocity: Vector3) -> void:
	if _glider == null:
		return
	_glide_t += delta
	var c := critter as Critter
	var steer := Vector3.ZERO
	if c:
		var stick := c.move_input.limit_length(1.0)
		steer = global_basis.inverse() * (Basis(Vector3.UP, c.look_yaw) * Vector3(stick.x, 0.0, -stick.y))
		steer.y = 0.0
	# tipping the top toward `steer` = rotating about up × steer
	var want := Vector3.UP.cross(steer) * GLIDE_LEAN
	want += Vector3(sin(_glide_t * 1.1 + 0.8) * 0.03, 0.0, -sin(_glide_t * 1.7) * 0.05)
	_tilt = _tilt.lerp(want, IKMath.damp(3.0, delta))
	_glider.basis = _tilt_basis().scaled_local(_glider.basis.get_scale())


func _tilt_basis() -> Basis:
	var angle := _tilt.length()
	return Basis(_tilt / angle, angle) if angle > 1e-5 else Basis.IDENTITY


## The model's pose on top of its rest placement: a jump trick's spin, lying
## prone (tipped forward onto the belly, centred over the feet), or banking
## under the glider (rotated about the grip, together with the canopy).
func _update_body_xf() -> void:
	if ragdolled or model == null or rig == null:
		return
	var xf := Transform3D.IDENTITY
	if trick:
		var pivot := Vector3(0, rig.world_head_top * 0.5, 0)
		var r := trick.rotation()
		xf = Transform3D(r, pivot - r * pivot)
	var prone := smoothstep(0.0, 1.0, poser.prone) if poser else 0.0
	if prone > 0.0:
		var h := rig.world_head_top
		# pivot at the body's half-depth (its thickest trunk segment), so the
		# belly rests on the ground: round hamsters lie higher than lean foxes
		var depth := maxf(maxf(rig.radii.get(&"hips", 0.05), rig.radii.get(&"spine", 0.05)), rig.radii.get(&"chest", 0.05)) * rig.size
		var c := Vector3(0, depth, 0)
		var r := Basis(Vector3.RIGHT, -1.45 * prone)
		xf = Transform3D(r, c - r * c + Vector3(0, 0, (h * 0.5 - c.y) * prone)) * xf
	if _glider:
		var g := _glider.position
		var b := _tilt_basis()
		xf = Transform3D(b, g - b * g) * xf
	else:
		_tilt = Vector3.ZERO
	model.transform = xf * _model_base


## Where shots leave from: the muzzle of the gun as if raised to the aim
## (CritterPoser.raised_holder), even while it's carried lowered.
func muzzle_position() -> Vector3:
	if muzzle and is_instance_valid(muzzle):
		if poser and poser.has_raised and holder:
			return poser.raised_holder * (holder.global_transform.affine_inverse() * muzzle.global_position)
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
		&"carrot_lmg": 0.85, &"carrot_sniper": 1.15, &"carrot_rocket_launcher": 0.95, &"root_rumbler": 0.9, &"carrot_lobber": 0.7,
		&"big_root_50": 1.3}.get(data.id, 0.5)
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
		# ears bounce but hold their shape (floppier ones folded over the face
		# at a run); tails swish and trail without whipping round the legs
		# (the fox's long brush most of all: soft, it looped under the body at every bound)
		var is_tail := String(chain_name).begins_with("tail")
		var long_tail := is_tail and chain.size() >= 5
		springs.set_stiffness(i, 4.0 if long_tail else (3.0 if is_tail else 2.6))
		springs.set_drag(i, 0.7 if long_tail else (0.55 if is_tail else 0.45))
		springs.set_gravity(i, 0.08 if long_tail else (0.12 if is_tail else 0.15))
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
	var was_down := knocked
	if knocked:   # (beaten down while it was down: the ragdoll's on already, and stays)
		knocked = false
		if _rise and _rise.is_valid():
			_rise.kill()
	ragdolled = true
	clear_enemy_highlight()
	for area in hitboxes.values():
		(area as Area3D).collision_layer = 0
	for pb in physical_bones.values():
		(pb as PhysicalBone3D).collision_layer = Layers.RAGDOLL
	if was_down:
		poser.active = false
		phys_sim.influence = 1.0
	else:
		_note_loose_bones()
		phys_sim.active = true
		phys_sim.physical_bones_start_simulation()
		_bodies_to_pose()
		_take_over(true)
	for pb in physical_bones.values():
		(pb as PhysicalBone3D).linear_velocity = velocity
	if holder:
		holder.visible = false


## Off its feet (Critter.knock_down): the ragdoll takes over, thrown with
## `velocity` and tumbling, while the poser keeps its standing pose
## underneath (the simulator comes after it) for when it gets up (`rise`).
## Its gun's put away meanwhile.
func knock_down(velocity: Vector3) -> void:
	if ragdolled or knocked:
		return
	knocked = true
	if _rise and _rise.is_valid():
		_rise.kill()
	_note_loose_bones()
	phys_sim.active = true
	phys_sim.physical_bones_start_simulation()
	_bodies_to_pose()
	_take_over(false)
	var tumble := Vector3(randf_range(-3.0, 3.0), randf_range(-2.0, 2.0), randf_range(-3.0, 3.0))
	for pb in physical_bones.values():
		(pb as PhysicalBone3D).linear_velocity = velocity
		(pb as PhysicalBone3D).angular_velocity = tumble
	poser.down = true
	if holder:
		holder.visible = false


## Up again over `seconds`: the ragdoll's hold eases off and the standing
## pose takes over (it springs back to its feet), then the ragdoll's off.
func rise(seconds: float) -> void:
	if not knocked or ragdolled:
		return
	if _rise and _rise.is_valid():
		_rise.kill()
	_rise = create_tween()
	_rise.tween_property(phys_sim, "influence", 0.0, seconds).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	_rise.tween_callback(end_knock)


func rising() -> bool:
	return _rise != null and _rise.is_valid() and _rise.is_running()


## On its feet (or put back somewhere: a rewind, a teleport): the ragdoll's
## off, the bones it left lying go back where the poser has them, the gun's out.
func end_knock() -> void:
	if not knocked:
		return
	knocked = false
	if _rise and _rise.is_valid():
		_rise.kill()
	_rise = null
	if ragdolled:
		return
	phys_sim.physical_bones_stop_simulation()
	phys_sim.active = false
	phys_sim.influence = 1.0
	for b: int in _loose:
		skeleton.set_bone_pose(b, skeleton.get_bone_rest(b))
	_loose.clear()
	poser.down = false


var _rise: Tween


## The ragdoll takes over once its bodies have been stepped from where they
## were put (_bodies_to_pose): till then the simulator still has them at the
## rest pose, so for that frame the poser's pose shows instead (`stop_poser`:
## a death's, and then the poser's done).
func _take_over(stop_poser: bool) -> void:
	phys_sim.influence = 0.0
	await get_tree().physics_frame
	await get_tree().physics_frame
	if not is_instance_valid(phys_sim) or not phys_sim.active:
		return
	if stop_poser:
		poser.active = false
	if not rising():
		phys_sim.influence = 1.0


## The ragdoll's bodies put where the bones are as rendered, as it takes over
## (starting the simulation puts every body at its bone's unmodified pose, the
## rest pose: left alone, every ragdoll started arms out, in a T).
func _bodies_to_pose() -> void:
	for pb: PhysicalBone3D in physical_bones.values():
		var idx := skeleton.find_bone(pb.bone_name)
		if idx >= 0:
			var xf := skeleton.global_transform * current_bone_global(idx) * pb.body_offset
			pb.global_transform = xf
			PhysicsServer3D.body_set_state(pb.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, xf)


## Bones hanging straight off the skeleton's root rather than off the body, or
## roots of their own (a squirrel's tail, and the two hip bones its thighs hang
## from, are three more roots beside its pelvis), aren't moved by the ragdoll:
## the body flew off and left them where it stood, the skin stretched across
## the floor between. At death each one's place on the hips is kept, and from
## then on it's put back there every frame (_follow_loose_bones), so it goes
## with the body. (The skeleton itself isn't changed: the ragdoll can't take
## bones changing parents under it.)
func _note_loose_bones() -> void:
	var hips: int = rig.bone.get(&"hips", -1)
	if hips < 0:
		return
	var above := {}   # (the bones the hips hang from)
	var a := skeleton.get_bone_parent(hips)
	while a >= 0:
		above[a] = true
		a = skeleton.get_bone_parent(a)
	var parts := {}
	for pb: PhysicalBone3D in physical_bones.values():
		parts[skeleton.find_bone(pb.bone_name)] = true
	var hg := skeleton.get_bone_global_pose(hips)
	for b in skeleton.get_bone_count():
		var parent := skeleton.get_bone_parent(b)
		if b == hips or above.has(b) or parts.has(b) or not (parent < 0 or above.has(parent)):
			continue
		_loose[b] = hg.affine_inverse() * skeleton.get_bone_global_pose(b)
	_loose_hips = hips


func _follow_loose_bones() -> void:
	var hg := current_bone_global(_loose_hips)
	for b: int in _loose:
		var g: Transform3D = hg * _loose[b]
		var parent := skeleton.get_bone_parent(b)
		var local := g if parent < 0 else current_bone_global(parent).affine_inverse() * g
		skeleton.set_bone_pose_position(b, local.origin)
		skeleton.set_bone_pose_rotation(b, local.basis.get_rotation_quaternion())


var _loose := {}   # bone -> where it sat on the hips at death
var _loose_hips := -1


func push_bone(role: StringName, impulse: Vector3, at: Vector3) -> void:
	var pb: PhysicalBone3D = physical_bones.get(role)
	if pb == null or not is_instance_valid(pb):
		pb = physical_bones.get(&"chest", physical_bones.get(&"hips"))
	if pb and is_instance_valid(pb):
		pb.apply_impulse(impulse, at - pb.global_position)


func pop_helmet(impulse: Vector3) -> void:
	# (a rogue's hat, glasses and the rest fly off with it)
	for piece in outfit.duplicate():
		if is_instance_valid(piece) and piece.get_parent() == attachments.get(&"head"):
			outfit.erase(piece)
			_knock_off(piece, impulse * randf_range(0.8, 1.2), 0.25)
	if helmet == null or not is_instance_valid(helmet):
		return
	_knock_off(helmet, impulse, 0.4)
	helmet = null


## Send something the critter was wearing flying: a little physics body
## that bounces about and is tidied away later.
func _knock_off(thing: Node3D, impulse: Vector3, mass: float) -> void:
	var body := RigidBody3D.new()
	body.collision_layer = Layers.DEBRIS
	body.collision_mask = Layers.WORLD | Layers.DEBRIS
	body.mass = mass
	var cs := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 0.12 * rig.world_scale
	cs.shape = sph
	cs.position = Vector3(0, 0.08 * rig.world_scale, 0)
	body.add_child(cs)
	var xf := thing.global_transform
	Despawner.debris_parent(self).add_child(body)   # (test runs have no current scene)
	body.global_transform = Transform3D(xf.basis.orthonormalized(), xf.origin)
	thing.reparent(body, true)
	body.apply_central_impulse(impulse + Vector3.UP * 1.2)
	body.angular_velocity = Vector3(randf_range(-12, 12), randf_range(-6, 6), randf_range(-12, 12))
	Despawner.schedule(body, 45.0)
	if KillCam.recording and not KillCam.instance.playing:
		KillCam.instance.note_node(body)


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


# --- scars ----------------------------------------------------------------------------------

const SCAR_CLOTH := Color(0.93, 0.9, 0.82)
const SCAR_STAIN := Color(0.62, 0.12, 0.1)
const SCAR_TWIG := Color(0.45, 0.31, 0.18)
const SCAR_PATCH := Color(0.08, 0.07, 0.07)


## The scars a bot came back with (RivalBook.SCARS): an eye patch on a strap,
## bandages round an arm, a twig splint on a leg, sooty singed fur. On the
## bones, so they move (and fly off) with the limb.
func add_scars(scars: Array) -> void:
	for scar in scars:
		match String(scar):
			"eye_patch":
				_eye_patch()
			"arm_l", "arm_r":
				for part in ["upper_arm", "lower_arm"]:
					_bandage(StringName("%s_%s" % [String(scar).right(1), part]))
			"leg_l", "leg_r":
				_splint(StringName("%s_lower_leg" % String(scar).right(1)))
			"singed":
				singed = true
				_singe()


## [attachment, start, end, radius] of a body segment, in the attachment's frame.
func _scar_part(role: StringName) -> Array:
	var att: Node3D = attachments.get(role)
	if att == null or not rig.segments.has(role):
		return []
	var seg: Dictionary = rig.segments[role]
	var inv: Transform3D = (rig.rest[role] as Transform3D).affine_inverse()
	return [att, inv * (seg["start"] as Vector3), inv * (seg["end"] as Vector3), float(seg["radius"])]


func _scar_mesh(mesh: PrimitiveMesh, c: Color, parent: Node3D, xf: Transform3D) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = c
	mat.roughness = 0.9
	mesh.material = mat
	var mi := MeshInstance3D.new()
	mi.name = "Scar"
	mi.set_meta(&"scar", true)
	mi.mesh = mesh
	mi.layers = RENDER_LAYER
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.transform = xf
	parent.add_child(mi)


## Soot over its fur: each of its materials (its skin's) with the singed
## pass after it, multiplied on top.
func _singe() -> void:
	if _soot == null:
		_soot = ShaderMaterial.new()
		_soot.shader = SINGED_SHADER
	for m in meshes:
		for s in m.mesh.get_surface_count():
			var mat := m.get_surface_override_material(s) as BaseMaterial3D
			if mat == null:
				mat = m.mesh.surface_get_material(s) as BaseMaterial3D
			if mat == null or mat.next_pass == _soot:
				continue
			var copy := mat.duplicate() as BaseMaterial3D
			copy.next_pass = _soot
			m.set_surface_override_material(s, copy)


func _bandage(role: StringName) -> void:
	var p := _scar_part(role)
	if p.is_empty():
		return
	var a: Vector3 = p[1]
	var b: Vector3 = p[2]
	var r: float = p[3]
	var along := _capsule_xform(a, b)
	var wrap := CylinderMesh.new()
	wrap.top_radius = r * 1.3
	wrap.bottom_radius = r * 1.3
	wrap.height = a.distance_to(b) * 0.45
	wrap.radial_segments = 12
	wrap.rings = 1
	_scar_mesh(wrap, SCAR_CLOTH, p[0], along)
	var stain := SphereMesh.new()
	stain.radius = r * 0.42
	stain.height = r * 0.4
	stain.radial_segments = 10
	stain.rings = 5
	_scar_mesh(stain, SCAR_STAIN, p[0], Transform3D(along.basis, along.origin + along.basis.x.normalized() * r * 1.18))


func _splint(role: StringName) -> void:
	var p := _scar_part(role)
	if p.is_empty():
		return
	var a: Vector3 = p[1]
	var b: Vector3 = p[2]
	var r: float = p[3]
	var along := _capsule_xform(a, b)
	for side in [-1.0, 1.0]:
		var twig := CylinderMesh.new()
		twig.top_radius = r * 0.2
		twig.bottom_radius = r * 0.25
		twig.height = a.distance_to(b)
		twig.radial_segments = 6
		twig.rings = 1
		_scar_mesh(twig, SCAR_TWIG, p[0], Transform3D(along.basis, along.origin + along.basis.x.normalized() * r * 1.25 * side))
	for t in [0.3, 0.72]:
		var twine := CylinderMesh.new()
		twine.top_radius = r * 1.5
		twine.bottom_radius = r * 1.5
		twine.height = r * 0.45
		twine.radial_segments = 10
		twine.rings = 1
		_scar_mesh(twine, SCAR_CLOTH, p[0], Transform3D(along.basis, a.lerp(b, t)))


func _eye_patch() -> void:
	var p := _scar_part(&"head")
	if p.is_empty():
		return
	var r: float = p[3]
	var seg: Dictionary = rig.segments[&"head"]
	var c: Vector3 = ((seg["start"] as Vector3) + (seg["end"] as Vector3)) * 0.5
	var inv: Transform3D = (rig.rest[&"head"] as Transform3D).affine_inverse()
	# models face +Z in skeleton space; the patch goes over the eye on the left
	# arm's side, on the face itself (found in the mesh: heads aren't round)
	var side := signf((rig.rest[&"l_upper_arm"] as Transform3D).origin.x) if rig.rest.has(&"l_upper_arm") else 1.0
	var eye := _face_point(c.x + side * r * 0.42, rig.eye_height, r)
	if eye == Vector3.INF:
		eye = Vector3(c.x + side * r * 0.42, rig.eye_height, c.z + r * 0.9)
	var patch := SphereMesh.new()
	patch.radius = r * 0.3
	patch.height = r * 0.16
	patch.radial_segments = 14
	patch.rings = 6
	_scar_mesh(patch, SCAR_PATCH, p[0], inv * Transform3D(Basis(Vector3.RIGHT, PI / 2.0), eye + Vector3(0, 0, r * 0.04)))


## The front of the model's surface at (x, y) in skeleton space (the most
## forward vertex near there), or INF if the mesh has nothing there.
func _face_point(x: float, y: float, r: float) -> Vector3:
	var best := Vector3.INF
	for m in meshes:
		if m.mesh == null:
			continue
		var xf := skeleton.global_transform.affine_inverse() * m.global_transform
		for si in m.mesh.get_surface_count():
			var verts: PackedVector3Array = m.mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX]
			for v in verts:
				var q := xf * v
				if absf(q.y - y) < r * 0.18 and absf(q.x - x) < r * 0.2 and (best == Vector3.INF or q.z > best.z):
					best = q
	return best


func _is_ancestor(ancestor: int, idx: int) -> bool:
	var i := idx
	while i >= 0:
		if i == ancestor:
			return true
		i = skeleton.get_bone_parent(i)
	return false
