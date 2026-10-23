class_name CameraRig
extends Node3D
## Third-person over-the-shoulder camera with a first-person option (V).
## Follows the critter's interpolated visual so it stays smooth at any frame
## rate; a SpringArm3D keeps it out of trees and rocks. Handles ADS zoom,
## recoil kick, trauma-based shake and the first-person viewmodel.

const TP_DISTANCE := 2.5
const TP_AIM_DISTANCE := 1.35
const TP_SHOULDER := 0.55
const DROP_DISTANCE := 7.0

var target: Critter
var yaw := 0.0
var pitch := 0.0
var first_person := false
var shoulder := 1.0          ## +1 right shoulder, -1 left
var aiming := false
var scoped := false           ## looking through a sniper scope (HUD draws the overlay)
var spectate_target: Node3D

var camera: Camera3D
var listener: AudioListener3D   ## at the critter's head, facing where you look
var _arm: SpringArm3D
var _pivot: Node3D
var _trauma := 0.0
var _kick := Vector2.ZERO
var _noise := FastNoiseLite.new()
var _t := 0.0
var _aim_blend := 0.0
var _fp_blend := 0.0
var _viewmodel_root: Node3D
var _viewmodel: Node3D
var _viewmodel_weapon: Variant = null   ## the WeaponInstance shown, or &"club"
var _sway := Vector2.ZERO
var _last_yaw := 0.0
var _last_pitch := 0.0
var _bob_t := 0.0


func _ready() -> void:
	top_level = true
	_pivot = Node3D.new()
	add_child(_pivot)
	_arm = SpringArm3D.new()
	_arm.collision_mask = Layers.WORLD
	_arm.margin = 0.15
	var probe := SphereShape3D.new()
	probe.radius = 0.18
	_arm.shape = probe
	_pivot.add_child(_arm)
	camera = Camera3D.new()
	camera.near = 0.03
	camera.far = 2500.0
	camera.current = true
	_arm.add_child(camera)
	_viewmodel_root = Node3D.new()
	camera.add_child(_viewmodel_root)
	listener = AudioListener3D.new()
	listener.top_level = true
	add_child(listener)
	listener.make_current()
	Audio.listener = listener
	_noise.frequency = 2.0
	Events.explosion.connect(_on_explosion)
	Events.shot_fired.connect(_on_shot)
	first_person = Settings.get_value(&"camera_mode") == Settings.CameraMode.FIRST_PERSON


func set_target(c: Critter) -> void:
	target = c
	_apply_first_person()


func toggle_first_person() -> void:
	first_person = not first_person
	Settings.set_value(&"camera_mode", Settings.CameraMode.FIRST_PERSON if first_person else Settings.CameraMode.THIRD_PERSON)
	_apply_first_person()


func _apply_first_person() -> void:
	if target and is_instance_valid(target) and target.visual:
		target.visual.set_first_person(first_person and target.alive)
	_viewmodel_root.visible = first_person


func add_trauma(amount: float) -> void:
	_trauma = clampf(_trauma + amount, 0.0, 1.0)


func kick(pitch_deg: float, yaw_deg: float) -> void:
	_kick += Vector2(deg_to_rad(yaw_deg) * randf_range(-1.0, 1.0), deg_to_rad(pitch_deg))


