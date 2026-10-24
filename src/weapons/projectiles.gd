class_name Projectiles
extends Node3D
## Every carrot in flight. Bolts and pellets are plain data stepped with a
## ray per physics tick (so fast carrots never tunnel) and drawn with one
## MultiMesh per kind; rockets are real nodes (see Rocket).
## Every carrot also draws a glowing tracer streak behind it, so you can see
## shots fly and tell where they came from.
## Carrots that hit something stay stuck in it — trees, crates, and critters.

const MAX_STUCK := 220
const MAX_LIFE := 3.0

const BOLT_MODEL := "res://assets/weapons/carrot_bolt.glb"
const PELLET_MODEL := "res://assets/weapons/carrot_shell_pellet.glb"
const TRACER_SHADER := preload("res://src/fx/tracer.gdshader")
const TRACER_SECONDS := 0.06         ## a tracer is as long as this much flight
const TRACER_ENEMY := Color(1.0, 0.3, 0.04, 1.0)     ## shots at you: hot orange
const TRACER_OWN := Color(1.0, 0.85, 0.5, 0.5)       ## your own: fainter, out of your way
## Your own tracers' colour this match (the Workshop's "Your tracers" look).
static var own_tracer := TRACER_OWN

static var instance: Projectiles


class Shot:
	var pos: Vector3
	var vel: Vector3
	var gravity: float
	var data: WeaponData
	var damage_scale: float
	var shooter: Node
	var exclude: Array[RID]
	var travelled := 0.0
	var life := 0.0


var _shots: Array[Shot] = []
var _mm: Dictionary = {}          # ProjectileKind -> MultiMeshInstance3D
var _tracers: MultiMeshInstance3D
var _stuck: Array[Node3D] = []
var _bolt_mesh: Mesh
var _pellet_mesh: Mesh


func _enter_tree() -> void:
	instance = self


func _exit_tree() -> void:
	if instance == self:
		instance = null


func _ready() -> void:
	_bolt_mesh = ModelUtil.first_mesh(BOLT_MODEL)
	if _bolt_mesh == null:
		_bolt_mesh = _fallback_carrot(0.14, 0.018)
	_pellet_mesh = ModelUtil.first_mesh(PELLET_MODEL)
	if _pellet_mesh == null:
		_pellet_mesh = _fallback_carrot(0.05, 0.016)
	for kind in [WeaponData.ProjectileKind.BOLT, WeaponData.ProjectileKind.PELLET]:
		var mmi := MultiMeshInstance3D.new()
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = _bolt_mesh if kind == WeaponData.ProjectileKind.BOLT else _pellet_mesh
		mm.instance_count = 512
		mm.visible_instance_count = 0
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.custom_aabb = AABB(Vector3(-2000, -500, -2000), Vector3(4000, 2000, 4000))
		add_child(mmi)
		_mm[kind] = mmi
	_tracers = MultiMeshInstance3D.new()
	_tracers.name = "Tracers"
	var tm := MultiMesh.new()
	tm.transform_format = MultiMesh.TRANSFORM_3D
	tm.use_custom_data = true
	tm.mesh = _tracer_strip()
	tm.instance_count = 1024
	tm.visible_instance_count = 0
	_tracers.multimesh = tm
	_tracers.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_tracers.custom_aabb = AABB(Vector3(-2000, -500, -2000), Vector3(4000, 2000, 4000))
	add_child(_tracers)


## Fire one trigger pull: spawns `pellets` projectiles inside the spread cone.
## `carried`: the velocity of whatever the shooter stands on (a moving toy
## train car), which the carrots keep, so riders can hit each other.
static func fire(shooter: Node, weapon: WeaponInstance, origin: Vector3, dir: Vector3, spread_deg: float, exclude: Array[RID], carried := Vector3.ZERO) -> void:
	if instance == null:
		return
	var data := weapon.data
	for i in data.pellets:
		var d := _spread_dir(dir, spread_deg) if data.pellets == 1 else _pattern_dir(dir, spread_deg, i, data.pellets)
		if data.projectile == WeaponData.ProjectileKind.ROCKET:
			var r := Rocket.new()
			r.setup(shooter, weapon, d, exclude)
			r.velocity += carried
			instance.add_child(r)
			r.global_position = origin
			if KillCam.recording and not KillCam.instance.playing:
				KillCam.instance.note_node(r, Rocket.MODEL)
			continue
		var s := Shot.new()
		s.pos = origin
		s.vel = d * data.projectile_speed + carried
		s.gravity = data.projectile_gravity * ProjectSettings.get_setting("physics/3d/default_gravity", 16.0)
		s.data = data
		s.damage_scale = weapon.damage_scale()
		s.shooter = shooter
		s.exclude = exclude
		instance._shots.append(s)
		if KillCam.recording and not KillCam.instance.playing:
			KillCam.instance.note_shot(s)


## Rewind (see TimeKeeper): every carrot and rocket in flight vanishes.
func clear_in_flight() -> void:
	_shots.clear()
	for c in get_children():
		if c is Rocket:
			c.queue_free()


