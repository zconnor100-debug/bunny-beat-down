class_name GraphicsTest
extends Control
## "Test graphics" (Settings): a little scene drawn exactly the way a match
## is (WorldLighting: the quality tier's effects, anti-aliasing and scaling on
## its own view, Graphics.apply_viewport), with what tends to go wrong on a
## troubled graphics card in it: critters moving (skinned, animated), one under
## its glider, the fly agaric and a mossy log (textured models), the forest
## floor, grass and flowers, and water for the reflections. Beside it: what the
## game is running on, the frame rate, quality and anti-aliasing to flip
## through, and buttons that restart the game in another graphics API and come
## straight back here to compare.

signal closed

## `BunnyBeatDown -- --graphics-test`: the main menu opens this at once (a
## restart into another graphics API comes back with it).
const ARG := "--graphics-test"

var _view: SubViewport
var _world: Node3D
var _cam: Camera3D
var _walker: Critter
var _idler: Critter
var _glider: Critter
var _fps: Label
var _info: Label
var _t := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UITheme.theme()
	mouse_filter = Control.MOUSE_FILTER_STOP
	var svc := SubViewportContainer.new()
	svc.stretch = true
	svc.set_anchors_preset(Control.PRESET_FULL_RECT)
	svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(svc)
	_view = SubViewport.new()
	_view.own_world_3d = true
	svc.add_child(_view)
	_world = Node3D.new()
	_view.add_child(_world)
	_build_scene()
	_build_panel()
	Settings.changed.connect(_on_setting)


func _exit_tree() -> void:
	if Settings.changed.is_connected(_on_setting):
		Settings.changed.disconnect(_on_setting)


func _on_setting(key: StringName) -> void:
	if key in Graphics.LIVE_KEYS:
		Graphics.apply_viewport(_view)
		_info.text = _describe()


func _build_scene() -> void:
	var light := WorldLighting.new()
	_world.add_child(light)
	light.build(Graphics.tier())   # (anti-aliasing and scaling land on _view: it's this world's viewport)
	light.sun.rotation_degrees = Vector3(-38, -140, 0)
	light.env.fog_density = 0.008
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(60, 60)
	ground.mesh = plane
	var gm := StandardMaterial3D.new()
	if ResourceLoader.exists("res://assets/textures/forest_floor/albedo.jpg"):
		gm.albedo_texture = load("res://assets/textures/forest_floor/albedo.jpg")
		gm.normal_enabled = true
		gm.normal_texture = load("res://assets/textures/forest_floor/normal.png")
		gm.uv1_scale = Vector3(8, 8, 8)
	ground.material_override = gm
	_world.add_child(ground)
	# a pond, for the reflections
	var pond := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(9, 6)
	pond.mesh = pm
	var water := ShaderMaterial.new()
	water.shader = Island.WATER_SHADER
	if ResourceLoader.exists("res://assets/textures/water/normal.png"):
		water.set_shader_parameter(&"normal_a", load("res://assets/textures/water/normal.png"))
	pond.material_override = water
	pond.position = Vector3(4.5, 0.03, 1.5)
	_world.add_child(pond)
	var scatter := Scatter.new()
	_world.add_child(scatter)
	scatter.load_manifest()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for spec in [["mushroom_fly_agaric", Vector3(-3.0, 0, -3.5), 1.2], ["log_mossy", Vector3(3.5, 0, -5.5), 1.0],
			["fern_a", Vector3(-5.0, 0, -0.5), 1.1], ["tree_oak_a", Vector3(-12, 0, -22), 1.0], ["rock_mossy_a", Vector3(8, 0, -8), 1.0],
			["dandelion_puff", Vector3(-1.5, 0, -6.5), 1.0]]:
		var e := scatter.get_entry(spec[0])
		if not e.is_empty():
			scatter.place(e, spec[1], rng.randf() * TAU, spec[2])
	for i in 160:
		var p := Vector3(rng.randf_range(-13, 13), 0, rng.randf_range(-15, 4))
		if p.distance_to(Vector3(4.5, 0, 1.5)) < 4.0 or p.length() < 2.5:
			continue
		scatter.place(scatter.pick("grass", rng), p, rng.randf() * TAU, rng.randf_range(0.7, 1.2))
	for i in 24:
		scatter.place(scatter.pick("flower", rng), Vector3(rng.randf_range(-11, 11), 0, rng.randf_range(-13, 1)), rng.randf() * TAU, 1.0)
	scatter.flush_batches(Graphics.tier())
	# critters: one idling with a gun, one walking round, one under its glider
	_idler = _critter(String(Settings.get_value(&"player_character")), Vector3(3.6, 0.05, -0.6), PI * 0.8)
	_idler.give_weapon(WeaponInstance.new(WeaponDB.get_weapon(&"carrot_lmg"), Rarity.Tier.GOLDEN))
	_walker = _critter("raccoon", Vector3(2, 0.05, -2), 0.0)
	Outfits.dress(_walker, "Trash Panda")
	_glider = _critter("fox", Vector3(2.0, 2.2, -3.2), 0.0)
	_glider.state = Critter.State.GLIDING   # (a preview: it hangs there, legs dangling)
	_glider.visual.set_glider(true)
	_cam = Camera3D.new()
	_cam.fov = 55.0
	_world.add_child(_cam)
	_cam.current = true


