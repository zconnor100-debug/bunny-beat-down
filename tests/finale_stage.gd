extends Node
## Stage for tests/capture_finale.gd: Bun against one bot. Bun walks about,
## rewinds, then wins the duel; the replay plays as in a real match.

var out_dir := "/tmp/bbd_finale"
var map := "island"
var game: Node
var mm: MatchManager
var _n := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for action in InputMap.get_actions():   # (pads drive every Godot window here)
		for e in InputMap.action_get_events(action):
			if e is InputEventJoypadButton or e is InputEventJoypadMotion:
				InputMap.action_erase_event(action, e)
	var settings: Node = get_node("/root/Settings")
	settings.set_value(&"seed", 4242, false)
	settings.set_value(&"map", map, false)
	settings.set_value(&"opponents", 1, false)
	settings.set_value(&"camera_mode", Settings.CameraMode.THIRD_PERSON, false)
	GameSession.replays_in_tests = true
	get_tree().change_scene_to_file("res://scenes/game.tscn")
	while game == null or game.get("hud") == null:
		await get_tree().process_frame
		game = get_tree().current_scene
	mm = game.match_manager
	var bun := mm.player
	var bot: Critter = mm.critters.filter(func(c): return c != bun)[0]
	await _wait(1.0)
	for c in mm.critters.duplicate():
		mm.dropship.eject(c)
	# a clear spot: Bun and the bot 14 m apart
	var spot := _ground(Vector3(20, 0, 20))
	for k in 24:
		var p := _ground(Vector3(cos(k * 0.9) * k * 9.0, 0, sin(k * 0.9) * k * 9.0))
		if _clear(p, p + Vector3(0, 0, -14)) and mm.island.water_level_at(p) < p.y - 0.5:
			spot = p
			break
	bun.get_node("PlayerController").process_mode = Node.PROCESS_MODE_DISABLED
	bot.get_node("AIBrain").process_mode = Node.PROCESS_MODE_DISABLED
	bun.place_at(spot, 0.0)
	bot.place_at(_ground(spot + Vector3(0, 0, -14)), PI)
	bun.give_weapon(WeaponInstance.new(WeaponDB.get_weapon(&"carrot_rifle"), Rarity.Tier.GOLDEN))
	bun.inventory.add_ammo(WeaponData.AmmoType.LIGHT, 120)
	bot.give_weapon(WeaponInstance.new(WeaponDB.get_weapon(&"carrot_pistol"), 0))
	game.rig.yaw = 0.0
	game.rig.pitch = -0.1
	while mm.phase != MatchManager.Phase.PLAYING:
		await get_tree().process_frame
	await _wait(1.5)
	# walk off to the side for a few seconds, then rewind
	bun.move_input = Vector2(1, 0)
	await _wait(3.0)
	bun.move_input = Vector2.ZERO
	await _snap("80_before_rewind")
	mm.time_keeper.rewind()
	await _wait(0.3)
	await _snap("81_rewinding")
	await _wait(0.35)
	await _snap("82_rewinding_later")
	while mm.time_keeper.playing_back:
		await get_tree().process_frame
	await _wait(0.5)
	await _snap("83_rewound")
	# the duel
	bun.place_at(spot, 0.0)
	bot.place_at(_ground(spot + Vector3(0, 0, -14)), PI)
	await _wait(1.6)
	var kc := mm.kill_cam
	var t0 := Time.get_ticks_msec()
	while bot.alive and Time.get_ticks_msec() - t0 < 15000:
		bun.aim_point = bot.get_chest_position()
		var d := (bun.aim_point - bun.get_eye_position()).normalized()
		bun.look_yaw = atan2(-d.x, -d.z)
		bun.look_pitch = asin(d.y)
		game.rig.yaw = bun.look_yaw
		bun.want_fire = (Time.get_ticks_msec() / 400) % 2 == 0   # bursts
		await get_tree().physics_frame
	bun.want_fire = false
	print("FINALE: bot down=%s, replay due=%s" % [not bot.alive, kc.has_final()])
	await _wait_real(0.4)
	await _snap("84_slow_motion")
	while not kc.playing and Time.get_ticks_msec() - t0 < 30000:
		await get_tree().process_frame
	for i in 12:
		await _wait_real(1.0)
		if not kc.playing:
			break
		await _snap("85_replay_%02d" % i)
	while kc.playing:
		await get_tree().process_frame
	await _wait_real(1.5)
	await _snap("86_end_screen")
	get_tree().quit()


func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


## Wall-clock wait (engine timers run on the paused engine's frame delta).
func _wait_real(s: float) -> void:
	var until := Time.get_ticks_msec() + int(s * 1000.0)
	while Time.get_ticks_msec() < until:
		await get_tree().process_frame


func _snap(name_: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out_dir, name_])
	print("snap ", name_)


func _ground(p: Vector3) -> Vector3:
	return Vector3(p.x, mm.island.terrain.height_at(p.x, p.z), p.z)


func _clear(a: Vector3, b: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(a + Vector3.UP * 1.0, b + Vector3.UP * 1.0, Layers.WORLD)
	return get_viewport().get_world_3d().direct_space_state.intersect_ray(q).is_empty()