## Where to point a shot so it lands on the crosshair: carrots drop, so
## inside a gun's effective range (falloff_end) the launch is lofted to make
## up for it exactly (a gun hits what you aim at); further out the drop
## starts to show, so long shots still take some skill.
static func zeroed(origin: Vector3, dir: Vector3, distance: float, data: WeaponData) -> Vector3:
	var g := data.projectile_gravity * float(ProjectSettings.get_setting("physics/3d/default_gravity", 16.0))
	if g <= 0.0 or data.projectile_speed <= 0.0:
		return dir
	var t := minf(distance, data.falloff_end) / data.projectile_speed
	var drop := 0.5 * g * t * t
	return (dir * minf(distance, data.falloff_end) + Vector3.UP * drop).normalized()


## A shotgun's pellets: one down the middle and the rest in an even ring
## (a little jitter, so no two blasts are identical) - a pattern you can
## learn, rather than a random cone.
static func _pattern_dir(dir: Vector3, spread_deg: float, i: int, n: int) -> Vector3:
	var d := dir.normalized()
	if i == 0 or spread_deg <= 0.0:
		return d
	var side := d.cross(Vector3.UP)
	if side.length_squared() < 1e-6:
		side = d.cross(Vector3.RIGHT)
	side = side.normalized()
	var up := side.cross(d)
	var a := TAU * float(i - 1) / float(n - 1) + randf_range(-0.2, 0.2)
	var r := tan(deg_to_rad(spread_deg * randf_range(0.6, 0.95)))
	return (d + (side * cos(a) + up * sin(a)) * r).normalized()


## Random direction inside a cone, uniformly distributed over the cap.
static func _spread_dir(dir: Vector3, spread_deg: float) -> Vector3:
	if spread_deg <= 0.0:
		return dir.normalized()
	var d := dir.normalized()
	var side := d.cross(Vector3.UP)
	if side.length_squared() < 1e-6:
		side = d.cross(Vector3.RIGHT)
	side = side.normalized()
	var up := side.cross(d)
	var cos_max := cos(deg_to_rad(spread_deg))
	var z := lerpf(cos_max, 1.0, randf())
	var r := sqrt(maxf(0.0, 1.0 - z * z))
	var a := randf() * TAU
	return (d * z + side * (r * cos(a)) + up * (r * sin(a))).normalized()


func _physics_process(delta: float) -> void:
	if _shots.is_empty():
		return
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.new()
	q.collision_mask = Layers.SHOT_MASK
	q.collide_with_areas = true
	q.hit_back_faces = false
	var i := 0
	while i < _shots.size():
		var s := _shots[i]
		var next := s.pos + s.vel * delta
		s.vel.y -= s.gravity * delta
		q.from = s.pos
		q.to = next
		q.exclude = s.exclude
		var hit := space.intersect_ray(q)
		if hit:
			s.travelled += s.pos.distance_to(hit.position)
			s.pos = hit.position
			if KillCam.recording:
				KillCam.instance.end_shot(s)
			_on_hit(s, hit)
			_shots.remove_at(i)
			continue
		s.travelled += s.pos.distance_to(next)
		s.pos = next
		s.life += delta
		if s.life > MAX_LIFE or s.pos.y < -50.0:
			if KillCam.recording:
				KillCam.instance.end_shot(s)
			_shots.remove_at(i)
			continue
		i += 1


func _process(_delta: float) -> void:
	# draw: extrapolate by the physics interpolation fraction for smooth motion
	draw_shots(_shots, Engine.get_physics_interpolation_fraction() / float(Engine.physics_ticks_per_second))


## The carrots in flight right now (the KillCam's replay draws its own).
func live_shots() -> Array[Shot]:
	return _shots


## Draw these carrots and their tracers, `frac` seconds ahead of where they are.
func draw_shots(shots: Array[Shot], frac := 0.0) -> void:
	var counts := {WeaponData.ProjectileKind.BOLT: 0, WeaponData.ProjectileKind.PELLET: 0}
	for s in shots:
		var kind := s.data.projectile
		var mmi: MultiMeshInstance3D = _mm.get(kind)
		if mmi == null:
			continue
		var n: int = counts[kind]
		if n >= mmi.multimesh.instance_count:
			continue
		var p := s.pos + s.vel * frac
		var fwd := s.vel.normalized()
		var basis := Basis.looking_at(fwd, Vector3.UP if absf(fwd.y) < 0.98 else Vector3.RIGHT)
		mmi.multimesh.set_instance_transform(n, Transform3D(basis, p))
		counts[kind] = n + 1
	for kind in counts:
		_mm[kind].multimesh.visible_instance_count = counts[kind]
	_draw_tracers(shots, frac)


