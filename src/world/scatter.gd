class_name Scatter
extends Node3D
## Places environment models from assets/env/manifest.json.
## Solid things (trees, rocks, logs) become individual instances with cached
## collision shapes; ground cover (grass, flowers, ferns) is batched into
## chunked MultiMeshes with visibility ranges and a wind shader.

const MANIFEST := "res://assets/env/manifest.json"
const CHUNK := 64.0
const FOLIAGE_SHADER := preload("res://src/world/shaders/foliage.gdshader")
const BATCHED := ["grass", "flower", "bush", "reed", "lily"]

var entries: Array = []                 # manifest dictionaries
var by_category: Dictionary = {}        # category -> Array of entries
var _shape_cache: Dictionary = {}
var _foliage_mats: Dictionary = {}          # model id -> foliage Mesh copy
var _foliage_shader_mats: Array[ShaderMaterial] = []
var _batches: Dictionary = {}           # "id|cx|cz" -> Array[Transform3D]
var _batch_entry: Dictionary = {}       # "id|cx|cz" -> entry
var obstacles: Array = []               # [Vector2 pos, radius] of solid things, for spacing
## Areas kept clear of other scatter (the big buildings) but not solid
## themselves: loot can go inside. [Vector2 pos, radius].
var reserved: Array = []
const GRID := 16.0                       # spatial hash cell for the spacing checks
var _grid: Dictionary = {}               # Vector2i -> Array of [pos, radius]

## Ground cover hides critters from bots the way it hides them from you.
## Optical depth per metre of sight line through each kind of cover:
## bushes and ferns hide you, grass hides legs, a dandelion barely anything.
const COVER_DENSITY := {"bush": 1.3, "reed": 1.0, "grass": 0.55, "flower": 0.25}
const COVER_CELL := 6.0
const COVER_MIN_HEIGHT := 0.6           ## clover and fallen leaves hide nothing
const LOW_COVER_REACH := 10.0           ## grass and flowers only matter near the target
## cell (Vector2i) -> PackedFloat32Array of [x, z, radius, base_y, top_y, density] per plant
var _cover_tall: Dictionary = {}        # bushes and ferns: block a whole sight line
var _cover_low: Dictionary = {}         # grass and flowers


func load_manifest() -> void:
	if not FileAccess.file_exists(MANIFEST):
		push_warning("no environment manifest — island will be bare")
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	if not data is Array:
		return
	for e in data:
		var path := "res://" + String(e.get("file", ""))
		if not ResourceLoader.exists(path):
			continue
		e["res"] = path
		entries.append(e)
		var cat: String = e.get("category", "prop")
		if not by_category.has(cat):
			by_category[cat] = []
		by_category[cat].append(e)


func get_entry(id: String) -> Dictionary:
	for e in entries:
		if e.get("id") == id:
			return e
	return {}


func pick(category: String, rng: RandomNumberGenerator) -> Dictionary:
	var list: Array = by_category.get(category, [])
	if list.is_empty():
		return {}
	var total := 0.0
	for e in list:
		total += float(e.get("density_weight", 1.0))
	var r := rng.randf() * total
	for e in list:
		r -= float(e.get("density_weight", 1.0))
		if r <= 0.0:
			return e
	return list.back()


## True if a solid object of `radius` at `p` would overlap one already placed
## (or a reserved building plot, unless `with_reserved` is off).
func blocked(p: Vector2, radius: float, with_reserved := true) -> bool:
	var lo := Vector2i(floori((p.x - radius) / GRID), floori((p.y - radius) / GRID))
	var hi := Vector2i(floori((p.x + radius) / GRID), floori((p.y + radius) / GRID))
	for cz in range(lo.y, hi.y + 1):
		for cx in range(lo.x, hi.x + 1):
			for o in _grid.get(Vector2i(cx, cz), []):
				if not with_reserved and o.size() > 2:
					continue
				var r: float = o[1] + radius
				if p.distance_squared_to(o[0]) < r * r:
					return true
	return false


