class_name Terrain
extends Node3D
## Heightfield island: generates heights + a splat control map from a seed,
## then builds chunked render meshes (for culling) and a single
## HeightMapShape3D for physics. Also answers height/normal/biome queries.
##
## The island has three biomes, each a wedge of the island with ragged,
## noise-warped borders: a hilly FOREST with ridges and valleys, open
## GRASSLANDS of rolling meadow and flat-topped mesas, and a low SWAMP whose
## floor sits around SWAMP_LEVEL (still water, knee deep) behind a little levee.

enum Biome { FOREST, SWAMP, GRASS }

const SIZE := 1536.0           ## metres covered by the heightfield
const CELL := 1.5              ## metres between height samples
const RES := 1025              ## samples per side (SIZE / CELL + 1)
const CHUNKS := 16             ## render chunks per side (96 m each)
const WATER_LEVEL := 0.0
const SEA_FLOOR := -7.0
const SWAMP_LEVEL := 2.6       ## the swamp's still water (above the sea)
const BIOME_CELL := 6.0        ## metres per biome-map texel
const BIOME_RES := 257

var island_radius := 660.0
## Area relative to the original 215 m island; content counts scale with it.
var area_scale: float:
	get:
		return pow(island_radius / 215.0, 2.0)
var heights := PackedFloat32Array()
var normals := PackedVector3Array()
var control: Image             ## R grass, G dirt path, B rock, A moss
var biome: Image               ## R swamp, G grassland, B forest (weights, sum 1)
var rng := RandomNumberGenerator.new()

var _n_base := FastNoiseLite.new()
var _n_detail := FastNoiseLite.new()
var _n_coast := FastNoiseLite.new()
var _n_patch := FastNoiseLite.new()
var _n_ridge := FastNoiseLite.new()
var _n_mesa := FastNoiseLite.new()
var _n_warp := FastNoiseLite.new()
var _n_bog := FastNoiseLite.new()
var _biome_w := PackedFloat32Array()   # BIOME_RES² × (forest, swamp, grass)
var _sector := 0.0                      # where the swamp wedge points (radians)
var _material: ShaderMaterial
## [vertices, indices] of every render chunk (world space), kept for baking
## the navigation mesh (its parser can't read a scaled heightmap collider).
var chunk_arrays: Array = []


func setup(seed_: int) -> void:
	rng.seed = seed_
	for n in [_n_base, _n_detail, _n_coast, _n_patch, _n_ridge, _n_mesa, _n_warp, _n_bog]:
		n.seed = rng.randi()
		n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_n_base.frequency = 0.003
	_n_base.fractal_type = FastNoiseLite.FRACTAL_FBM
	_n_base.fractal_octaves = 5
	_n_detail.frequency = 0.03
	_n_detail.fractal_octaves = 2
	_n_coast.frequency = 0.0045
	_n_coast.fractal_octaves = 3
	_n_patch.frequency = 0.02
	_n_patch.fractal_octaves = 3
	_n_ridge.frequency = 0.0042
	_n_ridge.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_n_ridge.fractal_octaves = 3
	_n_mesa.frequency = 0.007
	_n_mesa.fractal_octaves = 2
	_n_warp.frequency = 0.0035
	_n_warp.fractal_octaves = 2
	_n_bog.frequency = 0.018
	_n_bog.fractal_octaves = 3
	_sector = rng.randf() * TAU


# ---- biomes -----------------------------------------------------------------------------------

## Biome weights at a point: x forest, y swamp, z grassland (they sum to 1).
func biome_at(x: float, z: float) -> Vector3:
	if _biome_w.is_empty():
		return _biome_raw(x, z)
	var fx := clampf((x + SIZE * 0.5) / BIOME_CELL, 0.0, BIOME_RES - 1.001)
	var fz := clampf((z + SIZE * 0.5) / BIOME_CELL, 0.0, BIOME_RES - 1.001)
	var xi := int(fx)
	var zi := int(fz)
	var tx := fx - xi
	var tz := fz - zi
	var a := _bw(xi, zi).lerp(_bw(xi + 1, zi), tx)
	var b := _bw(xi, zi + 1).lerp(_bw(xi + 1, zi + 1), tx)
	return a.lerp(b, tz)


## The biome with the most weight at a point.
func biome_id(x: float, z: float) -> Biome:
	var w := biome_at(x, z)
	if w.y >= w.x and w.y >= w.z:
		return Biome.SWAMP
	return Biome.GRASS if w.z > w.x else Biome.FOREST


