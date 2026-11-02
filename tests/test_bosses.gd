extends TestCase
## The Boss Battle's bosses: ten critters tall, their hitboxes on them,
## carrots (and blasts, and clubs) hurting them (the head more, bots' carrots
## less), their blows hurting who's close and sparing who's far or in the
## air, the bots fighting them and getting out from under their blows, and a
## boss going down for good. Old Hoot, the one that flies: circling up high,
## carrying a critter off and dropping it (and wriggled free of), grounded by
## shots on her wings as she dives, her hoot knocking everyone under her
## down. Crackjaw, the nutcracker: shot in the legs he goes over (and gets
## up again), and his sabre passes under whoever jumps it. Noodle, the
## ferret: she goes under and pops up out of a red ring (a burrow's, if
## one's near), bopped on the nose she sees stars, she dances herself to
## sleep and wakes in a poof of musk, and beaten mid-pop or asleep she stays
## down. Then a whole Boss Battle on each map, against Old Hoot by night,
## Crackjaw and Noodle.

const TEST_DEF := "res://data/critters/test_critter.tres"
const BUN := "res://data/critters/bun.tres"
const SCRIPTS := {"brute": "res://src/bosses/brute_boss.gd", "robot": "res://src/bosses/robot_boss.gd",
	"hamster": "res://src/bosses/hamster_boss.gd", "owl": "res://src/bosses/owl_boss.gd",
	"nutcracker": "res://src/bosses/nutcracker_boss.gd", "ferret": "res://src/bosses/ferret_boss.gd"}
const GAME := "res://scenes/game.tscn"


func before_each() -> void:
	make_arena(800.0)


func after_each() -> void:
	AIBrain.boss = null
	Engine.time_scale = 1.0
	await super()


## A boss standing in the arena, fighting (or only doing what it's told).
func _boss(id: String, at := Vector3.ZERO, thinking := false) -> Boss:
	var b: Boss = (load(SCRIPTS[id]) as GDScript).new()
	b.thinking = thinking
	add_child(b)
	b.global_position = at
	b.state = Boss.State.FIGHTING
	b.visible = true
	b._set_hittable(true)
	return b


func test_every_boss_is_ten_critters_tall_and_hittable_all_over() -> void:
	var bun := spawn_critter(BUN, Vector3(60, 0, 60))
	await wait_physics(2)
	var critter_h := bun.visual.rig.world_head_top
	for id in SCRIPTS:
		var b := _boss(id)
		await wait_physics(3)
		if b is FerretBoss:   # (long and low: she's ten critters tall reared up on her hind legs)
			b.set_physics_process(false)
			b.poser.clear()
			b.poser.add_pose(FerretBoss.REARED)
			b.poser.apply()
			b._update_bones()
		var skull := b.bone_point(&"head", 1.0).y - b.global_position.y
		check(absf(skull / critter_h - 10.0) < 1.5, "%s: its skull is ten critters up (%.1f m, a critter %.2f m: x%.1f)" % [id, skull, critter_h, skull / critter_h])
		for role in [&"head", &"l_upper_leg", &"r_upper_leg"]:
			check(b.hitboxes.has(role), "%s has a hitbox on its %s" % [id, role])
		check(b.hitboxes.size() >= 8, "%s: hitboxes all over it (%d)" % [id, b.hitboxes.size()])
		# the head's hitbox is where its head is
		var head := b.hitboxes[&"head"] as Area3D
		check(head.global_position.distance_to(b.get_eye_position()) < 6.0, "%s: the head hitbox sits on its head (%.1f m off)" % [id,
			head.global_position.distance_to(b.get_eye_position())])
		check(b.eye_positions().size() == 2, "%s has two eyes" % id)
		if b.data.get("eye_mask") is String:   # (its own eyes glow, in its skin: they go where its eyes go)
			check(b._eyes.is_empty() and not b._eye_skin.is_empty() and b._eye_skin.all(func(m): return (m.emission_texture != null
				and m.emission_operator == BaseMaterial3D.EMISSION_OP_MULTIPLY)),
				"%s: its own eyes glow (%d materials)" % [id, b._eye_skin.size()])
		b.queue_free()
		await wait_physics(2)


func test_carrots_hurt_a_boss_and_hits_on_its_head_more() -> void:
	var b := _boss("brute")
	var you := spawn_critter(TEST_DEF, Vector3(0, 0.1, -60), 0.0)
	you.is_player = true
	await wait_physics(5)
	var rifle := WeaponInstance.new(WeaponDB.get_weapon(&"carrot_rifle"), 0)
	# a real carrot, fired at its chest from 60 m
	var hp := b.health
	var from := you.get_eye_position()
	var at := b.get_chest_position()
	Projectiles.fire(you, rifle, from, (at - from).normalized(), 0.0, you.visual.hitbox_rids)
	await wait_physics(20)
	var body_hit := hp - b.health
	check(body_hit > 5.0, "a carrot in the chest hurts it (%.1f)" % body_hit)
	hp = b.health
	b.receive_shot(you, rifle.data, 17.0, b.get_eye_position(), Vector3.FORWARD, &"head")
	var head_hit := hp - b.health
	hp = b.health
	b.receive_shot(you, rifle.data, 17.0, b.get_chest_position(), Vector3.FORWARD, &"chest")
	var chest_hit := hp - b.health
	check(head_hit > chest_hit * 1.8, "its head takes twice as much (%.1f vs %.1f)" % [head_hit, chest_hit])
	# a bot's carrot counts for less than yours
	var bot := spawn_critter(TEST_DEF, Vector3(10, 0.1, -60))
	await wait_physics(2)
	hp = b.health
	b.receive_shot(bot, rifle.data, 17.0, b.get_chest_position(), Vector3.FORWARD, &"chest")
	check_near((hp - b.health) / chest_hit, Boss.BOT_DAMAGE, 0.01, "a bot's carrot counts for BOT_DAMAGE of yours")
	# the Tin Tyrant's tin plate takes the sting out, but not at its key
	var r := _boss("robot", Vector3(120, 0, 0))
	await wait_physics(3)
	hp = r.health
	r.receive_shot(you, rifle.data, 17.0, r.get_chest_position(), Vector3.FORWARD, &"chest")
	var tin := hp - r.health
	hp = r.health
	r.receive_shot(you, rifle.data, 17.0, r.get_chest_position(), Vector3.FORWARD, &"key")
	check(hp - r.health > tin * 2.5, "its wind-up key is its weak spot (%.1f vs %.1f on the tin)" % [hp - r.health, tin])
	check(tin < 17.0, "the tin plate takes the sting out (%.1f of 17)" % tin)


