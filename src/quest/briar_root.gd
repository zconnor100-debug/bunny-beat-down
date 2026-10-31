class_name BriarRoot
extends Node3D
## One of the Briar's taproots (the Kernel Hunt's Finale, StarfallMission): a
## great thorny root broken up out of the island, snaking over the ground
## from its knot, where it came up, to the foot of Boulder Bluff, the
## Kernels' light running along it in pulses toward the Briar Heart. The knot
## is what to break: tough bark (carrots chip it, BARK; a blast does it the
## most harm, BLAST: Explosion's blast_targets), the rangers helping a little
## (HELP). While you're near, the Touched grow up out of the ground round it
## (`sprouted`: the mission brings them). Broken, it bursts gold-green, and
## the whole root withers grey and sinks back into the ground.

signal sprouted(at: Vector3)
signal cut(by: Node)
signal health_changed(health: float, max_health: float)

const HEALTH := 1300.0
const DIFFICULTY_HEALTH := [0.7, 1.0, 1.35]   ## Sleepy, Scrappy, Savage
const BARK := 0.55             ## carrots on its bark count this much
const BLAST := 1.7             ## a blast, this much
const HELP := 0.5              ## the rangers' hits (you do most of it)
const KNOT_R := 2.6            ## the knot's size (its radius, metres)
const ROOT_R := 0.95           ## the root's, where it leaves the knot (it thins toward the Bluff)
const NEAR := 80.0             ## you this close: the Touched grow up round it...
const SPROUT_EVERY := 10.0     ## ...every so often...
const MOST := 4                ## ...this many of its own at most
const BAR_CELLS := 12
const GLOW := Color(0.8, 1.0, 0.34)

var max_health := HEALTH
var health := HEALTH
var broken := false
var active := true             ## growing the Touched round it (the mission's step to cut them)
var sprouts: Array[Critter] = []   ## its own Touched, up now (the mission adds them)
var last_hit_pos := Vector3.ZERO
## Where it runs, in world space: from the knot (here) to its end, over the
## ground (set before it's added: StarfallMission).
var path := PackedVector3Array()
var _rng := RandomNumberGenerator.new()
var _mat: ShaderMaterial
var _knot: Node3D
var _knot_mat: ShaderMaterial
var _root_mesh: MeshInstance3D
var _thorns: MultiMeshInstance3D
var _light: OmniLight3D
var _area: Area3D
var _shape: CollisionShape3D
var _bar: Label3D
var _hum: AudioStreamPlayer3D
var _t := 0.0
var _sprout_t := 3.0
var _hurt := 0.0


func _init(difficulty := 1, seed_ := 1) -> void:
	name = "BriarRoot"
	max_health = HEALTH * float(DIFFICULTY_HEALTH[clampi(difficulty, 0, 2)])
	health = max_health
	_rng.seed = seed_


func _ready() -> void:
	add_to_group(&"briar_roots")
	add_to_group(&"blast_targets")
	add_to_group(&"objectives")
	_build()
	_hum = Audio.make_loop(&"kernel_hum", self) as AudioStreamPlayer3D
	if _hum:
		_hum.unit_size = 8.0
		_hum.max_distance = 90.0
		_hum.pitch_scale = 0.7
		_hum.position = Vector3(0, KNOT_R, 0)
		_hum.play()
	_show_bar()


# ---- what it looks like ----------------------------------------------------------------------------

