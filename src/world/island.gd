class_name Island
extends Node3D
## Builds a whole battle-royale island from a seed: terrain with three biomes
## (a hilly forest, open grasslands and a swamp of still water), points of
## interest including the big walk-in buildings of each biome, paths, trees,
## ground cover, reeds and lily pads, water, loot spots and a tiled
## navigation mesh for the AI. Generation yields between steps so a loading
## screen can animate (`progress` signal).

signal progress(fraction: float, label: String)

const TERRAIN_SHADER := preload("res://src/world/shaders/terrain.gdshader")
const WATER_SHADER := preload("res://src/world/shaders/water.gdshader")
const NAV_TILES := 12
const POI_SPACING := 125.0
const ANY := -1
const FOREST := Terrain.Biome.FOREST
const SWAMP := Terrain.Biome.SWAMP
const GRASS := Terrain.Biome.GRASS

## Points of interest: name, what to build there, radius, and the biome it
## belongs in. The big buildings come first so they always find a spot.
const POI_KINDS := [
	{"name": "Woodcutter's Lodge", "kit": "lodge", "radius": 28.0, "biome": FOREST},
	{"name": "Ranger's Lodge", "kit": "lodge", "radius": 28.0, "biome": FOREST},
	{"name": "Big Red Barn", "kit": "barn", "radius": 30.0, "biome": GRASS},
	{"name": "Haystack Barn", "kit": "barn", "radius": 30.0, "biome": GRASS},
	{"name": "Bayou Shacks", "kit": "shacks", "radius": 34.0, "biome": SWAMP},
	{"name": "Croaker's Stilts", "kit": "shacks", "radius": 34.0, "biome": SWAMP},
	{"name": "Carrot Patch", "kit": "carrot_patch", "radius": 30.0, "biome": GRASS},
	{"name": "Picnic Hill", "kit": "picnic", "radius": 26.0, "biome": GRASS},
	{"name": "Gnome Garden", "kit": "gnome_garden", "radius": 24.0, "biome": GRASS},
	{"name": "Duck Pond", "kit": "pond", "radius": 26.0, "biome": GRASS},
	{"name": "Mushroom Ring", "kit": "mushroom_ring", "radius": 24.0, "biome": FOREST},
	{"name": "Cottage Hollow", "kit": "cottages", "radius": 30.0, "biome": FOREST},
	{"name": "Hollow Stump", "kit": "hollow_stump", "radius": 26.0, "biome": SWAMP},
	{"name": "Log Jam", "kit": "logs", "radius": 26.0, "biome": SWAMP},
	{"name": "Stump Village", "kit": "stumps", "radius": 28.0, "biome": SWAMP},
	{"name": "Boulder Bluff", "kit": "boulders", "radius": 28.0, "biome": ANY},
	{"name": "Treasure Grove", "kit": "treasure", "radius": 22.0, "biome": ANY},
]

var seed_value := 1
var rng := RandomNumberGenerator.new()
## What everyone rides in on (see Dropship), what the map is called, and the
## music slot that plays during a match on it.
var drop_vehicle := &"balloon"
var map_id := "island"           ## (Settings "map": the key your wins on it are kept under)
var map_title := "Wildwood Island"
var music_slot := "match"
var terrain: Terrain
var scatter: Scatter
var pois: Array = []          # {name, center: Vector2, radius, height}
var paths: Array = []         # PackedVector2Array polylines
var loot_points: Array = []   # {pos: Vector3, crate: bool, poi: String}
var nav_regions: Array[NavigationRegion3D] = []
var buildings: Array[Building] = []
var water: MeshInstance3D
var swamp_water: MeshInstance3D
var _swamp_cells := PackedByteArray()   # Terrain.BIOME_RES² cells with standing swamp water
var ready_to_play := false
var _foliage_materials: Array[ShaderMaterial] = []

## The island currently being played (critters ask it where the water is).
static var current: Island


func _exit_tree() -> void:
	if current == self:
		current = null


func generate(seed_: int, quality := 2, bake_nav := true) -> void:
	current = self
	seed_value = seed_
	rng.seed = seed_
	terrain = Terrain.new()
	terrain.name = "Terrain"
	add_child(terrain)
	terrain.setup(seed_)
	scatter = Scatter.new()
	scatter.name = "Scatter"
	add_child(scatter)
	scatter.load_manifest()

	progress.emit(0.05, "Growing the island")
	await get_tree().process_frame
	terrain.generate_heights()
	_choose_pois()
	_shape_pois()
	_plan_paths()
	terrain.compute_normals()

	progress.emit(0.25, "Painting the meadows")
	await get_tree().process_frame
	terrain.build_control(paths)
	terrain.build_meshes(_terrain_material())
	terrain.build_collision()
	_build_water()
	_build_swamp_water()
	_build_boundary()

	progress.emit(0.4, "Raising barns and lodges")
	await get_tree().process_frame
	_build_pois()
	progress.emit(0.45, "Planting giant trees")
	await get_tree().process_frame
	_scatter_forest()
	progress.emit(0.55, "Scattering mushrooms and pebbles")
	await get_tree().process_frame
	_scatter_ground_cover(quality)
	_scatter_swamp(quality)
	scatter.flush_batches(quality)
	_collect_foliage_materials()
	_plan_loot()

	if bake_nav:
		progress.emit(0.7, "Teaching critters the paths")
		await get_tree().process_frame
		await _bake_navigation()
	progress.emit(1.0, "Ready")
	ready_to_play = true


# ---- POIs & paths -------------------------------------------------------------------------

