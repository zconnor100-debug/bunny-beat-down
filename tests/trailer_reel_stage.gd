extends Node
## The 30-second reel, made for phones: quick cuts of the best of the game,
## big fights first. Each run records one map's shots (Movie Maker, every
## frame), printing where each shot starts and ends; tools/make_reel.py cuts
## them together and lays one music track over the lot (the game's own music
## is muted here, so it doesn't jump at every cut). Started by
## tests/capture_trailer.gd with "reel island|cage|toybox".
##
## Directed like the other trailer cuts, but every piece is the real game:
## the balloon and the gliders, real carrots and rockets, ragdolls, gore,
## boons, a nemesis, the rewind, the toy train. In the battles each bot is
## driven by a few lines here (pick the nearest foe, strafe, fire in bursts)
## rather than its AIBrain, which paces fights for a whole match and spends
## half a minute looking for a gun first.

const FPS := 30.0
const SEEDS := {"island": 4242, "cage": 777, "toybox": 4242}
const SHAKY := 0.04            ## the hand-held wobble of the action cameras (radians)

var out_dir := ""
var map := "island"
var opponents := 40            ## bots in the match (tests/trailer_hunt_stage.gd wants every rogue)
var game: Node
var mm: MatchManager
var bun: Critter
var cam: Camera3D
var _t := 0.0                  # stage time (s), counted in frames
var _fighters: Array = []      # [{c, team, target, phase, aim, pick}]
var _shot := ""
var _shot_from := 0
var _cap: CanvasLayer
var _title_box: Control
var _title: Label
var _sub: Label
var _caption: Label
var _small: Label
var _card: ColorRect
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	RealClock.fixed_step = 1.0 / FPS
	_rng.seed = 2026
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		out_dir = a[0]
	for m in SEEDS:
		if a.has(m):
			map = m
	_run.call_deferred()


# ---- time, shots, captions ------------------------------------------------------------

func _frame() -> void:
	GameInput.using_pad = false
	_drive_fighters()
	await get_tree().process_frame
	_t += 1.0 / FPS


func _until(t: float, each := Callable()) -> void:
	while _t < t:
		if each.is_valid():
			each.call()
		await _frame()


func _for(seconds: float, each := Callable()) -> void:
	await _until(_t + seconds, each)


## Shots are cut out of the recording by frame (tools/make_reel.py).
func _begin(shot: String) -> void:
	_shot = shot
	_shot_from = Engine.get_frames_drawn()
	_shot_t0 = _t


func _end() -> void:
	print("SHOT %s %d %d" % [_shot, _shot_from, Engine.get_frames_drawn()])
	_shot = ""


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
	var size := get_viewport().get_visible_rect().size
	var tall := size.y > size.x
	_title_box = VBoxContainer.new()
	_title_box.add_theme_constant_override("separation", 10)
	_title_box.size = Vector2(size.x, 600)
	_title_box.position = Vector2(0, size.y * (0.18 if tall else 0.22))
	_title_box.pivot_offset = Vector2(size.x * 0.5, 160)
	_cap.add_child(_title_box)
	_title = _label("BUNNY\nBEAT DOWN" if tall else "BUNNY BEAT DOWN", 150 if tall else 130, UITheme.CARROT)
	_title_box.add_child(_title)
	_sub = _label("", 46 if tall else 40, UITheme.CREAM)
	_title_box.add_child(_sub)
	_title_box.modulate.a = 0.0
	_caption = _label("", 104 if tall else 84, UITheme.CREAM)
	_caption.size = Vector2(size.x, 300)
	_caption.position = Vector2(0, size.y * (0.12 if tall else 0.08))
	_caption.pivot_offset = Vector2(size.x * 0.5, 100)
	_caption.modulate.a = 0.0
	_cap.add_child(_caption)
	_small = _label("", 58 if tall else 40, UITheme.CARROT_LIGHT)
	_small.size = Vector2(size.x, 200)
	_small.position = Vector2(0, size.y * (0.12 if tall else 0.08) + (220 if tall else 110))
	_small.modulate.a = 0.0
	_cap.add_child(_small)


func _label(text: String, px: int, color: Color) -> Label:
	var l := UITheme.label(text, px, color, true)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_constant_override("outline_size", maxi(8, px / 7))
	l.add_theme_color_override("font_outline_color", Color(0.08, 0.04, 0.02, 0.95))
	l.add_theme_constant_override("line_spacing", -px / 6)
	return l


