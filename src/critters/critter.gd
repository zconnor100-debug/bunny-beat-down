class_name Critter
extends CharacterBody3D
## A woodland combatant. Players and AI drive it through the same "intent"
## fields (move_input, look_yaw/pitch, want_fire, ...) — the AI gets no
## shortcuts: same movement, same guns, same spread, same reloads.

signal died(info: DamageInfo)
signal damaged(info: DamageInfo)
signal weapon_changed(weapon: WeaponInstance)
signal state_changed(state: int)

enum State { IN_DROPSHIP, FREEFALL, GLIDING, GROUND, DEAD }

const ACCEL := 60.0
const AIR_ACCEL := 14.0
const FRICTION := 50.0
const FREEFALL_TERMINAL := 42.0
const GLIDE_FALL := 4.5
const GLIDE_SPEED := 11.0
const FREEFALL_STEER := 14.0
const AUTO_GLIDE_HEIGHT := 28.0
const CORPSE_LIFETIME := 75.0
# melee: each species swings its own club (a gun in the paws is stowed for it)
const MELEE_TIME := 0.55          ## one swing: wind-up, strike, recover
const MELEE_HIT_AT := 0.29        ## fraction of the swing when the club connects (level with the chest)
const MELEE_DAMAGE := 34.0
const MELEE_REACH := 0.85         ## from the chest, per metre of the critter's height
const MELEE_KEEP := 3.0           ## bare paws: the club stays out this long after a swing
const QUICK_KEEP := 0.2           ## gun out: the club goes back this soon after the swing
const PRONE_SPEED := 0.28         ## crawling, as a share of walking speed

@export var def: CritterDef

var display_name := "Critter"
var is_player := false
var state := State.GROUND
var health := 100.0
var max_health := 100.0
var armor := 0.0
var max_armor := 100.0
var alive := true
var kills := 0
var damage_dealt := 0.0
var last_attacker: Node = null
var placement := 0

# ---- intent (written by PlayerController / AIBrain each tick) -------------------
var move_input := Vector2.ZERO     ## x = strafe right, y = forward (look-relative)
var look_yaw := 0.0                ## world yaw of the aim (radians)
var look_pitch := 0.0
var aim_point := Vector3.ZERO      ## world point the crosshair/AI is aiming at
var want_fire := false
var want_aim := false
var want_sprint := false
var want_crouch := false
var want_prone := false            ## lie down and crawl (players only)
var want_jump := false             ## edge-triggered; consumed on use
var want_melee := false            ## edge-triggered: swing the club

var inventory := Inventory.new()
var current_slot := 0
var visual: CritterVisual

var _fire_cooldown := 0.0
var _equip_timer := 0.0
var _reload_timer := -1.0
var _trigger_held := false
var _bloom := 0.0
var _recoil := 0.0
var _was_on_floor := true
var _fall_speed := 0.0
var _hurt_sound_cd := 0.0
var _crouch := 0.0
var _prone := 0.0
var _body: CollisionShape3D
var _stand_height := 1.0
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 16.0)
var swimming := false
var _water_level := -INF
var _melee_t := -1.0               # seconds into the current swing, -1 when not swinging
var _melee_struck := false
var _club_out := 0.0               # seconds before the club is put away


## Menu/picker previews: not part of any match (no group, no events, no AI sight).
var preview := false


func _ready() -> void:
	if not preview:
		add_to_group(&"critters")
	collision_layer = Layers.CRITTERS
	collision_mask = Layers.WORLD | Layers.CRITTERS
	floor_max_angle = deg_to_rad(52.0)
	floor_snap_length = 0.35
	if def == null:
		def = load("res://data/critters/bun.tres")
	max_health = def.max_health
	health = max_health
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	visual = CritterVisual.new()
	visual.name = "Visual"
	add_child(visual)
	if not visual.build(self, def):
		push_error("critter %s failed to build its visual" % display_name)
	var h := visual.rig.world_head_top if visual.rig else 1.0
	cap.radius = clampf(h * 0.3, 0.22, 0.5)   # stays within the navmesh agent radius (0.5)
	cap.height = maxf(h * 0.98, cap.radius * 2.0 + 0.05)
	shape.shape = cap
	shape.position.y = cap.height * 0.5
	shape.name = "Body"
	add_child(shape)
	_body = shape
	_stand_height = cap.height
	visual.physics_tick(global_transform, true)
	visual.poser.footstep.connect(_on_footstep)
	inventory.changed.connect(_on_inventory_changed)
	if not preview:
		Events.critter_spawned.emit(self)


# ---- queries used by AI / HUD / weapons ---------------------------------------------

func get_eye_position() -> Vector3:
	return global_position + Vector3.UP * eye_height()


func get_chest_position() -> Vector3:
	return global_position + Vector3.UP * chest_height()


