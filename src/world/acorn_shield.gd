class_name AcornShield
extends RefCounted
## The shield (armor) pickup: a big glossy orange acorn, as tall as a lucky
## clover (half a Bun), with a scaly cap and a stalk, lit from within so it
## glows orange the way clovers glow green. Original procedural geometry.

const HEIGHT := 1.25                  ## same as Pickup.CLOVER_HEIGHT
const GLOW := Color(1.0, 0.5, 0.08)
const NUT_COLOR := Color(0.96, 0.42, 0.05)
const CAP_COLOR := Color(0.34, 0.2, 0.09)
const SCALE_COLOR := Color(0.52, 0.34, 0.16)

static var _mesh: ArrayMesh


## A fresh acorn node (meshes are shared between all acorns).
static func make() -> Node3D:
	var mi := MeshInstance3D.new()
	mi.name = "AcornShield"
	mi.mesh = mesh()
	return mi


## Surface 0 is the nut (it gets the glow overlay), surface 1 the cap.
static func mesh() -> ArrayMesh:
	if _mesh:
		return _mesh
	_mesh = ArrayMesh.new()
	var nut := SurfaceTool.new()
	nut.begin(Mesh.PRIMITIVE_TRIANGLES)
	# the nut: rounded shoulders under the cap, tapering to a little point
	var h := HEIGHT
	var prof: Array[Vector2] = []    # (radius, y) from the tip up to the cap rim
	for i in 15:
		var t := float(i) / 14.0
		var r := 0.36 * h * pow(sin(t * PI * 0.62 + 0.05), 0.9) * (1.0 - 0.15 * t * t)
		prof.append(Vector2(r, lerpf(0.0, 0.74 * h, t)))
	prof[0] = Vector2(0.0, 0.0)
	prof.insert(1, Vector2(0.025 * h, 0.03 * h))   # the tip nub
	_lathe(nut, prof, 28, NUT_COLOR, NUT_COLOR.lightened(0.25))
	nut.generate_normals()
	nut.commit(_mesh)
	_mesh.surface_set_material(0, _nut_material())

	var cap := SurfaceTool.new()
	cap.begin(Mesh.PRIMITIVE_TRIANGLES)
	# the cap: a low dome a bit wider than the nut, a stalk, and rows of scales
	var dome: Array[Vector2] = []
	for i in 10:
		var a := float(i) / 9.0 * PI * 0.5
		dome.append(Vector2(0.4 * h * cos(a), 0.66 * h + 0.2 * h * sin(a)))
	_lathe(cap, dome, 28, CAP_COLOR, CAP_COLOR.darkened(0.2))
	_lathe(cap, [Vector2(0.0, 0.64 * h), Vector2(0.3 * h, 0.64 * h), Vector2(0.4 * h, 0.66 * h)] as Array[Vector2], 28, CAP_COLOR.darkened(0.3), CAP_COLOR.darkened(0.3))
	_lathe(cap, [Vector2(0.06 * h, 0.82 * h), Vector2(0.05 * h, 0.95 * h), Vector2(0.0, 0.96 * h)] as Array[Vector2], 10, CAP_COLOR.darkened(0.1), CAP_COLOR)
	for row in 5:
		var a := (0.08 + row * 0.18) * PI * 0.5
		var n := 26 - row * 4
		for k in n:
			var b := TAU * (k + 0.5 * (row % 2)) / n
			var out := Vector3(cos(b), 0.0, sin(b))
			var base := Vector3(out.x * 0.4 * h * cos(a), 0.66 * h + 0.2 * h * sin(a), out.z * 0.4 * h * cos(a))
			_scale(cap, base, out, a, 0.07 * h, SCALE_COLOR.lerp(CAP_COLOR, row * 0.15))
	cap.generate_normals()
	cap.commit(_mesh)
	_mesh.surface_set_material(1, _cap_material())
	return _mesh


## A surface of revolution through `prof` (radius, y); it faces the side to
## the right of the profile's direction in the (radius, y) plane.
static func _lathe(st: SurfaceTool, prof: Array[Vector2], seg: int, c0: Color, c1: Color) -> void:
	for i in prof.size() - 1:
		var p0 := prof[i]
		var p1 := prof[i + 1]
		var d := (p1 - p0).normalized()
		var n2 := Vector2(d.y, -d.x)
		var col0 := c0.lerp(c1, float(i) / (prof.size() - 1))
		var col1 := c0.lerp(c1, float(i + 1) / (prof.size() - 1))
		for k in seg:
			var a0 := TAU * k / seg
			var a1 := TAU * (k + 1) / seg
			var v00 := Vector3(cos(a0) * p0.x, p0.y, sin(a0) * p0.x)
			var v01 := Vector3(cos(a1) * p0.x, p0.y, sin(a1) * p0.x)
			var v10 := Vector3(cos(a0) * p1.x, p1.y, sin(a0) * p1.x)
			var v11 := Vector3(cos(a1) * p1.x, p1.y, sin(a1) * p1.x)
			var am := (a0 + a1) * 0.5
			var n := Vector3(cos(am) * n2.x, n2.y, sin(am) * n2.x)
			_tri(st, v00, v10, v11, n, col0, col1, col1)
			_tri(st, v00, v11, v01, n, col0, col1, col0)


## One pointed cap scale lying on the dome, tip pointing down and out.
static func _scale(st: SurfaceTool, base: Vector3, out: Vector3, a: float, size: float, col: Color) -> void:
	var down := (out * sin(a) - Vector3.UP * cos(a)).normalized()   # along the dome, toward the rim
	var side := out.cross(Vector3.UP).normalized()
	var lift := (out * cos(a) + Vector3.UP * sin(a)).normalized() * size * 0.25
	var tip := base + down * size * 1.3 + lift
	var l := base - side * size * 0.55 + lift * 0.4
	var r := base + side * size * 0.55 + lift * 0.4
	var top := base - down * size * 0.3
	var n := lift.normalized()
	_tri(st, l, top, r, n, col, col, col)
	_tri(st, l, r, tip, n, col, col, col)


## One triangle wound to face `n` (Godot's front faces are clockwise).
static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, n: Vector3, ca: Color, cb: Color, cc: Color) -> void:
	var pts := [[a, ca], [b, cb], [c, cc]] if (b - a).cross(c - a).dot(n) < 0.0 else [[a, ca], [c, cc], [b, cb]]
	for v in pts:
		st.set_color(v[1])
		st.add_vertex(v[0])


static func _nut_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = 0.28
	m.metallic_specular = 0.7
	m.emission_enabled = true
	m.emission = GLOW
	m.emission_energy_multiplier = 0.35
	m.rim_enabled = true
	m.rim = 0.4
	return m


static func _cap_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = 0.85
	m.cull_mode = BaseMaterial3D.CULL_DISABLED   # thin scales are seen from both sides
	return m
