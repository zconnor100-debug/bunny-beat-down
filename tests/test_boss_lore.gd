extends TestCase
## The bosses' story and what beating them earns: their lore (BossLore), told
## a chapter at a time as you face them and beat them; your record against
## each (StatBook); a milestone for beating each with a piece of it to keep
## (the Brutus coat, the Tin Tyrant gun skin, the Rabid froth burst), harder
## ones and the bosses' ladders; the Trophy Room's Bosses page; and a boss's
## arrival as a cinematic (BossIntro).

const SCRIPTS := {"brute": "res://src/bosses/brute_boss.gd", "robot": "res://src/bosses/robot_boss.gd",
	"hamster": "res://src/bosses/hamster_boss.gd"}


func before_each() -> void:
	PlayerProfile.reset_for_tests()
	RivalBook.reset_for_tests()


func after_each() -> void:
	Engine.time_scale = 1.0
	await super()


func test_every_boss_has_its_story() -> void:
	check(BossLore.MYTH.length() > 400 and BossLore.MYTH.contains("Starfall"), "how the giants came")
	for id in BossLore.IDS:
		var b := BossLore.of(id)
		check(b.chapters.size() == BossLore.OPENS.size(), "%s: four chapters" % id)
		check(b.chapters.all(func(c): return String(c[0]) != "" and String(c[1]).length() > 150), "%s: each one a story" % id)
		check(BossLore.epigraph(id) != "" and b.rumours.size() >= 2, "%s: its line, and rumours" % id)
		check(MatchManager.BOSSES[b.map] == SCRIPTS[id] and BossLore.id_for_map(b.map) == id, "%s lives on %s" % [id, b.map])
		var boss: Boss = (load(SCRIPTS[id]) as GDScript).new()
		check(boss.display_name == b.name and boss.title == b.title, "%s: the same name and billing as the boss" % id)
		boss.free()
		check(Cast.BOSS_NAME_LINES.has(id), "%s: the rogues know its name" % id)
	check(BossLore.rumours("island").size() >= 2 and BossLore.rumours("nowhere").is_empty(), "the loading screen's rumours, by map")


func test_its_story_opens_a_chapter_at_a_time() -> void:
	check(BossLore.chapters_open("brute") == 1 and BossLore.is_open("brute", 0) and not BossLore.is_open("brute", 1),
		"the legend's for everyone; the rest is closed")
	check(BossLore.opens_when("brute", 1) == "Face Brutus in a Boss Battle to read on.", BossLore.opens_when("brute", 1))
	check(BossLore.opens_when("robot", 3) == "Beat the Tin Tyrant 3 times to read on.", BossLore.opens_when("robot", 3))
	StatBook.note_boss_fought("brute")
	check(BossLore.chapters_open("brute") == 2, "facing it opens the second")
	StatBook.note_boss_beaten("brute", 300.0, true, false, false)
	check(BossLore.chapters_open("brute") == 3, "beating it, the third")
	StatBook.note_boss_beaten("brute", 250.0, false, false, false)
	StatBook.note_boss_beaten("brute", 280.0, false, false, false)
	check(BossLore.chapters_open("brute") == 4, "three times, the last")
	check(BossLore.chapters_open("robot") == 1, "each boss its own")
	var r := StatBook.boss("brute")
	check(r.fought == 1.0 and r.beaten == 3.0 and r.standing == 1.0 and r.best == 250.0, "its record: %s" % r)


func test_beating_each_boss_earns_a_piece_of_it() -> void:
	check(not Workshop.owns("coat:brutus") and not Workshop.buy("coat:brutus"), "the Brutus coat can't be bought")
	var fresh := []
	for pair in [["brute", "coat:brutus"], ["robot", "skin:tin_tyrant"], ["hamster", "kill_fx:froth"]]:
		StatBook.note_boss_fought(pair[0])
		StatBook.note_boss_beaten(pair[0], 400.0, false, false, false)
		fresh = Mastery.check()
		check(Workshop.owns(pair[1]) and Workshop.earned_only(pair[1]), "%s beaten: %s" % pair)
	check(fresh.any(func(m): return m.id == "big_three"), "all three: The Big Three")
	check(Mastery.progress("bosses_beaten") == 3 and Mastery.progress("boss_wins") == 3, "three bosses beaten")
	check(not Mastery.has("still_standing") and not Mastery.has("hard_nut"), "not standing, not on Hard: not yet")
	StatBook.note_boss_beaten("brute", 380.0, true, true, true)
	fresh = Mastery.check()
	for id in ["still_standing", "hard_nut"]:
		check(fresh.any(func(m): return m.id == id), "standing, on Hard: %s" % id)
	check(Mastery.progress("boss_last_blows") == 1 and not Mastery.has("last_blow_2"), "one last blow, The Last Blow I needs two")
	StatBook.note_boss_beaten("hamster", 500.0, false, true, false)
	check(Mastery.check().any(func(m): return m.id == "last_blow_2"), "two: The Last Blow I")
	StatBook.begin_match(&"bun")
	StatBook.note_boss_damage("robot", 26000.0)
	check(Mastery.check().any(func(m): return m.id == "titan_tenderizer_25000"), "25,000 damage to bosses: Titan Tenderizer I")
	var row: Array = Mastery.ladder_rows(true).filter(func(r): return String(r[0]).begins_with("Titan Tenderizer"))[0]
	check(row[1] == "Deal 50,000 damage to bosses." and row[2] == "26,000 / 50,000", "big numbers grouped: %s" % [row])
	check(Mastery.rows().all(func(r): return not String(r[0]).begins_with("Giant Slayer")), "the bosses' milestones aren't on the Milestones page")
	check(Mastery.rows("brute").size() == 1 and Mastery.rows("*").size() == 3 and Mastery.ladder_rows(true).size() == 3,
		"they're on the Bosses page")


