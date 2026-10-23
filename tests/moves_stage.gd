extends Node3D
## Stage for tests/capture_moves.gd (loaded at runtime so autoloads exist).

var out_dir := "user://moves"
var cam: Camera3D


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


func _spawn(id: String, pos: Vector3, yaw := 0.0) -> Critter:
	var c := Critter.new()
	c.def = load("res://data/critters/%s.tres" % id)
	add_child(c)
	c.place_at(pos, yaw)
	return c


func _look(from: Vector3, at: Vector3, fov := 40.0) -> void:
	cam.fov = fov
	cam.global_position = from
	cam.look_at(at, Vector3.UP)


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
	box.size = Vector3(400, 1, 400)
	cs.shape = box
	cs.position.y = -0.5
	ground.add_child(cs)
	var mi := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(400, 400)
	mi.mesh = plane
	var gm := StandardMaterial3D.new()
	gm.albedo_texture = load("res://assets/textures/forest_floor/albedo.jpg")
	gm.uv1_scale = Vector3(50, 50, 50)
	mi.material_override = gm
	ground.add_child(mi)
	add_child(ground)
	cam = Camera3D.new()
	add_child(cam)
	cam.current = true

	# --- the army crawl: four species lying down and crawling toward +X
	var crawlers: Array[Critter] = []
	var ids := ["bun", "fox", "frog", "hamster"]
	for i in ids.size():
		var c := _spawn(ids[i], Vector3(-6, 0.05, (i - 1.5) * 3.2), -PI / 2.0)
		c.want_prone = true
		crawlers.append(c)
	crawlers[3].give_weapon(WeaponInstance.new(WeaponDB.get_weapon(&"carrot_rifle")))
	await _wait(1.0)
	for c in crawlers:
		c.move_input = Vector2(0, 1)
	await _wait(1.2)
	_look(Vector3(-2, 2.2, 13), Vector3(-3, 0.4, 0))
	await _snap("31_crawl_side")
	_look(Vector3(8, 3.5, 3), Vector3(-3, 0.3, 0))
	await _snap("32_crawl_front")
	for c in crawlers:
		c.queue_free()

	# --- running: a fox and a squirrel mid-bound, from the side
	var runners: Array[Critter] = []
	for i in 2:
		var c := _spawn(["fox", "squirrel"][i], Vector3(-60, 0.05, (i - 0.5) * 4.0), -PI / 2.0)
		c.move_input = Vector2(0, 1)
		c.want_sprint = i == 0
		runners.append(c)
	for k in 3:
		await _wait(0.13 + k * 0.05)
		var mid := (runners[0].global_position + runners[1].global_position) * 0.5
		_look(mid + Vector3(0, 2.0, 12), mid + Vector3(0, 1.2, 0))
		await _snap("33_run_%d" % k)
	for c in runners:
		c.queue_free()

	# --- under the glider: legs hanging, leaning into a steer to the right
	var gliders: Array[Critter] = []
	for i in 2:
		var c := _spawn(["bun", "fox"][i], Vector3(40 + i * 7.0, 0.05, 40), 0.0)
		c.begin_freefall(Vector3(40 + i * 7.0, 80, 40), Vector3.ZERO)
		c.want_jump = true
		c.give_weapon(WeaponInstance.new(WeaponDB.get_weapon(&"carrot_pistol")))   # face the way they look
		gliders.append(c)
	await _wait(0.3)
	for c in gliders:
		c.move_input = Vector2(1, 0)
	await _wait(1.8)
	var g := (gliders[0].global_position + gliders[1].global_position) * 0.5
	_look(g + Vector3(0, 1.5, 16), g + Vector3(0, 1.0, 0))
	await _snap("34_glide_behind_steer_right")
	g = (gliders[0].global_position + gliders[1].global_position) * 0.5
	_look(g + Vector3(14, 0.5, -6), g + Vector3(0, 1.0, 0))
	await _snap("35_glide_side")
	for c in gliders:
		c.queue_free()

	# --- a giant lucky clover beside a Bun
	var bun := _spawn("bun", Vector3(-1.5, 0.05, 30), PI * 0.8)
	bun.process_mode = Node.PROCESS_MODE_DISABLED   # (a live Bun would scoop it up)
	Pickup.spawn(self, Pickup.clover_spec(1), Vector3(2.5, 0.4, 30))
	await _wait(1.0)
	_look(Vector3(0.5, 2.4, 38), Vector3(0.5, 1.1, 30))
	await _snap("36_clover")
	bun.queue_free()

	# --- first person: the club over a shotgun, mid-swing
	var me := _spawn("fox", Vector3(0, 0.05, -40), 0.0)
	me.give_weapon(WeaponInstance.new(WeaponDB.get_weapon(&"carrot_shotgun")))
	var rig := CameraRig.new()
	add_child(rig)
	rig.set_target(me)
	rig.first_person = true
	rig.set_target(me)
	await _wait(0.8)
	await _snap("37_fp_shotgun")
	me.want_melee = true
	await _wait(Critter.MELEE_TIME * 0.12)
	await _snap("38_fp_club_ready")
	await _wait(Critter.MELEE_TIME * 0.33)
	await _snap("39_fp_club_strike")
	get_tree().quit()
