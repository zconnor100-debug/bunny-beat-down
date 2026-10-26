class_name HamsterCage
extends Island
## The second map: a battle royale inside a giant hamster tank. The floor is
## a sea of wood-shaving bedding (see CageFloor) with three biomes:
##   * BEDDING, the cage proper: the giant exercise wheel, a Habitrail "Tube
##     Town" of pods and tunnels, hamster huts, a food bowl heaped with seeds,
##     a sand bath, a shelf with a ramp, the water bottle on the glass,
##     cardboard rolls, chew blocks and food lying everywhere as cover;
##   * the LAGOON (west): spilled water over aquarium gravel round a cluster
##     of brimming water bowls, an aquarium castle, shells and plastic plants;
##   * the WINTER corner (north-east), next to the giant fridge the owner left
##     open: snow drifts, icicles, ice cubes, frozen peas, popsicles and an
##     upturned ice cream tub to hide in.
## The glass tank walls it in, the room stands round it (CageRoom), and
## everyone flies in on a toy airplane. It reuses the Island machinery for
## paths, loot, treasure, the navmesh and everything the AI asks of a map.

const CAGE_SHADER := preload("res://src/world/shaders/cage_floor.gdshader")
const BED := 0
const LAGOON := 1
const WINTER := 2

## The landmarks, laid out like a real arena map (each match jitters them a
## little): name, what to build, radius, where (x, z).
const CAGE_POIS := [
	{"name": "The Big Wheel", "kit": "wheel", "radius": 30.0, "at": Vector2(40, 30), "biome": BED},
	{"name": "Tube Town", "kit": "tubes", "radius": 50.0, "at": Vector2(-70, -230), "biome": BED},
	{"name": "Hamster Hut", "kit": "hut", "radius": 24.0, "at": Vector2(170, 250), "biome": BED},
	{"name": "Chew Chalet", "kit": "hut", "radius": 24.0, "at": Vector2(-250, -320), "biome": BED},
	{"name": "Seed Bowl", "kit": "seed_bowl", "radius": 24.0, "at": Vector2(120, -150), "biome": BED},
	{"name": "Sand Bath", "kit": "sand", "radius": 24.0, "at": Vector2(370, 290), "biome": BED},
	{"name": "Shelf Overlook", "kit": "platform", "radius": 32.0, "at": Vector2(-100, 320), "biome": BED},
	{"name": "Hamster Gym", "kit": "gym", "radius": 56.0, "at": Vector2(-60, 150), "biome": BED},
	{"name": "Water Bottle Falls", "kit": "bottle", "radius": 22.0, "at": Vector2(250, 372), "biome": BED},
	{"name": "Paper Roll Pile", "kit": "rolls", "radius": 30.0, "at": Vector2(260, 60), "biome": BED},
	{"name": "Chew Block Yard", "kit": "blocks", "radius": 26.0, "at": Vector2(-160, -110), "biome": BED},
	{"name": "Snack Stash", "kit": "treasure", "radius": 20.0, "at": Vector2(480, 335), "biome": BED},
	{"name": "Bowl Lagoon", "kit": "bowls", "radius": 70.0, "at": Vector2(-350, 110), "biome": LAGOON},
	{"name": "Castle Cove", "kit": "castle", "radius": 30.0, "at": Vector2(-420, -50), "biome": LAGOON},
	{"name": "Shell Shallows", "kit": "shells", "radius": 30.0, "at": Vector2(-320, 320), "biome": LAGOON},
	{"name": "Ice Cube Field", "kit": "ice", "radius": 36.0, "at": Vector2(330, -110), "biome": WINTER},
	{"name": "Ice Cream Igloo", "kit": "igloo", "radius": 26.0, "at": Vector2(440, -300), "biome": WINTER},
	{"name": "Frozen Pea Patch", "kit": "peas", "radius": 28.0, "at": Vector2(220, -300), "biome": WINTER},
	{"name": "Popsicle Point", "kit": "popsicles", "radius": 26.0, "at": Vector2(480, -120), "biome": WINTER},
]
const BOWL_COLOURS := [&"pink", &"mint", &"sky", &"lemon", &"lilac"]

## Water bowls: {center: Vector2, r, rim, base, level, inner} (inner = the
## water's radius at its level).
var bowls: Array = []
## Where each Tube Town pod and tube stands, for tests: [Vector3 ...].
var pods: Array = []


func _init() -> void:
	drop_vehicle = &"plane"
	map_id = "cage"
	map_title = "Hamster Cage"
	music_slot = "match_cage"


