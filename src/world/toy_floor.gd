class_name ToyFloor
extends Terrain
## The floor of the kid's bedroom in Toy Box Bash, on the heightfield
## machinery: flat oak floorboards with a printed town PLAY RUG in the middle
## (roads, lawns and a river printed on it, see `playmat_texture`), three
## biomes in the island's weight slots (x floor, y the SPILL round the
## tipped-over water from the fishbowl, z the PILLOW hills: pillows heaped
## under a patchwork quilt) and a flat bed for the toy train's track.

const HX := 580.0                ## the playable floor, half width (x)
const HZ := 420.0                ## and half depth (z)
const FLOOR := 4.0
const RUG_RAISE := 0.25
const SPILL_LEVEL := FLOOR - 0.25
const RUG := Rect2(-60.0, -250.0, 480.0, 510.0)   ## x, z, width, depth
const SPILL_AT := Vector2(-350, 225)
const SPILL_R := 170.0
const PILLOW_AT := Vector2(-410, -280)
const PILLOW_R := 230.0

## [centre: Vector2, half size: Vector2, yaw, height] of each pillow mound.
var pillows: Array = []


func _init() -> void:
	island_radius = sqrt(HX * HX + HZ * HZ)


func inside(x: float, z: float, margin := 0.0) -> bool:
	return absf(x) <= HX - margin and absf(z) <= HZ - margin


func on_rug(x: float, z: float, margin := 0.0) -> bool:
	return RUG.grow(-margin).has_point(Vector2(x, z))


func _biome_raw(x: float, z: float) -> Vector3:
	var q := Vector2(x, z) + Vector2(_n_warp.get_noise_2d(x, z), _n_warp.get_noise_2d(z + 311.0, x - 177.0)) * 40.0
	var ws := smoothstep(SPILL_R, SPILL_R * 0.55, q.distance_to(SPILL_AT))
	var wp := smoothstep(PILLOW_R, PILLOW_R * 0.55, q.distance_to(PILLOW_AT))
	var wf := clampf(1.0 - ws - wp, 0.0, 1.0)
	return Vector3(wf, ws, wp) / maxf(wf + ws + wp, 0.001)


func generate_heights() -> void:
	_build_biomes()
	# a heap of big pillows in the pillow corner (superellipse mounds)
	for i in 9:
		var a := rng.randf() * TAU
		var d := sqrt(rng.randf()) * PILLOW_R * 0.7
		pillows.append([PILLOW_AT + Vector2(cos(a), sin(a)) * d, Vector2(rng.randf_range(26.0, 38.0), rng.randf_range(17.0, 24.0)),
			rng.randf() * TAU, rng.randf_range(7.0, 16.0)])
	heights.resize(RES * RES)
	var half := SIZE * 0.5
	for zi in RES:
		var z := zi * CELL - half
		for xi in RES:
			var x := xi * CELL - half
			var h := FLOOR
			if inside(x, z, -1.0):
				var w := biome_at(x, z)
				# the rug: a quarter metre thick with a soft rolled edge
				var edge := minf(minf(x - RUG.position.x, RUG.end.x - x), minf(z - RUG.position.y, RUG.end.y - z))
				h += RUG_RAISE * smoothstep(-0.5, 1.5, edge)
				# the spill: the floorboards sag a little where the water pooled
				var dip := (0.6 + 0.9 * smoothstep(-0.2, 0.5, _n_bog.get_noise_2d(x, z))) * w.y
				h -= dip
				# pillows: soft rounded mounds under the quilt
				var lump := 0.0
				for p in (pillows if w.z > 0.05 else []):
					var local: Vector2 = (Vector2(x, z) - (p[0] as Vector2)).rotated(-float(p[2]))
					var u: float = local.x / (p[1] as Vector2).x
					var v: float = local.y / (p[1] as Vector2).y
					var s: float = 1.0 - (u * u * u * u + v * v * v * v)
					if s > 0.0:
						lump = maxf(lump, float(p[3]) * sqrt(s))
				h += lump * smoothstep(0.1, 0.4, w.z) + w.z * (1.5 + _n_base.get_noise_2d(x, z) * 1.5)
			heights[zi * RES + xi] = h


## Level a corridor along a polyline (the train track's bed) to the floor.
func flatten_corridor(points: PackedVector3Array, width: float) -> void:
	var half := SIZE * 0.5
	var reach := width * 0.5 + 6.0
	var r := int(ceil(reach / CELL)) + 1
	for i in points.size():
		var a := Vector2(points[i].x, points[i].z)
		var cx := int((a.x + half) / CELL)
		var cz := int((a.y + half) / CELL)
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var xi := cx + dx
				var zi := cz + dz
				if xi < 0 or zi < 0 or xi >= RES or zi >= RES:
					continue
				var d := Vector2(xi * CELL - half, zi * CELL - half).distance_to(a)
				var w := smoothstep(reach, width * 0.5, d)
				var k := zi * RES + xi
				heights[k] = lerpf(heights[k], FLOOR, w)


## Splat weights: R scuffed wax, G the track bed, B steep (quilt folds), A unused.
func build_control(paths: Array) -> void:
	if normals.size() != RES * RES:
		compute_normals()
	control = Image.create_empty(RES, RES, false, Image.FORMAT_RGBA8)
	var data := PackedByteArray()
	data.resize(RES * RES * 4)
	var half := SIZE * 0.5
	for zi in RES:
		for xi in RES:
			var i := zi * RES + xi
			var x := xi * CELL - half
			var z := zi * CELL - half
			data[i * 4] = int(clampf(smoothstep(0.25, 0.6, _n_patch.get_noise_2d(x, z)), 0.0, 1.0) * 255.0)
			data[i * 4 + 2] = int(clampf(smoothstep(0.2, 0.5, 1.0 - normals[i].y), 0.0, 1.0) * 255.0)
	control.set_data(RES, RES, false, Image.FORMAT_RGBA8, data)


