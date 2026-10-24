class_name ToyBox
extends Island
## The third map, Toy Box Bash: a battle royale on a kid's bedroom floor.
## Oak floorboards with a printed town play rug in the middle (see ToyFloor),
## a corner of pillow hills under a patchwork quilt, and a spill where the
## fishbowl's water slopped out. A wooden TOY TRAIN loops the whole room on
## its own track: ride it, or get bonked by it (see ToyTrain). Landmarks:
## the three-storey Dollhouse Manor, Brick City, an alphabet-block castle,
## the Loop-de-Loop race track, Crayon Canyon, Domino Run, a tea party, the
## fishbowl (swim in it), the pillow fort, a giant teddy, the toy chest, a
## piggy bank and a toy rocket. Everyone flies in on a paper airplane.

const TOY_SHADER := preload("res://src/world/shaders/toy_floor.gdshader")
const FLOORB := 0
const SPILL := 1
const PILLOWS := 2
const TRACK_RECT := Rect2(-460.0, -330.0, 920.0, 660.0)
const TRACK_CORNER := 110.0
const BOWL_RIM := 26.0

const TOY_POIS := [
	{"name": "Dollhouse Manor", "kit": "dollhouse", "radius": 30.0, "at": Vector2(170, -120), "biome": FLOORB},
	{"name": "Brick City", "kit": "bricks", "radius": 60.0, "at": Vector2(300, 150), "biome": FLOORB},
	{"name": "Loop-de-Loop", "kit": "racetrack", "radius": 34.0, "at": Vector2(40, 150), "biome": FLOORB},
	{"name": "Train Station", "kit": "station", "radius": 26.0, "at": Vector2(100, 320.4), "biome": FLOORB},
	{"name": "Block Castle", "kit": "castle", "radius": 30.0, "at": Vector2(-180, 40), "biome": FLOORB},
	{"name": "Crayon Canyon", "kit": "crayons", "radius": 32.0, "at": Vector2(-150, -190), "biome": FLOORB},
	{"name": "Domino Run", "kit": "dominoes", "radius": 32.0, "at": Vector2(-20, -60), "biome": FLOORB},
	{"name": "Tea Party", "kit": "tea", "radius": 26.0, "at": Vector2(380, -385), "biome": FLOORB},
	{"name": "Launch Pad", "kit": "rocket", "radius": 22.0, "at": Vector2(525, -230), "biome": FLOORB},
	{"name": "Piggy Bank", "kit": "treasure", "radius": 22.0, "at": Vector2(525, 360), "biome": FLOORB},
	{"name": "Toy Chest", "kit": "chest", "radius": 26.0, "at": Vector2(-200, 385), "biome": FLOORB},
	{"name": "Fishbowl Lagoon", "kit": "fishbowl", "radius": 40.0, "at": Vector2(-345, 218), "biome": SPILL},
	{"name": "Pillow Fort", "kit": "fort", "radius": 30.0, "at": Vector2(-300, -222), "biome": PILLOWS},
	{"name": "Teddy Hill", "kit": "teddy", "radius": 24.0, "at": Vector2(-505, -355), "biome": PILLOWS},
]

var train: ToyTrain
var track_points := PackedVector3Array()
## The fishbowl: {center: Vector2, base, level, r} (r: the water's radius).
var fishbowl: Dictionary = {}
var _mat_img: Image


func _init() -> void:
	drop_vehicle = &"paper_plane"
	map_title = "Toy Box Bash"
	music_slot = "match_toybox"