func _choose_pois() -> void:
	for k in POI_KINDS:
		var biome: int = k.biome
		for attempt in 800:
			var a := rng.randf() * TAU
			var d := sqrt(rng.randf()) * terrain.island_radius * 0.74
			var c := Vector2(cos(a), sin(a)) * d
			var h := terrain.height_at(c.x, c.y)
			var w := terrain.biome_at(c.x, c.y)
			if biome != ANY and [w.x, w.y, w.z][biome] < 0.6:
				continue
			if biome == SWAMP:
				if h < Terrain.SWAMP_LEVEL - 1.2:
					continue
			elif h < 3.0 or w.y > 0.3:
				continue
			var ok := true
			for p in pois:
				if c.distance_to(p.center) < POI_SPACING:
					ok = false
					break
			if not ok:
				continue
			var target := clampf(h, 3.0, 30.0)
			if k.kit == "shacks":
				target = Terrain.SWAMP_LEVEL - 0.6   # stilts standing in the water
			elif biome == SWAMP:
				target = maxf(h, Terrain.SWAMP_LEVEL + 0.7)   # a dry hummock in the swamp
			pois.append({"name": k.name, "kit": k.kit, "radius": k.radius, "center": c, "height": target,
				"biome": biome, "buildings": []})
			break


func _shape_pois() -> void:
	for p in pois:
		terrain.flatten(p.center, p.radius, p.height)
		if p.kit == "pond":
			terrain.flatten(p.center, p.radius * 0.55, p.height - 2.2)
		elif p.kit in ["lodge", "barn"]:
			# dead level under a building, so its floor sits just above the ground
			terrain.flatten(p.center, p.radius * 0.75, p.height, 1.0, false)


func _plan_paths() -> void:
	# connect every POI to its two nearest neighbours with a wandering track
	var seen := {}
	for i in pois.size():
		var near := []
		for j in pois.size():
			if i != j:
				near.append([pois[i].center.distance_to(pois[j].center), j])
		near.sort_custom(func(a, b): return a[0] < b[0])
		for k in mini(2, near.size()):
			var j: int = near[k][1]
			var key := "%d-%d" % [mini(i, j), maxi(i, j)]
			if seen.has(key):
				continue
			seen[key] = true
			paths.append(_wander(pois[i].center, pois[j].center))


func _wander(a: Vector2, b: Vector2) -> PackedVector2Array:
	var pts := PackedVector2Array([a])
	var n := int(a.distance_to(b) / 12.0)
	var side := (b - a).orthogonal().normalized()
	var phase := rng.randf() * TAU
	for i in range(1, n):
		var t := float(i) / n
		var off := sin(t * PI * 2.0 + phase) * 9.0 * sin(t * PI)
		pts.append(a.lerp(b, t) + side * off)
	pts.append(b)
	return pts


