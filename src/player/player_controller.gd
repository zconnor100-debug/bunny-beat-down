class_name PlayerController
extends Node
## Reads mouse/keyboard/gamepad and writes the owning Critter's intent.
## Recoil is applied to the real aim (not just the camera), and anything
## interactable under the crosshair is surfaced to the HUD.
## On a gamepad X picks up the gun (or works the crate) in front of you and
## reloads otherwise; A only jumps; B swings your club when your paws are empty; R3 swings it
## any time (the gun is stowed for the swing); L3 + R3 together flips first /
## third person. Crouch is a toggle: once to crouch, again to lie down and
## crawl, a third time (or jump, or sprint) to stand.

signal interact_hint_changed(text: String)

enum Stance { STAND, CROUCH, PRONE }

const PAD_LOOK_SPEED := 3.2       ## rad/s at full stick
const INTERACT_RANGE := 2.6
## Light aim assist (gamepad only): when the crosshair passes within this many
## metres of an opponent you can see, the stick slows down a little and the aim
## drifts gently onto them.
const ASSIST_RADIUS := 2.0
const ASSIST_RANGE := 140.0
const ASSIST_SLOWDOWN := 0.35     ## look speed lost right on target
const ASSIST_PULL := 2.2          ## 1/s: how fast the aim drifts onto the body

var critter: Critter
var rig: CameraRig
var enabled := true
var _focus: Node = null
var _hint := ""
var _jump_buffer := 0.0
var stance := Stance.STAND
var _sprint_latch := false         # pad: L3 clicks sprint on until you stop moving
var _latch_before := false         # (undone if that click was half of an L3 + R3 chord)
var _pad_pressed_at := {}          # button -> msec of its last press (for chords)
var _pending_melee := -1.0         # seconds until a pad R3 swing (it may yet be a chord)
var assist_target: Critter = null  ## who the aim assist is helping with (HUD / tests)


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
		return
	elif event.is_action_pressed(&"swap_shoulder"):
		rig.shoulder = -rig.shoulder
	if event is InputEventJoypadButton and event.pressed and _chord(event.button_index):
		rig.toggle_first_person()
		return
	if not critter.alive:
		return
	if event.is_action_pressed(&"interact") and _can_interact():
		_interact()   # (X on a pad: the pick-up wins over the reload)
	elif event.is_action_pressed(&"reload"):
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
	elif event.is_action_pressed(&"melee"):
		# a pad R3 waits a beat: with L3 it's the camera chord, not a swing
		_swing(CHORD_WAIT if event is InputEventJoypadButton else 0.0)
	elif event is InputEventJoypadButton and event.is_action_pressed(&"crouch") and critter.current_weapon() == null:
		_swing(0.0)
	elif event.is_action_pressed(&"crouch"):
		stance = ((stance + 1) % 3) as Stance
	elif event.is_action_pressed(&"sprint") and event is InputEventJoypadButton:
		_latch_before = _sprint_latch
		_sprint_latch = not _sprint_latch
		if _sprint_latch:
			stance = Stance.STAND
	elif event.is_action_pressed(&"jump") and stance != Stance.STAND:
		stance = Stance.STAND   # jump gets you up off the ground first
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
	var assist := _aim_assist_target() if GameInput.using_pad else {}
	if look.length_squared() > 0.0:
		var k := PAD_LOOK_SPEED * delta * (0.5 if rig.aiming else 1.0)
		if not assist.is_empty():
			k *= 1.0 - ASSIST_SLOWDOWN * float(assist.weight)
		look = look * look.length()   # response curve: fine control near the centre
		rig.yaw -= look.x * k
		rig.pitch = clampf(rig.pitch + look.y * k, deg_to_rad(-80), deg_to_rad(80))
	if not assist.is_empty():
		_assist_pull(assist, delta)
	critter.move_input = Input.get_vector(&"move_left", &"move_right", &"move_back", &"move_forward")
	if _pending_melee >= 0.0:
		_pending_melee -= delta
		if _pending_melee < 0.0:
			critter.want_melee = true
	critter.look_yaw = rig.yaw
	critter.look_pitch = rig.pitch
	critter.want_fire = Input.is_action_pressed(&"fire") and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	critter.want_aim = Input.is_action_pressed(&"aim")
	var was_aiming := rig.aiming
	rig.aiming = critter.want_aim and critter.current_weapon() != null
	if rig.aiming and not was_aiming and critter.current_weapon().data.scoped:
		Audio.play(&"scope_in", -4.0)
	# sprint: hold SHIFT, or click L3 and keep running (even while aiming)
	if critter.move_input.length() < 0.2:
		_sprint_latch = false
	var sprint_key := Input.is_action_pressed(&"sprint") and not GameInput.using_pad
	critter.want_sprint = sprint_key or _sprint_latch
	if critter.want_sprint and critter.move_input.length() > 0.2:
		stance = Stance.STAND
	if critter.swimming or critter.state != Critter.State.GROUND:
		stance = Stance.STAND
	critter.want_crouch = stance == Stance.CROUCH
	critter.want_prone = stance == Stance.PRONE
	_jump_buffer -= delta
	if _jump_buffer > 0.0 and (critter.is_on_floor() or critter.state != Critter.State.GROUND):
		critter.want_jump = true
		_jump_buffer = 0.0
	critter.aim_point = rig.aim_point(critter.visual.hitbox_rids)
	_update_focus()
	# treasure chests: keep unlocking while interact (X on a pad) is held
	var holding := Input.is_action_pressed(&"interact")
	if _focus is LootCrate and is_instance_valid(_focus) and holding:
		var crate := _focus as LootCrate
		if crate.open_time > 0.0 and crate.channel(critter, delta):
			_focus = null


