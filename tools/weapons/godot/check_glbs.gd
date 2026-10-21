# Headless import check for the weapons & props glbs (run by godot_check.py).
# Loads every res://glb/*.glb, instantiates it and prints one JSON line per file:
# AABB, triangle count, marker node positions and material flags.
extends SceneTree

const MARKERS := ["Muzzle", "SupportGrip", "Sight", "Eject", "Trail", "Lid", "Chute", "Rocket",
	"EarHole_L", "EarHole_R", "Hand_L", "Hand_R", "Burner", "Exit"]


func rel_xform(n: Node, root: Node) -> Transform3D:
	# transform of n relative to the scene root (global transforms are not
	# resolved yet while SceneTree._init runs)
	var xf := Transform3D.IDENTITY
	var cur := n
	while cur != null and cur != root:
		if cur is Node3D:
			xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf


func _init() -> void:
	var dir := "res://glb/"
	var files := DirAccess.get_files_at(dir)
	files.sort()
	for f in files:
		if not f.ends_with(".glb"):
			continue
		var out := {"file": f}
		var ps: PackedScene = load(dir + f)
		if ps == null:
			out["error"] = "load failed"
			print("GLBCHECK " + JSON.stringify(out))
			continue
		var root: Node3D = ps.instantiate()
		var have := false
		var box := AABB()
		var tris := 0
		var mats := []
		for mi in root.find_children("*", "MeshInstance3D", true, false):
			var mesh: Mesh = mi.mesh
			if mesh == null:
				continue
			var a: AABB = rel_xform(mi, root) * mi.get_aabb()
			box = a if not have else box.merge(a)
			have = true
			tris += mesh.get_faces().size() / 3
			for s in mesh.get_surface_count():
				var m := mesh.surface_get_material(s)
				if m is StandardMaterial3D:
					var sm := m as StandardMaterial3D
					mats.append({"node": String(mi.name), "albedo_tex": sm.albedo_texture != null,
						"normal": sm.normal_enabled, "orm": sm.roughness_texture != null,
						"transparency": sm.transparency, "cull": sm.cull_mode})
		out["aabb_pos"] = [box.position.x, box.position.y, box.position.z]
		out["aabb_size"] = [box.size.x, box.size.y, box.size.z]
		out["tris"] = tris
		out["materials"] = mats
		var mk := {}
		for name in MARKERS:
			var n := root.find_child(name, true, false)
			if n != null and n is Node3D:
				var p: Vector3 = rel_xform(n, root).origin
				mk[name] = [snappedf(p.x, 0.0001), snappedf(p.y, 0.0001), snappedf(p.z, 0.0001)]
		out["markers"] = mk
		var kids := []
		for c in root.get_children():
			kids.append("%s:%s" % [c.name, c.get_class()])
		out["children"] = kids
		print("GLBCHECK " + JSON.stringify(out))
		root.free()
	quit()