## A caption that punches in (and a smaller line under it), then fades.
func _say(text: String, small := "", hold := 2.0) -> void:
	_caption.text = text
	_small.text = small
	for l in [_caption, _small]:
		var tw := (l as Control).create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS).set_ignore_time_scale(true)
		(l as Control).modulate.a = 0.0
		(l as Control).scale = Vector2.ONE * 1.35
		tw.tween_property(l, "modulate:a", 1.0, 0.12)
		tw.parallel().tween_property(l, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_interval(hold)
		tw.tween_property(l, "modulate:a", 0.0, 0.2)


func _slam_title(sub: String) -> void:
	_sub.text = sub
	var tw := _title_box.create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS).set_ignore_time_scale(true)
	_title_box.scale = Vector2.ONE * 2.2
	tw.tween_property(_title_box, "modulate:a", 1.0, 0.1)
	tw.parallel().tween_property(_title_box, "scale", Vector2.ONE, 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _fade_title(to: float, seconds: float) -> void:
	_title_box.create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS).set_ignore_time_scale(true).tween_property(_title_box, "modulate:a", to, seconds)


# ---- the run ---------------------------------------------------------------------------

func _run() -> void:
	var settings: Node = get_tree().root.get_node("Settings")
	settings.set_value(&"quality", 2, false)
	settings.set_value(&"opponents", opponents, false)
	settings.set_value(&"difficulty", 1, false)
	settings.set_value(&"seed", SEEDS[map], false)
	settings.set_value(&"map", map, false)
	settings.set_value(&"camera_mode", Settings.CameraMode.THIRD_PERSON, false)
	settings.set_value(&"player_character", "bun", false)
	RivalBook.reset_for_tests()
	PlayerProfile.reset_for_tests()
	Boons.reset()
	for action in InputMap.get_actions():   # (pads drive every Godot window on the machine)
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
	game.hud.visible = false
	game.set_process_unhandled_input(false)
	bun.get_node("PlayerController").process_mode = Node.PROCESS_MODE_DISABLED
	mm.time_keeper.offered.connect(game._offer_rewind)
	AudioServer.set_bus_mute(AudioServer.get_bus_index(&"Music"), true)
	AIBrain.kills_held = false
	for c in mm.critters:
		c.defies_director = true
		var brain := c.get_node_or_null("AIBrain")
		if brain:
			brain.process_mode = Node.PROCESS_MODE_DISABLED
	cam = Camera3D.new()
	cam.fov = 70.0
	mm.world_root.add_child(cam)
	_build_captions()
	await _for(0.3)
	print("REEL_START %s" % map)
	match map:
		"island":
			await _island()
		"cage":
			await _cage()
		"toybox":
			await _toybox()
	print("REEL_END %d" % Engine.get_frames_drawn())
	get_tree().quit()


## Name tags over every bot clutter a wide shot: hide them (but `keep`'s).
func _tags_off(keep: Array = []) -> void:
	for c in mm.critters:
		var tag: Label3D = c.visual.name_tag
		if tag:
			tag.visible = keep.has(c)


func _bots() -> Array:
	return mm.critters.filter(func(c): return c != bun and c.alive)


# ---- the island: the drop, the big brawl, the hero, the rocket, the rewind, the card ----

