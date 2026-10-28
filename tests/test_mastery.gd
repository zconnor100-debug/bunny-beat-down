extends TestCase
## Milestones (Mastery): progress read off the trackers, each reached once
## (one-time rewards paid once), and the unlocks acting where they should: a
## mastered gun's carrots (yours only), bigger rocket blasts, a harder club,
## free Workshop looks, more helmets and rewinds on a run, bigger drafts. And
## the Trophy Room's Milestones page.


func before_each() -> void:
	PlayerProfile.reset_for_tests()
	RivalBook.reset_for_tests()
	Boons.reset()


func test_milestones_are_reached_once_and_pay_once() -> void:
	check(Mastery.MILESTONES.size() >= 12, "a dozen milestones or more (%d)" % Mastery.MILESTONES.size())
	var ids := {}
	for m in Mastery.MILESTONES:
		ids[m.id] = true
		check(m.has_all(["name", "text", "stat", "need", "reward", "gives"]), "%s is complete" % m.id)
	check(ids.size() == Mastery.MILESTONES.size(), "ids are unique")
	check(Mastery.check().is_empty(), "nothing yet")
	StatBook.begin_match(&"bun")
	StatBook.note_kill(&"carrot_pistol", 12.0)
	var acorns := Burrow.acorns()
	var fresh := Mastery.check()
	check(fresh.size() == 1 and fresh[0].id == "first_carrot" and Burrow.acorns() == acorns + 25, "First Carrot: +25 acorns")
	check(Mastery.check().is_empty() and Burrow.acorns() == acorns + 25, "and only once")
	check(Mastery.progress("gun_kills:carrot_pistol") == 1, "the pistol's count: 1 of 15")
	for i in 14:
		StatBook.note_kill(&"carrot_pistol", 12.0)
	check(Mastery.check().map(func(m): return m.id) == ["trick_shot"], "15 pistol beat-downs: Trick Shot")
	StatBook.end_match(1, 24, false)
	check(Mastery.check().any(func(m): return m.id == "winner") and Workshop.owns("skin:gilded"), "a win: the Gilded skin, free")
	# from the cast and runs
	for i in 8:
		RivalBook.note_you_beat("Sly", "fox")
	check(Mastery.progress("max_heat") == 4 and Mastery.check().any(func(m): return m.id == "arch_enemy"), "a Nemesis made: Arch-Enemy")
	Mastery.note_boons(6)
	check(Mastery.check().any(func(m): return m.id == "green_thumb") and Mastery.draft_size() == 4, "six boons at once: drafts of four")


func test_the_unlocks_act_where_they_should() -> void:
	make_arena()
	var you := spawn_critter("res://data/critters/bun.tres", Vector3.ZERO)
	you.is_player = true
	var bot := spawn_critter("res://data/critters/fox.tres", Vector3(5, 0, 0))
	var pistol := WeaponInstance.new(WeaponDB.get_weapon(&"carrot_pistol"), Rarity.Tier.GARDEN)
	check(Projectiles.mutations_for(you, pistol).is_empty(), "an ordinary pistol")
	PlayerProfile._book().set_value("mastery", "trick_shot", true)
	check(Projectiles.mutations_for(you, pistol).get("bounce", 0) == 1, "mastered: your pistol's carrots bounce")
	check(Projectiles.mutations_for(bot, pistol).is_empty(), "but not a bot's")
	check(Mastery.blast_scale() == 1.0 and Mastery.club_scale() == 1.0, "no bigger blasts or club yet")
	PlayerProfile._book().set_value("mastery", "big_bang", true)
	PlayerProfile._book().set_value("mastery", "bonk_master", true)
	check(Mastery.blast_scale() == 1.3 and Mastery.club_scale() == 1.25, "Big Bang and Bonk Master")
	# runs: a fourth helmet and a fourth rewind
	PlayerProfile._book().set_value("mastery", "trailblazer", true)
	PlayerProfile._book().set_value("mastery", "halfway_there", true)
	Run.start(5)
	check(Run.helmets() == Run.HELMETS + 1 and Run.rewinds() == Run.REWINDS + 1, "runs start with %d helmets and %d rewinds" % [Run.helmets(), Run.rewinds()])
	Run.clear()


