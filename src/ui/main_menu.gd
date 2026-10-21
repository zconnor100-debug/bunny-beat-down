extends Node3D
## Title screen: a little woodland diorama with Bun idling in the foreground
## (the same procedural animator as in-game) and the menu on the left.

const GAME_SCENE := "res://scenes/game.tscn"

var _ui: Control
var _menu: VBoxContainer
var _overlay: Control
var _cam: Camera3D
var _bun: Critter
var _t := 0.0


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = false
	# `BunnyBeatDown -- --quick-match` (or --smoke-test) skips straight into a match
	var args := OS.get_cmdline_user_args()
	if args.has("--quick-match") or args.has("--smoke-test"):
		get_tree().change_scene_to_file.call_deferred(GAME_SCENE)
		return
	_build_diorama()
	_build_ui()
	Audio.play_music("menu")


func _build_diorama() -> void:
	var light := WorldLighting.new()
	add_child(light)
	light.build(int(Settings.get_value(&"quality")))
	light.sun.rotation_degrees = Vector3(-35, -140, 0)
	light.env.fog_density = 0.01
	var fx := FX.new()
	add_child(fx)
	var proj := Projectiles.new()
	add_child(proj)
	# a patch of forest floor
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
	else:
		gm.albedo_color = Color(0.3, 0.25, 0.16)
	ground.material_override = gm
	add_child(ground)
	var body := StaticBody3D.new()
	body.collision_layer = Layers.WORLD
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60, 1, 60)
	cs.shape = box
	cs.position.y = -0.5
	body.add_child(cs)
	add_child(body)
	var scatter := Scatter.new()
	add_child(scatter)
	scatter.load_manifest()
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for spec in [["mushroom_fly_agaric", Vector3(-3.2, 0, -4.0), 1.2], ["log_mossy", Vector3(4.5, 0, -6.0), 1.0],
			["fern_a", Vector3(-5.5, 0, -1.0), 1.1], ["fern_b", Vector3(2.8, 0, -2.2), 1.0], ["tree_oak_a", Vector3(10, 0, -30), 1.0],
			["acorn", Vector3(1.2, 0, 0.6), 1.0], ["dandelion_puff", Vector3(-2.0, 0, -7.5), 1.0], ["rock_mossy_a", Vector3(-8, 0, -9), 1.0]]:
		var e := scatter.get_entry(spec[0])
		if not e.is_empty():
			scatter.place(e, spec[1], rng.randf() * TAU, spec[2])
	for i in 220:
		var p := Vector3(rng.randf_range(-14, 14), 0, rng.randf_range(-16, 4))
		if p.length() < 1.6:
			continue
		scatter.place(scatter.pick("grass", rng), p, rng.randf() * TAU, rng.randf_range(0.7, 1.2))
	for i in 30:
		scatter.place(scatter.pick("flower", rng), Vector3(rng.randf_range(-12, 12), 0, rng.randf_range(-14, 2)), rng.randf() * TAU, rng.randf_range(0.7, 1.1))
	scatter.flush_batches(2)

	_bun = Critter.new()
	_bun.def = load("res://data/critters/bun.tres")
	_bun.display_name = "Bun"
	add_child(_bun)
	_bun.place_at(Vector3(0, 0.05, 0), PI * 0.85)
	_bun.give_weapon(WeaponInstance.new(WeaponDB.get_weapon(&"carrot_lmg"), Rarity.Tier.GOLDEN))

	_cam = Camera3D.new()
	_cam.fov = 50
	add_child(_cam)
	_cam.current = true


