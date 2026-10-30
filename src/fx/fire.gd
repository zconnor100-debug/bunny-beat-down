class_name Fire
extends Node3D
## A fire on the ground (the Kernel Hunt's Act I burns the Carrot Patch):
## tongues of flame licking up all over a round patch `size` metres across,
## heaped higher in the middle (FXTextures.flame: yellow-white at the root,
## orange, red at the tips), a glow along the ground under them, dark smoke
## rolling up off them in billows (a taller, wider column the bigger the
## fire), embers drifting up on the heat, a flickering orange light and a
## crackle (fire_loop). `grow` brings it up from nothing; `die_down` puts it out.

const FLAME_HOT := Color(1.0, 0.92, 0.55)
const FLAME := Color(1.0, 0.5, 0.1)
const FLAME_TIP := Color(0.78, 0.14, 0.03)
const SMOKE := Color(0.16, 0.14, 0.13)
const LIGHT := Color(1.0, 0.55, 0.22)

var size := 2.0
var strength := 1.0             ## 0 out .. 1 roaring (what grow and die_down tween)
var _flames: GPUParticles3D
var _core: GPUParticles3D
var _glow: GPUParticles3D
var _smoke: GPUParticles3D
var _embers: GPUParticles3D
var _light: OmniLight3D
var _sound: AudioStreamPlayer3D
var _t := 0.0


func _init(size_ := 2.0, lit := true) -> void:
	size = size_
	strength = 1.0 if lit else 0.0
	name = "Fire"


func _ready() -> void:
	var r := size * 0.5
	var k := clampf(size, 1.0, 20.0)
	var tall := 0.9 + size * 0.14   # (how tall a tongue of flame stands)
	# low, ragged flames all over it, and a taller blaze in the middle (a fire heaps up)
	_flames = _particles({"amount": int(clampf(22.0 * k, 20.0, 360.0)), "lifetime": 0.7, "radius": r, "speed": Vector2(0.8, 2.2) * sqrt(tall),
		"rise": 2.5, "scale": Vector2(0.5, 1.15), "quad": Vector2(0.55, 1.0) * tall * 0.85, "ramp": _flame_ramp(), "texture": FXTextures.flame(),
		"spin": 9.0, "shrink": true})
	add_child(_flames)
	_core = _particles({"amount": int(clampf(9.0 * k, 10.0, 150.0)), "lifetime": 0.95, "radius": r * 0.5, "speed": Vector2(1.6, 3.2) * sqrt(tall),
		"rise": 3.5, "scale": Vector2(0.7, 1.3), "quad": Vector2(0.6, 1.0) * tall * 1.35, "ramp": _flame_ramp(), "texture": FXTextures.flame(),
		"spin": 7.0, "shrink": true})
	add_child(_core)
	_glow = _particles({"amount": int(clampf(5.0 * k, 6.0, 90.0)), "lifetime": 0.5, "radius": r * 0.85, "speed": Vector2(0.2, 0.6),
		"rise": 0.5, "scale": Vector2(0.7, 1.3), "quad": Vector2.ONE * tall * 0.9, "ramp": _glow_ramp(), "texture": FXTextures.soft_blob(),
		"spin": 180.0, "additive": true})
	add_child(_glow)
	var puff := 1.2 + size * 0.32
	_smoke = _particles({"amount": int(clampf(9.0 * k, 12.0, 200.0)), "lifetime": 4.5 + size * 0.35, "radius": r * 0.7,
		"speed": Vector2(1.8, 3.2) * sqrt(tall), "rise": 1.0, "scale": Vector2(0.8, 1.3), "quad": Vector2.ONE * puff,
		"ramp": _smoke_ramp(), "texture": FXTextures.smoke_puff(), "spin": 180.0, "grow": true, "turbulence": 0.5, "drag": 0.12})
	_smoke.position.y = tall * 0.8
	add_child(_smoke)
	_embers = _particles({"amount": int(clampf(10.0 * k, 10.0, 160.0)), "lifetime": 2.0, "radius": r * 0.8, "speed": Vector2(1.5, 3.5) * sqrt(tall),
		"rise": 1.2, "scale": Vector2(0.6, 1.2), "quad": Vector2.ONE * 0.09, "ramp": _ember_ramp(), "texture": FXTextures.soft_blob(),
		"spin": 0.0, "additive": true, "turbulence": 1.6})
	add_child(_embers)
	_light = OmniLight3D.new()
	_light.light_color = LIGHT
	_light.omni_range = 4.0 + size * 2.4
	_light.omni_attenuation = 1.3
	_light.shadow_enabled = false
	_light.position.y = tall * 0.6 + 0.4
	add_child(_light)
	_sound = Audio.make_loop(&"fire_loop", self) as AudioStreamPlayer3D
	if _sound:
		_sound.unit_size = 4.0 + size
		_sound.max_distance = 60.0 + size * 10.0
		_sound.position.y = 0.5
		_sound.play()
	_apply()