func _critter(id: String, at: Vector3, yaw: float) -> Critter:
	var c := Critter.new()
	c.preview = true
	var def: CritterDef = load("res://data/critters/%s.tres" % id)
	c.def = def if def else load("res://data/critters/bun.tres")
	c.display_name = c.def.display_name
	_world.add_child(c)
	c.place_at(at, yaw)
	return c


func _process(delta: float) -> void:
	_t += delta
	if _cam:
		# a slow swing round the scene, kept to the right of the panel
		var a := 0.35 + sin(_t * 0.12) * 0.55
		_cam.position = Vector3(sin(a) * 8.5, 2.3 + sin(_t * 0.3) * 0.3, cos(a) * 8.5)
		var right := _cam.global_basis.x if _cam.is_inside_tree() else Vector3.RIGHT
		_cam.look_at(Vector3(0, 1.1, -1.5) - right * 2.4, Vector3.UP)
	if _walker:
		# round and round the mushroom
		var w := _t * 0.5
		_walker.position = Vector3(cos(w) * 2.6 - 1.0, 0.05, sin(w) * 2.6 - 2.0)
		_walker.look_yaw = -w
		_walker.rotation.y = -w
		_walker.move_input = Vector2(0, 1)
	if _glider:
		_glider.position.y = 2.2 + sin(_t * 0.8) * 0.25
		_glider.look_yaw = _t * 0.4
		_glider.rotation.y = _t * 0.4
	if _fps:
		_fps.text = "%d FPS" % Engine.get_frames_per_second()


func _build_panel() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT)
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.offset_left = 30.0
	panel.custom_minimum_size = Vector2(520, 0)
	add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	panel.add_child(v)
	v.add_child(UITheme.label("Graphics check", 40, UITheme.CARROT_LIGHT, true))
	_info = UITheme.label(_describe(), 18)
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_info)
	_fps = UITheme.label("", 22, UITheme.LEAF, true)
	v.add_child(_fps)
	var tip := UITheme.label("The critters, the mushroom and the ground should look like they do in a match. Moving models "
		+ "turned to blocky noise, or surfaces flat black? Try another graphics API: the game restarts straight back here.",
		16, Color(UITheme.CREAM, 0.8))
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(tip)
	var quality := HBoxContainer.new()
	quality.add_theme_constant_override("separation", 8)
	v.add_child(quality)
	quality.add_child(UITheme.button("Quality ◀ ▶", func(): _cycle(&"quality", Graphics.TIER_NAMES.size())))
	quality.add_child(UITheme.button("Anti-aliasing ◀ ▶", func(): _cycle(&"anti_aliasing", Graphics.AA_NAMES.size())))
	quality.add_child(UITheme.button("Scaling ◀ ▶", func(): _cycle(&"upscaling", Graphics.UPSCALE_NAMES.size())))
	var apis := HBoxContainer.new()
	apis.add_theme_constant_override("separation", 8)
	v.add_child(apis)
	for api in Graphics.API_NAMES.size():
		if api == 1 and OS.get_name() != "Windows":
			continue   # (Direct3D 12 is Windows only)
		var b := UITheme.button(String(Graphics.API_NAMES[api]).get_slice(" (", 0), restart_into.bind(api))
		b.disabled = api == current_api()
		apis.add_child(b)
	var back := UITheme.button("Back", func(): closed.emit())
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(back)
	back.grab_focus.call_deferred()


func _cycle(key: StringName, n: int) -> void:
	Settings.set_value(key, (int(Settings.get_value(key)) + 1) % n)


func _describe() -> String:
	var aa := int(Settings.get_value(&"anti_aliasing"))
	return "Running on %s\nQuality: %s · Anti-aliasing: %s\nScaling: %s" % [Graphics.running_on(),
		Graphics.TIER_NAMES[Graphics.tier()], Graphics.AA_NAMES[clampi(aa, 0, Graphics.AA_NAMES.size() - 1)],
		Graphics.UPSCALE_NAMES[clampi(int(Settings.get_value(&"upscaling")), 0, Graphics.UPSCALE_NAMES.size() - 1)]]


## Which of Graphics.API_NAMES the game is running on now.
static func current_api() -> int:
	if RenderingServer.get_current_rendering_method() == "gl_compatibility":
		return 2
	return 1 if RenderingServer.get_current_rendering_driver_name() == "d3d12" else 0


## Restart the game in graphics API `api`, back on this screen. (Not in
## automated runs: those just note the choice.)
func restart_into(api: int) -> void:
	Settings.set_value(&"graphics_api", api)
	if Settings.is_test_run():
		return
	OS.set_restart_on_exit(true, ["--", ARG])
	get_tree().quit()
