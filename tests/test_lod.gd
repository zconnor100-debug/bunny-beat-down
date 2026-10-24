extends TestCase
## Levels of detail (tests/perf_bench.gd measures what they save): terrain
## chunks get coarser grids picked by their real height error, with skirts so
## neighbours never crack; buildings hand over to their code-built look far
## off; ground cover keeps its models' LODs and casts shadows near you only.


## The error each coarser terrain grid claims must bound how far it really
## strays from the full grid (checked the slow way on the roughest chunks).
func test_terrain_lod_errors_bound_the_real_error() -> void:
	var t := _terrain(Terrain)
	var n := (Terrain.RES - 1) / Terrain.CHUNKS
	var chunks := []
	for cz in Terrain.CHUNKS:
		for cx in Terrain.CHUNKS:
			chunks.append([t._lod_errors(cx * n, cz * n, n), cx, cz])
	chunks.sort_custom(func(a, b): return a[0][0] > b[0][0])
	for c in chunks.slice(0, 4) + [chunks[chunks.size() / 2]]:
		var errors: PackedFloat32Array = c[0]
		check(errors.size() == 6, "six coarser grids per chunk (%d)" % errors.size())
		var s := 2
		for err in errors:
			var real := _real_error(t, c[1] * n, c[2] * n, n, s)
			check(real <= err + 0.0001, "chunk %d,%d step %d: real error %.3f m within the claimed %.3f m" % [c[1], c[2], s, real, err])
			s *= 2
	t.free()


## Every chunk mesh carries its LODs (up to MAX_LOD_ERROR); a flat chunk (the
## Toy Box floor) gets down to two triangles plus its skirts; skirts face out
## of their chunk and stay shallow.
func test_terrain_chunks_have_lods_and_outward_skirts() -> void:
	var t := _terrain(ToyFloor)
	t.build_meshes(ShaderMaterial.new())
	var flat := 0
	var with_lods := 0   # (a chunk with a step taller than MAX_LOD_ERROR has none)
	for mi in t.get_children():
		if not mi is MeshInstance3D:
			continue
		var mesh := (mi as MeshInstance3D).mesh
		var surface: Dictionary = (mesh.get("_surfaces") as Array)[0]
		var lods: Array = surface.get("lods", [])
		check(lods.size() <= 12, "%s has at most six LODs (%d)" % [mi.name, lods.size() / 2])
		if not lods.is_empty():
			with_lods += 1
		for k in range(0, lods.size(), 2):
			check(float(lods[k]) <= Terrain.MAX_LOD_ERROR + 0.01, "%s LOD %d error %.2f m within the cap" % [mi.name, k / 2, float(lods[k])])
		var depth := mesh.get_aabb().size.y - _relief(mesh)
		check(depth <= Terrain.MAX_LOD_ERROR * 2.0 + Terrain.SKIRT_MARGIN + 0.01, "%s skirts hang %.1f m at most" % [mi.name, depth])
		if lods.size() == 12 and float(lods[10]) < 0.001:
			flat += 1
			var coarsest := (lods[11] as PackedByteArray).size() / 4 / 3
			check(coarsest <= 2 + 4 * 2, "flat %s draws %d triangles far off" % [mi.name, coarsest])
	check(flat > 50, "most of the toy floor is flat and collapses (%d chunks)" % flat)
	check(with_lods > 240, "nearly every chunk has LODs (%d of 256)" % with_lods)
	# skirts: every LOD-0 triangle off the ground plane faces away from the chunk
	var mi: MeshInstance3D = t.get_node("TerrainChunk_5_5")
	var arrays := mi.mesh.surface_get_arrays(0)
	var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var centre := mi.mesh.get_aabb().get_center()
	var skirts := 0
	for k in range(0, idx.size(), 3):
		var a := v[idx[k]]
		var nrm := (v[idx[k + 2]] - a).cross(v[idx[k + 1]] - a)   # (front faces are clockwise)
		if absf(nrm.normalized().y) > 0.01:
			continue
		skirts += 1
		var out := Vector3(a.x - centre.x, 0.0, a.z - centre.z)
		check(nrm.dot(out) > 0.0, "skirt triangle at %s faces out" % a)
	check(skirts == 4 * 64 * 2, "skirts on all four inner sides (%d triangles)" % skirts)
	check(t.chunk_arrays[0][1].size() == 64 * 64 * 6, "the navmesh gets the plain grid, no skirts")
	t.free()


