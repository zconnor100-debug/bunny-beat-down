extends Node3D
## A boss doing one move on a plain field, shot from the side every `step`
## seconds (a strip of stills to judge its animation by), or filmed as it goes
## (`movie`: run under Movie Maker). tests/capture_boss_strip.gd runs it.

const SCRIPTS := {"brute": "res://src/bosses/brute_boss.gd", "robot": "res://src/bosses/robot_boss.gd",
	"hamster": "res://src/bosses/hamster_boss.gd", "nutcracker": "res://src/bosses/nutcracker_boss.gd",
	"ferret": "res://src/bosses/ferret_boss.gd", "owl": "res://src/bosses/owl_boss.gd"}

var out_dir := "user://strip"
var id := "ferret"
var moves: Array = ["_dance"]
var step := 0.1             ## seconds between stills
var view := "side"          ## side | front | high | low
var movie := false          ## film it (no stills): under --write-movie
var walk := 0.0             ## seconds of walking at the bun first
var bun_at := Vector3(0, 0, 60)   ## where the bun it goes for stands (to one side: it turns)
var dist := 1.0             ## how far back the camera stands (a tall boss: further)
var hold := 0.0             ## seconds stood still after the walk, before its moves
var air := 0.0              ## a flier (Old Hoot) starts up in the air, this high (a death out of the sky)
var aim := -1.0             ## the camera at this height, looking level at the boss there (a close look at its middle)
var cam: Camera3D
var bun: Critter


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(out_dir)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)   # (a window behind others crawls, waiting on vsync; a movie's frames are timed anyway)
	var light := WorldLighting.new()
	add_child(light)
	light.build(2)
	var fx := FX.new()
	fx.name = "FX"
	add_child(fx)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(900, 900)
	ground.mesh = plane
	var gm := StandardMaterial3D.new()
	gm.albedo_texture = load("res://assets/textures/forest_floor/albedo.jpg")
	gm.uv1_scale = Vector3(130, 130, 130)
	ground.material_override = gm
	add_child(ground)
	var body := StaticBody3D.new()
	body.collision_layer = Layers.WORLD
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(900, 1, 900)
	cs.shape = box
	cs.position.y = -0.5
	body.add_child(cs)
	add_child(body)
	cam = Camera3D.new()
	cam.fov = 50
	cam.far = 3000.0
	add_child(cam)
	cam.current = true
	bun = Critter.new()
	bun.def = load("res://data/critters/bun.tres")
	add_child(bun)
	bun.place_at(bun_at, PI)
	bun.team = 2   # (on the boss's side: nothing it does hurts it)
	var boss: Boss = (load(SCRIPTS[id]) as GDScript).new()
	boss.thinking = false
	add_child(boss)
	boss.global_position = Vector3.ZERO
	boss.rotation.y = PI   # (facing +Z, at the bun)
	boss.state = Boss.State.FIGHTING
	boss.visible = true
	boss._set_hittable(true)
	if air > 0.0 and boss is OwlBoss:   # (flying, up there)
		(boss as OwlBoss)._air = true
		(boss as OwlBoss)._air_k = 1.0
		boss.global_position.y = air
	await _frames(10)
	var shot := 0
	if walk > 0.0:
		boss.target = bun
		var left := walk
		while left > 0.0:
			boss._walk_to(bun.global_position, 1.0 / 60.0)
			await get_tree().physics_frame
			left -= 1.0 / 60.0
			_aim(boss)
			if not movie and fmod(walk - left + 1e-4, step) < 1.0 / 60.0:
				shot = await _still(boss, shot)
		boss._speed = 0.0
	if hold > 0.0:   # (stood still a while: what it does with itself)
		var left := hold
		while left > 0.0:
			await get_tree().physics_frame
			left -= 1.0 / 60.0
			_aim(boss)
			if not movie and fmod(hold - left + 1e-4, step) < 1.0 / 60.0:
				shot = await _still(boss, shot)
	for m in moves:
		boss._cancel_action()
		boss.danger.clear()
		var a: BossAction = _make(boss, String(m))
		if a == null:
			push_error("strip: no move %s" % m)
			continue
		if a.name == &"death":
			boss.state = Boss.State.DEAD
		boss.start(a)
		var over := 0.0
		var k := 0
		var every := maxi(1, roundi(step * 60.0))
		boss.set_physics_process(movie)   # (stills: it's stepped here, a 60th of a second at a time, so each one's on time)
		while over < 0.4:
			if not movie and k % every == 0:
				shot = await _still(boss, shot)
			if movie:
				await get_tree().physics_frame
			else:
				boss._physics_process(1.0 / 60.0)
			k += 1
			if boss.action != a:
				over += 1.0 / 60.0
			_aim(boss)
		boss.set_physics_process(true)
	print("STRIP %d stills in %s" % [shot, out_dir])
	get_tree().quit()


## The boss's own move by name, or one that needs someone to go after (the bun).
func _make(boss: Boss, fn: String) -> BossAction:
	if fn == "_death_action":
		boss.alive = false
	if not boss.has_method(fn):
		return null
	if boss.get_method_argument_count(fn) > 0:
		return boss.call(fn, bun)
	var a: Variant = boss.call(fn)
	return a if a is BossAction else boss.action   # (a stun, a crash: it starts its own)


## The camera, kept on the boss as it moves.
func _aim(boss: Boss) -> void:
	var at := Vector3(boss.global_position.x, 0.0, boss.global_position.z)
	var fwd := boss.forward()
	fwd.y = 0.0
	fwd = fwd.normalized()
	var left := Vector3.UP.cross(fwd).normalized()   # (her left: the side we film)
	match view:
		"front":
			cam.global_position = at + (fwd * 75.0 + Vector3.UP * 12.0) * dist
		"high":
			cam.global_position = at + (left * 44.0 - fwd * 18.0 + Vector3.UP * 38.0) * dist
		"low":
			cam.global_position = at + (left * 70.0 + fwd * 10.0 + Vector3.UP * 2.5) * dist
		"back":
			cam.global_position = at + (-fwd * 75.0 + left * 20.0 + Vector3.UP * 12.0) * dist
		_:
			cam.global_position = at + (left * 58.0 + Vector3.UP * 7.0) * dist
	if aim >= 0.0:
		cam.global_position.y = aim
		cam.look_at(at + Vector3.UP * aim, Vector3.UP)
		return
	cam.look_at(at + Vector3.UP * 8.0 * dist, Vector3.UP)


func _still(boss: Boss, shot: int) -> int:
	var was := Engine.time_scale
	Engine.time_scale = 0.0
	_aim(boss)
	await _frames(2)
	# (where its paws are: how high off the ground, front and back)
	var low := func(roles: Array) -> float:
		return roles.map(func(r): return boss.bone_point(r, 1.0).y).min() if roles.all(func(r): return boss.poser.has(r)) else -1.0
	print("STILL %d front %.1f m, back %.1f m, hips %.1f m" % [shot, low.call([&"l_hand", &"r_hand"]), low.call([&"l_foot", &"r_foot"]),
		boss.bone_point(&"hips", 0.0).y if boss.poser.has(&"hips") else -1.0])
	var img := get_viewport().get_texture().get_image()
	img.resize(img.get_width() / 3, img.get_height() / 3, Image.INTERPOLATE_BILINEAR)
	img.save_png(out_dir.path_join("f%03d.png" % shot))
	Engine.time_scale = was
	return shot + 1


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
