extends SceneTree
## Bakes the convex collision of every model in assets/env/manifest.json with
## "collision": "convex" into assets/env/hulls.json, so an island doesn't
## decompose them all again each time it loads (Scatter._shape_for: two
## seconds of the island's load). Run it after adding or changing one:
##   godot4 --headless --path . -s tools/env/bake_hulls.gd
## A model missing from it (or changed since: tests/test_island.gd says so)
## is decomposed as the island loads, as before.

const OUT := "res://assets/env/hulls.json"


func _initialize() -> void:
	_bake.call_deferred()


func _bake() -> void:
	var sc := Scatter.new()
	root.add_child(sc)
	sc.load_manifest()
	var out := {}
	for e in sc.entries:
		if e.get("collision", "none") != "convex":
			continue
		var mesh := sc._merged_mesh(e["res"])
		if mesh == null:
			push_warning("no mesh in %s" % e["res"])
			continue
		var flat := []
		for p in mesh.create_convex_shape(true, true).points:   # (as Scatter._shape_for would)
			flat.append_array([snappedf(p.x, 0.00001), snappedf(p.y, 0.00001), snappedf(p.z, 0.00001)])
		out[e["id"]] = {"faces": mesh.get_faces().size(), "points": flat}
		print("%-24s %3d points" % [e["id"], flat.size() / 3])
	var keys := out.keys()
	keys.sort()
	var lines := []
	for k in keys:
		lines.append("  %s: %s" % [JSON.stringify(k), JSON.stringify(out[k])])
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	f.store_string("{\n" + ",\n".join(lines) + "\n}\n")
	f.close()
	print("%d hulls -> %s" % [keys.size(), OUT])
	quit()
