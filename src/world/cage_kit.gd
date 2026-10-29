class_name CageKit
extends Building
## Everything in the hamster cage that you can bump into, built in code like
## the island's buildings (one merged mesh per prop, every visible piece solid
## unless it says otherwise): the hamster wheel, Habitrail tube pods and
## tubes, cardboard rolls, hamster huts, the aquarium castle, an upturned ice
## cream tub, food and water bowls, chew blocks, giant seeds, frozen peas,
## ice cubes and popsicles. Toy plastics are glossy and saturated; wood,
## stone and snow use the soft PBR textures, so the cage matches the island.
##
## On top of Building's boxes, logs, cones and prisms this adds solids of
## revolution (`_lathe`, with matching concave collision), rings of panels
## (`_ring`: tubes, pods and the wheel's tread) and ellipsoids.

enum Kind { HUT, CASTLE, TUB }

const PLASTIC := {
	&"teal": Color(0.16, 0.72, 0.74), &"purple": Color(0.58, 0.38, 0.86), &"orange": Color(1.0, 0.55, 0.16),
	&"lime": Color(0.56, 0.86, 0.22), &"pink": Color(1.0, 0.5, 0.68), &"yellow": Color(1.0, 0.84, 0.22),
	&"blue": Color(0.26, 0.54, 0.98), &"red": Color(0.92, 0.22, 0.2), &"white": Color(0.95, 0.95, 0.93),
	&"black": Color(0.07, 0.07, 0.08),
}
const CERAMIC := {
	&"pink": Color(0.98, 0.66, 0.74), &"mint": Color(0.6, 0.9, 0.78), &"sky": Color(0.55, 0.78, 0.98),
	&"lemon": Color(1.0, 0.9, 0.5), &"white": Color(0.96, 0.95, 0.92), &"lilac": Color(0.78, 0.68, 0.96),
}

static var _cage_materials: Dictionary = {}
const TOY_SURFACE := preload("res://src/world/shaders/toy_surface.gdshader")
static var _toy_noise: NoiseTexture2D
static var _toy_bump: NoiseTexture2D

var _concave := PackedVector3Array()   # triangles of solid lathes (one concave shape)
var _dress: Array = []                 # [model path, Transform3D, {model material -> cage material key}, hull?]
var _keep: Dictionary = {}             # procedural surfaces still drawn under a dress
var _made := ""                        # this kit's Blender-refined model (assets/maps/<_made>.glb)
var _made_xf := Transform3D()
var _accents: Dictionary = {}          # accent slot -> the material key this kit drew for it

## Building the kits for tools/maps/refine.py (tests/export_kits.gd): no
## dressing, accent slots keep their names, materials are named by key.
static var exporting := false


static func make_kit(kind: Kind, rng: RandomNumberGenerator) -> CageKit:
	var k := CageKit.new()
	k._rng = rng
	k.collision_layer = Layers.WORLD
	k.set_meta(&"surface", &"wood")
	match kind:
		Kind.HUT:
			k.name = "Hut"
			k._build_hut()
		Kind.CASTLE:
			k.name = "Castle"
			k.set_meta(&"surface", &"rock")
			k._build_castle()
		Kind.TUB:
			k.name = "IceCreamTub"
			k._build_tub()
	k.made_as("cage/" + String(k.name).to_snake_case())
	return k.finish()


## An empty kit to build a prop into (see CageProps); call `finish()` after.
static func blank(name_: String, rng: RandomNumberGenerator, surface := &"wood") -> CageKit:
	var k := CageKit.new()
	k.name = name_
	k._rng = rng
	k.collision_layer = Layers.WORLD
	k.set_meta(&"surface", surface)
	return k


func finish() -> CageKit:
	if _made != "" and not exporting:
		dress("res://assets/maps/%s.glb" % _made, _made_xf, _accents)
	_commit()
	return self


## This kit has a refined model (tests/export_kits.gd -> tools/maps/refine.py:
## its own geometry, rebuilt clean in Blender): finish() dresses in it, at
## `xf` (for a model made at a reference size). Colliders stay the kit's.
func made_as(id: String, xf := Transform3D()) -> CageKit:
	_made = id
	_made_xf = xf
	return self


## Round pieces get twice the sides when built for a model (the colliders
## stay as they are).
func _segments(n: int) -> int:
	return n * 2 if exporting else n


## A material that varies per kit (a colour from the rng): the refined model
## has a slot named `slot` for it. Returns the key to build with.
func accent(slot: String, key: StringName) -> StringName:
	_accents[slot] = key
	return StringName(slot) if exporting else key


## Dress the kit in a model (assets/maps, made in Blender by tools/maps, or a
## downloaded one in assets/env): the procedural pieces still make its
## colliders, footprint, floor and loot spots, but what you see is the model,
## at `xf` in the kit's own space. A model material named "cage:<key>" (or
## listed in `mats`, model name -> key) is drawn with the cage's material for
## that key. Without the model file the kit keeps its procedural look.
## With `hull`, the model's convex hull is a collider, and the kit's own
## colliders go (for a model shaped unlike the primitives it replaces).
func dress(path: String, xf := Transform3D(), mats := {}, hull := false) -> CageKit:
	if ResourceLoader.exists(path):
		_dress.append([path, xf, mats, hull])
	return self


## Procedural surfaces (by material key) to keep drawing under a dress.
func keep_surfaces(keys: Array) -> CageKit:
	for key in keys:
		_keep[StringName(key)] = true
	return self


## A map model, its "cage:<key>" materials swapped for the cage's own.
static func model(path: String, mats := {}) -> Node3D:
	var root := ModelUtil.instantiate(path)
	if root == null:
		return null
	root.name = "Model"
	for mi in ModelUtil.find_all(root, "MeshInstance3D"):
		var mesh: Mesh = (mi as MeshInstance3D).mesh
		for i in mesh.get_surface_count():
			var key := _cage_key(mesh.surface_get_material(i), mats)
			if key != &"":
				(mi as MeshInstance3D).set_surface_override_material(i, mat(key))
	return root


