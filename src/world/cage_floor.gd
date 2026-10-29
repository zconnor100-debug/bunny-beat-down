class_name CageFloor
extends Terrain
## The floor of the hamster tank, on the island's heightfield machinery: a
## rectangle of wood-shaving bedding in rolling hills (like the island's
## meadows: broad rises, smaller rolls between them, and the hamster's own
## big heaps of bedding, the `mounds`), heaped up against the glass, with
## two other biomes in it: a LAGOON of spilled water over aquarium
## gravel round the water bowls (west), and a WINTER corner of snow drifts
## where the open fridge's cold pours over the north wall (north-east).
## Biome weights reuse the island's slots: x bedding, y lagoon, z winter.
## Outside the glass the heightfield drops out of sight under the room floor.

const HX := 560.0                ## the tank's inside, half width (x)
const HZ := 400.0                ## and half depth (z)
const BEDDING := 4.0             ## base height of the bedding
const LAGOON_LEVEL := 3.2        ## the lagoon's still water
const OUTSIDE := -40.0
const MAX_HEAP := 17.0           ## the bedding piled against the glass stops here
const MAX_HILL := 34.0           ## and out in the middle, the tallest hills here
const LAGOON_AT := Vector2(-340, 110)
const LAGOON_R := 250.0
const WINTER_AT := Vector2(400, -300)
const WINTER_R := 320.0

## The hamster's heaps of bedding: [Vector2 centre, radius, height] (set
## before generate_heights).
var mounds: Array = []
## Bathing-sand circles: [Vector2 centre, radius] (painted with sand).
var sand_spots: Array = []
## Gravel and snow ramps up to bowl rims and the like: [a, b, width, h_a, h_b].
var ramps: Array = []


func _init() -> void:
	island_radius = sqrt(HX * HX + HZ * HZ)


func inside(x: float, z: float, margin := 0.0) -> bool:
	return absf(x) <= HX - margin and absf(z) <= HZ - margin


## Metres to the nearest glass wall (negative outside).
func edge_distance(x: float, z: float) -> float:
	return minf(HX - absf(x), HZ - absf(z))


func _biome_raw(x: float, z: float) -> Vector3:
	var q := Vector2(x, z) + Vector2(_n_warp.get_noise_2d(x, z), _n_warp.get_noise_2d(z + 311.0, x - 177.0)) * 60.0
	var wl := smoothstep(LAGOON_R, LAGOON_R * 0.55, q.distance_to(LAGOON_AT))
	var ww := smoothstep(WINTER_R, WINTER_R * 0.5, q.distance_to(WINTER_AT))
	var wb := clampf(1.0 - wl - ww, 0.0, 1.0)
	return Vector3(wb, wl, ww) / maxf(wb + wl + ww, 0.001)


func generate_heights() -> void:
	_build_biomes()
	heights.resize(RES * RES)
	var half := SIZE * 0.5
	for zi in RES:
		var z := zi * CELL - half
		for xi in RES:
			var x := xi * CELL - half
			if absf(x) > HX + 1.0 or absf(z) > HZ + 1.0:
				heights[zi * RES + xi] = OUTSIDE
				continue
			var w := biome_at(x, z)
			var edge := maxf(edge_distance(x, z), 0.0)
			var detail := _n_detail.get_noise_2d(x, z) * 0.35
			# bedding: broad rolling hills, smaller rolls between them and the
			# hamster's heaps, piled up against the glass
			var hills := pow(_n_base.get_noise_2d(x, z) * 0.5 + 0.5, 1.3) * 21.0
			var rolls := (_n_mesa.get_noise_2d(x, z) * 0.5 + 0.5) * 6.5
			var heap := smoothstep(80.0, 0.0, edge) * (6.0 + _n_patch.get_noise_2d(x, z) * 3.0)
			var bed := BEDDING + hills + rolls + mound_at(x, z) + detail + heap
			bed = minf(bed, lerpf(MAX_HILL, MAX_HEAP, smoothstep(60.0, 0.0, edge)))
			# winter: rolling snow drifts, deepest where the cold spills over the glass
			var drift := pow(clampf(_n_mesa.get_noise_2d(x, z) * 0.5 + 0.5, 0.0, 1.0), 1.3) * 7.0
			var snow := BEDDING + 0.6 + drift + smoothstep(110.0, 0.0, edge) * 10.0 + detail * 0.4
			# lagoon: knee-deep water over gravel, with a few deeper pools
			var pools := smoothstep(-0.1, 0.45, _n_bog.get_noise_2d(x, z))
			var lagoon := LAGOON_LEVEL - 0.9 - pools * 1.6 + detail * 0.5
			heights[zi * RES + xi] = bed * w.x + lagoon * w.y + minf(snow, MAX_HEAP) * w.z


