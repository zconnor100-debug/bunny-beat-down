extends TestCase
## Moving like a critter: crouch → crawl → stand on one button, sprinting while
## aiming, long unhurried strides, legs hanging (not running) under a glider,
## the club on R3 with a gun out, L3 + R3 for first person (one gun in view),
## a light aim assist on the pad, paws gripping the glider, and giant glowing
## lucky clovers and shield acorns. Input goes through Input like a real
## keyboard or pad's.

const BUN := "res://data/critters/bun.tres"
const ROSTER := ["bun", "bandit_bunny", "squirrel", "fox", "raccoon", "frog", "beaver", "hamster"]

var player: Critter
var pc: PlayerController
var rig: CameraRig


func before_each() -> void:
	make_arena(120.0)
	player = spawn_critter(BUN, Vector3(0, 0.1, 0), 0.0)
	pc = PlayerController.new()
	pc.name = "PlayerController"
	player.add_child(pc)
	rig = CameraRig.new()
	add_child(rig)
	rig.set_target(player)
	rig.first_person = false
	pc.rig = rig
	rig.yaw = 0.0
	rig.pitch = 0.0
	await wait_physics(5)


func after_each() -> void:
	GameInput.using_pad = false
	for a in [&"move_forward", &"sprint", &"aim"]:
		Input.action_release(a)
	await super()


func _action(action: StringName) -> void:
	for down in [true, false]:
		var e := InputEventAction.new()
		e.action = action
		e.pressed = down
		Input.parse_input_event(e)
		await wait_frames(2)


func _pad_down(button: JoyButton, down := true) -> void:
	var e := InputEventJoypadButton.new()
	e.button_index = button
	e.pressed = down
	Input.parse_input_event(e)


func _flat_speed(c: Critter) -> float:
	return Vector2(c.velocity.x, c.velocity.z).length()


func test_crouch_button_cycles_crouch_crawl_stand() -> void:
	var stand_h := ((player.get_node("Body") as CollisionShape3D).shape as CapsuleShape3D).height
	await _action(&"crouch")
	await wait_physics(20)
	check(pc.stance == PlayerController.Stance.CROUCH and player.crouch_amount() > 0.9, "one press: crouched")
	await _action(&"crouch")
	await wait_physics(40)
	check(pc.stance == PlayerController.Stance.PRONE and player.prone_amount() > 0.95, "second press: lying down")
	var cap := (player.get_node("Body") as CollisionShape3D).shape as CapsuleShape3D
	check(cap.height < stand_h * 0.5, "lying down, the body is a low lump (%.2f m of %.2f)" % [cap.height, stand_h])
	var up_axis := (player.visual.model.transform.basis.y).normalized()
	check(up_axis.dot(Vector3.FORWARD) > 0.9, "the model is tipped onto its belly, head first")
	var head_h := player.visual.bone_world_position(&"head").y - player.global_position.y
	check(head_h < player.visual.rig.world_head_top * 0.4, "the head is down by the grass (%.2f m)" % head_h)
	# crawl forward: slow, with the elbows-and-knees cycle running and no footsteps
	var steps := [0]
	player.visual.poser.footstep.connect(func(_hop): steps[0] += 1)
	Input.action_press(&"move_forward")
	var phase0: float = player.visual.poser._phase
	await wait_physics(60)
	var crawl := _flat_speed(player)
	check_near(crawl, player.def.move_speed * Critter.PRONE_SPEED, 0.4, "crawling speed")
	check(not is_equal_approx(player.visual.poser._phase, phase0), "the crawl cycle runs")
	check(player.visual.poser._crawl > 0.8, "paws and knees work at full stroke, not a slide (%.2f)" % player.visual.poser._crawl)
	check(steps[0] == 0, "no footsteps while crawling")
	Input.action_release(&"move_forward")
	await _action(&"crouch")
	await wait_physics(40)
	check(pc.stance == PlayerController.Stance.STAND and player.prone_amount() < 0.05 and player.crouch_amount() < 0.05, "third press: standing")
	check_near(cap.height, stand_h, 0.02, "full height again")
	# jumping from the ground gets you up instead
	await _action(&"crouch")
	await _action(&"crouch")
	await wait_physics(30)
	await _action(&"jump")
	await wait_physics(30)
	check(pc.stance == PlayerController.Stance.STAND and player.prone_amount() < 0.05, "jump stands you up from a crawl")