func generate(seed_: int, quality := 2, bake_nav := true) -> void:
	current = self
	seed_value = seed_
	rng.seed = seed_
	var cf := CageFloor.new()
	terrain = cf
	terrain.name = "Terrain"
	add_child(terrain)
	terrain.setup(seed_)
	scatter = Scatter.new()
	scatter.name = "Scatter"
	add_child(scatter)
	scatter.load_manifest()

	progress.emit(0.05, "Laying fresh bedding")
	await get_tree().process_frame
	terrain.generate_heights()
	_choose_cage_pois()
	_shape_cage_pois()
	_plan_paths()
	terrain.compute_normals()

	progress.emit(0.25, "Fluffing the bedding")
	await get_tree().process_frame
	terrain.build_control(paths)
	terrain.build_meshes(_cage_material())
	terrain.build_collision()
	_build_lagoon_water()

	progress.emit(0.35, "Polishing the glass")
	await get_tree().process_frame
	CageRoom.build_tank(self, rng)
	CageRoom.build_room(self, rng)
	CageRoom.build_fridge(self, rng)
	CageRoom.build_icicles(self, rng)

	progress.emit(0.45, "Setting out the toys")
	await get_tree().process_frame
	_build_cage_pois()
	_build_lookouts()
	progress.emit(0.55, "Scattering seeds and snacks")
	await get_tree().process_frame
	_scatter_cage(quality)
	scatter.flush_batches(quality)
	_collect_foliage_materials()
	_plan_loot()

	if bake_nav:
		progress.emit(0.7, "Teaching critters the tunnels")
		await get_tree().process_frame
		await _bake_navigation()
	progress.emit(1.0, "Ready")
	ready_to_play = true


# ---- landmarks -------------------------------------------------------------------------------

func _choose_cage_pois() -> void:
	for k in CAGE_POIS:
		var c: Vector2 = k.at + Vector2(rng.randf_range(-12, 12), rng.randf_range(-12, 12))
		var h := terrain.height_at(c.x, c.y)
		var target := clampf(h, CageFloor.BEDDING + 0.5, CageFloor.BEDDING + 6.0)
		match k.kit:
			"castle":
				target = CageFloor.LAGOON_LEVEL + 0.7     # a gravel island in the lagoon
			"bowls", "shells":
				target = h
			"bottle":
				c.y = CageFloor.HZ - 28.0                 # right under the bottle on the south glass
		pois.append({"name": k.name, "kit": k.kit, "radius": k.radius, "center": c, "height": target,
			"biome": k.biome, "buildings": []})


func _shape_cage_pois() -> void:
	var cf := terrain as CageFloor
	for p in pois:
		match p.kit:
			"bowls":
				_plan_bowls(p)
			"shells":
				pass
			"tubes", "hut", "castle", "igloo", "wheel", "platform", "seed_bowl", "sand", "gym":
				terrain.flatten(p.center, p.radius * 0.85, p.height, 1.0, false)
			_:
				terrain.flatten(p.center, p.radius, p.height)
		if p.kit == "sand":
			cf.sand_spots.append([p.center, 16.0])
		if p.kit == "seed_bowl":
			# a ramp of bedding up to the rim, and nothing poking up inside it
			var dir: Vector2 = (Vector2.ZERO - p.center).normalized()
			cf.ramp(p.center + dir * 30.0, p.center + dir * 12.6, 9.0, p.height, p.height + 2.15)
			_dig(p.center, 12.0, p.height)
	for b in bowls:
		_dig(b.center, b.r - 0.6, b.base - 0.6)


## The lagoon's water bowls: four or five of different sizes and colours,
## each sunk into the gravel with a ramp of gravel up to its rim.
func _plan_bowls(p: Dictionary) -> void:
	var cf := terrain as CageFloor
	var n := 5
	var base_a := rng.randf() * TAU
	for i in n:
		var a := base_a + TAU * i / n + rng.randf_range(-0.25, 0.25)
		var d := 0.0 if i == 0 else rng.randf_range(36.0, 48.0)
		if i == 0:
			a = 0.0
		var r := rng.randf_range(15.0, 18.0) if i == 0 else rng.randf_range(10.0, 14.0)
		var c: Vector2 = p.center + Vector2(cos(a), sin(a)) * d
		var rim := rng.randf_range(3.0, 3.8)
		var base := CageFloor.LAGOON_LEVEL - 1.0
		var level := base + rim - 0.55
		bowls.append({"center": c, "r": r, "rim": rim, "base": base, "level": level,
			"inner": CageProps.bowl_inner_radius(r, rim, rim - 0.55), "colour": BOWL_COLOURS[i % BOWL_COLOURS.size()]})
		# the gravel ramp up to the rim, from the side facing out of the cluster
		var out: Vector2 = (c - p.center).normalized() if i > 0 else Vector2(cos(base_a + PI / n), sin(base_a + PI / n))
		cf.ramp(c + out * (r + 18.0), c + out * (r - 0.4), 8.0, CageFloor.LAGOON_LEVEL - 0.6, base + rim - 0.05)


