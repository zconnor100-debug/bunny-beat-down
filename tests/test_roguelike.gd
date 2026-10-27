extends TestCase
## The roguelike layer: boons (drafts, levels, duos, what each does in a
## match), carrots that split, pierce, bounce and pop, acorn shrines, a run
## down the Trail (stops, goals, helmets, rewards, picnics, the finale), and
## the bots that remember you (a nemesis hunt and its signature gun, a gang,
## scars, your stolen gun). Profile and rival book use their test files.


func before_each() -> void:
	PlayerProfile.reset_for_tests()
	RivalBook.reset_for_tests()
	Boons.reset()
	Run.in_match = false


func after_each() -> void:
	Boons.reset()
	Run.in_match = false
	AIBrain.player_stealth = 1.0


func test_boons_level_up_and_duos_need_two_families() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var first := Boons.offer(rng, 3)
	check(first.size() == 3 and first[0] != first[1] and first[1] != first[2] and first[0] != first[2], "three different boons: %s" % [first])
	check(first.all(func(id): return Boons.BOONS.has(id)), "no duos before you hold anything")
	Boons.add("thorny")
	Boons.add("thorny")
	check(Boons.level("thorny") == 2 and Boons.title("thorny") == "Thorny Carrots II", "picked again, it levels up: %s" % Boons.title("thorny"))
	check(Boons.describe("thorny").contains("7"), "the card shows the next level: %s" % Boons.describe("thorny"))
	for i in 3:
		Boons.add("thorny")
	check(Boons.level("thorny") == Boons.MAX_LEVEL, "up to level %d" % Boons.MAX_LEVEL)
	var seen := {}
	for s in 60:
		rng.seed = s
		for id in Boons.offer(rng, 3):
			seen[id] = true
	check(not seen.has("thorny"), "a maxed boon isn't offered again")
	check(not Boons.DUOS.keys().any(func(d): return seen.has(d)), "one family: no duos (%s)" % [seen.keys()])
	Boons.add("thick_skin")
	seen.clear()
	for s in 60:
		rng.seed = s
		for id in Boons.offer(rng, 3):
			seen[id] = true
	check(seen.has("bark_skin") and not seen.has("briar_shards") and not seen.has("second_breakfast"),
		"Bramble + Deep Roots: Bark Skin turns up, other duos don't (%s)" % [seen.keys().filter(func(k): return Boons.DUOS.has(k))])
	# stat boons onto a critter
	make_arena()
	var c := spawn_critter("res://data/critters/bun.tres", Vector3.ZERO)
	var hp := c.max_health
	Boons.reset()
	for id in ["thick_skin", "sugar_rush", "quick_draw", "hush"]:
		var was := Boons.add(id)
		Boons.apply_level(c, id, was, Boons.level(id))
	check_near(c.max_health, hp + 20.0, 0.01, "Thick Skin: +20 health")
	check_near(c.speed_scale, 1.1, 0.001, "Sugar Rush: 10% faster")
	check_near(c.reload_scale, 0.8, 0.001, "Quick Draw: reloads 20% faster")
	check_near(AIBrain.player_stealth, 0.8, 0.001, "Hush: spotted 25% slower")
	var was := Boons.add("thick_skin")
	Boons.apply_level(c, "thick_skin", was, Boons.level("thick_skin"))
	check_near(c.max_health, hp + 40.0, 0.01, "level 2: +40 in all")


