class_name StarfallKernel
extends Node3D
## A piece of the Starfall Acorn (docs/LORE.md): the first the Warren has
## ever seen out of a giant (PatchOutro). An acorn, gold-green and glowing
## from inside, turning slowly in the air and bobbing, haloed, lighting what's
## under it, humming. `pulse` makes it flare (it's calling to the others).

const MODEL := "res://assets/env/acorn/acorn.glb"
const SIZE := 0.75             ## metres, along its length
const GLOW := Color(0.8, 1.0, 0.34)
const GOLD := Color(0.95, 0.78, 0.3)

## How much it glows (1: a Kernel; the whole Acorn, StarfallOutro, much less:
## it's huge).
var glow_k := 1.0:
	set(v):
		glow_k = v
		if _mat:
			_mat.emission_energy_multiplier = 2.2 * v
var _body: Node3D
var _mat: StandardMaterial3D
var _halo: Sprite3D
var _light: OmniLight3D
var _hum: AudioStreamPlayer3D
var _t := 0.0
var _flare := 0.0


func _init() -> void:
	name = "StarfallKernel"


func _ready() -> void:
	_body = Node3D.new()
	add_child(_body)
	var acorn := ModelUtil.instantiate(MODEL)
	if acorn:
		var box := ModelUtil.aabb_of(acorn)
		var k := SIZE / maxf(box.size.x, 0.001)
		acorn.scale = Vector3.ONE * k
		acorn.position = -box.get_center() * k
		var hold := Node3D.new()
		hold.rotation.z = PI * 0.5   # (the model lies along x: stood on its point, cap up)
		hold.add_child(acorn)
		_body.add_child(hold)
		_mat = StandardMaterial3D.new()
		_mat.albedo_color = GOLD
		_mat.metallic = 0.6
		_mat.roughness = 0.3
		_mat.emission_enabled = true
		_mat.emission = GLOW
		_mat.emission_energy_multiplier = 2.2 * glow_k
		_mat.rim_enabled = true
		_mat.rim = 0.6
		for mi in ModelUtil.find_all(acorn, "MeshInstance3D"):
			(mi as MeshInstance3D).material_override = _mat
			(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	else:
		var mi := MeshInstance3D.new()
		var s := SphereMesh.new()
		s.radius = SIZE * 0.35
		s.height = SIZE
		mi.mesh = s
		_body.add_child(mi)
	_halo = Sprite3D.new()
	_halo.texture = FXTextures.soft_blob()
	_halo.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_halo.modulate = Color(GLOW, 0.6)
	_halo.pixel_size = SIZE * 3.2 / maxf(_halo.texture.get_width(), 1.0)
	_halo.shaded = false
	_halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_halo)
	_light = OmniLight3D.new()
	_light.light_color = GLOW
	_light.omni_range = 7.0
	_light.shadow_enabled = false
	add_child(_light)
	_hum = Audio.make_loop(&"kernel_hum", self) as AudioStreamPlayer3D
	if _hum:
		_hum.unit_size = 6.0
		_hum.max_distance = 80.0
		_hum.play()
	_process(0.0)


func _process(delta: float) -> void:
	_t += delta
	_flare = maxf(0.0, _flare - delta * 0.7)
	_body.rotation.y += delta * 0.9
	_body.position.y = sin(_t * 1.7) * 0.08
	var glow := 0.85 + 0.15 * sin(_t * 4.3) + _flare
	_light.light_energy = 2.4 * glow * glow_k
	_halo.modulate = Color(_halo.modulate, clampf(0.45 * glow * glow_k, 0.0, 1.0))   # (its colour kept: gold-green, or gold)
	_halo.scale = Vector3.ONE * (1.0 + _flare * 0.8)
	if _hum:
		_hum.pitch_scale = 1.0 + _flare * 0.08


## Gold all through, not gold-green (the whole Acorn, back together: StarfallOutro).
func gild() -> void:
	if _mat:
		_mat.emission = Color(1.0, 0.8, 0.38)
	_halo.modulate = Color(1.0, 0.85, 0.45, _halo.modulate.a)
	_light.light_color = Color(1.0, 0.85, 0.5)


## It flares, and hums louder for a moment.
func pulse(k := 1.0) -> void:
	_flare = maxf(_flare, k)
	FX.muzzle(global_position, Vector3.UP, true, Color(GLOW, 0.8))