func test_blasts_and_clubs_hurt_a_boss() -> void:
	var b := _boss("hamster")
	await wait_physics(5)
	var you := spawn_critter(TEST_DEF, Vector3(0, 0.1, -30), 0.0)
	you.is_player = true
	await wait_physics(3)
	var hp := b.health
	var rocket := WeaponInstance.new(WeaponDB.get_weapon(&"carrot_rocket_launcher"), 0)
	Explosion.detonate(get_tree(), b.bone_point(&"l_foot", 0.5) + Vector3(0, 0, -2), rocket, you)
	check(b.health < hp - 20.0, "a rocket going off at its feet hurts it (%.0f)" % (hp - b.health))
	# a club, swung at its leg
	hp = b.health
	var leg := b.bone_point(&"l_lower_leg", 0.5)
	you.global_position = Vector3(leg.x, 0.1, leg.z) + (Vector3(leg.x, 0, leg.z) - Vector3(b.global_position.x, 0, b.global_position.z)).normalized() * 2.0
	await wait_physics(2)
	var to := leg - you.get_chest_position()
	you.look_yaw = atan2(-to.x, -to.z)
	you.look_pitch = 0.0
	you.want_melee = true
	await wait_physics(40)
	check(b.health < hp, "a club to its leg hurts it (%.0f)" % (hp - b.health))


func test_a_blow_hurts_who_is_close_not_who_is_far_or_in_the_air() -> void:
	var b := _boss("brute")
	await wait_physics(3)
	var near := spawn_critter(TEST_DEF, Vector3(4, 0.1, -10))
	var far := spawn_critter(TEST_DEF, Vector3(0, 0.1, -70))
	var aloft := spawn_critter(TEST_DEF, Vector3(-4, 0.1, -10))
	await wait_physics(10)
	aloft.global_position.y = 6.0   # (mid-jump as it lands)
	aloft.velocity = Vector3.UP * 4.0
	await wait_physics(1)
	var hit := b.hurt_ring(Vector3(0, 0, -10), 20.0, 55.0, 15.0, 14.0, 9.0, &"pound")
	check(hit.has(near) and near.health < 100.0, "the critter right there took it (%.0f)" % near.health)
	check(not hit.has(far) and far.health == 100.0, "the one 60 m off didn't")
	check(not hit.has(aloft), "the one in the air when it landed was spared")
	# a whole Ground Pound, start to finish: a warning first, then the blow
	near.health = 100.0
	near.velocity = Vector3.ZERO
	near.global_position = b.global_position + b.forward() * 8.0 + Vector3.UP * 0.1
	await wait_physics(30)   # (back on its feet: the first blow threw it)
	b.start(b._pound())
	await wait_physics(10)
	check(not b.danger.is_empty(), "a red ring warns where it'll land")
	var before := near.health
	await wait_physics(160)
	check(near.health < before or not near.alive, "the Ground Pound landed on the critter in front of it")
	check(b.action == null, "and it's done (%s)" % (b.action.name if b.action else &""))


func test_a_boss_goes_down_for_good() -> void:
	var b := _boss("robot")
	var you := spawn_critter(TEST_DEF, Vector3(0, 0.1, -40))
	you.is_player = true
	await wait_physics(3)
	var by: Array = []
	b.died.connect(func(who): by.append(who))
	b.health = 5.0
	b.receive_shot(you, WeaponDB.get_weapon(&"carrot_sniper"), 90.0, b.get_eye_position(), Vector3.FORWARD, &"head")
	check(not b.alive and b.state == Boss.State.DEAD, "it's down")
	check(by.size() == 1 and by[0] == you, "and it says who did it")
	check((b.hitboxes[&"head"] as Area3D).collision_layer == 0, "carrots go through it now")
	var hp := b.health
	b.receive_shot(you, WeaponDB.get_weapon(&"carrot_rifle"), 17.0, b.get_eye_position(), Vector3.FORWARD, &"head")
	check(b.health == hp, "it can't be hurt again")
	await wait_physics(200)
	check(b.action == null and not b.is_physics_processing(), "its fall played out, and it lies still")


func test_teammates_never_hurt_each_other() -> void:
	var a := spawn_critter(TEST_DEF, Vector3(0, 0.1, 0))
	var mate := spawn_critter(TEST_DEF, Vector3(0, 0.1, -3))
	var foe := spawn_critter(TEST_DEF, Vector3(3, 0.1, -3))
	a.team = 1
	mate.team = 1
	foe.team = 2
	await wait_physics(3)
	var info := DamageInfo.make(30.0, DamageInfo.Kind.BULLET, a, &"carrot_rifle")
	mate.take_damage(info)
	check(mate.health == 100.0, "a team mate's carrot doesn't hurt")
	foe.take_damage(DamageInfo.make(30.0, DamageInfo.Kind.BULLET, a, &"carrot_rifle"))
	check(foe.health < 100.0, "the other team's does")
	# a grenade's blast spares the thrower's team too
	var nade := WeaponInstance.new(WeaponDB.get_weapon(&"carrot_rocket_launcher"), 0)
	Explosion.detonate(get_tree(), Vector3(0, 0.5, -3), nade, a)
	check(mate.health == 100.0, "and its blasts don't either (%.0f)" % mate.health)
	# bots don't pick their own side as targets
	var brain := AIBrain.new()
	brain.name = "AIBrain"
	a.add_child(brain)
	brain.skill = 0.9
	for i in 40:
		await wait_physics(5)
		if brain.target != null:
			break
	check(brain.target != mate, "a bot never targets its team mate")