func test_thorns_bleeding_and_carrot_juice() -> void:
	var mm := await _match(4)
	var you := mm.spawn_player(load("res://data/critters/bun.tres"), "default")
	you.place_at(Vector3(0, 40.0, 0), 0.0)
	var bots := mm.critters.filter(func(c): return c != you)
	var a: Critter = bots[0]
	var b: Critter = bots[1]
	for c in bots:
		c.get_node("AIBrain").process_mode = Node.PROCESS_MODE_DISABLED
	a.place_at(Vector3(6, 40.0, 0), 0.0)
	b.place_at(Vector3(-6, 40.0, 0), 0.0)
	await wait_physics(30)
	Boons.reset({"thorny": 1, "carrot_juice": 1, "cruel_thorns": 1})
	you.health = 50.0
	var hp := a.health
	a.take_damage(DamageInfo.make(20.0, DamageInfo.Kind.BULLET, you, &"carrot_rifle"))
	check(a.bleed_t > 0.0 and a.bleed_dps == 3.0 and a.bleed_by == you, "Thorny Carrots: it bleeds (%.1f s at %.0f/s)" % [a.bleed_t, a.bleed_dps])
	check_near(you.health, 50.0 + 20.0 * 0.08, 0.01, "Carrot Juice: you heal 8% of it")
	a.take_damage(DamageInfo.make(20.0, DamageInfo.Kind.BULLET, you, &"carrot_rifle"))
	check_near(hp - a.health, 20.0 + 24.0, 0.01, "Cruel Thorns: a bleeding critter takes 20% more")
	var before := a.health
	await wait_physics(270)
	check(a.bleed_t <= 0.0 and before - a.health > 12.0 and before - a.health < 16.0,
		"it bled about 3 a second for 4 s, crueller for the thorns (%.1f)" % (before - a.health))
	# bleeding out is your beat-down, with the gun that cut it
	a.health = 2.0
	a.bleed(3.0, 2.0, you, &"carrot_rifle")
	await wait_physics(80)
	check(not a.alive and you.kills == 1 and StatBook.gun(&"carrot_rifle").kills == 1.0, "bled out: your beat-down, the rifle's")
	# Bramble Coat: hit you, and the thorns hit back
	Boons.reset({"bramble_coat": 1})
	var bhp := b.health
	you.take_damage(DamageInfo.make(20.0, DamageInfo.Kind.BULLET, b, &"carrot_smg"))
	check(b.health < bhp and bhp - b.health < 5.0, "Bramble Coat: a quarter of it back in thorns (%.2f)" % (bhp - b.health))


func test_carrots_that_split_pierce_bounce_and_pop() -> void:
	var mm := await _match(2)
	var you := mm.spawn_player(load("res://data/critters/bun.tres"), "default")
	you.place_at(Vector3(0, 40.0, 0), -PI / 2.0)
	for c in mm.critters:
		if c != you:
			c.get_node("AIBrain").process_mode = Node.PROCESS_MODE_DISABLED
			c.place_at(Vector3(0, 40.0, 30.0 + mm.critters.find(c) * 3.0), 0.0)
	var a := _dummy("Sly", Vector3(7, 40.0, 0))
	var b := _dummy("Fennick", Vector3(10, 40.0, 0))
	await wait_physics(40)
	# Piercing Carrots: one carrot through the first fox and into the second
	Boons.reset({"piercing": 1})
	var rifle := WeaponInstance.new(WeaponDB.get_weapon(&"carrot_rifle"), Rarity.Tier.GARDEN)
	you.give_weapon(rifle)
	you.aim_point = a.get_chest_position()
	you._fire(rifle)
	await wait_physics(20)
	var da := a.max_health - a.health
	var db := b.max_health - b.health
	check(da > 0.0 and db > 0.0, "pierced: one carrot hit both foxes (%.1f, %.1f)" % [da, db])
	# straight to the mutations (no aiming needed)
	var proj := Projectiles.instance
	var through := Projectiles.Shot.new()
	through.data = rifle.data
	through.vel = Vector3(400, 0, 0)
	through.damage_scale = 1.0
	through.mut = {"pierce": 1}
	through.pierce_left = 1
	var before := proj.live_shots().size()
	check(proj._mutate_on_critter(through, a.get_chest_position(), a) and proj.live_shots().size() == before + 1
		and is_equal_approx(proj.live_shots().back().damage_scale, Projectiles.PIERCE_KEEP), "a pierced carrot goes on at 70%")
	var s := Projectiles.Shot.new()
	s.data = rifle.data
	s.weapon = rifle
	s.shooter = you
	s.vel = Vector3(400, 0, 0)
	s.damage_scale = 1.0
	s.mut = {"split": 3}
	var n0 := proj.live_shots().size()
	proj._mutate_on_critter(s, a.get_chest_position(), a)
	var shards := proj.live_shots().slice(n0)
	check(shards.size() == 3 and shards.all(func(x): return x.shard and x.mutated and is_equal_approx(x.damage_scale, 0.4)),
		"Splitting Carrots: three shards at 40%% (%d)" % shards.size())
	check(shards.all(func(x): return a.visual.hitbox_rids.all(func(r): return x.exclude.has(r))), "that don't hit the fox they burst from")
	var bounce := Projectiles.Shot.new()
	bounce.vel = Vector3(100, -50, 0)
	bounce.bounce_left = 1
	proj._bounce(bounce, {"position": Vector3(0, 0, 0), "normal": Vector3.UP})
	check(bounce.vel.y > 0.0 and bounce.bounce_left == 0 and bounce.mutated, "Bouncy Carrots: off the floor and up (%s)" % bounce.vel)
	# Popping Carrots: one in six goes off where it lands
	Boons.reset({"popping": 1})
	var blasts := [0]
	Events.explosion.connect(func(_p, _r): blasts[0] += 1)
	for i in 6:
		you.aim_point = you.global_position + Vector3(5, 0, 0)   # (the floor: every carrot lands)
		you._fire(rifle)
	await wait_physics(30)
	check(blasts[0] == 1, "one pop in six carrots (%d)" % blasts[0])
	# a gun with a mutation built in works for whoever holds it
	var sig := RivalBook.signature_gun("Sly")
	check(sig.rarity == Rarity.Tier.GOLDEN and sig.mutation in RivalBook.SIGNATURE_MUTATIONS and sig.display_name().begins_with("Sly's"),
		"Sly's signature gun: %s, %s" % [sig.display_name(), sig.mutation])
	check(not Projectiles.mutations_for(a, sig).is_empty(), "its mutation works in a bot's paws too")


