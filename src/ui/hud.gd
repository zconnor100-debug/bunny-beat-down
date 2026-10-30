class_name HUD
extends CanvasLayer
## In-match heads-up display: vitals, weapons, crosshair with live spread,
## hit markers, damage direction, blood on the lens, kill feed, Briar timer,
## minimap, prompts.

const SPLAT_LIFE := 3.0        ## seconds a splat stays on screen (plus up to 1 s)
const MAX_SPLATS := 12
const REWIND_SHADER := preload("res://src/ui/rewind_fx.gdshader")

var player: Critter
var rig: CameraRig
var match_manager: MatchManager

var _root: Control
var _screen: Control   # (full-screen effects, under _root)
var _overlay: HUDOverlay
var _alive_label: Label
var _kills_label: Label
var _storm_label: Label
var _message: Label
var _sub_message: Label
var _hint: Label
var _ammo_label: Label
var _weapon_name: Label
var _slots: Array[GunBadge] = []
var _clovers: ItemBadge
var _shields: ItemBadge
var _grenades: ItemBadge
var _arsenal_label: Label          ## your arsenal: beat-downs to go, or ready to call in (Arsenal)
var _call_menu: CallInMenu         ## the pick of your arsenal's guns, calling it in
var _pc: PlayerController
var _rewind_label: Label
var _news_frame := -1          # the frame a rival's news (REVENGE!...) was shown
var _rewind_tint: ColorRect
var _rewind_fx: CanvasLayer        ## the tape-rewinding look while the world runs back
var _feed: VBoxContainer
## Lifetime beat-downs with each gun (StatBook), shown by its name like a
## kill counter; refreshed whenever you beat someone down.
var _tracked: Dictionary = {}
## The crosshair's Workshop look (read once a match).
var reticle_style := "cross"
var reticle_color := Color(1, 1, 1, 0.92)
var _minimap: Minimap
var _bigmap: Minimap
var _storm_tint: ColorRect
var _hurt_tint: ColorRect
var _blood: Control
var _splats: Array = []        # [TextureRect, seconds left, starting alpha]
var _hit_flash := 0.0
var _fps: Label
var _message_t := 0.0
var _run_label: Label        ## a run's stop: its goal (and once you've made it)
var _hunt_label: Label       ## the nemesis hunting you: how far, which way
var _boons_label: Label
var _boons_key := ""
var _boss_bar: BossBar             ## a Boss Battle's boss (top centre)
var _mission_bar: MissionBar       ## a Kernel Hunt mission's Barn (top centre)
const ARROWS := ["↑", "↖", "←", "↙", "↓", "↘", "→", "↗"]