## Lower the ground inside a circle to at most `y` (hard edge): under a bowl.
func _dig(c: Vector2, radius: float, y: float) -> void:
	var half := Terrain.SIZE * 0.5
	var cell := Terrain.CELL
	var n := Terrain.RES
	for zi in range(maxi(0, int((c.y - radius + half) / cell)), mini(n - 1, int((c.y + radius + half) / cell) + 1) + 1):
		for xi in range(maxi(0, int((c.x - radius + half) / cell)), mini(n - 1, int((c.x + radius + half) / cell) + 1) + 1):
			if Vector2(xi * cell - half, zi * cell - half).distance_to(c) <= radius:
				var i := zi * n + xi
				terrain.heights[i] = minf(terrain.heights[i], y)


func _build_cage_pois() -> void:
	for p in pois:
		var at: Vector2 = p.center
		match p.kit:
			"gym":
				_place_kit(p, CageGym.gym(rng), at, _face_centre(at) + PI * 0.5)
			"wheel":
				_prop(CageProps.wheel(rng), at, _face_centre(at))
				for i in 6:
					_scatter_one(CageProps.sunflower_seed(rng), at, 18.0, 30.0, 1.6)
			"tubes":
				_build_tube_town(p)
			"hut":
				_place_kit(p, CageKit.make_kit(CageKit.Kind.HUT, rng), at, _face_centre(at))
				for i in 3:
					_scatter_one(CageProps.block(rng, rng.randf_range(2.5, 3.5)), at, 15.0, 22.0, 2.4)
			"seed_bowl":
				var sb := _prop(CageProps.seed_bowl(rng), at, rng.randf() * TAU)
				scatter.reserve(at, 14.0)
				for i in 5:
					_scatter_one(CageProps.sunflower_seed(rng), at, 16.0, 24.0, 1.6)
				sb.set_meta(&"poi", p.name)
			"sand":
				_prop(CageProps.sand_tray(rng, 16.6), at, 0.0, NAN, false)
				for i in 2:
					_scatter_one(CageProps.hamster_ball(rng, 5.0), at, 18.0, 24.0, 5.5)
			"platform":
				var yaw := _face_centre(at)
				_place_kit(p, CageProps.platform(rng, 9.0), at, yaw)
				_scatter_one(CageProps.block(rng, 3.0), at, 14.0, 20.0, 2.2)
			"bottle":
				var bottle := CageProps.water_bottle(rng)
				_prop(bottle, Vector2(at.x, CageFloor.HZ - 10.5), PI, NAN, false)
				_drips(bottle)
				var drip: Vector3 = bottle.to_global(bottle.get_meta(&"drip_from"))
				_puddle(Vector2(drip.x, drip.z))
			"rolls":
				_build_roll_pile(p)
			"blocks":
				for i in 12:
					var s := rng.randf_range(2.5, 5.0)
					var b := _scatter_one(CageProps.block(rng, s), at, 3.0, p.radius * 0.9, s * 0.8)
					if b and rng.randf() < 0.3:
						var top := CageProps.block(rng, s * 0.7)
						add_child(top)
						top.global_position = b.global_position + Vector3.UP * s
			"treasure":
				for i in 10:
					_scatter_one(CageProps.sunflower_seed(rng, rng.randf_range(1.8, 2.6)), at, 4.0, 13.0, 1.4)
				for i in 5:
					_scatter_one(CageProps.pellet(rng), at, 4.0, 14.0, 1.4)
			"bowls":
				_build_bowls()
			"castle":
				_place_kit(p, CageKit.make_kit(CageKit.Kind.CASTLE, rng), at, _face_centre(at))
				for i in 4:
					_scatter_one(CageProps.shell(rng, rng.randf_range(3.0, 4.5)), at, 20.0, 30.0, 3.5)
			"shells":
				for i in 7:
					_scatter_one(CageProps.shell(rng, rng.randf_range(3.0, 5.0)), at, 2.0, p.radius, 4.0, true)
			"ice":
				for i in 14:
					var s := rng.randf_range(4.0, 8.0)
					var cube := _scatter_one(CageProps.ice_cube(rng, s), at, 3.0, p.radius, s * 0.75)
					if cube and rng.randf() < 0.25:
						var top := CageProps.ice_cube(rng, s * 0.7)
						add_child(top)
						top.global_position = cube.global_position + Vector3.UP * s * 1.04   # (on the frost, not in it)
			"igloo":
				_place_kit(p, CageKit.make_kit(CageKit.Kind.TUB, rng), at, _face_centre(at))
				for i in 4:
					_scatter_one(CageProps.popsicle(rng), at, 17.0, 26.0, 5.0)
			"peas":
				for i in 18:
					_scatter_one(CageProps.pea(rng, rng.randf_range(1.3, 2.2)), at, 2.0, p.radius, 2.0)
			"popsicles":
				for i in 7:
					_scatter_one(CageProps.popsicle(rng), at, 2.0, p.radius, 5.0)