func generate(seed_: int, quality := 2, bake_nav := true) -> void:
	current = self
	seed_value = seed_
	rng.seed = seed_
	var tf := ToyFloor.new()
	terrain = tf
	terrain.name = "Terrain"
	add_child(terrain)
	terrain.setup(seed_)
	scatter = Scatter.new()
	scatter.name = "Scatter"
	add_child(scatter)
	scatter.load_manifest()

	progress.emit(0.05, "Tidying the bedroom floor")
	await get_tree().process_frame
	terrain.generate_heights()
	track_points = ToyTrain.loop_points(TRACK_RECT, TRACK_CORNER, ToyFloor.FLOOR)
	tf.flatten_corridor(track_points, 16.0)
	_choose_toy_pois()
	_shape_toy_pois()
	_plan_paths()
	terrain.compute_normals()

	progress.emit(0.25, "Rolling out the play rug")
	await get_tree().process_frame
	terrain.build_control(paths)
	terrain.build_meshes(_toy_material())
	terrain.build_collision()
	_build_spill_water()

	progress.emit(0.35, "Hanging the planet mobile")
	await get_tree().process_frame
	ToyRoom.build(self, rng)

	progress.emit(0.45, "Getting the toys out")
	await get_tree().process_frame
	_build_toy_pois()
	progress.emit(0.55, "Leaving bricks everywhere")
	await get_tree().process_frame
	_scatter_toys(quality)
	scatter.flush_batches(quality)
	_collect_foliage_materials()
	_plan_loot()

	if bake_nav:
		progress.emit(0.7, "Laying the train track")
		await get_tree().process_frame
		await _bake_navigation()
	# the train runs on top of the baked floor (it moves, so it isn't in the navmesh)
	train = ToyTrain.new()
	train.name = "ToyTrain"
	add_child(train)
	train.setup(track_points, rng)
	progress.emit(1.0, "Ready")
	ready_to_play = true


# ---- landmarks --------------------------------------------------------------------------------

func _choose_toy_pois() -> void:
	for k in TOY_POIS:
		var c: Vector2 = k.at
		if not k.kit in ["station", "fishbowl"]:
			c += Vector2(rng.randf_range(-10, 10), rng.randf_range(-10, 10))
		var h := terrain.height_at(c.x, c.y)
		var target := clampf(h, ToyFloor.FLOOR, ToyFloor.FLOOR + 6.0)
		if k.kit == "fishbowl":
			target = ToyFloor.SPILL_LEVEL - 0.7
		pois.append({"name": k.name, "kit": k.kit, "radius": k.radius, "center": c, "height": target, "biome": k.biome, "buildings": []})


func _shape_toy_pois() -> void:
	for p in pois:
		match p.kit:
			"station", "bricks", "racetrack":
				pass   # (flat already: rug and track bed)
			"dollhouse", "castle", "fort", "fishbowl", "crayons", "chest", "tea":
				terrain.flatten(p.center, p.radius * 0.8, p.height, 1.0, false)
			_:
				terrain.flatten(p.center, p.radius, p.height, 1.0, false)


func _build_toy_pois() -> void:
	for p in pois:
		var at: Vector2 = p.center
		match p.kit:
			"dollhouse":
				_place_kit(p, ToyProps.dollhouse(rng), at, _face_centre(at))
			"bricks":
				_build_brick_city(p)
			"racetrack":
				# 54 m long (ramp to loop): keep all of it clear, not just the middle
				var yaw := rng.randf() * TAU
				_prop(ToyProps.race_track(rng), at, yaw, NAN, true, false)
				add_long_obstacle(at + yaw_axis(yaw, true) * -5.0, yaw_axis(yaw, true), 26.0, 7.5)
				for i in 5:
					_scatter_one(ToyProps.race_car(rng), at, 14.0, p.radius + 6.0, 5.5)
			"station":
				_place_kit(p, _station(), at, 0.0)
			"castle":
				_place_kit(p, ToyProps.block_castle(rng), at, _face_centre(at))
			"crayons":
				_place_kit(p, ToyProps.crayon_box(rng), at, _face_centre(at))
				_prop(ToyProps.coloring_book(rng), at + Vector2(24, -14).rotated(rng.randf() * TAU), rng.randf() * TAU)
				for i in 9:
					var length := rng.randf_range(12.0, 20.0)
					_scatter_long(ToyProps.crayon(rng, length), at, 16.0, p.radius + 10.0, length * 0.5, 2.2)
			"dominoes":
				var start := rng.randf() * TAU
				for i in 13:
					var a := start + i * 0.36
					var d := Vector2(cos(a), sin(a)) * 24.0
					_prop(ToyProps.domino(rng, i > 10), at + d, -a, NAN)
			"tea":
				_prop(ToyProps.tea_table(rng), at, 0.0)
				for i in 3:
					_scatter_one(ToyProps.teacup(rng), at, 16.0, 26.0, 8.0)
			"rocket":
				_prop(ToyProps.rocket(rng), at, rng.randf() * TAU)
				for i in 3:
					_scatter_one(ToyProps.ball(rng, rng.randf_range(2.5, 4.0)), at, 13.0, 22.0, 4.0)
			"treasure":
				_prop(ToyProps.piggy_bank(rng), at + Vector2(0, -6), rng.randf() * TAU)
			"chest":
				_prop(ToyProps.toy_chest(rng), at, PI)
				for i in 5:
					_scatter_one(ToyProps.ball(rng, rng.randf_range(2.5, 5.0)), at, 16.0, 30.0, 5.0)
				for i in 4:
					_scatter_one(ToyProps.letter_block(rng), at, 14.0, 30.0, 3.4)
			"fishbowl":
				_build_fishbowl(p)
			"fort":
				_place_kit(p, ToyProps.pillow_fort(rng), at, _face_centre(at) + PI * 0.5)
			"teddy":
				_prop(ToyProps.teddy(rng), at, _face_centre(at))


