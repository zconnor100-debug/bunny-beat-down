class_name Rocket
extends Node3D
## A rocket carrot: fast, trails smoke, and detonates on contact or after a
## few seconds. A critter hit square on takes the blast's full damage; everyone
## else within the splash radius takes less the further they are from it.

const MODEL := "res://assets/weapons/carrot_rocket.glb"
const LIFETIME := 4.0

var shooter: Node
var weapon: WeaponInstance
var velocity := Vector3.ZERO
var exclude: Array[RID] = []
var _age := 0.0
var _trail: GPUParticles3D
var _whoosh: Node
var _gravity := 0.0
var _done := false


func setup(shooter_: Node, weapon_: WeaponInstance, dir: Vector3, exclude_: Array[RID]) -> void:
	shooter = shooter_
	weapon = weapon_
	exclude = exclude_
	velocity = dir * weapon.data.projectile_speed
	_gravity = weapon.data.projectile_gravity * float(ProjectSettings.get_setting("physics/3d/default_gravity", 16.0))


func _ready() -> void:
	var model := ModelUtil.instantiate(MODEL)
	if model == null:
		model = MeshInstance3D.new()
		(model as MeshInstance3D).mesh = Projectiles._fallback_carrot(0.45, 0.06)
	add_child(model)
	_trail = FX.smoke_trail(self)
	if _trail:
		_trail.position = Vector3(0, 0, 0.25)
	_whoosh = Audio.make_loop(&"rocket_whoosh_loop", self)
	if _whoosh:
		_whoosh.play()
	_face()


func _physics_process(delta: float) -> void:
	if _done:
		return
	_age += delta
	var from := global_position
	velocity.y -= _gravity * delta
	var to := from + velocity * delta
	var q := PhysicsRayQueryParameters3D.create(from, to, Layers.SHOT_MASK | Layers.WATER)
	q.collide_with_areas = true
	q.exclude = exclude
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit:
		global_position = hit.position - velocity.normalized() * 0.15
		_detonate(_critter_hit(hit))
		return
	global_position = to
	_face()
	if _age > LIFETIME:
		_detonate()


func _face() -> void:
	if velocity.length_squared() > 0.01:
		var f := velocity.normalized()
		global_basis = Basis.looking_at(f, Vector3.UP if absf(f.y) < 0.98 else Vector3.RIGHT)


## The critter whose hitbox the rocket struck, if any.
func _critter_hit(hit: Dictionary) -> Critter:
	var col: Object = hit.collider
	if col is Area3D and (col as Node).has_meta(&"critter"):
		var critter := (col as Node).get_meta(&"critter") as Critter
		if critter and is_instance_valid(critter):
			return critter
	return null


func _detonate(direct: Critter = null) -> void:
	_done = true
	Explosion.detonate(get_tree(), global_position, weapon, shooter, direct)
	# let the smoke trail finish drifting instead of popping out of existence
	if _trail:
		_trail.emitting = false
		_trail.reparent(get_parent())
		Despawner.after(_trail, _trail.lifetime + 0.2, func(n: Node): n.queue_free())
	queue_free()