func setup(player_: Critter, rig_: CameraRig, mm: MatchManager) -> void:
	player = player_
	rig = rig_
	match_manager = mm
	layer = 5
	# full-screen effects (tints, blood, the crosshair and scope overlay) span
	# the whole screen; the readouts sit in _root, which on a wide screen can
	# be kept to a 21:9 or 16:9 column (Settings hud_width)
	_screen = Control.new()
	_screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	_screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_screen.theme = UITheme.theme()
	add_child(_screen)
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = UITheme.theme()
	add_child(_root)
	get_viewport().size_changed.connect(_fit_width)
	Settings.changed.connect(func(key): if key == &"hud_width": _fit_width())
	_fit_width()

	_storm_tint = _tint(Color(0.45, 0.1, 0.6, 0.0))
	_hurt_tint = _tint(Color(0.7, 0.0, 0.05, 0.0))
	_blood = Control.new()
	_blood.set_anchors_preset(Control.PRESET_FULL_RECT)
	_blood.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_screen.add_child(_blood)

	_overlay = HUDOverlay.new()
	_overlay.hud = self
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_screen.add_child(_overlay)

	# top-left: alive + kills
	var tl := VBoxContainer.new()
	tl.position = Vector2(28, 20)
	_root.add_child(tl)
	_alive_label = UITheme.label("24 CRITTERS LEFT", 28, UITheme.CREAM, true)
	_kills_label = UITheme.label("BEAT DOWNS: 0", 22)
	tl.add_child(_alive_label)
	tl.add_child(_kills_label)
	_run_label = UITheme.label("", 20, UITheme.CARROT_LIGHT)
	tl.add_child(_run_label)

	# top-centre: Briar timer + messages
	_storm_label = UITheme.label("", 24)
	_storm_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_storm_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_storm_label.position.y = 18
	_storm_label.size.x = 600
	_storm_label.position.x = -300
	_root.add_child(_storm_label)
	if mm and mm.mode in ["boss", "kernel"] and mm.boss:
		_boss_bar = BossBar.new(mm.boss, mm)
		_boss_bar.hide_waiting = mm.mode == "kernel"   # (a mission's boss: the mission's bar is up till it's here)
		_boss_bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
		_boss_bar.offset_left = -BossBar.WIDTH * 0.5
		_boss_bar.offset_right = BossBar.WIDTH * 0.5
		_boss_bar.offset_top = 12
		_root.add_child(_boss_bar)
	if mm and mm.mode == "kernel" and mm.mission:
		_mission_bar = MissionBar.new(mm.mission)
		_mission_bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
		_mission_bar.offset_left = -MissionBar.WIDTH * 0.5
		_mission_bar.offset_right = MissionBar.WIDTH * 0.5
		_mission_bar.offset_top = 12
		_root.add_child(_mission_bar)
	_hunt_label = UITheme.label("", 24, Color(1.0, 0.4, 0.38), true)
	_hunt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hunt_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_hunt_label.offset_left = -300
	_hunt_label.offset_right = 300
	_hunt_label.offset_top = 54
	_root.add_child(_hunt_label)
	_message = UITheme.label("", 54, UITheme.CARROT_LIGHT, true)
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_message.offset_left = -700
	_message.offset_right = 700
	_message.offset_top = 150
	_root.add_child(_message)
	_sub_message = UITheme.label("", 26)
	_sub_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub_message.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_sub_message.offset_left = -700
	_sub_message.offset_right = 700
	_sub_message.offset_top = 222
	_root.add_child(_sub_message)

	# bottom-centre: interact hint
	_hint = UITheme.label("", 26, UITheme.CREAM)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_hint.offset_left = -500
	_hint.offset_right = 500
	_hint.offset_top = -230
	_root.add_child(_hint)

	# bottom-right: weapons
	var br := VBoxContainer.new()
	br.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	br.offset_left = -470
	br.offset_top = -280
	br.offset_right = -28
	br.offset_bottom = -24
	br.grow_horizontal = Control.GROW_DIRECTION_BEGIN   # (wider than its box: it grows left, not off the screen)
	br.grow_vertical = Control.GROW_DIRECTION_BEGIN
	br.alignment = BoxContainer.ALIGNMENT_END
	_root.add_child(br)
	_weapon_name = UITheme.label("", 24, UITheme.CREAM)
	_weapon_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	br.add_child(_weapon_name)
	_ammo_label = UITheme.label("", 46, UITheme.CREAM, true)
	_ammo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	br.add_child(_ammo_label)
	# what you carry to use, above the gun slots: carrot grenades, Acorn Shields
	# and lucky clovers
	var items := HBoxContainer.new()
	items.alignment = BoxContainer.ALIGNMENT_END
	items.add_theme_constant_override("separation", 10)
	br.add_child(items)
	_grenades = ItemBadge.new("grenade")
	items.add_child(_grenades)
	_shields = ItemBadge.new("shield")
	items.add_child(_shields)
	_clovers = ItemBadge.new("clover")
	items.add_child(_clovers)
	var slots := HBoxContainer.new()
	slots.alignment = BoxContainer.ALIGNMENT_END
	slots.add_theme_constant_override("separation", 10)
	br.add_child(slots)
	for i in Inventory.SLOTS:
		var gb := GunBadge.new(i)
		slots.add_child(gb)
		_slots.append(gb)

	# bottom-left: your arsenal (bars are drawn by the overlay)
	_arsenal_label = UITheme.label("", 22, UITheme.CREAM)
	_arsenal_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_arsenal_label.offset_left = 30
	_arsenal_label.offset_top = -252
	_root.add_child(_arsenal_label)
	_call_menu = CallInMenu.new()
	_call_menu.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_call_menu.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_call_menu.grow_vertical = Control.GROW_DIRECTION_BOTH
	_call_menu.offset_top = 150
	_call_menu.offset_bottom = 150
	_call_menu.visible = false
	_root.add_child(_call_menu)
	_rewind_label = UITheme.label("", 20, Color("9fe3ff"))
	_rewind_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_rewind_label.offset_left = 30
	_rewind_label.offset_top = -184
	_root.add_child(_rewind_label)
	_boons_label = UITheme.label("", 18, Color(1.0, 0.85, 0.55))
	_boons_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_boons_label.offset_left = 30
	_boons_label.offset_top = -214
	_boons_label.offset_right = 760
	_boons_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_root.add_child(_boons_label)
	_rewind_tint = _tint(Color(0.55, 0.85, 1.0, 0.0))
	if mm and mm.time_keeper:
		mm.time_keeper.rewound.connect(_on_rewound)
		mm.time_keeper.rewinding.connect(_on_rewinding)

	# top-right: minimap + kill feed
	_minimap = Minimap.new()
	_minimap.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_minimap.offset_left = -258
	_minimap.offset_right = -28
	_minimap.offset_top = 24
	_minimap.offset_bottom = 254
	_minimap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_minimap)
	_feed = VBoxContainer.new()
	_feed.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_feed.offset_left = -560
	_feed.offset_right = -28
	_feed.offset_top = 270
	_feed.alignment = BoxContainer.ALIGNMENT_BEGIN
	_root.add_child(_feed)

	_bigmap = Minimap.new()
	_bigmap.full = true
	_bigmap.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_bigmap.offset_left = -430
	_bigmap.offset_right = 430
	_bigmap.offset_top = -430
	_bigmap.offset_bottom = 430
	_bigmap.visible = false
	_bigmap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_bigmap)

	_fps = UITheme.label("", 16)
	_fps.position = Vector2(28, 1040)
	_fps.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_fps.offset_top = -28
	_fps.offset_left = 10
	_root.add_child(_fps)

	Events.critter_died.connect(_on_critter_died)
	Events.critter_died.connect(func(_v, _i): _tracked.clear())   # (the counters move on)
	Events.taunt.connect(_on_taunt)
	Events.headline.connect(_on_headline)
	reticle_style = Workshop.look("reticle")
	reticle_color = Color(Workshop.color(Workshop.look("reticle_color")), 0.92)
	Events.rival_news.connect(func(t, sub):
		_news_frame = Engine.get_process_frames()
		show_message(t, sub, 4.0))
	Events.announce.connect(func(t, sub): show_message(t, sub, 5.0))
	Events.alive_count_changed.connect(_show_alive)
	# (the match announced its head count before this HUD existed: start from it)
	if match_manager:
		_show_alive(match_manager.alive_critters().size(), match_manager.total)
	Events.player_hit_confirmed.connect(_overlay.on_hit_confirmed)
	Events.critter_damaged.connect(_on_damaged)
	Events.item_picked_up.connect(_on_picked_up)
	Events.supply_drop_incoming.connect(func(_pos):
		Audio.play(&"match_countdown_beep", -4.0)
		show_message("Supply drop incoming!", "Golden carrots inbound — check your map", 3.5))
	var pc_node := player.get_node_or_null("PlayerController") as PlayerController
	_pc = pc_node
	if pc_node:
		pc_node.interact_hint_changed.connect(func(t): _hint.text = t)