## Eye height above the feet: lower when crouched, near the grass when prone.
func eye_height() -> float:
	var e := visual.rig.world_eye_height if visual and visual.rig else 0.85
	return e * (1.0 - 0.15 * _crouch) * lerpf(1.0, 0.3, _prone)


func chest_height() -> float:
	var h := visual.rig.world_head_top if visual and visual.rig else 1.0
	return h * (1.0 - 0.15 * _crouch) * lerpf(0.6, 0.15, _prone)


## How far the club reaches from the chest.
func melee_reach() -> float:
	return MELEE_REACH * (visual.rig.world_head_top if visual and visual.rig else 1.0)


func current_weapon() -> WeaponInstance:
	return inventory.weapons[current_slot]


## 0 standing … 1 fully crouched.
func crouch_amount() -> float:
	return _crouch


## 0 up … 1 lying flat on the belly.
func prone_amount() -> float:
	return _prone


## Whether a round sits in the gun (drives the visible rocket in the launcher).
static func round_chambered(c: Node) -> bool:
	var w: WeaponInstance = (c as Critter).current_weapon()
	return w != null and (w.ammo_in_mag > 0 or (c as Critter).reload_progress() > 0.55)


func is_reloading() -> bool:
	return _reload_timer >= 0.0


func reload_progress() -> float:
	var w := current_weapon()
	if w == null or _reload_timer < 0.0:
		return -1.0
	return 1.0 - _reload_timer / w.reload_time()


func look_direction() -> Vector3:
	return Vector3(-sin(look_yaw) * cos(look_pitch), sin(look_pitch), -cos(look_yaw) * cos(look_pitch)).normalized()


func current_spread_deg() -> float:
	var w := current_weapon()
	if w == null:
		return 0.0
	var d := w.data
	var base := d.spread_aim_deg if want_aim else d.spread_hip_deg
	var moving := clampf(Vector2(velocity.x, velocity.z).length() / def.move_speed, 0.0, 1.0)
	var air := 0.0 if is_on_floor() else 1.5
	return base + d.spread_move_deg * moving + air + _bloom - (0.3 * base if _crouch > 0.5 else 0.0)


# ---- physics ------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if state == State.DEAD or state == State.IN_DROPSHIP:
		return
	_hurt_sound_cd = maxf(0.0, _hurt_sound_cd - delta)
	match state:
		State.FREEFALL, State.GLIDING:
			_air_drop_move(delta)
		_:
			_ground_move(delta)
	_weapon_tick(delta)
	_melee_tick(delta)
	_update_facing(delta)
	_update_visual(delta)
	if state == State.GROUND:
		_check_stuck(delta)
	visual.physics_tick(global_transform)


func _ground_move(delta: float) -> void:
	var on_floor := is_on_floor()
	_update_swimming()
	if swimming:
		_swim_move(delta)
		return
	# lying down: stay down while there's no room to stand (under a log)
	var stay_down := not want_prone and _prone > 0.05 and not _room_to_stand()
	_prone = move_toward(_prone, 1.0 if (want_prone or stay_down) and on_floor else 0.0, delta * 2.5)
	_crouch = move_toward(_crouch, 1.0 if want_crouch and on_floor and _prone < 0.5 else 0.0, delta * 6.0)
	_fit_body()
	var w := current_weapon()
	var speed := def.move_speed
	# sprint forward or sideways — aiming too (a little slower than flat out)
	var sprinting := want_sprint and move_input.length() > 0.3 and move_input.y > -0.3 and _prone < 0.5
	if sprinting:
		speed = def.sprint_speed
	if want_aim:
		speed *= 0.85 if sprinting else 0.6
	speed *= lerpf(1.0, 0.45, _crouch) * lerpf(1.0, PRONE_SPEED, _prone)
	# wading through the swamp (or a pond's edge) slows you down
	var wade := _water_level - global_position.y
	if wade > 0.15:
		var h := visual.rig.world_head_top if visual and visual.rig else 1.0
		speed *= lerpf(1.0, 0.7, clampf(wade / (h * 0.5), 0.0, 1.0))
	if w:
		speed *= w.data.move_speed_scale
	var basis := Basis(Vector3.UP, look_yaw)
	var wish := basis * Vector3(move_input.x, 0, -move_input.y)
	if wish.length() > 1.0:
		wish = wish.normalized()
	var target := wish * speed
	var hv := Vector3(velocity.x, 0, velocity.z)
	var accel := ACCEL if on_floor else AIR_ACCEL
	if wish.length_squared() < 0.01 and on_floor:
		accel = FRICTION
	hv = hv.move_toward(target, accel * delta)
	velocity.x = hv.x
	velocity.z = hv.z
	if on_floor:
		if want_jump:
			velocity.y = sqrt(2.0 * _gravity * def.jump_height)
			Audio.play_at(&"hop" if def.gait == CritterDef.Gait.HOP else &"jump", global_position, -6.0)
			# every species has its own move in the air (bunnies flip!)
			visual.start_jump_trick(global_basis.inverse() * velocity, 2.0 * velocity.y / _gravity)
	else:
		velocity.y -= _gravity * delta
	want_jump = false
	_fall_speed = -velocity.y if not on_floor else _fall_speed
	move_and_slide()
	_slide_off_slippery()
	var landed := is_on_floor() and not _was_on_floor
	if landed:
		_on_touchdown()
	if landed and _fall_speed > 4.0:
		visual.poser.on_landed(_fall_speed)
		Audio.play_at(&"land", global_position, -8.0)
	_was_on_floor = is_on_floor()
	if global_position.y < -30.0:
		take_damage(DamageInfo.make(9999.0, DamageInfo.Kind.FALL, null))


