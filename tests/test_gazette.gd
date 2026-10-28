extends TestCase
## The Warren Gazette: while you're away the rogues play matches of their own
## (WarrenSim), every few hours of real time. What happens goes into
## RivalBook like anything from your matches (wins, grudges, scars from the
## rogue that dealt them, moods) and into the paper (GazettePanel).

const T0 := 1_800_000_000.0   # (a fixed "now")
const HOUR := 3600.0


func before_each() -> void:
	RivalBook.reset_for_tests()
	WarrenSim.reset_for_tests()


func after_each() -> void:
	RivalBook.reset_for_tests()
	WarrenSim.reset_for_tests()


func test_time_away_becomes_off_screen_matches() -> void:
	var first := WarrenSim.catch_up(T0)
	check(int(first.get("matches", 0)) == WarrenSim.FIRST_EDITION, "a new warren has news already (%d matches)" % int(first.get("matches", 0)))
	check(WarrenSim.catch_up(T0 + HOUR).is_empty(), "an hour later: no news")
	var later := WarrenSim.catch_up(T0 + 7 * HOUR)
	check(int(later.get("matches", 0)) == 2, "seven hours away: two matches (%d)" % int(later.get("matches", 0)))
	check(WarrenSim.catch_up(T0 + 8 * HOUR).is_empty(), "(the hour left over counts toward the next one...)")
	check(int(WarrenSim.catch_up(T0 + 9 * HOUR).get("matches", 0)) == 1, "...two hours on")
	var month := WarrenSim.catch_up(T0 + 30 * 24 * HOUR)
	check(int(month.get("matches", 0)) == WarrenSim.MAX_MATCHES, "a month away: %d at most (%d)" % [WarrenSim.MAX_MATCHES, int(month.get("matches", 0))])
	check(WarrenSim.catch_up(T0 + 30 * 24 * HOUR + HOUR).is_empty(), "and the rest are forgotten, not owed")
	var wins := 0
	for n in Cast.names():
		wins += RivalBook.wins(n)
	check(wins == WarrenSim.FIRST_EDITION + 2 + 1 + WarrenSim.MAX_MATCHES, "every match has a winner (%d wins)" % wins)


func test_the_same_absence_makes_the_same_news() -> void:
	var a := WarrenSim.catch_up(T0)
	var said := JSON.stringify(a.get("stories", []))
	check(not (a.get("stories", []) as Array).is_empty(), "there's news")
	RivalBook.reset_for_tests()
	WarrenSim.reset_for_tests()
	check(JSON.stringify(WarrenSim.catch_up(T0).get("stories", [])) == said, "the same absence, the same news")
	RivalBook.reset_for_tests()
	WarrenSim.reset_for_tests()
	check(JSON.stringify(WarrenSim.catch_up(T0 + 5 * HOUR).get("stories", [])) != said, "another absence, other news")


func test_a_rogue_that_shoots_straighter_wins_more() -> void:
	# two rogues of the same temperament, one a crack shot (60% of 400 carrots), one hopeless (8%)
	var good := ""
	var bad := ""
	for n in Cast.names():
		for o in Cast.names():
			if good == "" and n != o and RivalBook.personality_of(n) == RivalBook.personality_of(o):
				good = n
				bad = o
	var even := WarrenSim.win_chance(good, bad)
	check_near(even, 0.5, 0.01, "(%s and %s start even)" % [good, bad])
	RivalBook.note_bot_shot(good, 400)
	RivalBook.note_bot_shot(bad, 400)
	for i in 240:
		RivalBook.note_bot_hit(good, &"carrot_rifle", 10.0, false)
	for i in 32:
		RivalBook.note_bot_hit(bad, &"carrot_rifle", 10.0, false)
	var p := WarrenSim.win_chance(good, bad)
	check(p > 0.8, "%s beats %s %.0f%% of the time they meet" % [good, bad, p * 100.0])
	check_near(WarrenSim.win_chance(bad, good), 1.0 - p, 1e-6, "(and the other way round, the rest)")
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var won := {good: 0, bad: 0}
	for i in 500:
		var m := WarrenSim.play_match(rng)
		if won.has(m.winner):
			won[m.winner] += 1
	check(won[good] > won[bad] * 2, "over 500 off-screen matches, the crack shot wins far more (%d vs %d)" % [won[good], won[bad]])