func _island() -> void:
	var bots := _bots()
	# 1. the drop: thirty critters pour out of the balloon and pop their gliders
	while mm.dropship == null or not mm.dropship.flying:
		await _frame()
	await _for(0.6)
	cam.make_current()
	var ship: Node3D = mm.dropship
	var droppers := bots.slice(0, 30)
	var side := Vector3(1, 0, 0.3).normalized()
	var crowd := func() -> Vector3:
		var m := Vector3.ZERO
		var n := 0
		for c in droppers:
			if c.state != Critter.State.IN_DROPSHIP:
				m += c.global_position
				n += 1
		return m / n if n > 0 else ship.global_position + Vector3.DOWN * 4.0
	var watch := func():
		_tags_off()
		var at: Vector3 = crowd.call()
		var want := at + side * 17.0 + Vector3.DOWN * 7.0
		cam.global_position = cam.global_position.lerp(want, 0.2)
		cam.look_at(at + Vector3.UP * 3.0, Vector3.UP)
		_wobble()
	cam.global_position = ship.global_position + Vector3.DOWN * 11.0 + side * 17.0
	cam.look_at(ship.global_position, Vector3.UP)
	_begin("drop")
	for i in droppers.size():
		var c: Critter = droppers[i]
		var away := Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1)).normalized()
		mm.dropship.eject(c)
		c.velocity = away * _rng.randf_range(3.0, 7.0) + Vector3.DOWN * 2.0
		c.look_yaw = atan2(-away.x, -away.z)
		c.move_input = Vector2(0, 1)
		var pop := func(cr: Critter): cr.want_jump = true
		get_tree().create_timer(_rng.randf_range(0.35, 0.8), true, false, true).timeout.connect(pop.bind(c))
		if i % 3 == 2:
			await _for(1.0 / FPS, watch)
	_slam_title("one bunny · forty-nine bots · carrot guns")
	await _for(2.2, watch)
	_fade_title(0.0, 0.25)
	await _for(0.3, watch)
	_end()
	for c in mm.critters.duplicate():
		if c.state == Critter.State.IN_DROPSHIP:
			mm.dropship.eject(c)

	# 2. the big brawl: two lines of fourteen at the Carrot Patch, Bun among them
	var spot := _open_spot(_poi("Carrot Patch"), 16.0)
	var fwd := Vector3(0, 0, -1)
	var right := Vector3(1, 0, 0)
	var team_a := bots.slice(0, 14)
	var team_b := bots.slice(14, 28)
	_line_up(team_a, spot + fwd * 9.0, -fwd, right, 0)
	_line_up(team_b, spot - fwd * 9.0, fwd, right, 1)
	_place(bun, spot + fwd * 1.5 + right * 1.5, atan2(fwd.x, fwd.z))
	_arm(team_a + team_b, [&"carrot_rifle", &"carrot_smg", &"carrot_shotgun", &"carrot_lmg", &"carrot_rifle", &"carrot_rocket_launcher"])
	_hand(bun, &"carrot_lmg", Rarity.Tier.GOLDEN)
	bun.max_health = 99999.0
	bun.health = bun.max_health
	for c in team_a + team_b:
		c.max_health = 32.0
		c.health = 32.0
		c.armor = 0.0
	_fight(team_a, team_b)
	await _for(0.6, _tags_off)
	_begin("brawl")
	var c0 := spot
	_say("BIG FIGHTS", "30 critters · one meadow", 2.4)
	await _for(4.0, func():
		# from behind Bun's line, round and up to the side of the whole fight
		var k := smoothstep(0.0, 1.0, (_t - _t0()) / 4.0)
		var angle := lerpf(PI + 0.45, PI * 0.5 + 0.15, k)
		var radius := lerpf(13.0, 14.5, k)
		var height := lerpf(3.2, 11.0, k)
		cam.global_position = c0 + Vector3(sin(angle), 0, cos(angle)) * radius + Vector3.UP * height
		cam.look_at(c0 + Vector3.UP * 0.8, Vector3.UP)
		_wobble())
	_end()

	# 3. Bun and the golden LMG, over the shoulder, into what's left of the far line
	_begin("hero")
	cam.fov = 52.0
	_say("CARROT GUNS", "pistol to rocket launcher", 1.8)
	var sweep_from := -0.5
	await _for(2.6, func():
		var foes := team_b.filter(func(c): return c.alive)
		var k := (_t - _t0()) / 2.6
		var aim := c0 - fwd * 9.0 + right * lerpf(-12.0, 12.0, k) * 0.8 + Vector3.UP * 1.4
		if not foes.is_empty():
			var near: Critter = foes.reduce(func(a, b): return a if a.global_position.distance_to(aim) < b.global_position.distance_to(aim) else b)
			aim = aim.lerp(near.get_chest_position(), 0.6)
		_aim(bun, aim)
		bun.want_fire = true
		var b := bun.global_position
		var to := (aim - b)
		to.y = 0
		var f := to.normalized()
		var s := f.cross(Vector3.UP)
		var h := bun.visual.rig.world_head_top
		cam.global_position = b - f * h * 1.35 + s * h * 0.55 + Vector3.UP * h * 0.95
		cam.look_at(b + f * 10.0 + Vector3.UP * h * 0.55, Vector3.UP)
		_wobble(1.6))
	bun.want_fire = false
	cam.fov = 70.0
	_end()
	_stop_fight()

	# 4. one rocket into a huddle, in slow motion
	var huddle := bots.slice(28, 34)
	var hspot := _open_spot(c0 + right * 60.0, 12.0, true)
	for i in huddle.size():
		var c: Critter = huddle[i]
		var at := hspot + Vector3(cos(i * TAU / huddle.size()), 0, sin(i * TAU / huddle.size())) * 1.6
		var to := hspot - at
		_place(c, at, atan2(-to.x, -to.z))
		c.give_weapon(WeaponInstance.new(WeaponDB.get_weapon(&"carrot_smg")))
		if i % 2 == 0:
			c.visual.say(["Huddle up!", "What's the plan?", "Shh!"][i % 3], 2.0)
	# Bun on dry ground (no shooting while swimming) with a clear shot, and a
	# camera on the side the reeds don't hide
	var from := hspot + Vector3(0, 0, 26.0)
	for k in 16:
		var d := Vector3(sin(k * TAU / 16.0), 0, cos(k * TAU / 16.0))
		var p := _ground(hspot + d * 24.0)
		if _dry(p) and _clear(p + Vector3.UP * 1.2, hspot + Vector3.UP * 1.0):
			from = p
			break
	var to_huddle := (hspot - from)
	to_huddle.y = 0
	_place(bun, from, atan2(-to_huddle.x, -to_huddle.z))
	_hand(bun, &"carrot_rocket_launcher", Rarity.Tier.GOLDEN)
	await _for(1.0, func(): _aim(bun, hspot + Vector3.UP * 1.0))
	_begin("rocket")
	var aside := to_huddle.normalized().cross(Vector3.UP)
	var side_cam := hspot + aside * 9.5 - to_huddle.normalized() * 4.0 + Vector3.UP * 1.4
	for k in 8:
		var c := hspot + (Basis(Vector3.UP, k * 0.35 * (1 if k % 2 else -1)) * aside) * 9.5 - to_huddle.normalized() * 4.0 + Vector3.UP * 1.4
		if _clear(c, hspot + Vector3.UP * 0.9):
			side_cam = c
			break
	var frame_huddle := func():
		cam.global_position = side_cam
		cam.look_at(hspot + Vector3.UP * 1.0 - to_huddle.normalized() * 3.5, Vector3.UP)
	frame_huddle.call()
	await _for(0.35, frame_huddle)
	bun.want_fire = true
	await _frame()
	bun.want_fire = false
	await _for(0.12, frame_huddle)
	_say("RAGDOLL PHYSICS", "and plenty of carrot gore", 2.0)
	Engine.time_scale = 0.2
	await _for(1.5, frame_huddle)
	var ramp := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS).set_ignore_time_scale(true)
	ramp.tween_property(Engine, "time_scale", 1.0, 0.4)
	await _for(0.6, frame_huddle)
	Engine.time_scale = 1.0
	_end()

	# 5. the rewind: the rival's killing blow freezes the match; ten seconds back, Bun turns round
	var spare := bots.slice(34)
	var foxes := spare.filter(func(c): return c.def.id == &"fox")
	await _rewind_shot(foxes[0] if not foxes.is_empty() else spare[0], c0 + right * 120.0)

	# 6. the end card
	_begin("card")
	_card.visible = true
	_card.modulate.a = 1.0
	_title_box.modulate.a = 0.0
	_slam_title("runs · boons · rewinds\na nemesis who hunts you")
	await _for(0.9)
	var get := _label("FREE TO PLAY", 84, UITheme.CREAM)
	var link := _label("github.com/zconnor100-debug/\nbunny-beat-down", 48, UITheme.CARROT_LIGHT)
	for l in [get, link]:
		_title_box.add_child(l)
		l.modulate.a = 0.0
		l.create_tween().set_ignore_time_scale(true).tween_property(l, "modulate:a", 1.0, 0.3)
	await _for(2.9)
	_end()


