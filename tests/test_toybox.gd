extends TestCase
## Toy Box Bash: every landmark on the bedroom floor and in its biome, a
## navmesh that reaches every floor of the dollhouse (up the stairs) and into
## every walk-in toy, a fishbowl you swim in, a paper plane under the
## ceiling, and the toy train: it runs round its loop, carries a rider, and
## bonks anyone standing on the track.

const BUN := "res://data/critters/bun.tres"

var toy: ToyBox


func _make_toybox(nav := true) -> void:
	toy = ToyBox.new()
	add_child(toy)
	var t0 := Time.get_ticks_msec()
	await toy.generate(4242, 1, nav)
	print("    toy box generated in %d ms" % (Time.get_ticks_msec() - t0))


func test_toybox_layout_and_paths() -> void:
	await _make_toybox()
	var tf := toy.terrain as ToyFloor
	check(toy.ready_to_play, "generation finished")
	check(toy.pois.size() == ToyBox.TOY_POIS.size(), "every landmark placed (%d)" % toy.pois.size())
	for p in toy.pois:
		check(tf.inside(p.center.x, p.center.y, 20.0), "%s is on the bedroom floor" % p.name)
		var w := tf.biome_at(p.center.x, p.center.y)
		var share: float = [w.x, w.y, w.z][int(p.biome)]
		check(share > 0.4, "%s is in its biome (%.2f)" % [p.name, share])
	check(toy.loot_points.size() > 250, "plenty of loot (%d)" % toy.loot_points.size())
	var stray := toy.loot_points.filter(func(l): return not tf.inside(l.pos.x, l.pos.z, 2.0))
	check(stray.is_empty(), "no loot outside the room (%d)" % stray.size())
	# from the middle of the rug, a bot can walk to every walk-in toy, and up
	# to every floor of the dollhouse
	var map := get_world_3d().navigation_map
	var from := NavigationServer3D.map_get_closest_point(map, Vector3(60, ToyFloor.FLOOR, 0))
	var floors := {}
	for b in toy.buildings:
		for spot in b.world_loot_spots():
			var to := NavigationServer3D.map_get_closest_point(map, spot)
			var path := Island.find_path(map, from, to)
			var ok := to.distance_to(spot) < 2.0 and path.size() >= 2 and path[path.size() - 1].distance_to(to) < 3.0
			check(ok, "%s: a bot can walk to the loot at %s" % [b.name, spot.snapped(Vector3.ONE * 0.1)])
			if b.name.begins_with("Dollhouse") and ok:
				floors[snappedf(spot.y - b.global_position.y, 1.0)] = true
	check(floors.size() >= 3, "all three dollhouse floors are reachable (%s)" % [floors.keys()])
	# the paper plane flies wall to wall under the ceiling
	var ship := Dropship.new()
	add_child(ship)
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	ship.setup(tf.island_radius, rng, toy.drop_vehicle, toy.play_bounds())
	check(ship.get_node_or_null("PaperPlane") != null, "everyone rides in on the paper airplane")
	for end in [ship.start, ship.finish]:
		check(tf.inside(end.x, end.z, 10.0) and end.y < ToyRoom.CEILING, "the route stays inside the room (%s)" % end)
	ship.queue_free()


func test_toy_train_rides_and_bonks() -> void:
	await _make_toybox(false)
	add_child(FX.new())
	add_child(Projectiles.new())
	var train := toy.train
	check(train != null and train.cars.size() == 6, "the toy train is on its track")
	check(train.total > 2500.0, "a loop round the whole room (%.0f m)" % train.total)
	# it moves at its speed along the loop
	var d0 := train.distance
	var p0 := train.cars[0].global_position
	await wait_physics(60)
	var moved := fposmod(train.distance - d0, train.total)
	check_near(moved, ToyTrain.SPEED, 1.5, "rolls along (%.1f m in a second)" % moved)
	check(train.cars[0].global_position.distance_to(p0) > 10.0, "and the engine really moved")
	# a critter standing on an open car rides along with it
	train.running = false
	await wait_physics(2)
	var car := train.cars[3]
	var rider := spawn_critter(BUN, car.global_position + Vector3.UP * (ToyTrain.DECK + 0.6))
	await wait_physics(40)
	check(rider.is_on_floor(), "standing on the open car")
	var start := rider.global_position
	train.running = true
	await wait_physics(90)
	var rode := rider.global_position.distance_to(start)
	check(rode > ToyTrain.SPEED * 1.0, "rode the train %.0f m in 1.5 s" % rode)
	check(rider.global_position.y > ToyFloor.FLOOR + ToyTrain.DECK - 0.5, "still aboard")
	rider.queue_free()
	await wait_physics(2)
	# a critter standing on the track ahead gets bonked off it
	train.running = false
	await wait_physics(2)
	var ahead := train.frame_at(train.distance + 40.0)
	var victim := spawn_critter(BUN, ahead.origin + Vector3.UP * 0.3)
	await wait_physics(20)
	var hp := victim.health
	train.running = true
	await wait_physics(240)
	check(victim.health < hp - 20.0, "bonked by the train (%.0f → %.0f hp)" % [hp, victim.health])
	var off := Vector2(victim.global_position.x, victim.global_position.z)
	var near := INF
	for i in range(0, train.track.size(), 2):
		near = minf(near, off.distance_to(Vector2(train.track[i].x, train.track[i].z)))
	check(near > ToyTrain.TRACK_WIDTH * 0.5, "and knocked off the track (%.1f m from it)" % near)


func test_fishbowl_swim() -> void:
	await _make_toybox(false)
	add_child(FX.new())
	add_child(Projectiles.new())
	var fb: Dictionary = toy.fishbowl
	check(not fb.is_empty() and fb.level > ToyFloor.FLOOR + 20.0, "the fishbowl is full to the brim")
	var swimmer := spawn_critter(BUN, Vector3(fb.center.x, fb.level - 1.0, fb.center.y))
	await wait_physics(90)
	check(swimmer.swimming, "swimming in the fishbowl")
	check(swimmer.global_position.y > fb.level - 3.0, "floating at the top")
