class_name BossFX
## The bosses' effects (Boss): a red ring on the ground where a blow is about
## to land, filling up as it comes (and a strip for a charge), the shockwave
## and dust when it does, the Tin Tyrant's eye beams, Nibbles's foam. Like FX,
## nothing without an FX node in the tree (tests, menus).

const WARN := Color(1.0, 0.16, 0.06)
const DEPTH := 20.0      ## how far up and down a warning reaches (hills, but not the treetops)
const DUST := Color(0.62, 0.55, 0.44, 0.62)

static var _tex: Dictionary = {}


## A red ring on the ground at `pos`, `radius` across, filling in from the
## middle over `seconds` (when the blow lands), then gone. Projected on the
## ground and what's on it, never on critters or the boss.
static func warn_circle(pos: Vector3, radius: float, seconds: float, color := WARN) -> Node3D:
	if FX.instance == null:
		return null
	var root := Node3D.new()
	root.name = "BossWarning"
	FX.instance.add_child(root)
	root.global_position = pos
	var ring := _decal(_texture("ring"), Vector3(radius * 2.0, DEPTH, radius * 2.0), color)
	root.add_child(ring)
	var fill := _decal(_texture("disc"), Vector3(0.1, DEPTH, 0.1), Color(color, 0.75))
	root.add_child(fill)
	var tw := root.create_tween()
	tw.tween_property(fill, "size", Vector3(radius * 2.0, DEPTH, radius * 2.0), maxf(seconds, 0.05))
	tw.tween_property(ring, "modulate:a", 0.0, 0.3)
	tw.parallel().tween_property(fill, "modulate:a", 0.0, 0.3)
	tw.tween_callback(root.queue_free)
	return root


## A red strip from `from` to `to` (a charge's path), `width` across, for
## `seconds`; chevrons along it point the way.
static func warn_strip(from: Vector3, to: Vector3, width: float, seconds: float, color := WARN) -> Node3D:
	if FX.instance == null:
		return null
	var d := to - from
	d.y = 0.0
	if d.length() < 0.5:
		return null
	var root := Node3D.new()
	root.name = "BossWarning"
	FX.instance.add_child(root)
	root.global_position = (from + to) * 0.5
	root.global_basis = Basis(Vector3.UP, atan2(d.x, d.z))
	var strip := _decal(_texture("strip"), Vector3(width, DEPTH, d.length()), color)
	root.add_child(strip)
	var tw := root.create_tween()
	tw.tween_interval(maxf(seconds, 0.05))
	tw.tween_property(strip, "modulate:a", 0.0, 0.3)
	tw.tween_callback(root.queue_free)
	return root


## The blow lands: a ring of dust racing out to `radius`, and a cloud.
static func shockwave(pos: Vector3, radius: float, color := DUST) -> void:
	if FX.instance == null:
		return
	var mi := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.8
	tm.outer_radius = 1.0
	tm.rings = 48
	tm.ring_segments = 10
	mi.mesh = tm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(color, 0.7)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	FX.instance.add_child(mi)
	mi.global_position = pos + Vector3.UP * 0.8
	mi.scale = Vector3(radius * 0.08, 14.0, radius * 0.08)
	var tw := mi.create_tween()
	tw.tween_property(mi, "scale", Vector3(radius, 22.0, radius), 0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(mat, "albedo_color:a", 0.0, 0.6)
	tw.tween_callback(mi.queue_free)
	dust(pos, radius)


## A cloud of dust thrown up round `pos`.
static func dust(pos: Vector3, radius: float, color := DUST) -> void:
	FX.burst(pos + Vector3.UP * 0.5, Vector3.UP, {"amount": 60, "lifetime": 2.4, "speed": Vector2(radius * 0.35, radius * 0.9),
		"spread": 88.0, "gravity": -0.4, "size": clampf(radius * 0.22, 1.5, 6.0), "scale": Vector2(0.7, 1.8), "color": color,
		"fade": true, "damping": 2.6, "aabb": radius * 1.6 + 10.0})


## A column of dust going up from `pos` for `seconds`, tall enough to see
## from across the map over the trees (something huge stirring under Boulder
## Bluff: MissionOutro). Like a flare's smoke, slower and far bigger.
static func dust_column(pos: Vector3, seconds := 3.0) -> GPUParticles3D:
	if FX.instance == null:
		return null
	var p: GPUParticles3D = FX.instance._make_particles({"amount": 340, "lifetime": 7.0, "speed": Vector2(6.0, 15.0), "spread": 28.0,
		"gravity": -0.4, "size": 12.0, "scale": Vector2(0.7, 2.2), "color": Color(0.3, 0.26, 0.21, 0.92), "fade": true, "damping": 0.4}, false)
	p.one_shot = false
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-90, -90, -10), Vector3(180, 180, 200))   # (its local -Z is the world's up)
	p.rotation = Vector3(PI * 0.5, 0.0, 0.0)   # (its particles start off along -Z: turned to point up, fast)
	FX.instance.add_child(p)
	p.global_position = pos
	p.emitting = true
	var tw := p.create_tween()
	tw.tween_interval(seconds)
	tw.tween_callback(func(): p.emitting = false)
	tw.tween_interval(7.0)
	tw.tween_callback(p.queue_free)
	return p