## The rewind, condensed: the rival creeps up behind Bun busy at a chest, the
## killing blow freezes the match and asks, and ten seconds earlier Bun turns.
func _rewind_shot(rival: Critter, near: Vector3) -> void:
	bun.max_health = 100.0
	bun.health = 100.0
	var spot := _open_spot(near, 10.0)
	var face := 0.6
	var fwd := -Basis(Vector3.UP, face).z
	_place(bun, spot, face)
	var chest := TreasureChest.new(true)
	mm.world_root.add_child(chest)
	chest.global_position = _ground(spot + fwd * 1.8)
	chest.rotation.y = face + PI
	_hand(bun, &"carrot_shotgun", Rarity.Tier.GOLDEN)
	bun.look_yaw = face
	_place(rival, _ground(spot - fwd * 11.0 + fwd.cross(Vector3.UP) * 2.0), face)
	rival.give_weapon(WeaponInstance.new(WeaponDB.get_weapon(&"carrot_shotgun"), Rarity.Tier.PRIZE))
	rival.inventory.add_ammo(WeaponData.AmmoType.SHELLS, 30)
	rival.max_health = 100.0
	rival.health = 100.0
	rival.visual.set_enemy_highlight(rival.display_name, true)
	var behind := func():
		rival.want_crouch = true
		var to := bun.global_position - rival.global_position
		rival.look_yaw = atan2(-to.x, -to.z)
		rival.move_input = Vector2(0, 0.9) if to.length() > 6.0 else Vector2.ZERO
		_over(rival, bun)
	cam.make_current()
	await _for(TimeKeeper.REWIND_SECONDS + 0.5, behind)   # (the rewind goes back ten seconds: they were here)
	_begin("rewind_creep")
	rival.visual.say("Don't turn around, Bun.", 2.2)
	await _for(1.2, behind)
	_end()
	rival.want_crouch = false
	rival.move_input = Vector2.ZERO
	bun.health = 12.0
	bun.armor = 0.0
	var shoot := func():
		var aim := bun.get_chest_position()
		_aim(rival, aim)
		rival.want_fire = true
		_over(rival, bun)
	var t_shot := _t
	while mm.time_keeper.pending == null and _t < t_shot + 3.0:
		shoot.call()
		await _frame()
	rival.want_fire = false
	game.hud.visible = true
	_begin("rewind_freeze")
	_say("REWIND THE KILLING BLOW", "three times a match", 2.4)
	await _for(1.1)
	_end()
	game._answer_offer(true)
	game.rig.camera.make_current()
	game.rig.yaw = face
	game.rig.pitch = -0.12
	bun.look_yaw = face
	_begin("rewind_turn")
	var t_rw := _t
	await _for(1.0, func():
		rival.want_crouch = true
		var to := bun.global_position - rival.global_position
		rival.look_yaw = atan2(-to.x, -to.z))
	var turn := func():
		bun.want_aim = true
		var d: Vector3 = (rival.get_chest_position() - bun.get_eye_position()).normalized()
		game.rig.yaw = lerp_angle(game.rig.yaw, atan2(-d.x, -d.z), 0.14)
		game.rig.pitch = lerpf(game.rig.pitch, asin(d.y), 0.14)
		bun.look_yaw = game.rig.yaw
		bun.look_pitch = game.rig.pitch
		bun.aim_point = rival.get_chest_position()
	await _until(t_rw + 1.8, turn)
	rival.move_input = Vector2.ZERO
	rival.visual.say("...!", 1.2)
	rival.health = minf(rival.health, 30.0)
	for i in 3:
		if not rival.alive:
			break
		bun.want_fire = true
		await _frame()
		bun.want_fire = false
		await _for(0.55, turn)
	await _until(t_rw + 3.6, turn)
	bun.want_aim = false
	game.hud.visible = false
	_end()