func test_sprint_while_aiming() -> void:
	player.give_weapon(WeaponInstance.new(WeaponDB.get_weapon(&"carrot_rifle")))
	await wait_physics(30)   # equip
	Input.action_press(&"aim")
	Input.action_press(&"move_forward")
	await wait_physics(40)
	var aim_walk := _flat_speed(player)
	Input.action_press(&"sprint")
	await wait_physics(40)
	var aim_run := _flat_speed(player)
	check(pc.rig.aiming, "still aiming")
	check(aim_run > aim_walk * 1.8, "sprinting while aiming (%.1f m/s vs %.1f walking)" % [aim_run, aim_walk])


func test_strides_are_long_and_unhurried() -> void:
	# a step rate a little under a brisk human walk, even though critters are fast
	for id in ROSTER:
		var c := spawn_critter("res://data/critters/%s.tres" % id, Vector3(-40, 0.1, 40), 0.0)
		await wait_physics(3)
		c.move_input = Vector2(0, 1)
		await wait_physics(40)
		var p := c.visual.poser
		var cycles := 0.0
		var last: float = p._phase
		for i in 60:
			await wait_physics(1)
			cycles += fposmod(p._phase - last, TAU) / TAU
			last = p._phase
		var steps_per_s := cycles * (1.0 if c.def.gait == CritterDef.Gait.HOP else 2.0)
		check(steps_per_s < 2.6, "%s: %.2f %s per second at %.1f m/s" % [id, steps_per_s, "hops" if c.def.gait == CritterDef.Gait.HOP else "steps", _flat_speed(c)])
		c.queue_free()
		await wait_physics(1)


func test_legs_hang_under_the_glider() -> void:
	var c := spawn_critter(BUN, Vector3(30, 0.1, 30), 0.0)
	await wait_physics(3)
	c.begin_freefall(Vector3(30, 60, 30), Vector3.ZERO)
	c.want_jump = true
	await wait_physics(3)
	check(c.state == Critter.State.GLIDING, "the glider is open")
	var steps := [0]
	c.visual.poser.footstep.connect(func(_hop): steps[0] += 1)
	c.move_input = Vector2(1, 0)   # steer right
	await wait_physics(70)
	check(_flat_speed(c) > Critter.GLIDE_SPEED * 0.6, "gliding along (%.1f m/s)" % _flat_speed(c))
	check(c.visual.poser._move < 0.05, "legs hang still instead of running on air (%.2f)" % c.visual.poser._move)
	check(steps[0] == 0, "no footsteps in the air")
	# the canopy (and the critter under it) leans toward the steer: world +X
	var lean := c.visual._glider.global_basis.y.normalized().x
	check(lean > 0.2, "leaning into the steer (%.2f)" % lean)
	c.move_input = Vector2(-1, 0)
	await wait_physics(160)   # (the glide takes a couple of seconds to turn round)
	lean = c.visual._glider.global_basis.y.normalized().x
	check(lean < -0.2, "and the other way (%.2f)" % lean)
	var body_up := (c.visual.model.global_basis.y).normalized().x
	check(body_up < -0.2, "the body leans with it (%.2f)" % body_up)


func test_let_go_of_the_glider_to_drop_faster_and_open_it_again() -> void:
	var c := spawn_critter(BUN, Vector3(30, 0.1, 30), 0.0)
	await wait_physics(3)
	c.begin_freefall(Vector3(30, 140, 30), Vector3.ZERO)
	c.want_jump = true
	await wait_physics(3)
	check(c.state == Critter.State.GLIDING and c.has_glided, "the glider is open")
	var glider := c.visual._glider_path
	await wait_physics(30)
	var gliding_fall := -c.velocity.y
	c.want_jump = true
	await wait_physics(2)
	check(c.state == Critter.State.FREEFALL, "Jump while gliding lets go of it")
	await wait_physics(60)
	check(-c.velocity.y > gliding_fall * 2.0, "and drops faster (%.1f m/s, gliding %.1f)" % [-c.velocity.y, gliding_fall])
	check(c._height_above_ground() > Critter.AUTO_GLIDE_HEIGHT or c.state == Critter.State.FREEFALL,
		"it doesn't snap open again at the usual height once you've let go")
	c.want_jump = true
	await wait_physics(2)
	check(c.state == Critter.State.GLIDING and c.visual._glider_path == glider, "Jump opens the same glider again")
	# let go once more, and it still opens by itself just above the ground
	await wait_physics(int(Critter.GLIDER_TOGGLE * 60) + 2)
	c.want_jump = true
	await wait_physics(2)
	var lowest := INF
	for i in 400:
		await wait_physics(1)
		if c.state == Critter.State.FREEFALL:
			lowest = minf(lowest, c._height_above_ground())
		if c.state != Critter.State.FREEFALL:
			break
	check(c.state == Critter.State.GLIDING or c.state == Critter.State.GROUND, "it opened before the ground")
	check(lowest >= Critter.LAST_CALL_HEIGHT - 3.0, "no lower than the last call (%.1f m)" % lowest)


