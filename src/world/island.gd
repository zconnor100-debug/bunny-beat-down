class_name Island
extends Node3D
## Builds a whole battle-royale island from a seed: terrain, points of
## interest, paths, forest, ground cover, water, loot spots and a tiled
## navigation mesh for the AI. Generation yields between steps so a loading
## screen can animate (`progress` signal).

signal progress(fraction: float, label: String)

const TERRAIN_SHADER := preload("res://src/world/shaders/terrain.gdshader")
const WATER_SHADER := preload("res://src/world/shaders/water.gdshader")
const NAV_TILES := 6

## Points of interest: name, radius, what to build there.
const POI_KINDS := [
	{"name": "Carrot Patch", "kit": "carrot_patch", "radius": 30.0},
	{"name": "Picnic Hill", "kit": "picnic", "radius": 26.0},
	{"name": "Mushroom Ring", "kit": "mushroom_ring", "radius": 24.0},
	{"name": "Hollow Stump", "kit": "hollow_stump", "radius": 26.0},
	{"name": "Gnome Garden", "kit": "gnome_garden", "radius": 24.0},
	{"name": "Boulder Bluff", "kit": "boulders", "radius": 28.0},
	{"name": "Log Jam", "kit": "logs", "radius": 26.0},
	{"name": "Duck Pond", "kit": "pond", "radius": 26.0},
	{"name": "Cottage Hollow", "kit": "cottages", "radius": 30.0},
	{"name": "Stump Village", "kit": "stumps", "radius": 28.0},
	{"name": "Treasure Grove", "kit": "treasure", "radius": 22.0},
]

var seed_value := 1
var rng := RandomNumberGenerator.new()
var terrain: Terrain
var scatter: Scatter
var pois: Array = []          # {name, center: Vector2, radius, height}
var paths: Array = []         # PackedVector2Array polylines
var loot_points: Array = []   # {pos: Vector3, crate: bool, poi: String}
var nav_regions: Array[NavigationRegion3D] = []
var water: MeshInstance3D
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

	progress.emit(0.25, "Painting the meadows")
	await get_tree().process_frame
	terrain.build_control(paths)
	terrain.build_meshes(_terrain_material())
	terrain.build_collision()
	_build_water()
	_build_boundary()

	progress.emit(0.4, "Planting giant trees")
	await get_tree().process_frame
	_build_pois()
	_scatter_forest()
	progress.emit(0.55, "Scattering mushrooms and pebbles")
	await get_tree().process_frame
	_scatter_ground_cover(quality)
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
	var kinds := POI_KINDS.duplicate()
	var tries := 0
	while not kinds.is_empty() and tries < 4000:
		tries += 1
		var a := rng.randf() * TAU
		var d := sqrt(rng.randf()) * terrain.island_radius * 0.72
		var c := Vector2(cos(a), sin(a)) * d
		var h := terrain.height_at(c.x, c.y)
		if h < 3.0:
			continue
		var ok := true
		for p in pois:
			if c.distance_to(p.center) < 88.0:
				ok = false
				break
		if not ok:
			continue
		var k: Dictionary = kinds.pop_front()
		pois.append({"name": k.name, "kit": k.kit, "radius": k.radius, "center": c, "height": clampf(h, 3.0, 18.0)})


func _shape_pois() -> void:
	for p in pois:
		terrain.flatten(p.center, p.radius, p.height)
		if p.kit == "pond":
			terrain.flatten(p.center, p.radius * 0.55, p.height - 2.2)


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
			"pond":
				_add_pond_water(c3, p)
				_put("rubber_duck", p.center + Vector2(3, 2), rng.randf() * TAU, 1.0, true)
				_put("old_tyre", p.center + Vector2(-16, 9), rng.randf() * TAU, 1.0)
				_put("rubber_boot", p.center + Vector2(17, -6), rng.randf() * TAU, 1.0)


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


