class_name BurrowPanel
extends PanelContainer
## The Burrow: spend the acorns you've earned on perks, pick which ones to
## take into the next match (Burrow.slots() of them), upgrade the Burrow,
## switch run modifiers on or off, and in the Workshop buy gun attachments
## (fit or take them off) and looks (browse each with ◂ ▸; one you own is
## worn as soon as you pick it), your wardrobe among them: a portrait beside
## the list shows you wearing what you're browsing, bought or not (your coat
## too), your gun in the skin you're browsing. Pad
## friendly: every row is buttons, and the list scrolls with the focus.

signal closed

var _acorns: Label
var _list: VBoxContainer
var _browse: Dictionary = {}        # look category -> option index shown
var _portrait: CritterPortrait
var _scroll: ScrollContainer


func _ready() -> void:
	theme = UITheme.theme()
	custom_minimum_size = Vector2(1080, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	add_child(v)
	var title := UITheme.label("The Burrow", 52, UITheme.CARROT_LIGHT, true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	_acorns = UITheme.label("", 24, UITheme.CREAM)
	_acorns.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_acorns)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	v.add_child(row)
	_scroll = ScrollContainer.new()
	_scroll.custom_minimum_size = Vector2(720, 560)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	row.add_child(_scroll)
	_portrait = CritterPortrait.new(Vector2(320, 560))
	row.add_child(_portrait)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 8)
	_scroll.add_child(_list)
	var back := UITheme.button("Back", func(): closed.emit())
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(back)
	for cat in Workshop.LOOKS:
		_browse[cat] = _index_of(cat, Workshop.look(cat))
	_rebuild()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		closed.emit()


func _rebuild(focus_key := "") -> void:
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	_acorns.text = "🌰 %d acorns   •   perks equipped: %d of %d" % [Burrow.acorns(), Burrow.equipped().size(), Burrow.slots()]
	_portrait.show_player(trying_on(), &"carrot_rifle", Workshop.kit(shown("skin")), shown(Workshop.COAT))   # (the skin and coat you're browsing too)
	var focus: Dictionary = {}   # key -> button
	_heading("Perks")
	for id in Burrow.PERKS:
		var p: Dictionary = Burrow.PERKS[id]
		var state: String
		if not Burrow.unlocked(id):
			state = "Unlock — %d 🌰" % int(p.cost)
		elif Burrow.has_perk(id):
			state = "Equipped ✓"
		else:
			state = "Equip"
		focus[id] = _row("%s — %s" % [p.name, p.text], state, func(): _perk_pressed(id))
	_heading("Burrow upgrades")
	for id in Burrow.UPGRADES:
		var u: Dictionary = Burrow.UPGRADES[id]
		focus[id] = _row("%s — %s" % [u.name, u.text], "Yours ✓" if Burrow.unlocked(id) else "Build — %d 🌰" % int(u.cost), func():
			if not Burrow.unlocked(id) and not Burrow.unlock(id):
				_short()
				return
			_rebuild(id))
	_heading("Run modifiers")
	for id in Burrow.MODIFIERS:
		var m: Dictionary = Burrow.MODIFIERS[id]
		focus[id] = _row("%s — %s" % [m.name, m.text], "On ✓" if Burrow.modifier_on(id) else "Off", func():
			Burrow.set_modifier(id, not Burrow.modifier_on(id))
			_rebuild(id))
	_heading("Workshop: attachments (on every gun you pick up)")
	for id in Workshop.ATTACHMENTS:
		var a: Dictionary = Workshop.ATTACHMENTS[id]
		var state := "Buy — %d 🌰" % int(a.cost)
		if Workshop.owns(id):
			state = "Fitted ✓" if Workshop.fitted(id) else "Fit"
		focus[id] = _row("%s — %s" % [a.name, a.text], state, func(): _attachment_pressed(id))
	_heading("Workshop: looks")
	for cat in Workshop.LOOKS:
		if not _on_you(cat):
			_look_row(cat, focus)
	_heading("Workshop: wardrobe (yours alone: no rogue wears these)")
	for cat in Workshop.WARDROBE + [Workshop.COAT]:
		_look_row(cat, focus)
	var to_focus: Control = focus.get(focus_key)
	if to_focus == null:
		to_focus = UITheme.first_focusable(_list)
	if to_focus:
		_refocus.call_deferred(to_focus, _scroll.scroll_vertical)


## Focus the rebuilt row's button where the list was. The rows just built
## aren't laid out yet (their wrapped labels have no width), so following the
## focus now threw the list to its end on every press: it stays put, and
## follows the focus again once they're in place.
func _refocus(c: Control, keep: int) -> void:
	if not is_instance_valid(c):
		return
	_scroll.follow_focus = false
	c.grab_focus()
	_scroll.scroll_vertical = keep
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_instance_valid(c):
		return
	_scroll.scroll_vertical = keep
	_scroll.follow_focus = true
	if c.has_focus():
		_scroll.ensure_control_visible(c)


func _heading(text: String) -> void:
	_list.add_child(UITheme.label(text, 28, UITheme.CARROT_LIGHT, true))


func _row(text: String, action: String, pressed: Callable) -> Button:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 16)
	var l := UITheme.label(text, 20)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	h.add_child(l)
	var b := UITheme.button(action, pressed)
	b.custom_minimum_size = Vector2(230, 0)
	h.add_child(b)
	_list.add_child(h)
	return b


