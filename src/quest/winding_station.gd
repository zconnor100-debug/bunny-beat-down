class_name WindingStation
extends StaticBody3D
## One of the Tin Tyrant's winding stations (the Kernel Hunt's Act II,
## ClockworkMission): a tin wind-up machine as big as a shed, painted like an
## old toy, where he winds the Wound. Its drum turns, its gears grind and the
## big key on its end turns and turns; while it's `active`, and you're near,
## it winds one out of its chute every so often (`wound_out`: the mission
## brings it). Tin takes the sting out of carrots (TIN), but not on its drum,
## where its spring is (SPRING), and blasts do it the most harm (BLAST).
## Broken (`broken`), it comes apart: the drum rolls off, the gears fly, the
## key goes up and comes down somewhere, and what's left smokes.

signal wound_out(at: Vector3, facing: Vector3)
signal broken_down(by: Node)
signal health_changed(health: float, max_health: float)

const HEALTH := 1200.0
const DIFFICULTY_HEALTH := [0.7, 1.0, 1.35]   ## Sleepy, Scrappy, Savage
const TIN := 0.6               ## carrots on its tin count this much...
const SPRING := 1.8            ## ...on its drum, this much
const BLAST := 1.6             ## blasts, this much more
const WIND_EVERY := 20.0       ## seconds between the Wound it winds out
const WIND_UP := 2.2           ## seconds its key whirs before one comes out
const WIND_NEAR := 160.0       ## metres: it winds only while you're this near
const MOST := 3                ## of its own Wound out at once, at most
const W := 10.0                ## its base: wide (x)...
const H := 4.5                 ## ...tall...
const D := 7.0                 ## ...and deep (z: its chute is on its front, +z)
const DRUM_R := 2.6
const DRUM_L := 8.2
const RED := Color(0.86, 0.16, 0.12)
const BAR_CELLS := 12

var max_health := HEALTH
var health := HEALTH
var broken := false
var active := false            ## winding them out (the mission's step to break them)
var wound: Array[Critter] = [] ## its own Wound, out now (the mission adds them)
var last_hit_pos := Vector3.ZERO
var _drum: Node3D
var _key: WindKey
var _gears: Array = []         # [Node3D, turns a second]
var _bulb_mat: StandardMaterial3D
var _light: OmniLight3D
var _bar: Label3D
var _hum: AudioStreamPlayer3D
var _areas: Array[Area3D] = []
var _base_meshes: Array[MeshInstance3D] = []
var _drum_shape: CollisionShape3D
var _wind_t := 6.0
var _winding := -1.0           # seconds into a wind-up (-1: not winding)
var _t := 0.0
var _hurt := 0.0               # (the bulb flickers when it's hit)
var _steam_t := 1.0


func _init(difficulty := 1) -> void:
	name = "WindingStation"
	max_health = HEALTH * float(DIFFICULTY_HEALTH[clampi(difficulty, 0, 2)])
	health = max_health


func _ready() -> void:
	add_to_group(&"winding_stations")
	add_to_group(&"blast_targets")
	collision_layer = Layers.WORLD
	collision_mask = 0
	set_meta(&"surface", &"metal")
	_build()
	_hum = Audio.make_loop(&"clockwork_loop", self) as AudioStreamPlayer3D
	if _hum:
		_hum.unit_size = 12.0
		_hum.max_distance = 140.0
		_hum.position = Vector3(0, H, 0)
		_hum.play()
	_show_bar()


# ---- what it looks like ----------------------------------------------------------------------------