# ---- the Hamster Cage: mutated carrots, the nemesis and its gang, a cage brawl ---------------

func _cage() -> void:
	var bots := _bots()
	for c in mm.critters.duplicate():
		if c.state == Critter.State.IN_DROPSHIP:
			mm.dropship.eject(c)
	cam.make_current()
	await _for(0.2)
	var spot := _open_spot(Vector3.ZERO, 16.0)
	var fwd := Vector3(0, 0, -1)
	var right := Vector3(1, 0, 0)

	# 1. a cage brawl, the gym behind
	var team_a := bots.slice(0, 14)
	var team_b := bots.slice(14, 28)
	_line_up(team_a, spot + fwd * 9.0, -fwd, right, 0)
	_line_up(team_b, spot - fwd * 9.0, fwd, right, 1)
	_place(bun, spot + fwd * 30.0, PI)
	_arm(team_a + team_b, [&"carrot_smg", &"carrot_rifle", &"carrot_shotgun", &"carrot_rocket_launcher", &"carrot_lmg"])
	for c in team_a + team_b:
		c.max_health = 32.0
		c.health = 32.0
	_fight(team_a, team_b)
	await _for(1.0, _tags_off)
	_begin("cage_brawl")
	_say("THREE MAPS", "the Hamster Cage", 2.2)
	var c0 := spot
	await _for(3.0, func():
		var k := smoothstep(0.0, 1.0, (_t - _t0()) / 3.0)
		cam.global_position = c0 + Vector3(lerpf(-22.0, -8.0, k), lerpf(16.0, 5.0, k), lerpf(-6.0, 14.0, k))
		cam.look_at(c0 + Vector3.UP * 1.0, Vector3.UP)
		_wobble())
	_end()
	_stop_fight()

	# 2. mutated carrots: splitting, bouncing, popping, from Bun's SMG
	for id in ["splitting", "bouncy", "popping"]:
		for k in Boons.MAX_LEVEL:
			Boons.add(id)
	var targets := bots.slice(28, 36)
	var tspot := _open_spot(c0 + right * 50.0, 12.0)
	for i in targets.size():
		var c: Critter = targets[i]
		var at := tspot + right * ((i % 4) - 1.5) * 1.7 + fwd * (1.6 if i >= 4 else 0.0) + right * (0.8 if i >= 4 else 0.0)
		_place(c, at, atan2(fwd.x, fwd.z))
		c.give_weapon(WeaponInstance.new(WeaponDB.get_weapon(&"carrot_pistol")))
		c.max_health = 60.0
		c.health = 60.0
	_place(bun, tspot - fwd * 9.0, 0.0)
	_hand(bun, &"carrot_smg", Rarity.Tier.GOLDEN)
	bun.max_health = 99999.0
	bun.health = bun.max_health
	_tags_off()
	await _for(0.8, func(): _aim(bun, tspot + Vector3.UP))
	_begin("mutations")
	_say("BOONS", "carrots that split, bounce and pop", 2.2)
	await _for(2.8, func():
		var k := (_t - _t0()) / 2.8
		var aim := tspot + right * lerpf(-3.0, 3.0, k) + Vector3.UP * 1.1
		_aim(bun, aim)
		bun.want_fire = true
		var b := bun.global_position
		var h := bun.visual.rig.world_head_top
		cam.global_position = b - fwd * h * 1.2 + right * h * 0.6 + Vector3.UP * h * 0.85
		cam.look_at(tspot + Vector3.UP * 0.9, Vector3.UP)
		_wobble(1.3))
	bun.want_fire = false
	_end()
	Boons.reset()

	# 3. the nemesis: scarred, golden gun, its gang behind it, coming for you
	var nem: Critter = bots[36]
	var gang := bots.slice(37, 40)
	var nspot := _open_spot(c0 - right * 50.0, 14.0)
	_place(bun, nspot - fwd * 60.0, 0.0)
	var cast_name := nem.display_name
	_place(nem, nspot, PI)
	nem.visual.add_scars(["eye_patch", "arm_l"])
	var sig := WeaponInstance.new(WeaponDB.get_weapon(&"carrot_shotgun"), Rarity.Tier.GOLDEN)
	nem.give_weapon(sig)
	nem.visual.set_enemy_highlight(cast_name, false, 4)
	nem.visual.name_tag.text = "☠ NEMESIS %s\nThe Bramble Gang" % cast_name
	nem.visual.name_tag.modulate = Color(1.0, 0.2, 0.25)
	for i in gang.size():
		var g: Critter = gang[i]
		_place(g, nspot + right * (i - 1) * 3.2 + fwd * 3.0, PI)
		g.give_weapon(WeaponInstance.new(WeaponDB.get_weapon([&"carrot_rifle", &"carrot_smg", &"carrot_lmg"][i])))
		g.visual.set_enemy_highlight(g.display_name, false, 3)
	var charge := func():
		for c in [nem] + gang:
			var to: Vector3 = bun.global_position - c.global_position
			c.look_yaw = atan2(-to.x, -to.z)
			c.move_input = Vector2(0, 1)
			c.want_sprint = true
			c.want_aim = c == nem
			c.aim_point = bun.get_chest_position()
		_tags_off([nem])
		var lead := nem.global_position
		var dir := (bun.global_position - lead)
		dir.y = 0
		dir = dir.normalized()
		var h := nem.visual.rig.world_head_top
		cam.global_position = lead + dir * h * 2.4 + Vector3.UP * h * 0.2 + dir.cross(Vector3.UP) * h * 0.45
		cam.look_at(lead + Vector3.UP * h * 0.8, Vector3.UP)
		_wobble(1.2)
	await _for(0.3, charge)
	_begin("nemesis")
	_say("THEY REMEMBER YOU", "your nemesis hunts you down", 2.4)
	await _for(2.8, charge)
	_end()