## Brick City: plastic-brick houses and towers on a green baseplate.
func _build_brick_city(p: Dictionary) -> void:
	_prop(ToyProps.baseplate(rng), p.center, 0.0, terrain.height_at(p.center.x, p.center.y) + 0.01, false, false)
	for off in [Vector2(-26, -24), Vector2(26, -24), Vector2(-26, 24), Vector2(26, 24)]:
		var at: Vector2 = p.center + off
		_place_kit(p, ToyProps.brick_house(rng), at, _face_centre(at, p.center))
	for off in [Vector2(0, -40), Vector2(-44, 0), Vector2(42, 4)]:
		_prop(ToyProps.brick_tower(rng), p.center + off, rng.randf() * TAU)


## The train station beside the track's south straight: a platform at the
## height of the open cars' decks, ramps at both ends and a canopy.
func _station() -> CageKit:
	var k := CageKit.blank("Station", rng)
	var deck := ToyTrain.DECK
	k._box(&"paint_red", Vector3(0, deck * 0.5, 0), Vector3(40.0, deck, 12.8))
	k._box(&"plastic_white", Vector3(0, deck + 0.03, 6.0), Vector3(40.0, 0.06, 0.8), Basis(), false)
	for xs in [-1.0, 1.0]:
		k._ramp(&"wood_light", Vector3(xs * 28.0, -0.15, -2.0), Vector3(xs * 19.8, deck, -2.0), 7.0)
		for zs in [-1.0, 1.0]:
			k._rod(&"plastic_white", Vector3(xs * 15.0, deck, zs * 4.0), Vector3(xs * 15.0, deck + 7.0, zs * 4.0), 0.5)
	k._box(&"paint_blue", Vector3(0, deck + 7.3, 0), Vector3(36.0, 0.6, 11.0))
	k._lathe(&"plastic_white", [Vector2(0.0, -0.2), Vector2(2.2, -0.2), Vector2(2.2, 0.2), Vector2(0.0, 0.2)], 20, Vector3(0, deck + 9.2, 0), false)
	k._box(&"paint_yellow", Vector3(0, deck + 8.6, 0), Vector3(10.0, 2.0, 0.4), Basis(), false)
	k.footprint = 22.0
	k.floor_y = deck
	k.loot_spots = [Vector3(-10.0, deck, -2.0), Vector3(8.0, deck, 1.0)]
	return k.made_as("toy/station").finish()


