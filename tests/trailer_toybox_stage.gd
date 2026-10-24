extends "res://tests/trailer_stage.gd"
## The Toy Box Bash cut of the trailer: the paper airplane, Bun riding the toy
## train round the bedroom, the rival on the car behind, the rewind running
## the whole train backwards, and the final shot slowed down and replayed.
## Directed like the island cut, every piece is the real game. Started by
## tests/capture_trailer.gd with "toybox" (see there).

const TOY_SEED := 4242
const RIDE_CAR := 3                ## Bun's open car; the rival rides the one behind


func _run() -> void:
	_stills = [2.5, 6.0, 8.5, 10.5, 12.0, 13.5, 15.5, 17.0, 18.5, 20.0, 21.5, 23.0, 24.5, 26.0, 27.5, 29.0, 30.5, 32.0, 33.5]
	var settings: Node = get_tree().root.get_node("Settings")
	settings.set_value(&"quality", 2, false)
	settings.set_value(&"opponents", 1, false)     # (the rival: its beat-down is the final shot)
	settings.set_value(&"seed", TOY_SEED, false)
	settings.set_value(&"map", "toybox", false)
	settings.set_value(&"camera_mode", Settings.CameraMode.THIRD_PERSON, false)
	settings.set_value(&"player_character", "bun", false)
	if _portrait():
		settings.set_value(&"fov", 88.0, false)
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
	var train: ToyTrain = game.island.train
	_build_captions()
	print("TRAILER_START (rival %s)" % vex.display_name)

	# 1. the paper airplane, and the title
	_title.text = "BUNNY BEAT DOWN"
	_sub.text = "Toy Box Bash"
	_fade(_title, 1.0, 0.6)
	_fade(_sub, 1.0, 1.0)
	await _until(3.6)
	print("TRAILER_MUSIC_MATCH %s" % (Audio._music.stream.resource_path if Audio._music.stream else "none"))   # (for the credit)
	_fade(_title, 0.0, 0.3)
	_fade(_sub, 0.0, 0.3)
	await _until(4.0)

	# 2. all aboard the toy train (the rival stays on the plane for now, so the
	# match, and the rewind's memory, only starts once both are riding)
	var car := train.cars[RIDE_CAR]
	mm.dropship.eject(bun)
	_board(bun, car)
	bun.give_weapon(WeaponInstance.new(WeaponDB.get_weapon(&"carrot_rifle"), Rarity.Tier.GOLDEN))
	bun.inventory.add_ammo(WeaponData.AmmoType.LIGHT, 90)
	cam = Camera3D.new()
	cam.fov = 60.0 if not _portrait() else 80.0
	mm.world_root.add_child(cam)
	cam.make_current()
	_lower.text = "Toy Box Bash: hop on the toy train"
	_fade(_lower, 1.0, 0.5)
	var ride := func():
		var fwd := -car.global_basis.z
		bun.look_yaw = atan2(-fwd.x, -fwd.z)
		bun.look_pitch = 0.0
		# alongside the train on the room's side, keeping pace with it
		var inward := Vector3(-car.global_position.x, 0, -car.global_position.z).normalized()
		var side := fwd.cross(Vector3.UP).normalized()
		if side.dot(inward) < 0.0:
			side = -side
		cam.global_position = car.global_position + side * 12.0 + Vector3.UP * 5.0 + fwd * 4.0
		cam.look_at(bun.global_position + Vector3.UP * 1.4, Vector3.UP)
	await _until(9.4, ride)
	_fade(_lower, 0.0, 0.4)

	# 3. the rival boards the car behind
	var back_car := train.cars[RIDE_CAR + 1]
	mm.dropship.eject(vex)
	_board(vex, back_car)
	vex.give_weapon(WeaponInstance.new(WeaponDB.get_weapon(&"carrot_shotgun"), Rarity.Tier.PRIZE))
	vex.inventory.add_ammo(WeaponData.AmmoType.SHELLS, 30)
	while mm.phase != MatchManager.Phase.PLAYING:
		ride.call()
		await _frame()
	_lower.text = "%s has beaten you down 3 times.\n%s remembers." % [vex.display_name, vex.display_name]
	_fade(_lower, 1.0, 0.5)
	var lurk := func():
		vex.want_crouch = true
		var fwd := -car.global_basis.z
		bun.look_yaw = atan2(-fwd.x, -fwd.z)
		var to := bun.global_position - vex.global_position
		vex.look_yaw = atan2(-to.x, -to.z)
		vex.look_pitch = 0.0
		_shoulder_cam(vex, bun)
	await _until(_t + 1.6, lurk)
	vex.visual.say(RivalBook.PERSONALITIES.sneak.spot[2].format({"you": bun.display_name}), 3.0)   # "Don't turn around, Bun."
	await _until(_t + 2.4, lurk)
	_fade(_lower, 0.0, 0.4)
	# 4. the pounce: the killing blow freezes the match and asks
	vex.want_crouch = false
	bun.health = 12.0
	bun.armor = 0.0
	var t_shoot := _t
	print("BEAT shoot at %.1f" % _t)
	while mm.time_keeper.pending == null and _t < t_shoot + 4.0:
		var aim := bun.get_chest_position()
		var to := aim - vex.get_eye_position()
		vex.look_yaw = atan2(-to.x, -to.z)
		vex.look_pitch = asin(clampf(to.normalized().y, -1.0, 1.0))
		vex.aim_point = aim
		vex.want_fire = true
		var fwd := -car.global_basis.z
		bun.look_yaw = atan2(-fwd.x, -fwd.z)
		_shoulder_cam(vex, bun)
		await _frame()
	vex.want_fire = false
	print("BEAT offer at %.1f (on hold: %s)" % [_t, mm.time_keeper.pending != null])
	await _until(_t + 2.2)
	game.hud.visible = true   # (the rewind's tape effect lives on the HUD)
	game._answer_offer(true)
	game.rig.camera.make_current()
	game.rig.yaw = bun.look_yaw
	game.rig.pitch = -0.15
	while mm.time_keeper.playing_back:
		await _frame()
	game.hud.visible = false
	print("BEAT rewound at %.1f" % _t)

	# 5. ten seconds earlier, and this time Bun turns around
	var t_rw := _t
	var face := func():
		var fwd := -car.global_basis.z
		bun.look_yaw = atan2(-fwd.x, -fwd.z)
		game.rig.yaw = bun.look_yaw
	vex.want_crouch = true
	await _until(t_rw + 0.8, face)
	var turn := func():
		var d: Vector3 = (vex.get_chest_position() - bun.get_eye_position()).normalized()
		game.rig.yaw = lerp_angle(game.rig.yaw, atan2(-d.x, -d.z), 0.12)
		game.rig.pitch = lerpf(game.rig.pitch, asin(d.y), 0.12)
		bun.look_yaw = game.rig.yaw
		bun.look_pitch = game.rig.pitch
		bun.aim_point = vex.get_chest_position()
	await _until(t_rw + 2.0, turn)
	vex.visual.say("...!", 1.5)
	vex.want_crouch = false   # (caught: he stands up out of the box car, in full view)
	vex.health = minf(vex.health, 40.0)
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
	print("BEAT replay end at %.1f" % _t)
	# the end screen, then the card
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


## Stand a critter on an open car of the moving train, facing forward.
func _board(c: Critter, car: AnimatableBody3D) -> void:
	var fwd := -car.global_basis.z
	c.place_at(car.global_position + Vector3.UP * (ToyTrain.DECK + 0.4), atan2(-fwd.x, -fwd.z))
	c.velocity = Vector3.ZERO
	c._set_state(Critter.State.GROUND)


## Over `c`'s shoulder at `at`, placed outright every frame (they're both
## riding a train at 15 m/s: easing would trail behind).
func _shoulder_cam(c: Critter, at: Critter) -> void:
	var h := c.visual.rig.world_head_top if c.visual.rig else 1.5
	var to := at.global_position - c.global_position
	to.y = 0.0
	var f := to.normalized()
	var side := f.cross(Vector3.UP)
	cam.global_position = c.global_position - f * (h * 1.3 + 1.6) + side * (h * 0.55) + Vector3.UP * (h * 0.95)
	cam.look_at(at.global_position + Vector3.UP * 0.9 - side * 0.3, Vector3.UP)