## A convex collider round a model (its points in kit space: the shape itself
## is never scaled, which Jolt dislikes).
func _hull(m: Node3D) -> void:
	var pts := PackedVector3Array()
	for mi in ModelUtil.find_all(m, "MeshInstance3D"):
		var shape := (mi as MeshInstance3D).mesh.create_convex_shape(true, true)
		var xf := m.transform * ModelUtil._relative_xform(m, mi)
		for p in shape.points:
			pts.append(xf * p)
	if pts.size() < 4:
		return
	var cs := CollisionShape3D.new()
	var hull := ConvexPolygonShape3D.new()
	hull.points = pts
	cs.shape = hull
	add_child(cs)


## A map model's mesh with the cage's materials baked in (for MultiMeshes).
static func model_mesh(path: String, mats := {}) -> Mesh:
	var src := ModelUtil.first_mesh(path)
	if src == null:
		return null
	var mesh := src.duplicate() as Mesh
	for i in mesh.get_surface_count():
		var key := _cage_key(mesh.surface_get_material(i), mats)
		if key != &"":
			mesh.surface_set_material(i, mat(key))
	return mesh


## One mesh from several map models, for MultiMesh ground cover: `parts` is
## [[model path, Transform3D], ...] (rotation and uniform scale).
static func cluster_mesh(parts: Array, mats := {}) -> ArrayMesh:
	var out := ArrayMesh.new()
	for part in parts:
		var src := model_mesh(part[0], mats)
		if src == null:
			continue
		var xf: Transform3D = part[1]
		var rot := xf.basis.orthonormalized()
		for i in src.get_surface_count():
			var arr := src.surface_get_arrays(i)
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			for j in v.size():
				v[j] = xf * v[j]
			arr[Mesh.ARRAY_VERTEX] = v
			if arr[Mesh.ARRAY_NORMAL] != null:
				var n: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
				for j in n.size():
					n[j] = rot * n[j]
				arr[Mesh.ARRAY_NORMAL] = n
			if arr[Mesh.ARRAY_TANGENT] != null:
				var t: PackedFloat32Array = arr[Mesh.ARRAY_TANGENT]
				for j in range(0, t.size(), 4):
					var tv := rot * Vector3(t[j], t[j + 1], t[j + 2])
					t[j] = tv.x
					t[j + 1] = tv.y
					t[j + 2] = tv.z
				arr[Mesh.ARRAY_TANGENT] = t
			out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
			out.surface_set_material(out.get_surface_count() - 1, src.surface_get_material(i))
	return out


## (exporting) A plain material named for its key, so the model keeps it.
static func _export_mat(key: StringName) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.resource_name = String(key) if String(key).begins_with("accent") else "cage:" + String(key)
	var real := mat(key) if not String(key).begins_with("accent") else null
	if real is StandardMaterial3D:
		m.albedo_color = (real as StandardMaterial3D).albedo_color
	elif real is ShaderMaterial and (real as ShaderMaterial).get_shader_parameter(&"albedo") is Color:
		m.albedo_color = (real as ShaderMaterial).get_shader_parameter(&"albedo")
	return m


static func _cage_key(m: Material, mats: Dictionary) -> StringName:
	var n := m.resource_name if m else ""
	if mats.has(n):
		return StringName(mats[n])
	return StringName(n.trim_prefix("cage:")) if n.begins_with("cage:") else &""


# ---- walk-in buildings ----------------------------------------------------------------------

## Hamster Hut: the wooden house from every pet shop, at critter scale. Honey
## coloured planks, an arched front door and a back door, round windows and
## a painted gable roof.
func _build_hut() -> void:
	var w := 17.0
	var d := 13.0
	var wall_h := 7.0
	var t := 0.5
	footprint = 14.0
	floor_y = 0.12
	var roof := accent("accent", [&"paint_red", &"paint_blue", &"paint_teal", &"paint_purple"][_rng.randi() % 4])
	_box(&"wood_light", Vector3(0, floor_y - 0.6, 0), Vector3(w + 0.6, 1.2, d + 0.6))
	for zs in [1.0, -1.0]:
		_plank_wall(&"wood_honey", Vector3(-w * 0.5, floor_y, zs * d * 0.5), Vector3(w * 0.5, floor_y, zs * d * 0.5), wall_h, t,
			[[0.0 if zs > 0 else 3.0, Building.DOOR_W + 0.4, 0.0, Building.DOOR_H + 0.4], [-5.2, 2.2, 3.0, 5.2], [5.2, 2.2, 3.0, 5.2]])
	for xs in [1.0, -1.0]:
		_plank_wall(&"wood_honey", Vector3(xs * w * 0.5, floor_y, -d * 0.5), Vector3(xs * w * 0.5, floor_y, d * 0.5), wall_h, t,
			[[0.0, 2.6, 2.8, 5.4]])
	# arch over the front door: a half ring of thick slats
	var arch_y := floor_y + Building.DOOR_H + 0.4
	for i in 7:
		var a0 := PI * i / 7.0
		var a1 := PI * (i + 1) / 7.0
		var r := (Building.DOOR_W + 0.4) * 0.5 + 0.3
		var p0 := Vector3(cos(a0) * r, arch_y + sin(a0) * r * 0.32, d * 0.5 + 0.3)
		var p1 := Vector3(cos(a1) * r, arch_y + sin(a1) * r * 0.32, d * 0.5 + 0.3)
		_log(roof, p0, p1, 0.28, false)
	# painted gable roof (ridge along X) with a little overhang, plank gable ends
	var ridge := floor_y + wall_h + 4.6
	_gable_roof(roof, w + 2.6, d + 2.4, floor_y + wall_h, ridge, 0.5)
	for xs in [1.0, -1.0]:
		_gable_end(&"wood_honey", d - 0.2, floor_y + wall_h, ridge - 0.3, xs * (w * 0.5 - 0.05), t)
	# chew-toy furniture: a block table and a seed sack
	_box(&"wood_light", Vector3(-4.5, floor_y + 0.9, -3.0), Vector3(3.2, 1.8, 2.2))
	_box(&"paint_yellow", Vector3(4.6, floor_y + 0.8, -3.6), Vector3(2.0, 1.6, 2.0))
	loot_spots = [Vector3(-4.0, floor_y, 2.6), Vector3(4.0, floor_y, 2.6), Vector3(0.0, floor_y, -3.8),
		Vector3(-6.2, floor_y, -0.5), Vector3(6.2, floor_y, 0.5)]
	chest_spot = Vector3(1.8, floor_y, -4.6)