func _build_pois() -> void:
	for p in pois:
		var c3 := Vector3(p.center.x, 0, p.center.y)
		match p.kit:
			"carrot_patch":
				var yaw := rng.randf() * TAU
				var across := Vector2(cos(yaw), -sin(yaw))
				for k in [-1.0, 1.0]:
					_put("carrot_patch", p.center + across * 7.0 * k, yaw, 1.0)
				for i in 6:
					var a := TAU * i / 6.0
					_put("fence_picket", p.center + Vector2(cos(a), sin(a)) * 22.0, -a, 1.0)
				_put("watering_can", p.center + Vector2(14, 6), rng.randf() * TAU, 1.0)
				_put("garden_spade", p.center + Vector2(-15, 10), rng.randf() * TAU, 1.0)
				_put("wooden_crate", p.center + Vector2(12, -12), rng.randf() * TAU, 1.0)
				_put("flower_pot", p.center + Vector2(-14, -12), 0.0, 1.0)
			"picnic":
				_put("picnic_blanket", p.center, rng.randf() * TAU, 1.0)
				_put("picnic_basket", p.center + Vector2(3, 2), rng.randf() * TAU, 1.0)
				_put("picnic_table", p.center + Vector2(-13, 6), rng.randf() * TAU, 1.0)
				for i in 3:
					_put("apple", p.center + Vector2(rng.randf_range(-6, 6), rng.randf_range(-6, 6)), rng.randf() * TAU, 1.0)
				_put("tin_can", p.center + Vector2(9, -8), rng.randf() * TAU, 1.0)
				_put("tin_can", p.center + Vector2(-7, -11), rng.randf() * TAU, 1.0)
			"mushroom_ring":
				var n := 12
				for i in n:
					var a := TAU * i / n
					var e := scatter.pick("mushroom", rng)
					_put_entry(e, p.center + Vector2(cos(a), sin(a)) * 17.0, rng.randf() * TAU, rng.randf_range(0.9, 1.4))
				_put("mushroom_cluster", p.center, 0.0, 1.6)
			"hollow_stump":
				_put("stump_hollow", p.center, rng.randf() * TAU, 1.0)
				_put("birdhouse_stump", p.center + Vector2(16, 8), rng.randf() * TAU, 1.0)
				_put("log_dead_big", p.center + Vector2(-14, -10), rng.randf() * TAU, 1.0)
			"gnome_garden":
				for i in 4:
					var fa := TAU * i / 4.0 + 0.3
					_put("fence_picket", p.center + Vector2(cos(fa), sin(fa)) * 19.0, -fa, 1.0)
				for i in 3:
					var a := TAU * i / 3.0 + 0.4
					_put("garden_gnome", p.center + Vector2(cos(a), sin(a)) * 11.0, a + PI, 1.0)
				_put("flower_pot", p.center + Vector2(4, -3), 0.0, 1.0)
				_put("rubber_boot", p.center + Vector2(-6, 5), rng.randf() * TAU, 1.0)
				_put("watering_can", p.center + Vector2(-2, -9), rng.randf() * TAU, 1.0)
			"boulders":
				_put("cliff_rock", p.center + Vector2(-8, 0), rng.randf() * TAU, 1.0)
				_put("boulder_big", p.center + Vector2(10, 7), rng.randf() * TAU, 1.0)
				_put("boulder_big", p.center + Vector2(6, -12), rng.randf() * TAU, 0.8)
				for i in 5:
					_put_entry(scatter.pick("rock", rng), p.center + Vector2(rng.randf_range(-20, 20), rng.randf_range(-20, 20)), rng.randf() * TAU, rng.randf_range(0.8, 1.3))
			"logs":
				_put("log_hollow", p.center, rng.randf() * TAU, 1.0)
				for id in ["log_dead_big", "log_mossy", "log_old_mossy", "log_fallen_a", "log_birch_rotten"]:
					_put(id, p.center + Vector2(rng.randf_range(-14, 14), rng.randf_range(-14, 14)), rng.randf() * TAU, rng.randf_range(0.9, 1.2))
			"cottages":
				# a little lane of critter cottages facing a shared green
				for i in 4:
					var a := TAU * i / 4.0 + rng.randf_range(-0.3, 0.3)
					var at: Vector2 = p.center + Vector2(cos(a), sin(a)) * rng.randf_range(13.0, 18.0)
					_put_entry(scatter.pick("cottage", rng), at, -a - PI / 2.0, 1.0)
				for i in 4:
					var a2 := rng.randf() * TAU
					_put_entry(scatter.pick("cover", rng), p.center + Vector2(cos(a2), sin(a2)) * rng.randf_range(5.0, 10.0), rng.randf() * TAU, 1.0)
				_put("fence_picket", p.center + Vector2(0, 22), 0.0, 1.0)
			"stumps":
				for i in 9:
					var a3 := rng.randf() * TAU
					var at3: Vector2 = p.center + Vector2(cos(a3), sin(a3)) * rng.randf_range(4.0, 20.0)
					_put_entry(scatter.pick("stump", rng), at3, rng.randf() * TAU, rng.randf_range(0.9, 1.3))
				_put_entry(scatter.pick("cottage", rng), p.center, rng.randf() * TAU, 1.0)
			"treasure":
				var n2 := 10
				for i in n2:
					var a4 := TAU * i / n2
					_put_entry(scatter.pick("mushroom", rng), p.center + Vector2(cos(a4), sin(a4)) * 12.0, rng.randf() * TAU, rng.randf_range(1.0, 1.5))
				for i in 3:
					_put_entry(scatter.pick("rock", rng), p.center + Vector2(rng.randf_range(-9, 9), rng.randf_range(-9, 9)), rng.randf() * TAU, 0.8)
			"lodge":
				var yaw := _face_centre(p.center)
				_place_building(p, Building.Style.LODGE, p.center, yaw)
				var back := Vector2(sin(yaw), cos(yaw))
				var side := Vector2(back.y, -back.x)
				_put("cover_logpile", p.center + side * 15.0 + back * 4.0, yaw, 1.0)
				_put("cover_logpile", p.center - side * 14.0 - back * 6.0, yaw + 0.4, 1.0)
				for i in 4:
					var a := rng.randf() * TAU
					_put_entry(scatter.pick("stump", rng), p.center + Vector2(cos(a), sin(a)) * rng.randf_range(16.0, 22.0), rng.randf() * TAU, 1.0)
			"barn":
				var yaw := _face_centre(p.center)
				_place_building(p, Building.Style.BARN, p.center, yaw)
				var back := Vector2(sin(yaw), cos(yaw))
				var side := Vector2(back.y, -back.x)
				for i in 5:
					_put("cover_haybale", p.center + side * (12.5 + (i % 2) * 2.2) + back * (-8.0 + i * 3.6), rng.randf() * TAU, 1.0)
				_put("watering_can", p.center - side * 13.0 + back * 6.0, rng.randf() * TAU, 1.0)
				_put("fence_picket", p.center - side * 18.0 - back * 4.0, yaw + PI / 2.0, 1.0)
			"shacks":
				# two shacks on stilts out in the pool, side by side, their ramps
				# running down into the water the same way
				var yaw := rng.randf() * TAU
				var across := Vector2(cos(yaw), sin(yaw))
				for k in [-1.0, 1.0]:
					_place_building(p, Building.Style.SHACK, p.center + across * 12.0 * k, atan2(-across.y, across.x))
			"pond":
				_add_pond_water(c3, p)
				_put("rubber_duck", p.center + Vector2(3, 2), rng.randf() * TAU, 1.0, true)
				_put("old_tyre", p.center + Vector2(-16, 9), rng.randf() * TAU, 1.0)
				_put("rubber_boot", p.center + Vector2(17, -6), rng.randf() * TAU, 1.0)


## Yaw that turns a building's front door (+Z) toward `target` (default the
## middle of the island, where the paths and the action are).
func _face_centre(at: Vector2, target := Vector2.ZERO) -> float:
	var to := target - at
	return atan2(to.x, to.y)


func _place_building(p: Dictionary, style: Building.Style, at: Vector2, yaw: float) -> Building:
	var b := Building.make(style, rng)
	b.name = "%s_%d" % [b.name, buildings.size()]
	add_child(b)
	b.global_position = Vector3(at.x, terrain.height_at(at.x, at.y), at.y)
	b.rotation.y = yaw
	scatter.reserve(at, b.footprint)
	buildings.append(b)
	(p.buildings as Array).append(b)
	return b


func _put(id: String, at: Vector2, yaw: float, scale_: float, float_on_pond := false) -> Node3D:
	return _put_entry(scatter.get_entry(id), at, yaw, scale_, float_on_pond)


func _put_entry(e: Dictionary, at: Vector2, yaw: float, scale_: float, float_on_pond := false) -> Node3D:
	if e.is_empty():
		return null
	var y := terrain.height_at(at.x, at.y)
	if float_on_pond:
		y = _pond_level(at) - 0.3
	return scatter.place(e, Vector3(at.x, y, at.y), yaw, scale_, terrain.normal_at(at.x, at.y), 0.6)


