class_name Boss
extends Node3D
## A boss: ten critters tall, alone against everyone in a Boss Battle
## (MatchManager.mode "boss"). Brutus on the island (BruteBoss), the Tin
## Tyrant in the Toy Box (RobotBoss), Nibbles in the Hamster Cage
## (HamsterBoss).
##
## Its model comes from assets/bosses/<id>/ (tools/characters/boss_build.py),
## posed by code (BossPoser). Hitboxes ride its bones like a critter's (the
## carrots call receive_shot), a solid body keeps critters from walking
## through it, and it does what its subclass picks (BossAction): a red ring
## where a blow is about to land (danger: the bots get out of it), then the
## blow. Below half health it's enraged: faster, and harder. Carrots from bots
## count for BOT_DAMAGE of yours, so you matter.

signal health_changed(health: float, max_health: float)
signal enraged_now
signal died(by: Node)

enum State { WAITING, ARRIVING, FIGHTING, DEAD }

const HEIGHT := 25.0                ## the top of its skull, in metres: ten critters tall
const BOT_DAMAGE := 0.12            ## bots' hits on it count this much (yours in full)
const ENRAGE_AT := 0.5              ## share of its health left when it's enraged
const RETARGET_EVERY := 2.5
const DIFFICULTY_HEALTH := [0.7, 1.0, 1.35]   ## Sleepy, Scrappy, Savage
const DIFFICULTY_DAMAGE := [0.65, 1.0, 1.25]
const VULNERABLE := 2.0             ## hits count this many times while it's stunned
const LIMBS := [&"l_upper_arm", &"l_lower_arm", &"l_hand", &"r_upper_arm", &"r_lower_arm", &"r_hand",
	&"l_upper_leg", &"l_lower_leg", &"l_foot", &"r_upper_leg", &"r_lower_leg", &"r_foot",
	&"l_ear", &"l_ear_tip", &"r_ear", &"r_ear_tip", &"tail", &"l_shoulder", &"r_shoulder"]

var id := ""
var display_name := ""
var title := ""                     ## its billing on the health bar
var land_time := 2.2                ## seconds into its entrance it lands (or bursts out): BossIntro
var from_below := false             ## it bursts up out of the ground instead of dropping in (BossIntro)
var base_health := 30000.0
var max_health := 30000.0
var health := 30000.0
var alive := true
var state := State.WAITING
var team := 2                       ## (everyone else is on Critter.team 1)
var enraged := false
var vulnerable_until := -1.0        ## stunned or wound down: it takes vulnerable_k times as much
var vulnerable_k := VULNERABLE
var moves_used: Dictionary = {}     ## how often it's done each thing (tests, tuning)
var damage_done := 0.0              ## all it's dealt out to critters
var kills := 0
var damage_scale := 1.0             ## its blows, by difficulty
var walk_speed := 9.0
var turn_speed := 1.4               ## radians a second
var armor := 1.0                    ## hits on it count this much (the Tin Tyrant's tin plate)
var weak_spots := {&"head": 2.0}    ## role -> how much more a hit there counts
var limb_scale := 0.75              ## arms, legs, ears and tails: hits there count this much
var blood := FX.BLOOD
var solid_roles: Array = [&"hips", &"spine", &"chest", &"l_upper_leg", &"l_lower_leg", &"r_upper_leg", &"r_lower_leg"]
var match_manager: Node
var target: Critter
var data: Dictionary = {}
var size := 1.0                     ## metres per model unit
var model: Node3D
var skeleton: Skeleton3D
var poser := BossPoser.new()
var action: BossAction
var danger: Array = []              ## [[centre, radius, until, since]]: where its blows are about to land
var last_hit_pos := Vector3.ZERO
var hitboxes: Dictionary = {}       ## role -> Area3D
var hitbox_rids: Array[RID] = []
var gore_ok := true                 ## (Settings.gore: off spares the bots' heads)
var thinking := true                ## off: it only does what it's told (captures, tests)
var _anchors: Dictionary = {}       # role -> Node3D on its bone (hitboxes and stuck carrots ride it)
var _solids: Array = []             # [AnimatableBody3D, role]
var _ready_at: Dictionary = {}      # ability -> clock when it can be used again
var _clock := 0.0
var arrived_at := -1.0              ## (its clock when it turned up: fight_time())
var _quiet_until := -1.0            # (its roar for the camera hurts nobody: show_off)
var _retarget_t := 0.0
var _gait := 0.0
var _speed := 0.0
var _path := PackedVector3Array()
var _path_i := 0
var _repath_t := 0.0
var _threat: Dictionary = {}        # Critter -> damage it did to us lately
var _look := Vector3.INF
var _step := 0
var _eyes: Array[MeshInstance3D] = []
var _eye_mat: StandardMaterial3D
var _built := false