func test_the_trophy_room_shows_milestones() -> void:
	StatBook.begin_match(&"bun")
	StatBook.note_kill(&"carrot_smg", 5.0)
	Mastery.check()
	var rows := Mastery.rows()
	var first: Array = rows.filter(func(r): return r[0] == "First Carrot")[0]
	var smg: Array = rows.filter(func(r): return r[0] == "Popcorn")[0]
	check(first[4] and first[2] == "1 / 1", "First Carrot reached: %s" % [first])
	check(not smg[4] and smg[2] == "1 / 25", "Popcorn on its way: %s" % [smg])
	var panel := TrophyPanel.new()
	add_child(panel)
	await wait_frames(2)
	var tab := panel.find_children("*", "Button", true, false).filter(func(b): return b.text == "Milestones")
	check(tab.size() == 1, "a Milestones tab")
	tab[0].pressed.emit()
	await wait_frames(2)
	check(panel.find_children("*", "Label", true, false).any(func(l): return l.text.contains("Popcorn") and l.is_visible_in_tree()), "showing the milestones")
	panel.queue_free()


func test_a_win_on_each_map_and_a_beaten_nemesis_earn_a_piece() -> void:
	for pair in [["island", "wear_face:snorkel_mask"], ["cage", "wear_hat:cheese_hat"], ["toybox", "wear_back:windup_key"]]:
		check(not Workshop.owns(pair[1]), "%s isn't yours yet" % pair[1])
		StatBook.begin_match(&"bun", pair[0])
		StatBook.end_match(1, 24, false)
		check(StatBook.map_wins(pair[0]) == 1, "a win on %s counted" % pair[0])
		Mastery.check()
		check(Workshop.owns(pair[1]) and Workshop.earned_only(pair[1]), "a win on %s: the %s (earned, not bought)" % pair)
	# losing on a map earns nothing
	StatBook.begin_match(&"bun", "island")
	StatBook.end_match(5, 24, true)
	check(StatBook.map_wins("island") == 1, "a loss isn't a win")
	check(not Workshop.owns("wear_hat:laurel_wreath"), "no laurels yet")
	Mastery.note_nemesis_beaten()
	Mastery.check()
	check(Mastery.progress("nemeses_beaten") == 1 and Workshop.owns("wear_hat:laurel_wreath"), "your Nemesis beaten down: the laurel wreath")


func test_ladders_climb_tier_by_tier_each_harder() -> void:
	var ids := {}
	for m in Mastery.all():
		ids[m.id] = true
	check(ids.size() == Mastery.all().size(), "every milestone and tier has its own id (%d)" % ids.size())
	check(Mastery.LADDERS.size() >= 15, "fifteen ladders or more (%d)" % Mastery.LADDERS.size())
	for l in Mastery.LADDERS:
		var needs: Array = l.tiers.map(func(t): return int(t[0]))
		check(needs.size() == 3 and needs[0] < needs[1] and needs[1] < needs[2], "%s: three tiers, each harder (%s)" % [l.id, needs])
		check(String(l.text).contains("%d"), "%s says how many" % l.id)
	for gun in StatBook.GUNS:
		check(Mastery.LADDERS.any(func(l): return l.stat == "gun_kills:%s" % gun), "a ladder for the %s" % gun)
	# climbing the Pistolero: 25, 50, then 100 pistol beat-downs
	StatBook.begin_match(&"bun")
	for i in 24:
		StatBook.note_kill(&"carrot_pistol", 10.0)
	Mastery.check()
	var row: Array = Mastery.ladder_rows().filter(func(r): return String(r[0]).begins_with("Pistolero"))[0]
	check(row[0] == "Pistolero ☆☆☆" and row[2] == "24 / 25" and row[3] == "50 acorns" and row[5] == "the Ruby gun skin",
		"on the first tier, the Ruby skin at the top: %s" % [row])
	var acorns := Burrow.acorns()
	StatBook.note_kill(&"carrot_pistol", 10.0)
	var fresh := Mastery.check()
	check(fresh.map(func(m): return m.id) == ["pistolero_25"] and fresh[0].name == "Pistolero I" and Burrow.acorns() == acorns + 50,
		"25: Pistolero I, 50 acorns (%s)" % [fresh.map(func(m): return m.id)])
	for i in 25:
		StatBook.note_kill(&"carrot_pistol", 10.0)
	check(Mastery.check().map(func(m): return m.id) == ["pistolero_50"] and Burrow.acorns() == acorns + 150, "50: Pistolero II, 100 more")
	check(not Workshop.owns("skin:ruby") and not Workshop.buy("skin:ruby"), "the Ruby skin can't be bought")
	for i in 50:
		StatBook.note_kill(&"carrot_pistol", 10.0)
	fresh = Mastery.check()
	check(fresh.any(func(m): return m.id == "pistolero_100") and Workshop.owns("skin:ruby"), "100: the Ruby skin, earned")
	check(fresh.any(func(m): return m.id == "carrot_crusher_100"), "and a hundred beat-downs in all: Carrot Crusher I")
	row = Mastery.ladder_rows().filter(func(r): return String(r[0]).begins_with("Pistolero"))[0]
	check(row[0] == "Pistolero ★★★" and row[4] and row[2] == "100 / 100", "all climbed: %s" % [row])
	check(Mastery.check().is_empty(), "each tier pays once")


