extends TestCase
## The cast: the same 49 bots every run, each its own way of fighting; bots
## you keep beating turn radical; bots hold grudges against each other and
## the director; a lobby is the cast (no "Fox 3"), with its news and bounty.
## (The rival book uses its own test file.)

const SPECIES := ["bandit_bunny", "squirrel", "fox", "raccoon", "frog", "beaver", "hamster"]


func before_each() -> void:
	RivalBook.reset_for_tests()
	DoppelData.reset_for_tests()   # (other tests' matches feed it: the gallery would list it first)


func test_the_cast_is_49_characters_who_each_fight_their_own_way() -> void:
	var names := Cast.names()
	check(names.size() == 49, "49 bots (%d)" % names.size())
	var unique := {}
	var per_species := {}
	var ways := {}
	for n in names:
		unique[n] = true
		var m := Cast.member(n)
		per_species[m.species] = int(per_species.get(m.species, 0)) + 1
		check(m.species in SPECIES and ResourceLoader.exists("res://data/critters/%s.tres" % m.species), "%s is a %s" % [n, m.species])
		check(Cast.STYLES.has(m.style), "%s fights like a %s" % [n, m.style])
		check(RivalBook.PERSONALITIES.has(m.voice), "%s talks like a %s" % [n, m.voice])
		check(WeaponDB.get_weapon(StringName(m.weapon)) != null, "%s's favourite gun %s exists" % [n, m.weapon])
		check(m.bio != "" and m.says != "", "%s has a bio and a line" % n)
		check(not n.contains("{") and n.strip_edges() == n, "%s is a clean name" % n)
		var way: String = "%s|%s" % [m.style, m.weapon]
		check(not ways.has(way), "%s fights unlike anyone else (%s is %s's too)" % [n, way, ways.get(way, "")])
		ways[way] = n
	check(unique.size() == 49, "49 different names")
	for sp in SPECIES:
		check(per_species.get(sp, 0) == 7, "7 %s (%d)" % [sp, per_species.get(sp, 0)])
	check(Cast.member("Fox 3").is_empty() and RivalBook.PERSONALITIES.has(RivalBook.personality_of("Fox 3")), "an old save's names still get a voice")


func test_beating_a_bot_again_and_again_radicalises_it() -> void:
	var n := "Dumpster Dot"   # a Survivor: runs from a losing fight
	var calm := Cast.traits_for(n)
	check(Cast.heat(n) == 0 and Cast.title(n) == n, "calm to start with")
	check(not calm.has("player_focus") and not calm.get("hunts_you", false), "and minding its own business")
	RivalBook.note_you_beat(n, "raccoon")
	check(Cast.heat(n) == 1 and Cast.title(n) == "Dumpster Dot the Sore", "once: Sore (%s)" % Cast.title(n))
	for i in 2:
		RivalBook.note_you_beat(n, "raccoon")
	var hot := Cast.traits_for(n)
	check(Cast.heat(n) == 2 and Cast.title(n).ends_with("the Vengeful"), "three times: Vengeful")
	check(float(hot.fight_range) > float(calm.fight_range) and float(hot.break_off) < float(calm.break_off),
		"picks fights from further off (%.0f m) and runs later (%.0f HP)" % [hot.fight_range, hot.break_off])
	check(hot.hunts_you and float(hot.player_focus) < 1.0 and not hot.no_slot, "comes looking for you")
	var line := Cast.heat_line(n, "spot", "Bun", RandomNumberGenerator.new())
	check(line != "" and not line.contains("{"), "and says so: “%s”" % line)
	for i in 5:
		RivalBook.note_you_beat(n, "raccoon")
	var nemesis := Cast.traits_for(n)
	check(Cast.heat(n) == 4 and Cast.title(n).ends_with("the Nemesis"), "eight times: your Nemesis")
	check(nemesis.no_slot and float(nemesis.break_off) < 30.0, "doesn't wait its turn, and hardly ever runs (%.0f HP)" % nemesis.break_off)
	RivalBook._cfg = null
	check(Cast.heat(n) == 4, "remembered after a restart")


