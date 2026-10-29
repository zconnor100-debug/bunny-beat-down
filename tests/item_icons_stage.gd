extends Node
## Stage for tests/capture_item_icons.gd: the HUD's item pictures (ItemBadge),
## a lucky clover bottle (in its green glow), an Acorn Shield and a carrot
## grenade, each the game's own model on a clear background, saved to
## assets/ui/item_<name>.png; and its gun pictures (GunBadge), every carrot
## gun and arsenal gun side on, muzzle to the right, saved to
## assets/ui/gun_<id>.png.

const SIZE := 160
const GUN_SIZE := Vector2i(320, 120)
const OUT := "res://assets/ui/"


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var clover := ModelUtil.instantiate(Pickup.MODELS["clover"])
	var glow := ShaderMaterial.new()
	glow.shader = Pickup.CLOVER_SHADER
	glow.set_shader_parameter(&"glow", Pickup.CLOVER_GLOW)
	for gi in ModelUtil.find_all(clover, "GeometryInstance3D"):
		(gi as GeometryInstance3D).material_overlay = glow
	await _render(clover, "item_clover.png")
	await _render(AcornShield.make(), "item_shield.png")
	await _render(Grenade.make_model(), "item_grenade.png")
	for w in WeaponDB.all() + WeaponDB.arsenal():
		var gun := ModelUtil.instantiate(w.model_path)
		if gun:
			await _render(gun, "gun_%s.png" % w.id, GUN_SIZE, _muzzle_yaw(gun))
	get_tree().quit()


## The turn that points `gun`'s muzzle down +X, so seen from +Z it points right.
func _muzzle_yaw(gun: Node3D) -> float:
	var muzzle := ModelUtil.find_named(gun, "Muzzle")
	if muzzle == null:
		return 0.0
	var at := muzzle.position
	var n := muzzle.get_parent()
	while n and n != gun:
		if n is Node3D:
			at = (n as Node3D).transform * at
		n = n.get_parent()
	var d := at - ModelUtil.aabb_of(gun).get_center()
	return atan2(d.z, d.x)


## `model` alone in a little world, lit from the front-left, turned a little
## to show its shape, filling the picture (a gun: `yaw` turns its muzzle down
## +X, and the camera looks at its side).
func _render(model: Node3D, file: String, size := Vector2i(SIZE, SIZE), yaw := NAN) -> void:
	var vp := SubViewport.new()
	vp.size = size
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_8X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.85, 0.85, 0.9)
	e.ambient_light_energy = 0.7
	e.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.environment = e
	vp.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, -40, 0)
	sun.light_energy = 1.6
	vp.add_child(sun)
	var pivot := Node3D.new()
	vp.add_child(pivot)
	pivot.add_child(model)
	pivot.rotation.y = 0.5
	if not is_nan(yaw):
		model.rotation.y = yaw
		pivot.rotation.y = 0.15   # (side on, with a touch of its near face)
	var box := ModelUtil.aabb_of(pivot)
	var cam := Camera3D.new()
	cam.fov = 30.0
	vp.add_child(cam)
	var reach := box.size.length() * 0.5
	if is_nan(yaw):
		cam.position = box.get_center() + Vector3(0, box.size.y * 0.08, reach / tan(deg_to_rad(15.0)) * 1.02)
	else:
		# fit its length to the picture's width (the vertical fov is 30 degrees)
		var tan_v := tan(deg_to_rad(15.0))
		var tan_h := tan_v * float(size.x) / float(size.y)
		cam.position = box.get_center() + Vector3(0, box.size.y * 0.15, maxf(box.size.x * 0.5 / tan_h, box.size.y * 0.5 / tan_v) * 1.1 + box.size.z * 0.5)
	cam.look_at(box.get_center(), Vector3.UP)
	cam.current = true
	for i in 6:
		await get_tree().process_frame
	vp.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT + file))
	print("ICON %s" % file)
	vp.queue_free()