func _init() -> void:
	name = "Boss"


func _ready() -> void:
	add_to_group(&"bosses")
	gore_ok = Settings.gore != Settings.Gore.OFF
	_build()
	visible = state != State.WAITING
	_set_hittable(state == State.FIGHTING)


## Its difficulty (MatchManager's): health and how hard it hits.
func setup(mm: Node, difficulty := 1) -> void:
	match_manager = mm
	var d := clampi(difficulty, 0, 2)
	max_health = base_health * DIFFICULTY_HEALTH[d]
	health = max_health
	damage_scale = DIFFICULTY_DAMAGE[d]


# ---- the model -----------------------------------------------------------------------------

func _build() -> void:
	if _built:
		return
	_built = true
	data = RigInfo.read_json("res://assets/bosses/%s/%s.boss.json" % [id, id])
	size = HEIGHT / float(data.get("head_top", 1.0))
	model = ModelUtil.instantiate("res://assets/bosses/%s/%s.glb" % [id, id])
	if model == null:
		push_error("boss %s: no model" % id)
		model = Node3D.new()
	model.name = "Model"
	model.scale = Vector3.ONE * size
	model.rotation.y = PI   # (it's modelled facing +Z; a Node3D's front is -Z)
	add_child(model)
	for gi in ModelUtil.find_all(model, "GeometryInstance3D"):
		(gi as GeometryInstance3D).layers = CritterVisual.RENDER_LAYER   # (no blood decals on it)
	skeleton = ModelUtil.find_first(model, "Skeleton3D") as Skeleton3D
	if skeleton:
		poser.bind(skeleton, data.get("bones", {}), data.get("tails", {}))
		poser.apply()
	_build_eyes()
	_build_hitboxes()
	_dress()


## Anything a boss adds to its model (BruteBoss: nothing; the Tin Tyrant's
## glowing eyes are its own...).
func _dress() -> void:
	pass


## Glowing eyes (red when it's enraged), from the boss.json's eye positions.
func _build_eyes() -> void:
	var eyes: Array = data.get("eyes", [])
	if eyes.is_empty() or skeleton == null:
		return
	_eye_mat = StandardMaterial3D.new()
	_eye_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_eye_mat.albedo_color = eye_color(false)
	_eye_mat.emission_enabled = true
	_eye_mat.emission = eye_color(false)
	_eye_mat.emission_energy_multiplier = 2.5
	var sm := SphereMesh.new()
	var r := float(data.get("eye_r", 0.02))
	sm.radius = r
	sm.height = r * 2.0
	var head: int = poser.bones.get(&"head", -1)
	for e in eyes:
		var p := Vector3(e[0], e[1], e[2])
		var att := BoneAttachment3D.new()
		att.bone_idx = head
		skeleton.add_child(att)
		var mi := MeshInstance3D.new()
		mi.mesh = sm
		mi.material_override = _eye_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.layers = CritterVisual.RENDER_LAYER
		att.add_child(mi)
		# (the attachment sits on the head bone: the eye where the model has it)
		mi.position = (skeleton.get_bone_global_rest(head).affine_inverse() * p) if head >= 0 else p
		_eyes.append(mi)


## Its eyes' glow: calm, and enraged.
func eye_color(angry: bool) -> Color:
	return Color(1.0, 0.1, 0.05) if angry else Color(1.0, 0.55, 0.15)