func attach_island(island: Island, storm: Storm) -> void:
	for m in [_minimap, _bigmap]:
		m.build(island)
		m.storm = storm
		m.player = player


func _show_alive(a: int, _total: int) -> void:
	if match_manager and match_manager.mode == "teams":
		var left := match_manager.team_counts()
		_alive_label.text = "YOUR TEAM %d  •  THEIRS %d" % [left[1], left[2]]
		return
	if match_manager and match_manager.mode == "kernel":
		var left := match_manager.team_counts()
		_alive_label.text = "YOUR SIDE %d  •  TOUCHED %d" % [left[1], left[2]]
		return
	_alive_label.text = "%d CRITTER%s LEFT" % [a, "" if a == 1 else "S"]


func attach_dropship(d: Dropship) -> void:
	_minimap.dropship = d
	_bigmap.dropship = d


## The world is running backwards (the match is paused, so this layer runs
## regardless): an old tape rewinding, a countdown of the seconds going
## back, and a high whirr.
func _on_rewinding() -> void:
	if _rewind_fx:
		_rewind_fx.queue_free()
	_rewind_fx = CanvasLayer.new()
	_rewind_fx.layer = 13
	_rewind_fx.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_rewind_fx)
	var screen := ColorRect.new()
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := ShaderMaterial.new()
	m.shader = REWIND_SHADER
	screen.material = m
	_rewind_fx.add_child(screen)
	var title := UITheme.label("◀◀  REWIND", 56, Color("9fe3ff"), true)
	title.position = Vector2(52, 44)
	_rewind_fx.add_child(title)
	var count := UITheme.label("", 30, Color("9fe3ff"))
	count.position = Vector2(58, 116)
	_rewind_fx.add_child(count)
	var tw := _rewind_fx.create_tween()
	tw.tween_method(func(v: float): count.text = "−%.1f s" % v, 0.0, match_manager.time_keeper.depth(), TimeKeeper.PLAYBACK)
	var whirr := Audio.make_loop(&"wind_loop", _rewind_fx, false) as AudioStreamPlayer
	if whirr:
		whirr.pitch_scale = 2.6
		whirr.volume_db = -4.0
		whirr.play()
	Audio.play(&"glider_open", -4.0, 0.0)


func _on_rewound() -> void:
	if _rewind_fx:
		# the tape catches: the effect fades out over the flash
		var fx := _rewind_fx
		_rewind_fx = null
		var screen := fx.get_child(0) as ColorRect
		var tw := fx.create_tween()
		tw.tween_method(func(v: float): (screen.material as ShaderMaterial).set_shader_parameter(&"amount", v), 1.0, 0.0, 0.25)
		tw.tween_callback(fx.queue_free)
	_rewind_tint.color.a = 0.55
	for s in _splats:
		s[1] = 0.0   # the blood on the lens hasn't happened yet either
	_hit_flash = 0.0
	_overlay._dirs.clear()
	_overlay._numbers.clear()
	var left := match_manager.time_keeper.charges
	show_message("⟲ REWOUND %d SECONDS" % int(TimeKeeper.REWIND_SECONDS), "%d rewind%s left" % [left, "" if left == 1 else "s"] if left > 0 else "That was your last rewind", 2.5)
	Audio.play(&"glider_open", -2.0, 0.0)


## The readouts kept to a column as wide as Settings hud_width asks (on a
## screen wider than that; full width otherwise).
func _fit_width() -> void:
	if _root == null or not is_inside_tree():
		return
	var view := get_viewport().get_visible_rect().size
	var aspect: float = Graphics.HUD_ASPECT[clampi(int(Settings.get_value(&"hud_width")), 0, Graphics.HUD_ASPECT.size() - 1)]
	var side := maxf(0.0, (view.x - aspect * view.y) * 0.5) if aspect > 0.0 else 0.0
	_root.offset_left = side
	_root.offset_right = -side


func _tint(c: Color) -> ColorRect:
	var r := ColorRect.new()
	r.color = c
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_screen.add_child(r)
	return r


