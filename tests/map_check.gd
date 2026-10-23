extends RefCounted
## Map sanity checks shared by tests and tests/diag_overlaps.gd: solid things
## generated inside each other, and loot spots buried in solids.


## Pairs of solid props (anything on the WORLD layer except the ground and the
## room around the map) that sink more than `min_depth` metres into each
## other: [{a, b, depth, at}], deepest first.
## With `within`, also parts of one toy that sink into each other (blocks in a
## block castle), by body instead of by toy.
static func overlaps(island: Island, min_depth := 0.35, within := false) -> Array:
	var space := island.get_world_3d().direct_space_state
	var bodies := _solids(island)
	var root_of := {}
	for b in bodies:
		root_of[b.get_rid()] = b if within else _root(island, b)
	var best := {}
	for body: CollisionObject3D in bodies:
		var mine: Node = root_of[body.get_rid()]
		for owner_id in body.get_shape_owners():
			for k in body.shape_owner_get_shape_count(owner_id):
				var shape := body.shape_owner_get_shape(owner_id, k)
				if shape is ConcavePolygonShape3D or shape is HeightMapShape3D or shape is WorldBoundaryShape3D:
					continue
				var q := PhysicsShapeQueryParameters3D.new()
				q.shape = shape
				q.transform = body.global_transform * body.shape_owner_get_transform(owner_id)
				q.collision_mask = Layers.WORLD
				q.exclude = [body.get_rid()]
				var hits := space.intersect_shape(q, 24)
				var others: Array[RID] = []
				for h in hits:
					others.append(h.rid)
				for h in hits:
					var theirs: Node = root_of.get(h.rid)
					if theirs == null or theirs == mine:
						continue   # the ground, the glass, or another part of the same toy
					# depth against this one body only: leave the rest out of the query
					var only: Array[RID] = [body.get_rid()]
					for r in others:
						if r != h.rid:
							only.append(r)
					q.exclude = only
					var pts := space.collide_shape(q, 16)
					q.exclude = [body.get_rid()]
					var depth := 0.0
					var at := Vector3.ZERO
					for i in range(0, pts.size() - 1, 2):
						var d := pts[i].distance_to(pts[i + 1])
						if d > depth:
							depth = d
							at = (pts[i] + pts[i + 1]) * 0.5
					if depth < min_depth:
						continue
					var key := _pair_key(mine, theirs)
					if not best.has(key) or float(best[key].depth) < depth:
						best[key] = {"a": _label(mine, island), "b": _label(theirs, island), "depth": depth, "at": at}
	var out := best.values()
	out.sort_custom(func(x, y): return x.depth > y.depth)
	return out


## Loot spots where a pickup would sit inside something solid: [{what, at}].
static func buried_loot(island: Island) -> Array:
	var space := island.get_world_3d().direct_space_state
	var solid := {}
	for b in _solids(island):
		solid[b.get_rid()] = b
	var probe := SphereShape3D.new()
	probe.radius = 0.3
	var out := []
	for l in island.loot_points:
		var q := PhysicsShapeQueryParameters3D.new()
		q.shape = probe
		q.transform = Transform3D(Basis(), (l.pos as Vector3) + Vector3.UP * 0.7)
		q.collision_mask = Layers.WORLD
		for h in space.intersect_shape(q, 8):
			if solid.has(h.rid):
				out.append({"what": "%s %s" % ["crate" if l.get("crate", false) else "loot", _label(solid[h.rid], island)], "at": l.pos})
				break
	return out


static func _solids(island: Island) -> Array:
	var out := []
	var stack: Array[Node] = [island]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n == island.terrain:
			continue
		if n is CollisionObject3D and not (n is Area3D) and ((n as CollisionObject3D).collision_layer & Layers.WORLD) != 0:
			if not _is_room(island, n):
				out.append(n)
		stack.append_array(n.get_children())
	return out


## The glass tank, the room round it, the walls: they hold everything else.
static func _is_room(island: Island, n: Node) -> bool:
	var r := _root(island, n)
	var nm := String(r.name).to_lower()
	return nm.contains("tank") or nm.contains("room") or nm.contains("wall") or nm.contains("glass") or nm.contains("boundary") \
		or nm.contains("floor") or nm.contains("shore") or nm.contains("fridge")


## The prop a collider belongs to: its ancestor that is a direct child of
## the island (or of the scatter).
static func _root(island: Island, n: Node) -> Node:
	var cur := n
	while cur.get_parent() != null and cur.get_parent() != island and cur.get_parent() != island.scatter:
		cur = cur.get_parent()
	return cur


static func _label(n: Node, island: Island) -> String:
	var r := _root(island, n)
	var p := (n as Node3D).global_position if n is Node3D else Vector3.ZERO
	var nm := String(r.name)
	if r.scene_file_path != "":
		nm = r.scene_file_path.get_file().get_basename()
	if r != n:
		nm += "/" + String(n.get_parent().name if n.name.begins_with("@") else n.name)
	return "%s@(%d,%d)" % [nm, roundi(p.x), roundi(p.z)]


static func _pair_key(a: Node, b: Node) -> String:
	var x := a.get_instance_id()
	var y := b.get_instance_id()
	return "%d-%d" % [mini(x, y), maxi(x, y)]