func test_bots_get_out_from_under_a_blow_and_fight_the_boss() -> void:
	seed(4)   # (whether a bot sees a blow coming is a dice roll)
	var b := _boss("brute", Vector3(0, 0, 0))
	await wait_physics(3)
	var c := spawn_critter(TEST_DEF, Vector3(0, 0.1, -40))
	c.team = 1
	var brain := AIBrain.new()
	brain.name = "AIBrain"
	brain.skill = 0.95
	c.add_child(brain)
	var gun := WeaponInstance.new(WeaponDB.get_weapon(&"carrot_rifle"), 0)
	c.give_weapon(gun)
	c.inventory.ammo[gun.data.ammo_type] = 400
	AIBrain.boss = b
	await wait_physics(20)
	# a blow coming down on a ring it's just inside (the middle of a big one is
	# a death trap: it takes a moment to sink in)
	var centre := c.global_position + Vector3(6.0, 0.0, 0.0)
	b.warn(centre, 12.0, 1.5)
	await wait_physics(95)
	var off := Vector2(c.global_position.x - centre.x, c.global_position.z - centre.z).length()
	check(off > 12.0, "the bot got out of the ring before the blow landed (%.1f m from its middle, 12 m across)" % off)
	b.danger.clear()
	var hp := b.health
	for i in 60:
		await wait_physics(10)
		if b.health < hp:
			break
	check(b.health < hp, "the bot shoots the boss (%.0f)" % (hp - b.health))
	check(brain.mode == AIBrain.Mode.BOSS, "fighting it as a boss (mode %s)" % AIBrain.Mode.keys()[brain.mode])


## While a boss can't be hit (down a hole), the bots hold their fire.
func test_bots_hold_fire_while_a_boss_is_down_a_hole() -> void:
	var b := _boss("hamster", Vector3(0, 0, 0))
	await wait_physics(3)
	var c := spawn_critter(TEST_DEF, Vector3(0, 0.1, -60))
	c.team = 1
	var brain := AIBrain.new()
	brain.name = "AIBrain"
	brain.skill = 0.95
	c.add_child(brain)
	var gun := WeaponInstance.new(WeaponDB.get_weapon(&"carrot_rifle"), 0)
	c.give_weapon(gun)
	c.inventory.ammo[gun.data.ammo_type] = 400
	AIBrain.boss = b
	b._set_hittable(false)
	var fired := false
	for i in 180:
		await wait_physics(1)
		fired = fired or c.want_fire
	check(not b.hittable() and not fired, "down a hole: the bot holds its fire")
	b._set_hittable(true)
	var hp := b.health
	for i in 60:
		await wait_physics(10)
		if b.health < hp:
			break
	check(b.hittable() and b.health < hp, "up again: it shoots (%.0f)" % (hp - b.health))


func test_rewind_puts_a_boss_back() -> void:
	var b := _boss("hamster")
	await wait_physics(3)
	var snap := b.snapshot()
	var hp := b.health
	b.global_position = Vector3(50, 0, 50)
	b.health -= 500.0
	b.restore(snap)
	check(b.global_position.distance_to(Vector3.ZERO) < 0.01 and b.health == hp, "back where it was, as hurt as it was")


func test_every_boss_does_all_its_moves() -> void:
	seed(11)
	for id in SCRIPTS:
		var b := _boss(id)
		var victim := spawn_critter(TEST_DEF, Vector3(0, 0.1, -50))
		victim.team = 1
		victim.max_health = 100000.0
		victim.health = victim.max_health
		await wait_physics(5)
		var moves: Array = {"brute": ["_pound", "_toss", "_leap", "_gobble", "_roar_action"],
			"robot": ["_clamp", "_lasers", "_barrage", "_wind_down", "_roar_action"],
			"hamster": ["_bite", "_charge", "_spit", "_burrow", "_roar_action"],
			"owl": ["_snatch", "_rake", "_volley", "_roar_action", "_perch"],
			"nutcracker": ["_march", "_sweep", "_crack", "_walnuts", "_roar_action"],
			"ferret": ["_bite", "_pop_goes", "_dance", "_roar_action"]}[id]
		for m in moves:
			b.global_position = Vector3.ZERO
			if b is OwlBoss:   # (up where she flies)
				b._air = true
				b.global_position = Vector3(0, OwlBoss.CRUISE, 40)
			var near: float = {"_gobble": -9, "_bite": -25 if b is FerretBoss else -9, "_crack": -12, "_sweep": -15}.get(m, -50)
			victim.global_position = Vector3(0, 0.1, near)
			victim.velocity = Vector3.ZERO
			await wait_physics(3)
			var a: BossAction = b.call(m, victim) if m not in ["_pound", "_clamp", "_wind_down", "_roar_action", "_crack"] else b.call(m)
			check(a != null, "%s: %s makes an action" % [id, m])
			if a == null:
				continue
			b.start(a)
			var frames := 0
			while b.action != null and frames < 900:
				await wait_physics(1)
				frames += 1
			check(b.action == null, "%s: %s plays out (%.1f s)" % [id, m, frames / 60.0])
			check(b.alive and b.visible, "%s: and it's still up afterwards" % id)
		check(victim.health < victim.max_health, "%s: its moves hurt the critter they were aimed at" % id)
		b.queue_free()
		victim.queue_free()
		await wait_physics(3)