func test_acorn_shrines_offer_you_a_boon() -> void:
	var mm := await _match(2)
	check(mm.shrines.size() == 3, "three shrines in the Hamster Cage (%d)" % mm.shrines.size())
	var sh: AcornShrine = mm.shrines[0]
	check(sh.is_in_group(&"shrines") and not sh.is_in_group(&"crates") and not sh.is_in_group(&"treasure"), "bots don't go looking for them")
	var you := mm.spawn_player(load("res://data/critters/bun.tres"), "default")
	var bot: Critter = mm.critters.filter(func(c): return c != you)[0]
	you.place_at(sh.global_position + Vector3(0.9, 0.2, 0), 0.0)
	bot.place_at(sh.global_position + Vector3(-0.9, 0.2, 0), 0.0)
	await wait_physics(20)
	var offered := []
	mm.boons_offered.connect(func(choices, _t): offered.append(choices))
	for i in 120:
		sh.channel(bot, 1.0 / 60.0)
	check(not sh.opened, "a bot can't pray there")
	for i in 100:
		sh.channel(you, 1.0 / 60.0)
		if sh.opened:
			break
	check(sh.opened and offered.size() == 1 and offered[0].size() == 3, "you can: a draft of three (%s)" % [offered])
	var hp := you.max_health
	mm.choose_boon("thick_skin")
	check(Boons.level("thick_skin") == 1 and you.max_health == hp + 20.0, "and the boon takes effect at once")


