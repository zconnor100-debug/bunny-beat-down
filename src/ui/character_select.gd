class_name CharacterSelect
extends PanelContainer
## Pick your critter and skin. The preview is a real Critter (same model,
## procedural animator, carrot gun and jump trick as in a match) rendered in its
## own SubViewport world, slowly turning on a little patch of forest floor.
## The choice is saved to Settings (player_character / player_skin).

signal confirmed

const ROSTER := ["bun", "bandit_bunny", "squirrel", "fox", "raccoon", "frog", "beaver", "hamster"]

var ready_to_drop := false:
	set(v):
		ready_to_drop = v
		if _go:
			_go.disabled = not v
			_go.text = "Drop in!" if v else "Growing the island…"

var _index := 0
var _skin_index := 0
var _defs: Array[CritterDef] = []
var _viewport: SubViewport
var _stage: Node3D
var _preview: Critter
var _turntable: Node3D
var _name: Label
var _skin_label: Label
var _blurb: Label
var _stats: Label
var _go: Button
var _t := 0.0
var _next_trick := 2.5


func _ready() -> void:
	theme = UITheme.theme()
	custom_minimum_size = Vector2(980, 0)
	for id in ROSTER:
		var d: CritterDef = load("res://data/critters/%s.tres" % id)
		if d:
			_defs.append(d)
	var cur := String(Settings.get_value(&"player_character"))
	for i in _defs.size():
		if String(_defs[i].id) == cur:
			_index = i

	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 26)
	add_child(h)
	# --- 3D preview
	var svc := SubViewportContainer.new()
	svc.stretch = true
	svc.custom_minimum_size = Vector2(420, 460)
	h.add_child(svc)
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_viewport.msaa_3d = Viewport.MSAA_4X
	svc.add_child(_viewport)
	_build_stage()
	# --- details
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	v.add_child(UITheme.label("Choose your critter", 40, UITheme.CARROT_LIGHT, true))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.add_child(UITheme.button("◀", func(): _cycle(-1)))
	_name = UITheme.label("", 38, UITheme.CREAM, true)
	_name.custom_minimum_size = Vector2(300, 0)
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(_name)
	row.add_child(UITheme.button("▶", func(): _cycle(1)))
	v.add_child(row)
	var srow := HBoxContainer.new()
	srow.add_theme_constant_override("separation", 12)
	srow.add_child(UITheme.button("◀", func(): _cycle_skin(-1)))
	_skin_label = UITheme.label("", 24)
	_skin_label.custom_minimum_size = Vector2(300, 0)
	_skin_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	srow.add_child(_skin_label)
	srow.add_child(UITheme.button("▶", func(): _cycle_skin(1)))
	v.add_child(srow)
	_blurb = UITheme.label("", 20, Color(UITheme.CREAM, 0.9))
	_blurb.autowrap_mode = TextServer.AUTOWRAP_WORD
	_blurb.custom_minimum_size = Vector2(480, 0)
	v.add_child(_blurb)
	_stats = UITheme.label("", 19, Color(UITheme.CREAM, 0.8))
	v.add_child(_stats)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(spacer)
	_go = UITheme.button("Growing the island…", func(): confirmed.emit())
	_go.custom_minimum_size = Vector2(320, 64)
	_go.size_flags_horizontal = Control.SIZE_SHRINK_END
	v.add_child(_go)
	ready_to_drop = ready_to_drop
	_show()


