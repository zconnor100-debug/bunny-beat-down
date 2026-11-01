extends Node3D
## Stage for tests/perf_bench.gd. For each map: the drop view, then every
## landmark from critter height (looking at it, then out across the map),
## each measured over SAMPLES frames after a short settle.

const SAMPLES := 90
const QUICK_SAMPLES := 24
const SETTLE := 0.6
const MAPS := {"island": "Island", "cage": "HamsterCage", "toybox": "ToyBox"}

var out_path := "user://perf.json"
var maps: PackedStringArray = ["island", "cage", "toybox"]
var quality := 2
var lod_threshold := -1.0         ## pixels; below 0 = what the quality sets
var seed_value := 1234
## Also list what the triangles, draw calls and GPU time are, at the map's
## heaviest views, and what each screen effect costs there.
var breakdown := false
## Fewer frames per view and no views out to the side (for a slow GPU).
var quick := false
## A folder to save each view's picture in (<map>_<n>.png), to compare a
## change's before and after; "" for none.
var shots := ""
var cam: Camera3D


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var vp := get_viewport()
	RenderingServer.viewport_set_measure_render_time(vp.get_viewport_rid(), true)
	var report := {"quality": quality, "lod_threshold": lod_threshold, "size": [vp.size.x, vp.size.y], "maps": {}}
	for map in maps:
		report.maps[map] = await _bench(map)
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(report, "  "))
	f.close()
	print("PERF_DONE ", out_path)
	get_tree().quit()


func _bench(map: String) -> Dictionary:
	var light := WorldLighting.new()
	add_child(light)
	light.build(quality)
	if lod_threshold >= 0.0:
		get_viewport().mesh_lod_threshold = lod_threshold
	var fx := FX.new()
	add_child(fx)
	var proj := Projectiles.new()
	add_child(proj)
	cam = Camera3D.new()
	cam.far = 2500.0
	add_child(cam)
	cam.current = true
	var island: Island = _make(MAPS[map])
	add_child(island)
	await island.generate(seed_value, quality, false)
	island.tune_lighting(light)
	var views := []
	var mid := Vector2.ZERO
	views.append(["drop", Vector3(mid.x - 60.0, island.terrain.height_at(mid.x, mid.y) + Dropship.ALTITUDE, mid.y + 140.0),
		Vector3(mid.x, island.terrain.height_at(mid.x, mid.y), mid.y - 60.0)])
	for p in island.pois:
		var c: Vector2 = p.center
		var out := (c - mid).normalized() if c.length() > 1.0 else Vector2(0, 1)
		var at := c + out * (float(p.radius) + 25.0)
		var eye := Vector3(at.x, island.terrain.height_at(at.x, at.y) + 3.0, at.y)
		views.append([p.name, eye, Vector3(c.x, island.terrain.height_at(c.x, c.y) + 3.0, c.y)])
		if not quick:
			var side := Vector2(-out.y, out.x) * 200.0
			views.append([p.name + " (side)", eye, Vector3(at.x + side.x, eye.y, at.y + side.y)])
	var rows := []
	for v in views:
		_look(island, v[1], v[2])
		rows.append(await _measure(v[0]))
		if shots != "":
			get_viewport().get_texture().get_image().save_png(shots.path_join("%s_%02d.png" % [map, rows.size() - 1]))
	var sum := {"view": "mean"}
	for k in rows[0]:
		if k != "view":
			sum[k] = snappedf(rows.map(func(r): return float(r[k])).reduce(func(a, b): return a + b) / rows.size(), 0.01)
	var worst := {"view": "worst"}
	for k in rows[0]:
		if k != "view":
			worst[k] = rows.map(func(r): return float(r[k])).max()
	_print(map, rows, sum, worst)
	var parts := {}
	if breakdown:
		var order := range(rows.size())
		order.sort_custom(func(a, b): return rows[a].tris + rows[a].shadow_tris > rows[b].tris + rows[b].shadow_tris)
		var heaviest := order.slice(0, 2)
		order.sort_custom(func(a, b): return rows[a].draws + rows[a].shadow_draws > rows[b].draws + rows[b].shadow_draws)
		for i in order.slice(0, 2):
			if i not in heaviest:
				heaviest.append(i)
		order.sort_custom(func(a, b): return rows[a].gpu_ms > rows[b].gpu_ms)
		for i in order.slice(0, 2):
			if i not in heaviest:
				heaviest.append(i)
		for i in heaviest:
			_look(island, views[i][1], views[i][2])
			parts[views[i][0]] = await _breakdown(island, views[i][0])
			parts[views[i][0] + " (effects)"] = await _effects(light, views[i][0])
	for n in [island, cam, light, fx, proj]:
		n.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	return {"views": rows, "mean": sum, "worst": worst, "breakdown": parts}


