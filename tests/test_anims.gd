extends TestCase
## How critters carry themselves (CritterPoser): standing about they breathe,
## shift their weight and fidget; a relaxed gun is carried low and comes up
## to the aim when it's needed, while shots still leave from the raised
## muzzle; big guns are held clear of the head; and turning on the spot steps
## the feet round instead of swivelling them.


func before_each() -> void:
	make_arena(120.0)


func _face_ahead(c: Critter) -> void:
	c.aim_point = c.get_eye_position() + c.look_direction() * 30.0


func test_standing_about_is_never_frozen() -> void:
	var c := spawn_critter("res://data/critters/fox.tres", Vector3(0, 0.1, 0))
	await wait_physics(3)
	_face_ahead(c)
	var p := c.visual.poser
	var hips: int = c.visual.rig.bone[&"hips"]
	var chest: int = c.visual.rig.bone[&"chest"]
	var seen := []
	for i in 6:
		await wait_physics(20)
		await wait_frames(1)
		seen.append([c.visual.current_bone_global(hips).origin, c.visual.current_bone_global(chest).basis.get_rotation_quaternion()])
	var moved := 0.0
	var turned := 0.0
	for s in seen:
		moved = maxf(moved, (s[0] as Vector3).distance_to(seen[0][0]))
		turned = maxf(turned, (s[1] as Quaternion).angle_to(seen[0][1]))
	check(moved > 0.002, "the hips sway and breathe (%.4f)" % moved)
	check(turned > 0.005, "the chest rises and falls (%.3f rad)" % turned)
	# once things are quiet a fidget comes along, one of the species' own...
	await wait_physics(150)   # (critters start out alert)
	p._fidget_wait = 0.0
	await wait_physics(10)
	check(CritterPoser.FIDGETS["fox"].has(p._fidget), "a fox fidget starts (%s)" % p._fidget)
	# ...and stops the moment the critter runs off
	c.move_input = Vector2(0, 1)
	await wait_physics(45)
	check(p._fidget == "" or p._fidget_w < 0.05, "running cuts it short")


func test_a_relaxed_gun_is_carried_low_but_shoots_from_the_aim() -> void:
	var c := spawn_critter("res://data/critters/fox.tres", Vector3(0, 0.1, 0))
	c.give_weapon(WeaponInstance.new(WeaponDB.get_weapon(&"carrot_rifle")))
	await wait_physics(3)
	_face_ahead(c)
	await wait_physics(int((Critter.READY_HOLD + 1.0) * Engine.physics_ticks_per_second))
	await wait_frames(2)
	var aim := c.look_direction()
	var v := c.visual
	var held := -v.holder.global_basis.z.normalized()
	check(held.y < aim.y - 0.2, "relaxed: the muzzle points down (%.2f below the aim)" % (aim.y - held.y))
	var raised := -v.poser.raised_holder.basis.z.normalized()
	check(raised.angle_to(aim) < 0.1, "raised, it would point along the aim (%.2f rad)" % raised.angle_to(aim))
	check(v.muzzle_position().distance_to(v.muzzle.global_position) > 0.1,
		"so carrots leave from the raised muzzle, wherever the gun is carried")
	c.want_aim = true
	await wait_physics(30)
	await wait_frames(2)
	held = -v.holder.global_basis.z.normalized()
	check(held.angle_to(aim) < 0.1, "aiming: up on the aim line (%.2f rad)" % held.angle_to(aim))
	check(v.muzzle_position().distance_to(v.muzzle.global_position) < 0.05, "and shooting from the muzzle you see")


func test_big_guns_are_held_clear_of_the_head() -> void:
	for pair in [["beaver", &"carrot_rocket_launcher"], ["frog", &"carrot_sniper"], ["raccoon", &"carrot_lmg"], ["squirrel", &"carrot_shotgun"]]:
		var c := spawn_critter("res://data/critters/%s.tres" % pair[0], Vector3(0, 0.1, 0))
		c.give_weapon(WeaponInstance.new(WeaponDB.get_weapon(pair[1])))
		c.want_aim = true
		await wait_physics(3)
		_face_ahead(c)
		await wait_physics(20)
		await wait_frames(2)
		var v := c.visual
		var seg: Dictionary = v.rig.segments[&"head"]
		var head := v.current_bone_global(v.rig.bone[&"head"]) * (v.rig.rest[&"head"] as Transform3D).affine_inverse()
		var to_gun := (v.skeleton.global_transform.affine_inverse() * v.holder.global_transform).affine_inverse()
		var box := v.poser.gun_box.grow(float(seg["radius"]) * 0.5)
		var through := 0
		for k in 3:
			if box.has_point(to_gun * (head * (seg["start"] as Vector3).lerp(seg["end"], k * 0.5))):
				through += 1
		check(through == 0, "%s holds its %s clear of its head" % [pair[0], pair[1]])
		c.queue_free()
		await wait_physics(1)


func test_turning_on_the_spot_steps_round() -> void:
	var c := spawn_critter("res://data/critters/bun.tres", Vector3(0, 0.1, 0))
	await wait_physics(10)
	var p := c.visual.poser
	var stepped := {}
	for i in 45:
		c.look_yaw += deg_to_rad(2.5)
		_face_ahead(c)
		await wait_physics(1)
		if p._step_side != &"":
			stepped[p._step_side] = true
	check(stepped.size() == 2, "both feet step round as it turns (%s)" % [stepped.keys()])
	await wait_physics(30)
	check(p._step_side == &"", "and settle when it stops")
