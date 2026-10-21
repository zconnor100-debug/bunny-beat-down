extends SceneTree
## Critter's-eye screenshots of environment assets, rendered by Godot itself.
##
## Needs a real renderer (not --headless), so run it in the THROWAWAY check project:
##   godot4 --path /tmp/bbd-envcheck --resolution 960x540 -s res://godot_eyelevel.gd -- id1 id2 ...
## For each asset: camera 1 m above the ground, 4 m from the model's nearest side
## (4 m from the trunk for trees), sun with shadows + the project's sky HDRI.
## Suffixes: "id@top" = elevated overview, "id@d15" = camera 15 m away instead of 4 m.
## Frames are written to /tmp/bbd-eyelevel/<id>[_<suffix>].png.

const OUT := "/tmp/bbd-eyelevel"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var manifest: Array = JSON.parse_string(FileAccess.get_file_as_string("res://assets/env/manifest.json"))
	var by_id := {}
	for e in manifest:
		by_id[e["id"]] = e
	_setup_world()
	var args := OS.get_cmdline_user_args()
	for arg in args:
		var top := arg.ends_with("@top")
		var dist := 4.0  # "id@d15" = camera 15 m from the model's surface/trunk
		if arg.contains("@d"):
			dist = float(arg.get_slice("@d", 1))
		var id := arg.get_slice("@", 0)
		var tag := arg.get_slice("@", 1) if arg.contains("@") else ""
		if not by_id.has(id):
			print("unknown id ", id)
			continue
		var e: Dictionary = by_id[id]
		var node: Node3D = (load("res://" + str(e["file"])) as PackedScene).instantiate()
		root.add_child(node)
		var box := _aabb(node)
		var cam := Camera3D.new()
		cam.fov = 60.0
		root.add_child(cam)
		var target: Vector3
		if top:
			var r := maxf(box.size.x, box.size.z)
			cam.position = Vector3(r * 0.9, r * 0.8 + 6.0, r * 1.4 + 6.0)
			target = Vector3(0, box.size.y * 0.3, 0)
		elif str(e["category"]) == "tree":
			var trunk := float(e["collision_radius_m"])
			cam.position = Vector3(1.5, 1.0, trunk + dist)
			target = Vector3(0, 1.0 + dist * 0.35, 0)  # base in the lower half, low canopy visible
		else:
			cam.position = Vector3(box.get_center().x + 1.0, 1.0, box.end.z + dist)
			target = Vector3(box.get_center().x, clampf(box.size.y * 0.4, 0.3, 2.0), box.get_center().z)
		cam.look_at_from_position(cam.position, target, Vector3.UP)
		cam.current = true
		for i in 12:  # let shadows, SSAO and auto-exposure settle
			await process_frame
		await RenderingServer.frame_post_draw
		var img := root.get_viewport().get_texture().get_image()
		img.save_png("%s/%s%s.png" % [OUT, id, ("_" + tag) if tag != "" else ""])
		print("saved ", id, " ", tag)
		node.queue_free()
		cam.queue_free()
		await process_frame
	quit()


func _setup_world() -> void:
	var env := Environment.new()
	var sky_mat := PanoramaSkyMaterial.new()
	sky_mat.panorama = load("res://assets/sky/kloofendal_48d_partly_cloudy_puresky_2k.hdr")
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.ssao_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -35, 0)
	sun.light_energy = 1.4
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 150.0
	root.add_child(sun)

	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(400, 400)
	ground.mesh = plane
	var m := StandardMaterial3D.new()
	m.albedo_texture = load("res://assets/textures/forest_floor/albedo.jpg")
	m.normal_enabled = true
	m.normal_texture = load("res://assets/textures/forest_floor/normal.png")
	m.roughness_texture = load("res://assets/textures/forest_floor/roughness.jpg")
	m.uv1_scale = Vector3(100, 100, 1)  # ~4 m per tile
	ground.material_override = m
	root.add_child(ground)


func _aabb(node: Node) -> AABB:
	var acc := {"box": AABB(), "has": false}
	_walk(node, Transform3D.IDENTITY, acc)
	return acc["box"]


func _walk(node: Node, xf: Transform3D, acc: Dictionary) -> void:
	var t := xf
	if node is Node3D:
		t = xf * (node as Node3D).transform
	if node is MeshInstance3D:
		var b := t * (node as MeshInstance3D).get_aabb()
		acc["box"] = b if not acc["has"] else (acc["box"] as AABB).merge(b)
		acc["has"] = true
	for c in node.get_children():
		_walk(c, t, acc)