func _build_hitboxes() -> void:
	var radii: Dictionary = data.get("radii", {})
	for r in radii:
		var role := StringName(r)
		if not poser.has(role):
			continue
		var anchor := Node3D.new()
		anchor.name = "Bone_" + role
		add_child(anchor)
		anchor.top_level = true
		_anchors[role] = anchor
		var radius := float(radii[r]) * size * 1.15
		var length := (poser.bone_tip(role) - poser.bone_pose(role).origin).length() * size
		var area := Area3D.new()
		area.name = "Hit_" + role
		area.collision_layer = Layers.HITBOXES
		area.collision_mask = 0
		area.monitoring = false
		area.monitorable = false
		area.set_meta(&"critter", self)
		area.set_meta(&"role", role)
		var cs := CollisionShape3D.new()
		var cap := CapsuleShape3D.new()
		cap.radius = radius
		cap.height = maxf(length + radius * 2.0, radius * 2.0 + 0.01)
		cs.shape = cap
		area.add_child(cs)
		anchor.add_child(area)
		hitboxes[role] = area
		hitbox_rids.append(area.get_rid())
		if role in solid_roles:
			# a body critters can't walk through (they're pushed out of it)
			var body := AnimatableBody3D.new()
			body.name = "Solid_" + role
			body.sync_to_physics = false
			body.collision_layer = Layers.CRITTERS
			body.collision_mask = 0
			var bcs := CollisionShape3D.new()
			var bcap := CapsuleShape3D.new()
			bcap.radius = radius * 0.8
			bcap.height = maxf(length + bcap.radius * 2.0, bcap.radius * 2.0 + 0.01)
			bcs.shape = bcap
			body.add_child(bcs)
			anchor.add_child(body)
			_solids.append(body)
	_update_bones()


## Hitboxes and the solid body follow the bones (each capsule from a bone's
## head to its tip).
func _update_bones() -> void:
	if skeleton == null:
		return
	var sk := skeleton.global_transform
	for role in _anchors:
		var a: Vector3 = sk * poser.bone_pose(role).origin
		var b: Vector3 = sk * poser.bone_tip(role)
		var y := b - a
		var l := y.length()
		var basis := Basis.IDENTITY
		if l > 1e-4:
			y /= l
			var x := y.cross(Vector3.UP if absf(y.y) < 0.95 else Vector3.RIGHT).normalized()
			basis = Basis(x, y, x.cross(y))
		(_anchors[role] as Node3D).global_transform = Transform3D(basis, (a + b) * 0.5)


func _set_hittable(on: bool) -> void:
	for area in hitboxes.values():
		(area as Area3D).collision_layer = Layers.HITBOXES if on else 0
	for body in _solids:
		(body as CollisionObject3D).collision_layer = Layers.CRITTERS if on else 0


## A world point on `role`'s bone (`along`: 0 its head … 1 its tip).
func bone_point(role: StringName, along := 0.0) -> Vector3:
	if skeleton == null or not poser.has(role):
		return global_position + Vector3.UP * HEIGHT * 0.5
	var a := poser.bone_pose(role).origin
	return skeleton.global_transform * a.lerp(poser.bone_tip(role), along)


## Model point (the boss.json's eyes, mouth) -> world, as the boss stands now.
func model_point(p: Vector3) -> Vector3:
	return model.global_transform * p if model else global_position


func get_eye_position() -> Vector3:
	return bone_point(&"head", 0.6)


func get_chest_position() -> Vector3:
	return bone_point(&"chest", 0.5) if poser.has(&"chest") else global_position + Vector3.UP * HEIGHT * 0.5


## A point on its head (the boss.json's eyes, mouth: model units, as it was
## modelled) where it is now, head turned and all.
func head_point(p: Vector3) -> Vector3:
	if skeleton == null or not poser.has(&"head"):
		return global_position + Vector3.UP * HEIGHT
	var head := poser.bone_pose(&"head")
	var rest := skeleton.get_bone_global_rest(poser.bones[&"head"])
	return skeleton.global_transform * (head * (rest.affine_inverse() * p))


## Where its mouth is (where a roar comes from, foam drips, a bite lands).
func mouth_position() -> Vector3:
	var m: Variant = data.get("mouth")
	return head_point(Vector3(m[0], m[1], m[2])) if m is Array else get_eye_position()


## Where its eyes are now.
func eye_positions() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for e in data.get("eyes", []):
		out.append(head_point(Vector3(e[0], e[1], e[2])))
	return out


func forward() -> Vector3:
	return -global_basis.z


# ---- the match -----------------------------------------------------------------------------

