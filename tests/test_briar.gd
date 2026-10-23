extends TestCase
## The Briar's moods (Storm.VARIANTS), one per match: the Hungry Briar closes
## in on the player, the Sticky one slows you in its thorns, the Bribable one
## naps if you munch a clover in its thorns, the Wandering circle creeps, the
## Sleepy one waits longer but bites twice as hard, the Bouncy one bounces you.

const BUN := "res://data/critters/bun.tres"

var island: Island


func _storm(variant: String, player: Critter = null) -> Storm:
	island = Island.new()
	add_child(island)
	island.terrain = Terrain.new()
	island.add_child(island.terrain)
	island.terrain.setup(5)
	island.terrain.generate_heights()
	island.seed_value = 5
	var storm := Storm.new()
	add_child(storm)
	storm.player = player
	storm.start(island, island.terrain.island_radius + 50.0, 1.0, variant)
	return storm


func test_every_match_has_a_mood() -> void:
	var moods := {}
	for s in 40:
		var mm := MatchManager.new()
		mm.rng.seed = s * 7 + 1
		var all := Storm.VARIANTS.keys().filter(func(k): return k != "classic")
		mm.briar_variant = "classic" if mm.rng.randf() < 0.25 else all[mm.rng.randi() % all.size()]
		moods[mm.briar_variant] = true
		mm.free()
	check(moods.size() >= 5, "matches roll different Briars (%s)" % [moods.keys()])
	for v in Storm.VARIANTS:
		check(not String(Storm.VARIANTS[v].rule).is_empty(), "%s has a rule to announce" % v)


func test_hungry_briar_closes_in_on_the_player() -> void:
	make_arena(2000.0)
	var bun := spawn_critter(BUN, Vector3(300, 0.1, 120))
	await wait_physics(3)
	var storm := _storm("hungry", bun)
	var to_player := (Vector2(300, 120) - storm.center).normalized()
	var to_next := (storm.next_center - storm.center).normalized()
	check(to_next.dot(to_player) > 0.95, "the next circle moves toward the player (%.2f)" % to_next.dot(to_player))
	check(storm.next_center.distance_to(storm.center) + storm.next_radius <= storm.radius + 0.01, "and still fits inside the current one")


func test_sticky_bouncy_and_sleepy_thorns() -> void:
	make_arena(2000.0)
	var out := Vector3(800, 0.1, 0)
	var stuck := spawn_critter(BUN, out)
	await wait_physics(3)
	var sticky := _storm("sticky")
	await wait_physics(70)
	check(stuck.slow_factor < 0.7, "the Sticky Briar slows you in its thorns (%.2f)" % stuck.slow_factor)
	stuck.place_at(Vector3(0, 0.1, 0), 0.0)
	await wait_physics(70)
	check(is_equal_approx(stuck.slow_factor, 1.0), "and lets go once you're inside")
	sticky.active = false
	sticky.queue_free()
	island.queue_free()
	stuck.place_at(out, 0.0)
	await wait_physics(5)
	var bouncy := _storm("bouncy")
	var top := 0.0
	for i in 90:
		await wait_physics(1)
		top = maxf(top, stuck.velocity.y)
	check(top > 9.0, "the Bouncy Briar bounces you sky-high (%.1f m/s up)" % top)
	bouncy.active = false
	bouncy.queue_free()
	island.queue_free()
	var sleepy := _storm("sleepy")
	check_near(sleepy.time_left, Storm.STAGES[0][0] * sleepy.pace * 1.5, 0.5, "the Sleepy Briar waits half as long again")
	check_near(sleepy.dps, Storm.STAGES[0][3] * 2.0, 0.01, "but bites twice as hard")
	sleepy.active = false


func test_bribe_and_wander() -> void:
	make_arena(2000.0)
	var bun := spawn_critter(BUN, Vector3(800, 0.1, 0))
	await wait_physics(3)
	var storm := _storm("bribable")
	bun.inventory.clovers = 1
	bun.health = 50.0
	var t0 := storm.time_left
	check(bun.use_clover(), "munches a clover in the thorns")
	check(storm.nap_left > 0.0, "the Bribable Briar takes the bribe and naps")
	await wait_physics(60)
	check_near(storm.time_left, t0, 0.05, "its clock stops while it naps")
	storm.active = false
	storm.queue_free()
	island.queue_free()
	var wander := _storm("wandering")
	var c0 := wander.center
	await wait_physics(120)
	check(wander.center.distance_to(c0) > 2.0, "the Wandering circle creeps before it shrinks (%.1f m)" % wander.center.distance_to(c0))
	wander.active = false
