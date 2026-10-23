extends Node
## The 30-second trailer: a rival sneaks up on you, beats you down, and you
## rewind and turn around. Directed (the shots and the two critters' inputs
## are scripted) but every piece is the real game: the island, the balloon,
## the rival's name tag and taunts, the killing-blow prompt and the rewind.
## Started by tests/capture_trailer.gd (see there for the command lines).

const FPS := 30.0
const SEED := 4242
const STAGE_POI := "Carrot Patch"

var out_dir := ""
var preview := false
var _t := 0.0                     # trailer time (s), counted in frames
var _stills := [2.5, 6.0, 9.0, 12.0, 15.0, 18.0, 21.0, 25.0]
var game: Node
var mm: MatchManager
var bun: Critter
var vex: Critter
var cam: Camera3D
var _cap: CanvasLayer
var _title: Label
var _sub: Label
var _lower: Label
var _card: ColorRect


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # (keeps directing while the match is frozen)
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		out_dir = a[0]
		DirAccess.make_dir_recursive_absolute(out_dir)
	preview = a.has("preview")
	_run.call_deferred()


func _frame() -> void:
	GameInput.using_pad = false   # (prompts say [T], not "pause menu", even with a pad plugged in)
	await get_tree().process_frame
	_t += 1.0 / FPS
	if preview and not _stills.is_empty() and _t >= _stills[0]:
		_stills.pop_front()
		var img := get_tree().root.get_viewport().get_texture().get_image()
		img.save_png(out_dir.path_join("trailer_%04.1f.png" % _t))


func _until(t: float, each := Callable()) -> void:
	while _t < t:
		if each.is_valid():
			each.call()
		await _frame()