## Aquarium castle ornament: crenellated grey stone walls round a courtyard,
## four round towers with pointed pink roofs and a big arched gate.
func _build_castle() -> void:
	var s := 24.0
	var wall_h := 9.0
	var t := 1.2
	footprint = 20.0
	floor_y = 0.15
	_box(&"stone", Vector3(0, floor_y - 0.8, 0), Vector3(s + 2.0, 1.6, s + 2.0))
	_plank_wall(&"stone", Vector3(-s * 0.5, floor_y, s * 0.5), Vector3(s * 0.5, floor_y, s * 0.5), wall_h, t, [[0.0, 6.0, 0.0, 6.6]])
	_plank_wall(&"stone", Vector3(-s * 0.5, floor_y, -s * 0.5), Vector3(s * 0.5, floor_y, -s * 0.5), wall_h, t, [[4.0, 5.0, 0.0, 6.0]])
	for xs in [1.0, -1.0]:
		_plank_wall(&"stone", Vector3(xs * s * 0.5, floor_y, -s * 0.5), Vector3(xs * s * 0.5, floor_y, s * 0.5), wall_h, t,
			[[0.0, 2.4, 4.0, 6.4]])
	# crenellations (merlons) along every wall top
	for side in 4:
		var basis := Basis(Vector3.UP, side * PI * 0.5)
		for i in 8:
			var x := -s * 0.5 + 2.0 + i * (s - 4.0) / 7.0
			_box(&"stone", basis * Vector3(x, floor_y + wall_h + 0.8, s * 0.5), Vector3(1.6, 1.6, t + 0.2), basis, true)
	# arched gate trim
	for i in 6:
		var a0 := PI * i / 6.0
		var a1 := PI * (i + 1) / 6.0
		_log(&"stone_dark", Vector3(cos(a0) * 3.4, floor_y + 6.6 + sin(a0) * 2.0, s * 0.5 + 0.7),
			Vector3(cos(a1) * 3.4, floor_y + 6.6 + sin(a1) * 2.0, s * 0.5 + 0.7), 0.5, false)
	# corner towers: stone drums with crenels and pointed roofs
	for xs in [1.0, -1.0]:
		for zs in [1.0, -1.0]:
			var c := Vector3(xs * s * 0.5, floor_y, zs * s * 0.5)
			_log(&"stone", c + Vector3.DOWN * 0.5, c + Vector3.UP * (wall_h + 5.0), 3.6)
			_lathe(&"stone", [Vector2(4.2, wall_h + 5.0), Vector2(4.2, wall_h + 6.4), Vector2(3.4, wall_h + 6.4), Vector2(3.4, wall_h + 5.0)],
				16, c, false)
			_cone(&"plastic_pink", c + Vector3.UP * (wall_h + 6.3), c + Vector3.UP * (wall_h + 13.0), 4.0)
			# arrow-slit windows (dark strips)
			for k in 3:
				var a := TAU * k / 3.0 + (0.4 if xs > 0 else 1.2)
				_box(&"stone_dark", c + Vector3(cos(a) * 3.62, wall_h * 0.6 + k * 1.2, sin(a) * 3.62), Vector3(0.5, 2.0, 0.2),
					Basis(Vector3.UP, -a + PI * 0.5), false)
	# a little keep in the courtyard's back corner: cover and a perch
	_box(&"stone", Vector3(-6.0, floor_y + 2.0, -6.0), Vector3(6.0, 4.0, 6.0))
	_box(&"stone_dark", Vector3(-6.0, floor_y + 4.2, -6.0), Vector3(6.4, 0.4, 6.4))
	loot_spots = [Vector3(5.0, floor_y, 5.0), Vector3(-6.0, floor_y, 5.5), Vector3(6.0, floor_y, -5.0),
		Vector3(0.5, floor_y, -1.0), Vector3(-1.5, floor_y, 7.5)]
	chest_spot = Vector3(-6.0, floor_y + 4.0, -6.0)


## An ice cream tub tipped upside down in the snow, a doorway chewed in its
## side: a round walk-in igloo with a striped label band and a domed lid.
func _build_tub() -> void:
	var r_base := 12.0
	var r_top := 10.5
	var h := 10.0
	footprint = 15.0
	floor_y = 0.1
	_lathe(&"snow", [Vector2(0.0, floor_y - 0.3), Vector2(r_base + 0.5, floor_y - 0.3), Vector2(r_base + 0.5, floor_y + 0.1), Vector2(0.0, floor_y + 0.1)], 24, Vector3.ZERO, false)
	# the side wall: panels round the rim, with the doorway gap facing +Z
	var seg := 24
	for i in seg:
		var a := TAU * (i + 0.5) / seg
		var gap := absf(wrapf(a - PI * 0.5, -PI, PI))
		if gap < 0.32:
			continue
		var r_mid := (r_base + r_top) * 0.5
		var c := Vector3(cos(a) * r_mid, floor_y + h * 0.5, sin(a) * r_mid)
		var tilt := atan2(r_base - r_top, h)
		var basis := Basis(Vector3.UP, -a + PI * 0.5) * Basis(Vector3.RIGHT, -tilt)
		var mat: StringName = &"plastic_pink" if int(i / 3) % 2 == 0 else &"plastic_white"
		_box(mat, c, Vector3(TAU * r_mid / seg + 0.25, h / cos(tilt), 0.45), basis)
	# the domed lid on top (the tub's bottom, really) and a label band
	_lathe(&"plastic_white", [Vector2(r_top + 0.3, floor_y + h), Vector2(r_top + 0.3, floor_y + h + 0.6), Vector2(r_top * 0.8, floor_y + h + 1.6),
		Vector2(0.0, floor_y + h + 1.9)], 24, Vector3.ZERO, true)
	_lathe(&"plastic_white", [Vector2(0.0, floor_y + h), Vector2(r_top + 0.3, floor_y + h)], 24, Vector3.ZERO, false)   # the ceiling
	for i in 4:
		var y := floor_y + 2.0 + i * 1.8
		var rr := lerpf(r_base, r_top, (y - floor_y) / h) + 0.28
		_lathe(&"plastic_brown" if i % 2 == 0 else &"plastic_yellow", [Vector2(rr, y), Vector2(rr, y + 0.5)], 24, Vector3.ZERO, false, 0.0)
	# a scoop of "snow" ice cream spilling out of the door
	_ellipsoid(&"snow", Vector3(0, floor_y + 0.2, r_base + 1.5), Vector3(3.0, 1.2, 2.2), Basis(), false)
	loot_spots = [Vector3(-5.0, floor_y, 0.0), Vector3(5.0, floor_y, 0.0), Vector3(0.0, floor_y, -5.5), Vector3(-3.0, floor_y, 5.0)]
	chest_spot = Vector3(0.0, floor_y, -2.0)