## The collision capsule shrinks to a low lump while lying down.
func _fit_body() -> void:
	var cap := _body.shape as CapsuleShape3D
	var want := lerpf(_stand_height, maxf(cap.radius * 2.0 + 0.05, _stand_height * 0.36), _prone)
	if absf(cap.height - want) > 0.01:
		cap.height = want
		_body.position.y = want * 0.5


func _room_to_stand() -> bool:
	var q := PhysicsShapeQueryParameters3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = (_body.shape as CapsuleShape3D).radius
	cap.height = _stand_height
	q.shape = cap
	q.transform = Transform3D(Basis(), global_position + Vector3.UP * (_stand_height * 0.5 + 0.05))
	q.collision_mask = Layers.WORLD
	return get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty()


## Chest-deep water → swim: buoyancy holds the chest at the surface, movement
## slows, and guns stay quiet until we wade out.
func _update_swimming() -> void:
	var was := swimming
	var level := Island.current.water_level_at(global_position) if Island.current else -INF
	_water_level = level
	var h := visual.rig.world_head_top if visual and visual.rig else 1.0
	var depth := level - global_position.y
	# hysteresis: start swimming when chest-deep, stop once we're wading out
	swimming = depth > h * (0.42 if was else 0.55)
	if swimming and not was:
		FX.impact(Vector3(global_position.x, level, global_position.z), Vector3.UP, &"water")
		Audio.play_at(&"land", global_position, -4.0)


func _swim_move(delta: float) -> void:
	var h := visual.rig.world_head_top if visual and visual.rig else 1.0
	var basis := Basis(Vector3.UP, look_yaw)
	var wish := basis * Vector3(move_input.x, 0, -move_input.y)
	if wish.length() > 1.0:
		wish = wish.normalized()
	var hv := Vector3(velocity.x, 0, velocity.z).move_toward(wish * def.move_speed * 0.5, 18.0 * delta)
	velocity.x = hv.x
	velocity.z = hv.z
	var float_y := _water_level - h * 0.5
	velocity.y = move_toward(velocity.y, clampf((float_y - global_position.y) * 4.0, -3.0, 3.0), 30.0 * delta)
	if want_jump:
		velocity.y = 4.0   # a little hop to clamber out onto the bank
	want_jump = false
	move_and_slide()
	# swimming into a bank: clamber up it instead of bumping against the edge
	if wish.length() > 0.3 and (is_on_wall() or is_on_floor()):
		velocity.y = maxf(velocity.y, 3.5)
		global_position.y += 0.05
	_was_on_floor = false


## Rescue for critters wedged between rocks, logs or terrain: if one keeps
## trying to move but goes nowhere, first hop, then pop it onto the nearest
## walkable navmesh spot (a little way out into the open).
const STUCK_HOP_AFTER := 1.5
const STUCK_RESCUE_AFTER := 4.0
## how many times this critter was lifted out of a trap (diagnostics + tests)
var rescues := 0
var _stuck_t := 0.0
var _stuck_from := Vector3.ZERO


func _check_stuck(delta: float) -> void:
	var real := get_real_velocity()
	# moving freely (incl. strafing back and forth in a fight) is never "stuck"
	if move_input.length() < 0.3 or Vector2(real.x, real.z).length() > 0.9:
		_stuck_t = 0.0
		_stuck_from = global_position
		return
	# only horizontal progress counts (the escape hop must not reset the timer)
	if Vector2(global_position.x - _stuck_from.x, global_position.z - _stuck_from.z).length() > 1.2:
		_stuck_t = 0.0
		_stuck_from = global_position
		return
	_stuck_t += delta
	if _stuck_t > STUCK_HOP_AFTER and _stuck_t - delta <= STUCK_HOP_AFTER:
		want_jump = true
	if _stuck_t > STUCK_RESCUE_AFTER:
		_stuck_t = 0.0
		_stuck_from = global_position
		rescue_to_open_ground()