## A run's goal, your boons, and the nemesis hunting you (distance and the
## way to turn to face it).
func _update_run_and_hunt() -> void:
	if match_manager == null:
		return
	if not match_manager.run_goal.is_empty():
		_run_label.text = ("✓ GOAL MET" if match_manager.run_goal_met else "GOAL: %s" % Run.goal_text(match_manager.total)) \
			+ "   " + "🌰".repeat(Run.helmets())
		_run_label.add_theme_color_override("font_color", UITheme.LEAF if match_manager.run_goal_met else UITheme.CARROT_LIGHT)
	var key := str(Boons.held)
	if key != _boons_key:
		_boons_key = key
		_boons_label.text = "" if Boons.held.is_empty() else "🌱 " + Boons.summary()
	var n := match_manager.nemesis
	if n and is_instance_valid(n) and n.alive and n.state == Critter.State.GROUND:
		var to := n.global_position - player.global_position
		var rel := wrapf(atan2(-to.x, -to.z) - player.look_yaw, -PI, PI)
		var arrow: String = ARROWS[posmod(roundi(rel / (PI / 4.0)), 8)]
		_hunt_label.text = "☠ NEMESIS %s  ·  %d m %s" % [n.display_name, roundi(to.length()), arrow]
	else:
		_hunt_label.text = ""


