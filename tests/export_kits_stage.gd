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


## A seed that gives a brick tower of `courses` courses (its second draw).
static func _tower_seed(courses: int) -> int:
	for s in 1000:
		var r := _rng(s)
		r.randf_range(7.0, 9.0)
		if r.randi_range(4, 8) == courses:
			return s
	return 0


## A room's kit, built (with everything else in the room) into a throwaway parent.
static func _room_kit(build: Callable, kit_name: String) -> Node:
	var p := Node3D.new()
	build.call(p)
	var k := p.find_child(kit_name, true, false)
	k.get_parent().remove_child(k)
	p.free()
	return k


static func _toy_box() -> ToyBox:
	var tb := ToyBox.new()
	tb.rng = _rng(1)
	return tb


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
	out += [
		["toy/dollhouse", func(): return ToyProps.dollhouse(_rng(1))],
		["toy/block_castle", func(): return ToyProps.block_castle(_rng(1))],
		["toy/brick_house", func(): return ToyProps.brick_house(_rng(1))],
		["toy/pillow_fort", func(): return ToyProps.pillow_fort(_rng(1))],
		["toy/crayon_box", func(): return ToyProps.crayon_box(_rng(1))],
		["toy/coloring_book", func(): return ToyProps.coloring_book(_rng(1))],
		["toy/tea_table", func(): return ToyProps.tea_table(_rng(1))],
		["toy/toy_chest", func(): return ToyProps.toy_chest(_rng(1))],
		["toy/race_track", func(): return ToyProps.race_track(_rng(1))],
		["toy/fishbowl", func(): return ToyProps.fishbowl(_rng(1), ToyBox.BOWL_RIM)],
		["toy/baseplate", func(): return ToyProps.baseplate(_rng(1))],
		["toy/station", func(): return _toy_box()._station()],
		["cage/room", func(): return _room_kit(func(p): CageRoom.build_room(p, _rng(1)), "Room")],
		["cage/tank_trim", func(): return _room_kit(func(p): CageRoom.build_tank(p, _rng(1)), "TankTrim")],
		["cage/fridge", func(): return _room_kit(func(p): CageRoom.build_fridge(p, _rng(1)), "Fridge")],
		["cage/icicles", func(): return _room_kit(func(p): CageRoom.build_icicles(p, _rng(1)), "Icicles")],
		["cage/plane_body", func(): return _room_kit(func(p): p.add_child(CageProps.toy_plane(_rng(1))), "Body")],
		["cage/plane_propeller", func(): return _room_kit(func(p): p.add_child(CageProps.toy_plane(_rng(1))), "Propeller")],
		["toy/bedroom", func(): return _room_kit(func(p): ToyRoom.build(p, _rng(1)), "Bedroom")],
		["toy/mobile", func(): return _room_kit(func(p): ToyRoom._mobile(p, _rng(1)), "MobileParts")],
		["toy/locomotive", func(): return ToyTrain.new()._locomotive(_rng(1), 0)],
		["toy/tender", func(): return ToyTrain.new()._tender(_rng(1), 1)],
		["toy/open_car", func(): return ToyTrain.new()._open_car(_rng(1), 2)],
		["toy/caboose", func(): return ToyTrain.new()._caboose(_rng(1), 5)],
	]
	for v in ToyProps.LETTER_VARIANTS:
		out.append(["toy/letter_block_%d" % v, func():
			var k := CageKit.blank("LetterBlock", _rng(1))
			k._letter_box(Vector3(0, 0.5, 0), 1.0, Basis(), ToyProps.LETTER_CELLS[v])
			return k.finish()])
	for n in range(4, 9):
		var s := _tower_seed(n)
		out.append(["toy/brick_tower_%d" % n, func(): return ToyProps.brick_tower(_rng(s))])
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
	# the toy train's loop, for tools/maps/models.py "toy/track" (a profile swept along it)
	if only.is_empty() or only.has("toy") or only.has("toy/track"):
		var pts := ToyTrain.loop_points(ToyBox.TRACK_RECT, ToyBox.TRACK_CORNER, ToyFloor.FLOOR)
		var flat := []
		for p in pts:
			flat.append([p.x, p.y, p.z])
		var f := FileAccess.open(dir.path_join("toy/track_points.json"), FileAccess.WRITE)
		f.store_string(JSON.stringify({"width": ToyTrain.TRACK_WIDTH, "points": flat}))
		f.close()
		print("raw toy/track_points.json: %d points" % pts.size())
	# Wildwood Island's buildings, piece by piece, for tools/maps/island.py
	if only.is_empty() or only.has("island"):
		Building.recording = true
		for style in Building.Style.values():
			var id := String(Building.Style.keys()[style]).to_lower()
			var b := Building.make(style, _rng(1))
			var data := {"style": id, "floor_y": b.floor_y, "footprint": b.footprint, "parts": b.parts, "walls": b.walls,
				"loot": b.loot_spots.map(func(q: Vector3): return [q.x, q.y, q.z]), "chest": [b.chest_spot.x, b.chest_spot.y, b.chest_spot.z]}
			var path := dir.path_join("island/%s.json" % id)
			DirAccess.make_dir_recursive_absolute(path.get_base_dir())
			var f := FileAccess.open(path, FileAccess.WRITE)
			f.store_string(JSON.stringify(data))
			f.close()
			print("raw island/%s.json: %d parts, %d walls" % [id, b.parts.size(), b.walls.size()])
			b.free()
		Building.recording = false
	CageKit.exporting = false
	get_tree().quit()