func rescue_to_open_ground() -> bool:
	var map := get_world_3d().navigation_map
	if not NavigationServer3D.map_is_active(map) or NavigationServer3D.map_get_iteration_id(map) == 0:
		return false
	var best := Vector3.INF
	var space := get_world_3d().direct_space_state
	# try spots in a widening ring and keep the first one with room to stand
	for radius in [1.5, 2.5, 4.0, 6.0, 10.0, 15.0]:
		for i in 8:
			var a := TAU * i / 8.0 + randf() * 0.3
			var probe: Vector3 = global_position + Vector3(cos(a), 0, sin(a)) * radius
			var p := NavigationServer3D.map_get_closest_point(map, probe)
			if p.distance_to(probe) > 2.0:
				continue
			var shape := PhysicsShapeQueryParameters3D.new()
			var cap := ($Body as CollisionShape3D).shape
			shape.shape = cap
			shape.transform = Transform3D(Basis(), p + Vector3.UP * ((cap as CapsuleShape3D).height * 0.5 + 0.08))
			shape.collision_mask = Layers.WORLD
			if space.intersect_shape(shape, 1).is_empty():
				best = p
				break
		if best != Vector3.INF:
			break
	if best == Vector3.INF:
		return false
	global_position = best + Vector3.UP * 0.1
	velocity = Vector3.ZERO
	visual.physics_tick(global_transform, true)
	rescues += 1
	return true


func _on_touchdown() -> void:
	var t := visual.trick
	if t == null or not t.active:
		return
	visual.trick_landed()
	if def.jump_style == CritterDef.JumpStyle.TAIL_SLAP:
		# beavers finish with a tail slap: a whap and a ring of dust
		Audio.play_at(&"body_fall", global_position, 0.0, 0.1)
		for i in 6:
			var a := TAU * i / 6.0
			FX.impact(global_position + Vector3(cos(a), 0.05, sin(a)) * 0.6, Vector3(cos(a), 0.6, sin(a)), &"dirt")


func _air_drop_move(delta: float) -> void:
	var basis := Basis(Vector3.UP, look_yaw)
	var wish := basis * Vector3(move_input.x, 0, -move_input.y)
	if state == State.FREEFALL:
		velocity.y = maxf(velocity.y - _gravity * delta, -FREEFALL_TERMINAL)
		var hv := Vector3(velocity.x, 0, velocity.z).move_toward(wish * FREEFALL_STEER, 20.0 * delta)
		velocity.x = hv.x
		velocity.z = hv.z
		if want_jump or _height_above_ground() < AUTO_GLIDE_HEIGHT:
			_set_state(State.GLIDING)
			Audio.play_at(&"glider_open", global_position)
	else:
		velocity.y = move_toward(velocity.y, -GLIDE_FALL, 30.0 * delta)
		var hv := Vector3(velocity.x, 0, velocity.z).move_toward(wish * GLIDE_SPEED, 10.0 * delta)
		velocity.x = hv.x
		velocity.z = hv.z
	want_jump = false
	move_and_slide()
	if _slide_off_slippery():
		return
	# splash-down: gliding into the sea or a pond ends the drop (swimming takes over)
	var level := Island.current.water_level_at(global_position) if Island.current else -INF
	if global_position.y <= level + 0.3:
		_set_state(State.GROUND)
		return
	if is_on_floor():
		_set_state(State.GROUND)
		visual.poser.on_landed(8.0)
		Audio.play_at(&"land", global_position)


## Standing on something that isn't meant to be stood on (the top of a tree
## trunk's collider, hidden in the canopy): shove the critter off the edge.
func _slide_off_slippery() -> bool:
	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		var other := col.get_collider() as Node3D
		if other and other.has_meta(&"slippery") and col.get_normal().y > 0.5:
			var away := global_position - other.global_position
			away.y = 0.0
			if away.length_squared() < 0.01:
				away = Vector3.RIGHT.rotated(Vector3.UP, randf() * TAU)
			away = away.normalized()
			velocity.x = away.x * 6.0
			velocity.z = away.z * 6.0
			global_position += away * 0.15
			return true
	return false


## Height above whatever we'd land on: the ground, or the water surface.
func _height_above_ground() -> float:
	var q := PhysicsRayQueryParameters3D.create(global_position, global_position + Vector3.DOWN * 400.0, Layers.WORLD | Layers.WATER)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var ground := global_position.y - (hit.position.y as float) if hit else 999.0
	var water := global_position.y - (Island.current.water_level_at(global_position) if Island.current else -INF)
	return minf(ground, water)