func _pond_level(at: Vector2) -> float:
	for p in pois:
		if p.kit == "pond" and at.distance_to(p.center) < p.radius:
			return p.height - 0.9
	return Terrain.WATER_LEVEL


## Height of the water surface above a point (sea level, a pond's surface,
## or the still water of the swamp).
func water_level_at(pos: Vector3) -> float:
	var level := _pond_level(Vector2(pos.x, pos.z))
	if _in_swamp_water(pos.x, pos.z):
		level = maxf(level, Terrain.SWAMP_LEVEL)
	return level


func _in_swamp_water(x: float, z: float) -> bool:
	if _swamp_cells.is_empty():
		return false
	var xi := int((x + Terrain.SIZE * 0.5) / Terrain.BIOME_CELL)
	var zi := int((z + Terrain.SIZE * 0.5) / Terrain.BIOME_CELL)
	if xi < 0 or zi < 0 or xi >= Terrain.BIOME_RES or zi >= Terrain.BIOME_RES:
		return false
	return _swamp_cells[zi * Terrain.BIOME_RES + xi] == 1


## The playable area: the drop route and the Briar's centres stay inside it.
func play_bounds() -> Rect2:
	var r := terrain.island_radius
	return Rect2(-r, -r, r * 2.0, r * 2.0)


## The ground's colour at (x, z) on the minimap: sea, sand, water, meadow,
## moss, paths and rock, hill-shaded.
func map_color(x: float, z: float) -> Color:
	var h := terrain.height_at(x, z)
	if h < -0.2:
		return Color("2d6f8e").lerp(Color("153a52"), clampf(-h / 7.0, 0.0, 1.0))
	var wl := water_level_at(Vector3(x, h, z))
	if wl > h + 0.05:
		return Color("4f5f3a").lerp(Color("2f3d27"), clampf((wl - h) / 1.5, 0.0, 1.0))   # swamp / pond water
	if h < 1.6:
		return Color("d9c79a")
	var ctl := terrain.control_at(x, z)
	var c := Color("4d6b2c")
	c = c.lerp(Color("79a83f"), ctl.r)
	c = c.lerp(Color("3b5a22"), ctl.a)
	c = c.lerp(Color("b59562"), ctl.g)
	c = c.lerp(Color("8d8a82"), ctl.b)
	var nrm := terrain.normal_at(x, z)
	var shade := clampf(nrm.dot(Vector3(-0.5, 0.75, -0.4).normalized()), 0.35, 1.0)
	return c * (0.55 + 0.6 * shade)


## A map may adjust the sun and the air once it's built (the island doesn't).
func tune_lighting(_lighting: WorldLighting) -> void:
	pass


func in_poi(p: Vector2, margin := 1.0) -> Dictionary:
	for poi in pois:
		if p.distance_to(poi.center) < poi.radius * margin:
			return poi
	return {}


# ---- vegetation --------------------------------------------------------------------------------

func _scatter_forest() -> void:
	var forest := FastNoiseLite.new()
	forest.seed = rng.randi()
	forest.frequency = 0.012
	var spacing := 19.0
	var half := terrain.island_radius
	var z := -half
	while z < half:
		var x := -half
		while x < half:
			var p := Vector2(x + rng.randf_range(-7, 7), z + rng.randf_range(-7, 7))
			x += spacing
			var w := terrain.biome_at(p.x, p.y)
			# thick woods in the forest, the odd lone oak on the grassland, and
			# bare dead trees standing in the swamp
			var dens := smoothstep(-0.25, 0.45, forest.get_noise_2d(p.x, p.y)) * (w.x + w.z * 0.1) + w.y * 0.35
			if rng.randf() > dens * 0.85 or not _solid_ok(p, 3.5):
				continue
			var cat := "deadtree" if w.y > maxf(w.x, w.z) and scatter.by_category.has("deadtree") and rng.randf() < 0.85 else "tree"
			var e := scatter.pick(cat, rng)
			if e.is_empty():
				continue
			var sr: Array = e.get("scale_range", [0.85, 1.15])
			var s := rng.randf_range(sr[0], sr[1])
			if scatter.blocked(p, float(e.get("collision_radius_m", 2.0)) * s + 3.0):
				continue
			_put_entry(e, p, rng.randf() * TAU, s)
		z += spacing
	# rocks, logs, stumps and mushrooms, each with the biomes it likes
	# (forest, swamp, grassland): logs and stumps rot in the swamp, rocks crop
	# out of the grassland, hay bales and stone walls belong on the farm
	for spec in [["rock", 150, Vector3(0.7, 0.2, 1.0)], ["log", 45, Vector3(1.0, 1.0, 0.15)], ["stump", 70, Vector3(1.0, 1.0, 0.3)],
			["mushroom", 110, Vector3(1.0, 0.7, 0.15)], ["prop", 90, Vector3(0.8, 0.5, 1.0)], ["cover", 60, Vector3(0.5, 0.2, 1.0)],
			["cottage", 10, Vector3(1.0, 0.3, 0.8)]]:
		var cat: String = spec[0]
		var likes: Vector3 = spec[2]
		for i in int(spec[1] * terrain.area_scale):
			var p := _random_land(2.0)
			if not _solid_ok(p, 1.5) or rng.randf() > terrain.biome_at(p.x, p.y).dot(likes):
				continue
			var e := scatter.pick(cat, rng)
			if e.is_empty():
				continue
			var sr: Array = e.get("scale_range", [0.85, 1.15])
			var s := rng.randf_range(sr[0], sr[1])
			# keep a critter-wide gap (or none) between solid things, so no
			# crevice can trap anyone: use the larger of footprint and collider
			var r := maxf(float(e.get("collision_radius_m", 0.5)), float(e.get("footprint_radius_m", 0.5)) * 0.8) * s
			if scatter.blocked(p, r + 2.2):
				continue
			_put_entry(e, p, rng.randf() * TAU, s)


