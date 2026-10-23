class_name CageRoom
extends RefCounted
## Everything around the hamster cage's floor: the glass TANK (four panes,
## solid, with black plastic trim top and bottom), the human ROOM it stands
## in (a wooden floor, cream walls, a sunny window with curtains, a couch, a
## ceiling lamp) and the giant FRIDGE behind the north wall, left open: its
## lit shelves full of enormous food, cold light and mist spilling over the
## glass into the winter corner, icicles and falling snow. Only the glass is
## solid; the room is scenery (nobody can get out to it).

const GLASS_TOP := 150.0
const ROOM_FLOOR := -12.0
const FRAME_TOP := 19.0          ## the black base trim hides the bedding's cut edge
const GLASS := 1.5
const SHADER := preload("res://src/world/shaders/glass.gdshader")
## The fridge stands behind the north wall: x 250..630, front face at z -460.
const FRIDGE_X := Vector2(250.0, 630.0)
const FRIDGE_FRONT := -460.0
const FRIDGE_DEPTH := 340.0
const FRIDGE_TOP := 748.0
const ROOM := Rect2(-1500.0, -840.0, 2900.0, 2340.0)   ## x, z extents of the room
const CEILING := 1400.0


static func build_tank(parent: Node3D, rng: RandomNumberGenerator) -> void:
	var hx := CageFloor.HX
	var hz := CageFloor.HZ
	var body := StaticBody3D.new()
	body.name = "TankGlass"
	body.collision_layer = Layers.WORLD
	body.set_meta(&"surface", &"rock")
	parent.add_child(body)
	var h := GLASS_TOP - ROOM_FLOOR
	var panes := [
		[Vector3(0, ROOM_FLOOR + h * 0.5, -(hz + GLASS * 0.5)), Vector3(hx * 2.0 + GLASS * 2.0, h, GLASS)],
		[Vector3(0, ROOM_FLOOR + h * 0.5, hz + GLASS * 0.5), Vector3(hx * 2.0 + GLASS * 2.0, h, GLASS)],
		[Vector3(-(hx + GLASS * 0.5), ROOM_FLOOR + h * 0.5, 0), Vector3(GLASS, h, hz * 2.0)],
		[Vector3(hx + GLASS * 0.5, ROOM_FLOOR + h * 0.5, 0), Vector3(GLASS, h, hz * 2.0)],
	]
	var glass := ShaderMaterial.new()
	glass.shader = SHADER
	var noise := NoiseTexture2D.new()
	noise.width = 256
	noise.height = 256
	noise.seamless = true
	noise.generate_mipmaps = true
	var fn := FastNoiseLite.new()
	fn.seed = rng.randi()
	fn.frequency = 0.03
	fn.fractal_octaves = 4
	noise.noise = fn
	glass.set_shader_parameter(&"smudge_tex", noise)
	glass.set_shader_parameter(&"frost_center", Vector3(CageFloor.WINTER_AT.x + 60.0, 0.0, -hz))
	for p in panes:
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = p[1]
		cs.shape = box
		cs.position = p[0]
		body.add_child(cs)
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = p[1]
		mi.mesh = bm
		mi.material_override = glass
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = p[0]
		body.add_child(mi)
	# black plastic trim round the bottom and the top, and up the corners
	var trim := CageKit.blank("TankTrim", rng, &"rock")
	trim.collision_layer = 0
	var t := 3.0
	for band in [[ROOM_FLOOR, FRAME_TOP], [GLASS_TOP - 7.0, GLASS_TOP + 1.5]]:
		var y0: float = band[0]
		var y1: float = band[1]
		var yc := (y0 + y1) * 0.5
		var bh := y1 - y0
		for zs in [-1.0, 1.0]:
			trim._box(&"plastic_black", Vector3(0, yc, zs * (hz + GLASS + t * 0.5)), Vector3(hx * 2.0 + (GLASS + t) * 2.0, bh, t), Basis(), false)
		for xs in [-1.0, 1.0]:
			trim._box(&"plastic_black", Vector3(xs * (hx + GLASS + t * 0.5), yc, 0), Vector3(t, bh, hz * 2.0 + GLASS * 2.0), Basis(), false)
	for xs in [-1.0, 1.0]:
		for zs in [-1.0, 1.0]:
			trim._box(&"plastic_black", Vector3(xs * (hx + GLASS), (ROOM_FLOOR + GLASS_TOP) * 0.5, zs * (hz + GLASS)), Vector3(4.0, h + 2.0, 4.0), Basis(), false)
	# the glass bottom's edge, seen through the panes: a dark slab under the bedding
	trim._box(&"plastic_black", Vector3(0, ROOM_FLOOR + 1.0, 0), Vector3(hx * 2.0 + 10.0, 2.0, hz * 2.0 + 10.0), Basis(), false)
	parent.add_child(trim.finish())