func test_off_screen_scars_are_theirs_not_yours() -> void:
	check(RivalBook.add_scar_from("Rocco", "eye_patch", "Vex"), "Vex takes Rocco's eye, off-screen")
	check(RivalBook.scars("Rocco").is_empty() and RivalBook.all_scars("Rocco") == ["eye_patch"], "Rocco wears it, but it isn't one of yours")
	check(not RivalBook.add_scar_from("Rocco", "eye_patch", "Sly"), "(one eye patch is plenty)")
	RivalBook.add_scar("Rocco", "leg_l")
	check(RivalBook.all_scars("Rocco") == ["leg_l", "eye_patch"], "yours, then theirs: %s" % [RivalBook.all_scars("Rocco")])
	check(" ".join(GalleryPanel.memory_lines("Rocco")).contains("an eye patch (from Vex)"), "the gallery says who gave it")
	check(GalleryPanel.card_title("Rocco").ends_with("scarred"), "and marks it scarred")
	var p := CritterPortrait.new(Vector2(320, 360))
	add_child(p)
	await wait_frames(2)
	p.show_rogue("Rocco")
	await wait_frames(2)
	var pieces := p.shown_critter().find_children("*", "MeshInstance3D", true, false).filter(func(x): return x.has_meta(&"scar"))
	check(pieces.size() >= 2, "its portrait wears the eye patch and your splint (%d pieces)" % pieces.size())
	p.queue_free()
	var now := Time.get_unix_time_from_system()
	RivalBook.add_scar_from("Sly", "leg_r", "Vex", now - (RivalBook.HEAL_DAYS + 1.0) * 24.0 * HOUR)
	RivalBook.add_scar("Sly", "arm_l")
	check(RivalBook.all_scars("Sly") == ["arm_l"], "a splint from %d days ago has healed; your bandage hasn't, and never will" % int(RivalBook.HEAL_DAYS + 1.0))
	check(RivalBook.add_scar_from("Sly", "leg_r", "Rocco", now), "(and the healed leg can be hurt again)")
	WarrenSim.catch_up(T0)
	RivalBook.reset_rogues()
	check(RivalBook.all_scars("Rocco").is_empty() and WarrenSim.edition().is_empty(), "Reset all rogues clears its off-screen history, and the news")


func test_what_happened_off_screen_carries_into_your_matches() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var m := WarrenSim.play_match(rng)
	var b: Dictionary = m.beats[0]
	check(RivalBook.grudges(b.loser).has(b.winner), "%s holds it against %s, as after one of your matches (it'll go after it first)" % [b.loser, b.winner])
	var base := Cast.traits_for("Sly")
	RivalBook.set_mood("Sly", "cocky")
	var cocky := Cast.traits_for("Sly")
	check(float(cocky.break_off) < float(base.get("break_off", AIBrain.BREAK_OFF_HEALTH))
		and float(cocky.fight_range) > float(base.get("fight_range", AIBrain.BOT_FIGHT_RANGE)), "a cocky rogue is braver and picks fights from further off")
	RivalBook.set_mood("Sly", "wary")
	var wary := Cast.traits_for("Sly")
	check(float(wary.break_off) > float(base.get("break_off", AIBrain.BREAK_OFF_HEALTH)) and float(wary.range) > float(base.get("range", 1.0)),
		"a wary one runs sooner and keeps its distance")
	RivalBook.set_mood("Sly", "")
	check(Cast.traits_for("Sly") == base, "and one in no mood is its old self")
	var ed := WarrenSim.catch_up(T0 + 40 * HOUR)
	for s in ed.get("standings", []):
		if int(s[1]) >= 2:
			check(RivalBook.mood(s[0]) == "cocky", "%s won %d while you were away: cocky" % [s[0], int(s[1])])
	check(not WarrenSim.feuds().is_empty(), "and there are feuds to watch")


func test_the_gazette_prints_the_news() -> void:
	var ed := WarrenSim.catch_up(T0)
	check(not bool(WarrenSim.edition().get("read", true)), "a new edition, unread")
	check(GazettePanel.dateline(ed).contains("%d matches while you were away" % WarrenSim.FIRST_EDITION), GazettePanel.dateline(ed))
	var g := GazettePanel.new()
	add_child(g)
	await wait_frames(3)
	check(g.headline() == String(ed.stories[0].title) and g.headline() != "", "the front page leads with the biggest story: %s" % g.headline())
	check(bool(WarrenSim.edition().get("read", false)), "read, once it's been shown")
	check(get_viewport().gui_get_focus_owner() == g._back, "Back has the focus (pad)")
	var closed := [false]
	g.closed.connect(func(): closed[0] = true)
	g._back.pressed.emit()
	check(closed[0], "Back closes it")
	g.queue_free()
	WarrenSim.forget_news()
	var none := GazettePanel.new()
	add_child(none)
	await wait_frames(2)
	check(none.headline() == "", "no edition, no headline (and no crash)")
	none.queue_free()
	await wait_frames(1)