func _process(delta: float) -> void:
	_t += delta
	if target == null or not is_instance_valid(target):
		return
	var follow: Node3D = target.visual
	var alive := target.alive
	var dropping := target.state in [Critter.State.FREEFALL, Critter.State.GLIDING, Critter.State.IN_DROPSHIP]
	if not alive and spectate_target and is_instance_valid(spectate_target):
		follow = spectate_target
	_aim_blend = lerpf(_aim_blend, 1.0 if aiming and alive and not dropping else 0.0, IKMath.damp(14.0, delta))
	# scoped weapons look through the scope: the camera moves to the eye
	var cur := target.current_weapon()
	var now_scoped := aiming and alive and not dropping and cur != null and cur.data.scoped and _aim_blend > 0.55
	if now_scoped != scoped:
		scoped = now_scoped
		if target.visual:
			target.visual.set_first_person((first_person or scoped) and alive)
		_viewmodel_root.visible = first_person and not scoped
	_fp_blend = 1.0 if (first_person or scoped) and alive and not dropping else 0.0
	var rig_scale := target.visual.rig.world_scale if target.visual.rig else 1.0
	var eye_h := target.eye_height()   # drops when crouched, to the grass when prone

	var base := follow.global_position
	if dropping and target.state == Critter.State.IN_DROPSHIP and spectate_target:
		base = spectate_target.global_position
	if _fp_blend > 0.5:
		# eye point is body-relative (ignores the hop bob, which would be nauseating)
		_pivot.global_position = base + Vector3.UP * eye_h
		_arm.spring_length = 0.0
		_arm.position = Vector3.ZERO
	else:
		var dist := lerpf(TP_DISTANCE, TP_AIM_DISTANCE, _aim_blend) * rig_scale
		if dropping:
			dist = DROP_DISTANCE
		if not alive:
			dist = 4.0
		_pivot.global_position = base + Vector3.UP * (eye_h + 0.12 * rig_scale)
		_arm.spring_length = dist
		var side := TP_SHOULDER * shoulder * rig_scale * (0.0 if dropping or not alive else 1.0)
		_arm.position = _arm.position.lerp(Vector3(side * lerpf(1.0, 0.75, _aim_blend), 0.0, 0.0), IKMath.damp(10.0, delta))
	if not alive:
		yaw += delta * 0.25   # slow orbit over the body
	_kick = _kick.lerp(Vector2.ZERO, IKMath.damp(9.0, delta))
	_pivot.global_rotation = Vector3(pitch + _kick.y, yaw + _kick.x, 0.0)
	# shake
	_trauma = maxf(0.0, _trauma - delta * 1.4)
	var s := _trauma * _trauma
	camera.rotation = Vector3(
		_noise.get_noise_2d(_t * 25.0, 1.0) * 0.06 * s,
		_noise.get_noise_2d(_t * 25.0, 2.0) * 0.06 * s,
		_noise.get_noise_2d(_t * 25.0, 3.0) * 0.08 * s)
	# hear the world from the critter's head (not from the camera behind it),
	# turned the way the camera looks, so stereo direction matches the screen
	var ear_src: Node3D = follow if (not alive or dropping) else target.visual
	if ear_src and is_instance_valid(ear_src):
		listener.global_transform = Transform3D(Basis(Vector3.UP, yaw), ear_src.global_position + Vector3.UP * eye_h)
	var w := target.current_weapon()
	var fov_scale := lerpf(1.0, w.data.aim_fov_scale if w else 0.85, _aim_blend)
	camera.fov = Settings.fov * fov_scale
	_update_viewmodel(delta, w)


## The world point under the crosshair (what shots converge on).
func aim_point(exclude: Array[RID]) -> Vector3:
	var origin := camera.global_position
	var fwd := -camera.global_basis.z
	# start the ray level with the critter so nothing behind it is "aimed at"
	if target and _fp_blend < 0.5:
		var to_head := target.get_eye_position() - origin
		origin += fwd * maxf(0.0, to_head.dot(fwd))
	var q := PhysicsRayQueryParameters3D.create(origin, origin + fwd * 600.0, Layers.SHOT_MASK)
	q.collide_with_areas = true
	q.exclude = exclude
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return hit.position if hit else origin + fwd * 600.0


# ---- first-person viewmodel ----------------------------------------------------------------------