func _bw(xi: int, zi: int) -> Vector3:
	var i := (zi * BIOME_RES + xi) * 3
	return Vector3(_biome_w[i], _biome_w[i + 1], _biome_w[i + 2])


## Three wedges (swamp, then grassland and forest a third of a turn on), their
## borders warped by noise; the swamp stays off the coast and the very middle
## of the island is woods.
func _biome_raw(x: float, z: float) -> Vector3:
	var d := sqrt(x * x + z * z) / island_radius
	var a := atan2(z, x) + _n_warp.get_noise_2d(x, z) * 1.1
	var k := 5.5
	var ws := exp(k * cos(a - _sector))
	var wg := exp(k * cos(a - _sector - TAU / 3.0))
	var wf := exp(k * cos(a - _sector - TAU * 2.0 / 3.0))
	ws *= smoothstep(0.8, 0.62, d) * smoothstep(0.08, 0.22, d)
	wf += (ws + wg + wf) * smoothstep(0.2, 0.05, d) * 2.0
	var sum := ws + wg + wf
	return Vector3(wf, ws, wg) / sum


func _build_biomes() -> void:
	_biome_w.resize(BIOME_RES * BIOME_RES * 3)
	biome = Image.create_empty(BIOME_RES, BIOME_RES, false, Image.FORMAT_RGB8)
	for zi in BIOME_RES:
		for xi in BIOME_RES:
			var w := _biome_raw(xi * BIOME_CELL - SIZE * 0.5, zi * BIOME_CELL - SIZE * 0.5)
			var i := (zi * BIOME_RES + xi) * 3
			_biome_w[i] = w.x
			_biome_w[i + 1] = w.y
			_biome_w[i + 2] = w.z
			biome.set_pixel(xi, zi, Color(w.y, w.z, w.x))


# ---- heights ----------------------------------------------------------------------------------

## Raw island shape before POIs are flattened in.
func generate_heights() -> void:
	_build_biomes()
	heights.resize(RES * RES)
	var half := SIZE * 0.5
	for zi in RES:
		var z := zi * CELL - half
		for xi in RES:
			var x := xi * CELL - half
			var d := sqrt(x * x + z * z) / island_radius
			var coast := d + _n_coast.get_noise_2d(x, z) * 0.12
			var land := smoothstep(1.02, 0.8, coast)
			var w := biome_at(x, z)
			var base := pow(_n_base.get_noise_2d(x, z) * 0.5 + 0.5, 1.35) * 24.0
			base *= lerpf(0.45, 1.0, clampf(1.0 - d, 0.0, 1.0))
			var detail := _n_detail.get_noise_2d(x, z) * 0.9
			var h := 0.0
			if w.x > 0.01:
				# forest: big hills cut by ridgelines and valleys
				var ridge := pow(clampf(_n_ridge.get_noise_2d(x, z) * 0.5 + 0.5, 0.0, 1.0), 2.2)
				h += w.x * (base * 1.1 + ridge * 34.0 * smoothstep(0.95, 0.6, d))
			if w.z > 0.01:
				# grassland: gentle rolls and flat-topped mesas with steep sides
				var mesa := smoothstep(0.28, 0.4, _n_mesa.get_noise_2d(x, z)) * 13.0 * smoothstep(0.9, 0.6, d)
				h += w.z * (base * 0.5 + mesa)
			if w.y > 0.01:
				# swamp: hummocks and channels around the water line
				var bog := _n_bog.get_noise_2d(x, z)
				h += w.y * (SWAMP_LEVEL - 1.4 + bog * 1.5 - 0.25)
			# the swamp's rim always rises above its water, so the pools can't spill
			var rim := smoothstep(0.04, 0.22, w.y) * (1.0 - smoothstep(0.42, 0.6, w.y))
			h = maxf(h, lerpf(h, SWAMP_LEVEL - 1.4 + 0.7, rim))
			heights[zi * RES + xi] = lerpf(SEA_FLOOR, 1.4 + h + detail * (1.0 - w.y * 0.7), land)