func _build_stage() -> void:
	_stage = Node3D.new()
	_viewport.add_child(_stage)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.75, 0.8, 0.9)
	e.ambient_light_energy = 0.6
	e.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.environment = e
	_stage.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, -30, 0)
	sun.light_energy = 1.5
	sun.shadow_enabled = true
	_stage.add_child(sun)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-10, 160, 0)
	rim.light_energy = 0.9
	rim.light_color = Color(1.0, 0.85, 0.6)
	_stage.add_child(rim)
	# a round patch of forest floor to stand on
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = Layers.WORLD
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 1.4
	cyl.height = 0.2
	cs.shape = cyl
	cs.position.y = -0.1
	floor_body.add_child(cs)
	var disc := MeshInstance3D.new()
	var dm := CylinderMesh.new()
	dm.top_radius = 1.3
	dm.bottom_radius = 1.4
	dm.height = 0.2
	var gm := StandardMaterial3D.new()
	if ResourceLoader.exists("res://assets/textures/moss/albedo.jpg"):
		gm.albedo_texture = load("res://assets/textures/moss/albedo.jpg")
		gm.uv1_scale = Vector3(2, 2, 2)
	else:
		gm.albedo_color = Color(0.3, 0.45, 0.2)
	dm.material = gm
	disc.mesh = dm
	disc.position.y = -0.1
	floor_body.add_child(disc)
	_stage.add_child(floor_body)
	_turntable = Node3D.new()
	_stage.add_child(_turntable)
	var cam := Camera3D.new()
	cam.fov = 30
	_stage.add_child(cam)
	cam.position = Vector3(0, 1.05, 3.3)
	cam.look_at(Vector3(0, 0.68, 0), Vector3.UP)
	cam.current = true


func _show() -> void:
	var d := _defs[_index]
	if _preview:
		_preview.queue_free()
	_preview = Critter.new()
	_preview.preview = true
	_preview.def = d
	_preview.display_name = d.display_name
	_stage.add_child(_preview)
	_preview.place_at(Vector3(0, 0.05, 0), 0.0)
	_preview.give_weapon(WeaponInstance.new(WeaponDB.get_weapon(&"carrot_rifle"), Rarity.Tier.PRIZE))
	var skins := d.skins()
	var cur_skin := String(Settings.get_value(&"player_skin"))
	_skin_index = 0
	for i in skins.size():
		if skins[i].get("id") == cur_skin:
			_skin_index = i
	_apply_skin()
	_name.text = d.display_name
	var helmet := " Comes with the acorn helmet." if d.wears_acorn_helmet else ""
	_blurb.text = "Jump trick: %s.%s" % [d.jump_blurb(), helmet]
	_stats.text = "Speed %s   •   Jump %s   •   Size %.2f m" % [_bar(d.move_speed / 7.2), _bar(d.jump_height / 2.6),
		_preview.visual.rig.world_head_top if _preview.visual.rig else 1.0]
	Settings.set_value(&"player_character", String(d.id))
	_next_trick = 1.5


func _apply_skin() -> void:
	var skins := _defs[_index].skins()
	var s: Dictionary = skins[_skin_index % skins.size()]
	_preview.visual.apply_skin(String(s.get("id", "default")))
	_skin_label.text = "Skin: %s  (%d/%d)" % [s.get("name", "Classic"), _skin_index % skins.size() + 1, skins.size()]
	Settings.set_value(&"player_skin", String(s.get("id", "default")))


func _bar(v: float) -> String:
	var n := clampi(roundi(v * 5.0), 1, 5)
	return "●".repeat(n) + "○".repeat(5 - n)


func _cycle(step: int) -> void:
	_index = posmod(_index + step, _defs.size())
	Settings.set_value(&"player_skin", "default", false)
	_show()


func _cycle_skin(step: int) -> void:
	var n := _defs[_index].skins().size()
	_skin_index = posmod(_skin_index + step, n)
	_apply_skin()


func _process(delta: float) -> void:
	if _preview == null or not is_instance_valid(_preview):
		return
	_t += delta
	# turn slowly to show the critter off; hop now and then to show the trick
	var yaw := sin(_t * 0.5) * 0.9
	_preview.look_yaw = yaw
	_preview.rotation.y = yaw
	_preview.aim_point = _preview.get_eye_position() + _preview.look_direction() * 6.0
	_next_trick -= delta
	if _next_trick <= 0.0:
		_next_trick = 3.5
		_preview.want_jump = true


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"move_left") or event.is_action_pressed(&"weapon_prev"):
		_cycle(-1)
	elif event.is_action_pressed(&"move_right") or event.is_action_pressed(&"weapon_next"):
		_cycle(1)
	elif event.is_action_pressed(&"move_forward"):
		_cycle_skin(1)
	elif event.is_action_pressed(&"jump") and ready_to_drop:
		confirmed.emit()
