class_name Projectiles
extends Node3D
## Every carrot in flight. Bolts and pellets are plain data stepped with a
## ray per physics tick (so fast carrots never tunnel) and drawn with one
## MultiMesh per kind; rockets are real nodes (see Rocket).
## Carrots that hit something stay stuck in it — trees, crates, and critters.

const MAX_STUCK := 220
const MAX_LIFE := 3.0

const BOLT_MODEL := "res://assets/weapons/carrot_bolt.glb"
const PELLET_MODEL := "res://assets/weapons/carrot_shell_pellet.glb"

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


## Fire one trigger pull: spawns `pellets` projectiles inside the spread cone.
static func fire(shooter: Node, weapon: WeaponInstance, origin: Vector3, dir: Vector3, spread_deg: float, exclude: Array[RID]) -> void:
	if instance == null:
		return
	var data := weapon.data
	for i in data.pellets:
		var d := _spread_dir(dir, spread_deg)
		if data.projectile == WeaponData.ProjectileKind.ROCKET:
			var r := Rocket.new()
			r.setup(shooter, weapon, d, exclude)
			instance.add_child(r)
			r.global_position = origin
			continue
		var s := Shot.new()
		s.pos = origin
		s.vel = d * data.projectile_speed
		s.gravity = data.projectile_gravity * ProjectSettings.get_setting("physics/3d/default_gravity", 16.0)
		s.data = data
		s.damage_scale = weapon.damage_scale()
		s.shooter = shooter
		s.exclude = exclude
		instance._shots.append(s)


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
			_on_hit(s, hit)
			_shots.remove_at(i)
			continue
		s.travelled += s.pos.distance_to(next)
		s.pos = next
		s.life += delta
		if s.life > MAX_LIFE or s.pos.y < -50.0:
			_shots.remove_at(i)
			continue
		i += 1


func _process(_delta: float) -> void:
	# draw: extrapolate by the physics interpolation fraction for smooth motion
	var frac := Engine.get_physics_interpolation_fraction() / float(Engine.physics_ticks_per_second)
	var counts := {WeaponData.ProjectileKind.BOLT: 0, WeaponData.ProjectileKind.PELLET: 0}
	for s in _shots:
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