## It turns up at `at` (MatchManager, once everyone's had time to find a gun),
## facing `look` if there's one to face (you: you get a good look at it).
func arrive(at: Vector3, look := Vector3.INF) -> void:
	global_position = at
	if look != Vector3.INF and Vector2(look.x - at.x, look.z - at.z).length() > 0.5:
		rotation.y = atan2(-(look.x - at.x), -(look.z - at.z))
	arrived_at = _clock
	state = State.ARRIVING
	visible = true
	_set_hittable(true)
	action = _entrance()
	if action == null:
		state = State.FIGHTING


## How it turns up (a subclass's: dropping out of the sky, bursting out of the bedding...).
func _entrance() -> BossAction:
	return null


func _physics_process(delta: float) -> void:
	if state == State.WAITING:
		return
	_clock += delta
	danger = danger.filter(func(d): return float(d[2]) > _clock)
	for c in _threat.keys():
		_threat[c] = float(_threat[c]) * exp(-delta * 0.15)
		if not is_instance_valid(c) or not (c as Critter).alive or float(_threat[c]) < 1.0:
			_threat.erase(c)
	if action:
		var a := action
		if not a.step(delta):
			if action == a:   # (unless it started something else meanwhile: a crash's stun)
				action = null
			_action_done(a)
	elif state == State.FIGHTING and thinking:
		_fight(delta)
	_animate(delta)
	_update_bones()


## Between blows: who it's after, what it does next, or walking at them.
func _fight(delta: float) -> void:
	_retarget_t -= delta
	if target == null or not is_instance_valid(target) or not target.alive or _retarget_t <= 0.0:
		_retarget_t = RETARGET_EVERY
		target = _pick_target()
	if target == null:
		_speed = 0.0
		return
	var next := _choose(target)
	if next:
		start(next)
		return
	_walk_to(target.global_position, delta)


## What it does now to `t` (a subclass picks an ability, or null to keep walking).
func _choose(_t: Critter) -> BossAction:
	return null


func _action_done(a: BossAction) -> void:
	if a.name == &"death":
		# down for good: it keeps the last pose of its fall, and stops
		poser.clear()
		poser.add_pose(a.keys.back()[1] if not a.keys.is_empty() else {})
		poser.apply()
		_update_bones()
		set_physics_process(false)
		_fallen()
		return
	if state == State.ARRIVING:
		state = State.FIGHTING
		_after_entrance()


## Down for good (a subclass's last flourish: a gore burst, a puff of steam).
func _fallen() -> void:
	pass


func _after_entrance() -> void:
	pass


func start(a: BossAction) -> void:
	action = a
	moves_used[a.name] = int(moves_used.get(a.name, 0)) + 1


## Who it goes for: whoever's nearest, you a bit sooner, and anyone hurting
## it a lot sooner still.
func _pick_target() -> Critter:
	var best: Critter = null
	var best_score := INF
	for c in foes():
		var d := c.global_position.distance_to(global_position)
		var score := d * (0.75 if c.is_player else 1.0) / (1.0 + float(_threat.get(c, 0.0)) / 400.0)
		if score < best_score:
			best_score = score
			best = c
	return best


## Everyone it's fighting: critters on the ground (or in the air) not on its team.
func foes() -> Array[Critter]:
	var out: Array[Critter] = []
	for n in get_tree().get_nodes_in_group(&"critters"):
		var c := n as Critter
		if c and c.alive and c.team != team and c.state != Critter.State.IN_DROPSHIP and c.state != Critter.State.DEAD:
			out.append(c)
	return out


func foes_near(p: Vector3, radius: float) -> Array[Critter]:
	var out: Array[Critter] = []
	for c in foes():
		if Vector2(c.global_position.x - p.x, c.global_position.z - p.z).length() <= radius:
			out.append(c)
	return out


func is_ready(ability: StringName) -> bool:
	return _clock >= float(_ready_at.get(ability, 0.0))


## `ability` can't be used again for `seconds` (less when it's enraged).
func cooldown(ability: StringName, seconds: float) -> void:
	_ready_at[ability] = _clock + seconds * (0.7 if enraged else 1.0)


# ---- moving ----------------------------------------------------------------------------------

