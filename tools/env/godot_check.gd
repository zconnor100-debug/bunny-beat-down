extends SceneTree
## Headless import check for the environment kit (Godot 4.x).
##
## Run in a THROWAWAY project that contains a copy of assets/ (see godot_check.sh):
##   godot4 --headless --path /tmp/bbd-envcheck --import
##   godot4 --headless --path /tmp/bbd-envcheck -s res://godot_check.gd
## Loads every GLB listed in assets/env/manifest.json, measures its AABB and
## compares it with the manifest (height, ground contact, footprint), counts
## alpha-scissor materials, and loads every terrain texture and sky HDRI.
## Exit code = number of problems.

const TOL := 0.03  # 3 % (plus 5 cm) tolerance on sizes


func _init() -> void:
	var problems := 0
	var text := FileAccess.get_file_as_string("res://assets/env/manifest.json")
	var manifest: Array = JSON.parse_string(text)
	print("id                        height(m) manifest  min_y   sink  radius  manifest  scissor/mats")
	for e in manifest:
		var path := "res://" + str(e["file"])
		var packed: PackedScene = load(path)
		if packed == null:
			print("FAIL could not load ", path)
			problems += 1
			continue
		var root := packed.instantiate()
		var info := {"aabb": AABB(), "has": false, "mats": 0, "scissor": 0}
		_walk(root, Transform3D.IDENTITY, info)
		var box: AABB = info["aabb"]
		var top := box.end.y
		var radius := maxf(maxf(absf(box.position.x), absf(box.end.x)), maxf(absf(box.position.z), absf(box.end.z)))
		var ok := absf(top - float(e["height_m"])) <= float(e["height_m"]) * TOL + 0.05
		ok = ok and absf(-box.position.y - float(e.get("sink_m", 0.0))) <= float(e["height_m"]) * TOL + 0.05
		# the footprint radius is measured from vertices, so it may be smaller than the AABB corner
		ok = ok and float(e["footprint_radius_m"]) <= radius * 1.42 + 0.05
		print("%-25s %8.2f %8.2f %7.2f %6.2f %7.2f %8.2f   %d/%d %s" % [
			e["id"], top, float(e["height_m"]), box.position.y, float(e.get("sink_m", 0.0)),
			radius, float(e["footprint_radius_m"]), info["scissor"], info["mats"], "" if ok else "  <-- MISMATCH"])
		if not ok:
			problems += 1
		root.free()
	for dir in ["res://assets/textures", "res://assets/sky"]:
		problems += _load_all(dir)
	print("problems: ", problems)
	quit(problems)


func _walk(node: Node, xf: Transform3D, info: Dictionary) -> void:
	var t := xf
	if node is Node3D:
		t = xf * (node as Node3D).transform
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		var b := t * mi.get_aabb()
		info["aabb"] = b if not info["has"] else (info["aabb"] as AABB).merge(b)
		info["has"] = true
		for s in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(s)
			info["mats"] += 1
			if m is BaseMaterial3D and (m as BaseMaterial3D).transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR:
				info["scissor"] += 1
	for c in node.get_children():
		_walk(c, t, info)


func _load_all(dir_path: String) -> int:
	var bad := 0
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return 0
	for sub in dir.get_directories():
		bad += _load_all(dir_path + "/" + sub)
	for f in dir.get_files():
		if f.ends_with(".import"):
			continue
		var res := load(dir_path + "/" + f)
		if res == null:
			print("FAIL could not load ", dir_path + "/" + f)
			bad += 1
		elif res is Texture2D:
			print("ok  %-55s %dx%d" % [(dir_path + "/" + f).trim_prefix("res://"), res.get_width(), res.get_height()])
	return bad
