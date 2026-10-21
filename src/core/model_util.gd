class_name ModelUtil
## Helpers for working with imported glTF scenes.

static var _scene_cache: Dictionary = {}


## Cached PackedScene load; null (with no error spam) if the file is missing.
static func scene(path: String) -> PackedScene:
	if path.is_empty():
		return null
	if not _scene_cache.has(path):
		_scene_cache[path] = load(path) if ResourceLoader.exists(path) else null
	return _scene_cache[path]


static func instantiate(path: String) -> Node3D:
	var ps := scene(path)
	return ps.instantiate() as Node3D if ps else null


## First Mesh found in a scene file (for MultiMesh / stuck-carrot rendering).
static func first_mesh(path: String) -> Mesh:
	var key := "mesh:" + path
	if _scene_cache.has(key):
		return _scene_cache[key]
	var mesh: Mesh = null
	var root := instantiate(path)
	if root:
		var mi := find_first(root, "MeshInstance3D") as MeshInstance3D
		if mi:
			mesh = mi.mesh
			# bake the node's local transform into a copy if it is not identity
			var xf := _relative_xform(root, mi)
			if not xf.is_equal_approx(Transform3D.IDENTITY):
				mesh = _transformed_copy(mesh, xf)
		root.free()
	_scene_cache[key] = mesh
	return mesh


static func find_first(node: Node, type_name: String) -> Node:
	if node.is_class(type_name):
		return node
	for c in node.get_children():
		var f := find_first(c, type_name)
		if f:
			return f
	return null


static func find_all(node: Node, type_name: String, out: Array = []) -> Array:
	if node.is_class(type_name):
		out.append(node)
	for c in node.get_children():
		find_all(c, type_name, out)
	return out


## Named marker (empty) inside an imported model, e.g. "Muzzle".
static func find_named(node: Node, marker: String) -> Node3D:
	if node.name == marker:
		return node as Node3D
	for c in node.get_children():
		var f := find_named(c, marker)
		if f:
			return f
	return null


static func aabb_of(root: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mi in find_all(root, "VisualInstance3D"):
		var vi := mi as VisualInstance3D
		var b: AABB = _relative_xform(root, vi) * vi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


static func _relative_xform(root: Node3D, node: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var n: Node = node
	while n and n != root:
		if n is Node3D:
			xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf


static func _transformed_copy(mesh: Mesh, xf: Transform3D) -> Mesh:
	var out := ArrayMesh.new()
	for s in mesh.get_surface_count():
		var st := SurfaceTool.new()
		st.create_from(mesh, s)
		var arrays := st.commit_to_arrays()
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for i in verts.size():
			verts[i] = xf * verts[i]
		arrays[Mesh.ARRAY_VERTEX] = verts
		if arrays[Mesh.ARRAY_NORMAL] != null:
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			for i in normals.size():
				normals[i] = (xf.basis * normals[i]).normalized()
			arrays[Mesh.ARRAY_NORMAL] = normals
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		out.surface_set_material(out.get_surface_count() - 1, mesh.surface_get_material(s))
	return out
