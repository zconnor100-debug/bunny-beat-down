class_name CritterPortrait
extends Control
## A critter on a little turntable, in its own 3D world: a real Critter (the
## same model, animator, outfit and gun as in a match), slowly turning, that
## the mouse can spin. The Rogues' Gallery shows each rogue in its outfit
## with its favourite gun; the Workshop shows you in your wardrobe.

const SPIN_SPEED := 0.45             ## radians a second when left alone
const SPIN_PER_PIXEL := TAU / 420.0

var _viewport: SubViewport
var _stage: Node3D
var _cam: Camera3D
var _critter: Critter
var _key := ""                       # what's shown (so showing it again does nothing)
var _spin := 0.0
var _dragging := false


func _init(min_size := Vector2(320, 360)) -> void:
	custom_minimum_size = min_size


func _ready() -> void:
	var svc := SubViewportContainer.new()
	svc.stretch = true
	svc.set_anchors_preset(Control.PRESET_FULL_RECT)
	svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(svc)
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_viewport.msaa_3d = Viewport.MSAA_4X
	svc.add_child(_viewport)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_DRAG
	_build_stage()


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
	_cam = Camera3D.new()
	_cam.fov = 30
	_stage.add_child(_cam)
	_cam.current = true


## One of the cast, in its fur and outfit, holding its favourite gun.
func show_rogue(rogue: String) -> void:
	var m := Cast.member(rogue)
	if m.is_empty():
		return
	_show("rogue:" + rogue, String(m.species), func(c: Critter):
		var gun := WeaponDB.get_weapon(StringName(m.weapon))
		if gun:
			c.give_weapon(WeaponInstance.new(gun, Rarity.Tier.PRIZE))
		Outfits.dress(c, rogue))


## You: your critter and skin (Settings), wearing `wear` (Outfits pieces).
func show_player(wear: Array) -> void:
	var id := String(Settings.get_value(&"player_character"))
	_show("you:%s:%s:%s" % [id, Settings.get_value(&"player_skin"), ",".join(wear)], id, func(c: Critter):
		c.visual.apply_skin(String(Settings.get_value(&"player_skin")))
		c.give_weapon(WeaponInstance.new(WeaponDB.get_weapon(&"carrot_rifle"), Rarity.Tier.PRIZE))
		Outfits.dress_player(c, wear))


func shown_critter() -> Critter:
	return _critter


func _show(key: String, def_id: String, dress: Callable) -> void:
	if key == _key and is_instance_valid(_critter):
		return
	_key = key
	if _stage == null:
		await ready
	if is_instance_valid(_critter):
		_critter.queue_free()
	var def: CritterDef = load("res://data/critters/%s.tres" % def_id)
	if def == null:
		return
	_critter = Critter.new()
	_critter.preview = true
	_critter.def = def
	_critter.display_name = def.display_name
	_stage.add_child(_critter)
	_critter.place_at(Vector3(0, 0.05, 0), PI)
	dress.call(_critter)
	_critter._unhurt_t = 99.0   # (calm: the gun carried low, out of the way of the face)
	_critter.visual.poser.relax()
	var h: float = _critter.visual.rig.world_head_top if _critter.visual.rig else 1.33
	# a tall, narrow frame needs the camera further back to fit the critter's width
	var back := 2.9 * maxf(1.0, 0.8 * size.y / maxf(size.x, 1.0)) if size.x > 0.0 else 2.9
	_cam.position = Vector3(0, 0.62, back) * h
	_cam.look_at(Vector3(0, 0.56 * h, 0), Vector3.UP)


func _process(delta: float) -> void:
	if not is_instance_valid(_critter):
		return
	if not _dragging:
		_spin = wrapf(_spin + SPIN_SPEED * delta, -PI, PI)
	var yaw := PI + _spin
	_critter.look_yaw = yaw
	_critter.rotation.y = yaw
	_critter.aim_point = _critter.get_eye_position() + Basis(Vector3.UP, yaw + 0.65) * Vector3(0, 0.05, -1) * 6.0


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		accept_event()
	elif event is InputEventMouseMotion and _dragging:
		_spin = wrapf(_spin + event.relative.x * SPIN_PER_PIXEL, -PI, PI)
		accept_event()
