extends Node3D
## Every species jumps in turn so each signature move can be seen.
##   godot --path . --write-movie /tmp/tricks/f.png --fixed-fps 30 \
##         --resolution 1280x720 -s tests/capture_tricks.gd
## Bun front-flips running left, the bandit bunny back-flips backing right, then the
## squirrel spins, the fox pounces, the raccoon cannonballs, the frog leaps, the
## beaver tail-slaps and the hamster barrel-rolls.

const ORDER := ["bun", "squirrel", "fox", "raccoon", "frog", "beaver", "hamster", "bandit_bunny"]

var critters: Array = []
var _t := 0.0
var _events: Array = []


func _ready() -> void:
	var light := WorldLighting.new()
	add_child(light)
	light.build(2)
	light.sun.rotation_degrees = Vector3(-40, -150, 0)
	light.env.fog_density = 0.004
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
	gm.normal_enabled = true
	gm.normal_texture = load("res://assets/textures/forest_floor/normal.png")
	gm.uv1_scale = Vector3(18, 18, 18)
	mi.material_override = gm
	ground.add_child(mi)
	add_child(ground)
	# the other six stand in a back row; the two bunnies get a front lane
	var row := 0
	for i in ORDER.size():
		var c := Critter.new()
		c.def = load("res://data/critters/%s.tres" % ORDER[i])
		add_child(c)
		var pos := Vector3.ZERO
		if ORDER[i] == "bun":
			pos = Vector3(4.2, 0.05, 2.0)
		elif ORDER[i] == "bandit_bunny":
			pos = Vector3(-4.0, 0.05, 3.2)
		else:
			pos = Vector3((row - 2.5) * 1.6, 0.05, -0.5)
			row += 1
		c.place_at(pos, PI / 2.0)   # in profile, facing screen-left (-X)
		c.give_weapon(WeaponInstance.new(WeaponDB.get_weapon(&"carrot_smg" if i % 2 == 0 else &"carrot_pistol"), 0))
		critters.append(c)
	var cam := Camera3D.new()
	cam.fov = 52
	add_child(cam)
	cam.current = true
	cam.global_position = Vector3(0.0, 1.35, 7.6)
	cam.look_at(Vector3(0, 1.0, 0), Vector3.UP)
	# Bun (left end) runs left and front-flips; the bandit (right end) backs off
	# to the right and back-flips; everyone else shows their move in turn
	var last := ORDER.size() - 1
	_events.append([0.4, func(): critters[0].move_input = Vector2(0, 1)])
	_events.append([0.7, func(): critters[0].want_jump = true])
	_events.append([1.5, func(): critters[0].move_input = Vector2.ZERO])
	_events.append([1.7, func(): critters[last].move_input = Vector2(0, -1)])
	_events.append([1.95, func(): critters[last].want_jump = true])
	_events.append([2.8, func(): critters[last].move_input = Vector2.ZERO])
	for i in range(1, last):
		var k: int = i
		_events.append([3.0 + (i - 1) * 0.55, func(): critters[k].want_jump = true])
	_events.append([7.0, func(): get_tree().quit()])
	_events.sort_custom(func(a, b): return a[0] < b[0])


func _physics_process(delta: float) -> void:
	_t += delta
	while not _events.is_empty() and _t >= _events[0][0]:
		_events.pop_front()[1].call()
	for c in critters:
		c.look_yaw = PI / 2.0
		c.aim_point = c.get_eye_position() + Vector3(-10, 0, 0)
