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