func _solid_ok(p: Vector2, poi_margin: float) -> bool:
	var h := terrain.height_at(p.x, p.y)
	if h < 2.0 or h < water_level_at(Vector3(p.x, h, p.y)) - 0.6:
		return false
	if terrain.normal_at(p.x, p.y).y < 0.8:
		return false
	if terrain.control_at(p.x, p.y).g > 0.3:
		return false
	for poi in pois:
		if p.distance_to(poi.center) < poi.radius + poi_margin:
			return false
	return true


func _scatter_ground_cover(quality: int) -> void:
	var density: float = [0.35, 0.6, 1.0, 1.4][clampi(quality, 0, 3)]
	var area := PI * terrain.island_radius * terrain.island_radius
	var counts := {"grass": int(area / 8.0 * density), "flower": int(area / 50.0 * density), "bush": int(area / 85.0 * density)}
	for cat in counts:
		for i in counts[cat]:
			var p := _random_land(1.3)
			var ctl := terrain.control_at(p.x, p.y)
			if ctl.g > 0.5 or ctl.b > 0.5:
				continue   # no grass on paths and cliffs
			var h := terrain.height_at(p.x, p.y)
			if water_level_at(Vector3(p.x, h, p.y)) > h - 0.1:
				continue   # the swamp water gets reeds and lily pads instead
			var w := terrain.biome_at(p.x, p.y)
			if cat == "grass" and rng.randf() > (0.25 + ctl.r * 0.75) * lerpf(0.75, 1.0, w.z):
				continue   # thick in meadows, sparse on the forest floor
			if cat == "flower" and rng.randf() > 0.35 + w.z * 0.65:
				continue   # wildflowers are a grassland thing
			if cat == "bush" and (rng.randf() < ctl.r * 0.6 or rng.randf() > w.x + w.y * 0.7 + w.z * 0.2):
				continue   # ferns prefer the forest
			var poi := in_poi(p, 0.6)
			if not poi.is_empty() and (cat != "flower" or not (poi.buildings as Array).is_empty()):
				continue
			var e := scatter.pick(cat, rng)
			var sr: Array = e.get("scale_range", [0.8, 1.2])
			_put_entry(e, p, rng.randf() * TAU, rng.randf_range(sr[0], sr[1]))


## Reeds along the swamp's shallows and banks, lily pads out on its water.
func _scatter_swamp(quality: int) -> void:
	if _swamp_cells.is_empty():
		return
	var density: float = [0.35, 0.6, 1.0, 1.4][clampi(quality, 0, 3)]
	var reed := SwampPlants.entry("reed")
	var lilies := [SwampPlants.entry("pad"), SwampPlants.entry("pad"), SwampPlants.entry("flower")]
	var clump := FastNoiseLite.new()
	clump.seed = rng.randi()
	clump.frequency = 0.03
	var area := PI * terrain.island_radius * terrain.island_radius
	for i in int(area / 30.0 * density):
		var p := _random_land(-1.0)
		if terrain.biome_at(p.x, p.y).y < 0.35:
			continue
		var h := terrain.height_at(p.x, p.y)
		var depth := Terrain.SWAMP_LEVEL - h
		if not in_poi(p, 0.9).is_empty():
			continue
		var c := clump.get_noise_2d(p.x, p.y)
		if depth > 0.3 and _in_swamp_water(p.x, p.y):
			if c > 0.1 and rng.randf() < 0.5:
				var e: Dictionary = lilies.pick_random()
				var sr: Array = e.scale_range
				scatter.place(e, Vector3(p.x, Terrain.SWAMP_LEVEL + 0.03, p.y), rng.randf() * TAU, rng.randf_range(sr[0], sr[1]))
		elif depth > -0.7 and c > -0.25:
			scatter.place(reed, Vector3(p.x, h, p.y), rng.randf() * TAU, rng.randf_range(0.75, 1.25))


func _random_land(min_h: float) -> Vector2:
	for i in 40:
		var a := rng.randf() * TAU
		var d := sqrt(rng.randf()) * terrain.island_radius
		var p := Vector2(cos(a), sin(a)) * d
		if terrain.height_at(p.x, p.y) > min_h:
			return p
	return Vector2.ZERO


func _collect_foliage_materials() -> void:
	_foliage_materials.append_array(scatter._foliage_shader_mats)


## Grass bends away from the local player.
func set_player_position(pos: Vector3) -> void:
	for m in _foliage_materials:
		m.set_shader_parameter(&"player_pos", pos)


# ---- water, boundary, materials ------------------------------------------------------------------