func show_message(text: String, sub := "", seconds := 3.0) -> void:
	_message.text = text
	_sub_message.text = sub
	_message_t = seconds
	_message.modulate.a = 1.0
	_sub_message.modulate.a = 1.0
	_message.pivot_offset = _message.size * 0.5
	_message.scale = Vector2(1.25, 1.25)
	var tw := create_tween()
	tw.tween_property(_message, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _process(delta: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	_kills_label.text = "BEAT DOWNS: %d" % player.kills
	_update_run_and_hunt()
	var w := player.current_weapon()
	if w:
		if not _tracked.has(w.data.id):
			_tracked[w.data.id] = int(StatBook.gun(w.data.id).kills)
		_weapon_name.text = "%s   ⚔ %d" % [w.display_name(), _tracked[w.data.id]]
		_weapon_name.add_theme_color_override("font_color", Rarity.COLORS[w.rarity])
		var reserve: int = player.inventory.ammo[w.data.ammo_type]
		_ammo_label.text = "RELOADING…" if player.is_reloading() else "%d  |  %d" % [w.ammo_in_mag, reserve]
	else:
		_weapon_name.text = "Paws only — find a carrot gun!"
		_weapon_name.add_theme_color_override("font_color", UITheme.CREAM)
		_ammo_label.text = ""
	for i in _slots.size():
		_slots[i].show_gun(player.inventory.weapons[i], i == player.current_slot)
	_clovers.show_count(player.inventory.clovers, Inventory.MAX_CLOVERS, GameInput.prompt(&"heal"))
	_shields.show_count(player.inventory.shields, Inventory.MAX_SHIELDS, GameInput.prompt(&"shield"))
	_grenades.show_count(player.inventory.grenades, Inventory.MAX_GRENADES, GameInput.prompt(&"grenade"))
	_arsenal_label.text = ""
	_call_menu.visible = _pc != null and _pc.call_menu and player.alive
	if _call_menu.visible:
		_call_menu.show_pick(Arsenal.unlocked(), _pc.call_choice)
	if _pc and _pc.flare_gun != &"" and player.alive:
		var data := WeaponDB.get_weapon(_pc.flare_gun)
		_arsenal_label.text = "A flare for your %s: hold [%s] to aim it, let go to throw" % [data.display_name if data else "gun", GameInput.prompt(&"call_in")]
		_arsenal_label.add_theme_color_override("font_color", UITheme.CARROT_LIGHT)
	elif match_manager and match_manager.phase == MatchManager.Phase.PLAYING and player.alive and not match_manager.called_in \
			and not Arsenal.unlocked().is_empty():
		var to_go := Arsenal.CALL_AT - match_manager.player_beat_downs
		var b := match_manager.boss
		if match_manager.mode == "boss" and b and b.state == Boss.State.WAITING and to_go > 0:
			to_go = 1   # (not yet: cream, not carrot)
			_arsenal_label.text = "Your arsenal: ready when %s turns up" % b.display_name
		elif match_manager.mode == "boss" and b:
			to_go = 0
			_arsenal_label.text = "Your arsenal is ready: [%s] to call it in" % GameInput.prompt(&"call_in")
		else:
			_arsenal_label.text = "Your arsenal is ready: [%s] to call it in" % GameInput.prompt(&"call_in") if to_go <= 0 \
				else "Your arsenal: %d more beat-down%s to call it in" % [to_go, "" if to_go == 1 else "s"]
		_arsenal_label.add_theme_color_override("font_color", UITheme.CARROT_LIGHT if to_go <= 0 else UITheme.CREAM)
	var tk := match_manager.time_keeper if match_manager else null
	if tk and match_manager.phase == MatchManager.Phase.PLAYING and player.alive:
		var how := "pause menu" if GameInput.using_pad else "[%s]" % GameInput.prompt(&"rewind")
		_rewind_label.text = "⟲ Rewinds: %d   %s" % [tk.charges, how] if tk.charges > 0 else "⟲ No rewinds left"
	else:
		_rewind_label.text = ""
	_rewind_tint.color.a = maxf(0.0, _rewind_tint.color.a - delta * 0.9)

	# Briar status
	var storm := match_manager.storm if match_manager else null
	if storm and storm.active:
		var t := int(ceil(storm.time_left))
		var mmss := "%d:%02d" % [t / 60, t % 60]
		var title: String = Storm.VARIANTS[storm.variant].title
		if storm.nap_left > 0.0:
			_storm_label.text = "%s is napping  %d" % [title, ceili(storm.nap_left)]
		else:
			_storm_label.text = ("%s IS CLOSING  %s" % [title.to_upper(), mmss]) if storm.shrinking else ("%s closes in %s" % [title, mmss])
		_storm_label.add_theme_color_override("font_color", Color("d9a0ff") if storm.shrinking else UITheme.CREAM)
		var outside := not storm.is_safe(player.global_position) and player.alive
		_storm_tint.color.a = lerpf(_storm_tint.color.a, 0.28 if outside else 0.0, IKMath.damp(4.0, delta))
	elif match_manager and match_manager.phase == MatchManager.Phase.DROPPING:
		var ride := _minimap.dropship.display_name() if _minimap.dropship and is_instance_valid(_minimap.dropship) and _minimap.dropship.vehicle != &"balloon" else "picnic balloon"
		_storm_label.text = "Riding the %s" % ride if player.state == Critter.State.IN_DROPSHIP else "Critters are still dropping in…"
	else:
		_storm_label.text = ""
	var hurt := clampf(1.0 - player.health / 35.0, 0.0, 1.0) if player.alive else 0.0
	_hit_flash = maxf(0.0, _hit_flash - delta * 1.6)
	_hurt_tint.color.a = hurt * (0.18 + 0.06 * sin(Time.get_ticks_msec() * 0.008)) + _hit_flash * 0.5
	for s in _splats:
		s[1] -= delta
		var tr: TextureRect = s[0]
		tr.modulate.a = s[2] * clampf(s[1] / 1.2, 0.0, 1.0)
		tr.position.y += delta * 6.0   # runs down the lens
	for s in _splats.filter(func(s): return s[1] <= 0.0):
		(s[0] as Node).queue_free()
	_splats = _splats.filter(func(s): return s[1] > 0.0)

	_message_t -= delta
	if _message_t < 0.6:
		_message.modulate.a = maxf(0.0, _message_t / 0.6)
		_sub_message.modulate.a = _message.modulate.a
	_bigmap.visible = Input.is_action_pressed(&"map")
	_minimap.visible = not _bigmap.visible
	_fps.visible = Settings.get_value(&"show_fps")
	if _fps.visible:
		_fps.text = "%d FPS" % Engine.get_frames_per_second()


func _on_critter_died(victim: Node, info: DamageInfo) -> void:
	var killer := info.attacker as Critter
	var v := victim as Critter
	var how := "the Briar" if info.kind == DamageInfo.Kind.STORM else ""
	if killer and info.weapon_id != &"":
		var data := WeaponDB.get_weapon(info.weapon_id)
		how = data.display_name if data else String(info.weapon_id)
	if info.kind == DamageInfo.Kind.BLEED:
		how = "thorns"
	var line: String
	if info.attacker is Boss:
		var b := info.attacker as Boss
		line = "☠ %s  ▸ %s ▸  %s" % [b.display_name, b.attack_name(info.weapon_id), v.display_name]
	elif killer and killer != v:
		line = "%s  ▸ %s ▸  %s%s" % [killer.display_name, how, v.display_name, "  ✦" if info.headshot else ""]
	elif info.kind == DamageInfo.Kind.STORM:
		line = "%s got lost in the Briar" % v.display_name
	elif info.weapon_id == &"toy_train":
		line = "%s got bonked by the toy train" % v.display_name
	else:
		line = "%s had a little accident" % v.display_name
	var col := UITheme.CARROT_LIGHT if (killer == player or v == player) else UITheme.CREAM
	if v.team != 0 and player and v.team == player.team and v != player:
		col = Color(0.55, 0.8, 1.0)   # (one of your team down)
	elif info.attacker is Boss:
		col = Color(1.0, 0.5, 0.42)
	var l := UITheme.label(line, 19, col)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_feed.add_child(l)
	while _feed.get_child_count() > 6:
		var oldest := _feed.get_child(0)
		_feed.remove_child(oldest)
		oldest.queue_free()
	Despawner.after(l, 7.0, func(n: Node):
		var tw := n.create_tween()
		tw.tween_property(n, "modulate:a", 0.0, 0.6)
		tw.tween_callback(n.queue_free))
	if killer == player and v != player:
		Audio.play(&"kill_confirm", -2.0)
		if _news_frame != Engine.get_process_frames():   # (a REVENGE! banner wins over this one)
			show_message("BEAT DOWN!", "%s is out%s" % [v.display_name, " — headshot!" if info.headshot else ""], 2.2)


const SPEECH := Color(0.88, 0.72, 1.0)
const NEWS := Color(1.0, 0.84, 0.42)


## Lobby news (MatchManager.headlines, a bot turning radical, a grudge paid back).
func _on_headline(text: String) -> void:
	var l := UITheme.label("📣 %s" % text, 19, NEWS)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_feed.add_child(l)
	while _feed.get_child_count() > 6:
		var oldest := _feed.get_child(0)
		_feed.remove_child(oldest)
		oldest.queue_free()
	Despawner.after(l, 9.0, func(n: Node):
		var tw := n.create_tween()
		tw.tween_property(n, "modulate:a", 0.0, 0.6)
		tw.tween_callback(n.queue_free))


func _on_taunt(c: Node, text: String) -> void:
	var critter := c as Critter
	if critter == null or not is_instance_valid(critter):
		return
	var l := UITheme.label("💬 %s: “%s”" % [critter.display_name, text], 19, SPEECH)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_feed.add_child(l)
	while _feed.get_child_count() > 6:
		var oldest := _feed.get_child(0)
		_feed.remove_child(oldest)
		oldest.queue_free()
	Despawner.after(l, 8.0, func(n: Node):
		var tw := n.create_tween()
		tw.tween_property(n, "modulate:a", 0.0, 0.6)
		tw.tween_callback(n.queue_free))
	if critter.visual and critter.alive:
		critter.visual.say(text)


func _on_damaged(victim: Node, info: DamageInfo) -> void:
	if victim != player or info.attacker == null or info.attacker == player:
		return
	_overlay.add_damage_direction((info.attacker as Node3D).global_position)
	_splatter(info)
	if info.attacker is Critter and (info.attacker as Critter).alive:
		(info.attacker as Critter).visual.reveal_name_tag(3.0)   # who's shooting


## Blood on the lens: a few splats on the side the shot came from, more and
## bigger for harder hits, plus a red flash. Stuffing with Plushie gore; just
## the flash with gore off.
func _splatter(info: DamageInfo) -> void:
	_hit_flash = minf(0.45, _hit_flash + clampf(info.amount / 40.0, 0.12, 0.35))
	if Settings.gore == Settings.Gore.OFF:
		return
	var col := Color(0.55, 0.02, 0.03) if Settings.gore == Settings.Gore.BLOOD else Color(0.96, 0.92, 0.84)
	var view := _root.size
	var from := Vector2.ZERO   # where the shooter is on screen: up = ahead, down = behind
	if rig and info.attacker is Node3D:
		var local := rig.camera.global_basis.inverse() * ((info.attacker as Node3D).global_position - player.global_position)
		from = Vector2(local.x, local.z).normalized()
	for i in clampi(roundi(info.amount / 8.0), 1, 5):
		var dir := from.rotated(randf_range(-0.9, 0.9)) if from != Vector2.ZERO else Vector2.from_angle(randf() * TAU)
		var pos := view * 0.5 + dir * view * Vector2(randf_range(0.28, 0.48), randf_range(0.25, 0.45))
		var side := randf_range(130.0, 260.0) * clampf(info.amount / 20.0, 0.8, 1.7)
		var tr := TextureRect.new()
		tr.texture = FXTextures.splat(randi() % 6, col)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_SCALE
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tr.size = Vector2(side, side)
		tr.position = pos - tr.size * 0.5
		tr.pivot_offset = tr.size * 0.5
		tr.rotation = randf() * TAU
		var a := randf_range(0.7, 0.92)
		tr.modulate.a = a
		_blood.add_child(tr)
		_splats.append([tr, SPLAT_LIFE + randf(), a])
	while _splats.size() > MAX_SPLATS:
		(_splats.pop_front()[0] as Node).queue_free()


## Splats on screen right now (tests).
func splat_count() -> int:
	return _splats.size()


func _on_picked_up(who: Node, what: String) -> void:
	if who == player and what != "crate":
		_overlay.add_toast("+ " + what)


class HUDOverlay:
	extends Control
	## Everything drawn immediate-mode: crosshair, hit markers, damage arcs,
	## vitals bars, floating damage numbers and pickup toasts.

	var hud: HUD
	var _hit_t := 0.0
	var _hit_kill := false
	var _hit_head := false
	var _dirs: Array = []      # [world_pos, time_left]
	var _numbers: Array = []   # [world_pos, text, time_left, color]
	var _toasts: Array = []    # [text, time_left]
	const DIR_LIFE := 2.2      # seconds a damage-direction marker shows

	func on_hit_confirmed(victim: Node, damage: float, headshot: bool, killed: bool) -> void:
		_hit_t = 0.22
		_hit_kill = killed
		_hit_head = headshot
		var pos := (victim as Boss).last_hit_pos if victim is Boss \
			else (victim as Critter).get_eye_position() + Vector3(randf_range(-0.3, 0.3), 0.3, randf_range(-0.3, 0.3))
		_numbers.append([pos, "%d" % roundi(damage), 0.9, Color("ffd34d") if headshot else UITheme.CREAM])
		Audio.play(&"headshot" if headshot else &"carrot_impact_flesh", -6.0 if headshot else -10.0)

	func add_damage_direction(from: Vector3) -> void:
		_dirs.append([from, DIR_LIFE])

	func add_toast(text: String) -> void:
		_toasts.append([text, 2.0])
		if _toasts.size() > 4:
			_toasts.pop_front()

	func _process(delta: float) -> void:
		_hit_t = maxf(0.0, _hit_t - delta)
		for d in _dirs:
			d[1] -= delta
		_dirs = _dirs.filter(func(d): return d[1] > 0.0)
		for n in _numbers:
			n[2] -= delta
			n[0] += Vector3.UP * delta * 0.8
		_numbers = _numbers.filter(func(n): return n[2] > 0.0)
		for t in _toasts:
			t[1] -= delta
		_toasts = _toasts.filter(func(t): return t[1] > 0.0)
		queue_redraw()

	func _draw() -> void:
		if hud == null or hud.player == null or not is_instance_valid(hud.player):
			return
		var p := hud.player
		var c := size * 0.5
		var font := UITheme.text_font(700)
		if hud.rig and hud.rig.scoped:
			_draw_scope(c)
		# crosshair: gap follows the real spread cone
		elif p.alive and p.current_weapon() and p.state == Critter.State.GROUND and not (hud.rig and hud.rig.first_person and p.want_aim):
			var cam := hud.rig.camera
			var spread := deg_to_rad(p.current_spread_deg())
			var gap := tan(spread) / tan(deg_to_rad(cam.fov) * 0.5) * size.y * 0.5 + 4.0
			Reticle.draw(self, c, gap, hud.reticle_style, hud.reticle_color)
		# unlocking a treasure chest: progress bar under the crosshair
		var pcn := p.get_node_or_null("PlayerController") as PlayerController
		var crate := pcn.focused_crate() if pcn else null
		if crate and crate.open_time > 0.0 and crate.channeler() == p and not crate.opened:
			var bw := 260.0
			var bp := c + Vector2(-bw * 0.5, 70.0)
			draw_style_box(_box(Color(UITheme.INK, 0.75), 9), Rect2(bp, Vector2(bw, 18)))
			draw_style_box(_box(Rarity.COLORS[Rarity.Tier.GOLDEN], 7), Rect2(bp + Vector2(3, 3), Vector2((bw - 6) * crate.progress, 12)))
			var label := "%s %s… %.1f s" % [crate.channel_verb, crate.display_name, (1.0 - crate.progress) * crate.open_time]
			draw_string_outline(font, bp + Vector2(0, -8), label, HORIZONTAL_ALIGNMENT_CENTER, bw, 18, 5, Color(0, 0, 0, 0.8))
			draw_string(font, bp + Vector2(0, -8), label, HORIZONTAL_ALIGNMENT_CENTER, bw, 18, UITheme.CREAM)
		# hit marker
		if _hit_t > 0.0:
			var hc := Color("ff4d4d") if _hit_kill else (Color("ffd34d") if _hit_head else Color.WHITE)
			var s := 9.0 + (1.0 - _hit_t / 0.22) * 4.0
			for d in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
				draw_line(c + d * s, c + d * (s + 9.0), hc, 3.0)
		# where the damage came from
		if hud.rig:
			var cam_basis := hud.rig.camera.global_basis
			for d in _dirs:
				var to: Vector3 = d[0] - p.global_position
				var local := cam_basis.inverse() * to
				var ang := atan2(local.x, -local.z)
				var a := clampf(d[1] / DIR_LIFE * 1.5, 0.0, 1.0)
				var col := Color(1, 0.2, 0.15, 0.85 * a)
				draw_arc(c, 150.0, ang - PI / 2 - 0.45, ang - PI / 2 + 0.45, 24, Color(0, 0, 0, 0.35 * a), 16.0)
				draw_arc(c, 150.0, ang - PI / 2 - 0.45, ang - PI / 2 + 0.45, 24, col, 11.0)
				# and an arrowhead pointing at the shooter
				var dir := Vector2.from_angle(ang - PI / 2)
				var tip := c + dir * 184.0
				draw_colored_polygon(PackedVector2Array([tip, c + dir * 160.0 + dir.orthogonal() * 16.0, c + dir * 160.0 - dir.orthogonal() * 16.0]), col)
		# where to go next (a Kernel Hunt mission's: the lit carrot, a ring still to catch, Boulder Bluff)
		if hud.rig:
			_draw_objectives(hud.rig.camera, p, font)
		# vitals (in the HUD's column on a wide screen: hud_width)
		var bx := 30.0 + hud._root.offset_left
		var by := size.y - 132.0
		var w := 480.0
		_bar(Vector2(bx, by), w, 30.0, p.armor / p.max_armor, UITheme.ACORN, "SHIELD %d" % roundi(p.armor), font)
		_bar(Vector2(bx, by + 40.0), w, 42.0, p.health / p.max_health, Color("5fc23a") if p.health > 35 else UITheme.BERRY, "HP %d" % roundi(p.health), font)
		# damage numbers
		if hud.rig:
			var cam := hud.rig.camera
			for n in _numbers:
				if cam.is_position_behind(n[0]):
					continue
				var sp := cam.unproject_position(n[0])
				var a: float = clampf(n[2] / 0.4, 0.0, 1.0)
				draw_string_outline(font, sp, n[1], HORIZONTAL_ALIGNMENT_CENTER, -1, 30, 6, Color(0, 0, 0, a))
				draw_string(font, sp, n[1], HORIZONTAL_ALIGNMENT_CENTER, -1, 30, Color(n[3], a))
		# pickup toasts
		var ty := size.y - 300.0
		for t in _toasts:
			var a: float = clampf(t[1] / 0.5, 0.0, 1.0)
			draw_string_outline(font, Vector2(30 + hud._root.offset_left, ty), t[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 20, 5, Color(0, 0, 0, 0.8 * a))
			draw_string(font, Vector2(30 + hud._root.offset_left, ty), t[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(UITheme.CREAM, a))
			ty -= 26.0

	var _boxes: Dictionary = {}

	func _box(col: Color, radius: int) -> StyleBoxFlat:
		var key := "%s|%d" % [col.to_html(), radius]
		if not _boxes.has(key):
			var sb := StyleBoxFlat.new()
			sb.bg_color = col
			sb.set_corner_radius_all(radius)
			_boxes[key] = sb
		return _boxes[key]

	## Sniper scope: black surround with a round lens, fine reticle and mil-dots.
	func _draw_scope(c: Vector2) -> void:
		var r := size.y * 0.42
		var outer := size.length()
		# a very thick ring covers everything outside the lens
		draw_arc(c, r + outer * 0.5, 0.0, TAU, 180, Color.BLACK, outer, true)
		draw_arc(c, r, 0.0, TAU, 180, Color(0.15, 0.1, 0.05), 6.0, true)
		var ink := Color(0.02, 0.02, 0.02, 0.9)
		draw_line(c - Vector2(r, 0), c + Vector2(r, 0), ink, 1.5)
		draw_line(c - Vector2(0, r), c + Vector2(0, r), ink, 1.5)
		draw_line(c - Vector2(r, 0), c - Vector2(r * 0.55, 0), ink, 5.0)
		draw_line(c + Vector2(r * 0.55, 0), c + Vector2(r, 0), ink, 5.0)
		draw_line(c + Vector2(0, r * 0.55), c + Vector2(0, r), ink, 5.0)
		for i in range(1, 5):
			var o := r * 0.1 * i
			for dpos in [Vector2(o, 0), Vector2(-o, 0), Vector2(0, o), Vector2(0, -o)]:
				draw_circle(c + dpos, 2.2, ink)
		draw_circle(c, 2.0, Color(1, 0.3, 0.1, 0.95))

	## A gold-green diamond over each of the mission's objectives (group
	## "objectives"), with how far it is; one that's off screen sits on the
	## edge, toward it.
	func _draw_objectives(cam: Camera3D, p: Critter, font: Font) -> void:
		var c := size * 0.5
		for n in hud.get_tree().get_nodes_in_group(&"objectives"):
			var o := n as Node3D
			if o == null or not o.is_inside_tree():
				continue
			var at := o.global_position + Vector3.UP * 2.4
			var sp := Vector2.INF
			if not cam.is_position_behind(at):
				sp = cam.unproject_position(at)
			if sp == Vector2.INF or not Rect2(Vector2.ZERO, size).grow(-60.0).has_point(sp):
				var local := cam.global_basis.inverse() * (at - cam.global_position)
				var dir := Vector2(local.x, -local.y)
				if local.z > 0.0:
					dir.y = absf(dir.y)   # (behind you: along the bottom edge, to the side it's on)
				dir = dir.normalized() if dir.length() > 0.001 else Vector2.DOWN
				var half := size * 0.5 - Vector2(70.0, 70.0)
				sp = c + dir * minf(half.x / maxf(absf(dir.x), 0.001), half.y / maxf(absf(dir.y), 0.001))
			var r := 13.0 + sin(Time.get_ticks_msec() * 0.006) * 2.0
			var pts := PackedVector2Array([sp + Vector2(0, -r), sp + Vector2(r * 0.75, 0), sp + Vector2(0, r), sp + Vector2(-r * 0.75, 0)])
			draw_colored_polygon(pts, Color(GlowCarrot.GLOW, 0.9))
			pts.append(pts[0])
			draw_polyline(pts, Color(0, 0, 0, 0.85), 2.5)
			var m := "%d m" % roundi(p.global_position.distance_to(o.global_position))
			draw_string_outline(font, sp + Vector2(-60, r + 22), m, HORIZONTAL_ALIGNMENT_CENTER, 120, 18, 5, Color(0, 0, 0, 0.8))
			draw_string(font, sp + Vector2(-60, r + 22), m, HORIZONTAL_ALIGNMENT_CENTER, 120, 18, UITheme.CREAM)

	func _bar(pos: Vector2, w: float, h: float, frac: float, col: Color, text: String, font: Font) -> void:
		draw_style_box(_box(Color(UITheme.INK, 0.7), int(h * 0.5)), Rect2(pos, Vector2(w, h)))
		if frac > 0.001:
			draw_style_box(_box(col, int(h * 0.5)), Rect2(pos + Vector2(3, 3), Vector2(maxf((w - 6) * clampf(frac, 0.0, 1.0), h - 6), h - 6)))
		var fs := int(clampf(h * 0.6, 18.0, 26.0))   # (the text grows with the bar)
		var at := pos + Vector2(16, h * 0.5 + fs * 0.38)
		draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 5, Color(0, 0, 0, 0.8))
		draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UITheme.CREAM)
