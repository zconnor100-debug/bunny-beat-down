extends TestCase
## Island generation: deterministic from a seed, POIs on land, loot spots on
## the ground, and a navigation mesh the AI can path across.

var _island: Island


func test_island_generates_and_navigates() -> void:
	_island = Island.new()
	add_child(_island)
	var t0 := Time.get_ticks_msec()
	await _island.generate(1234, 1, true)
	var ms := Time.get_ticks_msec() - t0
	print("    island generated in %d ms" % ms)
	check(_island.ready_to_play, "generation finished")
	check(_island.pois.size() >= 6, "placed most POIs (%d)" % _island.pois.size())
	for p in _island.pois:
		check(_island.terrain.height_at(p.center.x, p.center.y) > 1.0, "%s is on land" % p.name)
	check(_island.loot_points.size() > 60, "plenty of loot spots (%d)" % _island.loot_points.size())
	# a path between two far-apart POIs should exist and be walkable
	var a: Vector2 = _island.pois[0].center
	var b: Vector2 = _island.pois[_island.pois.size() - 1].center
	var map := get_world_3d().navigation_map
	var from := NavigationServer3D.map_get_closest_point(map, Vector3(a.x, _island.terrain.height_at(a.x, a.y), a.y))
	var to := NavigationServer3D.map_get_closest_point(map, Vector3(b.x, _island.terrain.height_at(b.x, b.y), b.y))
	var path := NavigationServer3D.map_get_path(map, from, to, true)
	check(path.size() >= 2, "navmesh path between POIs (%d points)" % path.size())
	if path.size() >= 2:
		check(path[path.size() - 1].distance_to(to) < 3.0, "path reaches the destination (%.1f m short)" % path[path.size() - 1].distance_to(to))


func test_island_is_deterministic() -> void:
	var t1 := Terrain.new()
	t1.setup(77)
	t1.generate_heights()
	var t2 := Terrain.new()
	t2.setup(77)
	t2.generate_heights()
	check(t1.heights == t2.heights, "same seed → same terrain")
	t1.free()
	t2.free()