func _build() -> void:
	_mat = VineMesh.bark_material(1.0, 0.08)
	# the root, from the knot (here) along `path`, half sunk in the ground
	if path.size() >= 2:
		var pts := PackedVector3Array()
		var radii := PackedFloat32Array()
		var total := 0.0
		for i in range(1, path.size()):
			total += path[i].distance_to(path[i - 1])
		var walked := 0.0
		for i in path.size():
			if i > 0:
				walked += path[i].distance_to(path[i - 1])
			var u := walked / maxf(total, 0.01)
			var r := lerpf(ROOT_R, ROOT_R * 0.55, u)
			# (humping up out of the ground and back down into it as it goes)
			var hump := maxf(0.0, sin(walked * 0.16 + 1.2)) * 0.7 * (1.0 - u * 0.5)
			pts.append(path[i] - path[0] + Vector3.UP * (r * 0.15 + hump))   # (it stands at path[0], unturned)
			radii.append(r)
		_root_mesh = MeshInstance3D.new()
		_root_mesh.name = "Root"
		_root_mesh.mesh = VineMesh.tube(pts, radii, 9)
		_root_mesh.material_override = _mat
		_root_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_root_mesh)
		_thorns = VineMesh.thorn_multimesh(VineMesh.thorns(pts, radii, _rng, 1.7, 2, 0.8), 0.9)
		_root_mesh.add_child(_thorns)
	# the knot: a swollen, thorny bulb of root coiled round on itself, split
	# where the light gets out
	_knot = Node3D.new()
	_knot.name = "Knot"
	add_child(_knot)
	_knot_mat = VineMesh.bark_material(0.6, 0.45)
	_knot_mat.set_shader_parameter(&"pulse_every", 4.0)
	_knot_mat.set_shader_parameter(&"pulse_speed", 3.0)
	var coils: Array[Transform3D] = []
	for k in 5:
		var pts := PackedVector3Array()
		var radii := PackedFloat32Array()
		var tilt := Basis(Vector3(_rng.randf_range(-1, 1), 0.3, _rng.randf_range(-1, 1)).normalized(), _rng.randf_range(0.5, 1.3))
		var r0 := KNOT_R * _rng.randf_range(0.65, 0.95)
		var y0 := KNOT_R * _rng.randf_range(0.7, 1.2)
		for i in 26:
			var a := TAU * 1.15 * i / 25.0 + k
			var rr := r0 * (1.0 + 0.12 * sin(a * 3.0))
			pts.append(tilt * Vector3(cos(a) * rr, sin(a * 2.0) * 0.35, sin(a) * rr) + Vector3.UP * y0)
			radii.append(lerpf(0.75, 1.05, sin(PI * i / 25.0)) * KNOT_R * 0.32)
		var coil := MeshInstance3D.new()
		coil.mesh = VineMesh.tube(pts, radii, 8)
		coil.material_override = _knot_mat
		_knot.add_child(coil)
		coils.append_array(VineMesh.thorns(pts, radii, _rng, 1.2, 2, 1.1))
	# a stump of root going down into the ground under it
	var stump := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = KNOT_R * 0.55
	cyl.bottom_radius = KNOT_R * 0.8
	cyl.height = KNOT_R * 1.6
	cyl.radial_segments = 10
	stump.mesh = cyl
	stump.material_override = _knot_mat
	stump.position = Vector3(0, KNOT_R * 0.3, 0)
	_knot.add_child(stump)
	_knot.add_child(VineMesh.thorn_multimesh(coils, 1.2))
	# its light, and the way it's seen across the island (a glow going up)
	_light = OmniLight3D.new()
	_light.light_color = GLOW
	_light.omni_range = 14.0
	_light.light_energy = 2.0
	_light.shadow_enabled = false
	_light.position = Vector3(0, KNOT_R * 1.1, 0)
	add_child(_light)
	var halo := Sprite3D.new()
	halo.name = "Halo"
	halo.texture = FXTextures.soft_blob()
	halo.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	halo.modulate = Color(GLOW, 0.2)
	halo.pixel_size = KNOT_R * 3.4 / maxf(halo.texture.get_width(), 1.0)
	halo.shaded = false
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	halo.position = Vector3(0, KNOT_R * 1.1, 0)
	_knot.add_child(halo)
	# solid (critters go round it), and where it's hit
	var body := StaticBody3D.new()
	body.collision_layer = Layers.WORLD
	body.collision_mask = 0
	body.set_meta(&"surface", &"wood")
	_shape = CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = KNOT_R * 0.95
	_shape.shape = sph
	_shape.position = Vector3(0, KNOT_R, 0)
	body.add_child(_shape)
	add_child(body)
	_area = Area3D.new()
	_area.name = "Hit_knot"
	_area.collision_layer = Layers.HITBOXES
	_area.collision_mask = 0
	_area.monitoring = false
	_area.monitorable = false
	_area.set_meta(&"critter", self)
	_area.set_meta(&"role", &"knot")
	var acs := CollisionShape3D.new()
	var asph := SphereShape3D.new()
	asph.radius = KNOT_R * 1.15
	acs.shape = asph
	acs.position = Vector3(0, KNOT_R, 0)
	_area.add_child(acs)
	add_child(_area)
	_bar = Label3D.new()
	_bar.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_bar.no_depth_test = true
	_bar.fixed_size = true
	_bar.pixel_size = 0.0016
	_bar.font_size = 34
	_bar.outline_size = 8
	_bar.position = Vector3(0, KNOT_R * 2.6, 0)
	add_child(_bar)


# ---- going ---------------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	_t += delta
	if broken:
		return
	_hurt = maxf(0.0, _hurt - delta * 3.0)
	var throb := 0.5 + 0.5 * sin(_t * 2.6)
	_light.light_energy = 1.4 + 1.6 * throb + 3.0 * _hurt
	_knot.scale = Vector3.ONE * (1.0 + 0.035 * throb + 0.06 * _hurt)
	_knot_mat.set_shader_parameter(&"hurt", _hurt)
	if not active:
		return
	_sprout_t -= delta
	if _sprout_t <= 0.0:
		_sprout_t = SPROUT_EVERY * _rng.randf_range(0.8, 1.2)
		sprouts = sprouts.filter(func(c): return is_instance_valid(c) and c.alive)
		if sprouts.size() < MOST and _you_near():
			var a := _rng.randf() * TAU
			sprouted.emit(global_position + Vector3(cos(a), 0.0, sin(a)) * _rng.randf_range(KNOT_R + 4.0, KNOT_R + 11.0))


func _you_near() -> bool:
	for n in get_tree().get_nodes_in_group(&"critters"):
		var c := n as Critter
		if c and c.is_player:
			return c.alive and c.global_position.distance_to(global_position) < NEAR
	return false


