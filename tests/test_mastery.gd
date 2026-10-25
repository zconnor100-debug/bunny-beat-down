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