func _run() -> void:
	var settings: Node = get_tree().root.get_node("Settings")
	settings.set_value(&"quality", 2, false)
	settings.set_value(&"opponents", 9, false)
	settings.set_value(&"difficulty", 1, false)
	settings.set_value(&"seed", SEED, false)
	settings.set_value(&"map", "island", false)
	settings.set_value(&"camera_mode", Settings.CameraMode.THIRD_PERSON, false)
	settings.set_value(&"player_character", "bun", false)
	# the rival: a sneaky fox who has beaten you three times (test save files)
	RivalBook.reset_for_tests()
	PlayerProfile.reset_for_tests()
	var fox: CritterDef = load("res://data/critters/fox.tres")
	var rival_name := ""
	for n in fox.names:
		if RivalBook.personality_of(n) == "sneak":
			rival_name = n
			break
	for i in 3:
		RivalBook.note_you_died_to(rival_name, "fox")
	# pads drive every Godot window on the machine: this one ignores them
	for action in InputMap.get_actions():
		for e in InputMap.action_get_events(action):
			if e is InputEventJoypadButton or e is InputEventJoypadMotion:
				InputMap.action_erase_event(action, e)
	get_tree().root.gui_disable_input = true
	get_tree().change_scene_to_file("res://scenes/game.tscn")
	while game == null or game.get("hud") == null:
		await get_tree().process_frame
		game = get_tree().current_scene
	mm = game.match_manager
	bun = mm.player
	vex = mm.critters.filter(func(c): return c.display_name == rival_name)[0]
	game.hud.visible = false
	game.set_process_unhandled_input(false)
	bun.get_node("PlayerController").process_mode = Node.PROCESS_MODE_DISABLED   # (Bun is directed too)
	mm.time_keeper.offered.connect(game._offer_rewind)   # (automated runs don't ask by default)
	_build_captions()
	print("TRAILER_START (rival %s)" % rival_name)

	# 1. the balloon, and the title
	game.rig.pitch = -0.25
	_fade(_title, 1.0, 0.6)
	_fade(_sub, 1.0, 1.0)
	await _until(3.6)
	_fade(_title, 0.0, 0.3)
	_fade(_sub, 0.0, 0.3)
	await _until(4.0)

	# 2. the stage: Bun busy at a chest at the Carrot Patch, the rival in the
	# leaves behind
	var poi: Dictionary = game.island.pois[0]
	for p in game.island.pois:
		if p.name == STAGE_POI:
			poi = p
	var c2: Vector2 = poi.center
	var spot := _ground(Vector3(c2.x + 6.0, 0, c2.y + 6.0))
	for c in mm.critters.duplicate():
		mm.dropship.eject(c)
	var face := 0.6                                   # Bun's yaw: looking at the chest
	for k in 16:
		var yaw := 0.6 + k * TAU / 16.0
		var f := -Basis(Vector3.UP, yaw).z
		if _clear(spot, spot - f * 14.0 + f.cross(Vector3.UP) * 2.0) and _clear(spot, spot + f * 2.5):
			face = yaw
			break
	var fwd := -Basis(Vector3.UP, face).z
	_place(bun, spot, face)
	var chest := TreasureChest.new(true)
	mm.world_root.add_child(chest)
	chest.global_position = _ground(spot + fwd * 1.8)
	chest.rotation.y = face + PI
	bun.give_weapon(WeaponInstance.new(WeaponDB.get_weapon(&"carrot_shotgun"), Rarity.Tier.GOLDEN))
	bun.inventory.add_ammo(WeaponData.AmmoType.SHELLS, 30)
	var vex_start := _ground(spot - fwd * 13.0 + fwd.cross(Vector3.UP) * 2.0)
	_place(vex, vex_start, face)
	vex.get_node("AIBrain").process_mode = Node.PROCESS_MODE_DISABLED
	vex.give_weapon(WeaponInstance.new(WeaponDB.get_weapon(&"carrot_shotgun"), Rarity.Tier.PRIZE))
	vex.inventory.add_ammo(WeaponData.AmmoType.SHELLS, 30)
	game.rig.yaw = face
	game.rig.pitch = -0.15
	bun.look_yaw = face
	cam = Camera3D.new()
	cam.fov = 58.0
	mm.world_root.add_child(cam)
	cam.make_current()
	_lower.text = "%s has beaten you down 3 times.\n%s remembers." % [rival_name, rival_name]
	_fade(_lower, 1.0, 0.5)
	var creep := func():
		vex.want_crouch = true
		vex.want_sprint = false
		var to := bun.global_position - vex.global_position
		vex.look_yaw = atan2(-to.x, -to.z)
		vex.look_pitch = 0.0
		vex.move_input = Vector2(0, 1) if to.length() > 6.0 else Vector2.ZERO
		_over_shoulder(vex, bun)
	await _until(6.2, creep)
	vex.visual.say(RivalBook.PERSONALITIES.sneak.spot[2].format({"you": bun.display_name}), 3.5)   # "Don't turn around, Bun."
	await _until(9.0, creep)
	_fade(_lower, 0.0, 0.4)
	await _until(10.2, creep)

	# 3. the pounce: the killing blow freezes the match and asks
	vex.want_crouch = false
	vex.move_input = Vector2.ZERO
	bun.health = 12.0
	bun.armor = 0.0
	var shoot := func():
		var aim := bun.get_chest_position()
		var to := aim - vex.get_eye_position()
		vex.look_yaw = atan2(-to.x, -to.z)
		vex.look_pitch = asin(clampf(to.normalized().y, -1.0, 1.0))
		vex.aim_point = aim
		vex.want_fire = true
		_over_shoulder(vex, bun)
	while mm.time_keeper.pending == null and _t < 13.0:
		shoot.call()
		await _frame()
	vex.want_fire = false
	await _until(_t + 2.6)
	game.hud.visible = true
	game._answer_offer(true)

	# 4. ten seconds earlier, and this time Bun turns around
	game.rig.camera.make_current()
	game.rig.yaw = face
	game.rig.pitch = -0.12
	bun.look_yaw = face
	bun.look_pitch = 0.0
	var t_rw := _t
	await _until(t_rw + 1.4, creep_quiet.bind(vex, bun))
	var turn := func():
		creep_quiet(vex, bun)
		# aim from Bun's eyes, not the orbiting camera (that feeds back on itself)
		var d: Vector3 = (vex.get_chest_position() - bun.get_eye_position()).normalized()
		game.rig.yaw = lerp_angle(game.rig.yaw, atan2(-d.x, -d.z), 0.09)
		game.rig.pitch = lerpf(game.rig.pitch, asin(d.y), 0.09)
		bun.look_yaw = game.rig.yaw
		bun.look_pitch = game.rig.pitch
		bun.aim_point = vex.get_chest_position()
	await _until(t_rw + 2.6, turn)
	vex.move_input = Vector2.ZERO
	vex.visual.say("...!", 1.5)
	vex.health = minf(vex.health, 30.0)   # (a blast or two at this range, for the cut)
	for i in 4:
		if not vex.alive:
			break
		bun.want_fire = true
		await _frame()
		await _frame()
		bun.want_fire = false
		await _until(_t + 0.85, turn)
	# look down over the carrot tops at the fallen rival
	await _until(t_rw + 6.6, func(): game.rig.pitch = lerpf(game.rig.pitch, -0.42, 0.04))
	game.hud.visible = false
	_lower.text = "Rivals with grudges · three rewinds a match · perks that carry over"
	_fade(_lower, 1.0, 0.5)
	await _until(t_rw + 10.0, func(): game.rig.pitch = lerpf(game.rig.pitch, -0.42, 0.04))

	# 5. the end card
	_fade(_lower, 0.0, 0.3)
	_card.visible = true
	_fade(_card, 1.0, 0.6)
	_title.text = "BUNNY BEAT DOWN"
	_sub.text = "A survival roguelike: one bunny, 49 bots who remember you.\nFree and open source · github.com/zconnor100-debug/bunny-beat-down"
	_fade(_title, 1.0, 0.6)
	_fade(_sub, 1.0, 0.8)
	await _until(t_rw + 14.0)
	print("TRAILER_END (%.1f s)" % _t)   # (tools/make_trailer.py takes the last this-many seconds of frames)
	print("TRAILER_MUSIC %s" % (Audio._music.stream.resource_path if Audio._music.stream else "none"))   # (for the credit)
	get_tree().quit()


