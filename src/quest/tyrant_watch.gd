class_name TyrantWatch
extends Node3D
## Two red eyes peering over the top of the bookshelf, high over the toy room,
## and the red light they sweep across the floor (the Kernel Hunt's Act II,
## ClockworkMission): the Tin Tyrant, watching his Decree being kept, all the
## time you're down there. The light is a pool of red on the floor (a Decal,
## glowing) under a faint beam from the eyes, and a SpotLight3D that tints
## what it passes. `glare` and they snap to a spot and flare (he's seen what
## you did; on the HUD while they do), and `leave`: they go out (he's jumped).

const RED := Color(1.0, 0.1, 0.04)
const SWEEP := 0.22            ## how fast the light sweeps (radians a second)
const POOL := 34.0             ## metres across, the pool of light on the floor

var centre := Vector3.ZERO     ## what the sweep goes back and forth across (the room's middle)
var _eyes: Array[MeshInstance3D] = []
var _eye_mat: StandardMaterial3D
var _spot: SpotLight3D
var _pool: Decal
var _beam: MeshInstance3D
var _beam_mat: StandardMaterial3D
var _at := Vector3.INF         # where the light is on the floor now
var _t := 0.0
var _glare_at := Vector3.INF
var _flare := 0.0
var _gone := false


func _init() -> void:
	name = "TyrantWatch"


func _ready() -> void:
	_eye_mat = StandardMaterial3D.new()
	_eye_mat.albedo_color = RED
	_eye_mat.emission_enabled = true
	_eye_mat.emission = RED
	_eye_mat.emission_energy_multiplier = 5.0
	_eye_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for xs in [-1.0, 1.0]:
		var e := MeshInstance3D.new()
		var s := SphereMesh.new()
		s.radius = 3.6
		s.height = 5.0
		e.mesh = s
		e.material_override = _eye_mat
		e.position = Vector3(xs * 8.0, 0, 0)
		e.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(e)
		_eyes.append(e)
		var halo := Sprite3D.new()
		halo.texture = FXTextures.soft_blob()
		halo.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		halo.modulate = Color(RED, 0.75)
		halo.pixel_size = 44.0 / maxf(halo.texture.get_width(), 1.0)   # (seen from the floor, 340 m down)
		halo.shaded = false
		halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		e.add_child(halo)
	_spot = SpotLight3D.new()
	_spot.light_color = RED
	_spot.light_energy = 40.0
	_spot.spot_range = 900.0
	_spot.spot_angle = 4.0
	_spot.spot_attenuation = 0.2
	_spot.shadow_enabled = false
	add_child(_spot)
	_pool = BossFX._decal(BossFX._texture("disc"), Vector3(POOL, 80.0, POOL), Color(1.0, 0.1, 0.05, 0.95))   # (round, soft-edged: as a boss's warnings)
	_pool.emission_energy = 4.0
	_pool.top_level = true
	add_child(_pool)
	_beam = MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.5      # (its top's on the floor: see _process)
	cone.bottom_radius = 0.04
	cone.height = 1.0
	cone.radial_segments = 16
	cone.rings = 1
	cone.cap_top = false
	cone.cap_bottom = false
	_beam.mesh = cone
	_beam_mat = StandardMaterial3D.new()
	_beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_beam_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_beam_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_beam_mat.no_depth_test = false
	var g := Gradient.new()   # (strongest at the eyes, gone before the floor)
	g.set_color(0, Color(RED, 0.0))
	g.add_point(0.55, Color(RED, 0.05))
	g.set_color(1, Color(RED, 0.22))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	_beam_mat.albedo_texture = gt
	_beam.material_override = _beam_mat
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beam.top_level = true
	add_child(_beam)


func _process(delta: float) -> void:
	_t += delta
	_flare = maxf(0.0, _flare - delta * 0.5)
	if _gone:
		return
	var want := _glare_at
	if want == Vector3.INF:
		# back and forth across the floor in a long slow figure of eight
		want = centre + Vector3(sin(_t * SWEEP) * 330.0, 0.0, sin(_t * SWEEP * 2.0) * 160.0 - 40.0)
	_at = want if _at == Vector3.INF else _at.lerp(want, clampf(delta * (5.0 if _glare_at != Vector3.INF else 1.2), 0.0, 1.0))
	var floor_y := ToyFloor.FLOOR
	if Island.current and Island.current.terrain:
		floor_y = Island.current.terrain.height_at(_at.x, _at.z)
	var on := Vector3(_at.x, floor_y, _at.z)
	_spot.global_basis = Basis.looking_at((on - _spot.global_position).normalized(), Vector3.UP)
	_pool.global_position = on
	var from := global_position + Vector3.DOWN * 0.5
	var d := on - from
	var y := d.normalized()
	var x := y.cross(Vector3.UP if absf(y.y) < 0.99 else Vector3.RIGHT).normalized()
	var w := POOL * 0.75
	_beam.global_transform = Transform3D(Basis(x * w, d, x.cross(y).normalized() * w), (from + on) * 0.5)
	var blink := 1.0 if fmod(_t, 5.3) > 0.18 else 0.1   # (now and then it blinks)
	var k := (1.0 + 2.5 * _flare) * blink
	_eye_mat.emission_energy_multiplier = 4.0 * k
	_spot.light_energy = 40.0 * k
	_pool.emission_energy = 4.0 * k
	_beam_mat.albedo_color = Color(1, 1, 1, clampf(0.8 * k, 0.0, 1.0))


## It's seen what you did: the light snaps to `at`, the eyes flare, and
## they're on your HUD (look up).
func glare(at: Vector3) -> void:
	_glare_at = at
	_flare = 1.0
	add_to_group(&"objectives")


## He's jumped: the eyes go out, and the light.
func leave() -> void:
	_gone = true
	if is_in_group(&"objectives"):
		remove_from_group(&"objectives")
	var tw := create_tween()
	tw.tween_property(_spot, "light_energy", 0.0, 0.25)
	tw.parallel().tween_property(_eye_mat, "emission_energy_multiplier", 0.0, 0.25)
	tw.parallel().tween_property(_pool, "modulate:a", 0.0, 0.25)
	tw.parallel().tween_property(_beam_mat, "albedo_color:a", 0.0, 0.25)
	tw.tween_callback(func(): visible = false)
