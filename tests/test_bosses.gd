extends TestCase
## The Boss Battle's bosses: ten critters tall, their hitboxes on them,
## carrots (and blasts, and clubs) hurting them (the head more, bots' carrots
## less), their blows hurting who's close and sparing who's far or in the
## air, the bots fighting them and getting out from under their blows, and a
## boss going down for good. Then a whole Boss Battle on each map.

const TEST_DEF := "res://data/critters/test_critter.tres"
const BUN := "res://data/critters/bun.tres"
const SCRIPTS := {"brute": "res://src/bosses/brute_boss.gd", "robot": "res://src/bosses/robot_boss.gd",
	"hamster": "res://src/bosses/hamster_boss.gd"}
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
			"hamster": ["_bite", "_charge", "_spit", "_burrow", "_roar_action"]}[id]
		for m in moves:
			b.global_position = Vector3.ZERO
			victim.global_position = Vector3(0, 0.1, -50 if m not in ["_gobble", "_bite"] else -9)
			victim.velocity = Vector3.ZERO
			await wait_physics(3)
			var a: BossAction = b.call(m, victim) if m not in ["_pound", "_clamp", "_wind_down", "_roar_action"] else b.call(m)
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


## A whole Boss Battle on each map: the drop, the boss turning up, the bots
## fighting it (it takes damage, it beats some of them down), and the match
## won when it falls.
func test_boss_battles() -> void:
	for map in ["island", "cage", "toybox"]:
		await _boss_battle(map)


func _boss_battle(map: String) -> void:
	WarrenSim.reset_for_tests()
	Settings.set_value(&"opponents", 7, false)
	Settings.set_value(&"difficulty", Settings.Difficulty.NORMAL, false)
	Settings.set_value(&"seed", 777, false)
	Settings.set_value(&"quality", 0, false)
	Settings.set_value(&"map", map, false)
	Settings.set_value(&"mode", "boss", false)
	GameSession.quick = true
	var game: Node = load(GAME).instantiate()
	get_tree().root.add_child(game)
	var t := 0.0
	while (game.match_manager == null or game.match_manager.phase == MatchManager.Phase.LOADING) and t < 90.0:
		await get_tree().process_frame
		t += get_process_delta_time()
	var mm: MatchManager = game.match_manager
	check(mm != null and mm.mode == "boss", "%s: a Boss Battle" % map)
	if mm == null:
		game.queue_free()
		return
	check(mm.boss != null and mm.boss.state == Boss.State.WAITING, "%s: its boss waits for the drop" % map)
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
	game.queue_free()
	await wait_frames(5)