## The fishbowl, its water, and goldfish circling inside.
func _build_fishbowl(p: Dictionary) -> void:
	var c: Vector2 = p.center
	var base := terrain.height_at(c.x, c.y)
	var bowl := ToyProps.fishbowl(rng, BOWL_RIM)
	add_child(bowl)
	bowl.global_position = Vector3(c.x, base, c.y)
	bowl.rotation.y = _face_centre(c) + PI   # the slide faces away from the middle
	scatter.add_obstacle(c, 31.0)
	var level := base + BOWL_RIM - 0.6
	fishbowl = {"center": c, "base": base, "level": level, "r": 21.8}
	_water_disc(Vector3(c.x, level, c.y), 21.9)
	var school := Spinner.new()
	school.name = "Goldfish"
	school.speed = 0.35
	school.bob = 1.5
	add_child(school)
	school.global_position = Vector3(c.x, base + 12.0, c.y)
	for i in 4:
		var fish := CageKit.blank("Goldfish", rng)
		fish.collision_layer = 0
		var r := 9.0 + i * 3.0
		fish._ellipsoid(&"plastic_orange", Vector3(r, 0, 0), Vector3(1.2, 1.5, 2.6), Basis(), false, 6, 12)
		fish._ellipsoid(&"plastic_orange", Vector3(r, 0, 3.0), Vector3(0.3, 1.5, 1.3), Basis(), false, 4, 8)
		fish._ellipsoid(&"button_eye", Vector3(r + 0.9, 0.4, -1.6), Vector3(0.3, 0.3, 0.3), Basis(), false, 3, 6)
		fish.dress(ToyProps.made("toy/goldfish"), Transform3D(Basis(), Vector3(r, 0, 0)))
		var pivot := Node3D.new()
		pivot.rotation.y = i * 1.6
		school.add_child(pivot)
		pivot.add_child(fish.finish())


# ---- placing things (as in HamsterCage) ----------------------------------------------------------

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


func _place_kit(p: Dictionary, kit: Building, at: Vector2, yaw: float) -> Building:
	kit.name = "%s_%d" % [kit.name, buildings.size()]
	add_child(kit)
	kit.global_position = Vector3(at.x, terrain.height_at(at.x, at.y), at.y)
	kit.rotation.y = yaw
	scatter.reserve(at, kit.footprint)
	buildings.append(kit)
	(p.buildings as Array).append(kit)
	return kit


## A long toy (a crayon) at a random free spot in a ring round `c`: clear
## along its whole length (it lies along its local X).
func _scatter_long(kit: Node3D, c: Vector2, r0: float, r1: float, half_len: float, radius: float) -> Node3D:
	for attempt in 20:
		var a := rng.randf() * TAU
		var at := c + Vector2(cos(a), sin(a)) * rng.randf_range(r0, r1)
		var yaw := rng.randf() * TAU
		var axis := yaw_axis(yaw)
		if not _toy_spot_ok(at, radius, false) or not _toy_spot_ok(at + axis * half_len, radius, false) \
				or not _toy_spot_ok(at - axis * half_len, radius, false) or not long_clear(at, axis, half_len, radius + 2.0):
			continue
		add_child(kit)
		kit.global_position = Vector3(at.x, terrain.height_at(at.x, at.y), at.y)
		kit.rotation.y = yaw
		add_long_obstacle(at, axis, half_len, radius)
		return kit
	kit.free()
	return null


func _scatter_one(kit: Node3D, c: Vector2, r0: float, r1: float, radius: float) -> Node3D:
	for attempt in 14:
		var a := rng.randf() * TAU
		var at := c + Vector2(cos(a), sin(a)) * rng.randf_range(r0, r1)
		var h := terrain.height_at(at.x, at.y)
		if not _toy_spot_ok(at, radius, false):
			continue
		add_child(kit)
		kit.global_position = Vector3(at.x, h, at.y)
		kit.rotation.y = rng.randf() * TAU
		scatter.add_obstacle(at, radius)
		return kit
	kit.free()
	return null