## Lookout perches on stilts around the cage (high ground with a ramp up),
## each counted with its nearest landmark for loot.
const LOOKOUTS := 5

func _build_lookouts() -> void:
	var colours := [&"pink", &"teal", &"orange", &"purple", &"blue", &"yellow"]
	var made := 0
	for attempt in 200:
		if made >= LOOKOUTS:
			break
		var at := _random_land(CageFloor.BEDDING - 1.0)
		var height := 9.0 + snappedf(rng.randf_range(0.0, 6.0), 2.0)   # (the heights the lookout models come in)
		var kit := CageGym.lookout(rng, height, colours[made % colours.size()])
		var yaw := rng.randf() * TAU
		# the deck and the far end of the ramp both need room
		var reach := kit.footprint
		if not _cage_spot_ok(at, reach) or not in_poi(at, 1.6).is_empty() or terrain.normal_at(at.x, at.y).y < 0.95:
			kit.free()
			continue
		var near := pois[0] as Dictionary
		for p in pois:
			if (p.center as Vector2).distance_to(at) < (near.center as Vector2).distance_to(at):
				near = p
		_place_kit(near, kit, at, yaw)
		scatter.add_obstacle(at, reach)
		made += 1


## Tube Town: four round pods in a diamond, joined in a loop by Habitrail
## tubes, each pod with a ground door facing out.
func _build_tube_town(p: Dictionary) -> void:
	var yaw := rng.randf() * TAU
	var spots: Array[Vector2] = []
	for i in 4:
		var a := yaw + TAU * i / 4.0
		spots.append(p.center + Vector2(cos(a), sin(a)) * 27.0)
	var colours := [&"teal", &"purple", &"orange", &"lime"]
	for i in 4:
		var here: Vector2 = spots[i]
		# each pod is built facing out (+X), doors out and to both neighbours,
		# then turned to face out from the middle
		var out := atan2(here.y - p.center.y, here.x - p.center.x)
		var pod := CageProps.pod(rng, colours[i], CageProps.TOWN_DOORS, "cage/pod")
		pod.loot_spots = [Vector3(0, pod.floor_y, 0), Vector3(3.5, pod.floor_y, -2.5)]
		_place_kit(p, pod, here, -out)
		pods.append(Vector3(here.x, p.height, here.y))
	for i in 4:
		var a: Vector2 = spots[i]
		var b: Vector2 = spots[(i + 1) % 4]
		var d := (b - a).normalized()
		var length := a.distance_to(b) - CageProps.POD_R * 2.0 + 1.2
		var t := CageProps.tube(rng, colours[(i + 2) % 4], length, "cage/tube" if absf(length - CageProps.TOWN_TUBE) < 0.05 else "")
		_prop(t, (a + b) * 0.5, atan2(d.x, d.y), p.height, true, false)
		scatter.reserve((a + b) * 0.5, length * 0.5)