## Walk toward `goal` along the navmesh (the critters' paths: it cuts the
## corners), turning as it goes, its feet on the ground.
func _walk_to(goal: Vector3, delta: float, speed_k := 1.0) -> void:
	if _clock >= _repath_t or _path.is_empty():
		_repath_t = _clock + 1.0
		_path_i = 0
		_path = PackedVector3Array()
		if is_inside_tree():
			var map := get_world_3d().navigation_map
			_path = Island.find_path(map, NavigationServer3D.map_get_closest_point(map, global_position),
				NavigationServer3D.map_get_closest_point(map, goal))
	var wp := goal
	while _path_i < _path.size():
		var p := _path[_path_i]
		if Vector2(p.x - global_position.x, p.z - global_position.z).length() > 8.0 or _path_i == _path.size() - 1:
			wp = p
			break
		_path_i += 1
	var to := wp - global_position
	to.y = 0.0
	if to.length() < 1.0:
		_speed = move_toward(_speed, 0.0, delta * 20.0)
		return
	face_toward(wp, delta)
	var along := maxf(forward().dot(to.normalized()), 0.15)
	var want := walk_speed * speed_k * (1.3 if enraged else 1.0) * along
	_speed = move_toward(_speed, want, delta * 12.0)
	move_by(forward() * _speed * delta)


## Turn toward `p` (at most turn_speed a second, or `rate`).
func face_toward(p: Vector3, delta: float, rate := -1.0) -> void:
	var to := p - global_position
	if Vector2(to.x, to.z).length() < 0.01:
		return
	var want := atan2(-to.x, -to.z)
	var step := (rate if rate > 0.0 else turn_speed) * delta
	rotation.y += clampf(wrapf(want - rotation.y, -PI, PI), -step, step)


## Move by `d` across the ground (its feet stay on it).
func move_by(d: Vector3) -> void:
	var p := global_position + Vector3(d.x, 0.0, d.z)
	p.y = lerpf(global_position.y, ground_y(p), 0.25)
	global_position = p


## The ground under `p` (props and buildings aside: it stomps through those).
func ground_y(p: Vector3) -> float:
	var isl: Island = match_manager.island if match_manager and "island" in match_manager else null
	if isl and isl.terrain:
		return isl.terrain.height_at(p.x, p.z)
	if is_inside_tree():
		var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, p.y + 30.0, p.z), Vector3(p.x, p.y - 60.0, p.z), Layers.WORLD)
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		if hit:
			return (hit.position as Vector3).y
	return p.y


# ---- animating ----------------------------------------------------------------------------

func _animate(delta: float) -> void:
	if skeleton == null or (state == State.DEAD and action == null):
		return
	poser.clear()
	var moving := clampf(_speed / maxf(walk_speed, 0.1), 0.0, 1.6)
	_gait += delta * _speed / maxf(stride() * size, 0.1) * PI
	var step := int(floor(_gait / PI))
	if step != _step:
		_step = step
		if _speed > 1.5 and state != State.WAITING:
			_footstep()
	var w := 1.0 - (action.weight() if action else 0.0)
	poser.add_pose(walk_pose(_gait, moving), w)
	poser.add_pose(idle_pose(_clock), 1.0)
	_look_at_target(delta, w)
	if action:
		poser.add_pose(action.pose(), action.weight())
	poser.apply()
	if _eye_mat:
		var c := eye_color(enraged)
		_eye_mat.albedo_color = c
		_eye_mat.emission = c
		_eye_mat.emission_energy_multiplier = (4.0 if enraged else 2.5) * (0.8 + 0.2 * sin(_clock * 6.0))


## How far a step takes it (model units).
func stride() -> float:
	return 0.18


## A foot coming down: a thud you hear across the map, the ground shaking
## right by it (CameraRig: Events.explosion).
func _footstep() -> void:
	Audio.play_at(step_sound(), global_position, -6.0, 0.1, {"max_distance": 320.0, "unit_size": 20.0})
	Events.explosion.emit(global_position, 4.0)


func step_sound() -> StringName:
	return &"boss_stomp"


## Its walk at `phase` (radians), `amount` 0 standing … 1 walking flat out.
## A heavy biped's by default: legs swinging, arms swinging back, a bob.
func walk_pose(phase: float, amount: float) -> Dictionary:
	var s := sin(phase)
	var c := cos(phase)
	return {
		&"l_upper_leg": Vector3(-28.0 * s * amount, 0, 0), &"r_upper_leg": Vector3(28.0 * s * amount, 0, 0),
		&"l_lower_leg": Vector3(maxf(0.0, c) * 30.0 * amount, 0, 0), &"r_lower_leg": Vector3(maxf(0.0, -c) * 30.0 * amount, 0, 0),
		&"l_upper_arm": Vector3(22.0 * s * amount, 0, 0), &"r_upper_arm": Vector3(-22.0 * s * amount, 0, 0),
		&"spine": Vector3(4.0 * amount, 6.0 * s * amount, 0), &"chest": Vector3(0, -5.0 * s * amount, 0),
		&"root": Vector3(0, -absf(c) * 0.012 * amount, 0),
	}


