extends Node
## Stage for tests/capture_item_icons.gd: the HUD's item pictures (ItemBadge),
## a lucky clover bottle (in its green glow) and an Acorn Shield, each the
## pickup's own model on a clear background, saved to assets/ui/item_<name>.png.

const SIZE := 160
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
	get_tree().quit()


## `model` alone in a little world, lit from the front-left, turned a little
## to show its shape, filling the picture.
func _render(model: Node3D, file: String) -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(SIZE, SIZE)
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
	var box := ModelUtil.aabb_of(pivot)
	var cam := Camera3D.new()
	cam.fov = 30.0
	vp.add_child(cam)
	var reach := box.size.length() * 0.5
	cam.position = box.get_center() + Vector3(0, box.size.y * 0.08, reach / tan(deg_to_rad(15.0)) * 1.02)
	cam.look_at(box.get_center(), Vector3.UP)
	cam.current = true
	for i in 6:
		await get_tree().process_frame
	vp.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT + file))
	print("ICON %s" % file)
	vp.queue_free()
