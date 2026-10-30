extends TestCase
## A Team Battle: 25 against 25, each team on its own balloon down its own
## side of the map, your team blue-tagged, nobody hurting their own side,
## and the match over when one side is gone.

const GAME := "res://scenes/game.tscn"


func after_each() -> void:
	Engine.time_scale = 1.0
	Settings.set_value(&"mode", "royale", false)
	await super()


func test_a_team_battle() -> void:
	Settings.set_value(&"opponents", 7, false)   # (ignored: a team battle is always 25 v 25)
	Settings.set_value(&"difficulty", Settings.Difficulty.NORMAL, false)
	Settings.set_value(&"seed", 5150, false)
	Settings.set_value(&"quality", 0, false)
	Settings.set_value(&"map", "island", false)
	Settings.set_value(&"mode", "teams", false)
	GameSession.quick = true
	var game: Node = load(GAME).instantiate()
	get_tree().root.add_child(game)
	var t := 0.0
	while (game.match_manager == null or game.match_manager.phase == MatchManager.Phase.LOADING) and t < 90.0:
		await get_tree().process_frame
		t += get_process_delta_time()
	var mm: MatchManager = game.match_manager
	check(mm != null and mm.mode == "teams", "a Team Battle")
	if mm == null:
		game.queue_free()
		return
	var counts := mm.team_counts()
	check(mm.total == 50 and counts[1] == 25 and counts[2] == 25, "25 against 25 (%d: %d v %d)" % [mm.total, counts[1], counts[2]])
	check(mm.player.team == 1, "you're on team 1")
	check(mm.enemy_ship != null and mm.dropship != mm.enemy_ship, "the other team has its own balloon")
	var theirs := mm.critters.filter(func(c): return c.team == 2)
	check(theirs.all(func(c): return mm.enemy_ship.passengers.has(c)), "the other team rides it")
	var mates := mm.critters.filter(func(c): return c.team == 1 and c != mm.player)
	check(mates.all(func(c): return mm.dropship.passengers.has(c)), "and yours rides yours")
	check(mates.all(func(c): return c.visual.name_tag and c.visual.name_tag.text.begins_with("◆")), "your team mates wear blue tags")
	check(theirs.all(func(c): return c.visual.name_tag == null or not c.visual.name_tag.text.begins_with("◆")), "the other team doesn't")
	# the two routes run down opposite sides of the island, the same way
	var a := (mm.dropship.start + mm.dropship.finish) * 0.5
	var b := (mm.enemy_ship.start + mm.enemy_ship.finish) * 0.5
	check(Vector2(a.x - b.x, a.z - b.z).length() > mm.island.terrain.island_radius * 0.5, "the balloons fly well apart (%.0f m)" % Vector2(a.x - b.x, a.z - b.z).length())
	# nobody ever hurts their own side
	var friendly := [0]
	Events.critter_damaged.connect(func(v, info):
		if info.attacker is Critter and info.attacker != v and (info.attacker as Critter).team == (v as Critter).team:
			friendly[0] += 1)
	await wait_physics(10)
	mm.player_jump()
	Engine.time_scale = 4.0
	var sim := 0.0
	while mm.phase == MatchManager.Phase.DROPPING and sim < 150.0:
		await get_tree().physics_frame
		sim += Engine.time_scale / Engine.physics_ticks_per_second
	check(mm.phase == MatchManager.Phase.PLAYING, "everyone's down")
	check(mm.storm.active, "the Briar closes in on a Team Battle too")
	# each team lands on its own side
	var mid1 := Vector3.ZERO
	var mid2 := Vector3.ZERO
	for c in mm.critters:
		if c.team == 1:
			mid1 += c.global_position / 25.0
		elif c.team == 2:
			mid2 += c.global_position / 25.0
	check(Vector2(mid1.x - mid2.x, mid1.z - mid2.z).length() > 150.0, "the teams landed apart (%.0f m)" % Vector2(mid1.x - mid2.x, mid1.z - mid2.z).length())
	check(not mm.squad.is_empty() and mm.squad.all(func(c): return c.team == 1), "your squad jumped with you (%d)" % mm.squad.size())
	var deaths := [0]
	Events.critter_died.connect(func(_v, _i): deaths[0] += 1)
	sim = 0.0
	while sim < 120.0 and mm.phase == MatchManager.Phase.PLAYING:
		await get_tree().physics_frame
		sim += Engine.time_scale / Engine.physics_ticks_per_second
	counts = mm.team_counts()
	print("    %.0f s of team battle: %d down, %d v %d left, %d friendly hits" % [sim, deaths[0], counts[1], counts[2], friendly[0]])
	check(deaths[0] >= 3, "the teams fought (%d down)" % deaths[0])
	check(friendly[0] == 0, "nobody hurt their own side (%d)" % friendly[0])
	# the last of the other team goes down: your side wins
	var ended := [null, -1]
	mm.finished.connect(func(w, p):
		ended[0] = w
		ended[1] = p)
	for c in mm.alive_critters():
		if c.team == 2 and mm.phase != MatchManager.Phase.ENDED:
			var info := DamageInfo.make(9999.0, DamageInfo.Kind.BULLET, mm.player, &"carrot_rifle")
			c.take_damage(info)
	check(mm.phase == MatchManager.Phase.ENDED and mm.winning_team == 1, "the other team's gone: yours won (team %d)" % mm.winning_team)
	check(int(ended[1]) == 1, "and the match ended with you first")
	Engine.time_scale = 1.0
	Settings.set_value(&"map", "island", false)
	game.queue_free()
	await wait_frames(5)
