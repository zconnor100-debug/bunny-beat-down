extends Node3D
## Stage for tests/capture_clubs.gd (loaded at runtime so autoloads exist).

const IDS := ["bun", "bandit_bunny", "squirrel", "fox", "raccoon", "frog", "beaver", "hamster"]

var out_dir := "user://clubs"
var critters: Array[Critter] = []


func _ready() -> void:
	_run.call_deferred()


func _wait(sec: float) -> void:
	var t := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t < sec * 1000.0:
		await get_tree().process_frame


func _snap(name: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out_dir.path_join(name + ".png"))
	print("shot ", name)


func _run() -> void:
	var light := WorldLighting.new()
	add_child(light)
	light.build(2)
	light.sun.rotation_degrees = Vector3(-40, -150, 0)
	light.env.fog_density = 0.002
	add_child(FX.new())
	add_child(Projectiles.new())
	var ground := StaticBody3D.new()
	ground.collision_layer = Layers.WORLD
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(120, 1, 120)
	cs.shape = box
	cs.position.y = -0.5
	ground.add_child(cs)
	var mi := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(120, 120)
	mi.mesh = plane
	var gm := StandardMaterial3D.new()
	gm.albedo_texture = load("res://assets/textures/forest_floor/albedo.jpg")
	gm.uv1_scale = Vector3(16, 16, 16)
	mi.material_override = gm
	ground.add_child(mi)
	add_child(ground)
	for i in IDS.size():
		var c := Critter.new()
		c.def = load("res://data/critters/%s.tres" % IDS[i])
		c.display_name = c.def.melee_name
		add_child(c)
		c.place_at(Vector3((i - (IDS.size() - 1) * 0.5) * 3.4, 0.05, 0), 0.0)
		critters.append(c)
	var cam := Camera3D.new()
	cam.fov = 40
	add_child(cam)
	cam.current = true
	cam.global_position = Vector3(0, 2.4, -17.0)
	cam.look_at(Vector3(0, 1.7, 0), Vector3.UP)
	await _wait(0.8)
	for c in critters:
		c.visual.set_club(true)
	await _wait(0.6)
	await _snap("21_clubs_ready")
	for c in critters:
		c.want_melee = true
	await _wait(Critter.MELEE_TIME * 0.3)
	await _snap("22_clubs_windup")
	await _wait(Critter.MELEE_TIME * 0.18)
	await _snap("23_clubs_strike")
	# close-ups: the two ends of the line from a 3/4 view
	for c in critters:
		c.visual.set_club(true)
	cam.fov = 30
	for k in [0, 4]:
		var mid := (critters[k].global_position + critters[k + 3].global_position) * 0.5
		cam.global_position = mid + Vector3(2.5, 2.2, -7.5)
		cam.look_at(mid + Vector3(0, 1.3, 0), Vector3.UP)
		await _wait(0.4)
		await _snap("24_clubs_close_%d" % k)
	get_tree().quit()
