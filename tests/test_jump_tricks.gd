extends TestCase
## Species jump tricks: the right flip for the direction of travel, full turns
## that land upright, and the poser's tuck/stretch cues.

const S := CritterDef.JumpStyle


func _up_at(t: JumpTrick, p: float) -> Vector3:
	return t.rotation_at(p) * Vector3.UP


func test_bunny_flip_direction_follows_movement() -> void:
	check(JumpTrick.make(S.FLIP, Vector3(0, 0, -6), 1.0).variant == JumpTrick.Variant.FRONT, "running forward → front flip")
	check(JumpTrick.make(S.FLIP, Vector3(0, 0, 5), 1.0).variant == JumpTrick.Variant.BACK, "backing up → back flip")
	check(JumpTrick.make(S.FLIP, Vector3.ZERO, 1.0).variant == JumpTrick.Variant.BACK, "standing jump → back flip")
	check(JumpTrick.make(S.FLIP, Vector3(5, 0, -1), 1.0).variant == JumpTrick.Variant.RIGHT, "strafing right → side flip right")


func test_front_flip_goes_head_first_and_lands_upright() -> void:
	var t := JumpTrick.make(S.FLIP, Vector3(0, 0, -6), 1.0)
	check(_up_at(t, 0.25).z < -0.5, "a quarter in, the head points forward (%s)" % _up_at(t, 0.25))
	check(_up_at(t, 0.5).y < -0.9, "halfway, upside down (%s)" % _up_at(t, 0.5))
	check_near(_up_at(t, 1.0), Vector3.UP, 1e-3, "full turn lands upright")
	var b := JumpTrick.make(S.FLIP, Vector3(0, 0, 6), 1.0)
	check(_up_at(b, 0.25).z > 0.5, "back flip: head goes backward first (%s)" % _up_at(b, 0.25))


func test_every_style_lands_upright() -> void:
	for style in S.values():
		var t := JumpTrick.make(style, Vector3(0, 0, -5), 0.9)
		var max_tilt := 0.0
		for i in range(1, 10):
			max_tilt = maxf(max_tilt, rad_to_deg(_up_at(t, i / 10.0).angle_to(Vector3.UP)))
		t.elapsed = 0.9
		t.land()
		for i in 20:
			t.step(0.02)
		check(t.finished(), "style %s settles" % S.keys()[style])
		check_near(t.rotation() * Vector3.UP, Vector3.UP, 1e-3, "style %s ends upright" % S.keys()[style])
		check(max_tilt > 15.0 or style == S.SPIN, "style %s visibly moves mid-air (%.0f°)" % [S.keys()[style], max_tilt])


func test_early_landing_settles_quickly() -> void:
	var t := JumpTrick.make(S.TUCK_ROLL, Vector3(0, 0, -4), 1.0)
	t.elapsed = 0.4     # hit a ledge mid-somersault
	t.land()
	check(not t.active, "trick ends on touchdown")
	for i in 10:
		t.step(0.02)
	check(t.finished(), "settles within a few frames")


func test_limb_cues() -> void:
	var flip := JumpTrick.make(S.FLIP, Vector3(0, 0, -6), 1.0)
	flip.elapsed = 0.5
	check(flip.tuck() > 0.9, "flips tuck the knees")
	var frog := JumpTrick.make(S.FROG_LEAP, Vector3(0, 0, -6), 1.0)
	frog.elapsed = 0.5
	check(frog.tuck() < -0.9, "frogs stretch their legs out")
	check(flip.blocks_fire() and not frog.blocks_fire(), "only rotation-heavy tricks hold fire")


func test_critter_flips_in_game() -> void:
	make_arena()
	var c := spawn_critter("res://data/critters/test_critter.tres", Vector3(0, 0.1, 0), 0.0)
	await wait_physics(5)
	c.move_input = Vector2(0, 1)
	await wait_physics(20)
	c.want_jump = true
	await wait_physics(2)
	check(c.visual.trick != null and c.visual.trick.active, "jumping starts the trick")
	check(c.visual.trick.variant == JumpTrick.Variant.FRONT, "running jump = front flip")
	var t := 0
	while c.visual.trick != null and t < 180:
		await wait_physics(1)
		t += 1
	check(c.visual.trick == null, "trick finished after landing")
	check(c.visual.model.transform.basis.is_equal_approx(Basis(Vector3.UP, PI)), "model back to its upright pose")
