extends SceneTree
## Triangles and LOD levels of every map model (the LOD pass's starting point).
##   godot --headless --path . -s tests/model_census.gd [-- dir|file.glb]
## A file lists each surface: material, triangles, and each LOD's triangles.


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	if not a.is_empty() and a[0].ends_with(".glb"):
		for s in _surfaces(a[0]):
			print("  %-26s %7d tris  lods %s" % [s.name, s.tris, s.lods])
		quit()
		return
	var dirs := ["res://assets/maps/island", "res://assets/maps/cage", "res://assets/maps/toy"] if a.is_empty() else [a[0]]
	var rows := []
	for d in dirs:
		for f in DirAccess.get_files_at(d):
			if f.ends_with(".glb"):
				rows.append(_census(d.path_join(f)))
	rows.sort_custom(func(x, y): return x[1] > y[1])
	for r in rows:
		print("%-34s %8d tris  farthest LOD %7d tris (%3d%%)  %d surfaces barely reduced" % [r[0], r[1], r[3], r[4], r[5]])
	quit()


func _surfaces(path: String) -> Array:
	var root: Node = (load(path) as PackedScene).instantiate()
	var out := []
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var mesh := (mi as MeshInstance3D).mesh as ArrayMesh
		var data: Array = mesh.get("_surfaces")
		for i in data.size():
			var s: Dictionary = data[i]
			var wide: bool = s.get("vertex_count", 0) > 65535
			var tris: int = (s.get("index_data", PackedByteArray()) as PackedByteArray).size() / (4 if wide else 2) / 3
			var lods := []
			var l: Array = s.get("lods", [])
			for j in range(1, l.size(), 2):
				lods.append((l[j] as PackedByteArray).size() / (4 if wide else 2) / 3)
			var m := mesh.surface_get_material(i)
			out.append({"name": m.resource_name if m else "?", "tris": tris, "lods": lods})
	root.free()
	return out


func _census(path: String) -> Array:
	var tris := 0
	var far := 0
	var stuck := 0
	for s in _surfaces(path):
		tris += s.tris
		far += s.lods.back() if not s.lods.is_empty() else s.tris
		if s.lods.is_empty() or s.lods.back() > s.tris / 2:
			stuck += 1
	return [path.trim_prefix("res://assets/maps/"), tris, 0, far, 100 * far / maxi(tris, 1), stuck]
