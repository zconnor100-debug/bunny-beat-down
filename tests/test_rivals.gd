extends TestCase
## Bots are characters: each has a personality for life, the rival book
## remembers who beat whom across runs (in its own test file here), a bot that
## has beaten you twice becomes your rival, comes back in your next matches,
## hunts you and taunts you in its own voice, and beating it is revenge.
## Also: matches are short (the Briar's whole run is about eight minutes).


func before_each() -> void:
	RivalBook.reset_for_tests()


func test_a_bot_becomes_your_rival_and_is_remembered() -> void:
	var bot := "Vex"
	check(not RivalBook.is_rival(bot), "a stranger to start with")
	check(not RivalBook.note_you_died_to(bot, "bandit_bunny"), "one beat-down: not a rival yet")
	check(RivalBook.note_you_died_to(bot, "bandit_bunny"), "two: now it's your rival")
	check(RivalBook.is_rival(bot) and RivalBook.kills_on_you(bot) == 2, "the book says so")
	check(RivalBook.note_you_beat(bot, "bandit_bunny"), "beating your rival is revenge")
	check(RivalBook.is_rival(bot), "still your rival while it leads (%s)" % RivalBook.score(bot))
	check(RivalBook.personality_of(bot) == RivalBook.personality_of(bot) and RivalBook.PERSONALITIES.has(RivalBook.personality_of(bot)),
		"one personality for life (%s)" % RivalBook.label_of(bot))
	var said := RivalBook.line(bot, "kill", "Bun")
	check(not said.is_empty() and not said.contains("{"), "talks in its own voice: “%s”" % said)
	# across runs: drop the in-memory book and read the file back
	RivalBook._cfg = null
	check(RivalBook.kills_on_you(bot) == 2 and RivalBook.your_kills(bot) == 1, "remembered after a restart")
	check(RivalBook.rivals().size() == 1 and RivalBook.rivals()[0][0] == bot and RivalBook.rivals()[0][1] == "bandit_bunny", "listed with its species")
	var names := {}
	for p in RivalBook.PERSONALITIES:
		names[p] = true
	var seen := {}
	for d in ["bandit_bunny", "squirrel", "fox", "raccoon", "frog", "beaver", "hamster"]:
		for n in (load("res://data/critters/%s.tres" % d) as CritterDef).names:
			seen[RivalBook.personality_of(n)] = true
	check(seen.size() >= 5, "the bots have a spread of personalities (%d of %d)" % [seen.size(), names.size()])


func test_rivals_come_back_hunt_and_taunt() -> void:
	RivalBook.note_you_died_to("Vex", "bandit_bunny")
	RivalBook.note_you_died_to("Vex", "bandit_bunny")
	var cage := HamsterCage.new()
	add_child(cage)
	await cage.generate(31, 0, false)
	add_child(FX.new())
	add_child(Projectiles.new())
	var mm := MatchManager.new()
	add_child(mm)
	mm.setup(self, cage, 6, 1, 31)
	var vex: Critter = null
	for c in mm.critters:
		if c.display_name == "Vex":
			vex = c
	check(vex != null, "your rival is in the match")
	if vex == null:
		return
	check(mm.rivals_here.has(vex), "and the match knows it")
	var brain := vex.get_node("AIBrain") as AIBrain
	check(brain.rival and brain.personality == RivalBook.personality_of("Vex"), "it hunts you, in character")
	check(vex.visual.name_tag.text.contains("RIVAL"), "its name tag says RIVAL")
	var player := mm.spawn_player(load("res://data/critters/bun.tres"), "default")
	var taunts := []
	Events.taunt.connect(func(c, t): taunts.append([c, t]))
	var news := []
	Events.rival_news.connect(func(t, sub): news.append(t))
	for c in mm.critters:
		c.place_at(Vector3(c.global_position.x, 30.0, c.global_position.z), 0.0)
	await wait_physics(5)
	# it beats you down again: it gloats, and the book counts it
	var hit := DamageInfo.make(999.0, DamageInfo.Kind.BULLET, vex)
	player.take_damage(hit)
	await wait_frames(2)
	check(RivalBook.kills_on_you("Vex") == 3, "the book counts it (%s)" % RivalBook.score("Vex"))
	check(taunts.any(func(t): return t[0] == vex), "Vex taunts you: %s" % [taunts])
	# and when you get it back, that's revenge
	var back := DamageInfo.make(999.0, DamageInfo.Kind.BULLET, player)
	player.alive = true
	vex.take_damage(back)
	await wait_frames(2)
	check(RivalBook.your_kills("Vex") == 1, "you got one back")
	check(news.has("REVENGE!"), "and the game calls it revenge")
	Events.taunt.disconnect(Events.taunt.get_connections().back().callable)
	Events.rival_news.disconnect(Events.rival_news.get_connections().back().callable)


func test_matches_are_short() -> void:
	var total := 0.0
	for s in Storm.STAGES:
		total += float(s[0]) + float(s[1])
	check(total * Storm.MAX_MAP_PACE <= 480.0, "the whole Briar runs in about 8 minutes at most (%.0f s)" % (total * Storm.MAX_MAP_PACE))