## One streak per carrot: from the carrot back along its path, never further
## back than the muzzle. Shotgun pellets get shorter, fainter streaks.
func _draw_tracers(shots: Array[Shot], frac: float) -> void:
	var tm := _tracers.multimesh
	var n := 0
	for s in shots:
		if n >= tm.instance_count:
			break
		var speed := s.vel.length()
		var length := minf(speed * TRACER_SECONDS, s.travelled + speed * frac)
		if length < 0.05:
			continue
		var back := -s.vel / speed
		var side := back.cross(Vector3.UP if absf(back.y) < 0.98 else Vector3.RIGHT).normalized()
		tm.set_instance_transform(n, Transform3D(Basis(side, back.cross(side), back * length), s.pos + s.vel * frac))
		var own := s.shooter is Critter and (s.shooter as Critter).is_player
		var col := own_tracer if own else TRACER_ENEMY
		if s.data.pellets > 1:
			col.a *= 0.55
		tm.set_instance_custom_data(n, col)
		n += 1
	tm.visible_instance_count = n


## The tracer colour for a Workshop look ("cream" is the stock one).
static func tracer_color(look: String) -> Color:
	return TRACER_OWN if look == "cream" else Color(Workshop.color(look), 0.6)


## Number of tracer streaks drawn last frame (tests).
func tracer_count() -> int:
	return _tracers.multimesh.visible_instance_count


## A flat strip, x = side (-1 / 1), z = 0 at the head to 1 at the tail; the
## tracer shader turns it to face the camera.
static func _tracer_strip() -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(-1, 0, 0), Vector3(1, 0, 0), Vector3(-1, 0, 1), Vector3(1, 0, 1)])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 1)])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 2, 1, 3])
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mat := ShaderMaterial.new()
	mat.shader = TRACER_SHADER
	m.surface_set_material(0, mat)
	return m


func _on_hit(s: Shot, hit: Dictionary) -> void:
	var col: Object = hit.collider
	var dir := s.vel.normalized()
	var dmg := s.data.damage_at(s.travelled) * s.damage_scale
	if col is Node and (col as Node).has_meta(&"critter"):
		var critter: Node = (col as Node).get_meta(&"critter")
		var role: StringName = (col as Node).get_meta(&"role", &"chest")
		if is_instance_valid(critter):
			if col is Area3D:
				critter.receive_shot(s.shooter, s.data, dmg, hit.position, dir, role)
			else:
				critter.receive_corpse_shot(s.data, hit.position, dir, col)
		if s.data.projectile == WeaponData.ProjectileKind.BOLT:
			_stick(hit.position, dir, col as Node3D, 0.5)
		return
	if col is RigidBody3D:
		(col as RigidBody3D).apply_impulse(dir * s.data.impulse * 0.5, hit.position - (col as RigidBody3D).global_position)
	var surface: StringName = (col as Node).get_meta(&"surface", &"dirt") if col is Node else &"dirt"
	FX.impact(hit.position, hit.normal, surface)
	Audio.play_at(&"carrot_impact_wood" if surface == &"wood" else &"carrot_impact_dirt", hit.position, -8.0)
	if s.data.projectile == WeaponData.ProjectileKind.BOLT and col is Node3D:
		_stick(hit.position, dir, col as Node3D, 0.35)


## Leave the carrot embedded where it hit, parented so it moves with the target.
func _stick(pos: Vector3, dir: Vector3, target: Node3D, depth_frac: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	var mi: MeshInstance3D
	_stuck = _stuck.filter(func(n): return is_instance_valid(n))
	if _stuck.size() >= MAX_STUCK:
		mi = _stuck.pop_front()
		mi.get_parent().remove_child(mi)
	else:
		mi = MeshInstance3D.new()
		mi.mesh = _bolt_mesh
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var parent: Node3D = target
	# hitboxes live on BoneAttachment3D nodes: parent to the attachment so the
	# carrot rides along with the limb, alive or ragdolled
	if target is Area3D and target.get_parent() is Node3D:
		parent = target.get_parent()
	parent.add_child(mi)
	var aabb := _bolt_mesh.get_aabb()
	var length := maxf(aabb.size.z, 0.05)
	var basis := Basis.looking_at(dir, Vector3.UP if absf(dir.y) < 0.98 else Vector3.RIGHT)
	basis = basis.rotated(dir, randf() * TAU)
	mi.global_transform = Transform3D(basis, pos + dir * length * depth_frac)
	_stuck.append(mi)
	if KillCam.recording and not KillCam.instance.playing:
		KillCam.instance.note_node(mi, "", false)


static func _fallback_carrot(length: float, radius: float) -> Mesh:
	# Fallback only (used until assets/weapons/carrot_bolt.glb exists).
	var m := CylinderMesh.new()
	m.top_radius = 0.0
	m.bottom_radius = radius
	m.height = length
	m.radial_segments = 8
	m.rings = 1
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.5, 0.1)
	mat.roughness = 0.6
	m.material = mat
	var am := ArrayMesh.new()
	var arrays := m.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	# cylinder is along +Y; point the tip down -Z
	var rot := Basis(Vector3.RIGHT, -PI / 2.0)
	for i in verts.size():
		verts[i] = rot * verts[i]
		normals[i] = rot * normals[i]
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TANGENT] = null
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	am.surface_set_material(0, mat)
	return am
