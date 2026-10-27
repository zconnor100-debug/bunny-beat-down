extends TestCase
## Carrot grenades: lobbed along the arc the aim shows, about 25 m at the
## most; they bounce, lie still, and go off on their fuse, hurting and blowing
## back everyone in the blast (a beat-down names the grenade). You carry a
## few, pick more up, and bots lob them onto you.

const TEST_DEF := "res://data/critters/test_critter.tres"


func before_each() -> void:
	make_arena(80.0)


func _ticks(seconds: float) -> int:
	return int(seconds * Engine.physics_ticks_per_second) + 2


func test_a_grenade_lands_where_the_arc_says_and_blows_them_back() -> void:
	var me := spawn_critter(TEST_DEF, Vector3(0, 0.1, 0))   # facing -Z
	me.is_player = true   # (bots go easy on each other)
	var them := spawn_critter(TEST_DEF, Vector3(0, 0.1, -12.0), PI)
	await wait_physics(3)
	check(not me.can_throw(), "no grenades, no throw")
	check(not me.throw_grenade(), "(throwing does nothing)")
	me.inventory.add_grenades(2)
	check(me.can_throw(), "with a grenade, it can be thrown")
	# aim so the arc comes down at their feet (on the ground, not off their head)
	var best := Vector3.ZERO
	var land := Vector3.INF
	var both: Array[RID] = me.visual.hitbox_rids.duplicate()
	both.append_array(them.visual.hitbox_rids)
	for i in 120:
		me.look_pitch = deg_to_rad(-20.0 + i * 0.5)
		var pts := Grenade.arc(me.get_world_3d().direct_space_state, me.throw_origin(), me.throw_velocity(), both)
		var end := pts[pts.size() - 1]
		if absf(end.z - them.global_position.z) < absf(land.z - them.global_position.z):
			land = end
			best = me.throw_velocity()
	check_near(land.z, -12.0, 1.0, "the arc can be aimed onto them (comes down at z %.1f)" % land.z)
	var hp := them.health
	check(me.throw_grenade(best), "thrown")
	check(me.inventory.grenades == 1, "one fewer carried (%d)" % me.inventory.grenades)
	await wait_physics(1)
	check(me.is_throwing() and me.visual.poser.throw >= 0.0, "the throw's wound up")
	await wait_physics(_ticks(Critter.THROW_TIME * Critter.THROW_RELEASE))
	var flying := get_tree().get_nodes_in_group(&"grenades")
	check(flying.size() == 1, "it leaves the paw")
	# where it first comes down
	var first := Vector3.INF
	var last_vy := 0.0
	for i in _ticks(1.6):
		await wait_physics(1)
		if flying.is_empty() or not is_instance_valid(flying[0]):
			break
		var vy: float = flying[0].velocity.y
		if first == Vector3.INF and last_vy < -2.0 and vy > last_vy + 2.0:
			first = flying[0].global_position
		last_vy = vy
	check(first != Vector3.INF and absf(first.z - land.z) < 1.0, "it comes down where the arc said, or off them at their feet (%.1f vs %.1f)" % [first.z, land.z])
	var start := them.global_position
	await wait_physics(_ticks(Grenade.FUSE - 1.7))
	var lie: Vector3 = flying[0].global_position if not flying.is_empty() and is_instance_valid(flying[0]) else Vector3.INF
	check(lie != Vector3.INF and lie.distance_to(land) < 4.5, "it lies still near there (%.1f m on)" % lie.distance_to(land))
	await wait_physics(_ticks(1.0))
	check(get_tree().get_nodes_in_group(&"grenades").is_empty(), "it goes off on its fuse")
	check(them.health < hp - 15.0 or not them.alive, "it hurts them (%.0f → %.0f hp)" % [hp, them.health])
	var moved := Vector2(them.global_position.x - start.x, them.global_position.z - start.z).length()
	check(not them.alive or moved > 1.0, "and blows them back (%.1f m)" % moved)
	check(me.health > me.max_health - 1.0, "the thrower, 12 m off, is fine")


func test_a_throw_reaches_about_twenty_five_metres() -> void:
	var me := spawn_critter(TEST_DEF, Vector3(0, 0.1, 30.0))
	await wait_physics(3)
	var far := 0.0
	for deg in range(0, 70, 5):
		me.look_pitch = deg_to_rad(deg)
		var pts := Grenade.arc(me.get_world_3d().direct_space_state, me.throw_origin(), me.throw_velocity(), me.visual.hitbox_rids)
		far = maxf(far, me.global_position.z - pts[pts.size() - 1].z)
	check(far > 20.0 and far < 32.0, "a lob carries far, but not too far (%.1f m)" % far)


func test_a_beat_down_names_the_grenade() -> void:
	var me := spawn_critter(TEST_DEF, Vector3(0, 0.1, 0))
	var them := spawn_critter(TEST_DEF, Vector3(3.0, 0.1, -6.0), PI)
	await wait_physics(3)
	them.health = 10.0
	var got := []
	them.died.connect(func(info: DamageInfo): got.append(info))
	Grenade.spawn(Projectiles.instance, me, them.global_position + Vector3(0.5, 0.3, 0.0), Vector3.ZERO)
	await wait_physics(_ticks(Grenade.FUSE + 0.2))
	check(not them.alive, "beaten down")
	check(not got.is_empty() and got[0].weapon_id == &"carrot_grenade" and got[0].attacker == me, "by the thrower's carrot grenade")
	check(WeaponDB.get_weapon(&"carrot_grenade") != null and not WeaponDB.all().has(WeaponDB.get_weapon(&"carrot_grenade")),
		"(a grenade's looked up by name, but it's never a gun on the floor)")


func test_grenades_are_picked_up_up_to_four() -> void:
	var me := spawn_critter(TEST_DEF, Vector3(0, 0.1, 0))
	await wait_physics(3)
	var p := Pickup.spawn(self, Pickup.grenade_spec(2), me.global_position + Vector3(0.3, 0.2, 0.0))
	await wait_physics(_ticks(0.6))
	check(me.inventory.grenades == 2, "walking over two grenades picks them up (%d)" % me.inventory.grenades)
	check(not is_instance_valid(p) or p.is_queued_for_deletion(), "and they're gone from the floor")
	check(me.inventory.add_grenades(5) == 3, "four at the most")


func test_a_bot_lobs_one_at_you_behind_cover() -> void:
	var brain := AIBrain.new()
	brain.skill = 1.0
	var from := Vector3(0, 1.4, 0)
	for d in [10.0, 16.0, 22.0]:
		var at := Vector3(0, 0.0, -d)
		var lob := brain._lob(from, at)
		check(lob != Vector3.ZERO and lob.length() <= Critter.THROW_SPEED + 0.01, "a lob reaches %.0f m" % d)
		var pts := Grenade.arc(get_world_3d().direct_space_state, from, lob)
		check_near(pts[pts.size() - 1].z, at.z, 1.0, "and comes down there")
	check(brain._lob(from, Vector3(0, 0, -4.0)) == Vector3.ZERO, "not inside its own blast")
	check(brain._lob(from, Vector3(0, 0, -40.0)) == Vector3.ZERO, "nor beyond a throw")
	brain.free()
