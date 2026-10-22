extends Node3D
## One match, from loading screen to "Winner Winner Carrot Dinner".
## Builds the world, hands control to MatchManager, and owns the pause and
## end-of-match screens.

const MENU_SCENE := "res://scenes/main.tscn"
const TIPS := [
	"Rocket carrots hurt you too. Stand well back from the salad.",
	"Headshots bonk extra hard — and acorn helmets fly off.",
	"Golden carrot guns hit 30% harder. Look for the gold beam.",
	"The Briar closes in stages. The white circle on the map is where it stops next.",
	"Press V to switch between third and first person.",
	"Lucky clovers heal 40. Press H to munch one.",
	"Bandit bunnies hop just as high as you do.",
	"Crates hold better loot than the forest floor.",
	"Press Q to swap shoulders when peeking around a tree.",
]

var quality := 2
var island: Island
var match_manager: MatchManager
var rig: CameraRig
var hud: HUD
var _loading: CanvasLayer
var _load_bar: ProgressBar
var _load_label: Label
var _pause: CanvasLayer
var _end: CanvasLayer
var _spectating := false
var _seed := 0
var _picker: CharacterSelect


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	quality = int(Settings.get_value(&"quality"))
	_seed = int(Settings.get_value(&"seed"))
	if _seed == 0:
		_seed = randi_range(1, 999999)
	GameSession.last_seed = _seed
	_build_loading()
	Audio.stop_music(1.0)
	await get_tree().process_frame
	await _build_world()
	# the island is ready: wait for the player to confirm their critter
	# (automated runs and --quick-match go straight in)
	_picker.ready_to_drop = true
	var args := OS.get_cmdline_user_args()
	if not (Settings.is_test_run() or args.has("--smoke-test") or args.has("--quick-match")):
		await _picker.confirmed
	_spawn_player()
	_start()


func _build_world() -> void:
	var world := Node3D.new()
	world.name = "World"
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(world)
	var lighting := WorldLighting.new()
	lighting.name = "Lighting"
	world.add_child(lighting)
	lighting.build(quality)
	var fx := FX.new()
	fx.name = "FX"
	world.add_child(fx)
	var proj := Projectiles.new()
	proj.name = "Projectiles"
	world.add_child(proj)
	island = Island.new()
	island.name = "Island"
	world.add_child(island)
	island.progress.connect(_on_load_progress)
	await island.generate(_seed, quality, true)

	match_manager = MatchManager.new()
	match_manager.name = "Match"
	world.add_child(match_manager)
	match_manager.setup(world, island, int(Settings.get_value(&"opponents")), int(Settings.get_value(&"difficulty")), _seed, 0.5 if GameSession.quick else 1.0)
	match_manager.player_eliminated.connect(_on_player_eliminated)
	match_manager.finished.connect(_on_match_finished)


func _spawn_player() -> void:
	var world := match_manager.world_root
	var def: CritterDef = load("res://data/critters/%s.tres" % String(Settings.get_value(&"player_character")))
	if def == null:
		def = load("res://data/critters/bun.tres")
	match_manager.spawn_player(def, String(Settings.get_value(&"player_skin")))
	rig = CameraRig.new()
	rig.name = "CameraRig"
	world.add_child(rig)
	rig.set_target(match_manager.player)
	var pc := match_manager.player.get_node("PlayerController") as PlayerController
	pc.rig = rig
	hud = HUD.new()
	hud.name = "HUD"
	world.add_child(hud)
	hud.setup(match_manager.player, rig, match_manager)
	hud.attach_island(island, match_manager.storm)


