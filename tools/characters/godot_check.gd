extends SceneTree
# Bunny Beat Down — Godot-side check of the character GLBs (run by godot_check.sh
# inside a THROWAWAY project; never point Godot at the real project for this).
# Loads every chars/<id>/<id>.glb, finds its Skeleton3D and checks that each
# bone named in <id>.rig.json exists; prints bone count, triangles, AABB,
# animation clips and the bone-axis convention (median dot product between a
# bone's rest +Y and the direction to its first child; 1.0 = +Y along bones).

func ids() -> Array:
	var out := []
	for d in DirAccess.get_directories_at("res://chars"):
		if FileAccess.file_exists("res://chars/%s/%s.glb" % [d, d]):
			out.append(d)
	return out

func find_type(n: Node, cls: String) -> Array:
	var out := []
	if n.is_class(cls):
		out.append(n)
	for c in n.get_children():
		out += find_type(c, cls)
	return out

func rel_xform(n: Node3D, top: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	while n != null and n != top:
		t = n.transform * t
		n = n.get_parent() as Node3D
	return t

func _initialize() -> void:
	var all_ok := true
	for id in ids():
		var ps: PackedScene = load("res://chars/%s/%s.glb" % [id, id])
		if ps == null:
			print("FAIL %s: cannot load" % id); all_ok = false; continue
		var root: Node3D = ps.instantiate()
		get_root().add_child(root)
		var skels := find_type(root, "Skeleton3D")
		if skels.size() != 1:
			print("FAIL %s: %d skeletons" % [id, skels.size()]); all_ok = false; continue
		var sk: Skeleton3D = skels[0]
		var rig = JSON.parse_string(FileAccess.get_file_as_string("res://chars/%s/%s.rig.json" % [id, id]))
		var missing := []
		var names := []
		for role in rig["bones"]:
			if rig["bones"][role] != null:
				names.append(rig["bones"][role])
		for ch in rig["chains"]:
			names += rig["chains"][ch]
		for n in names:
			if sk.find_bone(n) < 0:
				missing.append(n)
		var aabb := AABB()
		var first := true
		var meshes := find_type(root, "MeshInstance3D")
		var tris := 0
		for mi in meshes:
			var b: AABB = rel_xform(mi, root) * mi.get_aabb()
			aabb = b if first else aabb.merge(b)
			first = false
			for s in mi.mesh.get_surface_count():
				var arr = mi.mesh.surface_get_arrays(s)
				tris += (arr[Mesh.ARRAY_INDEX].size() / 3) if arr[Mesh.ARRAY_INDEX] != null else 0
		var clips := []
		for ap in find_type(root, "AnimationPlayer"):
			clips += Array(ap.get_animation_list())
		# bone axis convention: rest +Y vs direction to first child, averaged over bones with children
		var dots := []
		for i in sk.get_bone_count():
			var kids := sk.get_bone_children(i)
			if kids.size() == 0:
				continue
			var gp := sk.get_bone_global_rest(i)
			var cp := sk.get_bone_global_rest(kids[0])
			var d := cp.origin - gp.origin
			if d.length() > 0.001:
				dots.append(gp.basis.y.normalized().dot(d.normalized()))
		dots.sort()
		var hips := sk.find_bone(rig["bones"]["hips"])
		var lu := sk.get_bone_global_rest(sk.find_bone(rig["bones"]["l_upper_arm"])).origin
		var ok := missing.is_empty()
		all_ok = all_ok and ok
		print("%s %s: bones=%d roles+chains=%d missing=%s tris=%d aabb_min=%s aabb_size=%s clips=%s mesh_instances=%d axisY_dot(median)=%.2f hips_parent=%d l_upper_arm_x=%.3f" % [
			"OK  " if ok else "FAIL", id, sk.get_bone_count(), names.size(), str(missing), tris,
			str(aabb.position.snapped(Vector3.ONE * 0.001)), str(aabb.size.snapped(Vector3.ONE * 0.001)), str(clips), meshes.size(),
			dots[dots.size() / 2] if dots.size() > 0 else 0.0, sk.get_bone_parent(hips), lu.x])
		root.queue_free()
	print("ALL_OK" if all_ok else "SOME_FAILED")
	quit()
