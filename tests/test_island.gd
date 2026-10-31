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
	var path := Island.find_path(map, from, to)
	check(path.size() >= 2, "navmesh path between POIs (%d points)" % path.size())
	if path.size() >= 2:
		check(path[path.size() - 1].distance_to(to) < 3.0, "path reaches the destination (%.1f m short)" % path[path.size() - 1].distance_to(to))


## Every solid model's convex collision is baked (assets/env/hulls.json: rerun
## tools/env/bake_hulls.gd when this fails), from the model as it is now, and
## the scatter uses it instead of decomposing the mesh as the island loads.
func test_convex_collision_is_baked() -> void:
	var sc := Scatter.new()
	add_child(sc)
	sc.load_manifest()
	var hulls: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Scatter.HULLS))
	var convex := sc.entries.filter(func(e): return e.get("collision", "none") == "convex")
	check(not convex.is_empty(), "there are convex models (%d)" % convex.size())
	for e in convex:
		var id: String = e["id"]
		var mesh := sc._merged_mesh(e["res"])
		check(hulls.has(id), "%s's hull is baked" % id)
		if not hulls.has(id) or mesh == null:
			continue
		check(int(hulls[id].faces) == mesh.get_faces().size(), "%s's hull is from its model as it is now (%d faces baked, %d now)" % [id,
			int(hulls[id].faces), mesh.get_faces().size()])
		var shape := sc._shape_for(e, "convex") as ConvexPolygonShape3D
		check(shape != null and shape.points == Scatter.baked_hull(id) and shape.points.size() <= 64,
			"%s collides as its baked hull (%d points)" % [id, shape.points.size() if shape else -1])
	sc.queue_free()


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