func _process(delta: float) -> void:
	_t += delta
	_apply()


## Light it, from nothing up to roaring over `seconds`.
func grow(seconds := 1.5) -> void:
	strength = 0.0
	_apply()
	create_tween().tween_property(self, "strength", 1.0, seconds).set_ease(Tween.EASE_OUT)


## Burn down to embers and smoke over `seconds`, then go.
func die_down(seconds := 4.0) -> void:
	var tw := create_tween()
	tw.tween_property(self, "strength", 0.0, seconds)
	tw.tween_interval(_smoke.lifetime if _smoke else 4.5)   # (the last smoke clears)
	tw.tween_callback(queue_free)


func _apply() -> void:
	var on := strength > 0.02
	for p: GPUParticles3D in [_flames, _core, _glow, _embers]:
		if p:
			p.emitting = on
			p.amount_ratio = clampf(strength, 0.05, 1.0)
	if _smoke:
		_smoke.emitting = strength > 0.0
		_smoke.amount_ratio = clampf(0.3 + strength * 0.7, 0.05, 1.0)
	if _light:
		# a flicker: two wobbles out of step, and a quicker one
		var f := 0.82 + 0.12 * sin(_t * 13.0) * sin(_t * 7.3 + 1.7) + 0.06 * sin(_t * 23.0)
		_light.light_energy = (1.8 + size * 0.5) * f * strength
		_light.visible = on
	if _sound:
		_sound.volume_db = linear_to_db(maxf(strength, 0.001)) - 2.0


## A layer of the fire. cfg: amount, lifetime, radius (of the round patch it
## comes up from: evenly all over it), speed (up), rise (how hard the heat
## pulls it up), quad (each particle's size, metres) and scale (a spread on
## it), ramp, texture, spin (degrees it may lean or turn), shrink (narrows as
## it goes: a flame) or grow (spreads: smoke), additive, turbulence, drag
## (how fast it slows).
func _particles(cfg: Dictionary) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = maxi(4, int(cfg.amount))
	p.lifetime = cfg.lifetime
	p.randomness = 0.4
	p.local_coords = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var speed: Vector2 = cfg.speed
	var reach := maxf(size * 1.5, 4.0)
	var up := float(cfg.lifetime) * speed.y * 1.6 + float(cfg.quad.y) * float(cfg.scale.y) * 2.0
	p.visibility_aabb = AABB(Vector3(-reach - up * 0.3, -1.0, -reach - up * 0.3), Vector3((reach + up * 0.3) * 2.0, up + 2.0, (reach + up * 0.3) * 2.0))
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINTS
	m.emission_point_texture = _disc_points(maxf(float(cfg.radius), 0.05))
	m.emission_point_count = DISC_POINTS
	m.direction = Vector3.UP
	m.spread = 10.0
	m.initial_velocity_min = speed.x
	m.initial_velocity_max = speed.y
	m.gravity = Vector3(0, float(cfg.rise), 0)   # (hot air: up)
	var drag: float = cfg.get("drag", 0.5)
	m.damping_min = drag * 0.6
	m.damping_max = drag * 1.6
	var sc: Vector2 = cfg.scale
	m.scale_min = sc.x
	m.scale_max = sc.y
	var spin: float = cfg.get("spin", 0.0)
	m.angle_min = -spin
	m.angle_max = spin
	if spin > 30.0:
		m.angular_velocity_min = -25.0
		m.angular_velocity_max = 25.0
	m.color_ramp = cfg.ramp
	var curve := Curve.new()
	if cfg.get("shrink", false):
		curve.add_point(Vector2(0.0, 0.55))
		curve.add_point(Vector2(0.25, 1.0))
		curve.add_point(Vector2(1.0, 0.3))   # (a tongue of flame narrows as it licks up)
	elif cfg.get("grow", false):
		curve.add_point(Vector2(0.0, 0.35))
		curve.add_point(Vector2(1.0, 1.0))   # (smoke spreads as it climbs)
	else:
		curve.add_point(Vector2(0.0, 1.0))
		curve.add_point(Vector2(1.0, 0.6))
	var ct := CurveTexture.new()
	ct.curve = curve
	m.scale_curve = ct
	if cfg.has("turbulence"):
		m.turbulence_enabled = true
		m.turbulence_noise_strength = cfg.turbulence
		m.turbulence_noise_scale = 3.0
		m.turbulence_influence_min = 0.02   # (a waver, not a brake: smoke still climbs)
		m.turbulence_influence_max = 0.07
	p.process_material = m
	var mat := StandardMaterial3D.new()
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = cfg.texture
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if cfg.get("additive", false):
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.proximity_fade_enabled = true
	mat.proximity_fade_distance = 0.5
	mat.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA   # (standing in it, it doesn't fill the screen)
	mat.distance_fade_min_distance = 0.6
	mat.distance_fade_max_distance = 3.5
	var q := QuadMesh.new()
	q.size = cfg.quad
	q.center_offset = Vector3(0, float(cfg.quad.y) * 0.35, 0) if cfg.get("shrink", false) else Vector3.ZERO   # (a flame stands on its root)
	q.material = mat
	p.draw_pass_1 = q
	return p