# ---- primitives --------------------------------------------------------------------------------

## A solid of revolution about +Y through `centre`. `profile` is (radius, y)
## points; the surface faces the side to the right of the profile's direction
## in the (radius, y) plane. `solid` adds it to the prop's concave collider.
## `dir` < 0 flips which side faces out (for the inside of a bowl, say).
func _lathe(mat: StringName, profile: Array, seg: int, centre: Vector3, solid := true, uv_scale := 1.0) -> void:
	seg = _segments(seg)
	var st := _st(mat)
	for i in profile.size() - 1:
		var p0: Vector2 = profile[i]
		var p1: Vector2 = profile[i + 1]
		var d := (p1 - p0).normalized()
		var n2 := Vector2(d.y, -d.x)
		for k in seg:
			var a0 := TAU * k / seg
			var a1 := TAU * (k + 1) / seg
			var v00 := centre + Vector3(cos(a0) * p0.x, p0.y, sin(a0) * p0.x)
			var v01 := centre + Vector3(cos(a1) * p0.x, p0.y, sin(a1) * p0.x)
			var v10 := centre + Vector3(cos(a0) * p1.x, p1.y, sin(a0) * p1.x)
			var v11 := centre + Vector3(cos(a1) * p1.x, p1.y, sin(a1) * p1.x)
			var am := (a0 + a1) * 0.5
			var n := Vector3(cos(am) * n2.x, n2.y, sin(am) * n2.x).normalized()
			if absf(d.y) < 0.35:
				# flat-ish ring: map the texture from above, not round the axis
				var q := func(v: Vector3) -> Vector2: return Vector2(v.x, v.z) * uv_scale
				_face(st, [v00, v10, v11], [q.call(v00), q.call(v10), q.call(v11)], n, solid)
				_face(st, [v00, v11, v01], [q.call(v00), q.call(v11), q.call(v01)], n, solid)
				continue
			var u0 := a0 * maxf(p0.x, 1.0) * uv_scale
			var u1 := a1 * maxf(p0.x, 1.0) * uv_scale
			_face(st, [v00, v10, v11], [Vector2(u0, p0.y), Vector2(u0, p1.y), Vector2(u1, p1.y)], n, solid)
			_face(st, [v00, v11, v01], [Vector2(u0, p0.y), Vector2(u1, p1.y), Vector2(u1, p0.y)], n, solid)


## A ring of flat panels round an axis (a tube, a pod's wall, a wheel's
## tread): `seg` panels at `radius` (to their inner face), `thick` deep,
## `length` along the axis. `basis.y` is the axis; panel k sits at angle
## TAU*k/seg from `basis.x` toward `basis.z`. Panels whose middle angle falls
## inside a gap [angle, width] are left out (doorways).
func _ring(mat: StringName, centre: Vector3, basis: Basis, radius: float, length: float, thick: float, seg: int,
		gaps := [], solid := true, phase := 0.0) -> void:
	if gaps.is_empty():
		seg = _segments(seg)   # (with doorways, keep the collider's panels: the openings must match)
	var width := 2.0 * (radius + thick) * tan(PI / seg) + 0.04
	for k in seg:
		var a := TAU * k / seg + phase
		var skip := false
		for g in gaps:
			if absf(wrapf(a - float(g[0]), -PI, PI)) < float(g[1]) * 0.5:
				skip = true
		if skip:
			continue
		var out := basis.x * cos(a) + basis.z * sin(a)
		var tangent := basis.y.cross(out).normalized()
		var c := centre + out * (radius + thick * 0.5)
		_box(mat, c, Vector3(width, length, thick), Basis(tangent, basis.y.normalized(), out), solid)


## An ellipsoid (radii along the basis axes); solid ones collide as a convex hull.
func _ellipsoid(mat: StringName, centre: Vector3, radii: Vector3, basis := Basis(), solid := true, rings := 8, seg := 14) -> void:
	rings = _segments(rings)
	seg = _segments(seg)
	var st := _st(mat)
	var pts := PackedVector3Array()
	for i in rings:
		var t0 := PI * i / rings - PI * 0.5
		var t1 := PI * (i + 1) / rings - PI * 0.5
		for k in seg:
			var a0 := TAU * k / seg
			var a1 := TAU * (k + 1) / seg
			var q := [Vector2(a0, t0), Vector2(a0, t1), Vector2(a1, t1), Vector2(a1, t0)]
			var vs := []
			var ns := []
			var uvs := []
			for e in q:
				var unit := Vector3(cos(e.y) * cos(e.x), sin(e.y), cos(e.y) * sin(e.x))
				vs.append(centre + basis * (unit * radii))
				ns.append((basis * (unit / radii)).normalized())
				uvs.append(Vector2(e.x / TAU * 4.0, e.y / PI + 0.5))
			for tri in [[0, 1, 2], [0, 2, 3]]:
				var a: Vector3 = vs[tri[0]]
				var b: Vector3 = vs[tri[1]]
				var c: Vector3 = vs[tri[2]]
				if (b - a).cross(c - a).length_squared() < 1e-10:
					continue
				var nn: Vector3 = (ns[tri[0]] + ns[tri[1]] + ns[tri[2]]).normalized()
				var order := [0, 1, 2] if (b - a).cross(c - a).dot(nn) < 0.0 else [0, 2, 1]
				for o in order:
					st.set_normal(ns[tri[o]])
					st.set_uv(uvs[tri[o]])
					st.add_vertex(vs[tri[o]])
			pts.append(vs[0])
	if solid:
		pts.append(centre + basis * Vector3(0, radii.y, 0))
		var cs := CollisionShape3D.new()
		var hull := ConvexPolygonShape3D.new()
		hull.points = pts
		cs.shape = hull
		add_child(cs)