func test_a_run_down_the_trail() -> void:
	Run.start(1234)
	var trail: Array = Run.state().trail
	check(trail == Run.generate(1234) and trail.size() == Run.ROWS and trail.back().size() == 1 and trail.back()[0].kind == "finale",
		"five rows, the same for the same seed, ending at the finale")
	check(not trail[0].any(func(st): return st.kind == "picnic"), "no picnic first")
	for r in Run.ROWS - 1:
		for j in trail[r + 1].size():
			check(trail[r].any(func(st): return st.links.has(j)), "row %d stop %d can be reached" % [r + 1, j])
	check(Run.choices() == range(trail[0].size()), "any first stop")
	var col := _match_stop(0)
	check(Run.choose(col), "go to a stop")
	Run.in_match = true
	check(Burrow.modifiers() == Run.current().mods, "the stop's own modifiers play (%s)" % [Run.mods()])
	Run.in_match = false
	var g := Run.goal(24)
	check(int(g.top) >= 3 and int(g.kills) >= 2, "a goal: %s" % Run.goal_text(24))
	var rifle := WeaponInstance.new(WeaponDB.get_weapon(&"carrot_rifle"), Rarity.Tier.PRIZE)
	var r := Run.finish_match(int(g.top), 24, 0, false, [rifle], 2, {"thorny": 1})
	check(r.met and Run.state().row == 1 and Run.rewinds() == 2 and Run.boons() == {"thorny": 1}, "goal made: on to stop 2, rewinds and boons carried")
	check(Run.pending().size() == 2 and str(Run.pending()[0]) == "draft", "a boon, then a keepsake, waiting (%s)" % [Run.pending()])
	Run.take_pending("sugar_rush")
	Run.take_pending("", Run.pending()[0].keepsake[0])
	check(Run.boons().has("sugar_rush") and Run.keepsake().data.id == &"carrot_rifle" and Run.keepsake().rarity == Rarity.Tier.PRIZE,
		"took Sugar Rush, pocketed the rifle")
	# three missed goals: the run is over
	for i in 3:
		Run.choose(_match_stop(Run.state().row))
		Run.finish_match(24, 24, 0, false, [], 1, Run.boons())
	check(not Run.active() and Run.state().over and Run.helmets() == 0 and Run.record("helmets_lost") == 3, "three helmets cracked: run over")
	# a picnic
	var seed_ := 1
	while not Run.generate(seed_)[1].any(func(st): return st.kind == "picnic"):
		seed_ += 1
	Run.start(seed_)
	Run.choose(_match_stop(0))
	Run.finish_match(1, 24, 3, true, [], 3, {})
	var picnic: int = Run.state().trail[1].map(func(st): return st.kind).find("picnic")
	if not Run.choices().has(picnic):   # (not linked from where we went: walk the state there)
		var st := Run.state()
		st.at = Run.state().trail[0].map(func(x): return x.links.has(picnic)).find(true)
		Run._save(st)
	check(Run.choose(picnic), "a picnic")
	Run.picnic("rewinds")
	check(Run.rewinds() == 3 + Run.PICNIC_REWINDS and Run.state().row == 2, "two more rewinds, and on")
	# the finale: miss it and try again, then make it
	var st := Run.state()
	st.row = Run.ROWS - 1
	st.at = 0
	Run._save(st)
	Run.choose(0)
	check(Run.opponents(5) == Run.FINALE_LOBBY - 1 and int(Run.goal(24).top) == Run.FINALE_TOP, "the finale: a big lobby, top 3")
	var acorns := Burrow.acorns()
	Run.finish_match(8, 24, 2, false, [], 0, {})
	check(Run.active() and Run.state().row == Run.ROWS - 1 and Run.choices() == [0], "missed it: a helmet, and another go")
	Run.choose(0)
	Run.finish_match(2, 24, 2, false, [], 0, {})
	check(Run.state().complete and Burrow.acorns() == acorns + Run.COMPLETE_ACORNS and Run.record("completed") == 1,
		"made it: run complete, +%d acorns" % Run.COMPLETE_ACORNS)