## Remember a solid footprint for the spacing checks.
func add_obstacle(p: Vector2, radius: float) -> void:
	var o := [p, radius]
	obstacles.append(o)
	_hash(o)


## Keep other scatter out of a circle (a building plot) without making it solid.
func reserve(p: Vector2, radius: float) -> void:
	var o := [p, radius, true]
	reserved.append(o)
	_hash(o)


func _hash(o: Array) -> void:
	var p: Vector2 = o[0]
	var r: float = o[1]
	for cz in range(floori((p.y - r) / GRID), floori((p.y + r) / GRID) + 1):
		for cx in range(floori((p.x - r) / GRID), floori((p.x + r) / GRID) + 1):
			var k := Vector2i(cx, cz)
			if not _grid.has(k):
				_grid[k] = []
			_grid[k].append(o)


## Place one model. `ground` is the terrain height at the spot.
func place(e: Dictionary, pos: Vector3, yaw: float, scale_: float, normal := Vector3.UP, align := 0.0) -> Node3D:
	if e.is_empty():
		return null
	var cat: String = e.get("category", "prop")
	var basis := Basis(Vector3.UP, yaw)
	if align > 0.0 and normal.dot(Vector3.UP) < 0.999:
		basis = Basis(IKMath.from_to(Vector3.UP, Vector3.UP.lerp(normal, align).normalized())) * basis
	pos.y -= float(e.get("sink_m", 0.0)) * scale_
	var xf := Transform3D(basis.scaled_local(Vector3.ONE * scale_), pos)
	if cat in BATCHED:
		_add_batched(e, xf)
		return null
	var inst := ModelUtil.instantiate(e["res"])
	if inst == null:
		return null
	add_child(inst)
	inst.transform = xf
	var vis_end := 900.0 if cat in ["tree", "landmark"] else 260.0
	for gi in ModelUtil.find_all(inst, "GeometryInstance3D"):
		(gi as GeometryInstance3D).visibility_range_end = vis_end
		(gi as GeometryInstance3D).visibility_range_end_margin = 20.0
		(gi as GeometryInstance3D).visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	var col: String = e.get("collision", "none")
	if col != "none":
		_add_collision(inst, e, scale_, col)
		add_obstacle(Vector2(pos.x, pos.z), maxf(float(e.get("collision_radius_m", 0.5)), 0.3) * scale_)
	return inst


func _add_collision(inst: Node3D, e: Dictionary, scale_: float, kind: String) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = Layers.WORLD
	var cat: String = e.get("category", "prop")
	body.set_meta(&"surface", &"wood" if cat in ["tree", "log", "stump"] else (&"rock" if cat == "rock" else &"dirt"))
	if cat == "tree":
		# the trunk collider ends inside the canopy; nobody gets to stand on top of it
		body.set_meta(&"slippery", true)
	var shape := _shape_for(e, kind)
	if shape == null:
		return
	var cs := CollisionShape3D.new()
	cs.shape = shape
	if kind == "cylinder":
		var h := float(e.get("height_m", 2.0))
		if cat == "tree":
			h = minf(h, 40.0)   # trunks only; the canopy is far overhead
		cs.position.y = h * 0.5
	body.add_child(cs)
	# body sits at the instance origin without scale; the scale lives on the shape node
	add_child(body)
	body.global_transform = Transform3D(inst.global_basis.orthonormalized(), inst.global_position)
	if kind != "cylinder":
		cs.scale = Vector3.ONE * scale_
	else:
		cs.scale = Vector3.ONE * scale_


func _shape_for(e: Dictionary, kind: String) -> Shape3D:
	var key: String = e["id"] + "|" + kind
	if _shape_cache.has(key):
		return _shape_cache[key]
	var shape: Shape3D = null
	match kind:
		"cylinder":
			var c := CylinderShape3D.new()
			c.radius = maxf(float(e.get("collision_radius_m", 0.5)), 0.1)
			var h := float(e.get("height_m", 2.0))
			if e.get("category") == "tree":
				h = minf(h, 40.0)
			c.height = h
			shape = c
		"convex", "trimesh":
			var mesh := _merged_mesh(e["res"])
			if mesh:
				shape = mesh.create_convex_shape(true, true) if kind == "convex" else mesh.create_trimesh_shape()
	_shape_cache[key] = shape
	return shape


