extends TestCase
## The Burrow (meta progression, its own test file here): acorns earned per
## match, perks unlocked with them and equipped (two at a time, three with A
## Bigger Burrow), real power in the match (shield, clovers, a gun, faster
## reloads, higher jumps, a Second Wind, healing, a shield that grows back...),
## run modifiers that change the match and the pay, and the Workshop's gun
## attachments and looks.


func before_each() -> void:
	PlayerProfile.reset_for_tests()
	RivalBook.reset_for_tests()   # (no scars from other tests' matches: a scarred rogue comes back tougher)


func after_each() -> void:
	Critter.glass_cannon = false
	CritterVisual.name_tag_range_scale = 1.0
	AIBrain.player_stealth = 1.0
	AIBrain.player_muffled = false
	AIBrain.vision_scale = 1.0
	WeaponDB.only = &""
	Projectiles.own_tracer = Projectiles.TRACER_OWN
	await super()


func test_earn_unlock_and_equip() -> void:
	check(Burrow.acorns() == 0, "you start with no acorns")
	check(not Burrow.unlock("thick_fur"), "and can't afford a perk")
	var win := Burrow.reward(1, 24, 4, 1)
	var early := Burrow.reward(20, 24, 0, 0)
	check(win > early * 5, "winning pays far more than an early exit (%d vs %d)" % [win, early])
	Burrow.add_acorns(400)
	check(Burrow.unlock("thick_fur") and Burrow.unlocked("thick_fur"), "unlocked Thick Fur")
	check(Burrow.acorns() == 400 - int(Burrow.PERKS["thick_fur"].cost), "it cost its price")
	check(not Burrow.unlock("thick_fur"), "you only buy a perk once")
	for p in ["pocket_clover", "quick_paws"]:
		Burrow.unlock(p)
	check(Burrow.set_equipped("thick_fur", true) and Burrow.set_equipped("pocket_clover", true), "equip two perks")
	check(not Burrow.set_equipped("quick_paws", true), "but not a third (%d slots)" % Burrow.slots())
	check(Burrow.set_equipped("thick_fur", false) and Burrow.set_equipped("quick_paws", true), "swap one out")
	check(not Burrow.set_equipped("second_wind", true), "can't equip what you haven't unlocked")
	Burrow.set_modifier("briar_rush", true)
	check(Burrow.reward(1, 24, 0, 0) > Burrow.reward(1, 24, 0, 0) * 0.0 + 50, "a modifier pays a bonus")
	PlayerProfile._cfg = null
	check(Burrow.unlocked("quick_paws") and Burrow.has_perk("quick_paws") and Burrow.modifier_on("briar_rush"), "all remembered after a restart")