func test_the_trophy_room_has_a_bosses_page() -> void:
	StatBook.note_boss_fought("brute")
	var panel := TrophyPanel.new()
	add_child(panel)
	await wait_frames(2)
	var tab: Array = panel.find_children("*", "Button", true, false).filter(func(b): return b.text == "Bosses")
	check(tab.size() == 1, "a Bosses tab")
	if tab.is_empty():
		panel.queue_free()
		return
	tab[0].pressed.emit()
	await wait_frames(2)
	var shown := func() -> Array:
		return panel.find_children("*", "Label", true, false).filter(func(l): return l.is_visible_in_tree()).map(func(l): return l.text)
	var labels: Array = shown.call()
	check(labels.has(BossLore.MYTH_TITLE), "how they came")
	check(labels.any(func(t): return String(t).begins_with("BRUTUS, the Meadow's Nightmare")), "Brutus first")
	check(labels.has(BossLore.of("brute").chapters[1][1]), "the chapter you've opened, showing")
	var chapters: Array = panel.find_children("*", "Button", true, false).filter(func(b): return b.is_visible_in_tree() and b.text.begins_with("III."))
	check(chapters.size() == 1 and chapters[0].text == "III. ? ? ?", "a closed chapter's name is hidden")
	chapters[0].pressed.emit()
	check(shown.call().has("Beat Brutus to read on."), "and says what opens it")
	var robot: Array = panel.find_children("*", "Button", true, false).filter(func(b): return b.text.begins_with("Tin Tyrant"))
	robot[0].pressed.emit()
	await wait_frames(2)
	labels = shown.call()
	check(labels.any(func(t): return String(t).begins_with("TIN TYRANT, the Wind-Up Warlord")), "then the Tin Tyrant")
	check(labels.has(BossLore.of("robot").chapters[0][1]), "its legend")
	panel.queue_free()


func test_a_boss_arrives_as_a_cinematic() -> void:
	make_arena(800.0)
	var cam := Camera3D.new()   # (yours)
	add_child(cam)
	cam.make_current()
	for id in ["brute", "hamster"]:
		var b: Boss = (load(SCRIPTS[id]) as GDScript).new()
		add_child(b)
		b.global_position = Critter.PARKED
		await wait_physics(2)
		b.arrive(Vector3.ZERO, Vector3(0, 0, -80))
		check(b.forward().dot(Vector3(0, 0, -1)) > 0.99, "%s faces you as it lands" % id)
		var intro := BossIntro.new(b, null)
		var done := [false]
		intro.finished.connect(func(): done[0] = true)
		add_child(intro)
		await wait_frames(2)
		check(get_viewport().get_camera_3d() == intro._cam, "%s: the intro has the camera" % id)
		check(not b.thinking, "%s holds still for it" % id)
		var start := Time.get_ticks_msec()
		while not intro._card_shown and Time.get_ticks_msec() - start < 6000:
			await get_tree().process_frame
		check(intro._card_shown and b.fight_time() >= b.land_time, "%s: its name comes up once it's down" % id)
		var names: Array = intro.find_children("*", "Label", true, false).map(func(l): return l.text)
		check(names.has(b.display_name.to_upper()) and names.has(BossLore.epigraph(id)), "%s: its name and its line (%s)" % [id, names])
		while not done[0] and Time.get_ticks_msec() - start < 15000:
			await get_tree().process_frame
		check(done[0], "%s: then it's over" % id)
		check(get_viewport().get_camera_3d() == cam and Engine.time_scale == 1.0, "%s: your camera back, time as it was" % id)
		check(b.moves_used.has(&"roar") or b.moves_used.has(&"screech"), "%s roared for the camera (%s)" % [id, b.moves_used])
		check(b._quiet_until > 0.0, "%s: a roar that hurt nobody" % id)
		b.queue_free()
		await wait_frames(3)
	# any button skips it
	var r: Boss = (load(SCRIPTS["robot"]) as GDScript).new()
	add_child(r)
	r.global_position = Critter.PARKED
	await wait_physics(2)
	r.arrive(Vector3.ZERO)
	var skip := BossIntro.new(r, null)
	add_child(skip)
	await wait_frames(3)
	var press := InputEventAction.new()
	press.action = &"jump"
	press.pressed = true
	Input.parse_input_event(press)
	await wait_frames(3)
	check(not skip.playing and get_viewport().get_camera_3d() == cam, "skipped")
	press.pressed = false
	Input.parse_input_event(press)
	r.queue_free()
	cam.queue_free()
