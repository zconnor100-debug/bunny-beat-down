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
var want_jump := false             ## edge-triggered; consumed on use

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
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 16.0)
var swimming := false
var _water_level := -INF


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
	cap.radius = clampf(h * 0.3, 0.22, 0.38)
	cap.height = maxf(h * 0.98, cap.radius * 2.0 + 0.05)
	shape.shape = cap
	shape.position.y = cap.height * 0.5
	shape.name = "Body"
	add_child(shape)
	visual.physics_tick(global_transform, true)
	visual.poser.footstep.connect(_on_footstep)
	inventory.changed.connect(_on_inventory_changed)
	if not preview:
		Events.critter_spawned.emit(self)


# ---- queries used by AI / HUD / weapons ---------------------------------------------

func get_eye_position() -> Vector3:
	return global_position + Vector3.UP * (visual.rig.world_eye_height if visual and visual.rig else 0.85)


func get_chest_position() -> Vector3:
	return global_position + Vector3.UP * (visual.rig.world_head_top * 0.6 if visual and visual.rig else 0.6)


func current_weapon() -> WeaponInstance:
	return inventory.weapons[current_slot]


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
	_update_facing(delta)
	_update_visual(delta)
	visual.physics_tick(global_transform)


func _ground_move(delta: float) -> void:
	var on_floor := is_on_floor()
	_update_swimming()
	if swimming:
		_swim_move(delta)
		return
	_crouch = move_toward(_crouch, 1.0 if want_crouch and on_floor else 0.0, delta * 6.0)
	var w := current_weapon()
	var speed := def.move_speed
	if want_sprint and move_input.y > 0.3 and not want_aim and not want_fire:
		speed = def.sprint_speed
	if want_aim:
		speed *= 0.6
	speed *= lerpf(1.0, 0.45, _crouch)
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


## Chest-deep water → swim: buoyancy holds the chest at the surface, movement
## slows, and guns stay quiet until we wade out.
func _update_swimming() -> void:
	var was := swimming
	var level := Island.current.water_level_at(global_position) if Island.current else -INF
	_water_level = level
	var h := visual.rig.world_head_top if visual and visual.rig else 1.0
	swimming = level - global_position.y > h * 0.55
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
	var float_y := _water_level - h * 0.6
	velocity.y = move_toward(velocity.y, clampf((float_y - global_position.y) * 4.0, -3.0, 3.0), 30.0 * delta)
	if want_jump:
		velocity.y = 4.0   # a little hop to clamber out onto the bank
	want_jump = false
	move_and_slide()
	_was_on_floor = false


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


func _height_above_ground() -> float:
	var q := PhysicsRayQueryParameters3D.create(global_position, global_position + Vector3.DOWN * 400.0, Layers.WORLD | Layers.WATER)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return global_position.y - (hit.position.y as float) if hit else 999.0


func _update_facing(delta: float) -> void:
	# armed critters face where they aim; unarmed ones face where they run
	var target_yaw := look_yaw
	var hv := Vector2(velocity.x, velocity.z)
	if current_weapon() == null and hv.length() > 0.5 and not want_aim:
		target_yaw = atan2(-velocity.x, -velocity.z)
	rotation.y = lerp_angle(rotation.y, target_yaw, IKMath.damp(14.0, delta))


func _update_visual(delta: float) -> void:
	var p := visual.poser
	p.velocity = velocity
	p.grounded = is_on_floor() or state == State.GLIDING
	p.aim_dir = (aim_point - get_eye_position()).normalized() if aim_point.distance_squared_to(get_eye_position()) > 1.0 else look_direction()
	p.crouch = _crouch
	p.gliding = state == State.GLIDING or state == State.FREEFALL
	p.armed = current_weapon() != null and not swimming
	p.reload_progress = reload_progress()
	_recoil = move_toward(_recoil, 0.0, delta * 6.0)
	p.recoil = _recoil


func _on_footstep(hop: bool) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null or cam.global_position.distance_squared_to(global_position) > 45.0 * 45.0:
		return
	var vol := -12.0 if is_player else -16.0
	if want_crouch:
		vol -= 8.0
	Audio.play_at(&"hop" if hop else &"footstep_grass", global_position, vol + (2.0 if hop else 0.0), 0.12)


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
		_trigger_held = want_fire
		return
	_bloom = move_toward(_bloom, 0.0, delta * (w.data.bloom_max_deg * 1.5 + 1.0))
	if _reload_timer >= 0.0:
		_reload_timer -= delta
		if _reload_timer < 0.0:
			_finish_reload()
	var can_shoot := state == State.GROUND and not swimming and _equip_timer <= 0.0 and _reload_timer < 0.0 \
		and not (visual.trick and visual.trick.blocks_fire())
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
		return
	if gore_ok and info.bone_role != &"" and info.bone_role not in [&"chest", &"spine", &"hips"]:
		if randf() < p:
			visual.dismember(info.bone_role, push + Vector3.UP * 1.5)


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