## One look: its name and the option shown (with a preview), ◂ ▸ to browse,
## and Wear / Buy.
func _look_row(cat: String, focus: Dictionary) -> void:
	var opts: Array = Workshop.LOOKS[cat].options
	var i: int = _browse[cat]
	var opt: Array = opts[i]
	var item := "%s:%s" % [cat, opt[0]]
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	var l := UITheme.label("%s: %s" % [Workshop.LOOKS[cat].label, opt[1]], 21)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(l)
	if not _on_you(cat):   # (the wardrobe and your coat show on you, in the portrait)
		h.add_child(LookPreview.new(cat, opt[0], self))
	var prev := UITheme.button("◂", func(): _step(cat, -1))
	prev.custom_minimum_size = Vector2(60, 0)
	h.add_child(prev)
	var next := UITheme.button("▸", func(): _step(cat, 1))
	next.custom_minimum_size = Vector2(60, 0)
	h.add_child(next)
	var state := "Buy — %d 🌰" % int(opt[2])
	if Workshop.earned_only(item):
		var m := Mastery.giving(item)
		state = "Earn: %s" % m.get("name", "a milestone")
	if Workshop.owns(item):
		state = "Wearing ✓" if Workshop.look(cat) == opt[0] else "Wear"
	var act := UITheme.button(state, func(): _look_pressed(cat))
	act.custom_minimum_size = Vector2(200, 0)
	h.add_child(act)
	_list.add_child(h)
	focus[cat + ":prev"] = prev
	focus[cat + ":next"] = next
	focus[cat + ":act"] = act


## Shown on you in the portrait (your wardrobe and coat), not as a preview.
static func _on_you(cat: String) -> bool:
	return Workshop.WARDROBE.has(cat) or cat == Workshop.COAT


## The option a look row currently shows (for the previews).
func shown(cat: String) -> String:
	return Workshop.LOOKS[cat].options[_browse[cat]][0]


## The wardrobe as browsed: what the portrait tries on you.
func trying_on() -> Array:
	return Workshop.WARDROBE.map(func(cat): return shown(cat)).filter(func(id): return id != "none")


func _step(cat: String, by: int) -> void:
	var n: int = Workshop.LOOKS[cat].options.size()
	_browse[cat] = posmod(int(_browse[cat]) + by, n)
	Workshop.set_look(cat, shown(cat))   # (one you own: worn as you browse)
	_rebuild(cat + (":prev" if by < 0 else ":next"))


func _look_pressed(cat: String) -> void:
	var id := shown(cat)
	var item := "%s:%s" % [cat, id]
	if not Workshop.owns(item) and Workshop.earned_only(item):
		_acorns.text = "Not for sale: %s — %s" % [Mastery.giving(item).get("name", "a milestone"), Mastery.giving(item).get("text", "")]
		return
	if not Workshop.owns(item) and not Workshop.buy(item):
		_short()
		return
	Workshop.set_look(cat, id)
	_rebuild(cat + ":act")


func _attachment_pressed(id: String) -> void:
	if not Workshop.owns(id):
		if not Workshop.buy(id):
			_short()
			return
	else:
		Workshop.set_fitted(id, not Workshop.fitted(id))
	_rebuild(id)


func _perk_pressed(id: String) -> void:
	if not Burrow.unlocked(id):
		if not Burrow.unlock(id):
			_short()
			return
		Burrow.set_equipped(id, true)
	else:
		Burrow.set_equipped(id, not Burrow.has_perk(id))
	_rebuild(id)


func _short() -> void:
	_acorns.text = "Not enough acorns yet — win matches, beat down bots, get revenge on rivals, collect bounties."


static func _index_of(cat: String, id: String) -> int:
	var opts: Array = Workshop.LOOKS[cat].options
	for i in opts.size():
		if opts[i][0] == id:
			return i
	return 0


## A little picture of a look: the reticle (in the colour being shown), a
## colour swatch, or a skin's colours.
class LookPreview:
	extends Control

	var cat: String
	var id: String
	var panel: BurrowPanel

	func _init(cat_: String, id_: String, panel_: BurrowPanel) -> void:
		cat = cat_
		id = id_
		panel = panel_
		custom_minimum_size = Vector2(64, 40)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size * 0.5
		draw_rect(Rect2(Vector2.ZERO, size), Color(UITheme.INK, 0.55))
		match cat:
			"reticle", "reticle_color":
				var style := id if cat == "reticle" else panel.shown("reticle")
				var col := Workshop.color(id if cat == "reticle_color" else panel.shown("reticle_color"))
				Reticle.draw(self, c, 7.0, style, Color(col, 0.95))
			"skin":
				var s: Array = GunKit.SKINS.get(id, [])
				if s.is_empty():
					draw_rect(Rect2(c - Vector2(20, 8), Vector2(40, 16)), Color(1.0, 0.55, 0.12))
				else:
					draw_rect(Rect2(c - Vector2(20, 8), Vector2(14, 16)), s[1])
					draw_rect(Rect2(c - Vector2(6, 8), Vector2(13, 16)), s[2])
					draw_rect(Rect2(c + Vector2(7, -8), Vector2(13, 16)), s[3] if s[0] == 1 else s[1].lightened(0.25))
			"smoke", "kill_fx":
				draw_circle(c, 9.0, Color(0.9, 0.9, 0.88, 0.0 if id == "none" else 0.8))
			_:
				draw_circle(c, 11.0, Workshop.color(id if Workshop.COLORS.has(id) or id == "rainbow" else "cream", 0.1))