func _update_facing(delta: float) -> void:
	# armed critters (gun or club) face where they aim; unarmed ones face where they run
	var target_yaw := look_yaw
	var hv := Vector2(velocity.x, velocity.z)
	if current_weapon() == null and visual.club_model == null and hv.length() > 0.5 and not want_aim:
		target_yaw = atan2(-velocity.x, -velocity.z)
	# lying down, the body swings round slowly
	rotation.y = lerp_angle(rotation.y, target_yaw, IKMath.damp(lerpf(14.0, 4.0, _prone), delta))


func _update_visual(delta: float) -> void:
	var p := visual.poser
	p.velocity = velocity
	p.grounded = is_on_floor() or state == State.GLIDING
	p.aim_dir = (aim_point - get_eye_position()).normalized() if aim_point.distance_squared_to(get_eye_position()) > 1.0 else look_direction()
	p.crouch = _crouch
	p.prone = _prone
	p.gliding = state == State.GLIDING or state == State.FREEFALL
	p.armed = (current_weapon() != null or visual.club_model != null) and not swimming
	p.reload_progress = reload_progress()
	_recoil = move_toward(_recoil, 0.0, delta * 6.0)
	p.recoil = _recoil


## Footsteps are a gameplay cue: other critters' steps are loud, strongly panned
## and muffled when behind you, so you can hear where someone is and turn.
const FOOTSTEP_RANGE := 34.0


func _on_footstep(hop: bool) -> void:
	var key := &"hop" if hop else &"footstep_grass"
	if _water_level > global_position.y + 0.1:
		FX.impact(Vector3(global_position.x, _water_level, global_position.z), Vector3.UP, &"water")
	if is_player:
		Audio.play_at(key, global_position, -20.0 if _crouch < 0.5 else -26.0, 0.12)
		return
	var ear := Audio.listener_transform().origin
	if ear.distance_squared_to(global_position) > FOOTSTEP_RANGE * FOOTSTEP_RANGE:
		return
	var vol := (1.0 if hop else -1.0) - (7.0 if want_crouch else 0.0)
	Audio.play_at(key, global_position, vol, 0.12,
		{"unit_size": 3.5, "max_distance": FOOTSTEP_RANGE, "panning": 1.8, "directional": true})


func _set_state(s: State) -> void:
	if state == s:
		return
	state = s
	if visual:
		visual.set_glider(s == State.GLIDING)
	state_changed.emit(s)


## Drop-in from the dropship.
func begin_freefall(at: Vector3, initial_velocity: Vector3) -> void:
	global_position = at
	velocity = initial_velocity
	visible = true
	process_mode = Node.PROCESS_MODE_INHERIT
	_set_state(State.FREEFALL)
	visual.physics_tick(global_transform, true)


func board_dropship() -> void:
	_set_state(State.IN_DROPSHIP)
	visible = false
	velocity = Vector3.ZERO


## Teleport without interpolation smear.
func place_at(pos: Vector3, yaw := 0.0) -> void:
	global_position = pos
	rotation.y = yaw
	look_yaw = yaw
	visual.physics_tick(global_transform, true)


# ---- weapons ------------------------------------------------------------------------------------

func _weapon_tick(delta: float) -> void:
	_fire_cooldown = maxf(0.0, _fire_cooldown - delta)
	_equip_timer = maxf(0.0, _equip_timer - delta)
	var w := current_weapon()
	if w == null:
		if want_fire and not _trigger_held:
			want_melee = true   # bare paws: the trigger swings the club
		_trigger_held = want_fire
		return
	_bloom = move_toward(_bloom, 0.0, delta * (w.data.bloom_max_deg * 1.5 + 1.0))
	if _reload_timer >= 0.0:
		_reload_timer -= delta
		if _reload_timer < 0.0:
			_finish_reload()
	var can_shoot := state == State.GROUND and not swimming and _equip_timer <= 0.0 and _reload_timer < 0.0 \
		and not (visual.trick and visual.trick.blocks_fire()) and visual.club_model == null
	if want_fire and can_shoot and _fire_cooldown <= 0.0:
		var semi_ok := w.data.fire_mode == WeaponData.FireMode.AUTO or not _trigger_held
		if semi_ok:
			if w.ammo_in_mag > 0:
				_fire(w)
			elif not _trigger_held:
				Audio.play_at(&"dry_fire", global_position, -6.0)
				start_reload()
	_trigger_held = want_fire