func _start() -> void:
	match_manager.begin_drop()
	hud.attach_dropship(match_manager.dropship)
	rig.spectate_target = match_manager.dropship
	rig.yaw = atan2(-(match_manager.dropship.finish - match_manager.dropship.start).x, -(match_manager.dropship.finish - match_manager.dropship.start).z) + 0.6
	rig.pitch = -0.35
	var tw := create_tween()
	tw.tween_property(_loading, "offset:y", -1200.0, 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_callback(_loading.queue_free)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	Audio.play_music("match")
	var ambience: Node = Audio.make_loop(&"ambient_forest_loop", self, false)
	if ambience:
		ambience.volume_db = -10.0
		ambience.play()
	hud.show_message("Press SPACE to jump!", "Pick your spot — the balloon won't wait.", 6.0)
	match_manager.player.state_changed.connect(_on_player_state)
	GameSession.matches_played += 1
	if OS.get_cmdline_user_args().has("--smoke-test"):
		_smoke_test()


## `-- --smoke-test`: drop in, land, save user://smoke_test.png, quit. Exit code
## 0 if the match ran (used to check exported builds end to end).
func _smoke_test() -> void:
	var p := match_manager.player
	await get_tree().create_timer(2.0).timeout
	match_manager.player_jump()
	var t := 0.0
	while p.state != Critter.State.GROUND and t < 45.0:
		p.want_jump = p.state == Critter.State.FREEFALL
		await get_tree().process_frame
		t += get_process_delta_time()
	await get_tree().create_timer(3.0).timeout
	var ok := p.state == Critter.State.GROUND and match_manager.phase != MatchManager.Phase.LOADING
	# headless runs have no framebuffer to grab (and release builds crash on the null image)
	var img := get_viewport().get_texture().get_image() if DisplayServer.get_name() != "headless" else null
	var shot := "none (headless)"
	if img:
		img.save_png("user://smoke_test.png")
		shot = ProjectSettings.globalize_path("user://smoke_test.png")
	print("SMOKE TEST %s: landed=%s phase=%s fps=%d shot=%s" % ["PASS" if ok else "FAIL", p.state == Critter.State.GROUND,
		MatchManager.Phase.keys()[match_manager.phase], Engine.get_frames_per_second(), shot])
	get_tree().quit(0 if ok else 1)


func _on_player_state(s: int) -> void:
	match s:
		Critter.State.FREEFALL:
			rig.spectate_target = null
			hud.show_message("Wheee!", "SPACE to pop your dandelion glider", 3.0)
		Critter.State.GROUND:
			if match_manager.phase == MatchManager.Phase.DROPPING or match_manager.phase == MatchManager.Phase.PLAYING:
				hud.show_message("Find a carrot gun!", "Crates and glowing loot have the good stuff", 3.0)


func _process(_delta: float) -> void:
	if island and match_manager and is_instance_valid(match_manager.player):
		island.set_player_position(match_manager.player.global_position)
	if _spectating and rig and (rig.spectate_target == null or not is_instance_valid(rig.spectate_target) or not (rig.spectate_target as Critter).alive):
		_spectate_next()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"pause"):
		if _end == null:
			_toggle_pause()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"jump") and match_manager and match_manager.phase == MatchManager.Phase.DROPPING:
		match_manager.player_jump()
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and _pause == null and _end == null:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# ---- loading ---------------------------------------------------------------------------------------

func _build_loading() -> void:
	_loading = CanvasLayer.new()
	_loading.layer = 20
	add_child(_loading)
	var bg := ColorRect.new()
	bg.color = Color("1f2a17")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_loading.add_child(bg)
	var c := CenterContainer.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.theme = UITheme.theme()
	_loading.add_child(c)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	c.add_child(v)
	var t := UITheme.label("BUNNY BEAT DOWN", 64, UITheme.CARROT, true)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	_load_label = UITheme.label("Growing the island", 28)
	_load_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_load_label)
	_load_bar = ProgressBar.new()
	_load_bar.custom_minimum_size = Vector2(720, 26)
	_load_bar.show_percentage = false
	var fill := StyleBoxFlat.new()
	fill.bg_color = UITheme.CARROT
	fill.set_corner_radius_all(13)
	var back := StyleBoxFlat.new()
	back.bg_color = Color(UITheme.CREAM, 0.15)
	back.set_corner_radius_all(13)
	_load_bar.add_theme_stylebox_override("fill", fill)
	_load_bar.add_theme_stylebox_override("background", back)
	v.add_child(_load_bar)
	var tip := UITheme.label("Tip: " + TIPS.pick_random(), 22, Color(UITheme.CREAM, 0.8))
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(tip)
	var s := UITheme.label("Island #%d" % _seed, 18, Color(UITheme.CREAM, 0.5))
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(s)
	# pick a critter while the island grows
	_picker = CharacterSelect.new()
	_picker.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(_picker)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _on_load_progress(f: float, label: String) -> void:
	if _load_bar:
		_load_bar.value = f * 100.0
		_load_label.text = label + "…"