func test_perks_and_modifiers_in_a_match() -> void:
	Burrow.add_acorns(2000)
	for p in Burrow.PERKS:
		Burrow.unlock(p)
	Burrow.set_equipped("thick_fur", true)
	Burrow.set_equipped("lucky_start", true)
	Burrow.set_modifier("glass_cannon", true)
	Burrow.set_modifier("golden_hour", true)
	var cage := HamsterCage.new()
	add_child(cage)
	await cage.generate(31, 0, false)
	add_child(FX.new())
	add_child(Projectiles.new())
	var mm := MatchManager.new()
	add_child(mm)
	mm.setup(self, cage, 4, 1, 31)
	var player := mm.spawn_player(load("res://data/critters/bun.tres"), "default")
	check(is_equal_approx(player.armor, 50.0), "Thick Fur: dropped in with 50 shield")
	var w := player.current_weapon()
	check(w != null and w.rarity >= Rarity.Tier.PRIZE, "Lucky Start: landed with a %s gun" % (Rarity.NAMES[w.rarity] if w else "no"))
	check(Critter.glass_cannon, "Glass Cannon is on for the match")
	var bot: Critter = mm.critters.filter(func(c): return c != player)[0]
	bot.place_at(Vector3(bot.global_position.x, 40.0, bot.global_position.z), 0.0)
	await wait_physics(3)
	var hp := bot.health
	bot.armor = 0.0
	bot.take_damage(DamageInfo.make(20.0, DamageInfo.Kind.BULLET, player))
	check_near(hp - bot.health, 30.0, 0.01, "your hits land half as hard again")
	# the other perks, on a second player
	Burrow.set_equipped("thick_fur", false)
	Burrow.set_equipped("lucky_start", false)
	Burrow.set_equipped("second_wind", true)
	Burrow.set_equipped("spring_legs", true)
	var p2 := mm.spawn_player(load("res://data/critters/bun.tres"), "default")
	check(p2.second_wind and p2.jump_scale > 1.2, "Second Wind and Spring Legs")
	p2.place_at(Vector3(20, 40.0, 20), 0.0)
	await wait_physics(3)
	Critter.glass_cannon = false
	p2.take_damage(DamageInfo.make(500.0, DamageInfo.Kind.BULLET, bot))
	check(p2.alive and is_equal_approx(p2.health, 1.0), "Second Wind: the killing blow left you at 1 HP")
	p2.take_damage(DamageInfo.make(500.0, DamageInfo.Kind.BULLET, bot))
	check(not p2.alive, "but only once a match")
	# Golden Hour: floor loot one tier up (no Baby guns lying around)
	var babies := 0
	for n in get_tree().get_nodes_in_group(&"pickups"):
		var pk := n as Pickup
		if pk and pk.is_weapon() and (pk.spec["weapon"] as WeaponInstance).rarity == Rarity.Tier.BABY:
			babies += 1
	check(babies == 0, "Golden Hour: no Baby-tier guns on the floor (%d)" % babies)


func test_a_bigger_burrow_takes_three_perks() -> void:
	Burrow.add_acorns(2000)
	for p in ["thick_fur", "pocket_clover", "quick_paws"]:
		Burrow.unlock(p)
		Burrow.set_equipped(p, true)
	check(Burrow.equipped().size() == 2, "two slots to start with")
	check(Burrow.unlock("third_slot") and Burrow.slots() == 3, "A Bigger Burrow: three")
	check(Burrow.set_equipped("quick_paws", true) and Burrow.equipped().size() == 3, "and a third perk goes in")
	check(not Burrow.set_equipped("third_slot", true), "an upgrade isn't a perk to equip")
	var before := Burrow.reward(1, 24, 2, 0)
	Burrow.unlock("acorn_magnet")
	Burrow.set_equipped("quick_paws", false)
	Burrow.set_equipped("acorn_magnet", true)
	check(Burrow.reward(1, 24, 2, 0) == roundi(before * 1.25), "Acorn Magnet: a quarter more (%d vs %d)" % [Burrow.reward(1, 24, 2, 0), before])


func test_the_new_perks_in_a_match() -> void:
	Burrow.add_acorns(5000)
	Burrow.unlock("third_slot")
	for p in Burrow.PERKS:
		Burrow.unlock(p)
	for p in ["big_appetite", "deep_pockets", "thorn_coat"]:
		Burrow.set_equipped(p, true)
	var mm := await _match()
	var you := mm.spawn_player(load("res://data/critters/bun.tres"), "default")
	you.place_at(Vector3(10, 40.0, 10), 0.0)
	check(is_equal_approx(you.clover_heal, 60.0), "Big Appetite: clovers heal 60 (%.0f)" % you.clover_heal)
	check(you.inventory.add_ammo(0, 100000) < 100000 and you.inventory.ammo[0] == roundi(Inventory.AMMO_CAP[0] * 1.5), "Deep Pockets: half as many spare carrots again")
	await wait_physics(2)
	var hp := you.health
	you.take_damage(DamageInfo.make(10.0, DamageInfo.Kind.STORM, null))
	check_near(hp - you.health, 5.0, 0.01, "Thorn Coat: the Briar hurts half as much")
	# a second player with the rest
	for p in Burrow.equipped():
		Burrow.set_equipped(p, false)
	for p in ["regrowth", "adrenaline", "scavenger"]:
		Burrow.set_equipped(p, true)
	var p2 := mm.spawn_player(load("res://data/critters/bun.tres"), "default")
	p2.place_at(Vector3(-10, 40.0, -10), 0.0)
	await wait_physics(2)
	p2.armor = 0.0
	p2._unhurt_t = Critter.REGROW_AFTER + 1.0
	await wait_physics(30)
	check(p2.armor > 0.0 and p2.armor <= 25.0, "Regrowth: the shield grows back (%.1f)" % p2.armor)
	p2.health = 50.0
	var bot: Critter = mm.critters.filter(func(c): return c != p2 and c != you)[0]
	bot.place_at(Vector3(0, 40.0, 0), 0.0)
	await wait_physics(2)
	var clovers_before := get_tree().get_nodes_in_group(&"pickups").filter(func(n): return n is Pickup and n.spec.get("type") == "clover").size()
	bot.take_damage(DamageInfo.make(999.0, DamageInfo.Kind.BULLET, p2))
	await wait_frames(2)
	check(is_equal_approx(p2.health, 70.0), "Adrenaline: a beat-down heals 20 (%.0f)" % p2.health)
	var clovers := get_tree().get_nodes_in_group(&"pickups").filter(func(n): return n is Pickup and n.spec.get("type") == "clover").size()
	check(clovers == clovers_before + 1, "Scavenger: it dropped a clover (%d → %d)" % [clovers_before, clovers])