func _fire(w: WeaponInstance) -> void:
	w.ammo_in_mag -= 1
	_fire_cooldown = w.data.seconds_per_shot()
	var origin := visual.muzzle_position()
	var target := aim_point
	var dir := (target - origin)
	# if the aim point is behind the muzzle (hugging a wall), shoot along the look
	if dir.length_squared() < 0.25 or dir.normalized().dot(look_direction()) < 0.2:
		dir = look_direction()
	dir = dir.normalized()
	# point-blank: if something is between our body and the muzzle (a critter
	# hugging us, a tree we're pressed against), the carrots start from the
	# chest so they hit it instead of spawning on the far side
	var chest := get_chest_position()
	var q := PhysicsRayQueryParameters3D.create(chest, origin, Layers.SHOT_MASK)
	q.collide_with_areas = true
	q.exclude = visual.hitbox_rids
	if get_world_3d().direct_space_state.intersect_ray(q):
		origin = chest
	Projectiles.fire(self, w, origin, dir, current_spread_deg(), visual.hitbox_rids)
	_bloom = minf(_bloom + w.data.bloom_per_shot_deg, w.data.bloom_max_deg)
	_recoil = 1.0
	FX.muzzle(origin, dir, w.data.projectile == WeaponData.ProjectileKind.ROCKET or w.data.pellets > 1)
	if is_player:
		Audio.play(w.data.sfx_fire, -2.0, 0.06)
	else:
		Audio.play_at(w.data.sfx_fire, origin, 0.0, 0.06)
	Events.shot_fired.emit(self, origin, w.data.id)
	if w.data.cycle_sfx != &"":
		Despawner.after(self, 0.45, func(n: Node): Audio.play_at(w.data.cycle_sfx, (n as Node3D).global_position, -4.0))
	if w.ammo_in_mag <= 0 and inventory.ammo[w.data.ammo_type] > 0:
		start_reload.call_deferred()


func start_reload() -> void:
	var w := current_weapon()
	if w == null or _reload_timer >= 0.0 or w.ammo_in_mag >= w.magazine_size():
		return
	if inventory.ammo[w.data.ammo_type] <= 0:
		return
	_reload_timer = w.reload_time()
	Audio.play_at(&"reload_start", global_position, -4.0)


func _finish_reload() -> void:
	_reload_timer = -1.0
	var w := current_weapon()
	if w == null:
		return
	var need := w.magazine_size() - w.ammo_in_mag
	w.ammo_in_mag += inventory.take_ammo(w.data.ammo_type, need)
	Audio.play_at(&"reload_end", global_position, -4.0)


func switch_to(slot: int) -> void:
	if slot == current_slot or slot < 0 or slot >= Inventory.SLOTS:
		return
	current_slot = slot
	_reload_timer = -1.0
	var w := current_weapon()
	_equip_timer = w.data.equip_time if w else 0.0
	visual.set_weapon(w)
	weapon_changed.emit(w)
	if w:
		Audio.play_at(&"weapon_swap", global_position, -6.0)


func cycle_weapon(step: int) -> void:
	for i in range(1, Inventory.SLOTS + 1):
		var s := posmod(current_slot + step * i, Inventory.SLOTS)
		if inventory.weapons[s] != null:
			switch_to(s)
			return


## Pick up a gun: fills an empty slot, otherwise swaps with the held one.
## Returns the weapon that was dropped, if any.
func give_weapon(w: WeaponInstance) -> WeaponInstance:
	var slot := inventory.first_free_slot()
	var dropped: WeaponInstance = null
	if slot < 0:
		slot = current_slot
		dropped = inventory.take_weapon(slot)
	inventory.put_weapon(w, slot)
	if current_weapon() == null or slot == current_slot or inventory.weapon_count() == 1:
		current_slot = -1
		switch_to(slot)
	return dropped


func use_clover() -> bool:
	if inventory.clovers <= 0 or health >= max_health or not alive:
		return false
	inventory.clovers -= 1
	inventory.changed.emit()
	health = minf(max_health, health + 40.0)
	Audio.play_at(&"pickup_health", global_position)
	return true


func _on_inventory_changed() -> void:
	if current_weapon() == null:
		visual.set_weapon(null)


# ---- damage & death ------------------------------------------------------------------------------

# ---- melee -----------------------------------------------------------------------------------

func is_swinging() -> bool:
	return _melee_t >= 0.0


func _melee_tick(delta: float) -> void:
	if want_melee:
		want_melee = false
		if _melee_t < 0.0 and state == State.GROUND and not swimming and _prone < 0.2:
			_melee_t = 0.0
			_melee_struck = false
			# with a gun out, the gun is stowed for the swing and comes straight back
			_club_out = MELEE_KEEP if current_weapon() == null else QUICK_KEEP
			_reload_timer = -1.0
			visual.set_club(true)
			Audio.play_at(&"melee_swing", global_position, -3.0, 0.12)
	if _melee_t >= 0.0:
		_melee_t += delta
		if not _melee_struck and _melee_t >= MELEE_TIME * MELEE_HIT_AT:
			_melee_struck = true
			_melee_strike()
		if _melee_t >= MELEE_TIME:
			_melee_t = -1.0
	elif _club_out > 0.0:
		_club_out -= delta
		if _club_out <= 0.0:
			visual.set_club(false)
	visual.poser.melee = _melee_t / MELEE_TIME if _melee_t >= 0.0 else -1.0