# ---- pause -----------------------------------------------------------------------------------------

func _toggle_pause() -> void:
	if _pause:
		_pause.queue_free()
		_pause = null
		get_tree().paused = false
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_pause = CanvasLayer.new()
	_pause.layer = 15
	add_child(_pause)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause.add_child(dim)
	var c := CenterContainer.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.theme = UITheme.theme()
	_pause.add_child(c)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	c.add_child(v)
	var t := UITheme.label("Paused", 72, UITheme.CARROT, true)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var resume := UITheme.button("Resume", _toggle_pause)
	v.add_child(resume)
	v.add_child(UITheme.button("Settings", func():
		var p := SettingsPanel.new()
		c.remove_child(v)
		c.add_child(p)
		p.closed.connect(func():
			p.queue_free()
			c.add_child(v))))
	v.add_child(UITheme.button("Controls", func(): hud.show_message("WASD move • Mouse aim • LMB fire • RMB aim", "SPACE jump/glide • SHIFT sprint • CTRL crouch • R reload • E pick up • H heal • V camera • Q shoulder • M map", 6.0)))
	v.add_child(UITheme.button("Quit to menu", _to_menu))
	resume.grab_focus.call_deferred()


func _to_menu() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file(MENU_SCENE)


# ---- end of match -------------------------------------------------------------------------------------

func _on_player_eliminated(placement: int, killer: Critter) -> void:
	rig.set_target(match_manager.player)
	Audio.play(&"defeat_sting", -2.0)
	var who := killer.display_name if killer and killer != match_manager.player else "the Briar"
	_show_end("BEAT DOWN", "You placed #%d of %d — taken out by %s" % [placement, match_manager.total, who], false, killer)


func _on_match_finished(winner: Critter, _placement: int) -> void:
	if winner == match_manager.player:
		GameSession.wins += 1
		Audio.play_music("victory")
		Audio.play(&"victory_fanfare")
		_show_end("WINNER WINNER\nCARROT DINNER!", "%d beat downs • %d damage dealt" % [winner.kills, roundi(winner.damage_dealt)], true, null)
	elif _end and winner:
		var sub := _end.get_meta(&"sub") as Label
		if sub:
			sub.text += "\n%s won the match." % winner.display_name


func _show_end(title: String, sub: String, won: bool, killer: Critter) -> void:
	if _end:
		_end.queue_free()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_end = CanvasLayer.new()
	_end.layer = 12
	add_child(_end)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = UITheme.theme()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_end.add_child(root)
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	v.offset_left = -600
	v.offset_right = 600
	v.offset_top = -60
	v.offset_bottom = -60
	v.grow_vertical = Control.GROW_DIRECTION_BEGIN   # stack upward from the bottom edge
	v.alignment = BoxContainer.ALIGNMENT_END
	v.add_theme_constant_override("separation", 12)
	root.add_child(v)
	var t := UITheme.label(title, 86 if won else 76, UITheme.CARROT if won else UITheme.BERRY, true)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var s := UITheme.label(sub, 26)
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(s)
	_end.set_meta(&"sub", s)
	var p := match_manager.player
	var stats := UITheme.label("Beat downs: %d   •   Damage: %d   •   Island #%d" % [p.kills, roundi(p.damage_dealt), _seed], 20, Color(UITheme.CREAM, 0.8))
	stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(stats)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 18)
	v.add_child(row)
	if not won:
		row.add_child(UITheme.button("Spectate", func():
			_spectating = true
			rig.spectate_target = killer if killer and killer.alive else null
			if rig.spectate_target == null:
				_spectate_next()
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED))
	var again := UITheme.button("Play again", func(): get_tree().reload_current_scene())
	row.add_child(again)
	row.add_child(UITheme.button("Main menu", _to_menu))
	again.grab_focus.call_deferred()
	t.pivot_offset = Vector2(600, 60)
	t.scale = Vector2(0.4, 0.4)
	var tw := t.create_tween()
	tw.tween_property(t, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _spectate_next() -> void:
	var alive := match_manager.alive_critters()
	if alive.is_empty():
		_spectating = false
		return
	rig.spectate_target = alive.pick_random()
