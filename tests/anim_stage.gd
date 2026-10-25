extends Node3D
## Stage for tests/capture_anims.gd (loaded at runtime so autoloads exist):
## frame strips of how critters stand around, walk, sprint, jump, turn,
## strafe and shoot, so animation changes can be compared side by side.
## Every critter gets its own close camera; each frame is saved as
## <scene>_<critter>_<n>.png.

const ALL := ["bun", "bandit_bunny", "squirrel", "fox", "raccoon", "frog", "beaver", "hamster"]
const GUNS := {
	"bun": &"carrot_pistol", "bandit_bunny": &"carrot_smg", "squirrel": &"carrot_shotgun", "fox": &"carrot_rifle",
	"raccoon": &"carrot_lmg", "frog": &"carrot_sniper", "beaver": &"carrot_rocket_launcher", "hamster": &"carrot_rifle",
}
## The movers: a hopper, two runners with long and short legs, and the frog.
const MOVERS := ["bun", "fox", "hamster", "frog"]
const LANE := 40.0     ## metres between critters, so each camera sees one

var out_dir := "user://anims"
var only := ""
var cam: Camera3D
var actors: Array[Critter] = []


func _ready() -> void:
	_run.call_deferred()


func _physics_process(_delta: float) -> void:
	for c in actors:
		if is_instance_valid(c):
			c.aim_point = c.get_eye_position() + c.look_direction() * 30.0


func _wait(sec: float) -> void:
	var t := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t < sec * 1000.0:
		await get_tree().process_frame


func _spawn(id: String, pos: Vector3, yaw: float, armed: bool) -> Critter:
	var c := Critter.new()
	c.def = load("res://data/critters/%s.tres" % id)
	add_child(c)
	c.place_at(pos, yaw)
	if armed:
		c.give_weapon(WeaponInstance.new(WeaponDB.get_weapon(GUNS[id])))
	actors.append(c)
	return c


func _clear() -> void:
	for c in actors:
		if is_instance_valid(c):
			c.queue_free()
	actors.clear()
	await _wait(0.1)


## `count` frames, `every` seconds apart, each critter seen from `offset`
## (in its lane: x along the lane, metres) looking at its middle. `fixed`
## keeps the camera where the critter stood at the first frame.
func _strip(scene: String, count: int, every: float, offset: Vector3, fixed := false) -> void:
	var anchors := {}
	for c in actors:
		anchors[c] = c.global_position
	for k in count:
		await _wait(every)
		# time stands still while every camera takes its shot (saving is slow)
		Engine.time_scale = 0.0
		await get_tree().process_frame
		for c in actors:
			var h: float = c.visual.rig.world_head_top
			var at: Vector3 = anchors[c] if fixed else c.global_position
			at = Vector3(at.x, c.global_position.y, at.z) + Vector3.UP * h * 0.55
			cam.global_position = at + offset * h / 2.0
			cam.look_at(at, Vector3.UP)
			await get_tree().process_frame
			get_viewport().get_texture().get_image().save_png(out_dir.path_join("%s_%s_%d.png" % [scene, c.def.id, k]))
		Engine.time_scale = 1.0
	print("scene ", scene)


## `only`: comma-separated scene prefixes ("" = every scene).
func _wants(scene: String) -> bool:
	return only == "" or Array(only.split(",")).any(func(p): return scene.begins_with(p))