func _merged_mesh(path: String) -> ArrayMesh:
	var root := ModelUtil.instantiate(path)
	if root == null:
		return null
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var any := false
	for mi in ModelUtil.find_all(root, "MeshInstance3D"):
		var m := mi as MeshInstance3D
		var xf := ModelUtil._relative_xform(root, m)
		for s in m.mesh.get_surface_count():
			st.append_from(m.mesh, s, xf)
			any = true
	root.free()
	return st.commit() if any else null


func _add_batched(e: Dictionary, xf: Transform3D) -> void:
	_add_cover(e, xf)
	var cx := int(floor(xf.origin.x / CHUNK))
	var cz := int(floor(xf.origin.z / CHUNK))
	var key := "%s|%d|%d" % [e["id"], cx, cz]
	if not _batches.has(key):
		_batches[key] = []
		_batch_entry[key] = e
	_batches[key].append(xf)


func _add_cover(e: Dictionary, xf: Transform3D) -> void:
	var cat: String = e.get("category", "")
	var sc := xf.basis.get_scale().y
	var height := float(e.get("height_m", 0.0)) * sc
	if not COVER_DENSITY.has(cat) or height < COVER_MIN_HEIGHT:
		return
	var grid := _cover_tall if cat in ["bush", "reed"] else _cover_low
	var cell := Vector2i(floori(xf.origin.x / COVER_CELL), floori(xf.origin.z / COVER_CELL))
	if not grid.has(cell):
		grid[cell] = PackedFloat32Array()
	# the footprint includes the sparse tips of the leaves
	var radius := float(e.get("footprint_radius_m", 0.5)) * sc * 0.75
	grid[cell].append_array([xf.origin.x, xf.origin.z, radius, xf.origin.y, xf.origin.y + height * 0.9, COVER_DENSITY[cat]])


## How much of `points` (say a critter's head, chest and hips) can be seen
## from `eye` through the ground cover in between: 1 = in plain view, toward 0
## = hidden in the leaves. Solid things are not counted (use a raycast).
func visibility(eye: Vector3, points: PackedVector3Array) -> float:
	if points.is_empty():
		return 0.0
	var target := points[points.size() / 2]
	var plants := PackedFloat32Array()
	_gather(_cover_tall, eye, target, plants)
	var reach := minf(LOW_COVER_REACH, eye.distance_to(target))
	_gather(_cover_low, target + (eye - target).normalized() * reach, target, plants)
	if plants.is_empty():
		return 1.0
	var total := 0.0
	for p in points:
		total += exp(-_cover_depth(eye, p, plants))
	return total / points.size()


## Appends every plant within reach of the segment a→b (in plan view).
func _gather(grid: Dictionary, a: Vector3, b: Vector3, out: PackedFloat32Array) -> void:
	if grid.is_empty():
		return
	var a2 := Vector2(a.x, a.z)
	var b2 := Vector2(b.x, b.z)
	var cells := {}
	var steps := ceili(a2.distance_to(b2) / (COVER_CELL * 0.5))
	for i in steps + 1:
		var p := a2.lerp(b2, float(i) / maxf(steps, 1))
		var c := Vector2i(floori(p.x / COVER_CELL), floori(p.y / COVER_CELL))
		for dx in [-1, 0, 1]:
			for dz in [-1, 0, 1]:
				cells[c + Vector2i(dx, dz)] = true
	for c in cells:
		var arr: PackedFloat32Array = grid.get(c, PackedFloat32Array())
		for j in range(0, arr.size(), 6):
			var centre := Vector2(arr[j], arr[j + 1])
			var r := arr[j + 2]
			if Geometry2D.get_closest_point_to_segment(centre, a2, b2).distance_squared_to(centre) < r * r:
				out.append_array(arr.slice(j, j + 6))


