class_name Terrain
extends Node3D
## Heightfield island: generates heights + a splat control map from a seed,
## then builds chunked render meshes (for culling) and a single
## HeightMapShape3D for physics. Also answers height/normal queries.

const SIZE := 512.0            ## metres covered by the heightfield
const RES := 513               ## vertices per side (1 m spacing)
const CHUNKS := 8              ## render chunks per side
const WATER_LEVEL := 0.0
const SEA_FLOOR := -7.0

var island_radius := 215.0
var heights := PackedFloat32Array()
var control: Image             ## R grass, G dirt path, B rock, A moss
var rng := RandomNumberGenerator.new()

var _n_base := FastNoiseLite.new()
var _n_detail := FastNoiseLite.new()
var _n_coast := FastNoiseLite.new()
var _n_patch := FastNoiseLite.new()
var _material: ShaderMaterial


func setup(seed_: int) -> void:
	rng.seed = seed_
	for n in [_n_base, _n_detail, _n_coast, _n_patch]:
		n.seed = rng.randi()
		n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_n_base.frequency = 0.0045
	_n_base.fractal_type = FastNoiseLite.FRACTAL_FBM
	_n_base.fractal_octaves = 5
	_n_detail.frequency = 0.03
	_n_detail.fractal_octaves = 2
	_n_coast.frequency = 0.009
	_n_coast.fractal_octaves = 3
	_n_patch.frequency = 0.02
	_n_patch.fractal_octaves = 3


## Raw island shape before POIs are flattened in.
func generate_heights() -> void:
	heights.resize(RES * RES)
	var half := SIZE * 0.5
	for zi in RES:
		var z := zi - half
		for xi in RES:
			var x := xi - half
			var d := sqrt(x * x + z * z) / island_radius
			var coast := d + _n_coast.get_noise_2d(x, z) * 0.12
			var land := smoothstep(1.02, 0.8, coast)
			var hills := pow(_n_base.get_noise_2d(x, z) * 0.5 + 0.5, 1.35) * 24.0
			hills *= lerpf(0.45, 1.0, clampf(1.0 - d, 0.0, 1.0))
			hills += _n_detail.get_noise_2d(x, z) * 0.9
			heights[zi * RES + xi] = lerpf(SEA_FLOOR, 1.4 + hills, land)


## Blend the ground towards `target` inside a circle (for clearings, POIs).
func flatten(center: Vector2, radius: float, target: float, strength := 1.0) -> void:
	var half := SIZE * 0.5
	var r_out := radius * 1.45
	var x0 := maxi(0, int(center.x + half - r_out))
	var x1 := mini(RES - 1, int(center.x + half + r_out) + 1)
	var z0 := maxi(0, int(center.y + half - r_out))
	var z1 := mini(RES - 1, int(center.y + half + r_out) + 1)
	for zi in range(z0, z1 + 1):
		for xi in range(x0, x1 + 1):
			var p := Vector2(xi - half, zi - half)
			var w := smoothstep(r_out, radius * 0.75, p.distance_to(center)) * strength
			if w > 0.0:
				var i := zi * RES + xi
				heights[i] = lerpf(heights[i], target + _n_detail.get_noise_2d(p.x, p.y) * 0.3, w)


## Splat weights. `paths` is an array of PackedVector2Array polylines.
func build_control(paths: Array) -> void:
	control = Image.create_empty(RES, RES, false, Image.FORMAT_RGBA8)
	var half := SIZE * 0.5
	var path_mask := PackedFloat32Array()
	path_mask.resize(RES * RES)
	for poly in paths:
		_stamp_path(poly, path_mask, 2.6)
	for zi in RES:
		for xi in RES:
			var x := xi - half
			var z := zi - half
			var n := normal_at(x, z)
			var slope := 1.0 - n.y
			var h := heights[zi * RES + xi]
			var patch := _n_patch.get_noise_2d(x, z)
			var rock := smoothstep(0.22, 0.4, slope)
			var grass := smoothstep(-0.05, 0.35, patch) * (1.0 - rock) * smoothstep(1.2, 2.2, h)
			var moss := smoothstep(0.2, 0.55, -patch) * (1.0 - rock) * 0.8
			var dirt := maxf(path_mask[zi * RES + xi], smoothstep(0.12, 0.22, slope) * (1.0 - rock) * 0.6)
			control.set_pixel(xi, zi, Color(grass * (1.0 - dirt), dirt, rock, moss * (1.0 - dirt)))