## Somewhere a toy may sit: dry, inside the room, off the train track, clear
## of other things (and of the landmarks unless `near_poi_ok`).
func _toy_spot_ok(p: Vector2, radius: float, avoid_pois := true) -> bool:
	var tf := terrain as ToyFloor
	if not tf.inside(p.x, p.y, 10.0):
		return false
	var h := terrain.height_at(p.x, p.y)
	if water_level_at(Vector3(p.x, h, p.y)) > h - 0.3 or terrain.normal_at(p.x, p.y).y < 0.85:
		return false
	if _near_track(p, radius + 6.0):
		return false
	if avoid_pois:
		for poi in pois:
			if p.distance_to(poi.center) < poi.radius + 2.0:
				return false
	return not scatter.blocked(p, radius + 2.0)


func _near_track(p: Vector2, margin: float) -> bool:
	var inner := TRACK_RECT.grow(-margin)
	var outer := TRACK_RECT.grow(margin)
	if not outer.has_point(p):
		return false
	if not inner.has_point(p):
		return true
	# inside the inner rectangle but near a rounded corner?
	for i in track_points.size():
		if i % 4 == 0 and Vector2(track_points[i].x, track_points[i].z).distance_to(p) < margin:
			return true
	return false


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
	m.set_shader_parameter(&"shallow_color", Color(0.5, 0.82, 0.95))
	m.set_shader_parameter(&"deep_color", Color(0.15, 0.45, 0.7))
	m.set_shader_parameter(&"depth_fade", 6.0)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = c


# ---- toys everywhere --------------------------------------------------------------------------

func _scatter_toys(quality: int) -> void:
	var density: float = [0.35, 0.6, 1.0, 1.4][clampi(quality, 0, 3)]
	# [builder, count, spacing radius, biome weights it likes (floor, spill, pillows)]
	var solids := [
		[func(): return ToyProps.letter_block(rng, rng.randf_range(3.2, 4.5)), 38, 3.4, Vector3(1.0, 0.4, 0.4)],
		[func(): return ToyProps.ball(rng, rng.randf_range(2.2, 4.5)), 20, 4.0, Vector3(1.0, 0.3, 0.6)],
		[func(): return ToyProps.race_car(rng), 10, 5.0, Vector3(1.0, 0.0, 0.0)],
		[func(): return ToyProps.domino(rng, rng.randf() < 0.5), 8, 3.0, Vector3(1.0, 0.0, 0.0)],
		[func(): return ToyProps.brick_tower(rng), 6, 6.0, Vector3(1.0, 0.0, 0.0)],
		[func(): return ToyProps.pillow(rng), 16, 6.0, Vector3(0.0, 0.0, 1.0)],
	]
	for s in solids:
		var made := 0
		for i in int(s[1]) * 8:
			if made >= int(s[1]):
				break
			var p := _random_land(ToyFloor.FLOOR - 2.0)
			if rng.randf() > terrain.biome_at(p.x, p.y).dot(s[3]) or not _toy_spot_ok(p, float(s[2])):
				continue
			var kit: Node3D = (s[0] as Callable).call()
			add_child(kit)
			kit.global_position = Vector3(p.x, terrain.height_at(p.x, p.y), p.y)
			kit.rotation.y = rng.randf() * TAU
			scatter.add_obstacle(p, float(s[2]))
			made += 1
	# crayons are long: they keep their whole length clear
	var crayons := 0
	for i in 16 * 8:
		if crayons >= 16:
			break
		var p := _random_land(ToyFloor.FLOOR - 2.0)
		if rng.randf() > terrain.biome_at(p.x, p.y).dot(Vector3(1.0, 0.2, 0.3)):
			continue
		var length := rng.randf_range(12.0, 20.0)
		if not _toy_spot_ok(p, 2.2):
			continue
		if _scatter_long(ToyProps.crayon(rng, length), p, 0.0, 0.01, length * 0.5, 2.2):
			crayons += 1
	var area := ToyFloor.HX * ToyFloor.HZ * 4.0
	var batched := [[ToyProps.entry("bricks"), area / 900.0, Vector3(1.0, 0.3, 0.3)], [ToyProps.entry("marbles"), area / 1600.0, Vector3(1.0, 0.5, 0.2)],
		[ToyProps.entry("stuffing"), area / 260.0, Vector3(0.0, 0.0, 1.0)]]
	for b in batched:
		var e: Dictionary = b[0]
		for i in int(float(b[1]) * density):
			var p := Vector2(rng.randf_range(-ToyFloor.HX + 6.0, ToyFloor.HX - 6.0), rng.randf_range(-ToyFloor.HZ + 6.0, ToyFloor.HZ - 6.0))
			if rng.randf() > terrain.biome_at(p.x, p.y).dot(b[2]):
				continue
			var sr: Array = e.scale_range
			var sc := rng.randf_range(sr[0], sr[1])
			if not in_poi(p, 0.7).is_empty() or scatter.blocked(p, float(e.get("footprint_radius_m", 1.0)) * sc) or _near_track(p, 4.0):
				continue
			var h := terrain.height_at(p.x, p.y)
			if water_level_at(Vector3(p.x, h, p.y)) > h - 0.1:
				continue
			scatter.place(e, Vector3(p.x, h, p.y), rng.randf() * TAU, sc)