func _terrain_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = TERRAIN_SHADER
	m.set_shader_parameter(&"control_map", terrain.control_texture())
	m.set_shader_parameter(&"terrain_size", Terrain.SIZE)
	m.set_shader_parameter(&"biome_map", terrain.biome_texture())
	m.set_shader_parameter(&"swamp_level", Terrain.SWAMP_LEVEL)
	var layers := {"floor": "forest_floor", "grass": "grass", "dirt": "dirt_path", "rock": "rock", "moss": "moss", "sand": "sand", "mud": "mud"}
	var fallback := {"floor": Color(0.32, 0.26, 0.17), "grass": Color(0.3, 0.45, 0.16), "dirt": Color(0.42, 0.33, 0.22),
		"rock": Color(0.45, 0.44, 0.42), "moss": Color(0.25, 0.38, 0.12), "sand": Color(0.76, 0.68, 0.5), "mud": Color(0.25, 0.2, 0.13)}
	for key in layers:
		var dir := "res://assets/textures/%s/" % layers[key]
		m.set_shader_parameter(key + "_albedo", _tex_or_color(dir + "albedo.jpg", fallback[key]))
		m.set_shader_parameter(key + "_normal", _tex_or_color(dir + "normal.png", Color(0.5, 0.5, 1.0)))
		m.set_shader_parameter(key + "_rough", _tex_or_color(dir + "roughness.jpg", Color(0.85, 0.85, 0.85)))
	var noise := NoiseTexture2D.new()
	noise.width = 256
	noise.height = 256
	noise.seamless = true
	noise.generate_mipmaps = true
	var fn := FastNoiseLite.new()
	fn.seed = rng.randi()
	fn.frequency = 0.02
	fn.fractal_octaves = 4
	noise.noise = fn
	m.set_shader_parameter(&"macro_noise", noise)
	return m


func _tex_or_color(path: String, c: Color) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path)
	var img := Image.create_empty(4, 4, false, Image.FORMAT_RGBA8)
	img.fill(c)
	return ImageTexture.create_from_image(img)


func _build_water() -> void:
	water = MeshInstance3D.new()
	water.name = "Sea"
	var plane := PlaneMesh.new()
	plane.size = Vector2(4400, 4400)
	plane.subdivide_width = 110
	plane.subdivide_depth = 110
	water.mesh = plane
	water.material_override = _water_material()
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	water.position.y = Terrain.WATER_LEVEL
	add_child(water)


func _water_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = WATER_SHADER
	m.set_shader_parameter(&"normal_a", _tex_or_color("res://assets/textures/water/normal.png", Color(0.5, 0.5, 1.0)))
	return m


## The swamp's still water: one quad per biome-map cell where the swamp
## floor dips under SWAMP_LEVEL (the levee hides the edges). The same cells
## answer water_level_at().
func _build_swamp_water() -> void:
	var n := Terrain.BIOME_RES
	var cell := Terrain.BIOME_CELL
	var half := Terrain.SIZE * 0.5
	_swamp_cells.resize(n * n)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var any := false
	for zi in n - 1:
		for xi in n - 1:
			var x := xi * cell - half
			var z := zi * cell - half
			var w := terrain.biome_at(x + cell * 0.5, z + cell * 0.5)
			if w.y < 0.25:
				continue
			var low := INF
			for k in 5:
				var q := Vector2(x, z) + Vector2([0.0, cell, 0.0, cell, cell * 0.5][k], [0.0, 0.0, cell, cell, cell * 0.5][k])
				low = minf(low, terrain.height_at(q.x, q.y))
			if low > Terrain.SWAMP_LEVEL + 0.1:
				continue
			_swamp_cells[zi * n + xi] = 1
			any = true
			var y := Terrain.SWAMP_LEVEL
			var a := Vector3(x - 0.3, y, z - 0.3)
			var b := Vector3(x + cell + 0.3, y, z - 0.3)
			var c := Vector3(x + cell + 0.3, y, z + cell + 0.3)
			var d := Vector3(x - 0.3, y, z + cell + 0.3)
			for v in [a, b, c, a, c, d]:
				st.set_normal(Vector3.UP)
				st.set_uv(Vector2(v.x, v.z))
				st.add_vertex(v)
	if not any:
		_swamp_cells.clear()
		return
	swamp_water = MeshInstance3D.new()
	swamp_water.name = "SwampWater"
	swamp_water.mesh = st.commit()
	var m := _water_material()
	m.set_shader_parameter(&"shallow_color", Color(0.3, 0.34, 0.17))
	m.set_shader_parameter(&"deep_color", Color(0.07, 0.11, 0.05))
	m.set_shader_parameter(&"depth_fade", 1.1)
	swamp_water.material_override = m
	swamp_water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(swamp_water)


func _add_pond_water(c3: Vector3, p: Dictionary) -> void:
	var mi := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(p.radius * 1.5, p.radius * 1.5)
	plane.subdivide_width = 16
	plane.subdivide_depth = 16
	mi.mesh = plane
	var m := _water_material()
	m.set_shader_parameter(&"shallow_color", Color(0.32, 0.5, 0.32))
	m.set_shader_parameter(&"deep_color", Color(0.08, 0.2, 0.12))
	m.set_shader_parameter(&"depth_fade", 1.6)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = Vector3(c3.x, p.height - 0.9, c3.z)


## Invisible wall far out at sea so nobody swims off the map.
func _build_boundary() -> void:
	var body := StaticBody3D.new()
	body.name = "Boundary"
	body.collision_layer = Layers.WORLD
	var r := terrain.island_radius + 45.0
	var n := 48
	for i in n:
		var a := TAU * i / n
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(TAU * r / n + 2.0, 200.0, 2.0)
		cs.shape = box
		cs.position = Vector3(cos(a) * r, 80.0, sin(a) * r)
		cs.rotation.y = -a + PI / 2.0
		body.add_child(cs)
	add_child(body)


# ---- loot ----------------------------------------------------------------------------------------

