class_name Grenade
extends Node3D
## A carrot grenade: a stubby round carrot with a pin in it. Lobbed in an arc
## (Critter.throw_grenade), it bounces off the ground, walls and critters,
## rolls to a stop, blinks faster and faster, and goes off FUSE seconds after
## the throw: falloff damage and a big shove for everyone in the blast
## (Explosion, as a rocket's), so the ones it doesn't beat down get blown back.
## The Carrot Lobber fires these too (WeaponData.ProjectileKind.LOB): its
## own blast, a shorter fuse (WeaponData.fuse), and it goes off on a critter.

const DATA := "res://data/throwables/carrot_grenade.tres"
const FUSE := 2.4
const RADIUS := 0.1               ## how far its middle stays off what it lands on
const BOUNCE := 0.3               ## speed kept straight off a surface it hits
const SKID := 0.3                 ## speed kept along it, on a bounce (it digs in)
const ROLL_DRAG := 18.0           ## m/s² lost rolling along the ground
const SETTLE := 1.0               ## slower than this along the ground: it lies still

var thrower: Node
var weapon: WeaponInstance
var velocity := Vector3.ZERO
var exclude: Array[RID] = []
var fuse := FUSE
var _age := 0.0
var _gravity := 16.0
var _resting := false
var _done := false
var _model: Node3D
var _light: MeshInstance3D
var _spin := Vector3.ZERO
var _next_beep := 1.0


static func data() -> WeaponData:
	return load(DATA)


## Lob one from `pos` at `vel` (m/s); `thrower` gets the credit (and half the
## damage, standing in its own blast, like a rocket's). `gun`: the Carrot
## Lobber that fired it (its blast and fuse), or none for a thrown grenade.
static func spawn(parent: Node, thrower_: Node, pos: Vector3, vel: Vector3, exclude_: Array[RID] = [], gun: WeaponInstance = null) -> Grenade:
	var g := Grenade.new()
	g.thrower = thrower_
	g.weapon = gun if gun else WeaponInstance.new(data())
	if gun and gun.data.fuse > 0.0:
		g.fuse = gun.data.fuse
	g.velocity = vel
	g.exclude = exclude_
	parent.add_child(g)
	g.global_position = pos
	return g


## Where a lob from `from` at `vel` first comes down (or hits something):
## the arc's points, its last one where it lands. The aiming arc shows this.
static func arc(space: PhysicsDirectSpaceState3D, from: Vector3, vel: Vector3, exclude_: Array[RID] = [], step := 0.03, most := 3.0) -> PackedVector3Array:
	var g := data().projectile_gravity * float(ProjectSettings.get_setting("physics/3d/default_gravity", 16.0))
	var pts := PackedVector3Array([from])
	var p := from
	var v := vel
	var t := 0.0
	while t < most:
		v.y -= g * step
		var to := p + v * step
		var q := PhysicsRayQueryParameters3D.create(p, to, Layers.SHOT_MASK | Layers.WATER)
		q.collide_with_areas = true
		q.exclude = exclude_
		var hit := space.intersect_ray(q)
		if hit:
			pts.append(hit.position)
			return pts
		p = to
		pts.append(p)
		t += step
	return pts