## Blend the ground towards `target` inside a circle (for clearings, POIs),
## with a little natural unevenness unless `bumpy` is off.
func flatten(center: Vector2, radius: float, target: float, strength := 1.0, bumpy := true) -> void:
	var half := SIZE * 0.5
	var r_out := radius * 1.45
	var x0 := maxi(0, int((center.x + half - r_out) / CELL))
	var x1 := mini(RES - 1, int((center.x + half + r_out) / CELL) + 1)
	var z0 := maxi(0, int((center.y + half - r_out) / CELL))
	var z1 := mini(RES - 1, int((center.y + half + r_out) / CELL) + 1)
	for zi in range(z0, z1 + 1):
		for xi in range(x0, x1 + 1):
			var p := Vector2(xi * CELL - half, zi * CELL - half)
			var w := smoothstep(r_out, radius * 0.75, p.distance_to(center)) * strength
			if w > 0.0:
				var i := zi * RES + xi
				heights[i] = lerpf(heights[i], target + (_n_detail.get_noise_2d(p.x, p.y) * 0.3 if bumpy else 0.0), w)


## Smooth surface normals at every sample (central differences); call after
## the last change to the heights.
func compute_normals() -> void:
	normals.resize(RES * RES)
	for zi in RES:
		var zm := maxi(zi - 1, 0) * RES
		var zp := mini(zi + 1, RES - 1) * RES
		var row := zi * RES
		for xi in RES:
			var xm := maxi(xi - 1, 0)
			var xp := mini(xi + 1, RES - 1)
			normals[row + xi] = Vector3(heights[row + xm] - heights[row + xp], 2.0 * CELL,
				heights[zm + xi] - heights[zp + xi]).normalized()


## Splat weights. `paths` is an array of PackedVector2Array polylines.
func build_control(paths: Array) -> void:
	if normals.size() != RES * RES:
		compute_normals()
	control = Image.create_empty(RES, RES, false, Image.FORMAT_RGBA8)
	var half := SIZE * 0.5
	var path_mask := PackedFloat32Array()
	path_mask.resize(RES * RES)
	for poly in paths:
		_stamp_path(poly, path_mask, 2.6)
	var data := PackedByteArray()
	data.resize(RES * RES * 4)
	for zi in RES:
		for xi in RES:
			var i := zi * RES + xi
			var x := xi * CELL - half
			var z := zi * CELL - half
			var slope := 1.0 - normals[i].y
			var h := heights[i]
			var w := biome_at(x, z)
			var patch := _n_patch.get_noise_2d(x, z)
			var rock := smoothstep(0.22, 0.4, slope)
			# grassland is mostly grass, the forest floor mostly leaves and moss
			var grass := smoothstep(-0.05 - w.z * 0.6, 0.35 - w.z * 0.3, patch) * (1.0 - rock) * smoothstep(1.2, 2.2, h)
			var moss := smoothstep(0.2 - w.y * 0.5, 0.55 - w.y * 0.3, -patch) * (1.0 - rock) * (0.8 - w.z * 0.5)
			var dirt := maxf(path_mask[i], smoothstep(0.12, 0.22, slope) * (1.0 - rock) * 0.6)
			data[i * 4] = int(clampf(grass * (1.0 - dirt) * (1.0 - w.y * 0.8), 0.0, 1.0) * 255.0)
			data[i * 4 + 1] = int(clampf(dirt, 0.0, 1.0) * 255.0)
			data[i * 4 + 2] = int(clampf(rock, 0.0, 1.0) * 255.0)
			data[i * 4 + 3] = int(clampf(moss * (1.0 - dirt), 0.0, 1.0) * 255.0)
	control.set_data(RES, RES, false, Image.FORMAT_RGBA8, data)


func _stamp_path(poly: PackedVector2Array, mask: PackedFloat32Array, width: float) -> void:
	var half := SIZE * 0.5
	var reach := int(ceil((width + 1.0) / CELL)) + 1
	for i in poly.size() - 1:
		var a := poly[i]
		var b := poly[i + 1]
		var steps := int(a.distance_to(b) / CELL)
		for s in steps + 1:
			var p := a.lerp(b, float(s) / maxf(steps, 1))
			var wobble := _n_patch.get_noise_2d(p.x * 3.0, p.y * 3.0) * 0.8
			var r := width + wobble
			var cx := int((p.x + half) / CELL)
			var cz := int((p.y + half) / CELL)
			for dz in range(-reach, reach + 1):
				for dx in range(-reach, reach + 1):
					var xi := cx + dx
					var zi := cz + dz
					if xi < 0 or zi < 0 or xi >= RES or zi >= RES:
						continue
					var d := Vector2(xi * CELL - half, zi * CELL - half).distance_to(p)
					var w := smoothstep(r, r * 0.4, d)
					var idx := zi * RES + xi
					mask[idx] = maxf(mask[idx], w)


