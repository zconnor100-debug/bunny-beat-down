class_name HUD
extends CanvasLayer
## In-match heads-up display: vitals, weapons, crosshair with live spread,
## hit markers, damage direction, blood on the lens, kill feed, Briar timer,
## minimap, prompts.

const SPLAT_LIFE := 3.0        ## seconds a splat stays on screen (plus up to 1 s)
const MAX_SPLATS := 12

var player: Critter
var rig: CameraRig
var match_manager: MatchManager

var _root: Control
var _overlay: HUDOverlay
var _alive_label: Label
var _kills_label: Label
var _storm_label: Label
var _message: Label
var _sub_message: Label
var _hint: Label
var _ammo_label: Label
var _weapon_name: Label
var _slots: Array[PanelContainer] = []
var _clover_label: Label
var _rewind_label: Label
var _rewind_tint: ColorRect
var _feed: VBoxContainer
var _minimap: Minimap
var _bigmap: Minimap
var _storm_tint: ColorRect
var _hurt_tint: ColorRect
var _blood: Control
var _splats: Array = []        # [TextureRect, seconds left, starting alpha]
var _hit_flash := 0.0
var _fps: Label
var _message_t := 0.0


func setup(player_: Critter, rig_: CameraRig, mm: MatchManager) -> void:
	player = player_
	rig = rig_
	match_manager = mm
	layer = 5
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = UITheme.theme()
	add_child(_root)

	_storm_tint = _tint(Color(0.45, 0.1, 0.6, 0.0))
	_hurt_tint = _tint(Color(0.7, 0.0, 0.05, 0.0))
	_blood = Control.new()
	_blood.set_anchors_preset(Control.PRESET_FULL_RECT)
	_blood.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_blood)

	_overlay = HUDOverlay.new()
	_overlay.hud = self
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_overlay)

	# top-left: alive + kills
	var tl := VBoxContainer.new()
	tl.position = Vector2(28, 20)
	_root.add_child(tl)
	_alive_label = UITheme.label("24 CRITTERS LEFT", 28, UITheme.CREAM, true)
	_kills_label = UITheme.label("BEAT DOWNS: 0", 22)
	tl.add_child(_alive_label)
	tl.add_child(_kills_label)

	# top-centre: Briar timer + messages
	_storm_label = UITheme.label("", 24)
	_storm_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_storm_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_storm_label.position.y = 18
	_storm_label.size.x = 600
	_storm_label.position.x = -300
	_root.add_child(_storm_label)
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
	br.offset_top = -190
	br.offset_right = -28
	br.offset_bottom = -24
	br.alignment = BoxContainer.ALIGNMENT_END
	_root.add_child(br)
	_weapon_name = UITheme.label("", 24, UITheme.CREAM)
	_weapon_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	br.add_child(_weapon_name)
	_ammo_label = UITheme.label("", 46, UITheme.CREAM, true)
	_ammo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	br.add_child(_ammo_label)
	var slots := HBoxContainer.new()
	slots.alignment = BoxContainer.ALIGNMENT_END
	slots.add_theme_constant_override("separation", 10)
	br.add_child(slots)
	for i in Inventory.SLOTS:
		var pc := PanelContainer.new()
		pc.custom_minimum_size = Vector2(132, 52)
		var l := UITheme.label("%d" % (i + 1), 17)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.autowrap_mode = TextServer.AUTOWRAP_WORD
		pc.add_child(l)
		slots.add_child(pc)
		_slots.append(pc)

	# bottom-left: clovers (bars are drawn by the overlay)
	_clover_label = UITheme.label("", 22, UITheme.LEAF)
	_clover_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_clover_label.offset_left = 30
	_clover_label.offset_top = -150
	_root.add_child(_clover_label)
	_rewind_label = UITheme.label("", 20, Color("9fe3ff"))
	_rewind_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_rewind_label.offset_left = 30
	_rewind_label.offset_top = -184
	_root.add_child(_rewind_label)
	_rewind_tint = _tint(Color(0.55, 0.85, 1.0, 0.0))
	if mm and mm.time_keeper:
		mm.time_keeper.rewound.connect(_on_rewound)

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
	Events.taunt.connect(_on_taunt)
	Events.rival_news.connect(func(t, sub): show_message(t, sub, 4.0))
	Events.announce.connect(func(t, sub): show_message(t, sub, 5.0))
	Events.alive_count_changed.connect(func(a, _t): _alive_label.text = "%d CRITTER%s LEFT" % [a, "" if a == 1 else "S"])
	Events.player_hit_confirmed.connect(_overlay.on_hit_confirmed)
	Events.critter_damaged.connect(_on_damaged)
	Events.item_picked_up.connect(_on_picked_up)
	Events.supply_drop_incoming.connect(func(_pos):
		Audio.play(&"match_countdown_beep", -4.0)
		show_message("Supply drop incoming!", "Golden carrots inbound — check your map", 3.5))
	var pc_node := player.get_node_or_null("PlayerController") as PlayerController
	if pc_node:
		pc_node.interact_hint_changed.connect(func(t): _hint.text = t)