## Paper Roll Pile: toilet-paper and paper-towel tubes lying about, three of
## them stacked in a pyramid.
func _build_roll_pile(p: Dictionary) -> void:
	var yaw := rng.randf() * TAU
	var across := Vector2(cos(yaw), -sin(yaw))
	var r := 2.7
	for k in [-1.0, 1.0]:
		_prop(CageProps.roll(rng, 9.0, r), p.center + across * (r + 0.35) * k, yaw, p.height)
	var top := CageProps.roll(rng, 9.0, r)
	add_child(top)
	top.global_position = Vector3(p.center.x, p.height + sqrt(3.0) * (r + 0.35), p.center.y)
	top.rotation.y = yaw
	add_long_obstacle(p.center, yaw_axis(yaw, true), 4.5, r * 2.0 + 0.5)
	for i in 5:
		var length := 24.0 if i < 2 else 9.0
		var a := rng.randf() * TAU
		var at: Vector2 = p.center + Vector2(cos(a), sin(a)) * rng.randf_range(16.0, 28.0)
		var ryaw := rng.randf() * TAU
		# a roll lies along its local Z: keep its whole length clear
		if not long_clear(at, yaw_axis(ryaw, true), length * 0.5, r + 2.0):
			continue
		_prop(CageProps.roll(rng, length, r), at, ryaw, NAN, true, false)
		add_long_obstacle(at, yaw_axis(ryaw, true), length * 0.5, r + 0.5)


func _build_bowls() -> void:
	for b in bowls:
		var kit := CageProps.bowl(rng, b.colour, b.r, b.rim)
		add_child(kit)
		kit.global_position = Vector3(b.center.x, b.base, b.center.y)
		kit.rotation.y = rng.randf() * TAU
		scatter.add_obstacle(b.center, b.r + 1.0)
		_water_disc(Vector3(b.center.x, b.level, b.center.y), b.inner + 0.25)


# ---- placing things ---------------------------------------------------------------------------

## Add a prop standing on the ground at `at` (or at height `y`), turned `yaw`.
## Solid props keep other scatter clear of their footprint.
func _prop(kit: Node3D, at: Vector2, yaw: float, y := NAN, solid := true, obstacle := true) -> Node3D:
	add_child(kit)
	var h := terrain.height_at(at.x, at.y) if is_nan(y) else y
	kit.global_position = Vector3(at.x, h, at.y)
	kit.rotation.y = yaw
	if obstacle and kit is Building:
		var fp := (kit as Building).footprint
		if solid:
			scatter.add_obstacle(at, fp)
		else:
			scatter.reserve(at, fp)
	return kit


## A walk-in kit (hut, castle, tub, pod, platform): its loot spots go indoors.
func _place_kit(p: Dictionary, kit: Building, at: Vector2, yaw: float) -> Building:
	kit.name = "%s_%d" % [kit.name, buildings.size()]
	add_child(kit)
	kit.global_position = Vector3(at.x, terrain.height_at(at.x, at.y), at.y)
	kit.rotation.y = yaw
	scatter.reserve(at, kit.footprint)
	buildings.append(kit)
	(p.buildings as Array).append(kit)
	return kit


## A prop at a random free spot in a ring round `c`, on dry ground; null if
## no spot was found. `radius` is its spacing radius.
func _scatter_one(kit: Node3D, c: Vector2, r0: float, r1: float, radius: float, wet_ok := false) -> Node3D:
	for attempt in 14:
		var a := rng.randf() * TAU
		var at := c + Vector2(cos(a), sin(a)) * rng.randf_range(r0, r1)
		var h := terrain.height_at(at.x, at.y)
		if not (terrain as CageFloor).inside(at.x, at.y, 6.0) or scatter.blocked(at, radius):
			continue
		if not wet_ok and water_level_at(Vector3(at.x, h, at.y)) > h - 0.3:
			continue
		add_child(kit)
		kit.global_position = Vector3(at.x, h, at.y)
		kit.rotation.y = rng.randf() * TAU
		scatter.add_obstacle(at, radius)
		return kit
	kit.free()
	return null


func _water_disc(c: Vector3, r: float) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var seg := 40
	for i in seg:
		var a0 := TAU * i / seg
		var a1 := TAU * (i + 1) / seg
		for v in [Vector3.ZERO, Vector3(cos(a1), 0, sin(a1)) * r, Vector3(cos(a0), 0, sin(a0)) * r]:
			st.set_normal(Vector3.UP)
			st.set_uv(Vector2(c.x + v.x, c.z + v.z))
			st.add_vertex(v)
	var mi := MeshInstance3D.new()
	mi.name = "BowlWater"
	mi.mesh = st.commit()
	var m := _water_material()
	m.set_shader_parameter(&"shallow_color", Color(0.45, 0.78, 0.92))
	m.set_shader_parameter(&"deep_color", Color(0.12, 0.42, 0.62))
	m.set_shader_parameter(&"depth_fade", 2.2)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = c