## Old Hoot arrives gliding in out of the sky, lands, takes off again, and
## circles whoever she's after, up high.
func test_old_hoot_flies() -> void:
	var b: OwlBoss = (load(SCRIPTS["owl"]) as GDScript).new()
	add_child(b)
	var you := spawn_critter(TEST_DEF, Vector3(0, 0.1, 60))
	you.team = 1
	await wait_physics(3)
	b.arrive(Vector3.ZERO, you.global_position)
	check(b.global_position.length() < 0.1 and not b.visible, "where she'll land, unseen, till her glide starts (where BossIntro sets up)")
	await wait_physics(2)
	check(b.global_position.y > 40.0 and b._air and b.visible, "she glides in from high up (%.0f m)" % b.global_position.y)
	await _until(func(): return b.state == Boss.State.FIGHTING, 8.0)
	check(b.state == Boss.State.FIGHTING and not b._air and b.global_position.y < 0.5, "she lands where she was going to")
	await _until(func(): return b._air and b.global_position.y > 20.0, 12.0)
	check(b._air and b.global_position.y > 20.0, "and takes off again (%.0f m up)" % b.global_position.y)
	b.cooldown(&"snatch", 99.0)
	b.cooldown(&"rake", 99.0)
	b.cooldown(&"volley", 99.0)
	b.cooldown(&"perch", 99.0)
	b.cooldown(&"hoot", 99.0)
	await wait_physics(360)
	var flat := Vector2(b.global_position.x - you.global_position.x, b.global_position.z - you.global_position.z).length()
	check(b._air and b.global_position.y > 20.0 and absf(flat - OwlBoss.ORBIT) < 25.0,
		"circling you up high (%.0f m up, %.0f m out)" % [b.global_position.y, flat])
	var nose := b.model.global_basis.z.normalized()   # (the model's front: it's turned to face the boss's)
	check(nose.y < -0.2, "her body pitched into her flight, nose down (%.2f)" % nose.y)
	b.queue_free()


## Snatch: whoever's still in the ring when she comes down is carried off,
## dropped from high up and hurt by the fall; you can wriggle free (jump).
func test_old_hoot_carries_a_critter_off_and_drops_it() -> void:
	var b := _boss("owl", Vector3(0, OwlBoss.CRUISE, 50))
	b._air = true
	var bot := spawn_critter(TEST_DEF, Vector3(0, 0.1, -20))
	bot.team = 1
	bot.max_health = 1000.0
	bot.health = 1000.0
	await wait_physics(5)
	b.start(b._snatch(bot))
	await _until(func(): return b.holding() != null, 4.0)
	check(b.holding() == bot and bot.held_by == b, "she's got it")
	await wait_physics(60)
	check(bot.global_position.y > 10.0, "and she's carrying it off, up (%.0f m)" % bot.global_position.y)
	await _until(func(): return b.action == null, 6.0)
	check(b.holding() == null and bot.held_by == null, "let go")
	await _until(func(): return bot.is_on_floor(), 6.0)
	await wait_physics(3)
	check(bot.health < 1000.0 - 40.0, "hurt by the fall (%.0f)" % (1000.0 - bot.health))
	# you, caught: jump, and keep jumping
	var you := spawn_critter(TEST_DEF, Vector3(30, 0.1, -20))
	you.team = 1
	you.is_player = true
	you.max_health = 1000.0
	you.health = 1000.0
	b._air = true
	b.global_position = Vector3(30, OwlBoss.CRUISE, 50)
	b.cooldown(&"snatch", 0.0)
	await wait_physics(5)
	b.start(b._snatch(you))
	await _until(func(): return b.holding() == you, 4.0)
	check(b.holding() == you, "she's got you")
	for i in OwlBoss.STRUGGLES:
		you.want_jump = true
		await wait_physics(4)
	check(b.holding() == null and you.held_by == null and b.action != null, "you wriggled free before she let go")


## Shot in the wings as she dives, she comes down, and lies there stunned.
func test_shooting_old_hoots_wings_brings_her_down() -> void:
	var b := _boss("owl", Vector3(0, OwlBoss.CRUISE, 50))
	b._air = true
	var you := spawn_critter(TEST_DEF, Vector3(40, 0.1, -60))
	you.team = 1
	you.is_player = true
	var bot := spawn_critter(TEST_DEF, Vector3(0, 0.1, -20))
	bot.team = 1
	await wait_physics(5)
	b.start(b._snatch(bot))
	await _until(func(): return b.action != null and b.action.t > 1.2, 3.0)
	check(b._diving, "diving")
	for i in int(OwlBoss.GROUND_AT) + 1:
		var shot := DamageInfo.make(10.0, DamageInfo.Kind.BULLET, you, &"carrot_rifle")
		shot.bone_role = &"l_upper_arm" if i % 2 == 0 else &"r_lower_arm"
		b.take_damage(shot)
	check(b.action != null and b.action.name == &"grounded", "grounded (%s)" % (b.action.name if b.action else "nothing"))
	await _until(func(): return not b._air, 3.0)
	check(not b._air and b.global_position.y < 1.0 and b.vulnerable(), "down on the ground, stunned (%.1f m)" % b.global_position.y)


## Her hoot knocks everyone in the ring under her off their feet.
func test_old_hoots_hoot_knocks_them_down() -> void:
	var b := _boss("owl", Vector3(0, OwlBoss.CRUISE, 0))
	b._air = true
	var them: Array[Critter] = []
	for i in 3:
		var c := spawn_critter(TEST_DEF, Vector3(i * 8.0 - 8.0, 0.1, 6.0))
		c.team = 1
		c.max_health = 1000.0
		c.health = 1000.0
		them.append(c)
	var far := spawn_critter(TEST_DEF, Vector3(80, 0.1, 0))
	far.team = 1
	await wait_physics(5)
	b.start(b._roar_action())
	await wait_physics(60)
	check(them.all(func(c): return c.is_knocked() or c.visual.knocked), "everyone under her is knocked down")
	check(not (far.is_knocked() or far.visual.knocked), "not who's out of the ring")


