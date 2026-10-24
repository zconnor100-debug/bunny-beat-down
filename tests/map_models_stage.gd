extends Node3D
## Renders map models one by one (see tests/capture_map_models.gd): indoor
## lighting, a bedding-coloured floor, a 1 m critter-height post for scale,
## the camera framed on the model's bounds.

var out_dir := "user://map_models"
var ids: Array = []


func _ready() -> void:
	_run.call_deferred()


static func path_of(id: String) -> String:
	return "res://assets/maps/%s.glb" % id if id.contains("/") else "res://assets/env/%s/%s.glb" % [id, id]


func _run() -> void:
	var light := WorldLighting.new()
	add_child(light)
	light.build(2)
	light.make_indoor()
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(400, 400)
	ground.mesh = plane
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.86, 0.74, 0.55)
	gm.roughness = 0.95
	ground.material_override = gm
	add_child(ground)
	var post := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 0.15
	pm.bottom_radius = 0.15
	pm.height = 2.6
	post.mesh = pm
	add_child(post)
	var cam := Camera3D.new()
	cam.fov = 50
	add_child(cam)
	cam.current = true
	for id in ids:
		var m := CageKit.model(path_of(id), {"accent": "paint_red"})
		if m == null:
			print("missing ", id)
			continue
		add_child(m)
		var box := ModelUtil.aabb_of(m)
		var size := box.size.length()
		var c := box.get_center()
		post.position = Vector3(box.position.x - 1.2 - size * 0.05, 1.3, c.z)
		cam.global_position = c + Vector3(0.55, 0.42, 0.75).normalized() * maxf(size * 1.25, 4.0)
		cam.look_at(c, Vector3.UP)
		for i in 10:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png(out_dir.path_join("%s.png" % id.replace("/", "__")))
		print("shot %s %s" % [id, box.size])
		m.queue_free()
		await get_tree().process_frame
	get_tree().quit()
