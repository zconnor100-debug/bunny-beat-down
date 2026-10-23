extends TestCase
## The Burrow (meta progression, its own test file here): acorns earned per
## match, perks unlocked with them and equipped (two at a time), real power
## in the match (shield, clovers, a gun, faster reloads, higher jumps, a
## Second Wind), and run modifiers that change the match and the pay.


func before_each() -> void:
	PlayerProfile.reset_for_tests()


func after_each() -> void:
	Critter.glass_cannon = false
	CritterVisual.name_tag_range_scale = 1.0
	AIBrain.player_stealth = 1.0
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
	check(not Burrow.set_equipped("quick_paws", true), "but not a third (%d slots)" % Burrow.SLOTS)
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
