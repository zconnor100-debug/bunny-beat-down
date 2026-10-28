extends TestCase
## Gangs (Gang, MatchManager, AIBrain): they hunt as a pack (one calls you
## out and the rest know roughly where you are; the one with the longest
## reach pins you down while the others flank you, a side each; they rush you
## while you reload or heal), team up mid-match against a bot they both hate
## (or you, when you're leading), break up when the job's done, and turn on
## each other when the win is in sight: a sneak will, a noble never. The one
## turned on never forgets, and never gangs up with that one again.

const TEST_DEF := "res://data/critters/test_critter.tres"

var mm: MatchManager
var said: Array = []   # [critter, text] for everything said


func before_each() -> void:
	make_arena(160.0)
	RivalBook.reset_for_tests()
	mm = MatchManager.new()
	add_child(mm)
	said = []
	Events.taunt.connect(_heard)


func after_each() -> void:
	Events.taunt.disconnect(_heard)
	RivalBook.reset_for_tests()


func _heard(c: Node, text: String) -> void:
	said.append([c, text])


func _said(c: Critter, lines: Array, fields := {}) -> bool:
	return said.any(func(s): return s[0] == c and lines.any(func(l): return s[1] == String(l).format(fields)))


## A rogue of this kind (its voice), not one of `skip`.
func _one(voice: String, skip := []) -> String:
	for n in Cast.names():
		if RivalBook.personality_of(n) == voice and not skip.has(n):
			return n
	return ""


func _bot(n: String, at: Vector3, yaw := 0.0) -> Critter:
	var c := spawn_critter(TEST_DEF, at, yaw)
	c.display_name = n
	var b := AIBrain.new()
	b.name = "AIBrain"
	b.match_manager = mm
	b.personality = RivalBook.personality_of(n)
	b.skill = 0.8
	c.add_child(b)
	b.set_physics_process(false)
	mm.critters.append(c)
	return c


func _you(at: Vector3, yaw := 0.0) -> Critter:
	var c := spawn_critter(TEST_DEF, at, yaw)
	c.is_player = true
	mm.player = c
	mm.critters.append(c)
	return c


func _brain(c: Critter) -> AIBrain:
	return c.get_node("AIBrain") as AIBrain


func _arm(c: Critter, gun: StringName) -> void:
	c.give_weapon(WeaponInstance.new(WeaponDB.get_weapon(gun), Rarity.Tier.GARDEN))


func test_one_calls_you_out_and_the_gang_knows_where_you_are() -> void:
	var you := _you(Vector3(0, 0.1, -30))
	var a := _bot("Sly", Vector3(0, 0.1, 0))              # looking your way
	var b := _bot("Vex", Vector3(35, 0.1, 25), PI)        # looking away
	var c := _bot("Croaker", Vector3(-35, 0.1, 25), PI)
	await wait_physics(3)
	var g := mm.make_gang([a, b, c])
	check(a.gang == g.name and b.gang == g.name and c.gang == g.name, "they're a gang: %s" % g.name)
	for o: Critter in [b, c]:
		_brain(o)._perceive()
		check(_brain(o).target == null, "(%s can't see you)" % o.display_name)
	var ab := _brain(a)
	for i in 40:
		ab._clock += 0.2
		ab._perceive()
		if ab.target == you:
			break
	check(ab.target == you, "Sly spots you")
	for o: Critter in [b, c]:
		var ob := _brain(o)
		var off := ob._hunt_pos.distance_to(you.global_position) if ob._hunt_pos != Vector3.INF else INF
		check(off < 5.0 and ob.awareness_of(you) >= 0.7, "%s knows roughly where you are without seeing you (%.1f m off)" % [o.display_name, off])
	check(_said(a, Cast.GANG_SPOT_LINES), "Sly called it out")
	var hp := b.health
	b.take_damage(DamageInfo.make(30.0, DamageInfo.Kind.BULLET, a, &"carrot_smg"))
	check(b.health == hp, "gang mates' carrots don't hurt each other")


