class_name BurrowPanel
extends PanelContainer
## The Burrow: spend the acorns you've earned on perks, pick which ones to
## take into the next match (Burrow.SLOTS of them), and switch run modifiers
## on or off. Pad friendly: every row is a button.

signal closed

var _acorns: Label
var _list: VBoxContainer


func _ready() -> void:
	theme = UITheme.theme()
	custom_minimum_size = Vector2(980, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	add_child(v)
	var title := UITheme.label("The Burrow", 52, UITheme.CARROT_LIGHT, true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	_acorns = UITheme.label("", 24, UITheme.CREAM)
	_acorns.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_acorns)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(940, 520)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 8)
	scroll.add_child(_list)
	var back := UITheme.button("Back", func(): closed.emit())
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(back)
	_rebuild()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		closed.emit()


func _rebuild(focus_key := "") -> void:
	for c in _list.get_children():
		c.queue_free()
	_acorns.text = "🌰 %d acorns   •   perks equipped: %d of %d" % [Burrow.acorns(), Burrow.equipped().size(), Burrow.SLOTS]
	_list.add_child(UITheme.label("Perks", 28, UITheme.CARROT_LIGHT, true))
	var to_focus: Control = null
	for id in Burrow.PERKS:
		var p: Dictionary = Burrow.PERKS[id]
		var state: String
		if not Burrow.unlocked(id):
			state = "Unlock — %d 🌰" % int(p.cost)
		elif Burrow.has_perk(id):
			state = "Equipped ✓"
		else:
			state = "Equip"
		var b := _row("%s — %s" % [p.name, p.text], state, func(): _perk_pressed(id))
		if id == focus_key:
			to_focus = b
	_list.add_child(UITheme.label("Run modifiers", 28, UITheme.CARROT_LIGHT, true))
	for id in Burrow.MODIFIERS:
		var m: Dictionary = Burrow.MODIFIERS[id]
		var b := _row("%s — %s" % [m.name, m.text], "On ✓" if Burrow.modifier_on(id) else "Off", func():
			Burrow.set_modifier(id, not Burrow.modifier_on(id))
			_rebuild(id))
		if id == focus_key:
			to_focus = b
	if to_focus == null:
		to_focus = UITheme.first_focusable(_list)
	if to_focus:
		to_focus.grab_focus.call_deferred()


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


func _perk_pressed(id: String) -> void:
	if not Burrow.unlocked(id):
		if not Burrow.unlock(id):
			_acorns.text = "Not enough acorns yet — win matches, beat down bots, get revenge on rivals."
			return
		Burrow.set_equipped(id, true)
	else:
		Burrow.set_equipped(id, not Burrow.has_perk(id))
	_rebuild(id)