## How much the hamster's heaps raise the bedding here: a rounded dome each,
## its edge wandering a little.
func mound_at(x: float, z: float) -> float:
	var h := 0.0
	for m in mounds:
		var r: float = m[1] * (1.0 + _n_patch.get_noise_2d(x * 0.5, z * 0.5) * 0.25)
		var d := Vector2(x, z).distance_to(m[0]) / r
		if d < 1.0:
			h = maxf(h, float(m[2]) * (0.5 + 0.5 * cos(PI * d)))
	return h


## Raise the ground along a ramp (a gravel slope up to a bowl's rim, say):
## from height h_a at a to h_b at b, `width` wide, never lowering it.
func ramp(a: Vector2, b: Vector2, width: float, h_a: float, h_b: float) -> void:
	ramps.append([a, b, width, h_a, h_b])
	var half := SIZE * 0.5
	var reach := width * 0.5 + 6.0
	var lo := Vector2(minf(a.x, b.x), minf(a.y, b.y)) - Vector2.ONE * reach
	var hi := Vector2(maxf(a.x, b.x), maxf(a.y, b.y)) + Vector2.ONE * reach
	for zi in range(maxi(0, int((lo.y + half) / CELL)), mini(RES - 1, int((hi.y + half) / CELL) + 1) + 1):
		for xi in range(maxi(0, int((lo.x + half) / CELL)), mini(RES - 1, int((hi.x + half) / CELL) + 1) + 1):
			var p := Vector2(xi * CELL - half, zi * CELL - half)
			var ab := b - a
			var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
			var off := p.distance_to(a + ab * t)
			var target := lerpf(h_a, h_b, smoothstep(0.0, 1.0, t))
			# flat across the walkway, then a soft shoulder down to the ground
			var w := smoothstep(width * 0.5 + 6.0, width * 0.5, off)
			var i := zi * RES + xi
			heights[i] = maxf(heights[i], lerpf(heights[i], target, w))


## Splat weights: R paper bedding (white tufts over the shavings), G trodden
## trails, B steep slopes, A bathing sand.
func build_control(paths: Array) -> void:
	if normals.size() != RES * RES:
		compute_normals()
	control = Image.create_empty(RES, RES, false, Image.FORMAT_RGBA8)
	var half := SIZE * 0.5
	var path_mask := PackedFloat32Array()
	path_mask.resize(RES * RES)
	for poly in paths:
		_stamp_path(poly, path_mask, 3.2)
	var data := PackedByteArray()
	data.resize(RES * RES * 4)
	for zi in RES:
		for xi in RES:
			var i := zi * RES + xi
			var x := xi * CELL - half
			var z := zi * CELL - half
			var w := biome_at(x, z)
			var patch := _n_patch.get_noise_2d(x, z)
			var paper := smoothstep(0.32, 0.62, patch) * w.x * 0.8
			var trail := path_mask[i] * (1.0 - w.y) * (1.0 - w.z * 0.6)
			var steep := smoothstep(0.25, 0.5, 1.0 - normals[i].y)
			var sand := 0.0
			for s in sand_spots:
				sand = maxf(sand, smoothstep(float(s[1]), float(s[1]) - 3.0, Vector2(x, z).distance_to(s[0])))
			data[i * 4] = int(clampf(paper * (1.0 - trail) * (1.0 - sand), 0.0, 1.0) * 255.0)
			data[i * 4 + 1] = int(clampf(trail * (1.0 - sand), 0.0, 1.0) * 255.0)
			data[i * 4 + 2] = int(clampf(steep, 0.0, 1.0) * 255.0)
			data[i * 4 + 3] = int(clampf(sand, 0.0, 1.0) * 255.0)
	control.set_data(RES, RES, false, Image.FORMAT_RGBA8, data)
