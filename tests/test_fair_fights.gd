extends TestCase
## Fair fights: shots leave visible tracers, bots can't see through bushes and
## tall grass (any more than you can), they have to *spot* you before they
## fight, only a few shoot at you at once, and they hit softer than they look.

const TEST_DEF := "res://data/critters/test_critter.tres"


func before_each() -> void:
	make_arena(120.0)


func after_each() -> void:
	AIBrain._player_attackers.clear()
	await super()


func test_every_carrot_draws_a_tracer() -> void:
	var proj := get_node("Projectiles") as Projectiles
	var w := WeaponInstance.new(WeaponDB.get_weapon(&"carrot_rifle"))
	Projectiles.fire(null, w, Vector3(0, 1.5, 0), Vector3(0, 0.02, -1), 0.0, [])
	await wait_physics(3)
	await wait_frames(1)
	check(proj.tracer_count() == 1, "a carrot in flight has a tracer (%d)" % proj.tracer_count())
	var shotgun := WeaponInstance.new(WeaponDB.get_weapon(&"carrot_shotgun"))
	Projectiles.fire(null, shotgun, Vector3(0, 1.5, 0), Vector3(0, 0.02, -1), 5.0, [])
	await wait_physics(3)
	await wait_frames(1)
	check(proj.tracer_count() == 1 + shotgun.data.pellets, "every pellet streaks too (%d)" % proj.tracer_count())
	await wait_physics(Engine.physics_ticks_per_second * 4)   # all landed or expired
	await wait_frames(1)
	check(proj.tracer_count() == 0, "no tracers once the carrots are gone (%d)" % proj.tracer_count())


func test_bushes_and_grass_hide_critters() -> void:
	var sc := Scatter.new()
	add_child(sc)
	sc.load_manifest()
	var eye := Vector3(0, 1.8, 0)
	var body := func(at: Vector3) -> PackedVector3Array:
		return PackedVector3Array([at + Vector3.UP * 1.8, at + Vector3.UP * 1.2, at + Vector3.UP * 0.6])
	var spot := Vector3(0, 0, -30)
	check_near(sc.visibility(eye, body.call(spot)), 1.0, 0.001, "out in the open: fully visible")
	sc.place(sc.get_entry("bush_a"), spot, 0.0, 1.0)
	check(sc.visibility(eye, body.call(spot)) < 0.2, "inside a bush: hidden (%.2f)" % sc.visibility(eye, body.call(spot)))
	sc.place(sc.get_entry("bush_a"), Vector3(0, 0, -60), 0.0, 1.0)
	check(sc.visibility(eye, body.call(Vector3(0, 0, -75))) < 0.2, "behind a bush: hidden")
	check_near(sc.visibility(eye, body.call(Vector3(25, 0, -40))), 1.0, 0.001, "off to the side of it: visible")
	# a clump of grass hides legs but not a standing critter's head
	var meadow := Vector3(-30, 0, 0)
	for off in [Vector2(0, 0), Vector2(0.8, 0.5), Vector2(-0.7, 0.6), Vector2(0.2, -0.8)]:
		sc.place(sc.get_entry("grass_clump_a"), meadow + Vector3(off.x, 0, off.y), 0.0, 1.0)
	var v := sc.visibility(eye, body.call(meadow))
	check(v > 0.4 and v < 0.95, "standing in grass: partly hidden (%.2f)" % v)


func test_bots_must_spot_you_first() -> void:
	var player := spawn_critter(TEST_DEF, Vector3(0, 0.1, -40))
	player.is_player = true
	var bot := spawn_critter(TEST_DEF, Vector3(0, 0.1, 0))   # looking down -Z, at the player
	var brain := AIBrain.new()
	bot.add_child(brain)
	brain.set_physics_process(false)
	await wait_physics(3)
	brain._perceive()
	check(brain.target == null, "a still critter 40 m away isn't spotted at a glance")
	var spotted_after := -1.0
	for i in 40:
		brain._clock += 0.2
		brain._perceive()
		if brain.target == player:
			spotted_after = (i + 1) * 0.2
			break
	check(spotted_after > 0.4, "...but is after watching a while (%.1f s)" % spotted_after)
	# getting shot points the bot the right way, it doesn't hand it a target
	var bot2 := spawn_critter(TEST_DEF, Vector3(20, 0.1, 0), PI)   # facing away (+Z)
	var brain2 := AIBrain.new()
	bot2.add_child(brain2)
	brain2.set_physics_process(false)
	await wait_physics(2)
	var hit := DamageInfo.make(10.0, DamageInfo.Kind.BULLET, player)
	bot2.take_damage(hit)
	check(brain2.target == null and brain2._alerted(), "shot from behind: alerted, no instant target")
	check(brain2.awareness_of(player) >= 0.6, "and partly aware of the shooter (%.2f)" % brain2.awareness_of(player))


func test_only_a_few_bots_shoot_at_you_at_once() -> void:
	AIBrain.player_attack_slots = 2
	var brains: Array[AIBrain] = []
	for i in 3:
		var c := spawn_critter(TEST_DEF, Vector3(i * 3.0, 0.1, 0))
		var b := AIBrain.new()
		c.add_child(b)
		b.set_physics_process(false)
		brains.append(b)
	await wait_physics(2)
	check(brains[0]._may_shoot_player() and brains[1]._may_shoot_player(), "two bots get a turn")
	check(not brains[2]._may_shoot_player(), "the third waits")
	check(brains[0]._may_shoot_player(), "a bot keeps its turn while it keeps shooting")
	AIBrain._player_attackers.erase(brains[1].get_instance_id())   # bot 2 stopped long ago
	check(brains[2]._may_shoot_player(), "the next bot steps in when a slot frees up")


func test_bots_hit_the_player_softer() -> void:
	AIBrain.damage_to_player = 0.65
	var player := spawn_critter(TEST_DEF, Vector3(0, 0.1, 0))
	player.is_player = true
	var bot := spawn_critter(TEST_DEF, Vector3(5, 0.1, 0))
	await wait_physics(2)
	var info := DamageInfo.make(20.0, DamageInfo.Kind.BULLET, bot)
	info.bone_role = &"chest"
	player.take_damage(info)
	check_near(player.health, player.max_health - 13.0, 0.01, "a 20-damage bot hit takes 13")
	var info2 := DamageInfo.make(20.0, DamageInfo.Kind.BULLET, player)
	info2.bone_role = &"chest"
	bot.take_damage(info2)
	check_near(bot.health, bot.max_health - 20.0, 0.01, "the player's own hits are full strength")