func _stamp_path(poly: PackedVector2Array, mask: PackedFloat32Array, width: float) -> void:
	var half := SIZE * 0.5
	for i in poly.size() - 1:
		var a := poly[i]
		var b := poly[i + 1]
		var steps := int(a.distance_to(b))
		for s in steps + 1:
			var p := a.lerp(b, float(s) / maxf(steps, 1))
			var wobble := _n_patch.get_noise_2d(p.x * 3.0, p.y * 3.0) * 0.8
			var r := width + wobble
			for dz in range(-4, 5):
				for dx in range(-4, 5):
					var xi := int(p.x + half) + dx
					var zi := int(p.y + half) + dz
					if xi < 0 or zi < 0 or xi >= RES or zi >= RES:
						continue
					var d := Vector2(xi - half, zi - half).distance_to(p)
					var w := smoothstep(r, r * 0.4, d)
					var idx := zi * RES + xi
					mask[idx] = maxf(mask[idx], w)


# ---- queries --------------------------------------------------------------------------------

func height_at(x: float, z: float) -> float:
	var half := SIZE * 0.5
	var fx := clampf(x + half, 0.0, RES - 1.001)
	var fz := clampf(z + half, 0.0, RES - 1.001)
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
	var hl := height_at(x - 1.0, z)
	var hr := height_at(x + 1.0, z)
	var hd := height_at(x, z - 1.0)
	var hu := height_at(x, z + 1.0)
	return Vector3(hl - hr, 2.0, hd - hu).normalized()


func is_land(x: float, z: float, min_height := 1.0) -> bool:
	return height_at(x, z) > min_height


func control_at(x: float, z: float) -> Color:
	var half := SIZE * 0.5
	var xi := clampi(int(x + half), 0, RES - 1)
	var zi := clampi(int(z + half), 0, RES - 1)
	return control.get_pixel(xi, zi)


# ---- building --------------------------------------------------------------------------------

func build_meshes(material: ShaderMaterial) -> void:
	_material = material
	var verts_per := (RES - 1) / CHUNKS
	for cz in CHUNKS:
		for cx in CHUNKS:
			var mi := MeshInstance3D.new()
			mi.name = "TerrainChunk_%d_%d" % [cx, cz]
			mi.mesh = _chunk_mesh(cx * verts_per, cz * verts_per, verts_per)
			mi.material_override = material
			mi.set_meta(&"surface", &"dirt")
			add_child(mi)


func _chunk_mesh(x0: int, z0: int, n: int) -> ArrayMesh:
	var half := SIZE * 0.5
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var count := n + 1
	verts.resize(count * count)
	normals.resize(count * count)
	uvs.resize(count * count)
	for zi in count:
		for xi in count:
			var gx := x0 + xi
			var gz := z0 + zi
			var x := gx - half
			var z := gz - half
			var i := zi * count + xi
			verts[i] = Vector3(x, heights[gz * RES + gx], z)
			normals[i] = normal_at(x, z)
			uvs[i] = Vector2(x, z)
	for zi in n:
		for xi in n:
			var a := zi * count + xi
			var b := a + 1
			var c := a + count
			var d := c + 1
			indices.append_array([a, b, c, b, d, c])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	# tangents along +X so world-space-UV normal maps light correctly
	var tangents := PackedFloat32Array()
	tangents.resize(count * count * 4)
	for i in count * count:
		var nrm := normals[i]
		var t := (Vector3.RIGHT - nrm * nrm.x).normalized()
		tangents[i * 4] = t.x
		tangents[i * 4 + 1] = t.y
		tangents[i * 4 + 2] = t.z
		tangents[i * 4 + 3] = 1.0
	arrays[Mesh.ARRAY_TANGENT] = tangents
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
	body.add_child(cs)
	add_child(body)
	return body


func control_texture() -> ImageTexture:
	return ImageTexture.create_from_image(control)