func _update_viewmodel(delta: float, w: WeaponInstance) -> void:
	if not first_person:
		return
	var club := target.visual != null and target.visual.club_model != null
	var shown: Variant = &"club" if club else w
	if typeof(shown) != typeof(_viewmodel_weapon) or shown != _viewmodel_weapon:
		_viewmodel_weapon = shown
		if _viewmodel:
			_viewmodel.queue_free()
			_viewmodel = null
		if club:
			_viewmodel = target.visual.make_club()
			for gi in ModelUtil.find_all(_viewmodel, "GeometryInstance3D"):
				(gi as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			# the same club, most of a metre long at arm's length from the eye
			_viewmodel.scale *= 0.75 / maxf(CritterVisual.CLUB_LENGTH * target.visual.rig.head_top, 0.01)
			_viewmodel_root.add_child(_viewmodel)
		elif w:
			_viewmodel = ModelUtil.instantiate(w.data.model_path)
			if _viewmodel == null:
				_viewmodel = target.visual._fallback_gun(w.data)
			if w.rarity == Rarity.Tier.GOLDEN:
				target.visual._gild(_viewmodel)
			for gi in ModelUtil.find_all(_viewmodel, "GeometryInstance3D"):
				(gi as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_viewmodel.scale = Vector3.ONE * 1.15
			_viewmodel_root.add_child(_viewmodel)
	if _viewmodel == null:
		return
	if club:
		_club_viewmodel(delta)
		return
	# sway lags behind look motion, bob follows footsteps
	var dyaw := wrapf(yaw - _last_yaw, -PI, PI)
	var dpitch := pitch - _last_pitch
	_last_yaw = yaw
	_last_pitch = pitch
	_sway = _sway.lerp(Vector2(-dyaw, dpitch) * 2.5, IKMath.damp(10.0, delta))
	var speed := Vector2(target.velocity.x, target.velocity.z).length()
	_bob_t += delta * speed * 1.6
	var bob := Vector3(sin(_bob_t) * 0.006, -absf(cos(_bob_t)) * 0.008, 0.0) * clampf(speed / 6.0, 0.0, 1.0)
	var hip := Vector3(0.17, -0.17, -0.38)
	var ads := Vector3(0.0, -0.06, -0.24)
	var sight := ModelUtil.find_named(_viewmodel, "Sight")
	if sight:
		ads = -sight.position * _viewmodel.scale.x + Vector3(0, 0, -0.22)
	var pos := hip.lerp(ads, _aim_blend) + bob * (1.0 - _aim_blend * 0.8)
	pos += Vector3(_sway.x, _sway.y, 0.0) * 0.04
	var reload := target.reload_progress()
	var rot := Vector3(_sway.y * 0.3, _sway.x * 0.3, 0.0)
	if reload >= 0.0:
		var k := sin(reload * PI)
		rot += Vector3(-0.5 * k, 0.0, 0.6 * k)
		pos += Vector3(0.0, -0.08 * k, 0.0)
	var vm_round := ModelUtil.find_named(_viewmodel, "Rocket")
	if vm_round:
		vm_round.visible = Critter.round_chambered(target)
	var recoil: float = target.visual.poser.recoil if target.visual else 0.0
	pos.z += recoil * 0.05
	rot.x += recoil * 0.12
	_viewmodel_root.position = pos
	_viewmodel_root.rotation = rot


## First-person club: up over the right shoulder, then swept down and across
## to the lower left on the strike, and back.
func _club_viewmodel(delta: float) -> void:
	var swing: float = target.visual.poser.melee if target.visual else -1.0
	var strike := 0.0
	if swing >= 0.0:
		strike = smoothstep(0.3, 0.5, swing) * (1.0 - smoothstep(0.6, 1.0, swing))
	var pos := Vector3(0.55 - 0.6 * strike, -0.6 + 0.08 * strike, -0.95)
	_viewmodel_root.position = _viewmodel_root.position.lerp(pos, IKMath.damp(30.0, delta))
	_viewmodel_root.rotation = Vector3(CritterPoser._club_angle(swing) * 0.8, -0.3 + 0.95 * strike, 0.0)


# ---- feedback ------------------------------------------------------------------------------------

func _on_explosion(pos: Vector3, radius: float) -> void:
	var d := camera.global_position.distance_to(pos)
	add_trauma(clampf(1.0 - d / (radius * 6.0), 0.0, 0.8))


func _on_shot(shooter: Node, _origin: Vector3, weapon_id: StringName) -> void:
	if shooter != target:
		return
	var data := WeaponDB.get_weapon(weapon_id)
	if data:
		var k := 0.55 if aiming else 1.0
		kick(data.recoil_yaw_deg * k, data.recoil_pitch_deg * k)
		add_trauma(data.camera_shake)