func test_bots_hold_grudges_against_each_other_and_the_director() -> void:
	check(not RivalBook.note_bot_beat("Sly", "Croaker"), "Sly beats Croaker: nothing to pay back")
	check(RivalBook.grudges("Croaker").get("Sly", 0) == 1 and RivalBook.bot_kills("Sly") == 1, "Croaker holds it against Sly")
	RivalBook.note_bot_beat("Sly", "Croaker")
	check(RivalBook.grudges("Croaker").get("Sly", 0) == 2, "twice")
	check(RivalBook.note_bot_beat("Croaker", "Sly"), "Croaker gets one back: paid back")
	check(RivalBook.grudges("Croaker").get("Sly", 0) == 1 and RivalBook.grudges("Sly").get("Croaker", 0) == 1, "one left each way")
	RivalBook.save()
	RivalBook._cfg = null
	check(RivalBook.grudges("Croaker").get("Sly", 0) == 1, "grudges are remembered after a restart")
	# the director: the Briar and the pacing count against it
	check(not Cast.traits_for("Grimsby").defiant, "Grimsby puts up with the director, for now")
	RivalBook.note_director("Grimsby", Cast.DEFIANT_AT)
	check(Cast.traits_for("Grimsby").defiant, "until it's had enough: defiant")
	# a defiant bot's hits aren't softened by the pacing; anyone else's are
	var a := _bot("Grimsby", true)
	var b := _bot("Masky", false)
	var victim := _bot("Rocco", false)
	AIBrain.kills_held = true
	var before := victim.health
	victim.take_damage(DamageInfo.make(20.0, DamageInfo.Kind.BULLET, a))
	var defiant_hit := before - victim.health
	before = victim.health
	victim.take_damage(DamageInfo.make(20.0, DamageInfo.Kind.BULLET, b))
	var softened_hit := before - victim.health
	AIBrain.kills_held = false
	check(defiant_hit > softened_hit * 3.0, "the defiant bot hits harder while the director holds back (%.1f vs %.1f)" % [defiant_hit, softened_hit])
	check(RivalBook.director_grudge("Masky") == 1 and RivalBook.director_grudge("Rocco") == 0, "and Masky holds the softening against the director")


