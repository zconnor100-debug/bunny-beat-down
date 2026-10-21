extends Node3D
## Scripted gameplay vignette for the README GIF (recorded with Movie Maker):
##   godot --path . --write-movie /tmp/frames/f.png --fixed-fps 30 \
##         --resolution 960x540 -s tests/capture_showcase.gd
## Bun hops in, shotguns a fox, then rocket-carrots a pair of critters.

var world: Node3D
var bun: Critter
var rig: CameraRig
var _frame := 0
var _t := 0.0
var _events: Array = []
var _aim_target := Vector3.INF


func _ready() -> void:
	world = Node3D.new()
	add_child(world)
	var light := WorldLighting.new()
	world.add_child(light)
	light.build(2)
	light.sun.rotation_degrees = Vector3(-42, -60, 0)
	light.env.fog_density = 0.006
	world.add_child(FX.new())
	world.add_child(Projectiles.new())
	_build_ground()
	_dress_set()

	bun = _spawn("bun", Vector3(0, 0.05, 6), 0.0)
	bun.give_weapon(WeaponInstance.new(WeaponDB.get_weapon(&"carrot_shotgun"), Rarity.Tier.GOLDEN))
	bun.give_weapon(WeaponInstance.new(WeaponDB.get_weapon(&"carrot_rocket_launcher"), Rarity.Tier.HEIRLOOM))
	bun.switch_to(0)
	bun.inventory.add_ammo(WeaponData.AmmoType.SHELLS, 20)
	bun.inventory.add_ammo(WeaponData.AmmoType.ROCKET, 4)
	var fox := _spawn("fox", Vector3(2.4, 0.05, -1.2), PI - 0.6)
	var frog := _spawn("frog", Vector3(1.8, 0.05, -9.0), PI)
	var hamster := _spawn("hamster", Vector3(3.0, 0.05, -9.6), PI + 0.4)
	for c in [fox, frog, hamster]:
		c.give_weapon(WeaponInstance.new(WeaponDB.get_weapon(&"carrot_pistol"), 0))
		c.aim_point = bun.get_chest_position()
	rig = CameraRig.new()
	world.add_child(rig)
	rig.set_target(bun)
	rig.yaw = 0.0
	rig.pitch = -0.12

	# timeline (seconds): what Bun does
	_events = [
		[0.4, func(): bun.move_input = Vector2(0, 1)],
		[0.7, func(): bun.want_jump = true],
		[1.0, func(): bun.move_input = Vector2.ZERO],
		[1.5, func(): _aim_at(fox.get_chest_position() + Vector3.UP * 0.1)],
		[1.75, func(): _aim_at(fox.get_chest_position() + Vector3.UP * 0.1)],
		[1.9, func(): bun.want_fire = true],

		[2.0, func(): bun.want_fire = false],
		[2.9, func(): bun.want_fire = true],
		[3.0, func(): bun.want_fire = false],
		[3.6, func(): bun.switch_to(1)],
		[4.2, func(): _aim_at(Vector3(2.4, 0.3, -9.3))],
		[4.6, func(): bun.want_fire = true],
		[4.7, func(): bun.want_fire = false],
		[7.0, func(): get_tree().quit()],
	]


func _aim_at(p: Vector3) -> void:
	_aim_target = p


func _track_aim() -> void:
	if _aim_target == Vector3.INF:
		return
	# aim the *camera* ray at the target (what the crosshair does); the camera
	# orbits the shoulder as it turns, so this is re-solved every tick
	var d := (_aim_target - rig.camera.global_position).normalized()
	rig.yaw = atan2(-d.x, -d.z)
	rig.pitch = asin(d.y)


func _physics_process(delta: float) -> void:
	_t += delta
	while not _events.is_empty() and _t >= _events[0][0]:
		_events.pop_front()[1].call()
	_track_aim()
	bun.look_yaw = rig.yaw
	bun.look_pitch = rig.pitch
	bun.aim_point = rig.aim_point(bun.visual.hitbox_rids)


func _spawn(id: String, pos: Vector3, yaw: float) -> Critter:
	var c := Critter.new()
	c.def = load("res://data/critters/%s.tres" % id)
	c.display_name = id
	world.add_child(c)
	c.place_at(pos, yaw)
	return c


func _build_ground() -> void:
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
	world.add_child(ground)


func _dress_set() -> void:
	var scatter := Scatter.new()
	world.add_child(scatter)
	scatter.load_manifest()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for spec in [["mushroom_fly_agaric", Vector3(-6, 0, -6), 1.3], ["mushroom_amanita", Vector3(7, 0, -14), 1.2],
			["log_mossy", Vector3(-9, 0, -16), 1.0], ["tree_oak_a", Vector3(-26, 0, -60), 1.0], ["tree_birch_a", Vector3(22, 0, -50), 1.0],
			["fern_a", Vector3(5, 0, -3), 1.1], ["fern_b", Vector3(-4, 0, 2), 1.0], ["rock_mossy_a", Vector3(11, 0, -24), 1.0],
			["garden_gnome", Vector3(-12, 0, -26), 1.0], ["dandelion_a", Vector3(-3, 0, -11), 1.2]]:
		var e := scatter.get_entry(spec[0])
		if not e.is_empty():
			scatter.place(e, spec[1], rng.randf() * TAU, spec[2])
	for i in 500:
		var p := Vector3(rng.randf_range(-30, 30), 0, rng.randf_range(-40, 10))
		if absf(p.x) < 2.5 and p.z > -12 and p.z < 8:
			continue
		scatter.place(scatter.pick("grass", rng), p, rng.randf() * TAU, rng.randf_range(0.7, 1.3))
	for i in 60:
		scatter.place(scatter.pick("flower", rng), Vector3(rng.randf_range(-25, 25), 0, rng.randf_range(-35, 5)), rng.randf() * TAU, rng.randf_range(0.8, 1.2))
	scatter.flush_batches(2)
