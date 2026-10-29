extends TestCase
## Toy Box Bash: every landmark on the bedroom floor and in its biome, a
## navmesh that reaches every floor of the dollhouse (up the stairs) and into
## every walk-in toy, a fishbowl you swim in, a paper plane under the
## ceiling, and the toy train: it runs round its loop, carries a rider, and
## bonks anyone standing on the track.

const BUN := "res://data/critters/bun.tres"

var toy: ToyBox
const MapCheck := preload("res://tests/map_check.gd")


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
	# the floor's hills and cover are big toys: every one found room, and a bot
	# can walk to the loot on and in them (up the sock hills, the block forts'
	# ramps and the airplane's wing, into the cabins)
	check(toy.clutter.size() == 16, "every big toy found room on the floor (%d)" % toy.clutter.size())
	var kinds := toy.clutter.map(func(k): return String(k.name).get_slice("_", 0))
	for want in ["TakeApartPlane", "Derailment", "BlockFort", "SockHill", "LogCabin"]:
		check(want in kinds, "there's a %s" % want)
	check(kinds.filter(func(n): return n.begins_with("Plush")).size() == 6, "and six stuffed animals")
	for k in toy.clutter.filter(func(k): return k is Building):
		for spot in (k as Building).world_loot_spots():
			var to := NavigationServer3D.map_get_closest_point(map, spot)
			var path := Island.find_path(map, from, to)
			check(to.distance_to(spot) < 2.0 and path.size() >= 2 and path[path.size() - 1].distance_to(to) < 3.0,
				"%s: a bot can walk to the loot at %s" % [k.name, spot.snapped(Vector3.ONE * 0.1)])
	# ... and the floor itself stays flat: no hills in it outside the pillow corner
	var bumps := 0
	for zi in range(-40, 41):
		for xi in range(-55, 56):
			var x := xi * 10.0
			var z := zi * 10.0
			if tf.biome_at(x, z).x > 0.98:
				var h := tf.height_at(x, z)
				bumps += int(h < ToyFloor.FLOOR - 0.05 or h > ToyFloor.FLOOR + ToyFloor.RUG_RAISE + 0.05)
	check(bumps == 0, "the bare floor is flat, rug and all (%d bumps)" % bumps)
	# crayon scribbled on the floor beside the loose crayons
	check(toy.scribbles.size() >= 6, "crayon scribbles on the floor (%d)" % toy.scribbles.size())
	for d in toy.scribbles:
		check(absf(d.global_position.y - tf.height_at(d.global_position.x, d.global_position.z)) < 0.3, "a scribble lies on the floor")
	# the paper plane flies wall to wall under the ceiling
	var ship := Dropship.new()
	add_child(ship)
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	ship.setup(tf.island_radius, rng, toy.drop_vehicle, toy.play_bounds())
	check(ship.get_node_or_null("PaperPlane") != null, "everyone rides in on the paper airplane")
	for end in [ship.start, ship.finish]:
		check(tf.inside(end.x, end.z, 10.0) and end.y < ToyRoom.CEILING, "the route stays inside the room (%s)" % end)
	check(ship.view_distance() > 40.0, "the ride camera frames the whole plane (%.0f m back)" % ship.view_distance())
	ship.queue_free()
	await _check_tidy(toy)


## Nothing generated inside anything else (more than a tube's joint into its
## pod), and every loot spot clear of solids once it spawns (nudged if need be).
func _check_tidy(map: Island) -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	var deep := MapCheck.overlaps(map, 0.5)
	check(deep.is_empty(), "no props inside other props (%d: %s)" % [deep.size(), ", ".join(deep.slice(0, 3).map(func(o): return "%s in %s by %.1f m" % [o.a, o.b, o.depth]))])
	var dropped := 0
	for l in map.loot_points:
		var half := Vector3(0.9, 0.5, 0.9) if l.get("crate", false) or l.has("chest") else Vector3(0.35, 0.3, 0.35)
		if map.clear_loot_spot(l.pos, half, not l.get("inside", false)) == Vector3.INF:
			dropped += 1
	check(dropped < map.loot_points.size() * 0.03, "loot spots inside solids are moved clear, hardly any dropped (%d of %d)" % [dropped, map.loot_points.size()])


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


