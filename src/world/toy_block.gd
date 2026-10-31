class_name ToyBlock
extends StaticBody3D
## One piece of something built of toys that can come apart (Block Castle's
## letter blocks and its lintel, BlockPile): solid where it was put, part of
## the map (the navmesh is baked round it), until a blast knocks it loose
## (`loosen`). Then it's a body of its own that tumbles and bounces and stays
## where it ends up, and anything resting on it with nothing else under it
## comes loose too. Coming down hard on a critter, it hurts and bowls it over.

const DENSITY := 0.12          ## kg per cubic metre of toy (light: they're hollow wood and plastic)
const CRUSH_SPEED := 4.0       ## m/s it has to be going to hurt a critter
const CRUSH := 6.0             ## damage for each m/s over that

var size := Vector3.ONE * 4.0
var tips := false              ## a carrot's enough to tip it over (a domino: Projectiles)
var under: Array[ToyBlock] = []   ## what it rests on
var above: Array[ToyBlock] = []   ## what rests on it
var loose := false
var _shape: CollisionShape3D
var _visual: Node3D


func _init(size_: Vector3 = Vector3.ONE * 4.0) -> void:
	size = size_
	name = "ToyBlock"
	collision_layer = Layers.WORLD
	collision_mask = 0
	set_meta(&"surface", &"wood")
	_shape = CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	_shape.shape = box
	add_child(_shape)


## What it looks like (a letter block's model, a painted plank), its middle
## at this block's middle.
func dress(visual: Node3D) -> void:
	_visual = visual
	add_child(visual)


## Knocked loose: a body of its own from here on, given `impulse` at `at`
## (world). Whatever rested on it alone follows a moment later.
func loosen(impulse := Vector3.ZERO, at := Vector3.INF) -> RigidBody3D:
	if loose or not is_inside_tree():
		return null
	loose = true
	var body := Loose.new()
	body.name = "Loose" + name
	body.reach = size.length() * 0.5
	body.collision_layer = Layers.WORLD | Layers.DEBRIS
	body.collision_mask = Layers.WORLD | Layers.DEBRIS | Layers.CRITTERS
	body.mass = maxf(size.x * size.y * size.z * DENSITY, 0.5)
	body.physics_material_override = _bouncy()
	body.contact_monitor = true
	body.max_contacts_reported = 4
	body.set_meta(&"surface", &"wood")
	var parent := get_parent()
	parent.add_child(body)
	body.global_transform = global_transform
	_shape.reparent(body, false)
	if _visual:
		_visual.reparent(body, false)
	if impulse != Vector3.ZERO:
		body.apply_impulse(impulse, (at if at != Vector3.INF else global_position) - global_position)
	body.angular_velocity = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * impulse.length() * 0.02
	for b in under:
		b.above.erase(self)
	for b in above.duplicate():
		b.under.erase(self)
		if b.under.is_empty():
			b.loosen.call_deferred(Vector3.DOWN * b.size.length())   # (nothing under it now)
	above.clear()
	queue_free()
	return body


static var _bounce: PhysicsMaterial


static func _bouncy() -> PhysicsMaterial:
	if _bounce == null:
		_bounce = PhysicsMaterial.new()
		_bounce.bounce = 0.25
		_bounce.friction = 0.7
	return _bounce


## Blocks in `blocks` (all under one parent) resting on each other: B rests
## on A when B's bottom is at A's top and they overlap across (the castle's
## walls, its towers).
static func stack(blocks: Array[ToyBlock]) -> void:
	for a in blocks:
		for b in blocks:
			if a == b:
				continue
			var at := a.position
			var bt := b.position
			var gap := (bt.y - b.size.y * 0.5) - (at.y + a.size.y * 0.5)
			var across := Vector2(bt.x - at.x, bt.z - at.z).length()
			if absf(gap) < 0.3 and across < (a.size.x + b.size.x) * 0.5 * 0.95:
				b.under.append(a)
				a.above.append(b)


## A block knocked loose: what it does when it runs into things (another
## that tips, a domino, goes over too; coming down hard on a critter, it hurts
## and bowls it over). (Its own body: the block it came from is gone.)
class Loose extends RigidBody3D:
	var reach := 2.0               ## its middle to its far end (how fast that end's going counts too)
	var _hit := {}                 # critter -> msec it was last crushed by this
	var _was := Vector3.ZERO       # (how it was moving before what it ran into stopped it)
	var _spin := Vector3.ZERO

	func _ready() -> void:
		body_entered.connect(_bump)

	func _physics_process(_delta: float) -> void:
		_was = linear_velocity
		_spin = angular_velocity

	func _bump(other: Node) -> void:
		var speed := _was.length() + _spin.length() * reach
		var next := other as ToyBlock
		if next and next.tips and not next.loose and speed > 0.8:
			var top := next.global_position + Vector3.UP * next.size.y * 0.4
			var push := next.global_position - global_position
			push.y = 0.0
			next.loosen.call_deferred(push.normalized() * next.size.length() * 1.6, top)
			Audio.play_at(&"carrot_impact_wood", top, 0.0, 0.15)
			return
		var c := other as Critter
		if c == null or not c.alive:
			return
		var now := Time.get_ticks_msec()
		if speed < CRUSH_SPEED or now - int(_hit.get(c, -10000)) < 600:
			return
		_hit[c] = now
		var info := DamageInfo.make(CRUSH * (speed - CRUSH_SPEED) + 8.0, DamageInfo.Kind.MELEE, null, &"toy_blocks")
		info.position = c.get_chest_position()
		info.direction = _was.normalized() if _was.length() > 0.1 else Vector3.DOWN
		info.impulse = speed
		c.take_damage(info)
		if c.alive:
			c.knock_down(_was.limit_length(8.0))
		Audio.play_at(&"carrot_impact_wood", c.global_position, 2.0, 0.1)