## Optical depth of the leaves along eye→p: for each plant, the length of the
## sight line inside its (cylindrical) crown, if the line passes at a height
## the plant reaches.
func _cover_depth(eye: Vector3, p: Vector3, plants: PackedFloat32Array) -> float:
	var a := Vector2(eye.x, eye.z)
	var ab := Vector2(p.x, p.z) - a
	var length := ab.length()
	if length < 0.01:
		return 0.0
	var dir := ab / length
	var depth := 0.0
	for j in range(0, plants.size(), 6):
		var rel := Vector2(plants[j], plants[j + 1]) - a
		var along := rel.dot(dir)
		var off := absf(rel.cross(dir))
		var r := plants[j + 2]
		if off >= r:
			continue
		var half := sqrt(r * r - off * off)
		var t0 := clampf(along - half, 0.0, length)
		var t1 := clampf(along + half, 0.0, length)
		if t1 <= t0:
			continue
		var y := lerpf(eye.y, p.y, (t0 + t1) * 0.5 / length)
		if y >= plants[j + 3] and y <= plants[j + 4]:
			depth += (t1 - t0) * plants[j + 5]
	return depth


## Turn every collected batch into a MultiMeshInstance3D.
func flush_batches(quality: int) -> void:
	for key in _batches:
		var e: Dictionary = _batch_entry[key]
		var xfs: Array = _batches[key]
		var mesh := _foliage_mesh(e)
		if mesh == null:
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = xfs.size()
		for i in xfs.size():
			mm.set_instance_transform(i, xfs[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		var cat: String = e.get("category")
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cat in ["bush", "reed"] and quality >= 2 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var reach := {"grass": 75.0, "flower": 110.0, "bush": 170.0, "reed": 150.0, "lily": 90.0}.get(cat, 100.0) as float
		reach *= [0.55, 0.8, 1.0, 1.35][clampi(quality, 0, 3)]
		mmi.visibility_range_end = reach
		mmi.visibility_range_end_margin = 12.0
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		add_child(mmi)
	_batches.clear()
	_batch_entry.clear()


## A copy of the model's mesh whose every surface uses the wind/foliage shader
## with that surface's own textures (a bush's bark keeps its bark, its leaf
## cards keep their alpha cut-out). Cached per model.
func _foliage_mesh(e: Dictionary) -> Mesh:
	if e.has("_mesh"):
		return e["_mesh"]   # built in code (SwampPlants), materials already set
	var key: String = e["id"]
	if _foliage_mats.has(key):
		return _foliage_mats[key]
	var src := ModelUtil.first_mesh(e["res"])
	if src == null:
		return null
	var height := float(e.get("height_m", 1.0))
	var cat: String = e.get("category", "grass")
	var out := ArrayMesh.new()
	for i in src.get_surface_count():
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, src.surface_get_arrays(i))
		out.surface_set_material(i, _foliage_material(src.surface_get_material(i) as BaseMaterial3D, height, cat))
	_foliage_mats[key] = out
	return out


func _foliage_material(src: BaseMaterial3D, height: float, cat: String) -> Material:
	if src == null:
		return null
	var m := ShaderMaterial.new()
	m.shader = FOLIAGE_SHADER
	m.set_shader_parameter(&"albedo_tex", src.albedo_texture)
	m.set_shader_parameter(&"albedo_color", src.albedo_color)
	if src.normal_enabled and src.normal_texture:
		m.set_shader_parameter(&"normal_tex", src.normal_texture)
		m.set_shader_parameter(&"use_normal", true)
	m.set_shader_parameter(&"roughness", src.roughness)
	var cutout := src.transparency in [BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR, BaseMaterial3D.TRANSPARENCY_ALPHA_HASH, BaseMaterial3D.TRANSPARENCY_ALPHA]
	m.set_shader_parameter(&"alpha_scissor", src.alpha_scissor_threshold if cutout else 0.01)
	m.set_shader_parameter(&"model_height", maxf(height, 0.1))
	m.set_shader_parameter(&"wind_strength", 0.16 if cat == "grass" else 0.08)
	_foliage_shader_mats.append(m)
	return m