const CHORD_WAIT := GameInput.CHORD_SECONDS


## Swing the club (after `wait` seconds). Lying down, get up first.
func _swing(wait: float) -> void:
	if stance == Stance.PRONE:
		stance = Stance.STAND
		wait = maxf(wait, 0.45)
	if wait <= 0.0:
		critter.want_melee = true
	else:
		_pending_melee = wait


## True when `button` completes a chord (both buttons of a pair pressed within
## GameInput.CHORD_SECONDS); whatever the first half started is taken back.
func _chord(button: JoyButton) -> bool:
	var now := Time.get_ticks_msec()
	_pad_pressed_at[button] = now
	for pair in GameInput.CHORDS:
		if not button in pair:
			continue
		var other: JoyButton = pair[0] if button == pair[1] else pair[1]
		if now - int(_pad_pressed_at.get(other, -100000)) <= GameInput.CHORD_SECONDS * 1000.0:
			_pad_pressed_at.erase(other)
			_pad_pressed_at.erase(button)
			_pending_melee = -1.0
			if JOY_BUTTON_LEFT_STICK in pair:
				_sprint_latch = _latch_before
			return true
	return false


## The opponent nearest the crosshair ray, if the ray passes within
## ASSIST_RADIUS of their body and nothing solid is in the way:
## {critter, point (nearest point on their body), weight (1 on target … 0 at the edge)}.
func _aim_assist_target() -> Dictionary:
	assist_target = null
	if critter.current_weapon() == null or rig.camera == null:
		return {}
	var origin := rig.camera.global_position
	var fwd := -rig.camera.global_basis.z
	var best := {}
	var best_d := ASSIST_RADIUS
	for n in get_tree().get_nodes_in_group(&"critters"):
		var c := n as Critter
		if c == null or c == critter or not c.alive or c.state != Critter.State.GROUND:
			continue
		var feet := c.global_position
		var head := feet + Vector3.UP * c.chest_height() / 0.6
		var along := (c.get_chest_position() - origin).dot(fwd)
		if along < 1.0 or along > ASSIST_RANGE:
			continue
		# nearest points between the aim ray and the body's centre line
		var pts := Geometry3D.get_closest_points_between_segments(origin, origin + fwd * ASSIST_RANGE, feet + Vector3.UP * 0.2, head)
		var d := (pts[0] as Vector3).distance_to(pts[1])
		if d >= best_d:
			continue
		var q := PhysicsRayQueryParameters3D.create(origin, pts[1], Layers.WORLD)
		if critter.get_world_3d().direct_space_state.intersect_ray(q):
			continue
		best_d = d
		best = {"critter": c, "point": pts[1], "weight": clampf(1.0 - d / ASSIST_RADIUS, 0.0, 1.0)}
	if not best.is_empty():
		assist_target = best.critter
	return best


## Drift the aim onto the body (only as far as its outline: no tug off the head).
func _assist_pull(assist: Dictionary, delta: float) -> void:
	var to: Vector3 = (assist.point as Vector3) - rig.camera.global_position
	var body_r := 0.25 * (assist.critter as Critter).visual.rig.world_scale
	var fwd := -rig.camera.global_basis.z
	var miss := (to - fwd * to.dot(fwd)).length()
	if miss <= body_r:
		return
	var want_yaw := atan2(-to.x, -to.z)
	var want_pitch := asin(clampf(to.normalized().y, -1.0, 1.0))
	var k := (1.0 - exp(-ASSIST_PULL * (0.5 + 0.5 * float(assist.weight)) * delta)) * (1.0 - body_r / miss)
	rig.yaw += wrapf(want_yaw - rig.yaw, -PI, PI) * k
	rig.pitch = clampf(rig.pitch + (want_pitch - rig.pitch) * k, deg_to_rad(-80), deg_to_rad(80))


## Something right in front of you to pick up or open, on the ground.
func _can_interact() -> bool:
	return _focus != null and is_instance_valid(_focus) and critter.state == Critter.State.GROUND


## The button the pickup prompt names: X on a pad, E on the keyboard.
func _interact_key() -> String:
	return GameInput.prompt(&"interact")


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
	_focus = best
	var text := ""
	if best is Pickup:
		text = "[%s] Pick up %s" % [_interact_key(), (best as Pickup).label()]
	elif best is LootCrate:
		var crate := best as LootCrate
		var key := _interact_key()
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