func test_nemesis_gang_scars_and_your_stolen_gun() -> void:
	for i in 8:
		RivalBook.note_you_beat("Sly", "fox")
	for n in [["Croaker", "frog"], ["Vex", "bandit_bunny"]]:
		for i in 3:
			RivalBook.note_you_beat(n[0], n[1])
	RivalBook.add_scar("Croaker", "eye_patch")
	RivalBook.add_scar("Croaker", "arm_l")
	RivalBook.note_took_gun("Vex", {"id": "carrot_smg", "rarity": Rarity.Tier.HEIRLOOM, "skin": "candy"})
	RivalBook.save()
	var mm := await _match(6)
	var sly := _find(mm, "Sly")
	var croaker := _find(mm, "Croaker")
	var vex := _find(mm, "Vex")
	check(sly != null and croaker != null and vex != null, "the bots you've made radical are all here")
	check(mm.nemesis == sly and is_equal_approx(sly.max_health, sly.def.max_health * MatchManager.NEMESIS_HEALTH), "Sly is your nemesis, and tougher")
	check(sly.visual.name_tag.text.contains("NEMESIS"), "its tag says so: %s" % sly.visual.name_tag.text)
	check(mm.gang.size() == 3 and [sly, croaker, vex].all(func(c): return c.gang == mm.gang_name), "and they've ganged up: %s" % mm.gang_name)
	check(croaker.head_guard == 0.75 and is_equal_approx(croaker.max_health, croaker.def.max_health + 10.0), "Croaker's scars: it guards its head, and it's tougher")
	var worn := croaker.visual.find_children("*", "MeshInstance3D", true, false).filter(func(m): return m.has_meta(&"scar"))
	check(worn.size() >= 5, "and wears them: an eye patch and strap, bandages (%d)" % worn.size())
	var smg := vex.current_weapon()
	check(smg != null and smg.data.id == &"carrot_smg" and smg.rarity == Rarity.Tier.HEIRLOOM and vex.visual.kit.get("skin") == "candy",
		"Vex has your Heirloom SMG, in your candy skin")
	var news := mm.headlines()
	check(news[0].begins_with("NEMESIS HUNT") and news.any(func(t): return t.contains("ganged up")) and news.any(func(t): return t.contains("carrying your")),
		"the lobby news: %s" % [news])
	var hp := croaker.health
	croaker.take_damage(DamageInfo.make(30.0, DamageInfo.Kind.BULLET, vex, &"carrot_smg"))
	check(croaker.health == hp, "gang mates' carrots don't hurt each other")
	var you := mm.spawn_player(load("res://data/critters/bun.tres"), "default")
	for c in mm.critters:
		c.place_at(Vector3(c.global_position.x, 40.0, c.global_position.z), 0.0)
		if c != you:
			c.get_node("AIBrain").process_mode = Node.PROCESS_MODE_DISABLED   # (nobody grabs the drop first)
	await wait_physics(3)
	vex.take_damage(DamageInfo.make(999.0, DamageInfo.Kind.BULLET, you, &"carrot_rifle"))
	await wait_frames(2)
	check(RivalBook.took_gun("Vex").is_empty(), "you got your SMG back")
	var shot := DamageInfo.make(999.0, DamageInfo.Kind.BULLET, you, &"carrot_rifle")
	shot.headshot = true
	sly.take_damage(shot)
	await wait_frames(2)
	var sigs := get_tree().get_nodes_in_group(&"pickups").filter(func(p): return p.is_weapon() and (p.spec.weapon as WeaponInstance).signature == "Sly")
	check(mm.nemesis == null and sigs.size() == 1 and RivalBook.signature_won("Sly"),
		"nemesis down: its signature gun drops, and it's in your book (%s, %d, %s)" % [mm.nemesis, sigs.size(), RivalBook.signature_won("Sly")])
	check(RivalBook.scars("Sly").has("eye_patch"), "and Sly will remember that headshot")
	you.give_weapon(WeaponInstance.new(WeaponDB.get_weapon(&"carrot_lmg"), Rarity.Tier.GOLDEN))
	you.take_damage(DamageInfo.make(999.0, DamageInfo.Kind.BULLET, croaker, &"carrot_rifle"))
	await wait_frames(2)
	var took := RivalBook.took_gun("Croaker")
	check(took.get("id") == "carrot_lmg" and int(took.get("rarity")) == Rarity.Tier.GOLDEN, "Croaker took your Golden LMG (%s)" % [took])
	var card := GalleryPanel.card("Croaker")
	check(card.contains("an eye patch") and card.contains("It has your Golden Carrot"), "its card remembers: %s" % card)


func test_the_trail_and_draft_screens() -> void:
	var tp := TrailPanel.new()
	add_child(tp)
	await wait_frames(2)
	var start := _button(tp, "Start a run")
	check(start != null, "the Trail offers a run")
	start.pressed.emit()
	await wait_frames(2)
	var lit := tp.find_children("*", "Button", true, false).filter(func(b): return not b.disabled and b.text.contains("Goal"))
	check(lit.size() == Run.state().trail[0].size(), "the first stops are lit (%d)" % lit.size())
	var st := Run.state()
	st.pending = ["draft"]
	Run._save(st)
	tp.rebuild()
	await wait_frames(2)
	var cards := tp.find_children("*", "Button", true, false).filter(func(b): return b.text.contains("\n\n"))
	check(cards.size() == 3, "a boon waiting: three cards (%d)" % cards.size())
	cards[0].pressed.emit()
	await wait_frames(2)
	check(Run.boons().size() == 1 and Run.pending().is_empty(), "picked: %s" % [Run.boons()])
	st = Run.state()
	st.over = true
	st.active = false
	Run._save(st)
	tp.rebuild()
	await wait_frames(2)
	check(tp.find_children("*", "Label", true, false).any(func(l): return l.text == "RUN OVER"), "a run that's over says so")
	tp.queue_free()


# ---- helpers -------------------------------------------------------------------------------------

func _match(opponents: int) -> MatchManager:
	var cage := HamsterCage.new()
	add_child(cage)
	await cage.generate(31, 0, false)
	add_child(FX.new())
	add_child(Projectiles.new())
	var mm := MatchManager.new()
	add_child(mm)
	mm.setup(self, cage, opponents, 1, 31)
	return mm


func _find(mm: MatchManager, n: String) -> Critter:
	for c in mm.critters:
		if c.display_name == n:
			return c
	return null


