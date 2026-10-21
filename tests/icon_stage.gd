extends Node3D
## Renders the app icon: Bun in the acorn helmet, holding a golden carrot gun,
## on a transparent background. Run via tests/capture_icon.gd.

var out_path := "res://icon.png"
var size := 1024


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var vp := get_viewport()
	vp.transparent_bg = true
	var light := WorldLighting.new()
	add_child(light)
	light.build(3)
	light.env.background_mode = Environment.BG_CLEAR_COLOR
	light.env.fog_enabled = false
	light.sun.rotation_degrees = Vector3(-30, -35, 0)
	light.sun.light_energy = 1.6
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-15, 150, 0)
	rim.light_energy = 1.2
	rim.light_color = Color(1.0, 0.85, 0.6)
	add_child(rim)
	add_child(FX.new())
	add_child(Projectiles.new())
	var ground := StaticBody3D.new()
	ground.collision_layer = Layers.WORLD
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(10, 1, 10)
	cs.shape = box
	cs.position.y = -0.5
	ground.add_child(cs)
	add_child(ground)

	var bun := Critter.new()
	bun.def = load("res://data/critters/bun.tres")
	add_child(bun)
	bun.place_at(Vector3(0, 0.02, 0), 0.0)
	bun.give_weapon(WeaponInstance.new(WeaponDB.get_weapon(&"carrot_lmg"), Rarity.Tier.PRIZE))
	var cam := Camera3D.new()
	cam.fov = 44
	add_child(cam)
	cam.current = true
	# waist-up hero shot from the front-left; the gun is held across, in profile
	cam.global_position = Vector3(0.75, 1.0, -2.25)
	cam.look_at(Vector3(-0.12, 0.66, 0), Vector3.UP)
	var right := cam.global_basis.x
	var fwd := -cam.global_basis.z
	var d := (-right * 0.62 - fwd * 0.78).normalized()
	for i in 60:
		bun.look_yaw = atan2(-d.x, -d.z)
		bun.look_pitch = deg_to_rad(8.0)
		bun.aim_point = bun.get_eye_position() + bun.look_direction() * 6.0
		await get_tree().process_frame
	var img := vp.get_texture().get_image()
	# crop to everything that was drawn (Bun + gun), as a padded square
	var used := img.get_used_rect()
	var side := int(maxf(used.size.x, used.size.y) * 1.08)
	var c := used.get_center()
	var sq := Rect2i(int(c.x - side / 2.0), int(c.y - side / 2.0), side, side)
	var canvas := Image.create_empty(side, side, false, Image.FORMAT_RGBA8)
	canvas.blit_rect(img, sq.intersection(Rect2i(Vector2i.ZERO, img.get_size())), Vector2i(maxi(0, -sq.position.x), maxi(0, -sq.position.y)))
	img = canvas
	img.resize(size, size, Image.INTERPOLATE_LANCZOS)
	img.save_png(out_path)
	print("wrote ", out_path)
	get_tree().quit()