# ---- queries --------------------------------------------------------------------------------

func height_at(x: float, z: float) -> float:
	var half := SIZE * 0.5
	var fx := clampf((x + half) / CELL, 0.0, RES - 1.001)
	var fz := clampf((z + half) / CELL, 0.0, RES - 1.001)
	var xi := int(fx)
	var zi := int(fz)
	var tx := fx - xi
	var tz := fz - zi
	var h00 := heights[zi * RES + xi]
	var h10 := heights[zi * RES + xi + 1]
	var h01 := heights[(zi + 1) * RES + xi]
	var h11 := heights[(zi + 1) * RES + xi + 1]
	return lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)


func normal_at(x: float, z: float) -> Vector3:
	var hl := height_at(x - CELL, z)
	var hr := height_at(x + CELL, z)
	var hd := height_at(x, z - CELL)
	var hu := height_at(x, z + CELL)
	return Vector3(hl - hr, 2.0 * CELL, hd - hu).normalized()


func is_land(x: float, z: float, min_height := 1.0) -> bool:
	return height_at(x, z) > min_height


func control_at(x: float, z: float) -> Color:
	var half := SIZE * 0.5
	var xi := clampi(int((x + half) / CELL), 0, RES - 1)
	var zi := clampi(int((z + half) / CELL), 0, RES - 1)
	return control.get_pixel(xi, zi)


# ---- building --------------------------------------------------------------------------------

func build_meshes(material: ShaderMaterial) -> void:
	_material = material
	if normals.size() != RES * RES:
		compute_normals()
	var cells_per := (RES - 1) / CHUNKS
	for cz in CHUNKS:
		for cx in CHUNKS:
			var mi := MeshInstance3D.new()
			mi.name = "TerrainChunk_%d_%d" % [cx, cz]
			mi.mesh = _chunk_mesh(cx * cells_per, cz * cells_per, cells_per)
			mi.material_override = material
			mi.set_meta(&"surface", &"dirt")
			add_child(mi)


func _chunk_mesh(x0: int, z0: int, n: int) -> ArrayMesh:
	var half := SIZE * 0.5
	var count := n + 1
	var verts := PackedVector3Array()
	var nrms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var tangents := PackedFloat32Array()
	var indices := PackedInt32Array()
	verts.resize(count * count)
	nrms.resize(count * count)
	uvs.resize(count * count)
	tangents.resize(count * count * 4)
	for zi in count:
		for xi in count:
			var gi := (z0 + zi) * RES + x0 + xi
			var x := (x0 + xi) * CELL - half
			var z := (z0 + zi) * CELL - half
			var i := zi * count + xi
			var nrm := normals[gi]
			verts[i] = Vector3(x, heights[gi], z)
			nrms[i] = nrm
			uvs[i] = Vector2(x, z)
			# tangents along +X so world-space-UV normal maps light correctly
			var t := (Vector3.RIGHT - nrm * nrm.x).normalized()
			tangents[i * 4] = t.x
			tangents[i * 4 + 1] = t.y
			tangents[i * 4 + 2] = t.z
			tangents[i * 4 + 3] = 1.0
	indices.resize(n * n * 6)
	var k := 0
	for zi in n:
		for xi in n:
			var a := zi * count + xi
			var c := a + count
			indices[k] = a
			indices[k + 1] = a + 1
			indices[k + 2] = c
			indices[k + 3] = a + 1
			indices[k + 4] = c + 1
			indices[k + 5] = c
			k += 6
	chunk_arrays.append([verts, indices])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = nrms
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TANGENT] = tangents
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func build_collision() -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "TerrainBody"
	body.collision_layer = Layers.WORLD
	body.set_meta(&"surface", &"dirt")
	var shape := HeightMapShape3D.new()
	shape.map_width = RES
	shape.map_depth = RES
	shape.map_data = heights
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.scale = Vector3(CELL, 1.0, CELL)   # one sample every CELL metres
	body.add_child(cs)
	add_child(body)
	return body


func control_texture() -> ImageTexture:
	return ImageTexture.create_from_image(control)


func biome_texture() -> ImageTexture:
	return ImageTexture.create_from_image(biome)
