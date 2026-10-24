extends Node
## See tests/export_kits.gd. Each kit is built in CageKit.exporting mode: at
## its model's reference size, with accent slots left as slot names.

var only: Array = []


func _ready() -> void:
	_run.call_deferred()


static func _rng(s: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = s
	return r


## A seed whose first randf() is below 0.5 (or not): for builders that draw
## a coin flip first (a lookout's canopy).
static func _coin(heads: bool) -> int:
	for s in 1000:
		if (_rng(s).randf() < 0.5) == heads:
			return s
	return 0


func specs() -> Array:
	var out := [
		["cage/wheel", func(): return CageProps.wheel(_rng(1))],
		["cage/pod", func(): return CageProps.pod(_rng(1), &"teal", CageProps.TOWN_DOORS)],
		["cage/tube", func(): return CageProps.tube(_rng(1), &"teal", CageProps.TOWN_TUBE)],
		["cage/roll_9", func(): return CageProps.roll(_rng(1), 9.0, 2.7)],
		["cage/roll_24", func(): return CageProps.roll(_rng(1), 24.0, 2.7)],
		["cage/bowl", func(): return CageProps.bowl(_rng(1), &"pink", CageProps.BOWL_R, CageProps.BOWL_RIM)],
		["cage/seed_bowl", func(): return CageProps.seed_bowl(_rng(5))],
		["cage/sand_tray", func(): return CageProps.sand_tray(_rng(1), 16.6)],
		["cage/platform", func(): return CageProps.platform(_rng(1), 9.0)],
		["cage/water_bottle", func(): return CageProps.water_bottle(_rng(1))],
		["cage/hut", func(): return CageKit.make_kit(CageKit.Kind.HUT, _rng(1))],
		["cage/castle", func(): return CageKit.make_kit(CageKit.Kind.CASTLE, _rng(1))],
		["cage/ice_cream_tub", func(): return CageKit.make_kit(CageKit.Kind.TUB, _rng(1))],
		["cage/gym", func(): return CageGym.gym(_rng(1))],
		["cage/bridge", func(): return CageGym.bendy_bridge(_rng(1), CageGym.BRIDGE_SPAN, CageGym.BRIDGE_RISE)],
		["cage/coconut", func(): return CageGym.coconut(_rng(1), CageGym.COCONUT_R)],
		["cage/chew_sticks", func(): return CageGym.chew_sticks(_rng(3))],
		["cage/egg_carton", func(): return CageGym.egg_carton(_rng(1))],
	]
	for h in CageGym.LOOKOUT_HEIGHTS:
		for canopy in [false, true]:
			var s := _coin(canopy)
			out.append(["cage/lookout_%d%s" % [h, "_canopy" if canopy else ""], func(): return CageGym.lookout(_rng(s), float(h), &"pink")])
	return out


func _run() -> void:
	CageKit.exporting = true
	var dir := ProjectSettings.globalize_path("res://tools/_cache/maps/raw")
	for spec in specs():
		var id: String = spec[0]
		if not only.is_empty() and not only.has(id) and not only.has(id.get_slice("/", 0)):
			continue
		var kit: Node3D = spec[1].call()
		var mesh: Mesh = (kit.get_node("Mesh") as MeshInstance3D).mesh
		var root := Node3D.new()
		root.name = id.get_file()
		var mi := MeshInstance3D.new()
		mi.name = id.get_file()
		mi.mesh = mesh
		root.add_child(mi)
		var doc := GLTFDocument.new()
		var state := GLTFState.new()
		doc.append_from_scene(root, state)
		var path := dir.path_join(id + ".glb")
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
		var err := doc.write_to_filesystem(state, path)
		print("raw %s: %d surfaces, %s" % [id, mesh.get_surface_count(), "ok" if err == OK else error_string(err)])
		root.free()
		kit.free()
	CageKit.exporting = false
	get_tree().quit()
