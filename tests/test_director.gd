extends TestCase
## The bots learn you: the profile (its own test file here) remembers where
## you land and how you fight; in a match, camping in one spot sends the
## nearest bots to flush you out, and a hot streak makes them sharpen up for
## a while, then relax.


func before_each() -> void:
	PlayerProfile.reset_for_tests()


func test_the_profile_learns_your_habits() -> void:
	check(PlayerProfile.favourite_landing(["Tube Town"]) == "", "no habits yet")
	PlayerProfile.note_landing("Tube Town")
	check(PlayerProfile.favourite_landing(["Tube Town"]) == "", "once isn't a habit")
	PlayerProfile.note_landing("Tube Town")
	PlayerProfile.note_landing("Seed Bowl")
	check(PlayerProfile.favourite_landing(["Tube Town", "Seed Bowl"]) == "Tube Town", "you always land at Tube Town")
	check(PlayerProfile.favourite_landing(["Seed Bowl"]) == "", "(only landmarks on this map count)")
	for i in 4:
		PlayerProfile.note_kill(&"carrot_shotgun")
	check(PlayerProfile.fighting_style() == "close", "a shotgun fan fights up close")
	for i in 8:
		PlayerProfile.note_kill(&"carrot_sniper")
	check(PlayerProfile.fighting_style() == "far", "now mostly a sniper")
	PlayerProfile._cfg = null
	check(PlayerProfile.fighting_style() == "far" and PlayerProfile.favourite_landing(["Tube Town"]) == "Tube Town", "remembered after a restart")


func test_camping_draws_hunters_and_streaks_sharpen_bots() -> void:
	RivalBook.reset_for_tests()
	var cage := HamsterCage.new()
	add_child(cage)
	await cage.generate(31, 0, false)
	add_child(FX.new())
	add_child(Projectiles.new())
	var mm := MatchManager.new()
	add_child(mm)
	mm.setup(self, cage, 5, 1, 31)
	var player := mm.spawn_player(load("res://data/critters/bun.tres"), "default")
	for c in mm.critters:
		c.place_at(Vector3(c.global_position.x, 30.0, c.global_position.z), 0.0)
		if c != player:
			c.give_weapon(WeaponInstance.new(WeaponDB.get_weapon(&"carrot_rifle")))
	await wait_physics(5)
	mm.phase = MatchManager.Phase.PLAYING
	var taunts := []
	var cb := func(c, t): taunts.append(t)
	Events.taunt.connect(cb)
	# sit still for half a minute
	for i in 30:
		mm._direct(1.0)
	var hunting := mm.critters.filter(func(c): return c != player and (c.get_node("AIBrain") as AIBrain)._hunt_pos != Vector3.INF)
	check(hunting.size() >= 1 and hunting.size() <= 3, "camping sends a few bots to flush you out (%d)" % hunting.size())
	check(taunts.any(func(t): return String(t).contains("sitting still")), "and one of them says so")
	Events.taunt.disconnect(cb)
	# two quick beat-downs: the bots adapt
	var slots := AIBrain.player_attack_slots
	var bot: Critter = mm.critters.filter(func(c): return c != player)[0]
	var skill := (bot.get_node("AIBrain") as AIBrain).skill
	var info := DamageInfo.make(10.0, DamageInfo.Kind.BULLET, player, &"carrot_rifle")
	mm._note_player_kill(info)
	mm._note_player_kill(info)
	check(AIBrain.player_attack_slots == slots + 1, "more bots may take you on at once")
	check((bot.get_node("AIBrain") as AIBrain).skill > skill, "and they sharpen up")
	for i in int(MatchManager.ADAPT_SECONDS) + 2:
		mm._direct(1.0)
	check(AIBrain.player_attack_slots == slots and is_equal_approx((bot.get_node("AIBrain") as AIBrain).skill, skill), "then they relax again")