## Chips of rock (or tin, or bedding) flying off where something smashed.
static func chips(pos: Vector3, size: float, color: Color) -> void:
	FX.burst(pos, Vector3.UP, {"amount": 28, "lifetime": 1.6, "speed": Vector2(4.0, 12.0) * size, "spread": 75.0,
		"gravity": 16.0, "size": 0.35 * size, "scale": Vector2(0.5, 1.4), "color": color, "fade": false, "shape": "chip",
		"aabb": 20.0 * size})


## Sparks (the Tin Tyrant, hit, or a beam scorching the floor).
static func sparks(pos: Vector3, dir: Vector3, k := 1.0) -> void:
	FX.burst(pos, dir, {"amount": int(14 * k), "lifetime": 0.45, "speed": Vector2(3.0, 9.0) * k, "spread": 55.0,
		"gravity": 12.0, "size": 0.12 * k, "scale": Vector2(0.5, 1.2), "color": Color(1.0, 0.75, 0.3), "fade": true,
		"additive": true, "aabb": 12.0 * k})


## A beam (the Tin Tyrant's eyes): put it between two points with set_beam.
static func beam(color := Color(1.0, 0.12, 0.06)) -> MeshInstance3D:
	if FX.instance == null:
		return null
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 1.0
	cm.bottom_radius = 1.0
	cm.height = 1.0
	cm.radial_segments = 10
	cm.rings = 1
	mi.mesh = cm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color(color, 0.9)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	FX.instance.add_child(mi)
	var core := MeshInstance3D.new()   # (white-hot down the middle)
	core.mesh = cm
	var cmat := mat.duplicate() as StandardMaterial3D
	cmat.albedo_color = Color(1.0, 0.9, 0.8, 0.95)
	core.material_override = cmat
	core.scale = Vector3(0.35, 1.0, 0.35)
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.add_child(core)
	return mi


static func set_beam(mi: MeshInstance3D, from: Vector3, to: Vector3, width: float) -> void:
	if mi == null or not is_instance_valid(mi):
		return
	var d := to - from
	var length := maxf(d.length(), 0.01)
	var y := d / length
	var x := y.cross(Vector3.UP if absf(y.y) < 0.99 else Vector3.RIGHT).normalized()
	var z := x.cross(y)
	mi.global_transform = Transform3D(Basis(x * width, y * length, z * width), (from + to) * 0.5)