# ---- materials and water ----------------------------------------------------------------------

func _toy_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = TOY_SHADER
	m.set_shader_parameter(&"control_map", terrain.control_texture())
	m.set_shader_parameter(&"biome_map", terrain.biome_texture())
	m.set_shader_parameter(&"terrain_size", Terrain.SIZE)
	m.set_shader_parameter(&"spill_level", ToyFloor.SPILL_LEVEL)
	var r := ToyFloor.RUG
	m.set_shader_parameter(&"rug_rect", Vector4(r.position.x, r.position.y, r.size.x, r.size.y))
	var mat := ToyFloor.playmat_texture()
	_mat_img = mat.get_image()
	m.set_shader_parameter(&"playmat", mat)
	m.set_shader_parameter(&"oak_albedo", _tex_or_color("res://assets/textures/oak_floor/albedo.jpg", Color(0.7, 0.5, 0.3)))
	m.set_shader_parameter(&"oak_normal", _tex_or_color("res://assets/textures/oak_floor/normal.png", Color(0.5, 0.5, 1.0)))
	m.set_shader_parameter(&"weave_normal", _tex_or_color("res://assets/textures/plaid/normal.png", Color(0.5, 0.5, 1.0)))
	m.set_shader_parameter(&"gingham_albedo", _tex_or_color("res://assets/textures/gingham/albedo.jpg", Color(0.8, 0.3, 0.3)))
	m.set_shader_parameter(&"plaid_albedo", _tex_or_color("res://assets/textures/plaid/albedo.jpg", Color(0.9, 0.88, 0.8)))
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


## The spill: still water a hand's depth over the sagging floorboards round
## the fishbowl (like the island's swamp: one quad per biome cell).
func _build_spill_water() -> void:
	var n := Terrain.BIOME_RES
	var cell := Terrain.BIOME_CELL
	var half := Terrain.SIZE * 0.5
	_swamp_cells.resize(n * n)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var any := false
	var bowl_at := Vector2.INF
	for p in pois:
		if p.kit == "fishbowl":
			bowl_at = p.center
	for zi in n - 1:
		for xi in n - 1:
			var x := xi * cell - half
			var z := zi * cell - half
			var mid := Vector2(x + cell * 0.5, z + cell * 0.5)
			if terrain.biome_at(mid.x, mid.y).y < 0.25 or not (terrain as ToyFloor).inside(mid.x, mid.y) or mid.distance_to(bowl_at) < 31.0:
				continue
			var low := INF
			for k in 5:
				var q := Vector2(x, z) + Vector2([0.0, cell, 0.0, cell, cell * 0.5][k], [0.0, 0.0, cell, cell, cell * 0.5][k])
				low = minf(low, terrain.height_at(q.x, q.y))
			if low > ToyFloor.SPILL_LEVEL + 0.05:
				continue
			_swamp_cells[zi * n + xi] = 1
			any = true
			var y := ToyFloor.SPILL_LEVEL
			for v in [Vector3(x - 0.3, y, z - 0.3), Vector3(x + cell + 0.3, y, z - 0.3), Vector3(x + cell + 0.3, y, z + cell + 0.3),
					Vector3(x - 0.3, y, z - 0.3), Vector3(x + cell + 0.3, y, z + cell + 0.3), Vector3(x - 0.3, y, z + cell + 0.3)]:
				st.set_normal(Vector3.UP)
				st.set_uv(Vector2(v.x, v.z))
				st.add_vertex(v)
	if not any:
		_swamp_cells.clear()
		return
	swamp_water = MeshInstance3D.new()
	swamp_water.name = "SpillWater"
	swamp_water.mesh = st.commit()
	var m := _water_material()
	m.set_shader_parameter(&"shallow_color", Color(0.42, 0.7, 0.92))
	m.set_shader_parameter(&"deep_color", Color(0.2, 0.47, 0.78))
	m.set_shader_parameter(&"depth_fade", 0.5)   # (ankle-deep: it should still read as water)
	swamp_water.material_override = m
	swamp_water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(swamp_water)