func _make(cls: String) -> Island:
	return {"Island": Island, "HamsterCage": HamsterCage, "ToyBox": ToyBox}[cls].new()


func _look(island: Island, from: Vector3, at: Vector3) -> void:
	cam.fov = 75.0
	cam.global_position = from
	cam.look_at(at, Vector3.UP)
	island.set_player_position(from)


func _measure(view: String) -> Dictionary:
	var vp := get_viewport()
	var rid := vp.get_viewport_rid()
	var t := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t < SETTLE * 1000.0:
		await get_tree().process_frame
	var gpu := []
	var cpu := []
	for i in (QUICK_SAMPLES if quick else SAMPLES):
		await get_tree().process_frame
		gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(rid))
		cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(rid))
	gpu.sort()
	cpu.sort()
	return {
		"view": view,
		"gpu_ms": snappedf(gpu[gpu.size() / 2], 0.01),
		"cpu_ms": snappedf(cpu[cpu.size() / 2], 0.01),
		"tris": vp.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME),
		"shadow_tris": vp.get_render_info(Viewport.RENDER_INFO_TYPE_SHADOW, Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME),
		"draws": vp.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME),
		"shadow_draws": vp.get_render_info(Viewport.RENDER_INFO_TYPE_SHADOW, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME),
		"objects": vp.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_OBJECTS_IN_FRAME),
	}


## Triangles and draw calls each kind of thing adds at this view (hidden in turn).
func _breakdown(island: Island, view: String) -> Array:
	var groups := {}
	var names := {}
	for k in island.scatter._foliage_mats:
		names[island.scatter._foliage_mats[k]] = k
	for e in island.scatter.entries:
		if e.has("_mesh"):
			names[e["_mesh"]] = e.get("id", "?")
	for gi in island.find_children("*", "GeometryInstance3D", true, false):
		if (gi as GeometryInstance3D).is_visible_in_tree():
			var key := _group_key(island, gi, names)
			if not groups.has(key):
				groups[key] = []
			groups[key].append(gi)
	await _frames(3)
	var base := _counts()
	var base_gpu := await _gpu_ms()
	var out := []
	for key in groups:
		for gi in groups[key]:
			gi.visible = false
		await _frames(3)
		var now := _counts()
		var gpu := await _gpu_ms()
		for gi in groups[key]:
			gi.visible = true
		out.append({"group": key, "count": groups[key].size(), "tris": base[0] - now[0], "shadow_tris": base[1] - now[1],
			"draws": base[2] - now[2], "shadow_draws": base[3] - now[3], "gpu_ms": snappedf(base_gpu - gpu, 0.01)})
	print("  -- %s: %d tris + %d shadow, %d draws + %d shadow, %.2f GPU ms" % [view, base[0], base[1], base[2], base[3], base_gpu])
	print("     %-40s %-5s %9s %9s %6s %6s %7s" % ["", "", "tris", "shadow", "draws", "sdraws", "gpu ms"])
	for by in ["tris", "draws", "gpu_ms"]:
		var sorted := out.duplicate()
		match by:
			"tris": sorted.sort_custom(func(a, b): return a.tris + a.shadow_tris > b.tris + b.shadow_tris)
			"draws": sorted.sort_custom(func(a, b): return a.draws + a.shadow_draws > b.draws + b.shadow_draws)
			_: sorted.sort_custom(func(a, b): return a.gpu_ms > b.gpu_ms)
		print("  -- %s by %s:" % [view, by])
		for r in sorted.slice(0, 20):
			print("     %-40s x%-4d %9d %9d %6d %6d %7.2f" % [String(r.group).left(40), r.count, r.tris, r.shadow_tris, r.draws, r.shadow_draws, r.gpu_ms])
	return out