## Shot in the legs enough, Crackjaw teeters and goes over the way he's
## facing: flattening whoever's under him, then lying there with his head on
## the floor, taking double, till he gets back up. Not again straight away.
func test_shooting_crackjaws_legs_puts_him_over() -> void:
	var b: NutcrackerBoss = _boss("nutcracker")
	var you := spawn_critter(TEST_DEF, Vector3(60, 0.1, 20))
	you.team = 1
	you.is_player = true
	var under := spawn_critter(TEST_DEF, Vector3(0, 0.1, -12))   # (he faces -Z: where he'll land)
	under.team = 1
	under.max_health = 1000.0
	under.health = 1000.0
	await wait_physics(5)
	var head_up := b.bone_point(&"head", 0.5).y
	for i in int(NutcrackerBoss.TOPPLE_AT) - 1:
		var shot := DamageInfo.make(10.0, DamageInfo.Kind.BULLET, you, &"carrot_rifle")
		shot.bone_role = &"l_lower_leg" if i % 2 == 0 else &"r_upper_leg"
		b.take_damage(shot)
	check(b.action == null, "a few hits on his legs only wobble him")
	var arm_shot := DamageInfo.make(10.0, DamageInfo.Kind.BULLET, you, &"carrot_rifle")
	arm_shot.bone_role = &"l_upper_arm"
	b.take_damage(arm_shot)
	check(b.action == null, "a hit elsewhere doesn't count")
	var last := DamageInfo.make(10.0, DamageInfo.Kind.BULLET, you, &"carrot_rifle")
	last.bone_role = &"r_foot"
	b.take_damage(last)
	check(b.action != null and b.action.name == &"timber", "enough on his legs: TIMBER (%s)" % (b.action.name if b.action else "nothing"))
	await _until(func(): return b.vulnerable(), 3.0)
	await wait_physics(10)
	check(b.toppled() and b.bone_point(&"head", 0.5).y < head_up * 0.35, "down flat, his head low (%.1f m, was %.1f)" % [
		b.bone_point(&"head", 0.5).y, head_up])
	check(under.health < under.max_health, "whoever was where he landed was flattened")
	var hp := b.health
	var head_shot := DamageInfo.make(100.0, DamageInfo.Kind.BULLET, you, &"carrot_rifle")
	head_shot.bone_role = &"head"
	b.take_damage(head_shot)
	check(hp - b.health > 100.0 * b.armor * 1.8 * 1.9, "a shot on his head counts double while he's down (%.0f)" % (hp - b.health))
	await _until(func(): return b.action == null, NutcrackerBoss.TOPPLED_FOR + 4.0)
	await wait_physics(5)
	check(b.action == null and not b.vulnerable() and b.bone_point(&"head", 0.5).y > head_up * 0.9, "and back on his feet")
	for i in int(NutcrackerBoss.TOPPLE_AT) + 2:
		var shot := DamageInfo.make(10.0, DamageInfo.Kind.BULLET, you, &"carrot_rifle")
		shot.bone_role = &"l_lower_leg"
		b.take_damage(shot)
	check(b.action == null, "not straight back over")


## Beaten while he's flat on his face, he stays down (not up on his feet
## first, to fall over backwards).
func test_crackjaw_beaten_while_hes_down_stays_down() -> void:
	var b: NutcrackerBoss = _boss("nutcracker")
	var you := spawn_critter(TEST_DEF, Vector3(60, 0.1, 20))
	you.team = 1
	you.is_player = true
	await wait_physics(5)
	var head_up := b.bone_point(&"head", 0.5).y
	b._topple()
	await _until(func(): return b.toppled(), 4.0)
	await wait_physics(5)
	check(b.toppled(), "down on his face")
	b.take_damage(DamageInfo.make(1e9, DamageInfo.Kind.BULLET, you, &"carrot_sniper"))
	var highest := 0.0
	for i in 150:
		highest = maxf(highest, b.bone_point(&"head", 0.5).y)
		await wait_physics(1)
	check(not b.alive and highest < head_up * 0.35, "beaten there, his head stays low (at most %.1f m, standing %.1f)" % [highest, head_up])


## His sabre sweeps the floor in front of him: whoever's on the ground in its
## way goes flying; whoever's in the air as it passes is missed.
func test_jumping_crackjaws_sabre() -> void:
	var b: NutcrackerBoss = _boss("nutcracker")
	var grounded := spawn_critter(TEST_DEF, Vector3(-8, 0.1, -14))
	var jumper := spawn_critter(TEST_DEF, Vector3(8, 4.0, -14))
	var behind := spawn_critter(TEST_DEF, Vector3(0, 0.1, 14))
	for c in [grounded, jumper, behind]:
		c.team = 1
		c.max_health = 1000.0
		c.health = 1000.0
	await wait_physics(5)
	b.start(b._sweep(grounded))
	while b.action != null:
		jumper.global_position = Vector3(8, 4.0, -14)   # (up in the air the whole time)
		jumper.velocity = Vector3.ZERO
		await wait_physics(1)
	check(grounded.health < grounded.max_health, "on the ground in front of him: swept")
	check(jumper.health == jumper.max_health, "in the air as it passed: missed")
	check(behind.health == behind.max_health, "behind him: out of its reach")