func test_paws_hold_the_glider_handle() -> void:
	for id in ["hamster", "frog", "fox"]:
		var c := spawn_critter("res://data/critters/%s.tres" % id, Vector3(30, 0.1, 30), 0.0)
		await wait_physics(3)
		c.begin_freefall(Vector3(30, 80, 30), Vector3.ZERO)
		c.want_jump = true
		await wait_physics(40)
		var handle: Vector3 = c.visual._glider.global_position
		var reach := 0.0
		for side in ["l", "r"]:
			reach = maxf(reach, c.visual.bone_world_position(StringName(side + "_hand")).distance_to(handle))
		check(reach < 0.25 * c.visual.rig.world_scale, "%s: both paws on the handle (%.2f m off)" % [id, reach])
		c.queue_free()
		await wait_physics(1)


func test_first_person_shows_one_gun() -> void:
	rig.first_person = true
	rig.set_target(player)
	await wait_frames(3)
	# a gun picked up while already looking out of the critter's eyes
	player.give_weapon(WeaponInstance.new(WeaponDB.get_weapon(&"carrot_rifle")))
	await wait_frames(5)
	var body_gun := ModelUtil.find_all(player.visual.weapon_model, "GeometryInstance3D")
	check(not body_gun.is_empty() and body_gun.all(func(g): return (g as GeometryInstance3D).cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY),
		"the gun in the body's paws only casts a shadow")
	check(rig._viewmodel != null and rig._viewmodel_root.visible, "the first-person gun is the one you see")
	# and after a club swing puts it back in the paws
	player.want_melee = true
	await wait_physics(int((Critter.MELEE_TIME + Critter.QUICK_KEEP) * 60.0) + 10)
	check(player.visual.club_model == null, "club put away")
	check(ModelUtil.find_all(player.visual.weapon_model, "GeometryInstance3D").all(func(g): return (g as GeometryInstance3D).cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY),
		"still hidden from the camera after the swing")
	rig.first_person = false
	rig.set_target(player)
	await wait_frames(3)
	check(ModelUtil.find_all(player.visual.weapon_model, "GeometryInstance3D").all(func(g): return (g as GeometryInstance3D).cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON),
		"back in third person the body's gun shows again")


func test_r3_swings_the_club_even_with_a_gun() -> void:
	player.give_weapon(WeaponInstance.new(WeaponDB.get_weapon(&"carrot_shotgun")))
	await wait_physics(30)
	_pad_down(JOY_BUTTON_RIGHT_STICK)
	await wait_frames(2)
	_pad_down(JOY_BUTTON_RIGHT_STICK, false)
	await wait_physics(int(GameInput.CHORD_SECONDS * 60.0) + 6)
	check(player.is_swinging() and player.visual.club_model != null, "R3 swings the club with a shotgun in the paws")
	check(not player.visual.weapon_model.visible, "the shotgun is stowed for the swing")
	await wait_physics(60)
	check(player.visual.club_model == null and player.visual.weapon_model.visible, "and comes back after")


func test_l3_plus_r3_flips_first_person() -> void:
	var was := rig.first_person
	_pad_down(JOY_BUTTON_RIGHT_STICK)
	await wait_frames(1)
	_pad_down(JOY_BUTTON_LEFT_STICK)
	await wait_frames(2)
	_pad_down(JOY_BUTTON_RIGHT_STICK, false)
	_pad_down(JOY_BUTTON_LEFT_STICK, false)
	await wait_physics(20)
	check(rig.first_person != was, "L3 + R3 together toggles first person")
	check(not player.is_swinging() and player.visual.club_model == null, "and doesn't swing the club")
	check(not player.want_sprint, "or start a sprint")
	# the other order (L3 first) works too and toggles back
	_pad_down(JOY_BUTTON_LEFT_STICK)
	await wait_frames(1)
	_pad_down(JOY_BUTTON_RIGHT_STICK)
	await wait_frames(2)
	_pad_down(JOY_BUTTON_LEFT_STICK, false)
	_pad_down(JOY_BUTTON_RIGHT_STICK, false)
	await wait_physics(20)
	check(rig.first_person == was, "L3 then R3 toggles back")
	check(not player.is_swinging(), "still no swing")
	rig.first_person = was