## Breathing and the like, always (on top of everything).
func idle_pose(t: float) -> Dictionary:
	var b := sin(t * 1.7)
	return {&"chest": Vector3(2.0 * b, 0, 0), &"head": Vector3(-1.5 * b, 0, 0)}


## Turn its head toward its target (not while it's busy, mostly).
func _look_at_target(delta: float, w: float) -> void:
	if target == null or not is_instance_valid(target) or not poser.has(&"head"):
		return
	var want := target.get_eye_position()
	_look = want if _look == Vector3.INF else _look.lerp(want, IKMath.damp(4.0, delta))
	var local := global_transform.affine_inverse() * _look
	var yaw := clampf(rad_to_deg(atan2(-local.x, -local.z)), -50.0, 50.0)
	var head_h := (get_eye_position() - global_position).y
	var pitch := clampf(rad_to_deg(atan2(local.y - head_h, Vector2(local.x, local.z).length())), -40.0, 20.0)
	# (about its left axis, a turn tips the head down: looking up is the other way)
	poser.add(&"neck", Vector3(-pitch * 0.4, yaw * 0.4, 0), w)
	poser.add(&"head", Vector3(-pitch * 0.6, yaw * 0.6, 0), w)


# ---- getting hurt --------------------------------------------------------------------------

## A carrot hit one of its hitboxes (Projectiles, as on a critter).
func receive_shot(shooter: Node, data_: WeaponData, dmg: float, pos: Vector3, dir: Vector3, role: StringName, _mutated := false) -> void:
	var info := DamageInfo.make(dmg, DamageInfo.Kind.BULLET, shooter, data_.id)
	info.position = pos
	info.direction = dir
	info.bone_role = role
	info.impulse = data_.impulse
	take_damage(info)


## A carrot hit it after it went down: a little dust off the carcass.
func receive_corpse_shot(_data: WeaponData, pos: Vector3, dir: Vector3, _body: Object) -> void:
	FX.blood_hit(pos, -dir, 0.3, blood)


## A club: struck on whatever bit was nearest (Critter._melee_strike).
func receive_melee(attacker: Critter, amount: float, pos: Vector3, dir: Vector3, role: StringName) -> void:
	var info := DamageInfo.make(amount, DamageInfo.Kind.MELEE, attacker, &"melee")
	info.position = pos
	info.direction = dir
	info.bone_role = role
	take_damage(info)


## A blast `radius` across at `pos` (Explosion): it takes the splash where
## the blast meets its nearest bone, more the closer.
func receive_blast(pos: Vector3, radius: float, damage: float, shooter: Node, weapon_id: StringName) -> void:
	var near := INF
	var near_role := &"chest"
	for role in _anchors:
		var a := bone_point(role, 0.0)
		var b := bone_point(role, 1.0)
		var q := Geometry3D.get_closest_point_to_segment(pos, a, b)
		var d := maxf(0.0, q.distance_to(pos) - float(data.get("radii", {}).get(String(role), 0.05)) * size)
		if d < near:
			near = d
			near_role = role
	if near > radius:
		return
	var info := DamageInfo.make(damage * pow(1.0 - near / radius, 0.8), DamageInfo.Kind.EXPLOSION, shooter, weapon_id)
	info.position = pos
	info.direction = (get_chest_position() - pos).normalized()
	info.bone_role = near_role
	take_damage(info)


## How much a hit on `role` counts.
func role_scale(role: StringName) -> float:
	if weak_spots.has(role):
		return float(weak_spots[role])
	return limb_scale if role in LIMBS else 1.0


