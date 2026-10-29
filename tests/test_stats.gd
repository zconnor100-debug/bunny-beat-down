extends TestCase
## Your trackers (StatBook, in the test profile): every carrot fired, hit,
## headshot and beat-down counted against the gun that did it (pellets one by
## one, a rocket's blast once), each match's totals against the critter you
## played, remembered between runs, and shown: by the gun in the HUD, on the
## end screen, in the Trophy Room.


func before_each() -> void:
	PlayerProfile.reset_for_tests()
	RivalBook.reset_for_tests()


func test_shots_hits_and_beat_downs_count_against_the_gun() -> void:
	var mm := await _match()
	var you := mm.spawn_player(load("res://data/critters/fox.tres"), "default")
	you.place_at(Vector3(0, 40.0, 0), 0.0)
	var bots := mm.critters.filter(func(c): return c != you)
	var a: Critter = bots[0]
	var b: Critter = bots[1]
	a.place_at(Vector3(30, 40.0, 0), 0.0)
	b.place_at(Vector3(-12, 40.0, 0), 0.0)
	await wait_physics(3)
	# carrots fired: one a shot, a shotgun's nine pellets each
	var rifle := WeaponInstance.new(WeaponDB.get_weapon(&"carrot_rifle"), Rarity.Tier.GARDEN)
	you.give_weapon(rifle)
	you.aim_point = a.get_chest_position()
	for i in 4:
		you._fire(you.current_weapon())
	var shotgun := WeaponInstance.new(WeaponDB.get_weapon(&"carrot_shotgun"), Rarity.Tier.GARDEN)
	you._fire(shotgun)
	check(StatBook.gun(&"carrot_rifle").shots == 4.0 and StatBook.gun(&"carrot_shotgun").shots == 9.0,
		"carrots fired: 4 rifle, 9 pellets (%s, %s)" % [StatBook.gun(&"carrot_rifle").shots, StatBook.gun(&"carrot_shotgun").shots])
	# hits: two body shots and a headshot, then the beat-down from 30 m
	for head in [false, false, true]:
		var hit := DamageInfo.make(10.0, DamageInfo.Kind.BULLET, you, &"carrot_rifle")
		hit.headshot = head
		a.take_damage(hit)
	a.take_damage(DamageInfo.make(999.0, DamageInfo.Kind.BULLET, you, &"carrot_rifle"))
	await wait_frames(2)
	var r := StatBook.gun(&"carrot_rifle")
	check(r.hits == 4.0 and r.heads == 1.0 and r.kills == 1.0, "rifle: 4 hits, 1 headshot, 1 beat-down (%s)" % [r])
	check(StatBook.percent(r) == "100%", "accuracy: every carrot found its mark (%s)" % StatBook.percent(r))
	check(r.longest >= 29.0 and r.longest <= 31.0, "longest beat-down ~30 m (%.1f)" % r.longest)
	# a rocket's blast catching two critters is one hit
	StatBook.note_shot(&"carrot_rocket_launcher")
	StatBook.note_hit(&"carrot_rocket_launcher", 60.0, false, true)
	StatBook.note_hit(&"carrot_rocket_launcher", 40.0, false, true)
	var rk := StatBook.gun(&"carrot_rocket_launcher")
	check(rk.hits == 1.0 and rk.damage == 100.0, "one blast, one hit (%s)" % [rk])
	# a club swing and a club beat-down
	b.take_damage(DamageInfo.make(999.0, DamageInfo.Kind.MELEE, you, &"melee"))
	await wait_frames(2)
	check(StatBook.gun(&"melee").kills == 1.0, "the club's beat-downs count too")
	# this match, and the end screen's line
	check(int(StatBook.this_match.kills) == 2 and int(StatBook.this_match.heads) == 1, "this match: 2 beat-downs, 1 headshot")
	var line := StatBook.match_line()
	check(line.contains("Headshots 1") and line.contains("Longest beat-down") and line.contains("Best gun"), "end screen: %s" % line)
	# you're beaten: the match counts for the fox
	you.take_damage(DamageInfo.make(999.0, DamageInfo.Kind.BULLET, bots[2], &"carrot_smg"))
	await wait_frames(2)
	var fox := StatBook.critter(&"fox")
	check(fox.matches == 1.0 and fox.deaths == 1.0 and fox.kills == 2.0 and fox.best > 1.0,
		"the fox: 1 match, beaten once, 2 beat-downs, placed #%d (%s)" % [int(fox.best), fox])
	check(fox.shots == 13.0 + 1.0, "and every carrot fired (%s)" % fox.shots)
	PlayerProfile._cfg = null
	check(StatBook.gun(&"carrot_rifle").kills == 1.0 and StatBook.critter(&"fox").matches == 1.0, "remembered after a restart")