## Pop Goes the Weasel: she digs in and goes under (nothing there to see or
## to hit), a red ring goes down under whoever she's after before she comes
## up, and whoever's still in it when she does goes flying. Up out of her
## hole her nose counts three times over, and bopped on it enough she's
## seeing stars: out of her hole and down, taking double, till she gets up.
func test_noodle_pops_up_under_you_and_a_bop_on_the_nose_puts_her_down() -> void:
	var b: FerretBoss = _boss("ferret")
	var you := spawn_critter(TEST_DEF, Vector3(30, 0.1, 60))
	you.team = 1
	you.is_player = true
	var victim := spawn_critter(TEST_DEF, Vector3(0, 0.1, -80))
	victim.team = 1
	victim.max_health = 1000.0
	victim.health = 1000.0
	await wait_physics(5)
	b.start(b._pop_goes(victim))
	await _until(func(): return b._under, 3.0)
	check(b._under and not b.model.visible and (b.hitboxes[&"head"] as Area3D).collision_layer == 0, "she's gone under: nothing to see or hit")
	var hp := b.health
	b.take_damage(DamageInfo.make(500.0, DamageInfo.Kind.EXPLOSION, you, &"carrot_rocket_launcher"))
	check(b.health == hp, "a blast over her does nothing down there")
	var ringed := func() -> bool:
		return b.danger.any(func(d): return Vector2(d[0].x - victim.global_position.x, d[0].z - victim.global_position.z).length() < 8.0)
	await _until(ringed, 4.0)
	check(b._under and ringed.call(), "a red ring under whoever she's after, before she comes up")
	await _until(func(): return b._popped, 3.0)
	check(b._popped and b.model.visible and victim.health < victim.max_health, "POP! up under them, and they took it (%.0f)" % victim.health)
	check(Vector2(b.global_position.x, b.global_position.z + 80.0).length() < 6.0, "she came up where the ring was")
	# her nose, up out of the hole
	hp = b.health
	var body := DamageInfo.make(20.0, DamageInfo.Kind.BULLET, you, &"carrot_rifle")
	body.bone_role = &"chest"
	b.take_damage(body)
	var chest := hp - b.health
	var bops := 0.0
	hp = b.health
	b.take_damage(_bop(you))
	bops += 1.0
	check(hp - b.health > chest * 2.8, "up out of her hole, her nose counts three times over (%.0f vs %.0f)" % [hp - b.health, chest])
	while bops < FerretBoss.WHACK_AT - 1.0:
		b.take_damage(_bop(you))
		bops += 1.0
	check(b.action != null and b.action.name == &"popgoes", "a few bops only make her flinch")
	b.take_damage(_bop(you))
	check(b.action != null and b.action.name == &"dizzy" and b.vulnerable() and not b._popped, "bopped enough: seeing stars (%s)" % (
		b.action.name if b.action else &""))
	await wait_physics(45)
	check(b.bone_point(&"head", 0.5).y < 9.0, "out of her hole and flat on the bedding (her head %.1f m up)" % b.bone_point(&"head", 0.5).y)
	await _until(func(): return b.action == null, FerretBoss.DIZZY_FOR + 3.0)
	check(b.action == null and not b.vulnerable() and not b._dizzy and b.bone_point(&"head", 0.5).y > 9.0, "and back on her feet")


func _bop(by: Critter) -> DamageInfo:
	var d := DamageInfo.make(20.0, DamageInfo.Kind.BULLET, by, &"carrot_rifle")
	d.bone_role = &"head"
	return d


## Where she comes up: out of the mouth of a hamster's burrow, if there's one
## near where she'd come up (HamsterCage.burrows), or out of the bedding.
func test_noodle_comes_up_out_of_a_burrow_if_ones_near() -> void:
	var b: FerretBoss = _boss("ferret")
	var mm := FakeMatch.new()
	var isl := FakeIsland.new()
	isl.burrows = [{"mouth": Vector3(40, 0, 10), "out": Vector3.RIGHT}, {"mouth": Vector3(-200, 0, 0), "out": Vector3.LEFT}]
	mm.island = isl
	b.match_manager = mm
	check(b._burrow_near(Vector3(50, 0, 14)) == Vector3(40, 0, 10), "a burrow's mouth 11 m off: out of that")
	check(b._burrow_near(Vector3(100, 0, 0)) == Vector3.INF, "none near: out of the bedding")
	b.match_manager = null
	mm.free()
	isl.free()


class FakeIsland extends Node:
	var burrows: Array = []
	var habitrail: Array = []


class FakeMatch extends Node:
	var island: Node


## Tube Town (HamsterCage.habitrail): going by under it she sets it rattling
## on its connectors (not every frame), a burrow's roll too, and it settles
## back; coming up under a tube she knocks it clean off them, flying, and it
## comes down on the bedding. A burrow's roll she just comes up out of.
func test_noodle_rattles_tube_town_and_knocks_it_loose() -> void:
	var b: FerretBoss = _boss("ferret")
	var rng := RandomNumberGenerator.new()
	var tube := CageProps.tube(rng, &"teal", CageProps.TOWN_TUBE)   # (along z, through (0, 0, -60))
	add_child(tube)
	tube.global_position = Vector3(0, 0, -60)
	var half := CageProps.TOWN_TUBE * 0.5
	var pc := Habitrail.piece(tube, &"tube", Vector3(0, 0, -60 - half), Vector3(0, 0, -60 + half), CageProps.TUBE_R + CageProps.TUBE_WALL)
	var roll := CageProps.roll(rng, 12.0)
	add_child(roll)
	roll.global_position = Vector3(60, 0, 0)
	var burrow := Habitrail.piece(roll, &"burrow", roll.global_position, roll.global_position, 2.6)
	var isl := FakeIsland.new()
	isl.habitrail = [pc, burrow]
	var mm := FakeMatch.new()
	mm.island = isl
	b.match_manager = mm
	var victim := spawn_critter(TEST_DEF, Vector3(0, 0.6, -60))   # (hiding in the tube)
	victim.team = 1
	victim.max_health = 1000.0
	victim.health = 1000.0
	await wait_physics(3)
	var look: Node3D = tube.get_node("Mesh")
	b._rattle_near(Vector3(14, 0, -60))
	check(int(pc.get("rattled", 0)) == 1, "going by under it, the tube rattles")
	await wait_physics(4)
	check(look.has_meta(&"rest") and not look.transform.is_equal_approx(look.get_meta(&"rest")), "it jumps about on its connectors")
	b._rattle_near(Vector3(14, 0, -60))
	check(int(pc.get("rattled", 0)) == 1, "(not again straight away)")
	b._rattle_near(Vector3(60, 0, 10))
	check(int(burrow.get("rattled", 0)) == 1, "a burrow's roll rattles too")
	await wait_physics(40)
	check(look.transform.is_equal_approx(look.get_meta(&"rest")), "and settles back where it was")
	b._pop_up(Vector3(0, 0, -60), victim)
	await wait_physics(2)
	check(pc.loose and not is_instance_valid(tube), "coming up under the tube, she knocks it off its connectors")
	var flying: Array = get_children().filter(func(c): return c is ToyBlock.Loose)
	check(flying.size() == 1 and (flying[0] as RigidBody3D).linear_velocity.y > 8.0, "it goes flying (%.1f m/s up)" %
		((flying[0] as RigidBody3D).linear_velocity.y if flying.size() == 1 else 0.0))
	check(victim.health < victim.max_health, "and whoever was in it goes flying too (%.0f)" % victim.health)
	await wait_physics(240)
	check(flying.size() == 1 and (flying[0] as Node3D).global_position.y < 8.0, "it comes down on the bedding")
	b._pop_up(Vector3(60, 0, 0))
	await wait_physics(2)
	check(not burrow.loose and is_instance_valid(roll), "a burrow's roll stays put (she comes up out of it)")
	b.match_manager = null
	mm.free()
	isl.free()


