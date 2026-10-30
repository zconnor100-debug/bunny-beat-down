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

var _body: Node3D
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
		var mat := StandardMaterial3D.new()
		mat.albedo_color = GOLD
		mat.metallic = 0.6
		mat.roughness = 0.3
		mat.emission_enabled = true
		mat.emission = GLOW
		mat.emission_energy_multiplier = 2.2
		mat.rim_enabled = true
		mat.rim = 0.6
		for mi in ModelUtil.find_all(acorn, "MeshInstance3D"):
			(mi as MeshInstance3D).material_override = mat
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
	_light.light_energy = 2.4 * glow
	_halo.modulate = Color(GLOW, clampf(0.45 * glow, 0.0, 1.0))
	_halo.scale = Vector3.ONE * (1.0 + _flare * 0.8)
	if _hum:
		_hum.pitch_scale = 1.0 + _flare * 0.08


## It flares, and hums louder for a moment.
func pulse(k := 1.0) -> void:
	_flare = maxf(_flare, k)
	FX.muzzle(global_position, Vector3.UP, true, Color(GLOW, 0.8))