func _build() -> void:
	var tin_red := CageKit.mat(&"plastic_red")
	var tin_blue := CageKit.mat(&"plastic_blue")
	var tin_yellow := CageKit.mat(&"plastic_yellow")
	var brass := StandardMaterial3D.new()
	brass.albedo_color = WindKey.BRASS
	brass.metallic = 0.85
	brass.roughness = 0.3
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.05, 0.04, 0.04)
	dark.roughness = 0.9
	# the base, and its yellow bands top and bottom, riveted
	_base_meshes.append(_mesh(_boxm(Vector3(W, H, D)), tin_red, Vector3(0, H * 0.5, 0)))
	for y in [0.3, H - 0.3]:
		_base_meshes.append(_mesh(_boxm(Vector3(W + 0.3, 0.6, D + 0.3)), tin_yellow, Vector3(0, y, 0)))
	for i in 9:
		for zs in [-1.0, 1.0]:
			var r := _mesh(_ballm(0.16), brass, Vector3(-W * 0.5 + 0.7 + i * (W - 1.4) / 8.0, H - 0.3, zs * (D * 0.5 + 0.2)))
			_base_meshes.append(r)
	# the drum on top (its spring's inside), turning, banded with brass, capped yellow
	_drum = Node3D.new()
	_drum.name = "Drum"
	_drum.position = Vector3(0, H + DRUM_R * 0.92, 0)
	add_child(_drum)
	var cyl := CylinderMesh.new()
	cyl.top_radius = DRUM_R
	cyl.bottom_radius = DRUM_R
	cyl.height = DRUM_L
	cyl.radial_segments = 28
	cyl.rings = 1
	var drum := _mesh(cyl, tin_blue, Vector3.ZERO, _drum)
	drum.rotation.z = PI * 0.5
	for x in [-DRUM_L * 0.36, 0.0, DRUM_L * 0.36]:
		var band := TorusMesh.new()
		band.inner_radius = DRUM_R - 0.05
		band.outer_radius = DRUM_R + 0.22
		band.rings = 32
		band.ring_segments = 6
		var b := _mesh(band, brass, Vector3(x, 0, 0), _drum)
		b.rotation.z = PI * 0.5
	for xs in [-1.0, 1.0]:
		var cap := CylinderMesh.new()
		cap.top_radius = DRUM_R * 0.72
		cap.bottom_radius = DRUM_R * 0.86
		cap.height = 0.5
		cap.radial_segments = 24
		var c := _mesh(cap, tin_yellow, Vector3(xs * (DRUM_L * 0.5 + 0.2), 0, 0), _drum)
		c.rotation.z = -xs * PI * 0.5
		# (a stripe painted round it: you can see it turn)
		_mesh(_boxm(Vector3(0.12, DRUM_R * 1.6, 0.5)), tin_red, Vector3(xs * (DRUM_L * 0.5 + 0.47), 0, 0), _drum)
	# the stand the drum turns in
	for xs in [-1.0, 1.0]:
		_base_meshes.append(_mesh(_boxm(Vector3(0.7, DRUM_R * 1.3, 1.6)), tin_yellow, Vector3(xs * (DRUM_L * 0.5 + 0.75), H + DRUM_R * 0.55, 0)))
	# the big key, out of the drum's end
	_key = WindKey.new(5.5)
	_key.speed = 110.0
	_key.position = Vector3(DRUM_L * 0.5 + 0.9, H + DRUM_R * 0.92, 0)
	_key.rotation.y = PI * 0.5   # (its shaft along +x)
	add_child(_key)
	# gears on its front, grinding against each other, and one round the back
	for g in [[Vector3(-2.6, 2.3, D * 0.5 + 0.35), 1.75, 12, 0.5], [Vector3(-0.35, 3.25, D * 0.5 + 0.35), 1.05, 8, -0.833],
			[Vector3(1.0, 2.2, -D * 0.5 - 0.35), 1.5, 10, 0.4]]:
		var gear := Node3D.new()
		gear.position = g[0]
		add_child(gear)
		_mesh(_gear_mesh(int(g[2]), float(g[1]), 0.36, 0.45), brass, Vector3.ZERO, gear)
		var hub := CylinderMesh.new()
		hub.top_radius = float(g[1]) * 0.28
		hub.bottom_radius = float(g[1]) * 0.28
		hub.height = 0.7
		hub.radial_segments = 12
		var h := _mesh(hub, tin_red, Vector3.ZERO, gear)
		h.rotation.x = PI * 0.5
		_gears.append([gear, float(g[3])])
	# the chute it winds them out of, on the right of its front, with a ramp down
	var chute := Vector3(2.6, 1.9, D * 0.5)
	_base_meshes.append(_mesh(_boxm(Vector3(3.0, 3.2, 0.2)), dark, chute + Vector3(0, 0, 0.02)))
	for f in [[Vector3(-1.65, 0, 0), Vector3(0.3, 3.8, 0.5)], [Vector3(1.65, 0, 0), Vector3(0.3, 3.8, 0.5)], [Vector3(0, 1.85, 0), Vector3(3.6, 0.3, 0.5)]]:
		_base_meshes.append(_mesh(_boxm(f[1]), tin_yellow, chute + f[0] + Vector3(0, 0, 0.15)))
	var ramp := _mesh(_boxm(Vector3(3.0, 0.25, 2.6)), tin_yellow, chute + Vector3(0, -1.3, 1.3))
	ramp.rotation.x = 0.42
	_base_meshes.append(ramp)
	# the warning bulb on its post, and its stack
	_base_meshes.append(_mesh(_boxm(Vector3(0.35, 2.0, 0.35)), tin_yellow, Vector3(-W * 0.5 + 0.9, H + 1.0, -D * 0.5 + 0.9)))
	_bulb_mat = StandardMaterial3D.new()
	_bulb_mat.albedo_color = RED
	_bulb_mat.emission_enabled = true
	_bulb_mat.emission = RED
	_bulb_mat.emission_energy_multiplier = 3.0
	_mesh(_ballm(0.55), _bulb_mat, Vector3(-W * 0.5 + 0.9, H + 2.3, -D * 0.5 + 0.9))
	_light = OmniLight3D.new()
	_light.light_color = RED
	_light.omni_range = 14.0
	_light.light_energy = 1.5
	_light.shadow_enabled = false
	_light.position = Vector3(-W * 0.5 + 0.9, H + 2.6, -D * 0.5 + 0.9)
	add_child(_light)
	var stack := CylinderMesh.new()
	stack.top_radius = 0.55
	stack.bottom_radius = 0.7
	stack.height = 2.8
	stack.radial_segments = 14
	_base_meshes.append(_mesh(stack, CageKit.mat(&"metal"), Vector3(W * 0.5 - 1.0, H + 1.4, -D * 0.5 + 1.0)))
	# solid: the base and the drum
	var base_cs := CollisionShape3D.new()
	var bb := BoxShape3D.new()
	bb.size = Vector3(W, H, D)
	base_cs.shape = bb
	base_cs.position = Vector3(0, H * 0.5, 0)
	add_child(base_cs)
	_drum_shape = CollisionShape3D.new()
	var dc := CylinderShape3D.new()
	dc.radius = DRUM_R
	dc.height = DRUM_L
	_drum_shape.shape = dc
	_drum_shape.position = _drum.position
	_drum_shape.rotation.z = PI * 0.5
	add_child(_drum_shape)
	# where carrots hurt it (a little proud of the solid, so a carrot finds these first)
	_hit_area(&"tin", _box_shape(Vector3(W + 0.4, H + 0.3, D + 0.4)), Vector3(0, H * 0.5, 0), Vector3.ZERO)
	var spring := CylinderShape3D.new()
	spring.radius = DRUM_R + 0.3
	spring.height = DRUM_L + 0.8
	_hit_area(&"spring", spring, _drum.position, Vector3(0, 0, PI * 0.5))
	# its bar, over it
	_bar = Label3D.new()
	_bar.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_bar.font_size = 64
	_bar.outline_size = 14
	_bar.pixel_size = 0.012
	_bar.position = Vector3(0, H + DRUM_R * 2.0 + 2.6, 0)
	_bar.modulate = Color(1.0, 0.85, 0.3)
	add_child(_bar)