func _lane(i: int) -> float:
	return (i - 3.5) * LANE


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
	box.size = Vector3(800, 1, 800)
	cs.shape = box
	cs.position.y = -0.5
	ground.add_child(cs)
	var mi := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(800, 800)
	mi.mesh = plane
	var gm := StandardMaterial3D.new()
	gm.albedo_texture = load("res://assets/textures/forest_floor/albedo.jpg")
	gm.uv1_scale = Vector3(100, 100, 100)
	mi.material_override = gm
	ground.add_child(mi)
	add_child(ground)
	cam = Camera3D.new()
	cam.fov = 40.0
	add_child(cam)
	cam.current = true

	# --- standing around, every species: bare paws, then armed (front-right, so
	# the gun hand shows; critters face -Z, their right is +X)
	for armed in [false, true]:
		var scene := "idle_%s" % ["armed" if armed else "unarmed"]
		if not _wants(scene):
			continue
		for i in ALL.size():
			_spawn(ALL[i], Vector3(_lane(i), 0.05, 0), 0.0, armed)
		await _wait(1.0)
		await _strip(scene, 12, 0.8, Vector3(2.6, 0.9, -4.2), true)
		await _clear()

	# --- every species' idle fidgets, one after another, caught halfway through
	for armed in [false, true]:
		var scene := "fidget_%s" % ["armed" if armed else "unarmed"]
		if not _wants(scene):
			continue
		for i in ALL.size():
			_spawn(ALL[i], Vector3(_lane(i), 0.05, 0), 0.0, armed)
		await _wait(3.0)   # (calm: the gun down, the critter settled)
		for k in 5:
			for c in actors:
				var p: CritterPoser = c.visual.poser
				var choices := p._fidget_choices()
				p._fidget = choices[k % choices.size()]
				p._fidget_w = 1.0
				p._fidget_p = 0.5 - 0.6 / float(CritterPoser.FIDGET_TIME[p._fidget])
				p._fidget_wait = 99.0
			await _strip("%s_%d" % [scene, k], 1, 0.6, Vector3(2.6, 0.9, -4.2), true)
		await _clear()

	# --- aiming, every species: from the front and from the gun side
	if _wants("aim"):
		for i in ALL.size():
			var c := _spawn(ALL[i], Vector3(_lane(i), 0.05, -100), 0.0, true)
			c.want_aim = true
		await _wait(1.0)
		await _strip("aim_front", 1, 0.1, Vector3(0.0, 0.5, -4.4), true)
		await _strip("aim_side", 1, 0.1, Vector3(4.4, 0.5, 0.0), true)
		await _clear()

	# --- paws on the gun, up close: from the trigger side and the support side
	if _wants("grip"):
		for i in ALL.size():
			var c := _spawn(ALL[i], Vector3(_lane(i), 0.05, -200), 0.0, true)
			c.want_aim = true
		await _wait(1.0)
		Engine.time_scale = 0.0
		await get_tree().process_frame
		# both paws on the gun: from the trigger side, the support side and below
		# (critters face -Z; their right is +X)
		for view in [["grip_right", Vector3(1.0, 0.35, -0.6)], ["grip_left", Vector3(-1.0, 0.35, -0.6)],
				["grip_under", Vector3(0.2, -0.8, -0.6)]]:
			for c in actors:
				var at: Vector3 = (c.visual.bone_world_position(&"r_hand") + c.visual.bone_world_position(&"l_hand")) * 0.5
				cam.global_position = at + (view[1] as Vector3).normalized() * c.visual.rig.world_head_top * 0.75
				cam.look_at(at, Vector3.UP)
				await get_tree().process_frame
				get_viewport().get_texture().get_image().save_png(out_dir.path_join("%s_%s_0.png" % [view[0], c.def.id]))
		Engine.time_scale = 1.0
		print("scene grip")
		await _clear()

	# --- as you see yourself in play: from the game camera over the right
	# shoulder (CameraRig's offsets), relaxed and then aiming
	if _wants("ots"):
		for i in ALL.size():
			_spawn(ALL[i], Vector3(_lane(i), 0.05, -300), 0.0, true)
		await _wait(3.5)   # (the guns come down)
		for aiming in [false, true]:
			for c in actors:
				c.want_aim = aiming
			await _wait(0.8)
			Engine.time_scale = 0.0
			await get_tree().process_frame
			for c in actors:
				var ws: float = c.visual.rig.world_scale
				var eye: Vector3 = c.get_eye_position() + Vector3.UP * 0.12 * ws
				var dist := (CameraRig.TP_AIM_DISTANCE if aiming else CameraRig.TP_DISTANCE) * ws
				cam.global_position = eye + Vector3.RIGHT * CameraRig.TP_SHOULDER * ws * (0.75 if aiming else 1.0) + Vector3.BACK * dist
				cam.look_at(cam.global_position + Vector3.FORWARD, Vector3.UP)
				cam.fov = 70.0
				await get_tree().process_frame
				get_viewport().get_texture().get_image().save_png(out_dir.path_join("ots_%s_%s_0.png" % ["aim" if aiming else "relaxed", c.def.id]))
			Engine.time_scale = 1.0
		cam.fov = 40.0
		print("scene ots")
		await _clear()

	# --- on the move, side on (running toward +X, seen from their left)
	for scene in ["walk_armed", "sprint_unarmed", "sprint_armed", "jump_armed", "jump_running", "strafe"]:
		if not _wants(scene):
			continue
		var moving: bool = scene != "jump_armed"
		for i in MOVERS.size():
			var c := _spawn(MOVERS[i], Vector3(-150.0 if moving else 0.0, 0.05, 100 + _lane(i)), -PI / 2.0,
				scene != "sprint_unarmed" and scene != "jump_running")
			c.want_sprint = scene.begins_with("sprint")
			if moving:
				c.move_input = Vector2(1, 0) if scene == "strafe" else Vector2(0, 1)
			if scene == "strafe":
				c.place_at(c.global_position, 0.0)   # facing -Z, side-stepping toward +X
		# (long enough for a gun to come down: critters start out alert)
		await _wait(3.0 if moving else 1.2)
		if scene.begins_with("jump"):
			for c in actors:
				c.want_jump = true
		var view := Vector3(0, 0.7, 5.0) if scene != "strafe" else Vector3(0, 0.9, -5.0)
		await _strip(scene, 8 if not scene.begins_with("jump") else 12, 0.07 if not scene.begins_with("jump") else 0.08,
			view, scene == "jump_armed")
		await _clear()

	# --- turning on the spot: the aim swings 100° left over 0.7 s (seen from above-front)
	if _wants("turn"):
		for i in MOVERS.size():
			_spawn(MOVERS[i], Vector3(0, 0.05, 250 + _lane(i)), 0.0, true)
		await _wait(1.0)
		var turn := create_tween().set_parallel()
		for c in actors:
			turn.tween_property(c, "look_yaw", deg_to_rad(100.0), 0.7)
		await _strip("turn", 8, 0.1, Vector3(0.8, 3.2, -3.6), true)
		await _clear()

	# --- shooting on the spot, four guns (front-right)
	if _wants("fire"):
		for i in 4:
			_spawn(["bun", "fox", "raccoon", "beaver"][i], Vector3(_lane(i), 0.05, 300), 0.0, true)
		await _wait(1.0)
		for c in actors:
			c.want_fire = true
		await _strip("fire", 8, 0.06, Vector3(2.6, 0.9, -4.2), true)
		for c in actors:
			c.want_fire = false
		await _clear()
	get_tree().quit()