func attach_island(island: Island, storm: Storm) -> void:
	for m in [_minimap, _bigmap]:
		m.build(island)
		m.storm = storm
		m.player = player


func attach_dropship(d: Dropship) -> void:
	_minimap.dropship = d
	_bigmap.dropship = d


func _on_rewound() -> void:
	_rewind_tint.color.a = 0.55
	for s in _splats:
		s[1] = 0.0   # the blood on the lens hasn't happened yet either
	_hit_flash = 0.0
	_overlay._dirs.clear()
	_overlay._numbers.clear()
	var left := match_manager.time_keeper.charges
	show_message("⟲ REWOUND %d SECONDS" % int(TimeKeeper.REWIND_SECONDS), "%d rewind%s left" % [left, "" if left == 1 else "s"] if left > 0 else "That was your last rewind", 2.5)
	Audio.play(&"glider_open", -2.0, 0.0)


func _tint(c: Color) -> ColorRect:
	var r := ColorRect.new()
	r.color = c
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(r)
	return r


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
	var w := player.current_weapon()
	if w:
		_weapon_name.text = w.display_name()
		_weapon_name.add_theme_color_override("font_color", Rarity.COLORS[w.rarity])
		var reserve: int = player.inventory.ammo[w.data.ammo_type]
		_ammo_label.text = "RELOADING…" if player.is_reloading() else "%d  |  %d" % [w.ammo_in_mag, reserve]
	else:
		_weapon_name.text = "Paws only — find a carrot gun!"
		_weapon_name.add_theme_color_override("font_color", UITheme.CREAM)
		_ammo_label.text = ""
	for i in _slots.size():
		var sw: WeaponInstance = player.inventory.weapons[i]
		var l := _slots[i].get_child(0) as Label
		l.text = "%d  %s" % [i + 1, sw.data.display_name.replace("Carrot ", "") if sw else "—"]
		var sb := _slot_style(sw.rarity if sw else -1, i == player.current_slot)
		_slots[i].add_theme_stylebox_override("panel", sb)
	_clover_label.text = "Lucky clovers: %d   [%s] to heal" % [player.inventory.clovers, GameInput.prompt(&"heal")] if player.inventory.clovers > 0 else ""
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


var _slot_styles: Dictionary = {}


## Weapon-slot frame, cached per (rarity, selected) so the HUD allocates nothing per frame.
func _slot_style(rarity: int, selected: bool) -> StyleBoxFlat:
	var key := rarity * 2 + int(selected)
	if not _slot_styles.has(key):
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(UITheme.INK, 0.95 if selected else 0.75)
		sb.border_color = Rarity.COLORS[rarity] if rarity >= 0 else Color(UITheme.CREAM, 0.3)
		sb.set_border_width_all(4 if selected else 2)
		sb.set_corner_radius_all(12)
		_slot_styles[key] = sb
	return _slot_styles[key]