## Bun's second take: the rival creeps again, a little slower (it hasn't seen you turn).
func creep_quiet(v: Critter, b: Critter) -> void:
	v.want_crouch = true
	var to := b.global_position - v.global_position
	v.look_yaw = atan2(-to.x, -to.z)
	v.move_input = Vector2(0, 0.8) if to.length() > 7.0 else Vector2.ZERO


## Nothing solid between two points, a critter's chest height above the ground.
func _clear(a: Vector3, b: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(_ground(a) + Vector3.UP * 1.0, _ground(b) + Vector3.UP * 1.0, Layers.WORLD)
	return get_viewport().get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func _ground(p: Vector3) -> Vector3:
	return Vector3(p.x, game.island.terrain.height_at(p.x, p.z) + 0.05, p.z)


func _place(c: Critter, p: Vector3, yaw: float) -> void:
	c.place_at(p + Vector3.UP * 0.2, yaw)
	c.velocity = Vector3.ZERO
	c._set_state(Critter.State.GROUND)


## A camera behind and beside `c`'s shoulder (scaled to its size), looking
## past it at `at`.
func _over_shoulder(c: Critter, at: Critter) -> void:
	var h := c.visual.rig.world_head_top if c.visual.rig else 1.5
	var to := at.global_position - c.global_position
	to.y = 0.0
	var f := to.normalized()
	var side := f.cross(Vector3.UP)
	var want := c.global_position - f * (h * 1.3 + 1.6) + side * (h * 0.55) + Vector3.UP * (h * 0.95)
	cam.global_position = cam.global_position.lerp(want, 0.15) if cam.global_position.distance_to(want) < 4.0 else want
	cam.look_at(at.global_position + Vector3.UP * 0.7 - side * 0.3, Vector3.UP)


func _build_captions() -> void:
	_cap = CanvasLayer.new()
	_cap.layer = 30
	get_tree().root.add_child(_cap)
	_card = ColorRect.new()
	_card.color = Color(0.09, 0.06, 0.04, 1.0)
	_card.set_anchors_preset(Control.PRESET_FULL_RECT)
	_card.modulate.a = 0.0
	_card.visible = false
	_cap.add_child(_card)
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.add_theme_constant_override("separation", 14)
	_cap.add_child(box)
	_title = UITheme.label("BUNNY BEAT DOWN", 120, UITheme.CARROT, true)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.modulate.a = 0.0
	box.add_child(_title)
	_sub = UITheme.label("a survival roguelike", 40, UITheme.CREAM)
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub.modulate.a = 0.0
	box.add_child(_sub)
	_lower = UITheme.label("", 40, UITheme.CREAM, true)
	_lower.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_lower.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_lower.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_lower.offset_bottom = -90
	_lower.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lower.modulate.a = 0.0
	_cap.add_child(_lower)


func _fade(n: CanvasItem, to: float, seconds: float) -> void:
	var tw := n.create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(n, "modulate:a", to, seconds)