func take_damage(info: DamageInfo) -> void:
	if not alive or state == State.WAITING:
		return
	var by := info.attacker as Critter
	if by and by.team == team:
		return
	var amount := info.amount * armor
	if info.kind != DamageInfo.Kind.EXPLOSION and info.kind != DamageInfo.Kind.BLEED:
		amount *= role_scale(info.bone_role)
		info.headshot = weak_spots.has(info.bone_role)
	if _clock < vulnerable_until:
		amount *= vulnerable_k
	if by and not by.is_player:
		amount *= BOT_DAMAGE
	info.amount = amount
	var before := health
	health = maxf(0.0, health - amount)
	last_hit_pos = info.position if info.position != Vector3.ZERO else get_chest_position()
	if by:
		_threat[by] = float(_threat.get(by, 0.0)) + amount * (2.0 if by.is_player else 1.0)
		by.damage_dealt += amount
	_hit_fx(info)
	if by and by.is_player:
		Events.player_hit_confirmed.emit(self, amount, info.headshot, health <= 0.0)
		StatBook.note_hit(info.weapon_id, amount, info.headshot, info.kind == DamageInfo.Kind.EXPLOSION)
		StatBook.note_boss_damage(id, before - health)
	health_changed.emit(health, max_health)
	if not enraged and health <= max_health * ENRAGE_AT and health > 0.0:
		_enrage()
	if health <= 0.0:
		_die(info)


func _hit_fx(info: DamageInfo) -> void:
	FX.blood_hit(last_hit_pos, -info.direction, clampf(info.amount / 30.0, 0.3, 1.0), blood)


## Below ENRAGE_AT: it's had enough. Faster, harder, eyes red.
func _enrage() -> void:
	enraged = true
	enraged_now.emit()
	Events.announce.emit("%s IS ENRAGED!" % display_name.to_upper(), enrage_line())
	var roar := _roar_action()
	if roar and (action == null or action.interruptible):
		_cancel_action()
		start(roar)


func enrage_line() -> String:
	return "Faster, and hitting harder. Keep your distance."


## Its roar (enraged): a subclass's.
func _roar_action() -> BossAction:
	return null


func _cancel_action() -> void:
	if action and action.data.has("cancel"):
		(action.data.cancel as Callable).call()
	action = null


## Stunned (crashed into a wall, wound down...) for `seconds`: it stands
## there, and takes VULNERABLE times as much.
func stun(seconds: float, pose: Dictionary = {}, k := VULNERABLE) -> void:
	_cancel_action()
	vulnerable_until = _clock + seconds
	vulnerable_k = k
	var a := BossAction.new(&"stunned", seconds)
	a.key(0.0, pose).key(seconds, pose)
	start(a)
	Events.headline.emit("%s is stunned: hit it now!" % display_name)


func vulnerable() -> bool:
	return alive and _clock < vulnerable_until


## Seconds since a danger zone (`danger`) went up.
func seen_for(d: Array) -> float:
	return _clock - float(d[3]) if d.size() > 3 else 99.0


## Seconds until a danger zone's blow lands.
func lands_in(d: Array) -> float:
	return float(d[2]) - 0.2 - _clock


## Seconds since it turned up (0 before it has).
func fight_time() -> float:
	return _clock - arrived_at if arrived_at >= 0.0 else 0.0


## Its roar for the camera as it arrives (BossIntro): the pose and the noise,
## hurting nobody. False if it's busy (Brutus roaring at a crowd for real).
func show_off() -> bool:
	if not alive or action:
		return false
	var a := _roar_action()
	if a == null:
		return false
	_quiet_until = _clock + a.length
	start(a)
	return true


func _die(info: DamageInfo) -> void:
	alive = false
	state = State.DEAD
	_cancel_action()
	danger.clear()
	_set_hittable(false)
	_speed = 0.0
	died.emit(info.attacker)
	action = _death_action()


## How it goes down (a subclass's; by default it topples forward).
func _death_action() -> BossAction:
	var a := BossAction.new(&"death", 3.0)
	a.blend_out = 0.0
	a.interruptible = false
	a.key(0.0, {}).key(1.2, {&"spine": Vector3(30, 0, 0), &"l_upper_leg": Vector3(-40, 0, 0), &"r_upper_leg": Vector3(-40, 0, 0),
		&"l_lower_leg": Vector3(70, 0, 0), &"r_lower_leg": Vector3(70, 0, 0), &"root": Vector3(0, -0.12, 0)})
	a.key(2.6, {&"spine": Vector3(70, 0, 0), &"chest": Vector3(20, 0, 0), &"l_upper_leg": Vector3(-80, 0, 0), &"r_upper_leg": Vector3(-80, 0, 0),
		&"l_lower_leg": Vector3(120, 0, 0), &"r_lower_leg": Vector3(120, 0, 0), &"root": Vector3(0, -0.3, 0.05)})
	a.on(2.5, func():
		BossFX.shockwave(global_position + forward() * HEIGHT * 0.4, HEIGHT * 1.2)
		Audio.play_at(&"explosion", global_position, 6.0, 0.05, {"max_distance": 600.0, "unit_size": 40.0}))
	a.length = 2.7
	return a