## A toy alphabet block: a box whose six faces each show one cell of the
## letter atlas (see `_letters`), cells[i] for face i (+X, -X, +Y, -Y, +Z, -Z).
func _letter_box(c: Vector3, size: float, basis: Basis, cells: Array, solid := true) -> void:
	var st := _st(&"abc")
	var h := size * 0.5
	var axes := [basis.x, -basis.x, basis.y, -basis.y, basis.z, -basis.z]
	for f in 6:
		var n: Vector3 = axes[f]
		# side faces read left to right, upright, seen from outside
		var side := absf(n.dot(basis.y)) < 0.5
		var u: Vector3 = basis.y.cross(n).normalized() if side else basis.x
		var v: Vector3 = -basis.y if side else basis.z
		var cell: int = cells[f % cells.size()]
		var c0 := Vector2(cell % 4, cell / 4) * 0.25
		var centre := c + n * h
		var p := [centre - u * h - v * h, centre + u * h - v * h, centre + u * h + v * h, centre - u * h + v * h]
		var uv := [c0 + Vector2(0.0, 0.0), c0 + Vector2(0.25, 0.0), c0 + Vector2(0.25, 0.25), c0 + Vector2(0.0, 0.25)]
		_face(st, [p[0], p[1], p[2]], [uv[0], uv[1], uv[2]], n, false)
		_face(st, [p[0], p[2], p[3]], [uv[0], uv[2], uv[3]], n, false)
	if solid:
		_collide(c, Vector3.ONE * size, basis)


## A cylinder from a to b (a log with this kit's materials); thin wrapper.
func _rod(mat: StringName, a: Vector3, b: Vector3, r: float, solid := true) -> void:
	_log(mat, a, b, r, solid)


## A sloped walkway from `a` (bottom) to `b` (top), `width` wide: a board with
## cross slats on top, solid and smooth enough for the navmesh.
func _ramp(mat: StringName, a: Vector3, b: Vector3, width: float, slats := &"") -> void:
	var dir := (b - a)
	var length := dir.length()
	var f := dir / length
	var side := f.cross(Vector3.UP).normalized()
	var up := side.cross(f).normalized() * -1.0
	if up.y < 0.0:
		up = -up
	var basis := Basis(side, up, -f)
	_box(mat, (a + b) * 0.5 - up * 0.2, Vector3(width, 0.4, length), basis)
	if slats != &"":
		var n := int(length / 1.6)
		for i in n:
			var p := a.lerp(b, (i + 0.5) / n) + up * 0.08
			_box(slats, p, Vector3(width - 0.2, 0.16, 0.35), basis, false)


func _face(st: SurfaceTool, p: Array, uv: Array, n: Vector3, solid: bool) -> void:
	var order := [0, 1, 2] if (p[1] - p[0]).cross(p[2] - p[0]).dot(n) < 0.0 else [0, 2, 1]
	for k in order:
		st.set_normal(n)
		st.set_uv(uv[k])
		st.add_vertex(p[k])
	if solid:
		for k in order:
			_concave.append(p[k])


func _commit() -> void:
	if not _dress.is_empty():
		for key in _surfaces.keys():
			if not _keep.has(key):
				_surfaces.erase(key)
		if _dress.any(func(d): return d[3]):
			for c in get_children():
				if c is CollisionShape3D:
					remove_child(c)
					c.free()
			_concave = PackedVector3Array()
		for d in _dress:
			var m := model(d[0], d[2])
			if m:
				m.transform = d[1]
				add_child(m)
				if d[3]:
					_hull(m)
		_dress.clear()
	var mesh := ArrayMesh.new()
	for key in _surfaces:
		var st: SurfaceTool = _surfaces[key]
		st.generate_tangents()
		st.commit(mesh)
		mesh.surface_set_material(mesh.get_surface_count() - 1, _export_mat(key) if exporting else mat(key))
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = mesh
	add_child(mi)
	_surfaces.clear()
	if not _concave.is_empty():
		var cs := CollisionShape3D.new()
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(_concave)
		shape.backface_collision = true
		cs.shape = shape
		add_child(cs)
		_concave = PackedVector3Array()


# ---- materials ---------------------------------------------------------------------------------