## The War Dance: hops at you, each landing on its own red ring; then she's
## danced out and asleep (taking double, her eyes shut), and wakes in a poof
## of musk that knocks back whoever's close and hangs there, stinging.
func test_noodle_dances_herself_to_sleep_and_wakes_up_musky() -> void:
	var b: FerretBoss = _boss("ferret")
	var you := spawn_critter(TEST_DEF, Vector3(60, 0.1, 90))
	you.team = 1
	you.is_player = true
	var victim := spawn_critter(TEST_DEF, Vector3(0, 0.1, -60))
	victim.team = 1
	victim.max_health = 2000.0
	victim.health = 2000.0
	await wait_physics(5)
	b.start(b._dance(victim))
	await _until(func(): return not b.danger.is_empty(), 2.0)
	check(not b.danger.is_empty(), "a red ring where her first hop lands")
	await _until(func(): return b._asleep, 9.0)
	await wait_physics(2)
	check(b._asleep and b.vulnerable(), "danced out: asleep")
	check(b.global_position.distance_to(Vector3.ZERO) > 30.0, "she hopped over toward them (%.0f m)" % b.global_position.length())
	check(victim.health < victim.max_health, "her landings hurt whoever she was after (%.0f)" % victim.health)
	check(not b._eye_skin.is_empty() and b._eye_skin.all(func(m): return m.emission_energy_multiplier == 0.0), "her eyes shut")
	var hp := b.health
	var hit := DamageInfo.make(30.0, DamageInfo.Kind.BULLET, you, &"carrot_rifle")
	hit.bone_role = &"chest"
	b.take_damage(hit)
	check_near(hp - b.health, 30.0 * Boss.VULNERABLE, 0.5, "a hit counts double while she sleeps")
	var side := b.global_basis.x
	var close := spawn_critter(TEST_DEF, b.global_position + side * 11.0 + Vector3.UP * 0.1)
	close.team = 1
	close.max_health = 1000.0
	close.health = 1000.0
	await _until(func(): return not b._asleep, FerretBoss.SLEEP_FOR + 1.0)
	await wait_physics(5)
	check(not b._asleep and close.health < close.max_health, "awake, in a poof that caught whoever was close (%.0f)" % close.health)
	check(b._clouds.size() == 1 and b.danger.any(func(d): return float(d[1]) == FerretBoss.MUSK_R), "and the musk hangs there (the bots keep out)")
	var late := spawn_critter(TEST_DEF, (b._clouds[0][0] as Vector3) + side * 12.0 + Vector3.UP * 0.1)
	late.team = 1
	await wait_physics(80)
	check(late.health < 100.0, "standing in it stings (%.0f)" % late.health)


## Beaten while she's stood up out of a hole, she slumps out of it (not out
## onto her feet first); beaten asleep, she just doesn't wake.
func test_noodle_beaten_mid_pop_or_asleep_stays_down() -> void:
	for how in ["popped", "asleep"]:
		var b: FerretBoss = _boss("ferret")
		var you := spawn_critter(TEST_DEF, Vector3(60, 0.1, 60))
		you.team = 1
		you.is_player = true
		var victim := spawn_critter(TEST_DEF, Vector3(0, 0.1, -60))
		victim.team = 1
		victim.max_health = 5000.0
		victim.health = 5000.0
		await wait_physics(5)
		if how == "popped":
			b.start(b._pop_goes(victim))
			await _until(func(): return b._popped, 6.0)
		else:
			b.start(b._dance(victim))
			await _until(func(): return b._asleep, 9.0)
		await wait_physics(15)
		var was := b.bone_point(&"head", 0.5).y
		b.take_damage(DamageInfo.make(1e9, DamageInfo.Kind.BULLET, you, &"carrot_sniper"))
		check(not b.alive, "%s: beaten" % how)
		await wait_physics(3)
		if how == "popped":
			check(b.bone_point(&"hips", 0.0).y < b.global_position.y, "popped: still down her hole as she goes (her hips %.1f m)" %
				(b.bone_point(&"hips", 0.0).y - b.global_position.y))
		var highest := 0.0
		for i in 160:
			highest = maxf(highest, b.bone_point(&"head", 0.5).y)
			await wait_physics(1)
		check(b.bone_point(&"head", 0.5).y < 9.0, "%s: down on the bedding (her head %.1f m up)" % [how, b.bone_point(&"head", 0.5).y])
		if how == "asleep":
			check(highest < was + 1.5, "asleep: she never woke up first (her head at most %.1f m, %.1f m asleep)" % [highest, was])
		b.queue_free()
		you.queue_free()
		victim.queue_free()
		await wait_physics(3)


func _until(done: Callable, seconds: float) -> void:
	var t := 0.0
	while t < seconds and not done.call():
		await get_tree().physics_frame
		t += 1.0 / Engine.physics_ticks_per_second


## A whole Boss Battle on each map: the drop, the boss turning up, the bots
## fighting it (it takes damage, it beats some of them down), and the match
## won when it falls. And against Old Hoot on the island, by night.
func test_boss_battles() -> void:
	for map in ["island", "cage", "toybox"]:
		await _boss_battle(map)
	await _boss_battle("island", "owl")
	await _boss_battle("toybox", "nutcracker")
	await _boss_battle("cage", "ferret")


