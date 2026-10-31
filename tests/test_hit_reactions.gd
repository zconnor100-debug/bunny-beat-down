extends TestCase
## Hit reactions (Critter._react, knock_down): a light hit shoves a critter
## and turns a bot hit off its middle; a hard one (a blast, a sniper's
## carrot, a shotgun's load close up) knocks it off its feet: it tumbles as
## a ragdoll, its body going where its hips go, and springs back up after
## KNOCK_TIME, and can't be knocked down again straight away. You're only
## knocked down by blasts. Beaten down while it's down, it stays down; moved
## while it's down (a rewind, a teleport), it's up where it's put.

const TEST_DEF := "res://data/critters/test_critter.tres"


func before_each() -> void:
	make_arena()


func _tough(at := Vector3(0, 0.1, 0)) -> Critter:
	var c := spawn_critter(TEST_DEF, at)
	c.max_health = 100.0
	c.health = 100.0
	return c


func _hit(c: Critter, kind: DamageInfo.Kind, amount: float, impulse: float, dir := Vector3(1, 0, 0), at := Vector3.INF,
		weapon := &"carrot_rifle") -> void:
	var info := DamageInfo.make(amount, kind, null, weapon)
	info.direction = dir.normalized()
	info.impulse = impulse
	info.bone_role = &"chest"
	info.position = c.get_chest_position() if at == Vector3.INF else at
	c.take_damage(info)


func _ticks(seconds: float) -> int:
	return int(seconds * Engine.physics_ticks_per_second)


func test_a_blast_knocks_a_critter_down_and_it_gets_up() -> void:
	var c := _tough()
	await wait_physics(3)
	var at := c.global_position
	_hit(c, DamageInfo.Kind.EXPLOSION, 30.0, 16.0, Vector3(1, 0.7, 0), Vector3.INF, &"carrot_rocket_launcher")
	check(c.alive and c.is_knocked() and c.visual.knocked and c.visual.phys_sim.active, "knocked off its feet")
	await wait_physics(_ticks(0.5))
	var hips := c.visual.bone_world_position(&"hips")
	check(MissionDirector._flat(hips - at).length() > 0.5, "thrown (its hips %.2f m off)" % MissionDirector._flat(hips - at).length())
	check(MissionDirector._flat(c.global_position - hips).length() < 0.6, "its body goes where its hips go (%.2f m)" % MissionDirector._flat(c.global_position - hips).length())
	await wait_physics(_ticks(Critter.KNOCK_TIME) + 20)
	await wait_frames(3)
	check(not c.is_knocked() and not c.visual.knocked and not c.visual.phys_sim.active, "back on its feet (%.3f %s %s)" % [c.knocked, c.visual.knocked, c.visual.phys_sim.active])
	var head := c.visual.bone_world_position(&"head")
	check(head.y > c.global_position.y + c.visual.rig.world_head_top * 0.6, "standing again (head %.2f m up)" % (head.y - c.global_position.y))
	_hit(c, DamageInfo.Kind.EXPLOSION, 30.0, 16.0, Vector3(-1, 0.7, 0), Vector3.INF, &"carrot_rocket_launcher")
	check(not c.is_knocked(), "just up: not knocked down again yet")
	await wait_physics(_ticks(Critter.KNOCK_GUARD) + 5)
	_hit(c, DamageInfo.Kind.EXPLOSION, 30.0, 16.0, Vector3(-1, 0.7, 0), Vector3.INF, &"carrot_rocket_launcher")
	check(c.is_knocked(), "a while later, it can be again")


func test_a_light_hit_shoves_and_a_hit_off_its_middle_turns_a_bot() -> void:
	var c := _tough()
	await wait_physics(3)
	c.velocity = Vector3.ZERO
	_hit(c, DamageInfo.Kind.BULLET, 17.0, 4.0, Vector3(1, 0, 0))
	check(not c.is_knocked() and c.velocity.x > 1.0, "a rifle's carrot: shoved (%.2f m/s), not knocked down" % c.velocity.x)
	await wait_physics(20)
	var yaw := c.rotation.y
	_hit(c, DamageInfo.Kind.BULLET, 25.0, 4.0, Vector3(1, 0, 0), c.get_chest_position() + Vector3(0, 0, 0.35))
	check(absf(angle_difference(yaw, c.rotation.y)) > 0.15 and not c.is_knocked(), "hit on a shoulder: turned (%.2f rad)" % angle_difference(yaw, c.rotation.y))


func test_hard_hits_knock_a_bot_down() -> void:
	var c := _tough()
	await wait_physics(3)
	_hit(c, DamageInfo.Kind.BULLET, 30.0, 12.0, Vector3(0, 0, 1), Vector3.INF, &"carrot_sniper")
	check(c.is_knocked(), "a sniper's carrot knocks a bot down")
	var b := _tough(Vector3(6, 0.1, 0))
	await wait_physics(3)
	for i in 3:
		_hit(b, DamageInfo.Kind.BULLET, 11.0, 3.0, Vector3(0, 0, 1))
	check(not b.is_knocked(), "three pellets: still standing")
	_hit(b, DamageInfo.Kind.BULLET, 11.0, 3.0, Vector3(0, 0, 1))
	check(b.is_knocked(), "a fourth in the same instant (a shotgun's load close up): down")


func test_you_are_only_knocked_down_by_blasts() -> void:
	var c := _tough()
	c.is_player = true
	await wait_physics(3)
	_hit(c, DamageInfo.Kind.BULLET, 30.0, 12.0, Vector3(0, 0, 1), Vector3.INF, &"carrot_sniper")
	check(not c.is_knocked(), "a sniper's carrot doesn't knock you down")
	_hit(c, DamageInfo.Kind.EXPLOSION, 30.0, 16.0, Vector3(1, 0.7, 0), Vector3.INF, &"carrot_rocket_launcher")
	check(c.is_knocked(), "a blast does")


func test_beaten_down_while_down_it_stays_down() -> void:
	var c := _tough()
	await wait_physics(3)
	_hit(c, DamageInfo.Kind.EXPLOSION, 30.0, 16.0, Vector3(1, 0.7, 0), Vector3.INF, &"carrot_rocket_launcher")
	await wait_physics(10)
	_hit(c, DamageInfo.Kind.BULLET, 500.0, 4.0, Vector3(1, 0, 0))
	check(not c.alive and c.visual.ragdolled and not c.visual.knocked, "beaten down: a ragdoll for good")
	await wait_physics(_ticks(Critter.KNOCK_TIME) + 20)
	check(c.visual.ragdolled and c.visual.phys_sim.active, "and it doesn't get up")


func test_moved_while_down_it_is_up_where_it_is_put() -> void:
	var c := _tough()
	await wait_physics(3)
	_hit(c, DamageInfo.Kind.EXPLOSION, 30.0, 16.0, Vector3(1, 0.7, 0), Vector3.INF, &"carrot_rocket_launcher")
	await wait_physics(10)
	c.place_at(Vector3(-4, 0.1, 2))
	check(not c.is_knocked() and not c.visual.knocked and not c.visual.phys_sim.active, "put somewhere: up again, the ragdoll off")
	await wait_physics(10)
	check(c.global_position.distance_to(Vector3(-4, 0.1, 2)) < 0.5, "where it was put")