## The cage's materials by key (falls back to Building's textured ones).
## plastic_<colour>, ceramic_<colour>, paint_<colour> (painted wood), wood_light,
## wood_honey, cardboard, cardboard_in, stone, stone_dark, snow, ice, metal,
## seed_shell, pellet, and a few foods.
static func mat(key: StringName) -> Material:
	if _cage_materials.has(key):
		return _cage_materials[key]
	var s := String(key)
	var m: Material
	if s.begins_with("plastic_"):
		var c: Color = PLASTIC.get(StringName(s.substr(8)), Color.WHITE) if s != "plastic_brown" else Color(0.45, 0.26, 0.14)
		m = _toy(c, 0.32, 0.35, 1.0, 1.6)
	elif s.begins_with("ceramic_"):
		m = _gloss(CERAMIC.get(StringName(s.substr(8)), Color.WHITE), 0.12, 1.0)
	elif s.begins_with("tube_"):
		# see-through Habitrail plastic, tinted
		var tc: Color = PLASTIC.get(StringName(s.substr(5)), Color.WHITE)
		var tm := _clear(Color(tc.r, tc.g, tc.b, 0.4), 0.05)
		tm.rim_tint = 0.6
		tm.emission_enabled = true
		tm.emission = tc * 0.25
		m = tm
	elif s.begins_with("crayon_"):
		m = _toy(PLASTIC.get(StringName(s.substr(7)), Color.WHITE) * 0.92, 0.75, 0.0, 1.6, 0.9)   # (waxy)
	elif s.begins_with("pillow_"):
		m = _soft("plaid", 7.0, PLASTIC.get(StringName(s.substr(7)), Color.WHITE).lerp(Color.WHITE, 0.45), 0.6, 1.0)
	elif s.begins_with("paint_"):
		var tint: Color = PLASTIC.get(StringName(s.substr(6)), Color.WHITE)
		m = _soft("planks", 2.4, tint, 0.45, 1.0)
	else:
		match key:
			&"wood_light":
				m = _soft("floorboards", 2.6, Color(1.35, 1.18, 0.92), 0.6)
			&"wood_honey":
				m = _soft("planks", 2.4, Color(1.5, 1.15, 0.72), 0.6)
			&"stone":
				m = _soft("rock", 4.0, Color(0.86, 0.84, 0.88), 0.55, 1.0)
			&"stone_dark":
				m = _soft("rock", 4.0, Color(0.5, 0.5, 0.56), 0.55, 1.0)
			&"snow":
				m = _soft("snow", 6.0, Color(1.12, 1.16, 1.22), 0.6, 1.0)
			&"cardboard":
				m = _toy(Color(0.76, 0.58, 0.38), 0.9, 0.0, 1.8, 2.4, 0.1)   # (fibrous)
			&"coconut":
				m = _soft("bark", 3.0, Color(0.62, 0.42, 0.27), 0.75, 1.0)
			&"coconut_in":
				m = _flat(Color(0.95, 0.92, 0.84), 0.8)
			&"cardboard_in":
				m = _flat(Color(0.6, 0.44, 0.28), 0.95)
			&"ice":
				var ice := StandardMaterial3D.new()
				ice.albedo_color = Color(0.78, 0.92, 1.0, 0.72)
				ice.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
				ice.roughness = 0.06
				ice.metallic_specular = 0.9
				ice.rim_enabled = true
				ice.rim = 0.6
				ice.emission_enabled = true
				ice.emission = Color(0.35, 0.6, 0.8)
				ice.emission_energy_multiplier = 0.25
				m = ice
			&"metal":
				var mt := StandardMaterial3D.new()
				mt.albedo_color = Color(0.78, 0.8, 0.84)
				mt.metallic = 0.9
				mt.roughness = 0.22
				m = mt
			&"seed_shell":
				m = _gloss(Color(0.16, 0.15, 0.15), 0.5, 0.0)
				(m as StandardMaterial3D).albedo_texture = _stripes()
			&"pellet":
				m = _flat(Color(0.78, 0.6, 0.38), 0.85)
			&"broccoli":
				m = _flat(Color(0.28, 0.55, 0.18), 0.8)
			&"broccoli_stem":
				m = _flat(Color(0.62, 0.78, 0.38), 0.7)
			&"carrot":
				m = _gloss(Color(1.0, 0.5, 0.1), 0.45, 0.2)
			&"corn":
				m = _gloss(Color(1.0, 0.82, 0.25), 0.35, 0.3)
			&"pea":
				m = _gloss(Color(0.42, 0.78, 0.25), 0.3, 0.4)
			&"frost":
				m = _flat(Color(0.88, 0.95, 1.0), 0.9)
			&"apple_skin":
				m = _gloss(Color(0.85, 0.12, 0.12), 0.25, 0.6)
			&"apple_flesh":
				m = _flat(Color(1.0, 0.95, 0.78), 0.7)
			&"shell":
				m = _gloss(Color(1.0, 0.82, 0.76), 0.35, 0.4)
			&"popsicle_stick":
				m = _flat(Color(0.88, 0.74, 0.5), 0.8)
			&"paper_fluff":
				m = _flat(Color(0.97, 0.95, 0.9), 0.95)
			&"shaving":   # (a big curl of the bedding's own pale pine)
				m = _flat(Color(0.96, 0.84, 0.62), 0.9)
			# the room and the fridge
			&"laminate":
				m = _soft("laminate", 90.0, Color(1.05, 1.0, 0.95), 0.8)
			&"wall_paint":   # (rolled-on emulsion over plaster: a faint stipple and patchiness)
				m = _toy(Color(0.94, 0.86, 0.72), 0.92, 0.0, 0.7, 0.9, 0.09, 0.3)
			&"ceiling":
				m = _toy(Color(0.97, 0.96, 0.93), 0.95, 0.0, 0.5, 0.9, 0.05, 0.0)
			&"rug":
				m = _flat(Color(0.42, 0.62, 0.7), 1.0)
			&"rug_border":
				m = _flat(Color(0.95, 0.85, 0.55), 1.0)
			&"curtain":
				m = _flat(Color(0.98, 0.62, 0.68), 0.95)
			&"couch":
				m = _flat(Color(0.36, 0.42, 0.72), 0.95)
			&"cushion":
				m = _flat(Color(0.98, 0.82, 0.45), 0.95)
			&"lamp":
				var lamp := _flat(Color(1.0, 0.97, 0.88), 0.5)
				lamp.emission_enabled = true
				lamp.emission = Color(1.0, 0.94, 0.8)
				lamp.emission_energy_multiplier = 2.0
				m = lamp
			&"enamel":
				m = _gloss(Color(0.96, 0.96, 0.95), 0.18, 0.7)
			&"liner":
				var liner := _flat(Color(0.9, 0.95, 1.0), 0.4)
				liner.emission_enabled = true
				liner.emission = Color(0.75, 0.88, 1.0)
				liner.emission_energy_multiplier = 0.45
				m = liner
			&"shelf_glass":
				m = _clear(Color(0.78, 0.92, 1.0, 0.25), 0.05)
			&"milk":
				m = _flat(Color(0.98, 0.98, 0.96), 0.6)
			&"cheese":
				m = _flat(Color(1.0, 0.8, 0.28), 0.6)
			&"egg_carton":
				m = _flat(Color(0.72, 0.68, 0.62), 1.0)
			&"egg":
				m = _flat(Color(0.98, 0.9, 0.78), 0.55)
			&"jam":
				m = _clear(Color(0.7, 0.05, 0.15, 0.85), 0.1)
			&"butter":
				m = _flat(Color(1.0, 0.92, 0.55), 0.5)
			&"soda":
				m = _clear(Color(0.3, 0.75, 0.35, 0.6), 0.05)
			&"leftovers":
				m = _clear(Color(0.95, 0.95, 1.0, 0.5), 0.1)
			&"ketchup":
				m = _gloss(Color(0.85, 0.08, 0.06), 0.25, 0.5)
			&"mustard":
				m = _gloss(Color(1.0, 0.82, 0.1), 0.3, 0.4)
			&"lettuce":
				m = _flat(Color(0.55, 0.85, 0.35), 0.7)
			# Toy Box Bash
			&"abc":
				var abc := _flat(Color.WHITE, 0.55)
				abc.albedo_texture = _letters()
				m = abc
			&"gingham":
				m = _soft("gingham", 9.0, Color(1.0, 1.0, 1.0), 0.75)
			&"plaid":
				m = _soft("plaid", 9.0, Color(1.05, 1.03, 1.0), 0.75)
			&"fur":
				m = _flat(Color(0.62, 0.42, 0.24), 1.0)
			&"fur_light":
				m = _flat(Color(0.86, 0.72, 0.52), 1.0)
			&"button_eye":
				m = _gloss(Color(0.04, 0.03, 0.03), 0.15, 1.0)
			&"bowl_glass":
				m = _clear(Color(0.86, 0.95, 1.0, 0.16), 0.03)
			&"paper":
				m = _toy(Color(0.97, 0.97, 0.94), 0.85, 0.0, 0.8, 3.0, 0.03, 0.4)
			&"domino":
				m = _gloss(Color(0.08, 0.08, 0.09), 0.25, 0.8)
			&"coin":
				var coin := StandardMaterial3D.new()
				coin.albedo_color = Color(1.0, 0.78, 0.25)
				coin.metallic = 0.95
				coin.roughness = 0.25
				m = coin
			&"track":
				m = _gloss(Color(1.0, 0.45, 0.08), 0.35, 0.3)
			&"rail_wood":
				m = _soft("floorboards", 3.0, Color(1.45, 1.25, 0.95), 0.5)
			&"wallpaper":
				var wp := _flat(Color.WHITE, 0.9)
				wp.albedo_texture = _wallpaper()
				wp.uv1_scale = Vector3(1.0 / 160.0, 1.0 / 160.0, 1.0)
				m = wp
			&"rail_groove":
				m = _flat(Color(0.42, 0.27, 0.15), 0.85)
			&"pebble_mix":
				m = _soft("pebbles", 5.0, Color(1.2, 1.1, 1.25), 0.8)
			&"oak":
				m = _soft("oak_floor", 60.0, Color(1.0, 1.0, 1.0), 0.75)
			&"glow_star":
				var gs := _flat(Color(1.0, 0.92, 0.5), 0.6)
				gs.emission_enabled = true
				gs.emission = Color(1.0, 0.9, 0.45)
				gs.emission_energy_multiplier = 0.6
				m = gs
			&"bottle_glass":
				m = _clear(Color(0.85, 0.95, 1.0, 0.22), 0.04)
			&"bottle_water":
				m = _clear(Color(0.35, 0.68, 0.98, 0.5), 0.05)
			&"ball_plastic":
				m = _clear(Color(0.82, 0.68, 1.0, 0.28), 0.08)
			_:
				return Building.material(key)
	_cage_materials[key] = m
	return m


