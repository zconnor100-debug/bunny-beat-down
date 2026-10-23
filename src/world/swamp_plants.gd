class_name SwampPlants
extends RefCounted
## Procedural swamp plants, built once and batched by Scatter like grass:
## REED clumps (tall blades and cattails, critter-high: good cover in the
## shallows) and LILY PADS (flat, notched, some with a flower) floating on the
## swamp water. Both are original geometry with vertex colours.

const REED_HEIGHT := 4.2
const LILY_RADIUS := 1.3

static var _reed: ArrayMesh
static var _lily: Array[ArrayMesh] = []


## A scatter entry (as in assets/env/manifest.json) for a batched plant.
static func entry(kind: String) -> Dictionary:
	match kind:
		"reed":
			return {"id": "swamp_reed", "category": "reed", "height_m": REED_HEIGHT, "footprint_radius_m": 1.3,
				"scale_range": [0.75, 1.25], "_mesh": reed_mesh()}
		_:
			return {"id": "lily_pad_%s" % kind, "category": "lily", "height_m": 0.1, "footprint_radius_m": LILY_RADIUS,
				"scale_range": [0.6, 1.3], "_mesh": lily_mesh(kind == "flower")}


static func reed_mesh() -> ArrayMesh:
	if _reed:
		return _reed
	var rng := RandomNumberGenerator.new()
	rng.seed = 4471
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# blades: tapered, curving ribbons leaning out from the clump's centre
	for i in 11:
		var a := rng.randf() * TAU
		var base := Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.0, 0.6)
		var h := REED_HEIGHT * rng.randf_range(0.55, 1.0)
		var lean := Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.2, 0.9)
		var face := Vector3(-sin(a + 0.7), 0, cos(a + 0.7))
		_blade(st, base, h, lean, face, 0.16, Color(0.24, 0.42, 0.14), Color(0.62, 0.66, 0.3))
	# cattails: a stalk with a brown velvet head
	for i in 4:
		var a := rng.randf() * TAU
		var base := Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.1, 0.5)
		var h := REED_HEIGHT * rng.randf_range(0.8, 1.1)
		var top := base + Vector3(cos(a), 0, sin(a)) * 0.25 + Vector3.UP * h
		_tube(st, base, top, 0.04, Color(0.3, 0.42, 0.16))
		_tube(st, top - Vector3.UP * 0.9, top - Vector3.UP * 0.2, 0.15, Color(0.36, 0.22, 0.12))
	st.generate_normals()
	_reed = st.commit()
	_reed.surface_set_material(0, _plant_material())
	return _reed


static func lily_mesh(flower: bool) -> ArrayMesh:
	var idx := 1 if flower else 0
	if _lily.size() > idx and _lily[idx]:
		return _lily[idx]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# a flat disc with a notch cut to the centre
	var seg := 18
	var notch := 0.45
	var centre := Vector3(0, 0.03, 0)
	for i in seg:
		var a0 := notch + (TAU - notch) * i / seg
		var a1 := notch + (TAU - notch) * (i + 1) / seg
		var p0 := Vector3(cos(a0), 0.0, sin(a0)) * LILY_RADIUS
		var p1 := Vector3(cos(a1), 0.0, sin(a1)) * LILY_RADIUS
		for v in [[centre, Color(0.32, 0.5, 0.18)], [p1, Color(0.22, 0.4, 0.14)], [p0, Color(0.22, 0.4, 0.14)]]:
			st.set_color(v[1])
			st.set_normal(Vector3.UP)
			st.add_vertex(v[0])
	if flower:
		# a pink water-lily: two rings of pointed petals around a yellow middle
		for ring in 2:
			var n := 7
			for i in n:
				var a := TAU * (i + ring * 0.5) / n
				var dir := Vector3(cos(a), 0, sin(a))
				var side := Vector3(-dir.z, 0, dir.x)
				var r0 := 0.12
				var r1 := 0.55 - ring * 0.15
				var lift := 0.18 + ring * 0.12
				var base := Vector3(0, 0.08, 0)
				var tip := base + dir * r1 + Vector3.UP * lift
				var col := Color(1.0, 0.72, 0.85) if ring == 0 else Color(1.0, 0.86, 0.92)
				for v in [base + side * r0 * 0.5, tip, base - side * r0 * 0.5, base + dir * r1 * 0.5 + side * r0 + Vector3.UP * lift * 0.4,
						tip, base + side * r0 * 0.5, base - side * r0 * 0.5, tip, base + dir * r1 * 0.5 - side * r0 + Vector3.UP * lift * 0.4]:
					st.set_color(col)
					st.set_normal(Vector3.UP)
					st.add_vertex(v)
		_tube(st, Vector3(0, 0.05, 0), Vector3(0, 0.25, 0), 0.1, Color(1.0, 0.85, 0.2))
	var mesh := st.commit()
	mesh.surface_set_material(0, _plant_material())
	while _lily.size() <= idx:
		_lily.append(null)
	_lily[idx] = mesh
	return mesh


static func _blade(st: SurfaceTool, base: Vector3, h: float, lean: Vector3, face: Vector3, w: float, c0: Color, c1: Color) -> void:
	var segs := 4
	var pts := []
	for i in segs + 1:
		var t := float(i) / segs
		var p := base + Vector3.UP * h * t + lean * t * t
		var half := w * (1.0 - t * 0.92)
		pts.append([p - face * half, p + face * half, c0.lerp(c1, t)])
	for i in segs:
		var a: Array = pts[i]
		var b: Array = pts[i + 1]
		for v in [[a[0], a[2]], [b[0], b[2]], [a[1], a[2]], [a[1], a[2]], [b[0], b[2]], [b[1], b[2]]]:
			st.set_color(v[1])
			st.add_vertex(v[0])


static func _tube(st: SurfaceTool, a: Vector3, b: Vector3, r: float, col: Color) -> void:
	var dir := (b - a).normalized()
	var side := dir.cross(Vector3.RIGHT if absf(dir.x) < 0.9 else Vector3.FORWARD).normalized()
	var up := side.cross(dir)
	var seg := 6
	for i in seg:
		var a0 := TAU * i / seg
		var a1 := TAU * (i + 1) / seg
		var n0 := side * cos(a0) + up * sin(a0)
		var n1 := side * cos(a1) + up * sin(a1)
		for v in [a + n0 * r, b + n0 * r, b + n1 * r, a + n0 * r, b + n1 * r, a + n1 * r]:
			st.set_color(col)
			st.add_vertex(v)


static func _plant_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED   # thin blades are seen from both sides
	m.roughness = 0.75
	return m