## Riding the train in a match: your carrots keep the train's speed (so you
## can hit the critter on the next car), and a rewind puts the train back
## too, with you still aboard.
func test_train_riders_shoot_and_rewind() -> void:
	await _make_toybox(false)
	add_child(FX.new())
	add_child(Projectiles.new())
	PlayerProfile.reset_for_tests()
	RivalBook.reset_for_tests()
	var mm := MatchManager.new()
	add_child(mm)
	mm.setup(self, toy, 1, 1, 4242)
	var me := mm.spawn_player(load(BUN), "default")
	var bot: Critter = mm.critters.filter(func(c): return c != me)[0]
	bot.get_node("AIBrain").process_mode = Node.PROCESS_MODE_DISABLED
	var train := toy.train
	train.running = false
	# its open cars well into the east straight (the loop starts into the NE
	# corner: 173 m of curve, then 440 m straight), so the car runs straight
	# while we shoot from it
	train.set_distance(259.0)
	await wait_physics(2)
	var car := train.cars[3]
	me.place_at(car.global_position + Vector3.UP * (ToyTrain.DECK + 0.6), 0.0)
	bot.place_at(train.cars[4].global_position + Vector3.UP * (ToyTrain.DECK + 0.6), 0.0)
	await wait_physics(40)
	check(me.is_on_floor(), "aboard an open car")
	train.running = true
	mm.phase = MatchManager.Phase.PLAYING
	await wait_physics(30)
	# a carrot fired sideways off the moving car keeps the car's speed
	var along := -car.global_basis.z
	me.give_weapon(WeaponInstance.new(WeaponDB.get_weapon(&"carrot_rifle")))
	await wait_physics(30)
	var side := along.cross(Vector3.UP).normalized()
	# (aimed down the sights, far off to the side: hip-fire spread, or a near
	# aim point left behind as the car moves on, would tip a 480 m/s carrot
	# back along the track by more than the train's speed)
	me.want_aim = true
	me.aim_point = me.get_eye_position() + side * 2000.0
	me.look_yaw = atan2(-side.x, -side.z)
	var before := Projectiles.instance._shots.size()
	me.want_fire = true
	await wait_physics(2)
	me.want_fire = false
	me.want_aim = false
	check(Projectiles.instance._shots.size() > before, "fired a carrot from the train")
	if Projectiles.instance._shots.size() > before:
		var v: Vector3 = Projectiles.instance._shots[Projectiles.instance._shots.size() - 1].vel
		# (fired sideways: without the train's speed it would move ~0 m/s along the track)
		check(v.dot(along) > ToyTrain.SPEED * 0.7, "it keeps the train's speed (%.1f m/s along the track)" % v.dot(along))
	# the rewind takes the train back as well, rider and all
	var tk := mm.time_keeper
	await wait_physics(90)
	check(tk.rewind(false), "rewound")
	await wait_physics(30)
	var aboard := me.global_position.distance_to(car.global_position)
	check(aboard < 7.0 and me.global_position.y > ToyFloor.FLOOR + ToyTrain.DECK - 0.5, "still aboard the same car after the rewind (%.1f m from its middle)" % aboard)
	# and the final-shot replay has the riders riding the same cars as they did
	var kc := mm.kill_cam
	await wait_physics(120)
	check(KillCam.recording, "the KillCam is recording the last two")
	var tape: Array = kc._nodes.filter(func(n): return n.node == car)
	check(tape.size() == 1, "the car is on the tape once (%d)" % tape.size())
	if KillCam.recording and tape.size() == 1:
		var worst := 0.0
		for i in 8:
			var t: float = kc.clock - 2.0 + i * 0.25
			var f: Array = kc._poses[me].sample(t)
			if f.is_empty():
				continue
			var xf := KillCam._xf_at(tape[0].frames, t)
			worst = maxf(worst, (f[0] as Transform3D).origin.distance_to(xf.origin))
		check(worst < 7.0, "on the tape, Bun stays aboard the car (up to %.1f m from its middle)" % worst)
		# ...and in the replay itself (the world paused), the car is where the tape says
		kc._freeze_scene(true)
		get_tree().paused = true
		var t_r: float = kc.clock - 1.5
		var off := 0.0
		for i in 6:
			kc._show(t_r)
			await get_tree().process_frame
			off = maxf(off, car.global_position.distance_to(KillCam._xf_at(tape[0].frames, t_r).origin))
			t_r += 0.1
		check(off < 0.5, "the replay puts the car where it was (off by up to %.1f m)" % off)
		kc._show(INF)
		kc._freeze_scene(false)
		get_tree().paused = false
		await wait_physics(30)
		var after := me.global_position.distance_to(car.global_position)
		check(after < 7.0 and car.sync_to_physics, "after the replay, the train runs on with Bun aboard (%.1f m)" % after)


## A real match waits on the critter picker before anyone boards. The bots
## mustn't come to harm meanwhile: the Toy Box floor is 4 m up, and bots left
## standing at the origin fell out of the world while you picked, so the
## match was over (1 critter left) before you dropped in.
func test_bots_wait_safely_while_you_pick() -> void:
	await _make_toybox(false)
	add_child(FX.new())
	add_child(Projectiles.new())
	PlayerProfile.reset_for_tests()
	RivalBook.reset_for_tests()
	var mm := MatchManager.new()
	add_child(mm)
	mm.setup(self, toy, 6, 1, 4242)
	var ended := []
	mm.finished.connect(func(_w, p): ended.append(p))
	await wait_physics(240)
	var alive := mm.alive_critters().size()
	check(alive == 6, "every bot is still there after four seconds on the picker (%d of 6)" % alive)
	check(ended.is_empty() and mm.phase != MatchManager.Phase.ENDED, "and the match hasn't ended without you")
	mm.spawn_player(load(BUN), "default")
	mm.begin_drop()
	await wait_physics(2)
	check(mm.dropship.passengers.size() == 7, "all seven board the drop vehicle (%d)" % mm.dropship.passengers.size())


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