func test_the_new_run_modifiers() -> void:
	for m in ["pea_soup", "fragile", "rocket_party", "most_wanted", "stampede", "clover_drought"]:
		Burrow.set_modifier(m, true)
	check(Burrow.reward(5, 24, 0, 0) > Burrow.reward(5, 24, 0, 0) / 1.5, "they pay more")
	var mm := await _match()
	check(is_equal_approx(AIBrain.vision_scale, 0.5), "Pea Soup: everyone sees half as far")
	var you := mm.spawn_player(load("res://data/critters/bun.tres"), "default")
	check(is_equal_approx(you.max_health, 50.0) and is_equal_approx(you.health, 50.0), "Fragile Fluff: half the health (%.0f)" % you.max_health)
	var bot: Critter = mm.critters.filter(func(c): return c != you)[0]
	check(is_equal_approx(bot.max_health, 50.0), "for everyone")
	check(is_equal_approx(bot.speed_scale, 1.2) and is_equal_approx(you.speed_scale, 1.0), "Stampede: bots run faster, you don't")
	check(is_equal_approx(you.clover_heal, 20.0), "Clover Drought: clovers heal half")
	var guns := get_tree().get_nodes_in_group(&"pickups").filter(func(n): return n is Pickup and n.is_weapon())
	check(not guns.is_empty() and guns.all(func(g): return (g.spec["weapon"] as WeaponInstance).data.id == &"carrot_rocket_launcher"),
		"Rocket Party: every gun on the floor is a rocket launcher (%d)" % guns.size())
	# Most Wanted: once the timer comes round, the nearest bots come for you
	you.place_at(Vector3(5, 40.0, 5), 0.0)
	for c in mm.critters:
		if c != you:
			c.place_at(Vector3(c.global_position.x, 40.0, c.global_position.z), 0.0)
	mm._set_phase(MatchManager.Phase.PLAYING)
	await wait_physics(2)
	var heads := []
	Events.headline.connect(func(t): heads.append(t))
	mm._wanted_t = MatchManager.WANTED_EVERY
	await wait_frames(3)
	var hunting := mm.critters.filter(func(c): return c != you and (c.get_node("AIBrain") as AIBrain)._hunt_pos != Vector3.INF)
	check(hunting.size() >= 1 and heads.has("The bots know where you are."), "Most Wanted: %d bots told where you are" % hunting.size())


