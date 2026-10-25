extends Node3D
## Stage for tests/capture_outfits.gd (loaded at runtime so autoloads exist).
## "pieces": every outfit model on its own, from the front (+Z, the way a
## critter faces), the side and above, with a red arrow showing +Z, to set
## which way each one faces. "cast": every rogue in its outfit, one species
## at a time, front and three-quarter.

var out_dir := "user://outfits"
var only := ""
var cam: Camera3D


func _ready() -> void:
	_run.call_deferred()


func _snap(name: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out_dir.path_join(name + ".png"))


func _run() -> void:
	var light := WorldLighting.new()
	add_child(light)
	light.build(2)
	light.sun.rotation_degrees = Vector3(-45, -150, 0)
	light.env.fog_density = 0.0
	cam = Camera3D.new()
	cam.fov = 30.0
	add_child(cam)
	cam.current = true
	if only == "" or only == "pieces":
		await _pieces()
	if only == "" or only.begins_with("cast"):
		await _cast(only.trim_prefix("cast").trim_prefix(":"))
	get_tree().quit()


func _pieces() -> void:
	var ids: Array = Outfits.PIECES.keys()
	for i in ids.size():
		var root := Node3D.new()
		add_child(root)
		var m := ModelUtil.instantiate(Outfits.model_path(ids[i]))
		if m == null:
			continue
		root.add_child(m)
		var box := ModelUtil.aabb_of(m)
		var k := 1.0 / maxf(maxf(box.size.x, box.size.y), box.size.z)
		m.scale = Vector3.ONE * k
		m.position = -box.get_center() * k
		var arrow := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.0
		cyl.bottom_radius = 0.06
		cyl.height = 0.25
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(1, 0.1, 0.1)
		cyl.material = mat
		arrow.mesh = cyl
		arrow.rotation_degrees = Vector3(90, 0, 0)
		arrow.position = Vector3(0, -0.6, 0.55)
		root.add_child(arrow)
		for view in [["front", Vector3(0, 0.25, 3.0)], ["side", Vector3(3.0, 0.25, 0)], ["top", Vector3(0, 3.0, 0.01)]]:
			cam.global_position = view[1]
			cam.look_at(Vector3.ZERO, Vector3.UP)
			await _snap("piece_%s_%s" % [ids[i], view[0]])
		root.queue_free()
		await get_tree().process_frame
	print("pieces done")


func _cast(species: String) -> void:
	var ground := StaticBody3D.new()
	ground.collision_layer = Layers.WORLD
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400, 1, 400)
	cs.shape = box
	cs.position.y = -0.5
	ground.add_child(cs)
	var mi := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(400, 400)
	mi.mesh = plane
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.45, 0.5, 0.35)
	mi.material_override = gm
	ground.add_child(mi)
	add_child(ground)
	cam.fov = 34.0
	var groups := {}
	for n in Cast.names():
		var sp: String = Cast.member(n).species
		if species == "" or sp == species:
			if not groups.has(sp):
				groups[sp] = []
			groups[sp].append(n)
	for sp in groups:
		var crits: Array[Critter] = []
		var names: Array = groups[sp]
		for i in names.size():
			var c := Critter.new()
			c.def = load("res://data/critters/%s.tres" % sp)
			add_child(c)
			c.place_at(Vector3((i - (names.size() - 1) * 0.5) * 2.6, 0.05, 0), 0.0)
			c.display_name = names[i]
			Outfits.dress(c, names[i])
			c.process_mode = Node.PROCESS_MODE_DISABLED
			crits.append(c)
		await get_tree().process_frame
		await get_tree().process_frame
		# each rogue up close: three-quarters from the front, and from behind
		for c in crits:
			var h: float = c.visual.rig.world_head_top
			var f := OutfitFit.of(c.visual)
			var s: float = c.visual.rig.size
			# the head and shoulders, whatever the species' proportions
			var at := c.global_position + Vector3.UP * lerpf(f.neck_y, f.crown_y, 0.55) * s
			var span := maxf((f.crown_y - f.chest_y) * s * 1.6, f.head_w * s * 1.8)
			for view in [["front", Vector3(0.45, 0.12, -1.0)], ["back", Vector3(-0.5, 0.2, 1.0)]]:
				cam.global_position = at + (view[1] as Vector3).normalized() * span * 2.2
				cam.look_at(at, Vector3.UP)
				await _snap("rogue_%s_%s" % [c.display_name.replace(" ", "_").replace(".", ""), view[0]])
		for c in crits:
			c.queue_free()
		await get_tree().process_frame
	print("cast done")