static func build_room(parent: Node3D, rng: RandomNumberGenerator) -> void:
	var k := CageKit.blank("Room", rng, &"wood")
	k.collision_layer = 0
	var x0 := ROOM.position.x
	var x1 := ROOM.end.x
	var z0 := ROOM.position.y
	var z1 := ROOM.end.y
	var cx := (x0 + x1) * 0.5
	var cz := (z0 + z1) * 0.5
	var y0 := ROOM_FLOOR
	# floor, rug under the tank, ceiling and lamp
	k._box(&"laminate", Vector3(cx, y0 - 2.0, cz), Vector3(x1 - x0, 4.0, z1 - z0), Basis(), false)
	k._box(&"rug", Vector3(0, y0 + 0.4, 60.0), Vector3(1500.0, 0.8, 1180.0), Basis(), false)
	k._box(&"rug_border", Vector3(0, y0 + 0.2, 60.0), Vector3(1560.0, 0.6, 1240.0), Basis(), false)
	k._box(&"ceiling", Vector3(cx, CEILING + 5.0, cz), Vector3(x1 - x0, 10.0, z1 - z0), Basis(), false)
	k._lathe(&"lamp", [Vector2(0.0, CEILING - 60.0), Vector2(120.0, CEILING - 40.0), Vector2(160.0, CEILING)], 32, Vector3(0, 0, 200), false)
	# walls (the west one has the window), with a skirting board
	var wall_h := CEILING - y0
	var win := Rect2(-260.0, 260.0, 900.0, 780.0)   # z from, y from, width (z), height (y)
	k._box(&"wall_paint", Vector3(cx, y0 + wall_h * 0.5, z0 - 10.0), Vector3(x1 - x0 + 40.0, wall_h, 20.0), Basis(), false)
	k._box(&"wall_paint", Vector3(cx, y0 + wall_h * 0.5, z1 + 10.0), Vector3(x1 - x0 + 40.0, wall_h, 20.0), Basis(), false)
	k._box(&"wall_paint", Vector3(x1 + 10.0, y0 + wall_h * 0.5, cz), Vector3(20.0, wall_h, z1 - z0), Basis(), false)
	var wz0 := win.position.x
	var wz1 := win.position.x + win.size.x
	var wy0 := y0 + win.position.y
	var wy1 := wy0 + win.size.y
	k._box(&"wall_paint", Vector3(x0 - 10.0, y0 + wall_h * 0.5, (z0 + wz0) * 0.5), Vector3(20.0, wall_h, wz0 - z0), Basis(), false)
	k._box(&"wall_paint", Vector3(x0 - 10.0, y0 + wall_h * 0.5, (wz1 + z1) * 0.5), Vector3(20.0, wall_h, z1 - wz1), Basis(), false)
	k._box(&"wall_paint", Vector3(x0 - 10.0, (y0 + wy0) * 0.5, (wz0 + wz1) * 0.5), Vector3(20.0, wy0 - y0, wz1 - wz0), Basis(), false)
	k._box(&"wall_paint", Vector3(x0 - 10.0, (wy1 + CEILING) * 0.5, (wz0 + wz1) * 0.5), Vector3(20.0, CEILING - wy1, wz1 - wz0), Basis(), false)
	# window frame and cross bars, a sill, and pink curtains
	for z in [wz0, (wz0 + wz1) * 0.5, wz1]:
		k._box(&"plastic_white", Vector3(x0 - 4.0, (wy0 + wy1) * 0.5, z), Vector3(14.0, wy1 - wy0 + 20.0, 18.0), Basis(), false)
	for y in [wy0, (wy0 + wy1) * 0.5, wy1]:
		k._box(&"plastic_white", Vector3(x0 - 4.0, y, (wz0 + wz1) * 0.5), Vector3(14.0, 18.0, wz1 - wz0 + 20.0), Basis(), false)
	k._box(&"plastic_white", Vector3(x0 + 18.0, wy0 - 12.0, (wz0 + wz1) * 0.5), Vector3(50.0, 10.0, wz1 - wz0 + 80.0), Basis(), false)
	for side in [[wz0 - 90.0, -1.0], [wz1 + 90.0, 1.0]]:
		for i in 5:
			var z: float = side[0] + float(side[1]) * (i - 2) * 26.0
			k._box(&"curtain", Vector3(x0 + 12.0 + (i % 2) * 6.0, (y0 + 40.0 + wy1 + 60.0) * 0.5, z), Vector3(12.0, wy1 + 60.0 - y0 - 40.0, 30.0), Basis(), false)
	k._rod(&"metal", Vector3(x0 + 14.0, wy1 + 70.0, wz0 - 180.0), Vector3(x0 + 14.0, wy1 + 70.0, wz1 + 180.0), 4.0, false)
	for xs in [x0, x1]:
		k._box(&"plastic_white", Vector3(xs + (12.0 if xs == x0 else -12.0), y0 + 25.0, cz), Vector3(6.0, 50.0, z1 - z0), Basis(), false)
	for zs in [z0, z1]:
		k._box(&"plastic_white", Vector3(cx, y0 + 25.0, zs + (3.0 if zs == z0 else -3.0)), Vector3(x1 - x0, 50.0, 6.0), Basis(), false)
	# a couch along the south wall
	var cz2 := z1 - 210.0
	k._box(&"couch", Vector3(-300.0, y0 + 110.0, cz2), Vector3(1100.0, 180.0, 340.0), Basis(), false)
	k._box(&"couch", Vector3(-300.0, y0 + 330.0, cz2 + 140.0), Vector3(1100.0, 300.0, 120.0), Basis(), false)
	for xs in [-1.0, 1.0]:
		k._box(&"couch", Vector3(-300.0 + xs * 600.0, y0 + 200.0, cz2), Vector3(120.0, 280.0, 360.0), Basis(), false)
	for i in 2:
		k._box(&"cushion", Vector3(-560.0 + i * 520.0, y0 + 230.0, cz2 - 10.0), Vector3(480.0, 60.0, 300.0), Basis(), false)
	parent.add_child(k.finish())
	for gi in ModelUtil.find_all(k, "GeometryInstance3D"):
		(gi as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## The giant fridge, door wide open, its lit shelves stacked with food.
static func build_fridge(parent: Node3D, rng: RandomNumberGenerator) -> void:
	var k := CageKit.blank("Fridge", rng, &"rock")
	k.collision_layer = 0
	var xa := FRIDGE_X.x
	var xb := FRIDGE_X.y
	var w := xb - xa
	var xc := (xa + xb) * 0.5
	var zf := FRIDGE_FRONT
	var zb := zf - FRIDGE_DEPTH
	var zc := (zf + zb) * 0.5
	var foot := ROOM_FLOOR
	var base := foot + 18.0
	var wall := 22.0
	var split := 560.0        # fridge below, freezer above
	# feet and the kick plate
	for x in [xa + 30.0, xb - 30.0]:
		for z in [zf - 30.0, zb + 30.0]:
			k._box(&"plastic_black", Vector3(x, (foot + base) * 0.5, z), Vector3(30.0, base - foot, 30.0), Basis(), false)
	k._box(&"plastic_black", Vector3(xc, (foot + base) * 0.5, zf - 8.0), Vector3(w - 20.0, base - foot, 12.0), Basis(), false)
	# the shell: sides, back, top, bottom and the divider under the freezer
	k._box(&"enamel", Vector3(xa + wall * 0.5, (base + FRIDGE_TOP) * 0.5, zc), Vector3(wall, FRIDGE_TOP - base, FRIDGE_DEPTH), Basis(), false)
	k._box(&"enamel", Vector3(xb - wall * 0.5, (base + FRIDGE_TOP) * 0.5, zc), Vector3(wall, FRIDGE_TOP - base, FRIDGE_DEPTH), Basis(), false)
	k._box(&"enamel", Vector3(xc, (base + FRIDGE_TOP) * 0.5, zb + wall * 0.5), Vector3(w, FRIDGE_TOP - base, wall), Basis(), false)
	k._box(&"enamel", Vector3(xc, FRIDGE_TOP - wall * 0.5, zc), Vector3(w, wall, FRIDGE_DEPTH), Basis(), false)
	k._box(&"enamel", Vector3(xc, base + wall * 0.5, zc), Vector3(w, wall, FRIDGE_DEPTH), Basis(), false)
	k._box(&"enamel", Vector3(xc, split, zc), Vector3(w, wall * 1.5, FRIDGE_DEPTH), Basis(), false)
	# the lit liner inside the fridge compartment
	var in_x := Vector2(xa + wall, xb - wall)
	var iy0 := base + wall
	var iy1 := split - wall * 0.75
	k._box(&"liner", Vector3(xc, (iy0 + iy1) * 0.5, zb + wall + 1.0), Vector3(in_x.y - in_x.x, iy1 - iy0, 2.0), Basis(), false)
	for x in [in_x.x + 1.0, in_x.y - 1.0]:
		k._box(&"liner", Vector3(x, (iy0 + iy1) * 0.5, zc + wall * 0.5), Vector3(2.0, iy1 - iy0, FRIDGE_DEPTH - wall), Basis(), false)
	k._box(&"liner", Vector3(xc, iy1 - 1.0, zc + wall * 0.5), Vector3(in_x.y - in_x.x, 2.0, FRIDGE_DEPTH - wall), Basis(), false)
	# the closed freezer door above, with its handle
	k._box(&"enamel", Vector3(xc, (split + FRIDGE_TOP) * 0.5, zf + 14.0), Vector3(w, FRIDGE_TOP - split - 4.0, 28.0), Basis(), false)
	k._box(&"metal", Vector3(xa + 40.0, split + 70.0, zf + 36.0), Vector3(16.0, 90.0, 12.0), Basis(), false)
	# glass shelves and the crisper drawers
	var shelves := [iy0 + 110.0, iy0 + 230.0, iy0 + 360.0]
	for y in shelves:
		k._box(&"shelf_glass", Vector3(xc, y, zc + wall * 0.5), Vector3(in_x.y - in_x.x - 4.0, 4.0, FRIDGE_DEPTH - wall - 10.0), Basis(), false)
		k._box(&"plastic_white", Vector3(xc, y, zf - 6.0), Vector3(in_x.y - in_x.x - 4.0, 8.0, 8.0), Basis(), false)
	for xs in [-1.0, 1.0]:
		var dc := Vector3(xc + xs * (w * 0.25 - 6.0), iy0 + 45.0, zc + 20.0)
		k._box(&"shelf_glass", dc, Vector3(w * 0.5 - 30.0, 90.0, FRIDGE_DEPTH - 60.0), Basis(), false)
		k._ellipsoid(&"broccoli" if xs < 0 else &"lettuce", dc + Vector3(0, -5.0, 10.0), Vector3(60.0, 38.0, 60.0), Basis(), false, 8, 14)
	# food on the shelves: milk, cheese, eggs, jam, butter, a soda bottle, leftovers
	var s0: float = shelves[0] + 2.0
	var s1: float = shelves[1] + 2.0
	var s2: float = shelves[2] + 2.0
	var front := zf - 70.0
	k._box(&"milk", Vector3(xa + 80.0, s0 + 75.0, front - 40.0), Vector3(70.0, 150.0, 70.0), Basis(), false)
	k._prism(&"milk", [Vector2(xa + 45.0, s0 + 150.0), Vector2(xa + 80.0, s0 + 185.0), Vector2(xa + 115.0, s0 + 150.0)], front - 40.0, 70.0)
	k._box(&"plastic_blue", Vector3(xa + 80.0, s0 + 110.0, front - 4.0), Vector3(60.0, 50.0, 2.0), Basis(), false)
	k._prism(&"cheese", [Vector2(xc - 40.0, s0), Vector2(xc + 70.0, s0), Vector2(xc - 40.0, s0 + 70.0)], front - 30.0, 80.0)
	k._box(&"egg_carton", Vector3(xc + 20.0, s1 + 18.0, front - 40.0), Vector3(170.0, 36.0, 80.0), Basis(), false)
	for i in 6:
		k._ellipsoid(&"egg", Vector3(xc - 45.0 + (i % 3) * 32.0, s1 + 50.0, front - 60.0 + int(i / 3) * 38.0), Vector3(14.0, 20.0, 14.0), Basis(), false, 8, 12)
	k._rod(&"jam", Vector3(xb - 90.0, s1, front - 50.0), Vector3(xb - 90.0, s1 + 80.0, front - 50.0), 34.0, false)
	k._rod(&"plastic_red", Vector3(xb - 90.0, s1 + 80.0, front - 50.0), Vector3(xb - 90.0, s1 + 96.0, front - 50.0), 36.0, false)
	k._box(&"butter", Vector3(xa + 90.0, s2 + 22.0, front - 40.0), Vector3(90.0, 44.0, 50.0), Basis(), false)
	k._rod(&"soda", Vector3(xc + 40.0, s2, front - 60.0), Vector3(xc + 40.0, s2 + 150.0, front - 60.0), 24.0, false)
	k._rod(&"plastic_red", Vector3(xc + 40.0, s2 + 150.0, front - 60.0), Vector3(xc + 40.0, s2 + 170.0, front - 60.0), 10.0, false)
	k._box(&"leftovers", Vector3(xb - 90.0, s2 + 25.0, front - 70.0), Vector3(110.0, 50.0, 90.0), Basis(), false)
	k._box(&"plastic_blue", Vector3(xb - 90.0, s2 + 52.0, front - 70.0), Vector3(116.0, 6.0, 96.0), Basis(), false)
	# the door: hinged on the east edge and swung wide open, away from the tank
	var hinge := Vector3(xb, 0.0, zf)
	var open := deg_to_rad(105.0)
	var door := Basis(Vector3.UP, -open)
	var dh := split - base - 8.0
	var dcen := hinge + door * Vector3(-w * 0.5, 0, 14.0) + Vector3.UP * (base + dh * 0.5)
	k._box(&"enamel", dcen, Vector3(w, dh, 28.0), door, false)
	k._box(&"liner", dcen + door * Vector3(0, 0, -15.0), Vector3(w - 40.0, dh - 40.0, 2.0), door, false)
	k._box(&"metal", hinge + door * Vector3(-w + 40.0, 0, 38.0) + Vector3.UP * (base + dh - 80.0), Vector3(16.0, 120.0, 12.0), door, false)
	for i in 3:
		var y := base + 80.0 + i * 140.0
		var bin_c := hinge + door * Vector3(-w * 0.5, 0, -40.0) + Vector3.UP * y
		k._box(&"shelf_glass", bin_c, Vector3(w - 60.0, 40.0, 50.0), door, false)
		for j in 3:
			var bx := -w * 0.5 + (j - 1) * 90.0
			var bottle: StringName = [&"ketchup", &"mustard", &"soda"][(i + j) % 3]
			var bp := hinge + door * Vector3(bx, 0, -40.0) + Vector3.UP * (y + 20.0)
			k._rod(bottle, bp, bp + Vector3.UP * (90.0 + j * 15.0), 20.0, false)
	parent.add_child(k.finish())
	# the cold: a bluish light from inside, mist rolling out over the glass,
	# and snow falling in the winter corner
	var light := OmniLight3D.new()
	light.name = "FridgeLight"
	light.light_color = Color(0.82, 0.92, 1.0)
	light.light_energy = 5.0
	light.omni_range = 900.0
	light.omni_attenuation = 1.2
	light.shadow_enabled = false
	parent.add_child(light)
	light.position = Vector3(xc, (iy0 + iy1) * 0.5, zf - 60.0)
	_mist(parent, Vector3(xc - 40.0, 175.0, zf + 6.0), Vector3(150.0, 30.0, 4.0))
	_snowfall(parent, Vector3(CageFloor.WINTER_AT.x - 20.0, 140.0, CageFloor.WINTER_AT.y + 60.0), Vector3(210.0, 4.0, 150.0))


## Icicles hanging from the top trim along the cold corner's two walls.
static func build_icicles(parent: Node3D, rng: RandomNumberGenerator) -> void:
	var k := CageKit.blank("Icicles", rng, &"rock")
	k.collision_layer = 0
	var y := GLASS_TOP - 7.0
	var hx := CageFloor.HX
	var hz := CageFloor.HZ
	var x := 120.0
	while x < hx:
		var len := rng.randf_range(4.0, 22.0) * smoothstep(80.0, 300.0, x)
		if len > 1.5:
			var at := Vector3(x, y, -hz + 1.2)
			k._cone(&"ice", at, at + Vector3(rng.randf_range(-0.5, 0.5), -len, 0.5), rng.randf_range(0.8, 1.8))
		x += rng.randf_range(4.0, 11.0)
	var z := -hz
	while z < 40.0:
		var len := rng.randf_range(4.0, 22.0) * smoothstep(60.0, -200.0, z)
		if len > 1.5:
			var at := Vector3(hx - 1.2, y, z)
			k._cone(&"ice", at, at + Vector3(-0.5, -len, rng.randf_range(-0.5, 0.5)), rng.randf_range(0.8, 1.8))
		z += rng.randf_range(4.0, 11.0)
	parent.add_child(k.finish())


static func _mist(parent: Node3D, at: Vector3, extents: Vector3) -> void:
	var p := GPUParticles3D.new()
	p.name = "FridgeMist"
	p.amount = 140
	p.lifetime = 26.0
	p.preprocess = 26.0
	p.visibility_aabb = AABB(Vector3(-700, -400, -200), Vector3(1400, 800, 900))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = extents
	pm.direction = Vector3(0, -0.15, 1)
	pm.spread = 18.0
	pm.initial_velocity_min = 7.0
	pm.initial_velocity_max = 12.0
	pm.gravity = Vector3(0, -1.2, 0)
	pm.damping_min = 0.15
	pm.damping_max = 0.3
	pm.scale_min = 0.6
	pm.scale_max = 1.4
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0.0))
	fade.set_color(1, Color(1, 1, 1, 0.0))
	fade.add_point(0.2, Color(1, 1, 1, 1.0))
	fade.add_point(0.75, Color(1, 1, 1, 0.7))
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	pm.color_ramp = ramp
	p.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(70.0, 45.0)
	var m := StandardMaterial3D.new()
	m.albedo_texture = FXTextures.soft_blob()
	m.albedo_color = Color(0.92, 0.97, 1.0, 0.13)
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	quad.material = m
	p.draw_pass_1 = quad
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(p)
	p.position = at


static func _snowfall(parent: Node3D, at: Vector3, extents: Vector3) -> void:
	var p := GPUParticles3D.new()
	p.name = "Snowfall"
	p.amount = 2600
	p.lifetime = 34.0
	p.preprocess = 34.0
	p.visibility_aabb = AABB(Vector3(-300, -160, -260), Vector3(600, 200, 520))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = extents
	pm.direction = Vector3(0.2, -1, 0.1)
	pm.spread = 25.0
	pm.initial_velocity_min = 2.5
	pm.initial_velocity_max = 4.5
	pm.gravity = Vector3(0, -0.4, 0)
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 1.5
	pm.turbulence_noise_scale = 6.0
	pm.scale_min = 0.6
	pm.scale_max = 1.3
	p.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.45, 0.45)
	var m := StandardMaterial3D.new()
	m.albedo_texture = FXTextures.soft_blob()
	m.albedo_color = Color(1, 1, 1, 0.9)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	quad.material = m
	p.draw_pass_1 = quad
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(p)
	p.position = at
