extends Node3D
## Renders single env models at critter eye level (camera 1 m up, `dist` m away).
## Used for visual QA of imported scans: tests/capture_models.gd -- <out_dir> id1 id2 ...

var out_dir := "user://models"
var ids: Array = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var light := WorldLighting.new()
	add_child(light)
	light.build(2)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(200, 200)
	ground.mesh = plane
	var gm := StandardMaterial3D.new()
	gm.albedo_texture = load("res://assets/textures/forest_floor/albedo.jpg")
	gm.uv1_scale = Vector3(30, 30, 30)
	ground.material_override = gm
	add_child(ground)
	var scatter := Scatter.new()
	add_child(scatter)
	scatter.load_manifest()
	var cam := Camera3D.new()
	cam.fov = 70
	add_child(cam)
	cam.current = true
	for id in ids:
		var e := scatter.get_entry(id)
		if e.is_empty():
			print("missing ", id)
			continue
		var inst := scatter.place(e, Vector3.ZERO, 0.0, 1.0)
		var r := maxf(float(e.get("footprint_radius_m", 2.0)), 1.0)
		var dist := r + 5.0
		cam.global_position = Vector3(dist * 0.7, 1.0, dist * 0.7)
		cam.look_at(Vector3(0, minf(float(e.get("height_m", 2.0)) * 0.35, 3.0), 0), Vector3.UP)
		for i in 8:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png(out_dir.path_join("model_%s.png" % id))
		print("shot ", id)
		if inst:
			inst.queue_free()
		for c in scatter.get_children():
			c.queue_free()
		await get_tree().process_frame
	get_tree().quit()