## A building's model is its near look; far off, the code-built building it
## was made from takes over.
func test_buildings_hand_over_to_their_code_built_look_far_off() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var b := Building.make(Building.Style.BARN, rng)
	add_child(b)
	var model := b.get_node_or_null("Model")
	var far := b.get_node_or_null("Mesh") as MeshInstance3D
	check(model != null and far != null, "barn has its model and its code-built mesh")
	if model and far:
		for gi in model.find_children("*", "GeometryInstance3D", true, false):
			check(is_equal_approx((gi as GeometryInstance3D).visibility_range_end, Building.FAR_LOD), "model shows up to FAR_LOD")
		check(is_equal_approx(far.visibility_range_begin, Building.FAR_LOD) and far.visibility_range_end == 0.0, "code-built barn from FAR_LOD on")
		check(far.mesh.get_faces().size() / 3 < 2000, "far barn is light (%d triangles)" % (far.mesh.get_faces().size() / 3))


## Ferns keep their LODs in the batches, and their shadows stop near you.
func test_cover_keeps_lods_and_casts_shadows_near_you_only() -> void:
	var s := Scatter.new()
	add_child(s)
	s.load_manifest()
	var fern := s.get_entry("fern_a")
	check(not fern.is_empty(), "fern in the manifest")
	if fern.is_empty():
		return
	for i in 20:
		s.place(fern, Vector3(i * 2.0, 0.0, 0.0), 0.0, 1.0)
	s.flush_batches(2)
	var seen := []
	var shadows := []
	for c in s.get_children():
		if c is MultiMeshInstance3D:
			(shadows if (c as MultiMeshInstance3D).cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY else seen).append(c)
	check(seen.size() == 1 and shadows.size() == 1, "one batch and its shadow twin (%d, %d)" % [seen.size(), shadows.size()])
	if seen.size() == 1 and shadows.size() == 1:
		var mmi: MultiMeshInstance3D = seen[0]
		var twin: MultiMeshInstance3D = shadows[0]
		check(mmi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "the ferns themselves cast none")
		check(twin.multimesh == mmi.multimesh, "the twin draws the same ferns")
		check(twin.visibility_range_end < mmi.visibility_range_end, "shadows stop nearer than the ferns (%.0f < %.0f m)" % [twin.visibility_range_end, mmi.visibility_range_end])
		var surface: Dictionary = (mmi.multimesh.mesh.get("_surfaces") as Array)[0]
		check(not (surface.get("lods", []) as Array).is_empty(), "the batch's fern mesh kept its LODs")
	var low := Scatter.new()
	add_child(low)
	low.load_manifest()
	low.place(fern, Vector3.ZERO, 0.0, 1.0)
	low.flush_batches(1)
	check(low.get_children().filter(func(c): return c is MultiMeshInstance3D).size() == 1, "no shadow twin below High quality")


## Height range of a chunk's own grid (its skirts left out).
func _relief(mesh: Mesh) -> float:
	var v: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var lo := INF
	var hi := -INF
	for i in 65 * 65:
		lo = minf(lo, v[i].y)
		hi = maxf(hi, v[i].y)
	return hi - lo


func _terrain(cls) -> Terrain:
	var t: Terrain = cls.new()
	t.setup(1234)
	t.generate_heights()
	t.compute_normals()
	return t


## How far the step-s grid of a chunk strays from the full one, measured at
## every full-grid vertex against the coarse triangle above or below it.
func _real_error(t: Terrain, x0: int, z0: int, n: int, s: int) -> float:
	var h := t.heights
	var R := Terrain.RES
	var worst := 0.0
	for zi in n + 1:
		var cz := mini(zi / s, n / s - 1)
		var v := float(zi - cz * s) / s
		for xi in n + 1:
			var cx := mini(xi / s, n / s - 1)
			var u := float(xi - cx * s) / s
			var a := (z0 + cz * s) * R + x0 + cx * s
			var ha := h[a]
			var hb := h[a + s]
			var hc := h[a + s * R]
			var hd := h[a + s * R + s]
			var est := ha + u * (hb - ha) + v * (hc - ha) if u + v <= 1.0 else hd + (1.0 - u) * (hc - hd) + (1.0 - v) * (hb - hd)
			worst = maxf(worst, absf(h[(z0 + zi) * R + x0 + xi] - est))
	return worst