## What each screen effect costs at this view (GPU ms saved with it off).
func _effects(light: WorldLighting, view: String) -> Array:
	var env := light.env
	var vp := get_viewport()
	var toggles := {
		"sun shadows": [func(): light.sun.shadow_enabled = false, func(): light.sun.shadow_enabled = true],
		"ssao": [func(): env.ssao_enabled = not env.ssao_enabled, func(): env.ssao_enabled = not env.ssao_enabled],
		"ssil": [func(): env.ssil_enabled = not env.ssil_enabled, func(): env.ssil_enabled = not env.ssil_enabled],
		"ssr": [func(): env.ssr_enabled = not env.ssr_enabled, func(): env.ssr_enabled = not env.ssr_enabled],
		"glow": [func(): env.glow_enabled = not env.glow_enabled, func(): env.glow_enabled = not env.glow_enabled],
		"fog": [func(): env.fog_enabled = not env.fog_enabled, func(): env.fog_enabled = not env.fog_enabled],
		"volumetric fog": [func(): env.volumetric_fog_enabled = not env.volumetric_fog_enabled, func(): env.volumetric_fog_enabled = not env.volumetric_fog_enabled],
	}
	var was := {"msaa": vp.msaa_3d, "ssaa": vp.screen_space_aa, "taa": vp.use_taa, "scale": vp.scaling_3d_scale}
	toggles["msaa"] = [func(): vp.msaa_3d = Viewport.MSAA_DISABLED, func(): vp.msaa_3d = was.msaa]
	toggles["screen-space aa"] = [func(): vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED, func(): vp.screen_space_aa = was.ssaa]
	toggles["taa"] = [func(): vp.use_taa = false, func(): vp.use_taa = was.taa]
	toggles["render at 75%"] = [func(): vp.scaling_3d_scale = 0.75, func(): vp.scaling_3d_scale = was.scale]
	var on := {"ssao": env.ssao_enabled, "ssil": env.ssil_enabled, "ssr": env.ssr_enabled, "glow": env.glow_enabled, "fog": env.fog_enabled,
		"volumetric fog": env.volumetric_fog_enabled, "msaa": vp.msaa_3d != Viewport.MSAA_DISABLED,
		"screen-space aa": vp.screen_space_aa != Viewport.SCREEN_SPACE_AA_DISABLED, "taa": vp.use_taa, "sun shadows": light.sun.shadow_enabled,
		"render at 75%": true}
	await _frames(3)
	var base := await _gpu_ms()
	var out := []
	print("  -- %s effects (%.2f GPU ms):" % [view, base])
	for k in toggles:
		if not on[k]:
			continue
		toggles[k][0].call()
		await _frames(4)
		var gpu := await _gpu_ms()
		toggles[k][1].call()
		await _frames(2)
		out.append({"effect": k, "gpu_ms": snappedf(base - gpu, 0.01)})
		print("     %-24s %7.2f" % [k, base - gpu])
	return out


func _gpu_ms(n := 12) -> float:
	var rid := get_viewport().get_viewport_rid()
	var gpu := []
	for i in n:
		await get_tree().process_frame
		gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(rid))
	gpu.sort()
	return gpu[gpu.size() / 2]


func _counts() -> Array:
	var vp := get_viewport()
	return [vp.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME),
		vp.get_render_info(Viewport.RENDER_INFO_TYPE_SHADOW, Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME),
		vp.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME),
		vp.get_render_info(Viewport.RENDER_INFO_TYPE_SHADOW, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)]


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _group_key(island: Island, gi: Node, names: Dictionary) -> String:
	var n := gi
	var path := []
	while n.get_parent() != island and n.get_parent() != null:
		path.push_front(n)
		n = n.get_parent()
	var top := n
	if top is CageKit:
		return "kit:" + String(top.name).rstrip("0123456789_@")
	if top is Building:
		return "building:" + String(Building.Style.keys()[(top as Building).style]).to_lower()
	if top == island.scatter:
		if gi is MultiMeshInstance3D:
			var chunk := RegEx.create_from_string("_-?\\d+_-?\\d+$")
			return "cover:" + String(names.get((gi as MultiMeshInstance3D).multimesh.mesh, chunk.sub(String(gi.name), "")))
		var inst: Node = path[0] if not path.is_empty() else gi
		return "scatter:" + (inst.scene_file_path.get_file().get_basename() if inst.scene_file_path != "" else String(inst.name).rstrip("0123456789_@"))
	var nm := String(top.name)
	var cut := nm.length()
	while cut > 0 and (nm[cut - 1] in "0123456789_@"):
		cut -= 1
	return nm.left(cut) + ("/" + String(path[0].name).rstrip("0123456789_@") if path.size() > 1 else "")


func _print(map: String, rows: Array, sum: Dictionary, worst: Dictionary) -> void:
	print("== %s (quality %d, lod threshold %.1f)" % [map, quality, get_viewport().mesh_lod_threshold])
	print("  %-28s %7s %7s %9s %9s %6s %6s %6s" % ["view", "gpu ms", "cpu ms", "tris", "shadow", "draws", "sdraws", "objs"])
	for r in rows + [sum, worst]:
		print("  %-28s %7.2f %7.2f %9d %9d %6d %6d %6d" % [String(r.view).left(28), r.gpu_ms, r.cpu_ms, r.tris, r.shadow_tris,
			r.draws, r.shadow_draws, r.objects])