func _puddle(at: Vector2) -> void:
	var h := terrain.height_at(at.x, at.y)
	_water_disc(Vector3(at.x, h + 0.08, at.y), 5.0)


## Drops falling from the bottle's spout onto the bedding.
func _drips(bottle: Node3D) -> void:
	if not bottle.has_meta(&"drip_from"):
		return
	var p := GPUParticles3D.new()
	p.name = "Drips"
	p.amount = 6
	p.lifetime = 2.2
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3.DOWN
	pm.spread = 2.0
	pm.initial_velocity_min = 0.5
	pm.initial_velocity_max = 1.0
	pm.gravity = Vector3(0, -9.0, 0)
	p.process_material = pm
	var drop := SphereMesh.new()
	drop.radius = 0.5
	drop.height = 1.3
	drop.material = CageKit.mat(&"bottle_water")
	p.draw_pass_1 = drop
	p.visibility_aabb = AABB(Vector3(-4, -40, -4), Vector3(8, 44, 8))
	bottle.add_child(p)
	p.position = bottle.get_meta(&"drip_from")


# ---- ground cover and food everywhere ---------------------------------------------------------

func _scatter_cage(quality: int) -> void:
	var density: float = [0.35, 0.6, 1.0, 1.4, 1.75][clampi(quality, 0, 4)]
	# solid food and toys: [builder, count, spacing radius, biome weights it likes (bed, lagoon, winter)]
	var solids := [
		[func(): return CageProps.sunflower_seed(rng, rng.randf_range(1.8, 2.8)), 170, 1.6, Vector3(1.0, 0.1, 0.0)],
		[func(): return CageProps.pellet(rng, rng.randf_range(2.0, 3.0)), 80, 1.6, Vector3(1.0, 0.0, 0.0)],
		[func(): return CageProps.broccoli(rng, rng.randf_range(0.8, 1.3)), 26, 3.4, Vector3(1.0, 0.2, 0.0)],
		[func(): return CageProps.carrot_stick(rng), 18, 3.6, Vector3(1.0, 0.0, 0.1)],
		[func(): return CageProps.corn_cob(rng), 14, 4.2, Vector3(1.0, 0.0, 0.0)],
		[func(): return CageProps.apple_slice(rng), 12, 3.0, Vector3(1.0, 0.0, 0.0)],
		[func(): return CageProps.block(rng, rng.randf_range(2.5, 4.5)), 26, 3.2, Vector3(1.0, 0.0, 0.0)],
		[func(): return CageProps.roll(rng, 9.0, 2.7), 10, 5.0, Vector3(1.0, 0.0, 0.0)],
		[func(): return CageProps.hamster_ball(rng, rng.randf_range(4.5, 6.0)), 4, 6.0, Vector3(1.0, 0.0, 0.0)],
		[func(): return CageGym.bendy_bridge(rng, rng.randf_range(15.0, 20.0)), 6, 11.0, Vector3(1.0, 0.1, 0.3)],
		[func(): return CageGym.coconut(rng, rng.randf_range(4.5, 6.0)), 6, 7.5, Vector3(1.0, 0.4, 0.0)],
		[func(): return CageGym.chew_sticks(rng), 10, 7.0, Vector3(1.0, 0.0, 0.2)],
		[func(): return CageGym.egg_carton(rng), 5, 14.0, Vector3(1.0, 0.0, 0.0)],
		[func(): return CageProps.pea(rng, rng.randf_range(1.2, 2.0)), 60, 2.0, Vector3(0.0, 0.0, 1.0)],
		[func(): return CageProps.ice_cube(rng, rng.randf_range(3.0, 6.5)), 34, 4.0, Vector3(0.0, 0.0, 1.0)],
		[func(): return CageProps.popsicle(rng), 10, 5.0, Vector3(0.0, 0.0, 1.0)],
		[func(): return CageProps.shell(rng, rng.randf_range(2.5, 4.0)), 18, 3.0, Vector3(0.0, 1.0, 0.0)],
	]
	for s in solids:
		var made := 0
		for i in int(s[1]) * 6:
			if made >= int(s[1]):
				break
			var p := _random_land(CageFloor.BEDDING - 2.0)
			var likes: Vector3 = s[3]
			if rng.randf() > terrain.biome_at(p.x, p.y).dot(likes) or not _cage_spot_ok(p, float(s[2])):
				continue
			var kit: Node3D = (s[0] as Callable).call()
			add_child(kit)
			kit.global_position = Vector3(p.x, terrain.height_at(p.x, p.y), p.y)
			kit.rotation.y = rng.randf() * TAU
			scatter.add_obstacle(p, float(s[2]))
			made += 1
	# batched: bedding fluff and loose seeds, snow clumps, plastic plants in the lagoon
	var area := CageFloor.HX * CageFloor.HZ * 4.0
	var batched := [[CageProps.entry("fluff"), area / 220.0, Vector3(1.0, 0.0, 0.1)], [CageProps.entry("seeds"), area / 110.0, Vector3(1.0, 0.0, 0.0)],
		[CageProps.entry("snowball"), area / 110.0, Vector3(0.0, 0.0, 1.0)], [CageProps.entry("plant"), area / 160.0, Vector3(0.0, 1.0, 0.0)]]
	for b in batched:
		var e: Dictionary = b[0]
		var likes: Vector3 = b[2]
		for i in int(float(b[1]) * density):
			var p := Vector2(rng.randf_range(-CageFloor.HX + 4.0, CageFloor.HX - 4.0), rng.randf_range(-CageFloor.HZ + 4.0, CageFloor.HZ - 4.0))
			var w := terrain.biome_at(p.x, p.y)
			if rng.randf() > w.dot(likes):
				continue
			var h := terrain.height_at(p.x, p.y)
			var wet := water_level_at(Vector3(p.x, h, p.y)) > h - 0.1
			if (e.category == "reed") != wet and not (e.category == "reed" and w.y > 0.5 and rng.randf() < 0.3):
				continue
			var sr: Array = e.scale_range
			var sc := rng.randf_range(sr[0], sr[1])
			if not in_poi(p, 0.7).is_empty() or scatter.blocked(p, float(e.get("footprint_radius_m", 1.0)) * sc):
				continue
			if terrain.control_at(p.x, p.y).g > 0.4 or terrain.control_at(p.x, p.y).a > 0.4:
				continue   # nothing grows on the trails or in the sand bath
			scatter.place(e, Vector3(p.x, h, p.y), rng.randf() * TAU, sc)


