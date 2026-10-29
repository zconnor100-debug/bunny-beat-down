class_name Flare
extends Grenade
## The flare that calls your arsenal in (Arsenal): picked from the call-in's
## menu and thrown like a carrot grenade (the same arc, the same bounce and
## roll), it lands burning red under a column of red smoke anyone can see, and
## WAIT seconds later your crate is sent down onto it (`lit`, from
## PlayerController: MatchManager.send_call_in). It burns on until BURN, then
## gutters out. It never goes off.

const WAIT := 1.5                 ## seconds burning on the ground before the crate is sent
const BURN := 14.0                ## seconds it burns, all told
const RED := Color(1.0, 0.16, 0.08)

var gun: StringName = &""         ## the gun the crate brings
var lit: Callable                 ## called with where it lies, WAIT seconds after it lands
var _burning := 0.0               # seconds lying burning
var _sent := false
var _glow: OmniLight3D
var _smoke: GPUParticles3D


## Throw one from `pos` at `vel` (m/s) for `gun`.
static func spawn_flare(parent: Node, thrower_: Node, pos: Vector3, vel: Vector3, exclude_: Array[RID], gun_: StringName, lit_: Callable) -> Flare:
	var f := Flare.new()
	f.thrower = thrower_
	f.weapon = WeaponInstance.new(data())
	f.velocity = vel
	f.exclude = exclude_
	f.gun = gun_
	f.lit = lit_
	parent.add_child(f)
	f.global_position = pos
	return f


## A road flare: a red stick with a white band and a cap, its tip burning.
static func make_flare_model() -> Node3D:
	var root := Node3D.new()
	var red := StandardMaterial3D.new()
	red.albedo_color = Color(0.85, 0.08, 0.06)
	red.roughness = 0.5
	var white := StandardMaterial3D.new()
	white.albedo_color = Color(0.95, 0.94, 0.9)
	var tip := StandardMaterial3D.new()
	tip.albedo_color = Color(1.0, 0.55, 0.4)
	tip.emission_enabled = true
	tip.emission = RED
	tip.emission_energy_multiplier = 6.0
	for part in [[0.024, 0.2, 0.0, red], [0.025, 0.03, 0.05, white], [0.027, 0.04, -0.105, red], [0.02, 0.025, 0.11, tip]]:
		var mi := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = part[0]
		cyl.bottom_radius = part[0]
		cyl.height = part[1]
		cyl.radial_segments = 12
		cyl.material = part[3]
		mi.mesh = cyl
		mi.position = Vector3(0, part[2], 0)
		root.add_child(mi)
	return root


func _ready() -> void:
	# (not a grenade: no one dives away from it)
	_gravity = weapon.data.projectile_gravity * float(ProjectSettings.get_setting("physics/3d/default_gravity", 16.0))
	_model = make_flare_model()
	add_child(_model)
	_spin = Vector3(randf_range(-9.0, 9.0), randf_range(-4.0, 4.0), randf_range(-9.0, 9.0))
	_glow = OmniLight3D.new()
	_glow.light_color = RED
	_glow.light_energy = 2.5
	_glow.omni_range = 9.0
	_glow.position = Vector3.UP * 0.3
	add_child(_glow)
	_smoke = FX.flare_smoke(self)
	Audio.play_at(&"match_countdown_beep", global_position, -8.0, 0.0, {"unit_size": 3.0})


func _physics_process(delta: float) -> void:
	_age += delta
	var was_resting := _resting
	_move(delta)
	if _resting and not was_resting:
		_model.rotation = Vector3(0.0, randf() * TAU, PI * 0.5)   # (it lies on its side)
	if _resting or _age > 4.0:
		_burning += delta
	if not _sent and _burning >= WAIT:
		_sent = true
		if lit.is_valid():
			lit.call(global_position)
	var fade := clampf((BURN - _age) / 2.0, 0.0, 1.0)
	_glow.light_energy = (2.2 + randf() * 0.9) * fade
	if _smoke:
		_smoke.emitting = fade > 0.5
	if _age >= BURN:
		queue_free()
