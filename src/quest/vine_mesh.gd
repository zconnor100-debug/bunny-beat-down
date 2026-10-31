class_name VineMesh
extends RefCounted
## The Briar's vines, built (the Kernel Hunt's Finale: BriarRoot, BriarHeart):
## a tube along a line of points, thick or thin as it goes (`tube`: UV.x runs
## in metres along it, for vine.gdshader's pulses of light), and thorns all
## along it pointing out (`thorns`, for a MultiMesh), in the Briar's colours.

const SHADER := preload("res://src/quest/vine.gdshader")
const THORN := Color(0.27, 0.17, 0.23)


## A tube through `points`, `radii[i]` thick at each, `sides` round.
static func tube(points: PackedVector3Array, radii: PackedFloat32Array, sides := 9) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := points.size()
	if n < 2:
		return ArrayMesh.new()
	var along := 0.0
	var side := Vector3.ZERO
	for i in n:
		var fwd := (points[mini(i + 1, n - 1)] - points[maxi(i - 1, 0)]).normalized()
		if i > 0:
			along += points[i].distance_to(points[i - 1])
		# a frame carried along the tube (no twisting where it turns)
		if side == Vector3.ZERO or absf(side.dot(fwd)) > 0.98:
			side = fwd.cross(Vector3.UP if absf(fwd.y) < 0.95 else Vector3.RIGHT).normalized()
		side = (side - fwd * side.dot(fwd)).normalized()
		var up := fwd.cross(side).normalized()
		for k in sides + 1:
			var a := TAU * k / sides
			var out := side * cos(a) + up * sin(a)
			st.set_normal(out)
			st.set_uv(Vector2(along, float(k) / sides))
			st.add_vertex(points[i] + out * radii[i])
	for i in n - 1:
		for k in sides:
			var a := i * (sides + 1) + k
			var b := a + sides + 1
			st.add_index(a)
			st.add_index(b)
			st.add_index(a + 1)
			st.add_index(a + 1)
			st.add_index(b)
			st.add_index(b + 1)
	# (capped at the ends: a little cone to a point)
	for end: int in [0, n - 1]:
		var fwd := (points[mini(end + 1, n - 1)] - points[maxi(end - 1, 0)]).normalized() * (-1.0 if end == 0 else 1.0)
		var tip := points[end] + fwd * radii[end] * 1.6
		var tip_i := n * (sides + 1) + (0 if end == 0 else 1)
		st.set_normal(fwd)
		st.set_uv(Vector2(0.0 if end == 0 else along, 0.5))
		st.add_vertex(tip)
		for k in sides:
			var a := end * (sides + 1) + k
			if end == 0:
				st.add_index(tip_i)
				st.add_index(a)
				st.add_index(a + 1)
			else:
				st.add_index(a)
				st.add_index(tip_i)
				st.add_index(a + 1)
	return st.commit()


## Thorns along the tube, every `every` metres, `per` round it, pointing out
## (and a little along it), as transforms for a thorn mesh standing on +Y.
static func thorns(points: PackedVector3Array, radii: PackedFloat32Array, rng: RandomNumberGenerator, every := 1.5, per := 2,
		size := 1.0) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	var n := points.size()
	var next := rng.randf() * every
	var walked := 0.0
	for i in range(1, n):
		var seg := points[i] - points[i - 1]
		var l := seg.length()
		if l < 1e-4:
			continue
		var fwd := seg / l
		var side := fwd.cross(Vector3.UP if absf(fwd.y) < 0.95 else Vector3.RIGHT).normalized()
		var up := fwd.cross(side)
		while next <= walked + l:
			var u := (next - walked) / l
			var at := points[i - 1].lerp(points[i], u)
			var r := lerpf(radii[i - 1], radii[i], u)
			for k in per:
				var a := rng.randf() * TAU
				var dir := side * cos(a) + up * sin(a)
				var point := (dir + fwd * rng.randf_range(0.1, 0.5)).normalized()
				var s := size * rng.randf_range(0.7, 1.25) * clampf(r / 0.8, 0.45, 1.6)
				var b := Basis(IKMath.from_to(Vector3.UP, point)).scaled(Vector3.ONE * s)
				out.append(Transform3D(b, at + dir * r * 0.85))
			next += every * rng.randf_range(0.7, 1.3)
		walked += l
	return out


## The thorns as one MultiMesh (a cone each, `length` long).
static func thorn_multimesh(xforms: Array[Transform3D], length := 0.9, mat: Material = null) -> MultiMeshInstance3D:
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = length * 0.22
	cone.height = length
	cone.radial_segments = 5
	cone.rings = 1
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = cone
	mm.instance_count = xforms.size()
	for i in xforms.size():
		# (the cone's middle is its origin: up by half, so it stands on the bark)
		var x := xforms[i]
		mm.set_instance_transform(i, Transform3D(x.basis, x.origin + x.basis.y * length * 0.5))
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = mat if mat else thorn_material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


static func bark_material(pulses := 1.0, steady := 0.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.set_shader_parameter(&"pulse_amount", pulses)
	m.set_shader_parameter(&"glow_base", steady)
	return m


static func thorn_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = THORN
	m.roughness = 0.6
	m.emission_enabled = true
	m.emission = Color(0.5, 0.2, 0.7)
	m.emission_energy_multiplier = 0.12
	return m


## A line of points from `a` to `b` that wanders side to side as it goes
## (`wander` metres, `bends` times), `step` metres apart.
static func wandering(a: Vector3, b: Vector3, rng: RandomNumberGenerator, step := 2.0, wander := 6.0, bends := 3.0) -> PackedVector3Array:
	var out := PackedVector3Array()
	var d := b - a
	var l := d.length()
	var n := maxi(2, ceili(l / step))
	var side := Vector3(d.z, 0.0, -d.x).normalized() if Vector2(d.x, d.z).length() > 0.01 else Vector3.RIGHT
	var ph := rng.randf() * TAU
	var ph2 := rng.randf() * TAU
	for i in n + 1:
		var u := float(i) / n
		var off := sin(u * bends * PI + ph) * wander + sin(u * bends * 2.3 * PI + ph2) * wander * 0.35
		out.append(a.lerp(b, u) + side * off * sin(u * PI))
	return out