func _cage_spot_ok(p: Vector2, radius: float) -> bool:
	var h := terrain.height_at(p.x, p.y)
	if water_level_at(Vector3(p.x, h, p.y)) > h - 0.3:
		return false
	if terrain.normal_at(p.x, p.y).y < 0.85 or terrain.control_at(p.x, p.y).g > 0.3:
		return false
	if not (terrain as CageFloor).inside(p.x, p.y, 8.0):
		return false
	for poi in pois:
		if p.distance_to(poi.center) < poi.radius + 2.0:
			return false
	return not scatter.blocked(p, radius + 2.2)


# ---- materials and water ----------------------------------------------------------------------

func _cage_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = CAGE_SHADER
	m.set_shader_parameter(&"control_map", terrain.control_texture())
	m.set_shader_parameter(&"biome_map", terrain.biome_texture())
	m.set_shader_parameter(&"terrain_size", Terrain.SIZE)
	m.set_shader_parameter(&"lagoon_level", CageFloor.LAGOON_LEVEL)
	var layers := {"bedding": "bedding", "snow": "snow", "pebble": "pebbles", "sand": "sand"}
	var fallback := {"bedding": Color(0.85, 0.72, 0.5), "snow": Color(0.95, 0.97, 1.0), "pebble": Color(0.6, 0.62, 0.66), "sand": Color(0.86, 0.78, 0.55)}
	for key in layers:
		var dir := "res://assets/textures/%s/" % layers[key]
		m.set_shader_parameter(key + "_albedo", _tex_or_color(dir + "albedo.jpg", fallback[key]))
		m.set_shader_parameter(key + "_normal", _tex_or_color(dir + "normal.png", Color(0.5, 0.5, 1.0)))
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