func test_a_lobby_is_the_cast_with_its_news_and_bounty() -> void:
	# history: you've made Sly Unhinged, Croaker has a score to settle with
	# Vex, and Grimsby is furious with the director
	for i in 5:
		RivalBook.note_you_beat("Sly", "fox")
	RivalBook.note_bot_beat("Vex", "Croaker")
	RivalBook.note_director("Grimsby", Cast.DEFIANT_AT)
	RivalBook.save()
	var cage := HamsterCage.new()
	add_child(cage)
	await cage.generate(31, 0, false)
	add_child(FX.new())
	add_child(Projectiles.new())
	var mm := MatchManager.new()
	add_child(mm)
	mm.setup(self, cage, 49, 1, 31)
	var names := mm.critters.map(func(c): return c.display_name)
	check(names.size() == 49, "a full lobby (%d)" % names.size())
	var unique := {}
	for n in names:
		unique[n] = true
		check(not Cast.member(n).is_empty(), "%s is one of the cast" % n)
	check(unique.size() == 49, "nobody twice, no numbers")
	var sly: Critter = _find(mm, "Sly")
	var brain := sly.get_node("AIBrain") as AIBrain
	check(brain.traits.get("hunts_you", false) and brain.traits.get("no_slot", false), "Unhinged Sly comes for you")
	var gun := sly.current_weapon()
	check(gun != null and String(gun.data.id) == Cast.member("Sly").weapon, "and drops in with its favourite gun (%s)" % [gun.data.id if gun else "none"])
	check(sly.armor >= 50.0, "in armour (%.0f)" % sly.armor)
	check(sly.visual.name_tag.text.contains("Sly the Unhinged"), "its name tag says so: %s" % sly.visual.name_tag.text)
	var croaker: Critter = _find(mm, "Croaker")
	check((croaker.get_node("AIBrain") as AIBrain).grudges.has("Vex"), "Croaker brings its grudge")
	check(_find(mm, "Grimsby").defies_director, "Grimsby defies the director")
	check(mm.bounty_name == "Sly" and mm.bounty > 0, "a bounty on Sly (%s, %d)" % [mm.bounty_name, mm.bounty])
	var news := mm.headlines()
	check(news.any(func(t): return t.contains("Sly the Unhinged") and t.contains("5 times")), "the lobby news knows Sly: %s" % [news])
	check(news.any(func(t): return t.contains("Croaker has a score to settle with Vex")), "and the feud")
	check(news.any(func(t): return t.contains("Grimsby") and t.contains("director")), "and Grimsby's mood")
	check(news.any(func(t): return t.begins_with("BOUNTY")), "and the bounty")
	# you beat Sly down: the bounty pays, and Sly gets angrier still
	var player := mm.spawn_player(load("res://data/critters/bun.tres"), "default")
	for c in mm.critters:
		c.place_at(Vector3(c.global_position.x, 30.0, c.global_position.z), 0.0)
	var heads := []
	Events.headline.connect(func(t): heads.append(t))
	await wait_physics(3)
	sly.take_damage(DamageInfo.make(999.0, DamageInfo.Kind.BULLET, player))
	await wait_frames(2)
	check(mm.bounty_paid, "the bounty is paid")
	check(Cast.heat("Sly") == 3 and RivalBook.your_kills("Sly") == 6, "the book counts it (%d)" % RivalBook.your_kills("Sly"))
	# bots keep score among themselves: Vex beats Croaker again, Croaker
	# gets one back (paying off a grudge makes the news)
	var vex: Critter = _find(mm, "Vex")
	vex.take_damage(DamageInfo.make(999.0, DamageInfo.Kind.BULLET, croaker))
	await wait_frames(2)
	check(heads.any(func(t): return t == "Croaker got even with Vex."), "Croaker got even, and the feed says so: %s" % [heads])
	check(RivalBook.grudges("Vex").get("Croaker", 0) == 1, "now Vex holds it against Croaker")


func test_the_gallery_lists_everyone() -> void:
	RivalBook.note_you_died_to("Vex", "bandit_bunny")
	RivalBook.note_you_died_to("Vex", "bandit_bunny")
	for i in 3:
		RivalBook.note_you_beat("Turbo", "hamster")
	var g := GalleryPanel.new()
	add_child(g)
	await wait_frames(2)
	var cards := g._list.get_children()
	check(cards.size() == 49, "a card for each of the 49 (%d)" % cards.size())
	check(GalleryPanel.order()[0] == "Vex", "your rival first (%s)" % GalleryPanel.order()[0])
	check(GalleryPanel.order()[1] == "Turbo", "then the bot you've made radical")
	var card := GalleryPanel.card("Turbo")
	check(card.contains("Mood: Vengeful") and card.contains("You 3 – 0 Turbo") and card.contains("Trickster"), "Turbo's card: %s" % card)
	check(GalleryPanel.card("Sly").contains("You haven't met yet."), "strangers say so")


func _find(mm: MatchManager, n: String) -> Critter:
	for c in mm.critters:
		if c.display_name == n:
			return c
	return null


func _bot(n: String, defiant: bool) -> Critter:
	var c := Critter.new()
	c.def = load("res://data/critters/%s.tres" % Cast.member(n).species)
	c.display_name = n
	c.defies_director = defiant
	add_child(c)
	c.place_at(Vector3(randf_range(-20, 20), 50.0, randf_range(-20, 20)))
	return c
