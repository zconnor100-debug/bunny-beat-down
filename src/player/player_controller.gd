class_name PlayerController
extends Node
## Reads mouse/keyboard/gamepad and writes the owning Critter's intent.
## Recoil is applied to the real aim (not just the camera), and anything
## interactable under the crosshair is surfaced to the HUD.

signal interact_hint_changed(text: String)

const PAD_LOOK_SPEED := 3.2       ## rad/s at full stick
const INTERACT_RANGE := 2.6

var critter: Critter
var rig: CameraRig
var enabled := true
var _focus: Node = null
var _hint := ""
var _jump_buffer := 0.0


func _ready() -> void:
	critter = get_parent() as Critter
	critter.is_player = true
	Events.shot_fired.connect(_on_shot)


func _unhandled_input(event: InputEvent) -> void:
	if not enabled or rig == null:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sens: float = deg_to_rad(Settings.get_value(&"mouse_sensitivity"))
		if rig.aiming:
			sens *= Settings.get_value(&"aim_sensitivity_scale")
		var inv := -1.0 if Settings.get_value(&"invert_y") else 1.0
		rig.yaw -= event.relative.x * sens
		rig.pitch = clampf(rig.pitch - event.relative.y * sens * inv, deg_to_rad(-80), deg_to_rad(80))
	elif event.is_action_pressed(&"toggle_camera"):
		rig.toggle_first_person()
	elif event.is_action_pressed(&"swap_shoulder"):
		rig.shoulder = -rig.shoulder
	if not critter.alive:
		return
	if event.is_action_pressed(&"reload"):
		critter.start_reload()
	elif event.is_action_pressed(&"weapon_1"):
		critter.switch_to(0)
	elif event.is_action_pressed(&"weapon_2"):
		critter.switch_to(1)
	elif event.is_action_pressed(&"weapon_3"):
		critter.switch_to(2)
	elif event.is_action_pressed(&"weapon_next"):
		critter.cycle_weapon(1)
	elif event.is_action_pressed(&"weapon_prev"):
		critter.cycle_weapon(-1)
	elif event.is_action_pressed(&"heal"):
		critter.use_clover()
	elif event.is_action_pressed(&"interact"):
		_interact()
	elif event.is_action_pressed(&"drop_weapon"):
		var w := critter.inventory.take_weapon(critter.current_slot)
		if w:
			critter.visual.set_weapon(null)
			Pickup.spawn(Despawner.debris_parent(critter), Pickup.weapon_spec(w), critter.get_chest_position() - critter.global_basis.z * 0.8, -critter.global_basis.z * 2.0 + Vector3.UP * 2.0)
	elif event.is_action_pressed(&"jump"):
		_jump_buffer = 0.15


func _physics_process(delta: float) -> void:
	if rig == null:
		return
	if not enabled or not critter.alive:
		critter.move_input = Vector2.ZERO
		critter.want_fire = false
		critter.want_aim = false
		return
	# gamepad look
	var look := Input.get_vector(&"look_left", &"look_right", &"look_down", &"look_up")
	if look.length_squared() > 0.0:
		var k := PAD_LOOK_SPEED * delta * (0.5 if rig.aiming else 1.0)
		look = look * look.length()   # response curve: fine control near the centre
		rig.yaw -= look.x * k
		rig.pitch = clampf(rig.pitch + look.y * k, deg_to_rad(-80), deg_to_rad(80))
	critter.move_input = Input.get_vector(&"move_left", &"move_right", &"move_back", &"move_forward")
	critter.look_yaw = rig.yaw
	critter.look_pitch = rig.pitch
	critter.want_fire = Input.is_action_pressed(&"fire") and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	critter.want_aim = Input.is_action_pressed(&"aim")
	var was_aiming := rig.aiming
	rig.aiming = critter.want_aim and critter.current_weapon() != null
	if rig.aiming and not was_aiming and critter.current_weapon().data.scoped:
		Audio.play(&"scope_in", -4.0)
	critter.want_sprint = Input.is_action_pressed(&"sprint")
	critter.want_crouch = Input.is_action_pressed(&"crouch")
	_jump_buffer -= delta
	if _jump_buffer > 0.0 and (critter.is_on_floor() or critter.state != Critter.State.GROUND):
		critter.want_jump = true
		_jump_buffer = 0.0
	critter.aim_point = rig.aim_point(critter.visual.hitbox_rids)
	_update_focus()
	# treasure chests: keep unlocking while interact is held
	if _focus is LootCrate and is_instance_valid(_focus) and Input.is_action_pressed(&"interact"):
		var crate := _focus as LootCrate
		if crate.open_time > 0.0 and crate.channel(critter, delta):
			_focus = null


func _on_shot(shooter: Node, _origin: Vector3, weapon_id: StringName) -> void:
	if shooter != critter or rig == null:
		return
	var data := WeaponDB.get_weapon(weapon_id)
	if data:
		var k := 0.55 if rig.aiming else 1.0
		rig.pitch = clampf(rig.pitch + deg_to_rad(data.recoil_pitch_deg) * 0.35 * k, deg_to_rad(-80), deg_to_rad(80))
		rig.yaw += deg_to_rad(data.recoil_yaw_deg) * randf_range(-0.35, 0.35) * k


## Finds the weapon pickup or crate the player is looking at.
func _update_focus() -> void:
	var best: Node = null
	var best_score := -1.0
	var eye := critter.get_eye_position()
	var fwd := -rig.camera.global_basis.z
	for group in [&"pickups", &"crates"]:
		for n in get_tree().get_nodes_in_group(group):
			var n3 := n as Node3D
			if n3 == null:
				continue
			if group == &"pickups" and not (n as Pickup).is_weapon():
				continue
			if group == &"crates" and (n as LootCrate).opened:
				continue
			var to := n3.global_position + Vector3.UP * 0.3 - eye
			var d := to.length()
			if d > INTERACT_RANGE * critter.visual.rig.world_scale + 0.8:
				continue
			var facing := to.normalized().dot(fwd)
			var score := facing * 2.0 - d * 0.3
			if facing > 0.3 and score > best_score:
				best_score = score
				best = n
	if best != _focus:
		_focus = best
		var text := ""
		if best is Pickup:
			text = "[%s] Pick up %s" % [GameInput.prompt(&"interact"), (best as Pickup).label()]
		elif best is LootCrate:
			var crate := best as LootCrate
			var key := GameInput.prompt(&"interact")
			text = "[%s] Open garden crate" % key if crate.open_time <= 0.0 \
				else "[Hold %s] Unlock %s (%d s)" % [key, crate.display_name, ceili(crate.open_time)]
		if text != _hint:
			_hint = text
			interact_hint_changed.emit(text)


func focused_crate() -> LootCrate:
	return _focus as LootCrate if is_instance_valid(_focus) else null


func focused_pickup() -> Pickup:
	return _focus as Pickup if is_instance_valid(_focus) else null


func _interact() -> void:
	if _focus == null or not is_instance_valid(_focus):
		return
	if _focus is Pickup:
		(_focus as Pickup).try_collect(critter)
	elif _focus is LootCrate:
		var crate := _focus as LootCrate
		if crate.open_time > 0.0:
			return   # treasure chests are unlocked by holding interact (see _physics_process)
		crate.open(critter)
	_focus = null
