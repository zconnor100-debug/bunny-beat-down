extends Node3D
## The bosses on a plain field, a bunny at their feet for scale: standing,
## then caught in the middle of what they do (tests/capture_bosses.gd).

const SCRIPTS := {"brute": "res://src/bosses/brute_boss.gd", "robot": "res://src/bosses/robot_boss.gd",
	"hamster": "res://src/bosses/hamster_boss.gd"}
## Each boss's moves to catch, and how far into each (seconds).
const MOVES := {
	"brute": [["_pound", 0.85], ["_pound", 1.2], ["_toss_pose", 1.35], ["_gobble_pose", 1.5], ["_roar_action", 1.0], ["_death_action", 3.0]],
	"robot": [["_clamp", 0.8], ["_barrage_pose", 1.0], ["_wind_down", 3.0], ["_roar_action", 0.8], ["_death_action", 2.4]],
	"hamster": [["_bite_pose", 0.45], ["_charge_pose", 1.2], ["_spit_pose", 0.6], ["_roar_action", 1.0], ["_death_action", 2.6]],
}

var out_dir := "user://bosses"
var ids: Array = ["brute", "robot", "hamster"]
var faces := false   ## a close-up on its face after each move too
var cam: Camera3D


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(out_dir)
	var light := WorldLighting.new()
	add_child(light)
	light.build(2)
	var fx := FX.new()
	fx.name = "FX"
	add_child(fx)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(600, 600)
	ground.mesh = plane
	var gm := StandardMaterial3D.new()
	gm.albedo_texture = load("res://assets/textures/forest_floor/albedo.jpg")
	gm.uv1_scale = Vector3(90, 90, 90)
	ground.material_override = gm
	add_child(ground)
	var body := StaticBody3D.new()
	body.collision_layer = Layers.WORLD
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(600, 1, 600)
	cs.shape = box
	cs.position.y = -0.5
	body.add_child(cs)
	add_child(body)
	cam = Camera3D.new()
	cam.fov = 60
	cam.far = 2000.0
	add_child(cam)
	cam.current = true
	var bun := Critter.new()
	bun.def = load("res://data/critters/bun.tres")
	add_child(bun)
	bun.place_at(Vector3(7, 0, 9), PI * 0.8)
	bun.team = 2   # (on the bosses' side: nothing they do hurts it)
	for id in ids:
		var boss: Boss = (load(SCRIPTS[id]) as GDScript).new()
		boss.thinking = false
		add_child(boss)
		boss.global_position = Vector3.ZERO
		boss.rotation.y = PI * 0.15
		boss.state = Boss.State.FIGHTING
		boss.visible = true
		boss._set_hittable(true)
		await _settle(10)
		# the scale shot: from a critter's eye height, 70 m off, looking up
		_shoot(Vector3(22, 2.2, -62), Vector3(0, 13, 0), "boss_%s_scale" % id)
		await _settle(4)
		_save("boss_%s_scale" % id)
		_shoot(Vector3(-26, 14, -30), Vector3(0, 11, 0), "")
		await _settle(4)
		_save("boss_%s_front" % id)
		var k := 0
		for m in MOVES.get(id, []):
			boss._cancel_action()
			boss.danger.clear()
			var a: BossAction = _make(boss, String(m[0]))
			if a == null:
				continue
			if a.name == &"death":
				boss.state = Boss.State.DEAD   # (as _die leaves it: it stays down)
			boss.start(a)
			var frames := int(float(m[1]) * 60.0)
			for i in frames:
				await get_tree().physics_frame
			boss.thinking = false
			var was := Engine.time_scale
			Engine.time_scale = 0.0   # (hold the pose for the shot)
			_shoot(Vector3(-30, 12, -34), Vector3(0, 10, 0), "")
			await _settle(3)
			_save("boss_%s_move%d_%s" % [id, k, String(m[0]).trim_prefix("_")])
			if faces:   # (up close on its face: its eyes where they should be, in the pose)
				var eyes := boss.eye_positions()
				var f: Vector3 = (eyes[0] + eyes[1]) * 0.5
				cam.fov = 30.0
				cam.global_position = f + boss.forward() * 22.0 + boss.global_basis.x * 6.0 + Vector3.UP * 2.0
				cam.look_at(f, Vector3.UP)
				await _settle(3)
				_save("boss_%s_move%d_face" % [id, k])
				cam.fov = 60.0
			Engine.time_scale = was
			k += 1
			boss.global_position = Vector3.ZERO
			boss.state = Boss.State.FIGHTING
			boss.alive = true
			boss.set_physics_process(true)
			await _settle(2)
		boss.queue_free()
		await _settle(3)
	get_tree().quit()


## An action of the boss's by name: its own, or a stand-in that needs a target.
func _make(boss: Boss, fn: String) -> BossAction:
	var bun := get_children().filter(func(n): return n is Critter)[0] as Critter
	match fn:
		"_toss_pose":
			return boss._toss(bun)
		"_gobble_pose":
			return boss._gobble(bun)
		"_barrage_pose":
			return boss._barrage(bun)
		"_bite_pose":
			return boss._bite(bun)
		"_charge_pose":
			return boss._charge(bun)
		"_spit_pose":
			return boss._spit(bun)
	return boss.call(fn) as BossAction


func _shoot(from: Vector3, at: Vector3, _name: String) -> void:
	cam.global_position = from
	cam.look_at(at, Vector3.UP)


func _save(file: String) -> void:
	var img := get_viewport().get_texture().get_image()
	if img:
		img.save_png(out_dir.path_join(file + ".png"))
	print("shot ", file)


func _settle(n: int) -> void:
	for i in n:
		await get_tree().process_frame