## The lagoon's still water: like the island's swamp, one quad per biome cell
## whose floor dips under LAGOON_LEVEL (never inside a bowl: those have their
## own water).
func _build_lagoon_water() -> void:
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
			var mid := Vector2(x + cell * 0.5, z + cell * 0.5)
			if terrain.biome_at(mid.x, mid.y).y < 0.25 or not (terrain as CageFloor).inside(mid.x, mid.y):
				continue
			var in_bowl := false
			for b in bowls:
				if mid.distance_to(b.center) < b.r + cell:
					in_bowl = true
			if in_bowl:
				continue
			var low := INF
			for k in 5:
				var q := Vector2(x, z) + Vector2([0.0, cell, 0.0, cell, cell * 0.5][k], [0.0, 0.0, cell, cell, cell * 0.5][k])
				low = minf(low, terrain.height_at(q.x, q.y))
			if low > CageFloor.LAGOON_LEVEL + 0.1:
				continue
			_swamp_cells[zi * n + xi] = 1
			any = true
			var y := CageFloor.LAGOON_LEVEL
			var a := Vector3(x - 0.3, y, z - 0.3)
			var b2 := Vector3(x + cell + 0.3, y, z - 0.3)
			var c := Vector3(x + cell + 0.3, y, z + cell + 0.3)
			var d := Vector3(x - 0.3, y, z + cell + 0.3)
			for v in [a, b2, c, a, c, d]:
				st.set_normal(Vector3.UP)
				st.set_uv(Vector2(v.x, v.z))
				st.add_vertex(v)
	if not any:
		_swamp_cells.clear()
		return
	swamp_water = MeshInstance3D.new()
	swamp_water.name = "LagoonWater"
	swamp_water.mesh = st.commit()
	var m := _water_material()
	m.set_shader_parameter(&"shallow_color", Color(0.42, 0.78, 0.86))
	m.set_shader_parameter(&"deep_color", Color(0.1, 0.4, 0.55))
	m.set_shader_parameter(&"depth_fade", 1.8)
	swamp_water.material_override = m
	swamp_water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(swamp_water)


func water_level_at(pos: Vector3) -> float:
	var level := -100.0
	if _in_swamp_water(pos.x, pos.z):
		level = CageFloor.LAGOON_LEVEL
	var p := Vector2(pos.x, pos.z)
	for b in bowls:
		if p.distance_to(b.center) < b.inner and pos.y > b.base - 0.5:
			level = maxf(level, b.level)
	return level


# ---- the map's shape, colours and light ---------------------------------------------------------

func _random_land(min_h: float) -> Vector2:
	for i in 60:
		var p := Vector2(rng.randf_range(-CageFloor.HX + 25.0, CageFloor.HX - 25.0), rng.randf_range(-CageFloor.HZ + 25.0, CageFloor.HZ - 25.0))
		var h := terrain.height_at(p.x, p.y)
		if h > min_h and water_level_at(Vector3(p.x, h, p.y)) < h - 0.2:
			return p
	return Vector2(0, 0)


func play_bounds() -> Rect2:
	return Rect2(-CageFloor.HX, -CageFloor.HZ, CageFloor.HX * 2.0, CageFloor.HZ * 2.0)


func map_color(x: float, z: float) -> Color:
	var cf := terrain as CageFloor
	if not cf.inside(x, z):
		return Color("5a4330") if not cf.inside(x, z, -6.0) else Color("1c1c1e")
	var h := terrain.height_at(x, z)
	var wl := water_level_at(Vector3(x, h, z))
	if wl > h + 0.05:
		return Color("6cc0dc").lerp(Color("2f7fa8"), clampf((wl - h) / 2.5, 0.0, 1.0))
	var w := terrain.biome_at(x, z)
	var ctl := terrain.control_at(x, z)
	var c := Color("e6cf9f")
	c = c.lerp(Color("f6f1e6"), ctl.r)
	c = c.lerp(Color("b48f5c"), ctl.g * 0.8)
	c = c.lerp(Color("eadb8a"), ctl.a)
	c = c.lerp(Color("a9b7c2"), smoothstep(0.3, 0.6, w.y))
	c = c.lerp(Color("f2f7fc"), smoothstep(0.35, 0.65, w.z))
	var nrm := terrain.normal_at(x, z)
	return c * (0.75 + 0.3 * clampf(nrm.dot(Vector3(-0.5, 0.75, -0.4).normalized()), 0.0, 1.0))


## Daylight through the room's west window, clearer indoor air.
func tune_lighting(lighting: WorldLighting) -> void:
	var d := Vector3(1.0, -0.8, 0.3).normalized()
	lighting.sun.global_basis = Basis.looking_at(d, Vector3.UP)
	lighting.sun.light_energy = 1.2
	lighting.env.fog_density = 0.00022
	lighting.env.fog_light_color = Color(0.93, 0.89, 0.82)
	lighting.env.fog_aerial_perspective = 0.1
	lighting.env.ambient_light_energy = 1.0
	lighting.make_indoor()
