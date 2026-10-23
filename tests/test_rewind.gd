extends TestCase
## Rewind (TimeKeeper): ten seconds back, three times a match. Everyone still
## standing goes back where they were with what they carried, the loot they
## took returns to the floor, the guns they swapped out leave it, carrots in
## flight vanish, the Briar's clock winds back, and the beaten-down stay down.
## A killing blow on the player freezes the match and offers a rewind. The
## rewind plays out: the world runs backwards for a moment first.

var _mm: MatchManager
var _cage: HamsterCage


func before_each() -> void:
	PlayerProfile.reset_for_tests()
	RivalBook.reset_for_tests()


func after_each() -> void:
	get_tree().paused = false
	await super()


func _setup() -> Critter:
	_cage = HamsterCage.new()
	add_child(_cage)
	await _cage.generate(31, 0, false)
	add_child(FX.new())
	add_child(Projectiles.new())
	_mm = MatchManager.new()
	add_child(_mm)
	_mm.setup(self, _cage, 3, 1, 31)
	var player := _mm.spawn_player(load("res://data/critters/bun.tres"), "default")
	var i := 0
	for c in _mm.critters:
		var x := 40.0 + i * 6.0
		c.place_at(Vector3(x, _cage.terrain.height_at(x, 30.0) + 0.3, 30.0), 0.0)
		var brain := c.get_node_or_null("AIBrain") as AIBrain
		if brain:
			brain.process_mode = Node.PROCESS_MODE_DISABLED   # (hold still so we know where they were)
		i += 1
	await wait_physics(20)
	return player


## A gun of this kind lying within a metre of `pos` (the map has plenty elsewhere).
func _weapon_pickup_near(id: StringName, pos: Vector3) -> Pickup:
	for n in get_tree().get_nodes_in_group(&"pickups"):
		var p := n as Pickup
		if p and not p.is_queued_for_deletion() and p.is_weapon() and (p.spec["weapon"] as WeaponInstance).data.id == id \
				and p.global_position.distance_to(pos) < 1.0:
			return p
	return null


func test_rewind_puts_everyone_back() -> void:
	var player := await _setup()
	var tk := _mm.time_keeper
	check(tk != null and TimeKeeper.instance == tk, "every match has a time keeper")
	check(not tk.can_rewind(), "nothing to rewind before the match is on")
	var rifle := WeaponInstance.new(WeaponDB.get_weapon(&"carrot_rifle"))
	rifle.ammo_in_mag = 7
	player.give_weapon(rifle)
	player.health = 80.0
	player.armor = 20.0
	player.inventory.clovers = 1
	_mm.storm.start(_cage, 300.0, 1.0, "classic")
	_mm.phase = MatchManager.Phase.PLAYING
	await wait_physics(2)
	var was := player.global_position
	var briar := _mm.storm.time_left
	var ammo: Dictionary = player.inventory.ammo.duplicate()
	await wait_physics(40)
	# ...then a lot happens
	player.place_at(was + Vector3(25, 3, 0), 1.0)
	player.health = 30.0
	player.armor = 0.0
	var shotgun := Pickup.spawn(self, Pickup.weapon_spec(WeaponInstance.new(WeaponDB.get_weapon(&"carrot_shotgun"))), was + Vector3(2, 0.5, 0))
	var clover := Pickup.spawn(self, Pickup.clover_spec(1), was + Vector3(-2, 0.5, 0))
	await wait_physics(2)
	var shotgun_at := shotgun.global_position
	check(shotgun.try_collect(player) and clover.try_collect(player), "picked up a shotgun and a clover")
	check(player.inventory.weapon_count() == 2 and player.inventory.clovers == 2, "now carrying them")
	player.current_weapon().ammo_in_mag = 0
	var swapped := Pickup.spawn(self, Pickup.weapon_spec(WeaponInstance.new(WeaponDB.get_weapon(&"carrot_pistol"))), was + Vector3(0, 0.5, 3))
	swapped.dropped_by = player   # (a gun swapped out after the snapshot)
	var bots := _mm.critters.filter(func(c): return c != player)
	var fallen: Critter = bots[0]
	var standing: Critter = bots[1]
	var standing_was := standing.global_position
	standing.place_at(standing_was + Vector3(0, 0, 12), 0.0)
	standing.health = 5.0
	fallen.take_damage(DamageInfo.make(500.0, DamageInfo.Kind.BULLET, player))
	Projectiles.fire(standing, WeaponInstance.new(WeaponDB.get_weapon(&"carrot_rifle")), standing.global_position + Vector3.UP, Vector3.FORWARD, 0.0, [])
	check(not Projectiles.instance._shots.is_empty(), "a carrot is in the air")
	check(_mm.storm.time_left < briar - 0.4, "the Briar's clock ran on (%.1f → %.1f)" % [briar, _mm.storm.time_left])
	# rewind! (at once: the playback has its own test)
	check(tk.rewind(false), "rewound")
	check(tk.charges == TimeKeeper.CHARGES - 1, "used one of %d charges" % TimeKeeper.CHARGES)
	check(player.global_position.distance_to(was) < 0.3, "the player is back where they were (%.2f m off)" % player.global_position.distance_to(was))
	check(is_equal_approx(player.health, 80.0) and is_equal_approx(player.armor, 20.0), "with the health and shield they had (%.0f / %.0f)" % [player.health, player.armor])
	var w := player.current_weapon()
	check(player.inventory.weapon_count() == 1 and w != null and w.data.id == &"carrot_rifle" and w.ammo_in_mag == 7, "holding just the rifle, 7 carrots in it")
	check(player.inventory.clovers == 1 and player.inventory.ammo == ammo, "the same clovers and ammo")
	check(standing.global_position.distance_to(standing_was) < 0.3 and standing.health > 90.0, "a bot is back where it was, healthy again")
	check(not fallen.alive, "but the beaten-down stay down")
	check(Projectiles.instance._shots.is_empty(), "carrots in flight vanished")
	check(absf(_mm.storm.time_left - briar) < 0.1, "the Briar's clock wound back (%.1f, was %.1f)" % [_mm.storm.time_left, briar])
	await wait_physics(1)
	check(_weapon_pickup_near(&"carrot_shotgun", shotgun_at) != null, "the shotgun is back on the floor")
	check(not is_instance_valid(swapped) or swapped.is_queued_for_deletion(), "the gun swapped out since is gone (you never dropped it)")
	# three a match
	await wait_physics(20)
	check(tk.rewind(false) and tk.rewind(false), "two more")
	await wait_physics(20)
	check(not tk.can_rewind() and not tk.rewind(false), "and that's all of them")


