class_name Habitrail
extends RefCounted
## Tube Town's pods and tubes (HamsterCage.habitrail) as the House's ferret
## finds them (FerretBoss). Going by under the bedding beneath them she sets
## them rattling: they jump on their connectors and clatter, so you hear her
## coming. Coming up under one she knocks it clean off its connectors: from
## then it's a body of its own (ToyBlock.Loose) that goes tumbling, and comes
## down hard on whoever's under it. Each piece is a Dictionary: {kit (the
## CageKit), kind (&"pod", &"tube", or &"burrow": a hamster's cardboard roll,
## that only rattles), a, b (a tube's ends; a pod's or a roll's middle, both),
## r (how far its sides are from that line), loose}.

const DENSITY := 0.12          ## kg per cubic metre of its walls (ToyBlock's: light, hollow plastic)
const SHAKE := 0.45            ## metres it jumps about, rattling its hardest
const CRITTERS_AFTER := 0.35   ## seconds after it's knocked loose before it can land on anyone
const CRUSH_MOST := 45.0       ## the most it hurts coming down on you (flying plastic, not a falling brick)


static func piece(kit: Node3D, kind: StringName, a: Vector3, b: Vector3, r: float) -> Dictionary:
	return {"kit": kit, "kind": kind, "a": a, "b": b, "r": r, "loose": false}


## How far `p` is from a piece's sides, flat on the bedding (0 inside it).
static func distance(pc: Dictionary, p: Vector3) -> float:
	var a := Vector2(pc.a.x, pc.a.z)
	var b := Vector2(pc.b.x, pc.b.z)
	var q := Geometry2D.get_closest_point_to_segment(Vector2(p.x, p.z), a, b)
	return maxf(0.0, q.distance_to(Vector2(p.x, p.z)) - float(pc.r))


## The pieces still standing (and still there) within `reach` of `p`.
static func near(pieces: Array, p: Vector3, reach: float) -> Array:
	return pieces.filter(func(pc): return not pc.loose and is_instance_valid(pc.kit) and distance(pc, p) <= reach)


## Its middle (the bedding under it).
static func middle(pc: Dictionary) -> Vector3:
	return (pc.a + pc.b) * 0.5


## Rattles it for a moment, `k` hard (0..1): what you see of it jumping about
## on its connectors (its walls stay put, so nobody inside is shoved), and a
## clatter of plastic.
static func rattle(pc: Dictionary, k: float) -> void:
	var kit: Node3D = pc.kit
	if pc.loose or not is_instance_valid(kit) or not kit.is_inside_tree():
		return
	var looks := kit.get_children().filter(func(c): return c is Node3D and not c is CollisionShape3D)
	for v in looks:
		if not v.has_meta(&"rest"):
			v.set_meta(&"rest", v.transform)
	var old: Tween = kit.get_meta(&"rattle") if kit.has_meta(&"rattle") else null
	if old and old.is_valid():
		old.kill()
	var tw := kit.create_tween()
	kit.set_meta(&"rattle", tw)
	var steps := 9
	for i in steps:
		var amp := SHAKE * k * (1.0 - float(i) / steps)
		var off := Vector3(randf_range(-1, 1), randf_range(0.2, 1.0), randf_range(-1, 1)) * amp
		var tilt := Vector3(randf_range(-1, 1), randf_range(-0.4, 0.4), randf_range(-1, 1)) * amp * 0.03
		tw.tween_callback(func(): _pose(looks, Transform3D(Basis.from_euler(tilt), off)))
		tw.tween_interval(0.045)
	tw.tween_callback(func(): _pose(looks, Transform3D.IDENTITY))
	pc["rattled"] = int(pc.get("rattled", 0)) + 1
	Audio.play_at(&"tube_rattle", middle(pc) + Vector3.UP * 3.0, -6.0 + 6.0 * k, 0.12, {"max_distance": 320.0, "unit_size": 22.0})


static func _pose(looks: Array, by: Transform3D) -> void:
	for v in looks:
		if is_instance_valid(v):
			(v as Node3D).transform = (v.get_meta(&"rest") as Transform3D) * by


## Knocked clean off its connectors by something coming up under it at
## `from`: a body of its own from here on (its walls and all you see of it),
## flung up and away from `from` at `speed`, tumbling. A burrow's roll stays
## put. Returns the body (null if it was loose already).
static func loosen(pc: Dictionary, from: Vector3, speed: float) -> RigidBody3D:
	var kit: Node3D = pc.kit
	if pc.loose or pc.kind == &"burrow" or not is_instance_valid(kit) or not kit.is_inside_tree():
		return null
	pc.loose = true
	var old: Tween = kit.get_meta(&"rattle") if kit.has_meta(&"rattle") else null
	if old and old.is_valid():
		old.kill()
	var body := ToyBlock.Loose.new()
	body.name = "Loose" + kit.name
	body.what = &"habitrail"
	body.most = CRUSH_MOST
	body.reach = (pc.b - pc.a).length() * 0.5 + float(pc.r)
	body.collision_layer = Layers.WORLD | Layers.DEBRIS
	body.collision_mask = Layers.WORLD | Layers.DEBRIS   # (critters too once it's clear of whoever was inside: CRITTERS_AFTER)
	body.physics_material_override = ToyBlock._bouncy()
	body.contact_monitor = true
	body.max_contacts_reported = 4
	body.set_meta(&"surface", kit.get_meta(&"surface", &"wood"))
	kit.get_parent().add_child(body)
	body.global_transform = kit.global_transform.translated(Vector3.UP * 0.6)   # (its bottom's sunk in the bedding: clear of it, or the floor shoves it off like a shot)
	var walls := 0.0
	for c in kit.get_children():
		var cs := c as CollisionShape3D
		if cs:
			if cs.shape is ConcavePolygonShape3D:   # (a pod's dome: a body of its own needs it convex)
				var hull := ConvexPolygonShape3D.new()
				hull.points = (cs.shape as ConcavePolygonShape3D).get_faces()
				cs.shape = hull
			elif cs.shape is BoxShape3D:
				var s := (cs.shape as BoxShape3D).size
				walls += s.x * s.y * s.z
		elif c is Node3D and c.has_meta(&"rest"):
			(c as Node3D).transform = c.get_meta(&"rest")
		c.reparent(body, false)
	body.mass = maxf(walls * DENSITY, 4.0)
	var away := middle(pc) - from
	away.y = 0.0
	away = away.normalized() if away.length() > 0.5 else Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()
	body.linear_velocity = (Vector3.UP * 0.85 + away * 0.5).normalized() * speed
	body.angular_velocity = away.cross(Vector3.UP) * -randf_range(1.5, 2.6) + Vector3.UP * randf_range(-1.0, 1.0)
	body.get_tree().create_timer(CRITTERS_AFTER, false).timeout.connect(func():
		if is_instance_valid(body):
			body.collision_mask |= Layers.CRITTERS)
	var isl := kit.get_parent() as Island
	if isl:
		isl.buildings.erase(kit)
	kit.queue_free()
	Audio.play_at(&"tube_clunk", middle(pc) + Vector3.UP * 4.0, 4.0, 0.08, {"max_distance": 600.0, "unit_size": 35.0})
	return body