func _boss_battle(map: String, boss_id := "") -> void:
	WarrenSim.reset_for_tests()
	Settings.set_value(&"boss", boss_id, false)
	Settings.set_value(&"opponents", 7, false)
	Settings.set_value(&"difficulty", Settings.Difficulty.NORMAL, false)
	Settings.set_value(&"seed", 777, false)
	Settings.set_value(&"quality", 0, false)
	Settings.set_value(&"map", map, false)
	Settings.set_value(&"mode", "boss", false)
	GameSession.quick = true
	BossFX._tex.clear()
	var game: Node = load(GAME).instantiate()
	get_tree().root.add_child(game)
	var t := 0.0
	while (game.match_manager == null or game.match_manager.phase == MatchManager.Phase.LOADING) and t < 90.0:
		await get_tree().process_frame
		t += get_process_delta_time()
	var mm: MatchManager = game.match_manager
	check(mm != null and mm.mode == "boss", "%s: a Boss Battle" % map)
	check(["ring", "disc", "strip", "foam", "arc"].all(func(k): return BossFX._tex.has(k)),
		"%s: its warnings' textures made while it loaded, not on its first blow (%s)" % [map, BossFX._tex.keys()])
	if mm == null:
		game.queue_free()
		return
	check(mm.boss != null and mm.boss.state == Boss.State.WAITING, "%s: its boss waits for the drop" % map)
	if boss_id != "":
		check(mm.boss.id == boss_id, "%s: the boss picked (%s)" % [map, mm.boss.id])
		check((game.get_node("World/Lighting") as WorldLighting).night == (boss_id == "owl"), "%s: by night, with Old Hoot" % map)
	check(mm.total == MatchManager.TEAM_SIZE, "%s: 25 critters against it (%d)" % [map, mm.total])
	check(mm.critters.all(func(c): return c.team == 1), "%s: all on the same side" % map)
	await wait_physics(10)
	mm.player_jump()
	Engine.time_scale = 4.0
	var sim := 0.0
	while mm.phase == MatchManager.Phase.DROPPING and sim < 120.0:
		await get_tree().physics_frame
		sim += Engine.time_scale / Engine.physics_ticks_per_second
	check(mm.phase == MatchManager.Phase.PLAYING, "%s: everyone's down" % map)
	check(mm.storm == null or not mm.storm.active, "%s: no Briar in a Boss Battle" % map)
	check(mm.boss_countdown() > 0.0, "%s: the boss is on its way (%.0f s)" % [map, mm.boss_countdown()])
	var said := []
	Events.taunt.connect(func(_c, text): said.append(text))
	var fought: float = StatBook.boss(mm.boss.id).fought
	mm.release_boss()
	check(mm.boss.state != Boss.State.WAITING and AIBrain.boss == mm.boss, "%s: it turned up" % map)
	check(game.get_node_or_null("BossIntro") is BossIntro, "%s: its arrival plays as a cinematic" % map)
	check(StatBook.boss(mm.boss.id).fought == fought + 1.0, "%s: you faced it" % map)
	var deaths := [0]
	Events.critter_died.connect(func(_v, _i): deaths[0] += 1)
	var hp := mm.boss.health
	sim = 0.0
	while sim < 90.0 and mm.phase == MatchManager.Phase.PLAYING:
		await get_tree().physics_frame
		sim += Engine.time_scale / Engine.physics_ticks_per_second
	print("    %s: %.0f s of boss fight: boss %.0f -> %.0f, %d critters down, %d left, %.0f dealt out; it did %s" % [map, sim, hp,
		mm.boss.health, deaths[0], mm.team_counts()[1], mm.boss.damage_done, mm.boss.moves_used])
	check(mm.boss.health < hp, "%s: the bots hurt it (%.0f)" % [map, hp - mm.boss.health])
	check(deaths[0] >= 1 or mm.boss.damage_done >= 250.0, "%s: it beat some of them down, or near enough (%d down, %.0f dealt out)" % [map,
		deaths[0], mm.boss.damage_done])
	if mm.phase == MatchManager.Phase.PLAYING:
		var won := [false]
		mm.finished.connect(func(_w, _p): won[0] = true)
		var beaten: float = StatBook.boss(mm.boss.id).beaten
		var waited := 0.0
		while mm.boss is FerretBoss and (mm.boss as FerretBoss)._under and waited < 30.0:   # (down a hole, Noodle can't be hit)
			await get_tree().physics_frame
			waited += Engine.time_scale / Engine.physics_ticks_per_second
		mm.boss.take_damage(DamageInfo.make(1e9, DamageInfo.Kind.BULLET, mm.player, &"carrot_sniper"))
		check(won[0] and mm.winning_team == 1 and mm.phase == MatchManager.Phase.ENDED, "%s: it fell, and your side won" % map)
		check(StatBook.boss(mm.boss.id).beaten == beaten + 1.0, "%s: beaten, on your record" % map)
		var ed := WarrenSim.edition()
		var news: Dictionary = BossLore.NEWS[mm.boss.id]
		check(ed.get("extra", "") == "boss" and String(ed.stories[0].title) in [news.fell, news.again] and WarrenSim.has_news(),
			"%s: the Gazette's special edition: %s" % [map, ed.get("stories", [{}])[0].get("title", "")])
	var boss_lines := []
	for lines in Cast.BOSS_LINES.values() + [Cast.BOSS_NAME_LINES.values(), [Cast.BOSS_KEY_LINE]]:
		boss_lines.append_array(lines)
	var shouted := said.filter(func(t): return boss_lines.has(t))
	print("    %s: the rogues shouted %s" % [map, shouted])
	check(shouted.size() >= 2, "%s: the rogues shouted about it (%d)" % [map, shouted.size()])
	Engine.time_scale = 1.0
	Settings.set_value(&"mode", "royale", false)
	Settings.set_value(&"map", "island", false)
	Settings.set_value(&"boss", "", false)
	game.queue_free()
	await wait_frames(5)
