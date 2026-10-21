extends Node3D
## Stage for tests/capture_roster.gd (loaded at runtime so autoloads exist).

const IDS := ["bun", "bandit_bunny", "squirrel", "fox", "raccoon", "frog", "beaver", "hamster"]
const GUNS := [&"carrot_pistol", &"carrot_smg", &"carrot_shotgun", &"carrot_rifle", &"carrot_lmg", &"carrot_sniper", &"carrot_rocket_launcher", &"carrot_rifle"]

var out_dir := "user://roster"
var world: Node3D
var critters: Array = []


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
	print("run start")
	world = Node3D.new()
	add_child(world)
	var light := WorldLighting.new()
	world.add_child(light)
	light.build(2)
	light.sun.rotation_degrees = Vector3(-40, -150, 0)
	light.env.fog_density = 0.004
	world.add_child(FX.new())
	world.add_child(Projectiles.new())
	var ground := StaticBody3D.new()
	ground.collision_layer = Layers.WORLD
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(80, 1, 80)
	cs.shape = box
	cs.position.y = -0.5
	ground.add_child(cs)
	var mi := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(80, 80)
	mi.mesh = plane
	var gm := StandardMaterial3D.new()
	gm.albedo_texture = load("res://assets/textures/forest_floor/albedo.jpg")
	gm.normal_enabled = true
	gm.normal_texture = load("res://assets/textures/forest_floor/normal.png")
	gm.uv1_scale = Vector3(12, 12, 12)
	mi.material_override = gm
	ground.add_child(mi)
	world.add_child(ground)

	print("ground built")
	var spacing := 1.25
	for i in IDS.size():
		var c := Critter.new()
		c.def = load("res://data/critters/%s.tres" % IDS[i])
		c.display_name = IDS[i]
		world.add_child(c)
		var x := (i - (IDS.size() - 1) * 0.5) * spacing
		c.place_at(Vector3(x, 0.05, 0), 0.0)
		c.give_weapon(WeaponInstance.new(WeaponDB.get_weapon(GUNS[i % GUNS.size()]), i % 5))
		critters.append(c)
	print("critters spawned")
	var cam := Camera3D.new()
	cam.fov = 38
	world.add_child(cam)
	cam.current = true
	cam.global_position = Vector3(0, 1.0, -8.5)
	cam.look_at(Vector3(0, 0.62, 0), Vector3.UP)
	for c in critters:
		# aim a little to the side of the camera so the guns show in profile
		c.look_yaw = PI + 0.5
		c.aim_point = c.get_eye_position() + Vector3(-0.45, 0.05, -1).normalized() * 10.0
	await _wait(2.5)
	await _snap("roster")

	# hop/run cycle check: everyone jogs in place toward the camera
	for c in critters:
		c.move_input = Vector2(0, 0.0)
	await _wait(0.2)

	# gore showcase: a rocket lands in the middle of the line-up
	cam.global_position = Vector3(2.5, 1.6, -7.5)
	cam.look_at(Vector3(0, 0.5, 0), Vector3.UP)
	var w := WeaponInstance.new(WeaponDB.get_weapon(&"carrot_rocket_launcher"), 4)
	Explosion.detonate(get_tree(), Vector3(0.2, 0.2, 0.3), w, null)
	await _wait(0.12)
	await _snap("gore_blast")
	await _wait(1.6)
	await _snap("gore_aftermath")
	get_tree().quit()