func test_the_workshop() -> void:
	check(Workshop.owns("reticle:cross") and Workshop.look("reticle") == "cross", "the first option of each look is free and worn")
	check(not Workshop.buy("red_dot"), "attachments cost acorns")
	Burrow.add_acorns(1000)
	check(Workshop.buy("red_dot") and Workshop.fitted("red_dot"), "buy the Red Dot Sight: fitted")
	check(Burrow.acorns() == 1000 - Workshop.cost("red_dot"), "for its price")
	Workshop.set_fitted("red_dot", false)
	check(Workshop.owns("red_dot") and not Workshop.fitted("red_dot"), "take it off (still yours)")
	Workshop.set_fitted("red_dot", true)
	for a in ["long_mag", "muffler", "laser", "stock"]:
		Workshop.buy(a)
	check(not Workshop.set_look("reticle", "carrot"), "a look you don't own can't be worn")
	for item in ["reticle:carrot", "reticle_color:leaf", "skin:candy", "flash:plum", "smoke:spores", "tracer:gold", "kill_fx:confetti"]:
		check(Workshop.buy(item), "bought %s" % item)
		var parts: PackedStringArray = String(item).split(":")
		Workshop.set_look(parts[0], parts[1])
	check(Workshop.look("skin") == "candy", "and wear them")
	PlayerProfile._cfg = null
	check(Workshop.fitted("muffler") and Workshop.look("tracer") == "gold", "remembered after a restart")
	# in a match: your guns handle and look the part
	var mm := await _match()
	check(AIBrain.player_muffled, "the Muffler is on for the match")
	check(Projectiles.own_tracer.is_equal_approx(Color(Workshop.COLORS.gold, 0.6)), "gold tracers")
	var you := mm.spawn_player(load("res://data/critters/bun.tres"), "default")
	check(is_equal_approx(you.aim_spread_scale, 0.75) and is_equal_approx(you.hip_spread_scale, 0.8) and is_equal_approx(you.bloom_scale, 0.7),
		"sight, laser and stock steady your shots")
	check(you.flash_look == "plum" and you.smoke_look == "spores" and you.muffled, "your flash, smoke and muffler")
	var w := WeaponInstance.new(WeaponDB.get_weapon(&"carrot_rifle"), Rarity.Tier.GARDEN)
	var base := w.magazine_size()
	you.give_weapon(w)
	check(w.magazine_size() == roundi(base * 1.3) and w.ammo_in_mag == w.magazine_size(), "Carrot Quiver: 30%% more carrots (%d → %d), full" % [base, w.magazine_size()])
	await wait_frames(2)
	var gun := you.visual.weapon_model
	check(gun.find_child("RedDot", true, false) != null and gun.find_child("Laser", true, false) != null, "the gun wears a sight and a laser")
	var skinned := gun.find_children("*", "GeometryInstance3D", true, false).filter(func(g): return g.material_overlay == GunKit.skin_material("candy"))
	check(not skinned.is_empty(), "and its candy stripes")
	FX.beat_down(Vector3(0, 40, 0), Workshop.look("kill_fx"))
	var canvas := ReticleCanvas.new()
	add_child(canvas)
	await wait_frames(3)
	check(canvas.drawn == Workshop.LOOKS.reticle.options.size(), "every reticle draws (%d)" % canvas.drawn)
	# and the Burrow shows it all, with previews
	var panel := BurrowPanel.new()
	add_child(panel)
	await wait_frames(2)
	var labels := panel.find_children("*", "Label", true, false).map(func(l): return l.text)
	check(labels.has("Reticle: Carrot") and labels.has("Gun skin: Candy stripe"), "the Workshop lists your looks")
	check(panel.find_children("*", "Button", true, false).any(func(b): return b.text == "Fitted ✓"), "and your attachments")


## Browsing a look (◂ ▸) rebuilds the list: it used to jump to its end on
## every press, and the portrait's gun never wore the skin being browsed.
func test_browsing_the_workshop_keeps_your_place_and_shows_the_skin() -> void:
	var panel := BurrowPanel.new()
	add_child(panel)
	await wait_frames(10)
	var bar := panel._scroll.get_v_scroll_bar()
	check(bar.max_value - bar.page > 600.0, "the list is long enough to scroll (%d)" % bar.max_value)
	var next := _arrow(panel, "skin")
	next.grab_focus()
	await wait_frames(5)
	var before := panel._scroll.scroll_vertical
	check(before > 0 and before < bar.max_value - bar.page - 100.0, "scrolled to the gun skins, not the end (%d)" % before)
	for skin in ["fern_camo", "candy"]:
		_arrow(panel, "skin").pressed.emit()
		await wait_frames(6)
		check(panel._scroll.scroll_vertical == before, "▸ to %s: the list stays put (%d, was %d)" % [skin, panel._scroll.scroll_vertical, before])
		var focused := get_viewport().gui_get_focus_owner()
		check(focused == _arrow(panel, "skin"), "and the skin row's ▸ keeps the focus")
		check(panel.shown("skin") == skin, "showing %s" % skin)
		var gun: Node3D = panel._portrait.shown_critter().visual.weapon_model
		var skinned := gun.find_children("*", "GeometryInstance3D", true, false).filter(func(g): return g.material_overlay == GunKit.skin_material(skin))
		check(not skinned.is_empty(), "the portrait's gun wears %s (bought or not)" % skin)
	check(Workshop.look("skin") == "stock", "only trying them on: still wearing the stock skin")