func test_the_long_gun_pins_you_down_and_the_rest_flank() -> void:
	var you := _you(Vector3(0, 0.1, 0))                   # looking -Z
	var a := _bot("Sly", Vector3(0, 0.1, -25), PI)        # in front of you, looking at you
	var b := _bot("Vex", Vector3(4, 0.1, -14), PI)
	var c := _bot("Croaker", Vector3(-4, 0.1, -14), PI)
	await wait_physics(3)
	_arm(a, &"carrot_sniper")
	_arm(b, &"carrot_pistol")
	_arm(c, &"carrot_pistol")
	await wait_physics(2)
	mm.make_gang([a, b, c])
	check(_brain(a).flank == 0 and _brain(b).flank * _brain(c).flank == -1,
		"the sniper pins you; the others flank, a side each (%d, %d, %d)" % [_brain(a).flank, _brain(b).flank, _brain(c).flank])
	var sides := []
	for o: Critter in [b, c]:
		var ob := _brain(o)
		ob.target = you
		ob._last_seen_t = ob._clock
		ob._last_seen_pos = you.get_chest_position()
		ob._fight(0.1)
		var spot := ob._flank_spot(o.global_position.distance_to(you.global_position))
		var to_spot := spot - o.global_position
		to_spot.y = 0.0
		var world := Basis(Vector3.UP, o.look_yaw) * Vector3(o.move_input.x, 0.0, -o.move_input.y)
		check(world.length() > 0.5 and world.normalized().dot(to_spot.normalized()) > 0.7,
			"%s heads round to its side (%.2f)" % [o.display_name, world.normalized().dot(to_spot.normalized())])
		var off := spot - you.global_position
		sides.append(atan2(off.x, -off.z))   # (round from where you're looking)
	var apart := absf(wrapf(sides[0] - sides[1], -PI, PI))
	check(apart > deg_to_rad(120.0), "they come at you from either side (%.0f° apart)" % rad_to_deg(apart))
	check(absf(sides[0]) > deg_to_rad(60.0) and absf(sides[1]) > deg_to_rad(60.0), "out of your eyeline")


func test_they_rush_you_while_you_heal_or_reload() -> void:
	var you := _you(Vector3(0, 0.1, 0))
	var b := _bot("Vex", Vector3(0, 0.1, -15), PI)
	var c := _bot("Croaker", Vector3(5, 0.1, -15), PI)
	await wait_physics(3)
	_arm(b, &"carrot_pistol")
	_arm(c, &"carrot_pistol")
	await wait_physics(2)
	mm.make_gang([b, c])
	var bb := _brain(b)
	bb.target = you
	check(not bb._rushing(), "not while you're ready for them")
	Events.clover_eaten.emit(you)
	check(bb._rushing(), "you eat a clover: they rush you")
	bb._last_seen_t = bb._clock
	bb._last_seen_pos = you.get_chest_position()
	bb._fight(0.1)
	check(b.want_sprint and b.move_input.y > 0.5, "flat out, straight at you (%s)" % b.move_input)
	check(said.any(func(s): return s[1] in Cast.GANG_RUSH_LINES), "shouting it")
	bb._clock += 3.0
	check(not bb._rushing(), "(for a moment)")
	_arm(you, &"carrot_rifle")
	await wait_physics(30)
	var w := you.current_weapon()
	if check(w != null, "(you've a rifle)"):
		w.ammo_in_mag = 0
		you.inventory.add_ammo(w.data.ammo_type, 30)
		you.start_reload()
		check(you.is_reloading() and bb._rushing(), "and while you reload")