func water_level_at(pos: Vector3) -> float:
	var level := -100.0
	if _in_swamp_water(pos.x, pos.z):
		level = ToyFloor.SPILL_LEVEL
	if not fishbowl.is_empty() and Vector2(pos.x, pos.z).distance_to(fishbowl.center) < 28.0 and pos.y > fishbowl.base + 1.0:
		level = maxf(level, fishbowl.level)
	return level


# ---- the map's shape, colours and light ---------------------------------------------------------

func _random_land(min_h: float) -> Vector2:
	for i in 60:
		var p := Vector2(rng.randf_range(-ToyFloor.HX + 25.0, ToyFloor.HX - 25.0), rng.randf_range(-ToyFloor.HZ + 25.0, ToyFloor.HZ - 25.0))
		var h := terrain.height_at(p.x, p.y)
		if h > min_h and water_level_at(Vector3(p.x, h, p.y)) < h - 0.2:
			return p
	return Vector2(0, 0)


func play_bounds() -> Rect2:
	return Rect2(-ToyFloor.HX, -ToyFloor.HZ, ToyFloor.HX * 2.0, ToyFloor.HZ * 2.0)


func map_color(x: float, z: float) -> Color:
	var tf := terrain as ToyFloor
	if not tf.inside(x, z):
		return Color("4a3a2c")
	var h := terrain.height_at(x, z)
	if not fishbowl.is_empty() and Vector2(x, z).distance_to(fishbowl.center) < 29.0:
		return Color("8fd3f0")
	if water_level_at(Vector3(x, h, z)) > h + 0.05:
		return Color("7fb1c8")
	var c := Color("c08a55")
	if tf.on_rug(x, z) and _mat_img:
		var u := (x - ToyFloor.RUG.position.x) / ToyFloor.RUG.size.x
		var v := (z - ToyFloor.RUG.position.y) / ToyFloor.RUG.size.y
		c = _mat_img.get_pixel(clampi(int(u * _mat_img.get_width()), 0, _mat_img.get_width() - 1), clampi(int(v * _mat_img.get_height()), 0, _mat_img.get_height() - 1))
	var w := terrain.biome_at(x, z)
	c = c.lerp(Color("d65a5a") if int(floor(x / 34.0) + floor(z / 34.0)) % 2 == 0 else Color("efe6cf"), smoothstep(0.2, 0.45, w.z))
	if _near_track(Vector2(x, z), 2.6):
		c = Color("e8cf9e")
	var nrm := terrain.normal_at(x, z)
	return c * (0.8 + 0.25 * clampf(nrm.dot(Vector3(-0.5, 0.75, -0.4).normalized()), 0.0, 1.0))


## Daylight through the bedroom window in the north wall.
func tune_lighting(lighting: WorldLighting) -> void:
	lighting.sun.global_basis = Basis.looking_at(Vector3(0.3, -0.75, 1.0).normalized(), Vector3.UP)
	lighting.sun.light_energy = 1.25
	lighting.env.fog_density = 0.0002
	lighting.env.fog_light_color = Color(0.95, 0.9, 0.82)
	lighting.env.fog_aerial_perspective = 0.1
	lighting.env.ambient_light_energy = 1.0
	lighting.make_indoor()
