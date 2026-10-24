extends TestCase
## The Hamster Cage map: every landmark inside the glass and in its biome,
## water bowls you swim in, glass you can't get through, a toy plane that
## stays under the rim, and a navmesh that reaches into the huts, the pods,
## the castle, the ice cream tub and up onto the shelf.

const BUN := "res://data/critters/bun.tres"
const MapCheck := preload("res://tests/map_check.gd")

var cage: HamsterCage


func _make_cage(nav := true) -> void:
	cage = HamsterCage.new()
	add_child(cage)
	var t0 := Time.get_ticks_msec()
	await cage.generate(777, 1, nav)
	print("    cage generated in %d ms" % (Time.get_ticks_msec() - t0))


func test_cage_layout_and_paths() -> void:
	await _make_cage()
	var cf := cage.terrain as CageFloor
	check(cage.ready_to_play, "generation finished")
	check(cage.pois.size() == HamsterCage.CAGE_POIS.size(), "every landmark placed (%d)" % cage.pois.size())
	for p in cage.pois:
		check(cf.inside(p.center.x, p.center.y, p.radius * 0.5), "%s is inside the glass" % p.name)
		var w := cf.biome_at(p.center.x, p.center.y)
		var share: float = [w.x, w.y, w.z][int(p.biome)]
		check(share > 0.4, "%s is in its biome (%.2f)" % [p.name, share])
	check(cage.bowls.size() == 5, "a cluster of water bowls in the lagoon (%d)" % cage.bowls.size())
	check(cage.buildings.size() >= 9, "walk-in pods, huts, castle, tub and shelf (%d)" % cage.buildings.size())
	check(cage.loot_points.size() > 250, "plenty of loot (%d)" % cage.loot_points.size())
	var stray := cage.loot_points.filter(func(l): return not cf.inside(l.pos.x, l.pos.z, 2.0))
	check(stray.is_empty(), "no loot outside the tank (%d)" % stray.size())
	check(cage.get_node_or_null("TankGlass") != null and cage.get_node_or_null("Fridge") != null, "the glass tank and the open fridge are there")
	var food := cage.get_node_or_null("FridgeFood")
	check(food != null and food.get_child_count() >= 30, "the fridge is stocked (%d foods)" % (food.get_child_count() if food else 0))
	# from the big wheel, a bot can walk into every walk-in landmark
	var map := get_world_3d().navigation_map
	var wheel: Dictionary = cage.pois.filter(func(p): return p.kit == "wheel")[0]
	var from := NavigationServer3D.map_get_closest_point(map, Vector3(wheel.center.x, wheel.height, wheel.center.y) + Vector3(0, 0, 26))
	for b in cage.buildings:
		var spots := b.world_loot_spots()
		if spots.is_empty():
			continue
		var target: Vector3 = spots[0]
		var to := NavigationServer3D.map_get_closest_point(map, target)
		check(to.distance_to(target) < 2.0, "%s: the navmesh covers its floor (%.1f m off)" % [b.name, to.distance_to(target)])
		var path := Island.find_path(map, from, to)
		check(path.size() >= 2 and path[path.size() - 1].distance_to(to) < 3.0, "%s: a bot can walk in from the wheel" % b.name)
	# the toy plane flies wall to wall, under the rim of the glass
	var ship := Dropship.new()
	add_child(ship)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	ship.setup(cf.island_radius, rng, cage.drop_vehicle, cage.play_bounds())
	check(ship.vehicle == &"plane" and ship.get_node_or_null("ToyPlane") != null, "everyone rides in on the toy plane")
	for end in [ship.start, ship.finish]:
		check(cf.inside(end.x, end.z, 10.0) and end.y < CageRoom.GLASS_TOP, "the route stays inside the tank (%s)" % end)
	check(ship.start.distance_to(ship.finish) > 600.0, "and crosses most of it")
	check(ship.view_distance() > 40.0, "the ride camera frames the whole plane (%.0f m back)" % ship.view_distance())
	ship.queue_free()
	await _check_tidy(cage)


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


func test_glass_walls_and_water_bowls() -> void:
	await _make_cage(false)
	add_child(FX.new())
	add_child(Projectiles.new())
	var cf := cage.terrain as CageFloor
	# the glass: run at the east wall for a few seconds
	var z := 120.0
	var x := CageFloor.HX - 30.0
	var bun := spawn_critter(BUN, Vector3(x, cf.height_at(x, z) + 1.0, z), -PI / 2.0)
	await wait_physics(10)
	bun.look_yaw = -PI / 2.0
	bun.move_input = Vector2(0, 1)
	bun.want_sprint = true
	await wait_physics(240)
	check(bun.global_position.x > CageFloor.HX - 8.0, "ran right up to the glass (x %.1f)" % bun.global_position.x)
	check(bun.global_position.x < CageFloor.HX, "and the glass held")
	bun.queue_free()
	await wait_physics(2)
	# a water bowl: drop in the middle and swim
	var b: Dictionary = cage.bowls[0]
	check(b.level > CageFloor.LAGOON_LEVEL, "bowls are brimming above the lagoon")
	var swimmer := spawn_critter(BUN, Vector3(b.center.x, b.level - 1.0, b.center.y))
	await wait_physics(90)
	check(is_equal_approx(cage.water_level_at(swimmer.global_position), b.level), "the bowl's water level")
	check(swimmer.swimming, "swimming in the bowl")
	check(swimmer.global_position.y > b.base, "floating, not sunk through the bowl")