func test_the_win_in_sight_a_sneak_turns_on_its_gang_and_a_noble_never_does() -> void:
	var sneak_n := _one("sneak")
	var noble_n := _one("noble")
	var you := _you(Vector3(0, 0.1, 60))
	var s := _bot(sneak_n, Vector3(0, 0.1, 0))
	var n := _bot(noble_n, Vector3(4, 0.1, 0))
	var others := []
	for o in Cast.names().filter(func(x): return x != sneak_n and x != noble_n).slice(0, 4):
		others.append(_bot(o, Vector3(-40.0 + others.size() * 6.0, 0.1, -50.0)))
	await wait_physics(3)
	var g := mm.make_gang([s, n])
	check(mm.betrayal_chance(s, g) == 0.0, "with the lobby still full, nobody turns (%d left)" % mm.alive_critters().size())
	for o in others:
		o.take_damage(DamageInfo.make(9999.0, DamageInfo.Kind.BULLET, null))
	await wait_physics(2)
	check(mm.win_in_sight(g), "down to the two of them and you: the win's in sight")
	check(mm.betrayal_chance(n, g) == 0.0, "a noble never turns on its gang")
	check(mm.betrayal_chance(s, g) > 0.1, "a sneak might, any second (%.2f a second)" % mm.betrayal_chance(s, g))
	mm.rng.seed = 7
	var secs := 0
	while s.gang != "" and secs < 120:
		mm._tend_gangs(1.0)
		secs += 1
	check(s.gang == "" and n.gang == "", "the sneak turned on the noble (after %d s), and that's the end of the gang" % secs)
	check(_brain(s).target == n, "and goes for it")
	check(_said(s, Cast.BETRAY_LINES, {"them": noble_n}), "saying so")
	check(RivalBook.betrayed_by(noble_n).has(sneak_n) and int(RivalBook.grudges(noble_n).get(sneak_n, 0)) >= 2, "the noble never forgets")
	var hp := n.health
	n.take_damage(DamageInfo.make(10.0, DamageInfo.Kind.BULLET, s, &"carrot_smg"))
	check(n.health < hp, "and the sneak's carrots hurt now")
	check(" ".join(GalleryPanel.memory_lines(noble_n)).contains("Betrayed by %s" % sneak_n), "the gallery remembers")
	# never again: not at the drop...
	for x in [[sneak_n, s], [noble_n, n]]:
		for i in 3:
			RivalBook.note_you_beat(x[0], "test_critter")
	mm._form_gang()
	check(mm.gang_of(s) == null and mm.gang_of(n) == null, "they never drop in as a gang again")
	# ...nor mid-match
	mm.player_beat_downs = MatchManager.LEADING_AT
	for i in 40:
		mm._try_truce()
	check(s.gang == "" and n.gang == "", "nor team up against you, though you're leading")
	check(WarrenSim.feuds(20).any(func(f): return f[0] == noble_n and f[1] == sneak_n and f[3]), "and Feud Watch calls it a betrayal")


func test_two_who_hate_the_same_bot_team_up_and_split_when_its_down() -> void:
	var a_n := _one("grump")
	var b_n := _one("grump", [a_n])
	var x_n: String = Cast.names().filter(func(x): return x != a_n and x != b_n)[0]
	RivalBook.note_bot_beat(x_n, a_n)
	RivalBook.note_bot_beat(x_n, b_n)
	var you := _you(Vector3(0, 0.1, 60))
	var a := _bot(a_n, Vector3(0, 0.1, 0))
	var b := _bot(b_n, Vector3(6, 0.1, 0))
	var x := _bot(x_n, Vector3(50, 0.1, -40))
	await wait_physics(3)
	mm.rng.seed = 3
	for i in 30:
		if a.gang == "":
			mm._try_truce()
	var g := mm.gang_of(a)
	check(g != null and b.gang == a.gang and g.enemy == x, "two grudge-holders near each other team up against %s" % x_n)
	check(_brain(a).gang_enemy == x and _brain(b).gang_enemy == x, "and go after it first")
	check(_said(a, Cast.TRUCE_LINES, {"them": x_n}), "\"Truce? Just till we get %s.\"" % x_n)
	check(x.gang == "" and you.gang == "", "(it's not about you)")
	x.take_damage(DamageInfo.make(9999.0, DamageInfo.Kind.BULLET, null))
	await wait_physics(2)
	mm._tend_gangs(1.0)
	check(a.gang == "" and b.gang == "" and mm.gangs.is_empty(), "the job's done, and so is the gang")
	check(said.any(func(s): return s[1] in Cast.DONE_LINES), "\"Pleasure doing business.\"")


func test_beat_one_down_and_a_disloyal_mate_cuts_and_runs() -> void:
	var p_n := _one("prankster")
	var g_n := _one("grump")
	var h_n := _one("hothead")
	var k_n := _one("noble")
	var you := _you(Vector3(0, 0.1, 0))
	var a := _bot(p_n, Vector3(0, 0.1, -20), PI)
	var b := _bot(g_n, Vector3(5, 0.1, -20), PI)
	var c := _bot(h_n, Vector3(-5, 0.1, -20), PI)
	var d := _bot(k_n, Vector3(10, 0.1, -20), PI)
	await wait_physics(3)
	mm.make_gang([a, b, c, d])
	a.health = 40.0
	b.health = 40.0
	c.take_damage(DamageInfo.make(9999.0, DamageInfo.Kind.BULLET, you))
	mm._gang_member_down(c)
	check(a.gang == "" and _brain(a)._shy_until > _brain(a)._clock, "the prankster, hurting, cuts and runs")
	check(_said(a, Cast.SPLIT_LINES), "\"I'm out!\"")
	check(b.gang != "" and b.gang == d.gang, "the loyal ones stay (a grudge-holder, a noble)")
	var ab := _brain(a)
	for i in 10:
		ab._clock += 0.2
		ab._perceive()
	check(ab.target != you, "and the one that ran leaves you be for a while")