func _plan_loot() -> void:
	for p in pois:
		# the big buildings keep their loot indoors: crates, floor loot and
		# (usually) a treasure chest, plus a little lying around outside
		for b in p.buildings:
			var spots := (b as Building).world_loot_spots()
			for i in spots.size():
				loot_points.append({"pos": spots[i], "crate": i < 2, "poi": p.name, "yaw": rng.randf() * TAU, "inside": true})
			if (b as Building).chest_spot != Vector3.INF and rng.randf() < 0.75:
				loot_points.append({"pos": (b as Building).global_transform * (b as Building).chest_spot, "crate": false, "chest": "treasure",
					"poi": p.name, "yaw": (b as Building).rotation.y, "inside": true})
		if not (p.buildings as Array).is_empty():
			for i in 3:
				var a := rng.randf() * TAU
				var lp: Vector2 = p.center + Vector2(cos(a), sin(a)) * rng.randf_range(p.radius * 0.6, p.radius)
				loot_points.append({"pos": Vector3(lp.x, terrain.height_at(lp.x, lp.y), lp.y), "crate": false, "poi": p.name})
			continue
		for i in rng.randi_range(3, 5):
			var a := rng.randf() * TAU
			var lp: Vector2 = p.center + Vector2(cos(a), sin(a)) * rng.randf_range(4.0, p.radius * 0.85)
			if scatter.blocked(lp, 1.0):
				continue
			loot_points.append({"pos": Vector3(lp.x, terrain.height_at(lp.x, lp.y), lp.y), "crate": true, "poi": p.name, "yaw": rng.randf() * TAU})
		for i in rng.randi_range(5, 8):
			var lp: Vector2 = p.center + Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * p.radius
			loot_points.append({"pos": Vector3(lp.x, terrain.height_at(lp.x, lp.y), lp.y), "crate": false, "poi": p.name})
	# stragglers along the paths and in the woods
	for poly in paths:
		for i in range(2, poly.size() - 2, 4):
			var lp: Vector2 = poly[i] + Vector2(rng.randf_range(-3, 3), rng.randf_range(-3, 3))
			loot_points.append({"pos": Vector3(lp.x, terrain.height_at(lp.x, lp.y), lp.y), "crate": rng.randf() < 0.15, "poi": "", "yaw": rng.randf() * TAU})
	for i in int(40 * terrain.area_scale):
		var lp := _random_land(2.0)
		loot_points.append({"pos": Vector3(lp.x, terrain.height_at(lp.x, lp.y), lp.y), "crate": false, "poi": ""})
	# never leave loot inside a rock, log or cottage (it would be unreachable),
	# or under the swamp water where nobody could see it
	loot_points = loot_points.filter(func(l): return l.get("inside", false) or (
		not scatter.blocked(Vector2(l.pos.x, l.pos.z), 0.9, false) and water_level_at(l.pos) < l.pos.y + 0.2))
	_plan_treasure()


## Treasure chests: one golden chest in Treasure Grove, a chance of a chest at
## each landmark, and more tucked into the woods (beside trees and rocks, so
## whoever is unlocking has a little cover — and a little blind spot).
func _plan_treasure() -> void:
	for p in pois:
		var golden: bool = p.kit == "treasure"
		if not (p.buildings as Array).is_empty():
			continue   # (their chests are indoors)
		if golden or rng.randf() < 0.45:
			var a := rng.randf() * TAU
			var at: Vector2 = p.center if golden else p.center + Vector2(cos(a), sin(a)) * p.radius * 0.6
			if water_level_at(Vector3(at.x, terrain.height_at(at.x, at.y), at.y)) > terrain.height_at(at.x, at.y) - 0.2:
				continue
			loot_points.append({"pos": Vector3(at.x, terrain.height_at(at.x, at.y), at.y), "crate": false,
				"chest": "golden" if golden else "treasure", "poi": p.name, "yaw": rng.randf() * TAU})
	var hidden := int(10 * terrain.area_scale)
	var placed := 0
	var tries := 0
	while placed < hidden and tries < hidden * 30:
		tries += 1
		if scatter.obstacles.is_empty():
			break
		var o: Array = scatter.obstacles[rng.randi() % scatter.obstacles.size()]
		var a := rng.randf() * TAU
		var at: Vector2 = o[0] + Vector2(cos(a), sin(a)) * (float(o[1]) + 1.4)
		var ah := terrain.height_at(at.x, at.y)
		if ah < 2.0 or terrain.normal_at(at.x, at.y).y < 0.85 or scatter.blocked(at, 0.7) or water_level_at(Vector3(at.x, ah, at.y)) > ah - 0.2:
			continue
		loot_points.append({"pos": Vector3(at.x, terrain.height_at(at.x, at.y), at.y), "crate": false,
			"chest": "golden" if rng.randf() < 0.08 else "treasure", "poi": "", "yaw": a + PI})
		placed += 1


## A walkable path across the island's navmesh. Godot's default query gives
## up after 4096 polygons, which on this island cuts long trips short (the
## path then stops wherever it got closest), so this searches further.
const PATH_SEARCH_POLYGONS := 40000
static var _query: NavigationPathQueryParameters3D
static var _result: NavigationPathQueryResult3D


static func find_path(map: RID, from: Vector3, to: Vector3) -> PackedVector3Array:
	if _query == null:
		_query = NavigationPathQueryParameters3D.new()
		_query.path_search_max_polygons = PATH_SEARCH_POLYGONS
		_query.simplify_path = true
		_query.simplify_epsilon = 0.4
		_result = NavigationPathQueryResult3D.new()
	_query.map = map
	_query.start_position = from
	_query.target_position = to
	NavigationServer3D.query_path(_query, _result)
	return _result.path


## A random reachable spot on land (for AI wandering and landing targets).
## Loot must never sit inside something solid (a toy's leg, a platform, a
## wall): checked against the real colliders just before it spawns. Returns
## `pos`, or the nearest clear spot up to 4.5 m away, or Vector3.INF.
## `half` is half the item's size (a crate's box); ground spots follow the
## ground when nudged, indoor ones stay on their floor.
func clear_loot_spot(pos: Vector3, half: Vector3, on_ground := true) -> Vector3:
	var space := get_world_3d().direct_space_state
	var box := BoxShape3D.new()
	box.size = half * 2.0
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = box
	q.collision_mask = Layers.WORLD
	var ground := terrain.get_node_or_null("TerrainBody") as CollisionObject3D
	if ground:
		q.exclude = [ground.get_rid()]
	for ring: float in [0.0, 1.5, 3.0, 4.5]:
		var tries := 1 if ring == 0.0 else 8
		for k in tries:
			var a := TAU * k / tries
			var p := pos + Vector3(cos(a), 0.0, sin(a)) * ring
			if on_ground and ring > 0.0:
				p.y = terrain.height_at(p.x, p.z)
				if water_level_at(p) > p.y + 0.2:
					continue
			q.transform = Transform3D(Basis(), p + Vector3.UP * (half.y + 0.12))
			if space.intersect_shape(q, 1).is_empty():
				return p
	return Vector3.INF