## A toy's surface (see toy_surface.gdshader): moulded plastic, crayon wax,
## cardboard or paper with a fine bump, mottling and a few scuffs.
static func _toy(c: Color, rough: float, coat: float, grain: float, grain_scale: float, mottle := 0.06, wear := 1.0) -> ShaderMaterial:
	if _toy_noise == null:
		var fn := FastNoiseLite.new()
		fn.frequency = 0.02
		fn.fractal_octaves = 4
		_toy_noise = NoiseTexture2D.new()
		_toy_noise.width = 256
		_toy_noise.height = 256
		_toy_noise.seamless = true
		_toy_noise.generate_mipmaps = true
		_toy_noise.noise = fn
		var bn := FastNoiseLite.new()
		bn.frequency = 0.08
		bn.fractal_octaves = 3
		_toy_bump = NoiseTexture2D.new()
		_toy_bump.width = 256
		_toy_bump.height = 256
		_toy_bump.seamless = true
		_toy_bump.as_normal_map = true
		_toy_bump.bump_strength = 6.0
		_toy_bump.generate_mipmaps = true
		_toy_bump.noise = bn
	var sm := ShaderMaterial.new()
	sm.shader = TOY_SURFACE
	sm.set_shader_parameter(&"albedo", c)
	sm.set_shader_parameter(&"roughness", rough)
	sm.set_shader_parameter(&"clearcoat", coat)
	sm.set_shader_parameter(&"grain", grain)
	sm.set_shader_parameter(&"grain_scale", grain_scale)
	sm.set_shader_parameter(&"mottle", mottle)
	sm.set_shader_parameter(&"wear", wear)
	sm.set_shader_parameter(&"noise_tex", _toy_noise)
	sm.set_shader_parameter(&"bump_tex", _toy_bump)
	return sm


