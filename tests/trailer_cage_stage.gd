extends "res://tests/trailer_stage.gd"
## The Hamster Cage cut of the trailer: the tin biplane, a climb up the
## Hamster Gym's see-through tubes, the rival creeping up the tube behind you
## on the top perch, the rewind running backwards, and the final shot in slow
## motion and replayed. Directed like the island cut, every piece is the real
## game. Started by tests/capture_trailer.gd with "cage" (see there).

const CAGE_SEED := 777

var gym: Building


func _run() -> void:
	_stills = [2.5, 6.0, 8.0, 10.0, 12.0, 13.5, 15.5, 17.0, 18.5, 20.0, 21.5, 23.0, 24.5, 26.0, 27.5, 29.0, 30.5, 32.0, 33.5]
	var settings: Node = get_tree().root.get_node("Settings")
	settings.set_value(&"quality", 2, false)
	settings.set_value(&"opponents", 1, false)     # (the rival: its beat-down is the final shot)
	settings.set_value(&"seed", CAGE_SEED, false)
	settings.set_value(&"map", "cage", false)
	settings.set_value(&"camera_mode", Settings.CameraMode.THIRD_PERSON, false)
	settings.set_value(&"player_character", "bun", false)
	if _portrait():
		settings.set_value(&"fov", 88.0, false)    # (a tall frame needs a wider lens)
	GameSession.replays_in_tests = true
	RivalBook.reset_for_tests()
	PlayerProfile.reset_for_tests()
	var fox: CritterDef = load("res://data/critters/fox.tres")
	var rival_name := ""
	for n in fox.names:
		if RivalBook.personality_of(n) == "sneak":
			rival_name = n
			break
	for i in 3:
		RivalBook.note_you_died_to(rival_name, "fox")
	for action in InputMap.get_actions():   # (pads drive every Godot window on the machine)
		for e in InputMap.action_get_events(action):
			if e is InputEventJoypadButton or e is InputEventJoypadMotion:
				InputMap.action_erase_event(action, e)
	get_tree().root.gui_disable_input = true
	get_tree().change_scene_to_file("res://scenes/game.tscn")
	while game == null or game.get("hud") == null:
		await get_tree().process_frame
		game = get_tree().current_scene
	mm = game.match_manager
	bun = mm.player
	vex = mm.critters.filter(func(c): return c != bun)[0]
	game.hud.visible = false
	game.set_process_unhandled_input(false)
	bun.get_node("PlayerController").process_mode = Node.PROCESS_MODE_DISABLED
	vex.get_node("AIBrain").process_mode = Node.PROCESS_MODE_DISABLED
	mm.time_keeper.offered.connect(game._offer_rewind)   # (automated runs don't ask by default)
	gym = game.island.buildings.filter(func(b): return String(b.name).begins_with("HamsterGym"))[0]
	_build_captions()
	print("TRAILER_START (rival %s)" % vex.display_name)

	# 1. the tin biplane, and the title
	_title.text = "BUNNY BEAT DOWN"
	_sub.text = "the Hamster Cage"
	_fade(_title, 1.0, 0.6)
	_fade(_sub, 1.0, 1.0)
	await _until(3.6)
	print("TRAILER_MUSIC_MATCH %s" % (Audio._music.stream.resource_path if Audio._music.stream else "none"))   # (for the credit)
	_fade(_title, 0.0, 0.3)
	_fade(_sub, 0.0, 0.3)
	await _until(4.0)

	# 2. up the Hamster Gym's tubes (the rival stays aboard for now, so the
	# match, and the rewind's memory, only starts on the top perch)
	var x := gym.global_transform
	var tube_lo := x * Vector3(8, 14, -7)       # from the middle perch...
	var tube_hi := x * Vector3(8, 21, -30)      # ...up to the top one
	var up_dir := (tube_hi - tube_lo)
	var flat := Vector3(up_dir.x, 0, up_dir.z).normalized()
	var climb_yaw := atan2(-flat.x, -flat.z)
	mm.dropship.eject(bun)
	_place_at(bun, tube_lo.lerp(tube_hi, 0.08) + Vector3.UP * 0.4, climb_yaw)
	bun.give_weapon(WeaponInstance.new(WeaponDB.get_weapon(&"carrot_rifle"), Rarity.Tier.GOLDEN))
	bun.inventory.add_ammo(WeaponData.AmmoType.LIGHT, 90)
	cam = Camera3D.new()
	cam.fov = 60.0 if not _portrait() else 80.0
	mm.world_root.add_child(cam)
	cam.make_current()
	var side := flat.cross(Vector3.UP).normalized()
	_lower.text = "The Hamster Gym: see-through tubes, all the way up"
	_fade(_lower, 1.0, 0.5)
	var climb := func():
		bun.look_yaw = climb_yaw
		bun.look_pitch = 0.1
		bun.move_input = Vector2(0, 1)
		# alongside the tube, looking in at Bun through the plastic
		var want := bun.global_position + side * 9.5 + Vector3.UP * 1.5 - flat * 3.0
		cam.global_position = cam.global_position.lerp(want, 0.2) if cam.global_position.distance_to(want) < 6.0 else want
		cam.look_at(bun.global_position + Vector3.UP * 1.3 + flat * 2.0, Vector3.UP)
	await _until(8.6, climb)
	_fade(_lower, 0.0, 0.4)
	# out onto the top perch: Bun looks out over the cage
	var perch := x * Vector3(8, 21.05, -36)
	var face_out := x.basis * Vector3(-1, 0, 0)
	var out_yaw := atan2(-face_out.x, -face_out.z)
	bun.move_input = Vector2.ZERO
	_place_at(bun, perch + face_out * 2.0, out_yaw)
	bun.look_yaw = out_yaw
	# 3. the rival comes up the tube behind
	mm.dropship.eject(vex)
	_place_at(vex, tube_lo.lerp(tube_hi, 0.78) + Vector3.UP * 0.4, climb_yaw)
	vex.give_weapon(WeaponInstance.new(WeaponDB.get_weapon(&"carrot_shotgun"), Rarity.Tier.PRIZE))
	vex.inventory.add_ammo(WeaponData.AmmoType.SHELLS, 30)
	while mm.phase != MatchManager.Phase.PLAYING:
		await _frame()
	_lower.text = "%s has beaten you down 3 times.\n%s remembers." % [vex.display_name, vex.display_name]
	_fade(_lower, 1.0, 0.5)
	var creep := func():
		vex.want_crouch = true
		var to := bun.global_position - vex.global_position
		vex.look_yaw = atan2(-to.x, -to.z)
		vex.look_pitch = 0.0
		vex.move_input = Vector2(0, 1) if to.length() > 5.5 else Vector2.ZERO
		_over_shoulder(vex, bun)
	await _until(_t + 2.0, creep)
	vex.visual.say(RivalBook.PERSONALITIES.sneak.spot[2].format({"you": bun.display_name}), 3.0)   # "Don't turn around, Bun."
	await _until(_t + 2.6, creep)
	_fade(_lower, 0.0, 0.4)
	# 4. the pounce: the killing blow freezes the match and asks
	vex.want_crouch = false
	vex.move_input = Vector2.ZERO
	bun.health = 12.0
	bun.armor = 0.0
	var t_shoot := _t
	while mm.time_keeper.pending == null and _t < t_shoot + 3.0:
		var aim := bun.get_chest_position()
		var to := aim - vex.get_eye_position()
		vex.look_yaw = atan2(-to.x, -to.z)
		vex.look_pitch = asin(clampf(to.normalized().y, -1.0, 1.0))
		vex.aim_point = aim
		vex.want_fire = true
		_over_shoulder(vex, bun)
		await _frame()
	vex.want_fire = false
	print("BEAT offer at %.1f" % _t)
	await _until(_t + 2.2)
	game.hud.visible = true   # (the rewind's tape effect lives on the HUD)
	game._answer_offer(true)
	game.rig.camera.make_current()
	game.rig.yaw = out_yaw
	game.rig.pitch = -0.15
	while mm.time_keeper.playing_back:
		await _frame()
	game.hud.visible = false
	print("BEAT rewound at %.1f" % _t)

	# 5. ten seconds earlier, and this time Bun turns around
	bun.look_yaw = out_yaw
	var t_rw := _t
	await _until(t_rw + 1.0, creep_quiet.bind(vex, bun))
	var turn := func():
		creep_quiet(vex, bun)
		var d: Vector3 = (vex.get_chest_position() - bun.get_eye_position()).normalized()
		game.rig.yaw = lerp_angle(game.rig.yaw, atan2(-d.x, -d.z), 0.1)
		game.rig.pitch = lerpf(game.rig.pitch, asin(d.y), 0.1)
		bun.look_yaw = game.rig.yaw
		bun.look_pitch = game.rig.pitch
		bun.aim_point = vex.get_chest_position()
	await _until(t_rw + 2.2, turn)
	vex.move_input = Vector2.ZERO
	vex.visual.say("...!", 1.5)
	vex.health = minf(vex.health, 40.0)
	# the burst that ends it: the final shot, slowed down and replayed
	while vex.alive and _t < t_rw + 6.0:
		turn.call()
		bun.want_fire = true
		await _frame()
	bun.want_fire = false
	print("BEAT kill at %.1f" % _t)
	var kc := mm.kill_cam
	while not kc.playing and _t < t_rw + 12.0:
		await _frame()
	print("BEAT replay start at %.1f" % _t)
	while kc.playing:
		await _frame()
	# the end screen, then the card
	print("BEAT replay end at %.1f" % _t)

	await _until(_t + 2.4)
	_card.visible = true
	_fade(_card, 1.0, 0.6)
	_title.text = "BUNNY BEAT DOWN"
	_sub.text = "A survival roguelike: one bunny, 49 bots who remember you.\nFree and open source · github.com/zconnor100-debug/bunny-beat-down"
	if _portrait():
		_sub.text = "A survival roguelike:\none bunny, 49 bots who remember you.\n\nFree and open source\ngithub.com/zconnor100-debug/bunny-beat-down"
	_fade(_title, 1.0, 0.6)
	_fade(_sub, 1.0, 0.8)
	await _until(_t + 3.6)
	print("TRAILER_END (%.1f s)" % _t)
	print("TRAILER_MUSIC %s" % (Audio._music.stream.resource_path if Audio._music.stream else "none"))
	get_tree().quit()


func _place_at(c: Critter, p: Vector3, yaw: float) -> void:
	c.place_at(p, yaw)
	c.velocity = Vector3.ZERO
	c._set_state(Critter.State.GROUND)