## Long things (crayons, paper rolls, the race track) keep their spacing with
## a row of circles along their length, not one circle in the middle.
## `axis` is the ground direction they lie along.
func long_clear(c: Vector2, axis: Vector2, half_len: float, radius: float) -> bool:
	var n := maxi(1, ceili(half_len / radius))
	for i in range(-n, n + 1):
		if scatter.blocked(c + axis * (half_len * i / n), radius):
			return false
	return true


func add_long_obstacle(c: Vector2, axis: Vector2, half_len: float, radius: float) -> void:
	var n := maxi(1, ceili(half_len / radius))
	for i in range(-n, n + 1):
		scatter.add_obstacle(c + axis * (half_len * i / n), radius)


## The ground direction of a node's local X (or Z) axis after turning it `yaw`.
static func yaw_axis(yaw: float, local_z := false) -> Vector2:
	return Vector2(sin(yaw), cos(yaw)) if local_z else Vector2(cos(yaw), -sin(yaw))


func random_land_point(min_h := 2.0, inside_center := Vector2.ZERO, inside_radius := 1e9) -> Vector3:
	for i in 60:
		var p := _random_land(min_h)
		if p.distance_to(inside_center) <= inside_radius:
			return Vector3(p.x, terrain.height_at(p.x, p.y), p.y)
	var c := inside_center
	return Vector3(c.x, terrain.height_at(c.x, c.y), c.y)


# ---- navigation ----------------------------------------------------------------------------------

func _bake_navigation() -> void:
	var template := NavigationMesh.new()
	template.agent_radius = 0.5
	template.agent_height = 3.0   # the tallest critter (fox) stands 2.8 m
	template.agent_max_climb = 0.75
	template.agent_max_slope = 44.0
	template.cell_size = 0.5
	template.cell_height = 0.25
	template.region_min_size = 4.0
	template.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	template.geometry_collision_mask = Layers.WORLD
	var source := NavigationMeshSourceGeometryData3D.new()
	# the parser ignores the terrain collider's grid scale (Terrain.CELL), so
	# leave the terrain out of the collider scan and add the terrain surface
	# from the render chunks' own vertex arrays instead (same surface, world space)
	var ground: StaticBody3D = terrain.get_node("TerrainBody")
	ground.collision_layer = 0
	NavigationServer3D.parse_source_geometry_data(template, source, self)
	ground.collision_layer = Layers.WORLD
	for va in terrain.chunk_arrays:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = va[0]
		arrays[Mesh.ARRAY_INDEX] = va[1]
		source.add_mesh_array(arrays, Transform3D.IDENTITY)
	var tile := Terrain.SIZE / NAV_TILES
	var pending := [0]
	var baked: Array[NavigationMesh] = []
	for tz in NAV_TILES:
		for tx in NAV_TILES:
			var x0 := -Terrain.SIZE * 0.5 + tx * tile
			var z0 := -Terrain.SIZE * 0.5 + tz * tile
			var nm: NavigationMesh = template.duplicate()
			# grow the bake area by the border so polygons end exactly on the tile edge
			# and neighbouring tiles stitch together
			var border := 1.0
			nm.border_size = border
			nm.filter_baking_aabb = AABB(Vector3(x0 - border, Terrain.SEA_FLOOR - 2.0, z0 - border), Vector3(tile + border * 2.0, 160.0, tile + border * 2.0))
			var region := NavigationRegion3D.new()
			region.name = "Nav_%d_%d" % [tx, tz]
			add_child(region)
			nav_regions.append(region)
			baked.append(nm)
			pending[0] += 1
			NavigationServer3D.bake_from_source_geometry_data_async(nm, source, func(): pending[0] -= 1)
	while pending[0] > 0:
		await get_tree().process_frame
	# hand every tile to its region in one go: regions updated one by one while
	# the map was rebuilding (tiles finishing at different frames) could be
	# left out of the map
	for i in nav_regions.size():
		nav_regions[i].navigation_mesh = baked[i]
	await _wait_for_nav_map(baked)


## Don't hand the island over until the navigation map really has every tile
## (a vertex of each tile must be findable on the map). The map rebuilds on
## its own schedule, slower on slow machines; a tile still missing after a
## couple of seconds is handed to the server again.
func _wait_for_nav_map(baked: Array[NavigationMesh]) -> void:
	var map := get_world_3d().navigation_map
	var probes := {}   # region index -> a vertex of its tile
	for i in baked.size():
		var vs := baked[i].get_vertices()
		if not vs.is_empty():
			probes[i] = vs[vs.size() / 2]
	for frame in 1200:
		await get_tree().physics_frame
		if frame < 2:
			continue
		var missing := []
		for i in probes:
			var v: Vector3 = probes[i]
			if NavigationServer3D.map_get_closest_point(map, v).distance_squared_to(v) > 1.0:
				missing.append(i)
		if missing.is_empty():
			return
		if frame % 120 == 119:
			for i in missing:
				NavigationServer3D.region_set_navigation_mesh(nav_regions[i].get_rid(), baked[i])
	push_warning("navigation map still missing tiles after 20 s")