# ---- Toy Box Bash: a battle across the train track, and the train ----------------------------

func _toybox() -> void:
	var bots := _bots()
	for c in mm.critters.duplicate():
		if c.state == Critter.State.IN_DROPSHIP:
			mm.dropship.eject(c)
	cam.make_current()
	await _for(0.2)
	var train: ToyTrain = game.island.train
	# a straight stretch of track: the battle sits across it
	var s := 0.0
	var best := -1.0
	for i in 40:
		var at := train.total * i / 40.0
		var a := train.frame_at(at)
		var b := train.frame_at(at + 20.0)
		var straight := (-a.basis.z).dot(-b.basis.z)
		if straight > best:
			best = straight
			s = at + 10.0
	var xf := train.frame_at(s)
	var along := -xf.basis.z.normalized()
	along.y = 0
	along = along.normalized()
	var across := along.cross(Vector3.UP)
	var spot := xf.origin
	var team_a := bots.slice(0, 13)
	var team_b := bots.slice(13, 26)
	_line_up(team_a, spot + across * 8.0, -across, along, 0)
	_line_up(team_b, spot - across * 8.0, across, along, 1)
	_arm(team_a + team_b, [&"carrot_rifle", &"carrot_smg", &"carrot_shotgun", &"carrot_rocket_launcher"])
	for c in team_a + team_b:
		c.max_health = 70.0
		c.health = 70.0
	# a few brave ones on the track itself
	for i in 3:
		_place(bots[26 + i], spot + along * (i - 1) * 3.0, atan2(across.x, across.z))
		bots[26 + i].give_weapon(WeaponInstance.new(WeaponDB.get_weapon(&"carrot_pistol")))
	_place(bun, spot + across * 30.0, 0.0)
	_fight(team_a, team_b)
	_tags_off()
	# the locomotive arrives at the battle 1.4 s into the shot
	train.set_distance(fposmod(s - ToyTrain.SPEED * 1.9, train.total))
	await _for(0.5)
	_begin("toybox")
	_say("ALL ABOARD", "Toy Box Bash", 2.2)
	await _for(3.0, func():
		var k := smoothstep(0.0, 1.0, (_t - _t0()) / 3.0)
		cam.global_position = spot + across * lerpf(19.0, 15.0, k) + along * lerpf(9.0, 4.0, k) + Vector3.UP * lerpf(9.0, 6.5, k)
		cam.look_at(spot + Vector3.UP * 1.0 - along * 1.5, Vector3.UP)
		_wobble())
	_end()
	_stop_fight()