## A puddle of rabid foam (Nibbles): a frothy patch that bubbles for
## `seconds`, then dries up.
static func foam(pos: Vector3, radius: float, seconds: float) -> Node3D:
	if FX.instance == null:
		return null
	var root := Node3D.new()
	root.name = "Foam"
	FX.instance.add_child(root)
	root.global_position = pos
	var d := _decal(_texture("foam"), Vector3(radius * 2.0, 20.0, radius * 2.0), Color(0.86, 0.95, 0.72, 0.95))
	d.rotation.y = randf() * TAU
	root.add_child(d)
	var bubbles: GPUParticles3D = FX.instance._make_particles({"amount": 30, "lifetime": 1.2, "speed": Vector2(0.3, 1.2),
		"spread": 25.0, "gravity": 0.5, "size": 0.9, "scale": Vector2(0.4, 1.3), "color": Color(0.9, 0.97, 0.8, 0.8),
		"fade": true, "aabb": radius + 4.0}, false)
	bubbles.one_shot = false
	bubbles.emitting = true
	var ring := ParticleProcessMaterial.new()
	ring.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	ring.emission_sphere_radius = radius * 0.8
	ring.direction = Vector3(0, 0, -1)
	ring.spread = 25.0
	ring.initial_velocity_min = 0.3
	ring.initial_velocity_max = 1.2
	ring.gravity = Vector3(0, -0.5, 0)
	ring.color = Color(0.9, 0.97, 0.8, 0.8)
	ring.scale_min = 0.4
	ring.scale_max = 1.3
	bubbles.process_material = ring
	bubbles.rotation.x = -PI * 0.5
	root.add_child(bubbles)
	var tw := root.create_tween()
	tw.tween_interval(maxf(seconds - 1.0, 0.1))
	tw.tween_callback(func(): bubbles.emitting = false)
	tw.tween_property(d, "modulate:a", 0.0, 1.0)
	tw.tween_callback(root.queue_free)
	return root


static func _decal(tex: Texture2D, size: Vector3, color: Color) -> Decal:
	var d := Decal.new()
	d.texture_albedo = tex
	d.texture_emission = tex
	d.emission_energy = 1.4
	d.size = size
	d.modulate = color
	d.cull_mask = 1   # (the world: not critters, not the boss)
	d.upper_fade = 0.15
	d.lower_fade = 0.15
	d.normal_fade = 0.55   # (the ground, not tree trunks and walls)
	return d


## The warnings' textures: "ring" (a bright rim over a faint fill), "disc"
## (soft-edged), "strip" (edged, with chevrons pointing up the texture: the
## strip's +Z) and "foam" (frothy blobs).
static func _texture(kind: String) -> Texture2D:
	if _tex.has(kind):
		return _tex[kind]
	var w := 64 if kind == "strip" else 256
	var h := 256
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var blobs := []
	if kind == "foam":
		for i in 70:
			var a := rng.randf() * TAU
			var r := sqrt(rng.randf()) * 0.85
			blobs.append([Vector2(cos(a), sin(a)) * r, rng.randf_range(0.05, 0.16)])
	for y in h:
		for x in w:
			var p := Vector2((x + 0.5) / w * 2.0 - 1.0, (y + 0.5) / h * 2.0 - 1.0)
			var a := 0.0
			match kind:
				"ring":
					var r := p.length()
					a = clampf((1.0 - r) * 40.0, 0.0, 1.0) * (1.0 if r > 0.9 else 0.2)
				"disc":
					a = clampf((1.0 - p.length()) * 6.0, 0.0, 1.0) * 0.55
				"strip":
					var edge := 1.0 if absf(p.x) > 0.82 else 0.22
					var chevron := fposmod(p.y * 3.0 + absf(p.x) * 0.9, 1.0)   # (Vs pointing to the far end)
					if chevron < 0.18 and absf(p.x) < 0.7:
						edge = 0.85
					a = edge * clampf((1.0 - absf(p.y)) * 30.0, 0.0, 1.0)
				"foam":
					for b in blobs:
						a = maxf(a, clampf((b[1] - p.distance_to(b[0])) * 30.0, 0.0, 1.0))
					a *= clampf((1.0 - p.length()) * 5.0, 0.0, 1.0)
			img.set_pixel(x, y, Color(a, a, a, a))   # (premultiplied: the emission, which ignores alpha, is dark where it's clear)
	img.generate_mipmaps()
	var t := ImageTexture.create_from_image(img)
	_tex[kind] = t
	return t