## The printed play rug: a little town of roads round lawns and parks, a
## river with a bridge, parking bays and printed houses, in bright felt colours.
static func playmat_texture() -> ImageTexture:
	var n := 1024
	var img := Image.create_empty(n, n, false, Image.FORMAT_RGB8)
	var k := Vector2(n / RUG.size.x, n / RUG.size.y)
	var rect := func(x0: float, z0: float, x1: float, z1: float, c: Color) -> void:
		var a := Vector2i(int((x0 - RUG.position.x) * k.x), int((z0 - RUG.position.y) * k.y))
		var b := Vector2i(int((x1 - RUG.position.x) * k.x), int((z1 - RUG.position.y) * k.y))
		img.fill_rect(Rect2i(a, (b - a).max(Vector2i.ONE)).intersection(Rect2i(0, 0, n, n)), c)
	var x0 := RUG.position.x
	var z0 := RUG.position.y
	var x1 := RUG.end.x
	var z1 := RUG.end.y
	var lawn := Color(0.42, 0.72, 0.36)
	var road := Color(0.42, 0.44, 0.48)
	var line := Color(0.98, 0.95, 0.75)
	rect.call(x0, z0, x1, z1, lawn)
	# parks and a pond
	rect.call(x0 + 40.0, z0 + 40.0, x0 + 150.0, z0 + 150.0, Color(0.34, 0.62, 0.3))
	rect.call(x0 + 70.0, z0 + 70.0, x0 + 120.0, z0 + 120.0, Color(0.36, 0.62, 0.9))
	# the river across the north part, and a bridge
	rect.call(x0, z0 + 175.0, x1, z0 + 205.0, Color(0.32, 0.58, 0.92))
	rect.call(x0 + 245.0, z0 + 168.0, x0 + 275.0, z0 + 212.0, Color(0.72, 0.5, 0.32))
	# roads: a ring road and two cross streets, with dashed centre lines
	var w := 14.0
	var roads := [[x0 + 18.0, z0 + 18.0, x1 - 18.0, z0 + 18.0 + w], [x0 + 18.0, z1 - 18.0 - w, x1 - 18.0, z1 - 18.0],
		[x0 + 18.0, z0 + 18.0, x0 + 18.0 + w, z1 - 18.0], [x1 - 18.0 - w, z0 + 18.0, x1 - 18.0, z1 - 18.0],
		[x0 + 253.0, z0 + 18.0, x0 + 253.0 + w, z1 - 18.0], [x0 + 18.0, z0 + 280.0, x1 - 18.0, z0 + 280.0 + w],
		[x0 + 368.0, z0 + 280.0, x0 + 368.0 + w, z1 - 18.0], [x0 + 253.0, z0 + 400.0, x1 - 18.0, z0 + 400.0 + w]]
	for r in roads:
		rect.call(r[0], r[1], r[2], r[3], road)
	for r in roads:
		var horizontal: bool = r[2] - r[0] > r[3] - r[1]
		if horizontal:
			var zc: float = (r[1] + r[3]) * 0.5
			var x: float = r[0] + 4.0
			while x < r[2] - 6.0:
				rect.call(x, zc - 0.5, x + 5.0, zc + 0.5, line)
				x += 10.0
		else:
			var xc: float = (r[0] + r[2]) * 0.5
			var z: float = r[1] + 4.0
			while z < r[3] - 6.0:
				rect.call(xc - 0.5, z, xc + 0.5, z + 5.0, line)
				z += 10.0
	# printed houses and parking bays along the streets
	var rng := RandomNumberGenerator.new()
	rng.seed = 2024
	var colours := [Color(0.95, 0.4, 0.35), Color(0.98, 0.8, 0.3), Color(0.45, 0.6, 0.95), Color(0.9, 0.55, 0.85), Color(0.98, 0.6, 0.25)]
	for i in 18:
		var hx := rng.randf_range(x0 + 40.0, x1 - 50.0)
		var hz := rng.randf_range(z0 + 215.0, z1 - 50.0)
		var col: Color = colours[i % colours.size()]
		rect.call(hx, hz, hx + 14.0, hz + 12.0, col)
		rect.call(hx + 3.0, hz + 3.0, hx + 6.0, hz + 6.0, Color(0.95, 0.95, 0.85))
		rect.call(hx + 8.0, hz + 3.0, hx + 11.0, hz + 6.0, Color(0.95, 0.95, 0.85))
	for i in 6:
		var px := x0 + 300.0 + i * 12.0
		rect.call(px, z0 + 300.0, px + 1.0, z0 + 318.0, line)
	# a felt border
	rect.call(x0, z0, x1, z0 + 6.0, Color(0.2, 0.3, 0.65))
	rect.call(x0, z1 - 6.0, x1, z1, Color(0.2, 0.3, 0.65))
	rect.call(x0, z0, x0 + 6.0, z1, Color(0.2, 0.3, 0.65))
	rect.call(x1 - 6.0, z0, x1, z1, Color(0.2, 0.3, 0.65))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)