func _hit_area(role: StringName, shape: Shape3D, at: Vector3, rot: Vector3) -> void:
	var area := Area3D.new()
	area.name = "Hit_" + role
	area.collision_layer = Layers.HITBOXES
	area.collision_mask = 0
	area.monitoring = false
	area.monitorable = false
	area.set_meta(&"critter", self)
	area.set_meta(&"role", role)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = at
	cs.rotation = rot
	area.add_child(cs)
	add_child(area)
	_areas.append(area)


func _mesh(m: Mesh, mat: Material, at: Vector3, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = mat
	mi.position = at
	(parent if parent else self).add_child(mi)
	return mi


static func _boxm(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


static func _ballm(r: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 12
	s.rings = 6
	return s


static func _box_shape(size: Vector3) -> BoxShape3D:
	var b := BoxShape3D.new()
	b.size = size
	return b


## A gear: `teeth` square-ish teeth round a disc `r` across to their tips,
## `depth` deep, `thick` through (along z).
static func _gear_mesh(teeth: int, r: float, depth: float, thick: float) -> ArrayMesh:
	var pts := PackedVector2Array()
	var step := TAU / teeth
	for i in teeth:
		var a := step * i
		pts.append(Vector2.from_angle(a) * (r - depth))
		pts.append(Vector2.from_angle(a + step * 0.12) * r)
		pts.append(Vector2.from_angle(a + step * 0.45) * r)
		pts.append(Vector2.from_angle(a + step * 0.57) * (r - depth))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := pts.size()
	for side in [1.0, -1.0]:
		var z: float = thick * 0.5 * side
		for i in n:
			var a := pts[i]
			var b := pts[(i + 1) % n]
			_tri(st, Vector3(0, 0, z), Vector3(a.x, a.y, z), Vector3(b.x, b.y, z), Vector3(0, 0, side))
	for i in n:
		var a := pts[i]
		var b := pts[(i + 1) % n]
		var e := b - a
		var out := Vector3(e.y, -e.x, 0.0).normalized()
		if out.dot(Vector3(a.x + b.x, a.y + b.y, 0.0)) < 0.0:
			out = -out
		var a0 := Vector3(a.x, a.y, thick * 0.5)
		var b0 := Vector3(b.x, b.y, thick * 0.5)
		var a1 := Vector3(a.x, a.y, -thick * 0.5)
		var b1 := Vector3(b.x, b.y, -thick * 0.5)
		_tri(st, a0, b0, b1, out)
		_tri(st, a0, b1, a1, out)
	return st.commit()


## A triangle facing `n` (Godot's front faces wind clockwise, seen from in front).
static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, n: Vector3) -> void:
	var p := [a, b, c] if (b - a).cross(c - a).dot(n) < 0.0 else [a, c, b]
	for v in p:
		st.set_normal(n)
		st.add_vertex(v)


# ---- going ---------------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	_t += delta
	if broken:
		return
	var busy := _winding >= 0.0
	_drum.rotation.x += delta * (2.4 if busy else 0.5)
	_key.speed = 900.0 if busy else 110.0
	for g in _gears:
		(g[0] as Node3D).rotation.z += delta * float(g[1]) * (4.0 if busy else 1.0)
	_hurt = maxf(0.0, _hurt - delta * 3.0)
	var blink := 0.5 + 0.5 * sin(_t * (9.0 if busy else 3.0))
	_bulb_mat.emission_energy_multiplier = 1.0 + 3.0 * blink + 6.0 * _hurt
	_light.light_energy = 0.6 + 1.6 * blink + 3.0 * _hurt
	_steam_t -= delta
	if _steam_t <= 0.0:
		_steam_t = 0.9 if busy else 2.6
		FX.burst(to_global(Vector3(W * 0.5 - 1.0, H + 3.0, -D * 0.5 + 1.0)), Vector3.UP, {"amount": 5, "lifetime": 1.8,
			"speed": Vector2(1.5, 3.0), "spread": 18.0, "gravity": -0.8, "size": 0.9, "scale": Vector2(0.6, 1.5),
			"color": Color(0.94, 0.94, 0.92, 0.5), "fade": true, "damping": 1.2, "aabb": 12.0})
	if busy:
		_winding += delta
		if _winding >= WIND_UP:
			_winding = -1.0
			var front := global_basis.z.normalized()
			wound_out.emit(to_global(Vector3(2.6, 0.0, D * 0.5 + 3.4)), front)
			FX.burst(to_global(Vector3(2.6, 1.6, D * 0.5 + 0.6)), front, {"amount": 14, "lifetime": 1.4, "speed": Vector2(2.0, 5.0),
				"spread": 40.0, "gravity": -0.5, "size": 1.0, "scale": Vector2(0.6, 1.4), "color": Color(0.94, 0.94, 0.92, 0.55),
				"fade": true, "damping": 2.0, "aabb": 14.0})
		return
	if not active:
		return
	_wind_t -= delta
	if _wind_t <= 0.0:
		_wind_t = WIND_EVERY
		wound = wound.filter(func(c): return is_instance_valid(c) and c.alive)
		if wound.size() < MOST and _you_near():
			_winding = 0.0
			Audio.play_at(&"wind_key", _key.global_position, 4.0, 0.05, {"max_distance": 220.0, "unit_size": 18.0})


func _you_near() -> bool:
	var p: Critter = null
	for n in get_tree().get_nodes_in_group(&"critters"):
		if (n as Critter).is_player:
			p = n
			break
	return p != null and p.alive and p.global_position.distance_to(global_position) < WIND_NEAR


## The one to break now: on the HUD and the minimap (the mission's step), or not.
func mark(on: bool) -> void:
	if on and not broken:
		add_to_group(&"objectives")
	elif is_in_group(&"objectives"):
		remove_from_group(&"objectives")


func _show_bar() -> void:
	if _bar == null:
		return
	var k := clampf(health / maxf(max_health, 1.0), 0.0, 1.0)
	var full := ceili(k * BAR_CELLS)
	_bar.text = "■".repeat(full) + "□".repeat(BAR_CELLS - full)
	_bar.modulate = Color(1.0, 0.25, 0.15).lerp(Color(1.0, 0.85, 0.3), k)
	_bar.visible = not broken and health < max_health


# ---- getting hurt -----------------------------------------------------------------------------------

## A carrot hit it (on its tin, or its drum).
func receive_shot(shooter: Node, data: WeaponData, dmg: float, pos: Vector3, dir: Vector3, role: StringName, _mutated := false) -> void:
	_hit(shooter, dmg * (SPRING if role == &"spring" else TIN), pos, dir, role == &"spring", DamageInfo.Kind.BULLET, data.id)


func receive_corpse_shot(_data: WeaponData, pos: Vector3, dir: Vector3, _body: Object) -> void:
	BossFX.sparks(pos, -dir, 0.4)


## A blast `radius` across at `pos` (Explosion): the more, the nearer its middle.
func receive_blast(pos: Vector3, radius: float, damage: float, shooter: Node, weapon_id: StringName) -> void:
	var middle := to_global(Vector3(0, H * 0.7, 0))
	var d := maxf(0.0, pos.distance_to(middle) - W * 0.5)
	if d > radius:
		return
	_hit(shooter, damage * BLAST * pow(1.0 - d / radius, 0.8), pos, (middle - pos).normalized(), false, DamageInfo.Kind.EXPLOSION, weapon_id)


func _hit(shooter: Node, amount: float, pos: Vector3, dir: Vector3, spring: bool, kind: DamageInfo.Kind, weapon_id: StringName) -> void:
	if broken:
		return
	var by := shooter as Critter
	if by and by.team == 2:
		return   # (the Wound don't hurt their own)
	if by and not by.is_player:
		amount *= 0.5   # (the rangers help, you do most of it)
	health = maxf(0.0, health - amount)
	last_hit_pos = pos
	_hurt = 1.0
	BossFX.sparks(pos, -dir, clampf(amount / 40.0, 0.4, 1.3))
	Audio.play_at(&"armor_break" if spring else &"carrot_impact_wood", pos, -8.0 if not spring else -10.0, 0.15)
	if by and by.is_player:
		Events.player_hit_confirmed.emit(self, amount, spring, health <= 0.0)
		StatBook.note_hit(weapon_id, amount, spring, kind == DamageInfo.Kind.EXPLOSION)
	health_changed.emit(health, max_health)
	_show_bar()
	if health <= 0.0:
		break_down(shooter)


## It comes apart.
func break_down(by: Node = null) -> void:
	if broken:
		return
	broken = true
	active = false
	mark(false)
	remove_from_group(&"blast_targets")
	_show_bar()
	for a in _areas:
		a.collision_layer = 0
	_drum_shape.set_deferred(&"disabled", true)
	if _hum:
		_hum.stop()
	_light.light_energy = 0.0
	_bulb_mat.emission_energy_multiplier = 0.0
	var top := to_global(Vector3(0, H + DRUM_R, 0))
	Audio.play_at(&"station_break", top, 8.0, 0.05, {"max_distance": 600.0, "unit_size": 30.0})
	Audio.play_at(&"explosion", top, 2.0, 0.1, {"max_distance": 500.0, "unit_size": 25.0})
	FX.explosion(top, 7.0)
	Events.explosion.emit(top, 12.0)
	BossFX.sparks(top, Vector3.UP, 3.0)
	BossFX.chips(top, 1.6, RED)
	BossFX.dust(global_position, 12.0, Color(0.3, 0.29, 0.28, 0.6))
	# the drum rolls off, the gears and the key fly, and it smokes
	_fling(_drum, _cylinder_shape(DRUM_R, DRUM_L, true), 30.0, Vector3(randf_range(-4, 4), 7.0, randf_range(-4, 4)))
	for g in _gears:
		_fling(g[0], _cylinder_shape(1.5, 0.5, false), 4.0, Vector3(randf_range(-9, 9), randf_range(8, 14), randf_range(-9, 9)), Vector3(PI * 0.5, 0, 0))
	_fling(_key, _box_shape(Vector3(1.0, 3.2, 3.4)), 6.0, Vector3(randf_range(-5, 5), 22.0, randf_range(-5, 5)))
	for mi in _base_meshes:
		if is_instance_valid(mi):
			mi.material_overlay = _scorch()
	var tw := create_tween()   # (what's left lurches over)
	tw.tween_property(self, "rotation:z", rotation.z + randf_range(0.08, 0.14) * (1.0 if randf() < 0.5 else -1.0), 0.35).set_trans(Tween.TRANS_BACK)
	BossFX.dust_column(top, 6.0, 0.35, Color(0.17, 0.16, 0.15, 0.8))   # (it smokes: you can see which are done from afar)
	broken_down.emit(by)


## `part` comes off as a body of its own (it rolls, bounces and lies there a while).
func _fling(part: Node3D, shape: Shape3D, mass: float, velocity: Vector3, shape_turn := Vector3.ZERO) -> void:
	if part == null or not is_instance_valid(part):
		return
	var body := RigidBody3D.new()
	body.name = "Scrap"
	body.collision_layer = Layers.DEBRIS
	body.collision_mask = Layers.WORLD | Layers.DEBRIS
	body.mass = mass
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.rotation = shape_turn   # (a gear's a disc across its own z)
	body.add_child(cs)
	Despawner.debris_parent(self).add_child(body)
	body.global_transform = part.global_transform
	part.reparent(body)
	part.transform = Transform3D(part.transform.basis, Vector3.ZERO)
	body.linear_velocity = velocity
	body.angular_velocity = Vector3(randf_range(-6, 6), randf_range(-6, 6), randf_range(-6, 6))
	if part is WindKey:
		(part as WindKey).speed = 0.0
	Despawner.schedule(body, 30.0, 1.0)


static func _cylinder_shape(r: float, h: float, along_x: bool) -> Shape3D:
	var c := CylinderShape3D.new()
	c.radius = r
	c.height = h
	if not along_x:
		return c
	# (the drum lies along x: a convex hull of it turned that way)
	var pts := PackedVector3Array()
	for i in 16:
		var a := TAU * i / 16.0
		for x in [-h * 0.5, h * 0.5]:
			pts.append(Vector3(x, cos(a) * r, sin(a) * r))
	var hull := ConvexPolygonShape3D.new()
	hull.points = pts
	return hull


static var _scorched: ShaderMaterial


## Soot over what's left of it (an overlay: its paint shows through, darker).
static func _scorch() -> ShaderMaterial:
	if _scorched == null:
		var sh := Shader.new()
		sh.code = "shader_type spatial;\nrender_mode unshaded, cull_back;\nvoid fragment() {\n\tALBEDO = vec3(0.03, 0.025, 0.02);\n\tALPHA = 0.62;\n}\n"
		_scorched = ShaderMaterial.new()
		_scorched.shader = sh
	return _scorched
