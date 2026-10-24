class_name NearSnow
extends GPUParticles3D
## Light snow round the camera that only falls in one round patch of the map
## (the Hamster Cage's winter corner, by the open fridge). The emitter follows
## the camera but keeps its box inside the patch, so no flake starts outside
## it, and it thins out as the camera leaves (a wider, sparser snowfall
## covers the patch from afar: see CageRoom).

const BOX := 60.0      ## half the width of the box the flakes start in
const ABOVE := 45.0    ## how far over the camera they start

var centre := Vector2.ZERO
var radius := 300.0
var ground := 0.0


static func make(centre_: Vector2, radius_: float, ground_: float, drift: Vector3) -> NearSnow:
	var s := NearSnow.new()
	s.name = "NearSnow"
	s.centre = centre_
	s.radius = radius_
	s.ground = ground_
	s.amount = 4000
	s.lifetime = 14.0
	s.preprocess = 14.0
	s.visibility_aabb = AABB(Vector3(-BOX - 60.0, -160.0, -BOX - 60.0), Vector3(BOX * 2.0 + 120.0, 175.0, BOX * 2.0 + 120.0))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(BOX, 6.0, BOX)
	pm.direction = (drift + Vector3.DOWN * 5.0).normalized()
	pm.spread = 14.0
	pm.initial_velocity_min = 4.5
	pm.initial_velocity_max = 7.0
	pm.gravity = Vector3(0, -0.3, 0)
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 1.2
	pm.turbulence_noise_scale = 5.0
	pm.scale_min = 0.6
	pm.scale_max = 1.4
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0))
	fade.set_color(1, Color(1, 1, 1, 0))
	fade.add_point(0.08, Color(1, 1, 1, 1))
	fade.add_point(0.9, Color(1, 1, 1, 1))
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	pm.color_ramp = ramp
	s.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.8, 0.8)
	var m := StandardMaterial3D.new()
	m.albedo_texture = FXTextures.soft_blob()
	m.albedo_color = Color(1, 1, 1, 0.95)
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	quad.material = m
	s.draw_pass_1 = quad
	s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return s


func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var c := cam.global_position
	var off := Vector2(c.x, c.z) - centre
	# the box (corners and all) stays inside the patch
	var at := centre + off.limit_length(maxf(radius - BOX * 1.42, 0.0))
	global_position = Vector3(at.x, maxf(c.y, ground) + ABOVE, at.y)
	# full inside the patch, gone a little way out of it (or high above it)
	amount_ratio = smoothstep(radius + 220.0, radius, off.length()) * smoothstep(ground + 300.0, ground + 160.0, c.y)