func _on_critter_died(victim: Node, info: DamageInfo) -> void:
	var killer := info.attacker as Critter
	var v := victim as Critter
	var how := "the Briar" if info.kind == DamageInfo.Kind.STORM else ""
	if killer and info.weapon_id != &"":
		var data := WeaponDB.get_weapon(info.weapon_id)
		how = data.display_name if data else String(info.weapon_id)
	var line: String
	if killer and killer != v:
		line = "%s  ▸ %s ▸  %s%s" % [killer.display_name, how, v.display_name, "  ✦" if info.headshot else ""]
	elif info.kind == DamageInfo.Kind.STORM:
		line = "%s got lost in the Briar" % v.display_name
	elif info.weapon_id == &"toy_train":
		line = "%s got bonked by the toy train" % v.display_name
	else:
		line = "%s had a little accident" % v.display_name
	var l := UITheme.label(line, 19, UITheme.CARROT_LIGHT if (killer == player or v == player) else UITheme.CREAM)
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
		show_message("BEAT DOWN!", "%s is out%s" % [v.display_name, " — headshot!" if info.headshot else ""], 2.2)


const SPEECH := Color(0.88, 0.72, 1.0)


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
		var pos := (victim as Critter).get_eye_position() + Vector3(randf_range(-0.3, 0.3), 0.3, randf_range(-0.3, 0.3))
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
			var col := Color(1, 1, 1, 0.92)
			for dir in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
				var a: Vector2 = c + dir * gap
				var b: Vector2 = c + dir * (gap + 10.0)
				draw_line(a, b, Color(0, 0, 0, 0.6), 4.0)
				draw_line(a, b, col, 2.0)
			draw_circle(c, 2.5, Color(0, 0, 0, 0.6))
			draw_circle(c, 1.6, col)
		# unlocking a treasure chest: progress bar under the crosshair
		var pcn := p.get_node_or_null("PlayerController") as PlayerController
		var crate := pcn.focused_crate() if pcn else null
		if crate and crate.open_time > 0.0 and crate.channeler() == p and not crate.opened:
			var bw := 260.0
			var bp := c + Vector2(-bw * 0.5, 70.0)
			draw_style_box(_box(Color(UITheme.INK, 0.75), 9), Rect2(bp, Vector2(bw, 18)))
			draw_style_box(_box(Rarity.COLORS[Rarity.Tier.GOLDEN], 7), Rect2(bp + Vector2(3, 3), Vector2((bw - 6) * crate.progress, 12)))
			var label := "Unlocking %s… %.1f s" % [crate.display_name, (1.0 - crate.progress) * crate.open_time]
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
		# vitals
		var bx := 30.0
		var by := size.y - 110.0
		var w := 360.0
		_bar(Vector2(bx, by), w, 22.0, p.armor / p.max_armor, UITheme.ACORN, "SHIELD %d" % roundi(p.armor), font)
		_bar(Vector2(bx, by + 34.0), w, 30.0, p.health / p.max_health, Color("5fc23a") if p.health > 35 else UITheme.BERRY, "HP %d" % roundi(p.health), font)
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
			draw_string_outline(font, Vector2(30, ty), t[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 20, 5, Color(0, 0, 0, 0.8 * a))
			draw_string(font, Vector2(30, ty), t[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(UITheme.CREAM, a))
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

	func _bar(pos: Vector2, w: float, h: float, frac: float, col: Color, text: String, font: Font) -> void:
		draw_style_box(_box(Color(UITheme.INK, 0.7), int(h * 0.5)), Rect2(pos, Vector2(w, h)))
		if frac > 0.001:
			draw_style_box(_box(col, int(h * 0.5)), Rect2(pos + Vector2(3, 3), Vector2(maxf((w - 6) * clampf(frac, 0.0, 1.0), h - 6), h - 6)))
		draw_string_outline(font, pos + Vector2(14, h * 0.5 + 7), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, 5, Color(0, 0, 0, 0.8))
		draw_string(font, pos + Vector2(14, h * 0.5 + 7), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, UITheme.CREAM)