# ---- battles ---------------------------------------------------------------------------

var _shot_t0 := 0.0


func _t0() -> float:
	return _shot_t0


## Two loose lines facing each other (staggered so they don't stand in a row).
func _line_up(team: Array, centre: Vector3, facing: Vector3, along: Vector3, side: int) -> void:
	for i in team.size():
		var c: Critter = team[i]
		var at := centre + along * (floori(i / 2.0) - team.size() * 0.25) * 2.0 + along * (i % 2) * 1.0 + facing * (-1.0 if i % 2 else 0.0) * 1.8
		at += Vector3(_rng.randf_range(-0.4, 0.4), 0, _rng.randf_range(-0.4, 0.4))
		_place(c, at, atan2(-facing.x, -facing.z))
		c.set_meta(&"team", side)


func _arm(team: Array, guns: Array) -> void:
	for i in team.size():
		var c: Critter = team[i]
		var w := WeaponInstance.new(WeaponDB.get_weapon(guns[i % guns.size()]), [Rarity.Tier.GARDEN, Rarity.Tier.PRIZE, Rarity.Tier.GOLDEN][i % 3])
		c.give_weapon(w)
		for t in WeaponData.AmmoType.values():
			c.inventory.add_ammo(t, 300)


func _fight(team_a: Array, team_b: Array) -> void:
	_fighters.clear()
	for team in [team_a, team_b]:
		for c in team:
			_fighters.append({"c": c, "foes": team_b if team == team_a else team_a, "target": null,
				"phase": _rng.randf() * TAU, "aim": Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-0.5, 0.8), _rng.randf_range(-1, 1)) * 0.5,
				"pick": 0.0, "rate": _rng.randf_range(1.6, 3.2)})


func _stop_fight() -> void:
	for f in _fighters:
		var c: Critter = f.c
		if is_instance_valid(c) and c.alive:
			c.want_fire = false
			c.move_input = Vector2.ZERO
	_fighters.clear()


## Each fighter: the nearest live foe, strafing as it shoots in bursts, now
## and then a hop (each species' own trick), the aim a little off so not
## every carrot lands.
func _drive_fighters() -> void:
	for f in _fighters:
		var c: Critter = f.c
		if not is_instance_valid(c) or not c.alive:
			continue
		var target: Critter = f.target
		if target == null or not is_instance_valid(target) or not target.alive or _t > f.pick:
			var best: Critter = null
			for o in f.foes:
				if is_instance_valid(o) and o.alive and (best == null or o.global_position.distance_to(c.global_position) < best.global_position.distance_to(c.global_position)):
					best = o
			f.target = best
			f.pick = _t + _rng.randf_range(0.8, 1.6)
			target = best
		if target == null:
			c.want_fire = false
			c.move_input = Vector2.ZERO
			continue
		var wob: Vector3 = f.aim
		var aim := target.get_chest_position() + wob * (0.8 + 0.6 * sin(_t * 1.7 + f.phase))
		_aim(c, aim)
		var dist := c.global_position.distance_to(target.global_position)
		c.move_input = Vector2(sin(_t * 1.3 + f.phase) * 0.9, 0.6 if dist > 13.0 else (-0.4 if dist < 6.0 else 0.0))
		c.want_fire = sin(_t * f.rate + f.phase) > -0.25
		if _rng.randf() < 0.004:
			c.want_jump = true