static func _gloss(c: Color, rough: float, coat: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	if coat > 0.0:
		m.clearcoat_enabled = true
		m.clearcoat = coat
		m.clearcoat_roughness = 0.2
	return m


static func _clear(c: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = rough
	m.metallic_specular = 0.9
	m.rim_enabled = true
	m.rim = 0.4
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


static func _flat(c: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m


static func _soft(folder: String, metres: float, tint: Color, detail: float, recolor := 0.0) -> ShaderMaterial:
	var sm := ShaderMaterial.new()
	sm.shader = Building.SOFT_SHADER
	var alb := Building._tex(Building.TEXTURES % [folder, "albedo.jpg"])
	var nrm := Building._tex(Building.TEXTURES % [folder, "normal.png"])
	var rgh := Building._tex(Building.TEXTURES % [folder, "roughness.jpg"])
	sm.set_shader_parameter(&"albedo_tex", alb)
	sm.set_shader_parameter(&"use_albedo", alb != null)
	sm.set_shader_parameter(&"normal_tex", nrm)
	sm.set_shader_parameter(&"use_normal", nrm != null)
	sm.set_shader_parameter(&"rough_tex", rgh)
	sm.set_shader_parameter(&"use_rough", rgh != null)
	sm.set_shader_parameter(&"tint", tint)
	sm.set_shader_parameter(&"metres_per_repeat", metres)
	sm.set_shader_parameter(&"detail", detail)
	sm.set_shader_parameter(&"recolor", recolor)
	return sm


## The alphabet-block atlas: 4×4 cells, each a pastel square with a darker
## frame and a big letter (A to P) in a contrasting colour.
static var _letter_tex: ImageTexture
const GLYPHS := {
	"A": ["01110", "10001", "10001", "11111", "10001", "10001", "10001"],
	"B": ["11110", "10001", "10001", "11110", "10001", "10001", "11110"],
	"C": ["01111", "10000", "10000", "10000", "10000", "10000", "01111"],
	"D": ["11110", "10001", "10001", "10001", "10001", "10001", "11110"],
	"E": ["11111", "10000", "10000", "11110", "10000", "10000", "11111"],
	"F": ["11111", "10000", "10000", "11110", "10000", "10000", "10000"],
	"G": ["01111", "10000", "10000", "10011", "10001", "10001", "01111"],
	"H": ["10001", "10001", "10001", "11111", "10001", "10001", "10001"],
	"I": ["11111", "00100", "00100", "00100", "00100", "00100", "11111"],
	"J": ["00111", "00010", "00010", "00010", "00010", "10010", "01100"],
	"K": ["10001", "10010", "10100", "11000", "10100", "10010", "10001"],
	"L": ["10000", "10000", "10000", "10000", "10000", "10000", "11111"],
	"M": ["10001", "11011", "10101", "10101", "10001", "10001", "10001"],
	"N": ["10001", "11001", "10101", "10011", "10001", "10001", "10001"],
	"O": ["01110", "10001", "10001", "10001", "10001", "10001", "01110"],
	"P": ["11110", "10001", "10001", "11110", "10000", "10000", "10000"],
}


static func _letters() -> ImageTexture:
	if _letter_tex:
		return _letter_tex
	var cell := 128
	var img := Image.create_empty(cell * 4, cell * 4, false, Image.FORMAT_RGB8)
	var backs := [Color(1.0, 0.62, 0.62), Color(0.62, 0.8, 1.0), Color(1.0, 0.9, 0.5), Color(0.66, 0.92, 0.62),
		Color(0.85, 0.7, 1.0), Color(1.0, 0.75, 0.5), Color(0.6, 0.92, 0.9), Color(1.0, 0.7, 0.85)]
	var inks := [Color(0.75, 0.1, 0.12), Color(0.12, 0.3, 0.75), Color(0.85, 0.4, 0.05), Color(0.1, 0.5, 0.15),
		Color(0.45, 0.15, 0.7), Color(0.8, 0.25, 0.05), Color(0.05, 0.45, 0.5), Color(0.7, 0.1, 0.4)]
	var letters := "ABCDEFGHIJKLMNOP"
	for i in 16:
		var ox := (i % 4) * cell
		var oy := (i / 4) * cell
		var back: Color = backs[i % 8]
		img.fill_rect(Rect2i(ox, oy, cell, cell), back.darkened(0.25))
		img.fill_rect(Rect2i(ox + 10, oy + 10, cell - 20, cell - 20), back)
		var g: Array = GLYPHS[letters[i]]
		var px := 13
		var lx := ox + (cell - 5 * px) / 2
		var ly := oy + (cell - 7 * px) / 2
		for row in 7:
			for col in 5:
				if String(g[row])[col] == "1":
					img.fill_rect(Rect2i(lx + col * px, ly + row * px, px, px), inks[(i + 3) % 8])
	img.generate_mipmaps()
	_letter_tex = ImageTexture.create_from_image(img)
	return _letter_tex


## Kid's-room wallpaper: soft stripes with little stars and dots.
static func _wallpaper() -> ImageTexture:
	var n := 256
	var img := Image.create_empty(n, n, false, Image.FORMAT_RGB8)
	img.fill(Color(0.98, 0.93, 0.82))
	for x in range(0, n, 64):
		img.fill_rect(Rect2i(x, 0, 30, n), Color(0.86, 0.93, 0.98))
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for i in 18:
		var cx := rng.randi_range(8, n - 8)
		var cy := rng.randi_range(8, n - 8)
		var col: Color = [Color(1.0, 0.85, 0.35), Color(1.0, 0.6, 0.65), Color(0.6, 0.8, 1.0)][i % 3]
		img.fill_rect(Rect2i(cx - 1, cy - 6, 3, 13), col)
		img.fill_rect(Rect2i(cx - 6, cy - 1, 13, 3), col)
		img.fill_rect(Rect2i(cx - 3, cy - 3, 7, 7), col)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## Sunflower-seed stripes: dark shell with cream streaks running lengthwise.
static func _stripes() -> ImageTexture:
	var img := Image.create_empty(64, 8, true, Image.FORMAT_RGB8)
	for x in 64:
		var on := fmod(float(x), 16.0) < 5.0 or fmod(float(x) + 8.0, 16.0) < 2.5
		for y in 8:
			img.set_pixel(x, y, Color(0.92, 0.9, 0.82) if on else Color(0.13, 0.12, 0.12))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)