func _show_bar() -> void:
	if _bar == null:
		return
	var k := clampf(health / maxf(max_health, 1.0), 0.0, 1.0)
	var full := ceili(k * BAR_CELLS)
	_bar.text = "■".repeat(full) + "□".repeat(BAR_CELLS - full)
	_bar.modulate = Color(1.0, 0.25, 0.15).lerp(GLOW, k)
	_bar.visible = not broken and health < max_health


## Where its knot is (what to aim at: the middle of it).
func knot_point() -> Vector3:
	return global_position + Vector3.UP * KNOT_R


# ---- getting hurt -----------------------------------------------------------------------------------

## A carrot hit its knot.
func receive_shot(shooter: Node, data: WeaponData, dmg: float, pos: Vector3, dir: Vector3, _role: StringName, _mutated := false) -> void:
	_hit(shooter, dmg * BARK, pos, dir, DamageInfo.Kind.BULLET, data.id)


func receive_corpse_shot(_data: WeaponData, pos: Vector3, dir: Vector3, _body: Object) -> void:
	BossFX.chips(pos, 0.4, Color(0.3, 0.2, 0.26))


## A blast `radius` across at `pos` (Explosion): the more, the nearer its middle.
func receive_blast(pos: Vector3, radius: float, damage: float, shooter: Node, weapon_id: StringName) -> void:
	var middle := knot_point()
	var d := maxf(0.0, pos.distance_to(middle) - KNOT_R)
	if d > radius:
		return
	_hit(shooter, damage * BLAST * pow(1.0 - d / radius, 0.8), pos, (middle - pos).normalized(), DamageInfo.Kind.EXPLOSION, weapon_id)


func _hit(shooter: Node, amount: float, pos: Vector3, dir: Vector3, kind: DamageInfo.Kind, weapon_id: StringName) -> void:
	if broken:
		return
	var by := shooter as Critter
	if by and by.team == 2:
		return   # (the Touched don't hurt it)
	if by and not by.is_player:
		amount *= HELP
	health = maxf(0.0, health - amount)
	last_hit_pos = pos
	_hurt = 1.0
	BossFX.chips(pos, clampf(amount / 60.0, 0.3, 1.0), Color(0.3, 0.2, 0.26))
	FX.burst(pos, -dir, {"amount": 6, "lifetime": 0.9, "speed": Vector2(1.0, 3.0), "spread": 50.0, "gravity": 1.0, "size": 0.12,
		"scale": Vector2(0.6, 1.3), "color": Color(GLOW, 0.8), "fade": true, "additive": true, "damping": 2.0})
	Audio.play_at(&"carrot_impact_wood", pos, -8.0, 0.15)
	if by and by.is_player:
		Events.player_hit_confirmed.emit(self, amount, false, health <= 0.0)
		StatBook.note_hit(weapon_id, amount, false, kind == DamageInfo.Kind.EXPLOSION)
	health_changed.emit(health, max_health)
	_show_bar()
	if health <= 0.0:
		break_down(shooter)


## It's cut: the knot bursts, its light goes out, and the root withers back
## into the ground.
func break_down(by: Node = null) -> void:
	if broken:
		return
	broken = true
	active = false
	remove_from_group(&"blast_targets")
	remove_from_group(&"objectives")
	_show_bar()
	_area.collision_layer = 0
	_shape.set_deferred(&"disabled", true)
	if _hum:
		_hum.stop()
	var at := knot_point()
	Audio.play_at(&"root_snap", at, 8.0, 0.05, {"max_distance": 600.0, "unit_size": 30.0})
	FX.burst(at, Vector3.UP, {"amount": 60, "lifetime": 2.2, "speed": Vector2(3.0, 11.0), "spread": 160.0, "gravity": -0.6,
		"size": 0.4, "scale": Vector2(0.6, 1.5), "color": Color(GLOW, 0.95), "fade": true, "additive": true, "damping": 1.4, "aabb": 30.0})
	FX.muzzle(at, Vector3.UP, true, Color(GLOW, 1.0))
	BossFX.chips(at, 2.2, Color(0.28, 0.18, 0.24))
	BossFX.dust(global_position, 9.0, Color(0.28, 0.22, 0.24, 0.7))
	Events.explosion.emit(at, 10.0)
	var tw := create_tween()
	tw.tween_property(_light, "light_energy", 9.0, 0.12)
	tw.tween_property(_light, "light_energy", 0.0, 1.4)
	var wither := create_tween()
	wither.tween_method(_wither, 1.0, 0.0, 2.6)
	wither.parallel().tween_property(_knot, "scale", Vector3(1.1, 0.35, 1.1), 2.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	if _root_mesh:
		wither.tween_property(_root_mesh, "position:y", -2.2, 5.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	cut.emit(by)


func _wither(k: float) -> void:
	_mat.set_shader_parameter(&"alive", k)
	_knot_mat.set_shader_parameter(&"alive", k)
	(_knot.get_node("Halo") as Sprite3D).modulate = Color(GLOW, 0.2 * k)
