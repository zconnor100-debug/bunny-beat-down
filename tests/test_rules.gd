extends TestCase
## Game rules: weapon data sanity, rarity scaling and rolls, the Briar's
## geometry, armor, and the gore setting being respected.

const TEST_DEF := "res://data/critters/test_critter.tres"


func test_weapons_are_sane() -> void:
	var all := WeaponDB.all()
	check(all.size() == 7, "seven carrot guns (%d)" % all.size())
	for w in all:
		var dps := w.damage * w.pellets * w.rounds_per_minute / 60.0
		check(dps > 20.0 and dps < 250.0, "%s dps %.0f in a sane range" % [w.id, dps])
		check(w.magazine > 0 and w.reload_time > 0.2, "%s mag/reload" % w.id)
		check(ResourceLoader.exists(w.model_path), "%s has its model" % w.id)
		check(w.damage_at(0.0) >= w.damage_at(500.0), "%s damage falls off with range" % w.id)
	var rocket := WeaponDB.get_weapon(&"carrot_rocket_launcher")
	check(rocket.splash_radius > 0.0 and rocket.ai_min_range > rocket.splash_radius, "bots won't rocket themselves")


func test_rarity_scales_and_rolls() -> void:
	var w0 := WeaponInstance.new(WeaponDB.get_weapon(&"carrot_lmg"), Rarity.Tier.BABY)
	var w4 := WeaponInstance.new(WeaponDB.get_weapon(&"carrot_lmg"), Rarity.Tier.GOLDEN)
	check(w4.damage_scale() > w0.damage_scale(), "golden hits harder")
	check(w4.magazine_size() > w0.magazine_size(), "golden holds more")
	check(w4.reload_time() < w0.reload_time(), "golden reloads faster")
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var counts := [0, 0, 0, 0, 0]
	for i in 5000:
		counts[Rarity.roll(Rarity.FLOOR_WEIGHTS, rng)] += 1
	check(counts[0] > counts[4] * 5, "baby loot is far commoner than golden (%s)" % [counts])
	check(counts[4] > 0, "golden loot can drop")
	var crate_baby := 0
	for i in 2000:
		if Rarity.roll(Rarity.CRATE_WEIGHTS, rng) == 0:
			crate_baby += 1
	check(crate_baby == 0, "crates never hold baby-tier guns")


func test_storm_geometry() -> void:
	var island := Island.new()
	add_child(island)
	island.terrain = Terrain.new()
	island.add_child(island.terrain)
	island.terrain.setup(5)
	island.terrain.generate_heights()
	island.seed_value = 5
	var storm := Storm.new()
	add_child(storm)
	storm.start(island, 260.0, 1.0)
	check(storm.is_safe(Vector3.ZERO), "centre is safe at the start")
	check(storm.next_radius < storm.radius, "first circle shrinks")
	check(Vector2.ZERO.distance_to(storm.next_center) + storm.next_radius <= storm.radius + 0.01, "next circle fits inside the current one")
	var outside := Vector3(400, 0, 0)
	check(not storm.is_safe(outside), "far out at sea is in the Briar")
	check(storm.threat(outside) > 0.0, "AI feels the threat outside")
	var sp := storm.safe_point(outside)
	check(Vector2(sp.x, sp.z).distance_to(storm.next_center) < storm.next_radius, "safe point lies inside the next circle")


func test_armor_absorbs_first() -> void:
	make_arena()
	var c := spawn_critter(TEST_DEF, Vector3(0, 0.1, 0))
	await wait_physics(2)
	c.armor = 50.0
	c.take_damage(DamageInfo.make(30.0, DamageInfo.Kind.BULLET, null))
	check_near(c.armor, 20.0, 0.01, "armor soaks the hit")
	check_near(c.health, 100.0, 0.01, "health untouched")
	c.take_damage(DamageInfo.make(30.0, DamageInfo.Kind.BULLET, null))
	check_near(c.armor, 0.0, 0.01, "armor broken")
	check_near(c.health, 90.0, 0.01, "overflow reaches health")
	c.take_damage(DamageInfo.make(5.0, DamageInfo.Kind.STORM, null))
	check_near(c.health, 85.0, 0.01, "the Briar ignores armor")


func test_gore_off_spawns_no_gibs() -> void:
	make_arena()
	Settings.set_value(&"gore", Settings.Gore.OFF, false)
	var c := spawn_critter(TEST_DEF, Vector3(0, 0.1, 0))
	await wait_physics(2)
	var info := DamageInfo.make(999.0, DamageInfo.Kind.EXPLOSION, null)
	info.dismember_power = 1.0
	info.impulse = 10.0
	c.take_damage(info)
	await wait_physics(5)
	var gibs := 0
	for n in get_tree().root.find_children("*", "RigidBody3D", true, false):
		if n.has_meta(&"gib"):
			gibs += 1
	check(gibs == 0, "no limbs fly when gore is off (%d)" % gibs)
	check(c.visual.ragdolled, "still ragdolls")
	Settings.set_value(&"gore", Settings.Gore.BLOOD, false)


func test_critters_swim_in_deep_water() -> void:
	# a sea floor 5 m down; the island's water surface is at y = 0
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = Layers.WORLD
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40, 1, 40)
	cs.shape = box
	cs.position.y = -5.5
	floor_body.add_child(cs)
	add_child(floor_body)
	add_child(FX.new())
	add_child(Projectiles.new())
	var island := Island.new()
	add_child(island)
	Island.current = island
	var c := spawn_critter(TEST_DEF, Vector3(0, -4.0, 0))
	await wait_physics(150)
	check(c.swimming, "critter is swimming")
	check(c.global_position.y > -1.0 and c.global_position.y < 0.0, "floats with its head above water (y=%.2f)" % c.global_position.y)
	Island.current = null