## The grenade itself: a round orange carrot, ridged, with a green leafy top,
## a steel pin ring through it and a little red light that blinks on the fuse.
static func make_model() -> Node3D:
	var root := Node3D.new()
	var orange := StandardMaterial3D.new()
	orange.albedo_color = Color(0.95, 0.47, 0.1)
	orange.roughness = 0.6
	var ridge := StandardMaterial3D.new()
	ridge.albedo_color = Color(0.72, 0.3, 0.06)
	ridge.roughness = 0.7
	var leaf := StandardMaterial3D.new()
	leaf.albedo_color = Color(0.3, 0.68, 0.22)
	leaf.roughness = 0.8
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.7, 0.72, 0.75)
	steel.metallic = 0.9
	steel.roughness = 0.3
	var body := MeshInstance3D.new()
	var ball := SphereMesh.new()
	ball.radius = 0.09
	ball.height = 0.2
	ball.material = orange
	body.mesh = ball
	root.add_child(body)
	for y in [-0.035, 0.0, 0.035]:
		var ring := MeshInstance3D.new()
		var tm := TorusMesh.new()
		var r := sqrt(maxf(0.0, 1.0 - pow(y / 0.1, 2.0))) * 0.09
		tm.inner_radius = r - 0.004
		tm.outer_radius = r + 0.004
		tm.rings = 24
		tm.material = ridge
		ring.mesh = tm
		ring.position.y = y
		root.add_child(ring)
	for i in 4:
		var l := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.0
		cm.bottom_radius = 0.014
		cm.height = 0.1
		cm.radial_segments = 6
		cm.material = leaf
		l.mesh = cm
		var a := TAU * i / 4.0 + 0.4
		l.rotation = Vector3(0.45 * cos(a), 0.0, 0.45 * sin(a))
		l.position = Vector3(sin(a) * 0.012, 0.13, -cos(a) * 0.012)
		root.add_child(l)
	var pin := MeshInstance3D.new()
	var pm := TorusMesh.new()
	pm.inner_radius = 0.022
	pm.outer_radius = 0.03
	pm.material = steel
	pin.mesh = pm
	pin.rotation = Vector3(0.0, 0.0, PI / 2.0)
	pin.position = Vector3(0.06, 0.08, 0.0)
	root.add_child(pin)
	var light := MeshInstance3D.new()
	light.name = "Light"
	var lm := SphereMesh.new()
	lm.radius = 0.016
	lm.height = 0.032
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color(1.0, 0.15, 0.1)
	glow.emission_enabled = true
	glow.emission = Color(1.0, 0.1, 0.05)
	glow.emission_energy_multiplier = 3.0
	lm.material = glow
	light.mesh = lm
	light.position = Vector3(0.0, 0.095, 0.03)
	root.add_child(light)
	return root


func _ready() -> void:
	add_to_group(&"grenades")
	_gravity = weapon.data.projectile_gravity * float(ProjectSettings.get_setting("physics/3d/default_gravity", 16.0))
	_model = make_model()
	add_child(_model)
	_light = _model.get_node("Light")
	_spin = Vector3(randf_range(-9.0, 9.0), randf_range(-4.0, 4.0), randf_range(-9.0, 9.0))


func _physics_process(delta: float) -> void:
	if _done:
		return
	_age += delta
	if _age >= fuse:
		_detonate()
		return
	# the light blinks faster as the fuse runs down, and beeps for the last second
	var left := fuse - _age
	_light.visible = fmod(_age, lerpf(0.08, 0.4, left / fuse)) < 0.05 or left < 0.15
	if left < _next_beep:
		_next_beep -= 0.33
		Audio.play_at(&"match_countdown_beep", global_position, -10.0, 0.0, {"unit_size": 3.0})
	if _resting:
		return
	velocity.y -= _gravity * delta
	var from := global_position
	var to := from + velocity * delta
	var q := PhysicsRayQueryParameters3D.create(from, to + velocity.normalized() * RADIUS, Layers.SHOT_MASK)
	q.collide_with_areas = true
	q.exclude = exclude
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit:
		var n: Vector3 = hit.normal
		if n == Vector3.ZERO:
			n = -velocity.normalized()   # (a critter's hitbox: back the way it came)
		var into := velocity.dot(n)
		var along := velocity - n * into
		global_position = hit.position + n * RADIUS
		if hit.collider is Area3D and (hit.collider as Node).has_meta(&"critter") and weapon.data.projectile == WeaponData.ProjectileKind.LOB:
			_detonate()   # (a Lobber's carrot goes off on whoever it hits)
			return
		if hit.collider is Area3D and (hit.collider as Node).has_meta(&"critter"):
			# a critter's soft: it thuds off them and drops at their feet
			velocity = velocity * 0.12 + n * 1.0
			Audio.play_at(&"carrot_impact_flesh", global_position, -8.0, 0.15)
			_spin *= 0.3
		elif into < -2.0:
			# a bounce
			velocity = along * SKID - n * into * BOUNCE
			Audio.play_at(&"carrot_impact_dirt", global_position, clampf(-14.0 - into, -14.0, -4.0), 0.15)
			_spin *= 0.6
		else:
			# rolling (or sliding) along it
			velocity = along.move_toward(Vector3.ZERO, ROLL_DRAG * delta)
			if n.y > 0.6 and velocity.length() < SETTLE:
				velocity = Vector3.ZERO
				_resting = true
	else:
		global_position = to
	_model.rotation += _spin * delta * clampf(velocity.length() / 6.0, 0.0, 1.0)


func _detonate() -> void:
	_done = true
	Explosion.detonate(get_tree(), global_position + Vector3.UP * 0.15, weapon, thrower)
	queue_free()