## The club connects: everyone within reach in front of us takes a hit on the
## body part nearest the club, and gets knocked back.
func _melee_strike() -> void:
	var reach := melee_reach()
	var fwd := look_direction()
	var centre := get_chest_position() + fwd * reach * 0.6
	var q := PhysicsShapeQueryParameters3D.new()
	var ball := SphereShape3D.new()
	ball.radius = reach * 0.65
	q.shape = ball
	q.transform = Transform3D(Basis(), centre)
	q.collision_mask = Layers.HITBOXES
	q.collide_with_areas = true
	q.collide_with_bodies = false
	q.exclude = visual.hitbox_rids
	var victims := {}   # critter -> [role, distance, position]
	for hit in get_world_3d().direct_space_state.intersect_shape(q, 64):
		var area := hit.collider as Node3D
		if area == null or not area.has_meta(&"critter"):
			continue
		var c := area.get_meta(&"critter") as Critter
		if c == null or c == self or not c.alive:
			continue
		var d := area.global_position.distance_to(centre)
		if not victims.has(c) or d < victims[c][1]:
			victims[c] = [area.get_meta(&"role", &"chest"), d, area.global_position]
	for c in victims:
		var v: Array = victims[c]
		var info := DamageInfo.make(MELEE_DAMAGE * RigInfo.DAMAGE_SCALE.get(v[0], 1.0), DamageInfo.Kind.MELEE, self, &"melee")
		info.position = v[2]
		info.direction = fwd
		info.bone_role = v[0]
		info.impulse = 7.0
		info.dismember_power = 0.35
		if v[0] == &"head":
			info.headshot = true
			info.amount *= 1.5
		(c as Critter).take_damage(info)
		(c as Critter).velocity += Vector3(fwd.x, 0.0, fwd.z).normalized() * 5.0 + Vector3.UP * 2.5
	if not victims.is_empty():
		Audio.play_at(&"melee_hit", centre, 0.0, 0.1)


## A carrot hit one of this critter's hitboxes.
func receive_shot(shooter: Node, data: WeaponData, dmg: float, pos: Vector3, dir: Vector3, role: StringName) -> void:
	if not alive:
		return
	var info := DamageInfo.make(dmg * RigInfo.DAMAGE_SCALE.get(role, 1.0), DamageInfo.Kind.BULLET, shooter, data.id)
	info.position = pos
	info.direction = dir
	info.bone_role = role
	info.impulse = data.impulse
	info.dismember_power = data.dismember_power
	if role == &"head":
		info.headshot = true
		info.amount *= data.headshot_multiplier
	take_damage(info)


func take_damage(info: DamageInfo) -> void:
	if not alive or state == State.IN_DROPSHIP:
		return
	if is_player and info.attacker is Critter and info.attacker != self and not (info.attacker as Critter).is_player:
		info.amount *= AIBrain.damage_to_player   # bots hit softer than they look (per difficulty)
	var dmg := info.amount
	if info.kind != DamageInfo.Kind.STORM and info.kind != DamageInfo.Kind.FALL and armor > 0.0:
		var absorbed := minf(armor, dmg)
		armor -= absorbed
		dmg -= absorbed
		if armor <= 0.0:
			Audio.play_at(&"armor_break", global_position)
	health -= dmg
	if info.attacker and info.attacker != self:
		last_attacker = info.attacker
		if info.attacker is Critter:
			(info.attacker as Critter).damage_dealt += info.amount
	if info.kind != DamageInfo.Kind.STORM:
		var strength := clampf(info.amount / 40.0, 0.15, 1.0)
		FX.blood_hit(info.position if info.position != Vector3.ZERO else get_chest_position(), -info.direction, strength, def.fur_color)
		visual.poser.flinch(info.direction, strength)
		if info.kind == DamageInfo.Kind.EXPLOSION:
			velocity += info.direction * info.impulse * 0.3
	if _hurt_sound_cd <= 0.0 and health > 0.0:
		Audio.play_at(&"hurt_squeak", global_position, -2.0, 0.15)
		_hurt_sound_cd = 0.35
	damaged.emit(info)
	Events.critter_damaged.emit(self, info)
	if info.attacker is Critter and (info.attacker as Critter).is_player and info.attacker != self:
		Events.player_hit_confirmed.emit(self, info.amount, info.headshot, health <= 0.0)
	if health <= 0.0:
		_die(info)