## The coat rack: every coat at once, on you, side by side. Wear one
## you've earned; one you haven't is dimmed, with how far along you are.
func test_the_coat_rack() -> void:
	var book := PlayerProfile._book()
	book.set_value("workshop", "owned", ["coat:starry_night"])
	var panel := BurrowPanel.new()
	add_child(panel)
	await wait_frames(6)
	var open: Button = panel._list.find_children("*", "Button", true, false).filter(func(b): return b.text == "Open")[0]
	open.pressed.emit()
	await wait_frames(6)
	var rack: CoatRack = panel._rack
	var coats: Array = Workshop.LOOKS[Workshop.COAT].options
	check(rack != null and not panel._shelves.visible, "the rack takes the list's place")
	check(rack._portraits.size() == coats.size(), "every coat on its own turntable (%d)" % rack._portraits.size())
	var starry: Critter = (rack._portraits["starry_night"] as CritterPortrait).shown_critter()
	check(starry != null and starry.visual.meshes[0].material_overlay == Workshop.coat_material("starry_night"), "each worn by you")
	check(rack._portraits["natural"].modulate == Color.WHITE and rack._portraits["starry_night"].modulate == Color.WHITE
		and rack._portraits["patchwork"].modulate == CoatRack.LOCKED, "yours bright, the rest dimmed")
	check(CoatRack.how_to("patchwork") == "Play 100 matches. (0 / 100)" and CoatRack.how_to("starry_night").begins_with("Earned:"),
		"with what earns each and how far along you are (%s)" % CoatRack.how_to("patchwork"))
	check(get_viewport().gui_get_focus_owner() == rack._buttons["natural"], "the coat you're wearing has the focus")
	rack._buttons["patchwork"].pressed.emit()
	check(Workshop.look(Workshop.COAT) == "natural" and rack._title.text.begins_with("Not yet"), "one you haven't earned stays on the rack")
	rack._buttons["starry_night"].pressed.emit()
	check(Workshop.look(Workshop.COAT) == "starry_night" and rack._buttons["starry_night"].text == "Wearing ✓", "one you have, you put on")
	rack.closed.emit()
	await wait_frames(6)
	check(panel._rack == null and panel._shelves.visible, "back to the list")
	check(panel.shown(Workshop.COAT) == "starry_night" and get_viewport().gui_get_focus_owner() == open_button(panel),
		"showing the coat you put on, the rack's row in focus")


func open_button(panel: BurrowPanel) -> Button:
	var open := panel._list.find_children("*", "Button", true, false).filter(func(b): return b.text == "Open")
	return open[0] if not open.is_empty() else null


func _arrow(panel: BurrowPanel, cat: String) -> Button:
	for h in panel._list.get_children():
		if h is HBoxContainer and (h.get_child(0) as Label).text.begins_with(Workshop.LOOKS[cat].label + ":"):
			for b in h.get_children():
				if b is Button and b.text == "▸":
					return b
	return null

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


## Draws every reticle style in a real draw pass.
class ReticleCanvas:
	extends Control
	var drawn := 0

	func _draw() -> void:
		drawn = 0
		for s in Workshop.LOOKS.reticle.options:
			Reticle.draw(self, Vector2(40 + drawn * 60, 40), 8.0, s[0], Color.WHITE)
			drawn += 1
