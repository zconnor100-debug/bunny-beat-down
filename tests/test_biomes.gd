extends TestCase
## The big island: twice as wide as before, three biomes (forest, grassland,
## swamp) in roughly equal shares, big walk-in buildings in each biome with
## their loot inside and reachable, and swamp water you wade through.

const BUN := "res://data/critters/bun.tres"

var island: Island


func _make_island() -> void:
	island = Island.new()
	add_child(island)
	await island.generate(4321, 1, true)


func test_three_biomes_on_a_bigger_island() -> void:
	await _make_island()
	check(island.terrain.island_radius >= 650.0, "the island is twice as wide (radius %.0f m, was 330)" % island.terrain.island_radius)
	var counts := [0, 0, 0]
	var land := 0
	var step := 24.0
	var r := island.terrain.island_radius
	var x := -r
	while x <= r:
		var z := -r
		while z <= r:
			if island.terrain.height_at(x, z) > 1.0:
				land += 1
				counts[island.terrain.biome_id(x, z)] += 1
			z += step
		x += step
	for b in 3:
		var share := float(counts[b]) / land
		check(share > 0.18 and share < 0.5, "%s covers a fair share of the land (%.0f%%)" % [["forest", "swamp", "grassland"][b], share * 100.0])
	# more topography: real hills and valleys, not a pancake
	var hs := []
	for p in island.pois:
		hs.append(island.terrain.height_at(p.center.x, p.center.y))
	var highest := 0.0
	x = -r
	while x <= r:
		var z := -r
		while z <= r:
			highest = maxf(highest, island.terrain.height_at(x, z))
			z += 8.0
		x += 8.0
	check(highest > 35.0, "there are proper hills (highest %.0f m)" % highest)
	# every biome has its landmarks, and the big buildings are in theirs
	for p in island.pois:
		if p.biome >= 0:
			var w := island.terrain.biome_at(p.center.x, p.center.y)
			check([w.x, w.y, w.z][p.biome] > 0.5, "%s sits in its biome" % p.name)
	var styles := {}
	for b in island.buildings:
		styles[b.style] = styles.get(b.style, 0) + 1
	for s in [Building.Style.LODGE, Building.Style.BARN, Building.Style.SHACK]:
		check(styles.get(s, 0) >= 2, "two or more of every building (%s: %d)" % [Building.Style.keys()[s], styles.get(s, 0)])

	# buildings: loot inside, and the navmesh reaches it from outside the door
	var map := get_world_3d().navigation_map
	for b in island.buildings:
		var spots := b.world_loot_spots()
		var inside := island.loot_points.filter(func(l): return l.get("inside", false) and (l.pos as Vector3).distance_to(b.global_position) < b.footprint)
		check(inside.size() >= spots.size(), "%s has its loot inside (%d spots)" % [b.name, inside.size()])
		var door := b.global_transform * Vector3(0, 0, b.footprint + 6.0)
		var from := NavigationServer3D.map_get_closest_point(map, door)
		for spot in spots:
			var to := NavigationServer3D.map_get_closest_point(map, spot)
			var path := Island.find_path(map, from, to)
			var reached := path.size() >= 2 and path[path.size() - 1].distance_to(spot) < 2.0 and to.distance_to(spot) < 1.0
			check(reached, "%s: a bot can walk in to the loot at %s" % [b.name, spot])

	# swamp water: standing water at SWAMP_LEVEL, and no loot sunk under it
	var wet := 0
	for i in 400:
		var p := island.random_land_point(1.0)
		if island.water_level_at(p) > p.y + 0.05:
			wet += 1
			if island.terrain.biome_at(p.x, p.z).y > 0.25:
				check_near(island.water_level_at(p), Terrain.SWAMP_LEVEL, 0.01, "swamp water stands at the swamp level")
	check(wet > 10, "there is standing water in the swamp (%d of 400 random spots)" % wet)
	for l in island.loot_points:
		if not l.get("inside", false):
			check(island.water_level_at(l.pos) < (l.pos as Vector3).y + 0.25, "loot at %s is not under water" % l.pos)


func test_walk_into_a_barn_and_wade_in_the_swamp() -> void:
	await _make_island()
	add_child(FX.new())
	add_child(Projectiles.new())
	var barn: Building = null
	for b in island.buildings:
		if b.style == Building.Style.BARN:
			barn = b
	if not check(barn != null, "there is a barn"):
		return
	# start in front of the big doors, facing in, and walk
	var front := barn.global_transform.basis.z.normalized()
	var start := barn.global_position + front * (barn.footprint + 3.0)
	var bun := spawn_critter(BUN, start + Vector3.UP * 0.5, atan2(-(-front).x, -(-front).z))
	await wait_physics(10)
	bun.look_yaw = atan2(front.x, front.z)
	bun.move_input = Vector2(0, 1)
	await wait_physics(240)
	var local := barn.global_transform.affine_inverse() * bun.global_position
	check(absf(local.x) < 7.0 and absf(local.z) < 10.0, "walked in through the barn doors (at %s in the barn)" % local)
	check(bun.global_position.y > barn.global_position.y - 0.2, "standing on the floor, not under it")
	bun.queue_free()
	await wait_physics(2)
	# wading: find a spot in the swamp water and walk through it
	var wet := Vector3.INF
	for i in 2000:
		var p := island.random_land_point(1.0)
		var depth := island.water_level_at(p) - p.y
		if depth > 0.5 and depth < 1.0 and island.terrain.normal_at(p.x, p.z).y > 0.97:
			wet = p
			break
	if not check(wet != Vector3.INF, "found knee-deep swamp water"):
		return
	var frog := spawn_critter(BUN, wet + Vector3.UP * 0.3)
	await wait_physics(10)
	frog.move_input = Vector2(0, 1)
	await wait_physics(40)
	var speed := Vector2(frog.velocity.x, frog.velocity.z).length()
	check(not frog.swimming, "knee-deep: wading, not swimming")
	check(speed < frog.def.move_speed * 0.97 and speed > frog.def.move_speed * 0.5, "wading slows you down (%.1f of %.1f m/s)" % [speed, frog.def.move_speed])
