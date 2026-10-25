extends Node3D
## One match, from loading screen to "Winner Winner Carrot Dinner".
## Builds the world, hands control to MatchManager, and owns the pause and
## end-of-match screens.

const MENU_SCENE := "res://scenes/main.tscn"
const TOYBOX_TIPS := [
	"Hop on the toy train for a ride round the room — but don't stand on the track!",
	"Dollhouse Manor has three floors: take the stairs for the best view.",
	"Swim in the fishbowl: climb the slide and jump in.",
	"Pillow stuffing hides you from bots, just like bushes.",
	"Mind the tiny bricks. Ow.",
]
const MAP_NAMES := {"island": "Island", "cage": "Hamster Cage", "toybox": "Toy Box Bash"}
const CAGE_TIPS := [
	"Hamster tubes are tunnels: run through Tube Town to cross unseen.",
	"Water bowls are brimming: swim in, and climb out over the rim.",
	"The fridge left the north-east corner frozen. Ice cubes make great cover.",
	"Paper bedding tufts hide you from bots, just like bushes.",
	"The toy plane only flies once. Jump before it reaches the glass!",
]
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
var _offer: CanvasLayer     # "rewind, or accept defeat?" (see TimeKeeper)
var _draft: CanvasLayer     # a boon draft (an acorn shrine): the match waits
var _run_result: Dictionary = {}   # a run's stop, once it's over for you (Run.finish_match)
var _spectating := false
var _seed := 0
var _picker: CharacterSelect
var _map := "island"
var _paid := false          # acorns for this match already added
var _earned := 0
var _after_replay: Callable  # the end screen held back for the final-shot replay


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	quality = int(Settings.get_value(&"quality"))
	_seed = int(Settings.get_value(&"seed"))
	_map = String(Settings.get_value(&"map"))
	var args := OS.get_cmdline_user_args()
	if args.has("--map") and args.find("--map") + 1 < args.size():
		_map = args[args.find("--map") + 1]   # `-- --smoke-test --map cage`
	if not MAP_NAMES.has(_map):
		_map = "island"
	if GameSession.replay_seed > 0:
		_seed = GameSession.replay_seed   # "Rematch (same seed)"
		GameSession.replay_seed = 0
	if Run.in_match:   # a run's stop: its map, and a seed of its own
		var rs := Run.state()
		_map = String(Run.current().get("map", "island"))
		_seed = int(rs.seed) * 31 + int(rs.row) * 7 + int(rs.playing) * 3 + int(rs.stats.matches) * 101 + 1
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
	match _map:
		"cage":
			island = HamsterCage.new()
		"toybox":
			island = ToyBox.new()
		_:
			island = Island.new()
	island.name = "Island"
	world.add_child(island)
	island.progress.connect(_on_load_progress)
	await island.generate(_seed, quality, true)
	island.tune_lighting(lighting)
	if Burrow.modifier_on("pea_soup"):
		lighting.env.fog_density *= 6.0   # (Pea Soup: distance fog only; height fog blanks the view here)
		lighting.env.fog_light_color = Color(0.72, 0.78, 0.62)

	# let physics register every prop before loot checks its spot against them
	await get_tree().physics_frame
	await get_tree().physics_frame
	match_manager = MatchManager.new()
	match_manager.name = "Match"
	world.add_child(match_manager)
	var opponents := int(Settings.get_value(&"opponents"))
	if Run.in_match:
		opponents = Run.opponents(opponents)
	match_manager.setup(world, island, opponents, int(Settings.get_value(&"difficulty")), _seed, 0.5 if GameSession.quick and not Run.in_match else 1.0)
	match_manager.player_eliminated.connect(_on_player_eliminated)
	match_manager.boons_offered.connect(_show_draft)
	match_manager.finished.connect(_on_match_finished)
	if not Settings.is_test_run():   # (automated matches just let the blow land)
		match_manager.time_keeper.offered.connect(_offer_rewind)


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
	rig.yaw = match_manager.dropship.view_yaw()
	rig.pitch = -0.3
	var tw := create_tween()
	tw.tween_property(_loading, "offset:y", -1200.0, 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_callback(_loading.queue_free)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	Audio.play_music(island.music_slot)
	var ambience: Node = Audio.make_loop(&"ambient_forest_loop", self, false)
	if ambience:
		ambience.volume_db = -10.0 if _map == "island" else -18.0   # (birdsong through an open window)
		ambience.play()
	hud.show_message("Press %s to jump!" % GameInput.prompt(&"jump"), "Pick your spot — the %s won't wait." % match_manager.dropship.display_name(), 6.0)
	if Run.in_match:
		var stop := Run.current()
		get_tree().create_timer(6.5).timeout.connect(func():
			if hud:
				hud.show_message(String(Run.KINDS[stop.kind].name).to_upper(), "Goal: %s" % Run.goal_text(match_manager.total), 4.5))
	match_manager.player.state_changed.connect(_on_player_state)
	GameSession.matches_played += 1
	if not match_manager.rivals_here.is_empty():
		var names := match_manager.rivals_here.map(func(r): return "%s the %s (%s)" % [r.display_name, RivalBook.label_of(r.display_name), RivalBook.score(r.display_name)])
		get_tree().create_timer(7.0).timeout.connect(func():
			if hud:
				hud.show_message("⚔ YOUR RIVAL%s %s HERE" % ["S" if names.size() > 1 else "", "ARE" if names.size() > 1 else "IS"], ", ".join(names), 5.0))
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
			hud.show_message("Wheee!", "%s to pop your dandelion glider" % GameInput.prompt(&"jump"), 3.0)
		Critter.State.GROUND:
			if match_manager.phase == MatchManager.Phase.DROPPING or match_manager.phase == MatchManager.Phase.PLAYING:
				hud.show_message("Find a carrot gun!", "Crates and glowing loot have the good stuff", 3.0)


func _process(_delta: float) -> void:
	if island and match_manager and is_instance_valid(match_manager.player):
		island.set_player_position(match_manager.player.global_position)
	if _spectating and rig and (rig.spectate_target == null or not is_instance_valid(rig.spectate_target) or not (rig.spectate_target as Critter).alive):
		_spectate_next()


func _unhandled_input(event: InputEvent) -> void:
	if match_manager and (match_manager.time_keeper.playing_back or match_manager.kill_cam.playing):
		return   # (the rewind or the replay owns the screen for now)
	if _draft:
		if event.is_action_pressed(&"pause") or event.is_action_pressed(&"ui_cancel"):
			get_viewport().set_input_as_handled()   # (pick one: the match is waiting)
		else:
			UITheme.refocus_if_lost(event, get_viewport(), UITheme.first_focusable(_draft))
	elif _offer:
		if event.is_action_pressed(&"rewind"):
			get_viewport().set_input_as_handled()
			_answer_offer(true)
		elif event.is_action_pressed(&"pause"):
			get_viewport().set_input_as_handled()
		else:
			UITheme.refocus_if_lost(event, get_viewport(), UITheme.first_focusable(_offer))
	elif event.is_action_pressed(&"pause"):
		_toggle_pause()   # (over the end screen too: Quit is always there)
		get_viewport().set_input_as_handled()
	elif _pause and event.is_action_pressed(&"ui_cancel"):   # B backs out of the pause menu
		_toggle_pause()
		get_viewport().set_input_as_handled()
	elif _pause or _end:
		var menu := _pause if _pause else _end
		UITheme.refocus_if_lost(event, get_viewport(), UITheme.first_focusable(menu))
	elif event.is_action_pressed(&"jump") and match_manager and match_manager.phase == MatchManager.Phase.DROPPING:
		match_manager.player_jump()
	elif event.is_action_pressed(&"rewind") and match_manager and match_manager.phase == MatchManager.Phase.PLAYING:
		_rewind_now()
		get_viewport().set_input_as_handled()
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
	_load_label = UITheme.label({"cage": "Laying fresh bedding", "toybox": "Tidying the bedroom floor"}.get(_map, "Growing the island"), 28)
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
	var tips: Array = {"cage": CAGE_TIPS + TIPS.slice(0, 3), "toybox": TOYBOX_TIPS + TIPS.slice(0, 3)}.get(_map, TIPS)
	var tip := UITheme.label("Tip: " + tips.pick_random(), 22, Color(UITheme.CREAM, 0.8))
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(tip)
	var s := UITheme.label("%s #%d" % [MAP_NAMES[_map], _seed], 18, Color(UITheme.CREAM, 0.5))
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
		# (back to the end screen's buttons, or to playing / spectating)
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if _end and not _spectating else Input.MOUSE_MODE_CAPTURED
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
	var tk := match_manager.time_keeper if match_manager else null
	if tk and tk.can_rewind():
		v.add_child(UITheme.button("⟲ Rewind %d seconds (%d left)" % [int(TimeKeeper.REWIND_SECONDS), tk.charges], func():
			_toggle_pause()
			_rewind_now()))
	v.add_child(UITheme.button("Settings", func():
		var back_to := get_viewport().gui_get_focus_owner()   # this button, for the pad
		var p := SettingsPanel.new()
		c.remove_child(v)
		c.add_child(p)
		p.closed.connect(func():
			p.queue_free()
			c.add_child(v)
			if back_to:
				back_to.grab_focus())))
	v.add_child(UITheme.button("Controls", _show_controls))
	v.add_child(UITheme.button("Quit to menu", _to_menu))
	resume.grab_focus.call_deferred()


func _show_controls() -> void:
	if GameInput.using_pad:
		hud.show_message("Left stick move • Right stick aim • RT fire • LT aim • R3 club • L3+R3 first person", "A jump/glide • X pick up/open, or reload • L3 sprint • B crouch/crawl • LB/RB switch • D-pad ↓ heal ← drop → shoulder ↑ map • Start → Rewind", 6.0)
	else:
		hud.show_message("WASD move • Mouse aim • LMB fire • RMB aim • F club", "SPACE jump/glide • SHIFT sprint • CTRL crouch/crawl • R reload • E pick up • H heal • V camera • Q shoulder • M map • T rewind", 6.0)


# ---- rewind ----------------------------------------------------------------------------------------

func _rewind_now() -> void:
	var tk := match_manager.time_keeper
	if not tk.rewind() and hud:
		hud.show_message("No rewinds left" if tk.charges <= 0 else "Nothing to rewind yet", "", 1.5)


## A killing blow is on hold (see TimeKeeper): rewind ten seconds, or accept defeat?
func _offer_rewind(info: DamageInfo) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_offer = CanvasLayer.new()
	_offer.layer = 15
	add_child(_offer)
	var dim := ColorRect.new()
	dim.color = Color(0.08, 0.16, 0.24, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_offer.add_child(dim)
	var c := CenterContainer.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.theme = UITheme.theme()
	_offer.add_child(c)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	c.add_child(v)
	var t := UITheme.label("About to be beaten down!", 64, UITheme.CARROT, true)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var by := ""
	if info.attacker is Critter and info.attacker != match_manager.player:
		by = "by %s" % (info.attacker as Critter).display_name
	elif info.kind == DamageInfo.Kind.STORM:
		by = "by the Briar"
	elif info.kind == DamageInfo.Kind.FALL:
		by = "by the ground"
	var left := match_manager.time_keeper.charges
	var sub := UITheme.label(("%s   •   " % by if by else "") + "%d rewind%s left" % [left, "" if left == 1 else "s"], 26, UITheme.CREAM)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)
	var rw := UITheme.button("⟲ Rewind %d seconds" % int(TimeKeeper.REWIND_SECONDS), func(): _answer_offer(true))
	v.add_child(rw)
	v.add_child(UITheme.button("Accept defeat", func(): _answer_offer(false)))
	rw.grab_focus.call_deferred()


func _answer_offer(rewind_it: bool) -> void:
	if _offer == null:
		return
	_offer.queue_free()
	_offer = null
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	match_manager.time_keeper.resolve(rewind_it)


func _to_menu() -> void:
	KillCam.reset_time()   # (in case we leave mid slow-motion)
	get_tree().paused = false
	if Run.in_match:
		_finish_run_stop()   # (walking out of a run's match: it counts where you stood)
		GameSession.open_trail = true
	Run.in_match = false
	get_tree().change_scene_to_file(MENU_SCENE)


# ---- boons and runs ----------------------------------------------------------------------------

## An acorn shrine's draft: the match waits while you pick.
func _show_draft(choices: Array, title: String) -> void:
	if _draft or Settings.is_test_run():
		return
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_draft = CanvasLayer.new()
	_draft.layer = 16
	_draft.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_draft)
	var dim := ColorRect.new()
	dim.color = Color(0.1, 0.07, 0.02, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_draft.add_child(dim)
	var c := CenterContainer.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	_draft.add_child(c)
	var d := DraftPanel.new()
	d.heading = title
	d.choices = choices
	d.chosen.connect(func(id):
		match_manager.choose_boon(id)
		_draft.queue_free()
		_draft = null
		get_tree().paused = false
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED)
	c.add_child(d)


## The run's stop is over for you: goal, helmets, rewards (Run.finish_match). Once.
func _finish_run_stop() -> void:
	if not Run.in_match or not _run_result.is_empty() or match_manager == null or match_manager.player == null:
		return
	var p := match_manager.player
	var won := p.alive and match_manager.phase == MatchManager.Phase.ENDED
	var placement := p.placement if not p.alive else (1 if won else match_manager.alive_critters().size())
	var guns: Array = (p.inventory.weapons if p.alive else p.last_weapons).filter(func(w): return w != null and w != p.get_meta(&"stolen", null))
	_run_result = Run.finish_match(placement, match_manager.total, p.kills, won, guns, match_manager.time_keeper.charges, Boons.held)


## The end screen's line about the run.
func _run_line() -> String:
	var r := _run_result
	if r.is_empty():
		return ""
	if r.complete:
		return "RUN COMPLETE! +%d 🌰" % Run.COMPLETE_ACORNS
	if r.over:
		return "Goal missed. Your last acorn helmet cracked: the run is over."
	if r.met:
		return "Goal made! A boon waits for you on the Trail."
	return "Goal missed: an acorn helmet cracked (%d left)." % int(r.helmets)


# ---- end of match -------------------------------------------------------------------------------------

func _on_player_eliminated(placement: int, killer: Critter) -> void:
	rig.set_target(match_manager.player)
	if _replay_due():
		# you were the final shot: the end screen waits for the replay
		_after_replay = _on_player_eliminated_screen.bind(placement, killer)
		return
	_on_player_eliminated_screen(placement, killer)


func _on_player_eliminated_screen(placement: int, killer: Critter) -> void:
	Audio.play(&"defeat_sting", -2.0)
	var who := killer.display_name if killer and killer != match_manager.player else "the Briar"
	var sub := "You placed #%d of %d — taken out by %s" % [placement, match_manager.total, who]
	if killer and killer != match_manager.player:
		if killer.has_meta(&"new_rival"):
			sub += "\n%s the %s is now your RIVAL (%s). It'll be back." % [who, RivalBook.label_of(who), RivalBook.score(who)]
		elif RivalBook.is_rival(who):
			sub += "\nYour rival %s leads %d–%d." % [who, RivalBook.kills_on_you(who), RivalBook.your_kills(who)]
	_show_end("BEAT DOWN", sub, false, killer)


## The final shot gets a replay when it's yours (you won, or you were
## beaten down by it) or you're spectating it. Automated runs skip it.
func _replay_due() -> bool:
	var kc := match_manager.kill_cam
	if (Settings.is_test_run() and not GameSession.replays_in_tests) or kc == null or not kc.has_final():
		return false
	var p := match_manager.player
	return kc.shooter == p or kc.victim == p or _spectating


func _on_match_finished(winner: Critter, _placement: int) -> void:
	if _replay_due():
		hud.visible = false
		if _end:
			_end.visible = false
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		await match_manager.kill_cam.play_final()
		hud.visible = true
		if _end:
			_end.visible = true
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if _after_replay.is_valid():
		_after_replay.call()
		_after_replay = Callable()
	if winner == match_manager.player:
		GameSession.wins += 1
		Audio.play_music("victory")
		Audio.play(&"victory_fanfare", 0.0, 0.0)   # tuned and timed to the victory track: no jitter
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
	var half := minf(600.0, get_viewport().get_visible_rect().size.x * 0.5 - 24.0)   # (narrow windows too)
	v.offset_left = -half
	v.offset_right = half
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
	if not _paid:
		_paid = true
		_earned = Burrow.reward(1 if won else p.placement, match_manager.total, p.kills, match_manager.revenges) \
			+ (match_manager.bounty * (2 if Burrow.has_perk("bounty_hunter") else 1) if match_manager.bounty_paid else 0)
		if Run.in_match and Run.current().get("kind", "") == "golden":
			_earned *= 2
		_finish_run_stop()
		Burrow.add_acorns(_earned)
	var stats := UITheme.label("Beat downs: %d   •   Damage: %d   •   %s #%d   •   +%d 🌰 (%d in the Burrow)" % [p.kills, roundi(p.damage_dealt), island.map_title, _seed, _earned, Burrow.acorns()], 20, Color(UITheme.CREAM, 0.8))
	stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(stats)
	var tracker := UITheme.label(StatBook.match_line(), 20, Color(UITheme.CREAM, 0.8))
	tracker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tracker.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(tracker)
	if Run.in_match:
		var rl := UITheme.label(_run_line(), 26, UITheme.LEAF if _run_result.get("met", false) else UITheme.BERRY, true)
		rl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(rl)
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
	var again: Button
	if Run.in_match:
		again = UITheme.button("Back to the Trail", _to_menu)
		row.add_child(again)
	else:
		again = UITheme.button("Play again", func(): get_tree().reload_current_scene())
		row.add_child(again)
		row.add_child(UITheme.button("Rematch (same seed)", func():
			GameSession.replay_seed = _seed
			get_tree().reload_current_scene()))
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