func _die(info: DamageInfo) -> void:
	alive = false
	health = 0.0
	_set_state(State.DEAD)
	collision_layer = 0
	collision_mask = 0
	if info.attacker is Critter and info.attacker != self:
		(info.attacker as Critter).kills += 1
	Audio.play_at(&"death_squeak", global_position, 0.0, 0.15)
	_drop_loot()
	visual.go_ragdoll(velocity.limit_length(9.0))
	var push := info.direction.normalized() * info.impulse
	if info.kind == DamageInfo.Kind.EXPLOSION:
		# spread the blast over every body part, proportional to its mass
		for role in visual.physical_bones:
			var pb: PhysicalBone3D = visual.physical_bones[role]
			visual.push_bone(role, push.normalized() * pb.mass * minf(info.impulse * 0.35, 7.0), visual.bone_world_position(role))
	else:
		visual.push_bone(info.bone_role, push, info.position)
	_apply_death_gore(info)
	if info.kind != DamageInfo.Kind.EXPLOSION:
		# the ragdoll hits the ground (blasts throw it too far to time this)
		Despawner.after(self, 0.45, func(n: Node): Audio.play_at(&"body_fall", (n as Critter).visual.bone_world_position(&"hips"), -3.0, 0.1))
	died.emit(info)
	Events.critter_died.emit(self, info)
	if not is_player:
		Despawner.schedule(self, CORPSE_LIFETIME, 1.0)


func _apply_death_gore(info: DamageInfo) -> void:
	var gore_ok := Settings.gore != Settings.Gore.OFF
	var p := info.dismember_power
	var push := info.direction.normalized() * maxf(info.impulse, 4.0) * 0.6
	if info.kind == DamageInfo.Kind.EXPLOSION:
		visual.pop_helmet(push * 1.5)
		if gore_ok and p > 0.35:
			FX.gore_burst(get_chest_position(), 1.4, def.fur_color)
			_gore_splat()
			var limbs := [&"head", &"l_upper_arm", &"r_upper_arm", &"l_upper_leg", &"r_upper_leg", &"l_lower_arm", &"r_lower_leg"]
			limbs.shuffle()
			var n := clampi(int(round(p * 4.0)), 1, 4)
			for i in n:
				var away := (push + Vector3(randf_range(-1, 1), randf_range(0.5, 1.5), randf_range(-1, 1)) * 3.0)
				visual.dismember(limbs[i], away)
		return
	if info.headshot:
		visual.pop_helmet(push + Vector3.UP * 1.5)
		if gore_ok and (p >= 0.5 or info.amount >= 45.0):
			visual.dismember(&"head", push * 1.2 + Vector3.UP * 3.0)
			_gore_splat()
		return
	if gore_ok and info.bone_role != &"" and info.bone_role not in [&"chest", &"spine", &"hips"]:
		if randf() < p:
			visual.dismember(info.bone_role, push + Vector3.UP * 1.5)


## Wet splat on a gory kill (Gore: Full only; plushie stuffing doesn't squelch).
func _gore_splat() -> void:
	if Settings.gore == Settings.Gore.BLOOD:
		Audio.play_at(&"gore_splat", get_chest_position(), -2.0, 0.1)


## A carrot hit this critter's ragdoll.
func receive_corpse_shot(data: WeaponData, pos: Vector3, dir: Vector3, body: Object) -> void:
	if body is PhysicalBone3D:
		(body as PhysicalBone3D).apply_impulse(dir * data.impulse * 0.6, pos - (body as PhysicalBone3D).global_position)
	FX.blood_hit(pos, -dir, 0.4, def.fur_color)
	var role: StringName = (body as Node).get_meta(&"role", &"") if body is Node else &""
	if role != &"" and role not in [&"chest", &"spine", &"hips"] and Settings.gore != Settings.Gore.OFF and randf() < data.dismember_power * 0.5:
		visual.dismember(role, dir * 3.0 + Vector3.UP)


## A rocket went off next to this corpse.
func blast_corpse(pos: Vector3, strength: float) -> void:
	if alive or Settings.gore == Settings.Gore.OFF:
		return
	for role in [&"head", &"l_upper_arm", &"r_upper_arm", &"l_upper_leg", &"r_upper_leg"]:
		if randf() < strength * 0.5:
			var away := (visual.bone_world_position(role) - pos).normalized() * 5.0 + Vector3.UP * 2.0
			visual.dismember(role, away)


func _drop_loot() -> void:
	var drops: Array = []
	for i in Inventory.SLOTS:
		var w: WeaponInstance = inventory.weapons[i]
		if w:
			drops.append(Pickup.weapon_spec(w))
	for t in inventory.ammo:
		if inventory.ammo[t] > 0:
			drops.append(Pickup.ammo_spec(t, inventory.ammo[t]))
	if inventory.clovers > 0:
		drops.append(Pickup.clover_spec(inventory.clovers))
	inventory.weapons = [null, null, null]
	var parent := Despawner.debris_parent(self)
	for i in drops.size():
		var a := TAU * i / maxf(drops.size(), 1)
		Pickup.spawn(parent, drops[i], global_position + Vector3(cos(a), 0.6, sin(a)) * 0.7, Vector3(cos(a) * 2.0, 3.0, sin(a) * 2.0))