func test_the_new_stats_count() -> void:
	check(Mastery.progress("matches") == 0 and Mastery.progress("gang_beaten") == 0 and Mastery.progress("doppels_beaten") == 0, "nothing yet")
	for i in 3:
		StatBook.begin_match(&"fox")
		StatBook.end_match(5, 24, true)
	check(Mastery.progress("matches") == 3, "three matches played (%d)" % Mastery.progress("matches"))
	Mastery.note_gang_beaten()
	Mastery.note_gang_beaten()
	check(Mastery.progress("gang_beaten") == 2, "two gang members beaten")
	DoppelData.reset_for_tests()
	DoppelData.note_mirror("beaten")
	check(Mastery.progress("doppels_beaten") == 1, "a Doppelbunny beaten")
	DoppelData.reset_for_tests()


func test_every_earned_only_look_is_a_milestones_reward_and_exists() -> void:
	for cat in Workshop.LOOKS:
		for o in Workshop.LOOKS[cat].options:
			var item := "%s:%s" % [cat, o[0]]
			if Workshop.earned_only(item):
				check(not Mastery.giving(item).is_empty(), "%s is a milestone's reward" % item)
			match cat:
				"skin":
					check(o[0] == "stock" or GunKit.SKINS.has(o[0]), "the %s skin is drawn" % o[0])
				"kill_fx":
					check(o[0] == "none" or FX.BEAT_DOWN_BURSTS.has(o[0]), "the %s burst is drawn" % o[0])
				"reticle_color", "tracer", "flash":
					check(Workshop.COLORS.has(o[0]) or o[0] == "rainbow", "the %s colour %s exists" % [cat, o[0]])
				"coat":
					check(o[0] == "natural" or Workshop.coat_material(o[0]) != null, "the %s coat is drawn" % o[0])
	for m in Mastery.all():
		if m.reward.has("look"):
			check(Workshop.earned_only(m.reward.look) or Workshop.cost(m.reward.look) > 0, "%s gives a real look (%s)" % [m.id, m.reward.look])


func test_the_trophy_room_shows_the_ladders() -> void:
	var panel := TrophyPanel.new()
	add_child(panel)
	await wait_frames(2)
	var tab := panel.find_children("*", "Button", true, false).filter(func(b): return b.text == "Ladders")
	check(tab.size() == 1, "a Ladders tab")
	tab[0].pressed.emit()
	await wait_frames(2)
	var shown := panel.find_children("*", "Label", true, false).filter(func(l): return l.is_visible_in_tree())
	check(shown.any(func(l): return l.text == "Rumble On ☆☆☆"), "the Root Rumbler's ladder, nothing climbed")
	check(not shown.any(func(l): return l.text.contains("Popcorn")), "the milestones page is hidden")
	panel.queue_free()