## Puts `foe` (feet on the ground) so the crosshair ray passes `off` metres to
## the left of its chest: the camera is first pitched to cross chest height 16 m out.
func _beside_the_crosshair(foe: Critter, off: float) -> void:
	rig.yaw = 0.0
	rig.pitch = atan2(foe.chest_height() - rig.camera.global_position.y, 16.0)
	await wait_frames(2)
	var cam := rig.camera.global_transform
	var spot := cam.origin - cam.basis.z * 16.0 - cam.basis.x * off
	foe.place_at(Vector3(spot.x, 0.1, spot.z), PI)
	await wait_physics(3)


func _miss(foe: Critter) -> float:
	var fwd := -rig.camera.global_basis.z
	var to := foe.get_chest_position() - rig.camera.global_position
	return (to - fwd * to.dot(fwd)).length()


func test_aim_assist_drifts_onto_a_nearby_target() -> void:
	player.give_weapon(WeaponInstance.new(WeaponDB.get_weapon(&"carrot_rifle")))
	var foe := spawn_critter(BUN, Vector3(30, 0.1, -16.0), PI)
	await wait_physics(30)
	GameInput.using_pad = true
	await _beside_the_crosshair(foe, 1.4)
	var before := _miss(foe)
	await wait_physics(90)
	check(pc.assist_target == foe, "the opponent near the crosshair is picked up by the assist")
	check(_miss(foe) < before - 0.4, "the aim drifts onto the body (%.2f → %.2f m)" % [before, _miss(foe)])
	# out past 2 m: no help
	await _beside_the_crosshair(foe, 3.5)
	var yaw := rig.yaw
	await wait_physics(60)
	check(pc.assist_target == null and is_equal_approx(rig.yaw, yaw), "nothing beyond %.0f m from the crosshair" % PlayerController.ASSIST_RADIUS)
	# and never on the keyboard / mouse
	GameInput.using_pad = false
	await _beside_the_crosshair(foe, 1.4)
	yaw = rig.yaw
	await wait_physics(60)
	check(is_equal_approx(rig.yaw, yaw), "no aim assist with a mouse")


func test_lucky_clovers_are_big_and_glow() -> void:
	var p := Pickup.spawn(self, Pickup.clover_spec(1), Vector3(5, 0.5, 0))
	await wait_physics(5)
	var model := p._spin.get_child(0) as Node3D
	var h := ModelUtil.aabb_of(model).size.y * model.scale.y
	var bun_h := player.visual.rig.world_head_top
	check_near(h / bun_h, 0.5, 0.06, "a clover stands half as tall as a Bun (%.2f m)" % h)
	var glowing := ModelUtil.find_all(model, "GeometryInstance3D").all(func(g): return (g as GeometryInstance3D).material_overlay != null)
	check(glowing, "it glows (overlay on every mesh)")
	var lights := p.find_children("*", "OmniLight3D", false, false)
	check(lights.size() == 1 and (lights[0] as OmniLight3D).light_color.g > 0.8, "with a green light")


func test_shields_are_big_glowing_acorns() -> void:
	var p := Pickup.spawn(self, Pickup.armor_spec(50.0), Vector3(-5, 0.5, 0))
	await wait_physics(5)
	var model := p._spin.get_child(0) as MeshInstance3D
	check(model != null and model.name == "AcornShield", "a shield is an acorn")
	var h := ModelUtil.aabb_of(model).size.y
	check_near(h, Pickup.CLOVER_HEIGHT, 0.1, "as tall as a lucky clover (%.2f m)" % h)
	var nut := model.get_surface_override_material(0)
	check(nut != null and nut.next_pass is ShaderMaterial, "the nut glows")
	var lights := p.find_children("*", "OmniLight3D", false, false)
	check(lights.size() == 1 and (lights[0] as OmniLight3D).light_color.r > 0.9 and (lights[0] as OmniLight3D).light_color.b < 0.3, "with an orange light")
	check(p.label().begins_with("Acorn Shield"), "called an Acorn Shield")