## Put a gun in `c`'s paws, ready to fire (with plenty of carrots for it).
func _hand(c: Critter, id: StringName, tier: int) -> void:
	var w := WeaponInstance.new(WeaponDB.get_weapon(id), tier)
	c.give_weapon(w)
	c.switch_to(c.inventory.weapons.find(w))
	c.inventory.add_ammo(w.data.ammo_type, 400)


func _aim(c: Critter, at: Vector3) -> void:
	var to := at - c.get_eye_position()
	c.look_yaw = atan2(-to.x, -to.z)
	c.look_pitch = asin(clampf(to.normalized().y, -1.0, 1.0))
	c.aim_point = at


# ---- places and cameras ----------------------------------------------------------------

func _poi(name_: String) -> Vector3:
	for p in game.island.pois:
		if p.name == name_:
			return Vector3(p.center.x, 0, p.center.y)
	return Vector3.ZERO


func _ground(p: Vector3) -> Vector3:
	var space := get_viewport().get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, p.y + 60.0, p.z), Vector3(p.x, p.y - 60.0, p.z), Layers.WORLD)
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return Vector3(p.x, game.island.terrain.height_at(p.x, p.z) + 0.05, p.z)
	return hit.position + Vector3.UP * 0.05


## No water here (a critter can't shoot while it swims).
func _dry(p: Vector3) -> bool:
	return not game.island.has_method("water_level_at") or game.island.water_level_at(p) < p.y - 0.3


## Nothing solid between two points.
func _clear(a: Vector3, b: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(a, b, Layers.WORLD)
	return get_viewport().get_world_3d().direct_space_state.intersect_ray(q).is_empty()


## The nearest open, dry, fairly flat spot to `near` with nothing solid within
## `radius` at chest height (rings of candidates further and further out);
## `grass`: well away from the swamp and its reeds, too.
func _open_spot(near: Vector3, radius: float, grass := false) -> Vector3:
	var space := get_viewport().get_world_3d().direct_space_state
	for ring in 12:
		for k in maxi(1, ring * 8):
			var a := TAU * k / maxf(1.0, ring * 8.0)
			var p := _ground(near + Vector3(cos(a), 0, sin(a)) * ring * 9.0)
			if not _dry(p):
				continue
			if grass and not _dry_around(p, radius * 2.0):
				continue
			var ok := true
			for d in 12:
				var dir := Vector3(cos(d * TAU / 12.0), 0, sin(d * TAU / 12.0))
				var far := _ground(p + dir * radius)
				if absf(far.y - p.y) > radius * 0.25:
					ok = false
					break
				var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 1.2, far + Vector3.UP * 1.2, Layers.WORLD)
				if not space.intersect_ray(q).is_empty():
					ok = false
					break
			if ok:
				return p
	return _ground(near)


func _dry_around(p: Vector3, r: float) -> bool:
	for d in 8:
		if not _dry(_ground(p + Vector3(cos(d * TAU / 8.0), 0, sin(d * TAU / 8.0)) * r)):
			return false
	return true


func _place(c: Critter, p: Vector3, yaw: float) -> void:
	c.place_at(_ground(p) + Vector3.UP * 0.2, yaw)
	c.velocity = Vector3.ZERO
	c._set_state(Critter.State.GROUND)
	c.move_input = Vector2.ZERO
	c.want_fire = false


## Behind and beside `c`'s shoulder, looking past it at `at`.
func _over(c: Critter, at: Critter) -> void:
	var h := c.visual.rig.world_head_top
	var to := at.global_position - c.global_position
	to.y = 0.0
	var f := to.normalized()
	var s := f.cross(Vector3.UP)
	var want := c.global_position - f * (h * 1.9 + 1.8) + s * (h * 0.5) + Vector3.UP * (h * 1.25)
	cam.global_position = cam.global_position.lerp(want, 0.15) if cam.global_position.distance_to(want) < 4.0 else want
	cam.look_at(at.global_position + Vector3.UP * 0.7 - s * 0.3, Vector3.UP)


## A hand-held wobble on the action cameras.
func _wobble(k := 1.0) -> void:
	cam.rotate_object_local(Vector3.RIGHT, sin(_t * 2.3) * SHAKY * 0.3 * k)
	cam.rotate_object_local(Vector3.UP, sin(_t * 1.7 + 1.0) * SHAKY * 0.3 * k)