const DISC_POINTS := 256
static var _discs := {}


## DISC_POINTS points spread evenly over a disc `radius` across (on the
## ground), as an emission texture.
static func _disc_points(radius: float) -> ImageTexture:
	var key := snappedf(radius, 0.01)
	if _discs.has(key):
		return _discs[key]
	var img := Image.create_empty(DISC_POINTS, 1, false, Image.FORMAT_RGBF)
	var golden := PI * (3.0 - sqrt(5.0))   # (a sunflower spiral: even, with no rings or clumps)
	for i in DISC_POINTS:
		var rr := radius * sqrt((i + 0.5) / DISC_POINTS)
		var a := i * golden
		img.set_pixel(i, 0, Color(cos(a) * rr, 0.0, sin(a) * rr))
	var tex := ImageTexture.create_from_image(img)
	_discs[key] = tex
	return tex


static func _ramp(points: Array, hdr := false) -> GradientTexture1D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array(points.map(func(pt): return pt[0]))
	g.colors = PackedColorArray(points.map(func(pt): return pt[1]))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	gt.use_hdr = hdr
	return gt


static func _flame_ramp() -> GradientTexture1D:
	return _ramp([[0.0, Color(FLAME_HOT * 1.3, 0.0)], [0.06, Color(FLAME_HOT * 1.3, 0.9)], [0.22, Color(FLAME * 1.35, 0.92)],
		[0.6, Color(FLAME_TIP * 1.15, 0.78)], [1.0, Color(FLAME_TIP * 0.6, 0.0)]], true)


static func _glow_ramp() -> GradientTexture1D:
	return _ramp([[0.0, Color(1.0, 0.7, 0.3, 0.0)], [0.25, Color(1.0, 0.6, 0.2, 0.3)], [1.0, Color(1.0, 0.4, 0.1, 0.0)]], true)


static func _smoke_ramp() -> GradientTexture1D:
	return _ramp([[0.0, Color(SMOKE, 0.0)], [0.1, Color(SMOKE, 0.82)], [0.55, Color(SMOKE.lightened(0.12), 0.6)],
		[1.0, Color(SMOKE.lightened(0.3), 0.0)]])


static func _ember_ramp() -> GradientTexture1D:
	return _ramp([[0.0, Color(2.2, 1.6, 0.6, 1.0)], [0.5, Color(2.0, 0.8, 0.15, 0.9)], [1.0, Color(1.0, 0.2, 0.02, 0.0)]], true)