func _process(delta: float) -> void:
	_t += delta
	if _cam and _bun:
		var a := 0.55 + sin(_t * 0.15) * 0.2
		_cam.global_position = Vector3(sin(a) * 3.6, 1.15, cos(a) * 3.6)
		_cam.look_at(Vector3(-0.9, 0.62, 0), Vector3.UP)
		# Bun glances around, gun ready
		_bun.look_yaw = PI * 0.85 + sin(_t * 0.6) * 0.35
		_bun.look_pitch = sin(_t * 0.43) * 0.12
		_bun.aim_point = _bun.get_eye_position() + _bun.look_direction() * 10.0


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_ui = Control.new()
	_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui.theme = UITheme.theme()
	layer.add_child(_ui)
	var shade := TextureRect.new()
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, 0.65))
	g.set_color(1, Color(0, 0, 0, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_to = Vector2(0.6, 0)
	shade.texture = gt
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(shade)

	_menu = VBoxContainer.new()
	_menu.position = Vector2(110, 150)
	_menu.add_theme_constant_override("separation", 16)
	_ui.add_child(_menu)
	var title := UITheme.label("BUNNY\nBEAT DOWN", 112, UITheme.CARROT, true)
	title.add_theme_constant_override("line_spacing", -26)
	_menu.add_child(title)
	var tag := UITheme.label("One bunny. One acorn helmet. A whole lot of carrots.", 24, UITheme.CREAM)
	_menu.add_child(tag)
	_menu.add_child(Control.new())
	for item in [["Play", _open_play], ["Settings", _open_settings], ["Credits", _open_credits], ["Quit", func(): get_tree().quit()]]:
		var b := UITheme.button(item[0], item[1])
		b.custom_minimum_size = Vector2(320, 64)
		b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		_menu.add_child(b)
	(_menu.get_child(3) as Button).grab_focus.call_deferred()
	var ver := UITheme.label("v%s  •  Godot %s" % [ProjectSettings.get_setting("application/config/version"), Engine.get_version_info().string], 16, Color(UITheme.CREAM, 0.7))
	ver.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	ver.offset_left = 24
	ver.offset_top = -40
	_ui.add_child(ver)


func _show_overlay(panel: Control) -> void:
	if _overlay:
		_overlay.queue_free()
	_menu.visible = false
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.add_child(panel)
	_ui.add_child(center)
	_overlay = center


func _close_overlay() -> void:
	if _overlay:
		_overlay.queue_free()
		_overlay = null
	_menu.visible = true


func _open_settings() -> void:
	var p := SettingsPanel.new()
	p.closed.connect(_close_overlay)
	_show_overlay(p)


func _open_credits() -> void:
	var p := CreditsPanel.new()
	p.closed.connect(_close_overlay)
	_show_overlay(p)


func _open_play() -> void:
	var panel := PanelContainer.new()
	panel.theme = UITheme.theme()
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	panel.add_child(v)
	var t := UITheme.label("New match", 50, UITheme.CARROT_LIGHT, true)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 30)
	grid.add_theme_constant_override("v_separation", 12)
	v.add_child(grid)
	grid.add_child(UITheme.label("Opponents", 22))
	var opp := SpinBox.new()
	opp.min_value = 1
	opp.max_value = 49
	opp.value = Settings.get_value(&"opponents")
	opp.value_changed.connect(func(x): Settings.set_value(&"opponents", int(x)))
	grid.add_child(opp)
	grid.add_child(UITheme.label("Difficulty", 22))
	var diff := OptionButton.new()
	for d in ["Sleepy", "Scrappy", "Savage"]:
		diff.add_item(d)
	diff.selected = int(Settings.get_value(&"difficulty"))
	diff.item_selected.connect(func(i): Settings.set_value(&"difficulty", i))
	grid.add_child(diff)
	grid.add_child(UITheme.label("Island seed (0 = random)", 22))
	var seed_box := SpinBox.new()
	seed_box.min_value = 0
	seed_box.max_value = 999999
	seed_box.value = Settings.get_value(&"seed")
	seed_box.value_changed.connect(func(x): Settings.set_value(&"seed", int(x)))
	grid.add_child(seed_box)
	grid.add_child(UITheme.label("Quick match (faster Briar)", 22))
	var quick := CheckButton.new()
	quick.button_pressed = GameSession.quick
	quick.toggled.connect(func(on): GameSession.quick = on)
	grid.add_child(quick)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 20)
	row.add_child(UITheme.button("Back", _close_overlay))
	var go := UITheme.button("Drop in!", func(): get_tree().change_scene_to_file(GAME_SCENE))
	row.add_child(go)
	v.add_child(row)
	_show_overlay(panel)
	go.grab_focus.call_deferred()