## Height of the water surface above a point (sea level, or a pond's surface).
func water_level_at(pos: Vector3) -> float:
	return _pond_level(Vector2(pos.x, pos.z))


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
			var dens := smoothstep(-0.25, 0.45, forest.get_noise_2d(p.x, p.y))
			if rng.randf() > dens * 0.85 or not _solid_ok(p, 3.5):
				continue
			var e := scatter.pick("tree", rng)
			if e.is_empty():
				continue
			var sr: Array = e.get("scale_range", [0.85, 1.15])
			var s := rng.randf_range(sr[0], sr[1])
			if scatter.blocked(p, float(e.get("collision_radius_m", 2.0)) * s + 3.0):
				continue
			_put_entry(e, p, rng.randf() * TAU, s)
		z += spacing
	# rocks, logs, stumps and mushrooms (mushrooms like to grow near trees)
	for spec in [["rock", 150], ["log", 45], ["stump", 70], ["mushroom", 110], ["prop", 90], ["cover", 60], ["cottage", 10]]:
		var cat: String = spec[0]
		for i in int(spec[1] * terrain.area_scale):
			var p := _random_land(2.0)
			if not _solid_ok(p, 1.5):
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
	if h < 2.0:
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
	var counts := {"grass": int(area / 9.0 * density), "flower": int(area / 60.0 * density), "bush": int(area / 85.0 * density)}
	for cat in counts:
		for i in counts[cat]:
			var p := _random_land(1.3)
			var ctl := terrain.control_at(p.x, p.y)
			if ctl.g > 0.5 or ctl.b > 0.5:
				continue   # no grass on paths and cliffs
			if cat == "grass" and rng.randf() > 0.25 + ctl.r * 0.75:
				continue   # thick in meadows, sparse on the forest floor
			if cat == "bush" and rng.randf() < ctl.r * 0.6:
				continue   # ferns prefer the forest
			var poi := in_poi(p, 0.6)
			if not poi.is_empty() and cat != "flower":
				continue
			var e := scatter.pick(cat, rng)
			var sr: Array = e.get("scale_range", [0.8, 1.2])
			_put_entry(e, p, rng.randf() * TAU, rng.randf_range(sr[0], sr[1]))


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
	var layers := {"floor": "forest_floor", "grass": "grass", "dirt": "dirt_path", "rock": "rock", "moss": "moss", "sand": "sand"}
	var fallback := {"floor": Color(0.32, 0.26, 0.17), "grass": Color(0.3, 0.45, 0.16), "dirt": Color(0.42, 0.33, 0.22),
		"rock": Color(0.45, 0.44, 0.42), "moss": Color(0.25, 0.38, 0.12), "sand": Color(0.76, 0.68, 0.5)}
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
	plane.size = Vector2(2400, 2400)
	plane.subdivide_width = 60
	plane.subdivide_depth = 60
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
	# never leave loot inside a rock, log or cottage (it would be unreachable)
	loot_points = loot_points.filter(func(l): return not scatter.blocked(Vector2(l.pos.x, l.pos.z), 0.9))
	_plan_treasure()


## Treasure chests: one golden chest in Treasure Grove, a chance of a chest at
## each landmark, and more tucked into the woods (beside trees and rocks, so
## whoever is unlocking has a little cover — and a little blind spot).
func _plan_treasure() -> void:
	for p in pois:
		var golden: bool = p.kit == "treasure"
		if golden or rng.randf() < 0.45:
			var a := rng.randf() * TAU
			var at: Vector2 = p.center if golden else p.center + Vector2(cos(a), sin(a)) * p.radius * 0.6
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
		if terrain.height_at(at.x, at.y) < 2.0 or terrain.normal_at(at.x, at.y).y < 0.85 or scatter.blocked(at, 0.7):
			continue
		loot_points.append({"pos": Vector3(at.x, terrain.height_at(at.x, at.y), at.y), "crate": false,
			"chest": "golden" if rng.randf() < 0.08 else "treasure", "poi": "", "yaw": a + PI})
		placed += 1


## A random reachable spot on land (for AI wandering and landing targets).
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
	template.agent_height = 2.4   # the tallest critter (fox) stands 2.24 m
	template.agent_max_climb = 0.75
	template.agent_max_slope = 44.0
	template.cell_size = 0.5
	template.cell_height = 0.25
	template.region_min_size = 4.0
	template.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	template.geometry_collision_mask = Layers.WORLD
	var source := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(template, source, self)
	var tile := Terrain.SIZE / NAV_TILES
	var pending := [0]
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
			pending[0] += 1
			NavigationServer3D.bake_from_source_geometry_data_async(nm, source, func():
				region.navigation_mesh = nm
				pending[0] -= 1)
	while pending[0] > 0:
		await get_tree().process_frame
	# let the server sync the new regions before anyone asks for a path
	for i in 6:
		await get_tree().physics_frame