func test_the_trophy_room_and_the_guns_counter() -> void:
	StatBook.begin_match(&"bun")
	for i in 3:
		StatBook.note_shot(&"carrot_lmg")
	StatBook.note_hit(&"carrot_lmg", 14.0, true)
	StatBook.note_kill(&"carrot_lmg", 42.0)
	StatBook.end_match(1, 24, false)
	var rows := TrophyPanel.gun_rows()
	var lmg: Array = rows.filter(func(r): return r[0] == StatBook.gun_name(&"carrot_lmg"))[0]
	check(lmg[1] == "1" and lmg[2] == "33%" and lmg[3] == "1" and lmg[5] == "42 m", "the LMG's row: %s" % [lmg])
	check(rows.back()[0] == "All" and rows.back()[1] == "1", "and a total")
	var bun: Array = TrophyPanel.critter_rows()[0]
	check(bun[1] == "1" and bun[2] == "1" and bun[3] == "#1", "Bun: 1 match, 1 win, best #1 (%s)" % [bun])
	var panel := TrophyPanel.new()
	add_child(panel)
	await wait_frames(2)
	check(panel.find_children("*", "Label", true, false).any(func(l): return l.text == "Trophy Room"), "the Trophy Room opens")
	# the HUD's counter by the gun's name
	var mm := await _match()
	var you := mm.spawn_player(load("res://data/critters/bun.tres"), "default")
	you.give_weapon(WeaponInstance.new(WeaponDB.get_weapon(&"carrot_lmg"), Rarity.Tier.GARDEN))
	var hud := HUD.new()
	add_child(hud)
	hud.setup(you, null, mm)
	await wait_frames(3)
	check(hud._weapon_name.text.ends_with("⚔ 1"), "the HUD counts the LMG's beat-downs: %s" % hud._weapon_name.text)


func test_the_bots_keep_their_own_trackers() -> void:
	var mm := await _match()
	var you := mm.spawn_player(load("res://data/critters/bun.tres"), "default")
	you.place_at(Vector3(0, 40.0, 0), 0.0)
	var bots := mm.critters.filter(func(c): return c != you)
	var a: Critter = bots[0]
	var b: Critter = bots[1]
	a.place_at(Vector3(20, 40.0, 0), 0.0)
	b.place_at(Vector3(-5, 40.0, 0), 0.0)
	await wait_physics(3)
	# carrots fired (into the sky): a shotgun's nine pellets, then two rifle shots
	a.aim_point = a.global_position + Vector3(0, 60.0, -5.0)
	a._fire(WeaponInstance.new(WeaponDB.get_weapon(&"carrot_shotgun"), Rarity.Tier.GARDEN))
	var rifle := WeaponInstance.new(WeaponDB.get_weapon(&"carrot_rifle"), Rarity.Tier.GARDEN)
	a._fire(rifle)
	a._fire(rifle)
	# hits: a headshot, a club hit (not a carrot), then the beat-down from 25 m
	var head := DamageInfo.make(10.0, DamageInfo.Kind.BULLET, a, &"carrot_rifle")
	head.headshot = true
	b.take_damage(head)
	b.take_damage(DamageInfo.make(5.0, DamageInfo.Kind.MELEE, a, &"melee"))
	b.take_damage(DamageInfo.make(999.0, DamageInfo.Kind.BULLET, a, &"carrot_rifle"))
	await wait_frames(2)
	var s := RivalBook.bot_stats(a.display_name)
	check(s.shots == 11.0 and s.hits == 2.0 and s.heads == 1.0, "%s: 11 carrots, 2 hits, 1 headshot (%s)" % [a.display_name, s])
	check(RivalBook.gun_kills(a.display_name) == {"carrot_rifle": 1}, "a beat-down with the rifle (%s)" % [RivalBook.gun_kills(a.display_name)])
	check(absf(RivalBook.longest(a.display_name) - 25.0) < 1.0, "from ~25 m (%.1f)" % RivalBook.longest(a.display_name))
	check(StatBook.gun(&"carrot_rifle").shots == 0.0, "and none of it counts as yours")
	# it beats you down with the club
	you.take_damage(DamageInfo.make(999.0, DamageInfo.Kind.MELEE, a, &"melee"))
	await wait_frames(2)
	check(RivalBook.gun_kills(a.display_name).get("melee", 0) == 1, "the club's beat-downs count too")
	var card := GalleryPanel.card(a.display_name)
	check(card.contains("Accuracy 18%") and card.contains("1 headshot")
		and card.contains("Beat-downs by gun: %s 1, Club 1" % StatBook.gun_name(&"carrot_rifle")) and card.contains("longest 25 m"),
		"its card: %s" % card)
	RivalBook._cfg = null
	check(RivalBook.gun_kills(a.display_name).size() == 2, "remembered after a restart")
	var here := mm.critters.map(func(c): return c.display_name)
	var stranger: String = Cast.names().filter(func(n): return not here.has(n))[0]
	check(GalleryPanel.tracker_lines(stranger).is_empty(), "a bot that's never fired has no trackers (%s)" % stranger)


func _match() -> MatchManager:
	var cage := HamsterCage.new()
	add_child(cage)
	await cage.generate(31, 0, false)
	add_child(FX.new())
	add_child(Projectiles.new())
	var mm := MatchManager.new()
	add_child(mm)
	mm.setup(self, cage, 4, 1, 31)
	return mm


func test_every_gun_has_its_picture_on_the_gun_badges() -> void:
	var badge := GunBadge.new(0)
	add_child(badge)
	for w in WeaponDB.all() + WeaponDB.arsenal():
		check(ResourceLoader.exists("res://assets/ui/gun_%s.png" % w.id), "%s has a HUD picture" % w.id)
		badge.show_gun(WeaponInstance.new(w, Rarity.Tier.PRIZE), true)
		check(badge._picture.texture != null and badge._name.text != "Empty", "%s's badge shows it" % w.id)
	badge.show_gun(null, false)
	check(badge._picture.texture == null and badge._name.text == "Empty" and badge.modulate.a < 1.0, "an empty slot is dimmed")
	badge.queue_free()