## A fox standing still (no brain), out of any match.
func _dummy(n: String, at: Vector3) -> Critter:
	var c := Critter.new()
	c.def = load("res://data/critters/fox.tres")
	c.display_name = n
	add_child(c)
	c.place_at(at, PI / 2.0)
	return c


## A match stop (not a picnic) you can go to in this row.
func _match_stop(row: int) -> int:
	for col in Run.choices():
		if Run.stop(row, col).kind != "picnic":
			return col
	return Run.choices()[0]


func _button(root: Node, text: String) -> Button:
	for b in root.find_children("*", "Button", true, false):
		if b.text == text:
			return b
	return null


func test_the_gallery_shows_the_scars_you_gave_it() -> void:
	RivalBook.add_scar("Croaker", "eye_patch")
	RivalBook.add_scar("Croaker", "leg_r")
	RivalBook.add_scar("Croaker", "singed")
	var p := CritterPortrait.new(Vector2(320, 360))
	add_child(p)
	await wait_frames(2)
	p.show_rogue("Croaker")
	await wait_frames(2)
	var c := p.shown_critter()
	var scars := c.find_children("*", "MeshInstance3D", true, false).filter(func(x): return x.has_meta(&"scar"))
	check(scars.size() >= 3, "its portrait wears its eye patch and splint (%d pieces)" % scars.size())
	var sooty := false
	for m in c.visual.meshes:
		var mat := m.get_surface_override_material(0) as BaseMaterial3D
		sooty = sooty or (mat != null and mat.next_pass is ShaderMaterial and (mat.next_pass as ShaderMaterial).shader == CritterVisual.SINGED_SHADER)
	check(c.visual.singed and sooty, "and its singed fur is sooty")
	check(GalleryPanel.card_title("Croaker").ends_with("scarred") and not GalleryPanel.card_title("Vex").ends_with("scarred"),
		"the list marks it scarred (and not one you've never hurt)")
	p.show_rogue("Vex")
	await wait_frames(2)
	var none := p.shown_critter().find_children("*", "MeshInstance3D", true, false).filter(func(x): return x.has_meta(&"scar"))
	check(none.is_empty() and not p.shown_critter().visual.singed, "a rogue you've never hurt has none")
	p.queue_free()


func test_reset_all_rogues_asks_first_then_starts_them_over() -> void:
	for i in 8:
		RivalBook.note_you_beat("Sly", "fox")
	for i in RivalBook.RIVAL_AT:
		RivalBook.note_you_died_to("Vex", "bandit_bunny")
	RivalBook.add_scar("Sly", "eye_patch")
	RivalBook.note_took_gun("Vex", {"id": "carrot_smg", "rarity": Rarity.Tier.HEIRLOOM, "skin": "candy"})
	RivalBook.note_signature_won("Sly")
	RivalBook.save()
	check(Cast.heat("Sly") == 4 and RivalBook.is_rival("Vex"), "(Sly's a nemesis, Vex your rival)")
	var g := GalleryPanel.new()
	add_child(g)
	await wait_frames(2)
	g._reset.pressed.emit()
	await wait_frames(1)
	check(g._confirm.visible and g._no.has_focus() and Cast.heat("Sly") == 4, "Reset all rogues asks first (No in focus), and nothing's reset yet")
	var asked := g._confirm.get_child(0) as Label
	check(asked.text == "Are You Sure you want to reset all rogues to original?", "in so many words")
	g._no.pressed.emit()
	await wait_frames(1)
	check(not g._confirm.visible and Cast.heat("Sly") == 4 and RivalBook.is_rival("Vex"), "No: nobody's reset")
	g._reset.pressed.emit()
	(g._confirm.get_child(1) as Button).pressed.emit()
	await wait_frames(2)
	check(Cast.heat("Sly") == 0 and not RivalBook.is_rival("Vex") and RivalBook.scars("Sly").is_empty() and RivalBook.took_gun("Vex").is_empty(),
		"Yes: every rogue starts over (no heat, rival, scars, or gun of yours)")
	check(RivalBook.signatures() == ["Sly"], "the signature guns you won stay yours (%s)" % [RivalBook.signatures()])
	check(not GalleryPanel.card_title("Sly").ends_with("scarred") and (g._list.get_child(0) as Button).text == GalleryPanel.card_title(GalleryPanel.order()[0]),
		"the list starts over too")
	RivalBook._cfg = null   # (read back from the file)
	check(Cast.heat("Sly") == 0 and RivalBook.signature_won("Sly"), "and it's saved")
	g.queue_free()