# ---- hurting critters ------------------------------------------------------------------------

## A red ring where a blow will land in `seconds` (the bots get out of it).
func warn(pos: Vector3, radius: float, seconds: float) -> void:
	BossFX.warn_circle(pos, radius, seconds)
	danger.append([pos, radius, _clock + seconds + 0.2, _clock])


func warn_strip(from: Vector3, to: Vector3, width: float, seconds: float) -> void:
	BossFX.warn_strip(from, to, width, seconds)
	var d := to - from
	var n := maxi(1, int(d.length() / width))
	for i in n + 1:   # (as a row of circles, for the bots)
		danger.append([from + d * (float(i) / n), width * 0.75, _clock + seconds + 0.6, _clock])


## Everyone in `radius` of `centre` takes `inner` damage at the middle down
## to `outer` at the edge, thrown out and up (`push`, `lift`, m/s). Anyone in
## the air when it lands (`jump_clear`) is spared. Returns who it hit.
func hurt_ring(centre: Vector3, radius: float, inner: float, outer: float, push: float, lift: float, what: StringName,
		jump_clear := true) -> Array[Critter]:
	var hit: Array[Critter] = []
	if _clock < _quiet_until:
		return hit
	for c in foes_near(centre, radius):
		if jump_clear and not c.is_on_floor() and c.global_position.y > ground_y(c.global_position) + 1.2:
			continue
		var off := c.global_position - centre
		off.y = 0.0
		var k := clampf(off.length() / radius, 0.0, 1.0)
		var dir := off.normalized() if off.length() > 0.1 else forward()
		hurt(c, lerpf(inner, outer, k), dir, push * (1.0 - 0.5 * k), lift * (1.0 - 0.4 * k), what)
		hit.append(c)
	return hit


## One critter takes `amount` (times its difficulty), thrown along `dir`.
func hurt(c: Critter, amount: float, dir: Vector3, push: float, lift: float, what: StringName,
		kind := DamageInfo.Kind.EXPLOSION, dismember := 0.6) -> void:
	if c == null or not c.alive:
		return
	var info := DamageInfo.make(amount * damage_scale, kind, self, what)
	info.position = c.get_chest_position()
	info.direction = (dir + Vector3.UP * 0.6).normalized()
	info.impulse = 8.0 + push
	info.dismember_power = dismember
	info.bone_role = &"chest"
	var was_alive := c.alive
	var hp := c.health + c.armor
	c.take_damage(info)
	damage_done += maxf(0.0, hp - (c.health + c.armor))
	if c.alive:
		c.velocity += Vector3(dir.x, 0.0, dir.z) * push + Vector3.UP * lift
	elif was_alive:
		kills += 1


## A boss's own name for what it hurt you with (the kill feed).
func attack_name(what: StringName) -> String:
	return String(what).capitalize()


# ---- rewind (TimeKeeper) ---------------------------------------------------------------------

func snapshot() -> Dictionary:
	var ready := {}
	for k in _ready_at:
		ready[k] = float(_ready_at[k]) - _clock
	return {"xf": global_transform, "hp": health, "enraged": enraged, "ready": ready, "state": state,
		"vulnerable": vulnerable_until - _clock}


func restore(s: Dictionary) -> void:
	if not alive:
		return
	_cancel_action()
	danger.clear()
	global_transform = s.xf
	health = s.hp
	enraged = s.enraged
	state = s.state
	vulnerable_until = _clock + float(s.get("vulnerable", -1.0))
	_ready_at.clear()
	for k in s.ready:
		_ready_at[k] = _clock + float(s.ready[k])
	visible = state != State.WAITING
	_set_hittable(state != State.WAITING)
	health_changed.emit(health, max_health)
	target = null
	_speed = 0.0
