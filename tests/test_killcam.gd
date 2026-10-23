extends TestCase
## The final shot (KillCam): once few are left it records them; the last
## beat-down is caught with the carrot that did it; the slow motion and the
## three-angle replay show the recording (bones and all) with the world
## frozen; any button skips; and afterwards everything is exactly as it was.

const TEST_DEF := "res://data/critters/test_critter.tres"

var _kc: KillCam


func before_each() -> void:
	make_arena()
	add_child(FX.new())
	add_child(Projectiles.new())


func after_each() -> void:
	get_tree().paused = false
	Engine.time_scale = 1.0
	await super()


func _duel() -> Array[Critter]:
	var shooter := spawn_critter(TEST_DEF, Vector3(0, 0.1, 0))
	var victim := spawn_critter(TEST_DEF, Vector3(0, 0.1, -8))
	await wait_physics(3)
	_kc = KillCam.new()
	add_child(_kc)
	_kc.track(shooter)
	_kc.track(victim)
	KillCam.recording = true
	return [shooter, victim]


## Shoot until the victim goes down (the last one standing wins).
func _shoot_down(shooter: Critter, victim: Critter) -> void:
	var w := WeaponInstance.new(WeaponDB.get_weapon(&"carrot_pistol"), 0)
	for i in 30:
		if not victim.alive:
			break
		var dir := (victim.get_chest_position() - shooter.get_chest_position()).normalized()
		Projectiles.fire(shooter, w, shooter.get_chest_position() + dir * 0.6, dir, 0.0, shooter.visual.hitbox_rids)
		await wait_physics(8)


func test_the_final_shot_is_recorded() -> void:
	var pair := await _duel()
	var shooter: Critter = pair[0]
	var victim: Critter = pair[1]
	await wait_physics(30)
	await _shoot_down(shooter, victim)
	check(not victim.alive, "the victim went down")
	check(_kc.has_final() and _kc.victim == victim and _kc.shooter == shooter, "the KillCam caught the final shot, who shot whom")
	var rp: ReplayPose = victim.visual.skeleton.get_node("ReplayPose")
	check(rp.frames.size() > 30 and rp.get_index() == victim.visual.skeleton.get_child_count() - 1, "it records every frame, last in the skeleton's stack (%d frames)" % rp.frames.size())
	check(not _kc._killing_shot().is_empty(), "and knows the carrot that did it")
	var poses: Array = rp.frames[0][6]
	check(poses.size() == victim.visual.skeleton.get_bone_count(), "every bone, every frame")
	KillCam.recording = false


func test_slow_motion_replay_and_skip() -> void:
	var pair := await _duel()
	var shooter: Critter = pair[0]
	var victim: Critter = pair[1]
	await wait_physics(30)
	await _shoot_down(shooter, victim)
	check(_kc.has_final(), "a final shot to show")
	var cam_before := get_viewport().get_camera_3d()
	var done := [false]
	_kc.finished.connect(func(): done[0] = true)
	_kc.play_final()
	await get_tree().process_frame
	check(Engine.time_scale < 0.5 and Engine.physics_ticks_per_second > 60, "slow motion at the kill (x%.1f, physics at %d Hz)" % [Engine.time_scale, Engine.physics_ticks_per_second])
	var t0 := Time.get_ticks_msec()
	while not _kc.playing and Time.get_ticks_msec() - t0 < 8000:
		await get_tree().process_frame
	check(_kc.playing and get_tree().paused, "then the replay, with the world frozen")
	check(is_equal_approx(Engine.time_scale, 1.0) and Engine.physics_ticks_per_second == 60, "(at full speed again)")
	check(get_viewport().get_camera_3d() == _kc._cam, "seen through the replay camera")
	var rp: ReplayPose = victim.visual.skeleton.get_node("ReplayPose")
	await get_tree().create_timer(0.4, true, false, true).timeout
	check(rp.play_at >= 0.0 and rp.play_at < _kc.kill_time + KillCam.POST + 0.01, "the victim shows a recorded moment (t=%.2f)" % rp.play_at)
	# any button skips
	var ev := InputEventKey.new()
	ev.keycode = KEY_SPACE
	ev.pressed = true
	Input.parse_input_event(ev)
	t0 = Time.get_ticks_msec()
	while not done[0] and Time.get_ticks_msec() - t0 < 3000:
		await get_tree().process_frame
	check(done[0], "a button press skips to the end")
	check(not get_tree().paused and not _kc.playing and rp.play_at < 0.0, "and the match carries on as it was")
	check(get_viewport().get_camera_3d() == cam_before or (cam_before == null and get_viewport().get_camera_3d() != _kc._cam), "with the camera it had")
	check(victim.visual.skeleton.process_mode == Node.PROCESS_MODE_INHERIT, "(the skeletons are back to normal)")