func test_the_world_runs_backwards() -> void:
	var player := await _setup()
	var tk := _mm.time_keeper
	_mm.phase = MatchManager.Phase.PLAYING
	await wait_physics(2)
	var was := player.global_position
	await wait_physics(40)
	player.place_at(was + Vector3(25, 0, 0), 0.0)
	await wait_physics(20)   # (a snapshot or two over here)
	var rewound := [false]
	tk.rewound.connect(func(): rewound[0] = true)
	check(tk.rewind(), "rewinding")
	check(tk.playing_back and get_tree().paused and not rewound[0], "the world runs backwards first, the match paused")
	check(not tk.can_rewind(), "(no rewinding a rewind)")
	var path: Array[float] = []
	var t0 := Time.get_ticks_msec()
	while tk.playing_back and Time.get_ticks_msec() - t0 < 3000:
		path.append(player.global_position.distance_to(was))
		await get_tree().process_frame
	var between := path.filter(func(d): return d > 1.0 and d < 24.0)
	check(between.size() >= 3, "the player glides back over several frames (%d in between)" % between.size())
	check(rewound[0] and not tk.playing_back and not get_tree().paused, "then it lands and the match goes on")
	check(player.global_position.distance_to(was) < 0.3, "right where the player was (%.2f m off)" % player.global_position.distance_to(was))
	var took := (Time.get_ticks_msec() - t0) / 1000.0
	check(took > TimeKeeper.PLAYBACK * 0.7 and took < TimeKeeper.PLAYBACK + 1.0, "in about %.1f s (%.2f s)" % [TimeKeeper.PLAYBACK, took])


func test_a_killing_blow_offers_a_rewind() -> void:
	var player := await _setup()
	var tk := _mm.time_keeper
	var offers := []
	tk.offered.connect(func(info): offers.append(info))
	_mm.phase = MatchManager.Phase.PLAYING
	await wait_physics(30)
	var bot: Critter = _mm.critters.filter(func(c): return c != player)[0]
	player.take_damage(DamageInfo.make(500.0, DamageInfo.Kind.BULLET, bot))
	check(offers.size() == 1 and player.alive and is_equal_approx(player.health, 1.0), "the blow is on hold, the player hangs on at 1 HP")
	check(get_tree().paused, "the match froze to ask")
	player.take_damage(DamageInfo.make(500.0, DamageInfo.Kind.BULLET, bot))
	check(offers.size() == 1 and player.alive, "(another pellet of the same blast waits too)")
	tk.resolve(true)
	await tk.rewound
	check(not get_tree().paused and player.alive and player.health > 90.0, "rewound: back on your paws (%.0f HP)" % player.health)
	check(tk.charges == TimeKeeper.CHARGES - 1, "and it used a charge")
	await wait_physics(10)
	player.take_damage(DamageInfo.make(500.0, DamageInfo.Kind.BULLET, bot))
	check(offers.size() == 2, "asked again")
	tk.resolve(false)
	check(not player.alive and not get_tree().paused, "accepting defeat lets the blow land")
	check(tk.charges == TimeKeeper.CHARGES - 1 and not tk.can_rewind(), "(no charge used, and no rewinding the beaten-down)")
	# with no charges left the blow just lands
	var p2 := _mm.spawn_player(load("res://data/critters/bun.tres"), "default")
	p2.place_at(Vector3(20, _cage.terrain.height_at(20, 20) + 0.3, 20), 0.0)
	await wait_physics(10)
	tk.charges = 0
	p2.take_damage(DamageInfo.make(500.0, DamageInfo.Kind.BULLET, bot))
	check(not p2.alive and offers.size() == 2, "no rewinds left: no offer")
