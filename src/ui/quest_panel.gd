class_name QuestPanel
extends PanelContainer
## The Kernel Hunt's page (KernelHunt): what's going on, the acts down the
## left (the ones you've finished ticked, the ones to come sealed), and the
## one picked on the right: where it is, what happens, your best at it, how
## hard, and Begin. Beginning a mission emits play_mission (the menu opens
## the match with KernelHunt.playing set).

signal closed
signal play_mission(id: String)

const INTRO := "Something is getting into the Warren's critters: a gold-green light behind the eyes, running through the fur. The Warren calls them the Touched. Old Mother Clover says it's the Starfall Acorn, looking for its pieces."

var _detail: VBoxContainer
var _picked := "prologue"
var _acts: Array[Button] = []


func _ready() -> void:
	theme = UITheme.theme()
	custom_minimum_size = Vector2(1320, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	add_child(v)
	var title := UITheme.label("The Kernel Hunt", 56, UITheme.CARROT_LIGHT, true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var intro := UITheme.label(INTRO, 21, Color(UITheme.CREAM, 0.85))
	intro.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.custom_minimum_size = Vector2(1200, 0)
	v.add_child(intro)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 34)
	v.add_child(h)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 10)
	list.custom_minimum_size = Vector2(430, 0)
	h.add_child(list)
	for a in KernelHunt.ACTS:
		var id := String(a.id)
		var mark := "✓  " if KernelHunt.done(id) else ("" if a.get("open", false) else "🔒  ")
		var b := UITheme.button("%s%s: %s" % [mark, a.name, a.title], func(): show_act(id))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.set_meta(&"act", id)
		list.add_child(b)
		_acts.append(b)
		b.focus_entered.connect(func(): show_act(id))
	_detail = VBoxContainer.new()
	_detail.add_theme_constant_override("separation", 10)
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail.custom_minimum_size = Vector2(820, 420)
	h.add_child(_detail)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(row)
	row.add_child(UITheme.button("Back", func(): closed.emit()))
	show_act(_picked)
	_acts[0].grab_focus.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		closed.emit()


## The act on the right: an open one's briefing, your record and Begin; a
## sealed one's teaser.
func show_act(id: String) -> void:
	_picked = id
	for c in _detail.get_children():
		_detail.remove_child(c)
		c.queue_free()
	var a := KernelHunt.act(id)
	if a.is_empty():
		return
	var open: bool = a.get("open", false)
	_detail.add_child(UITheme.label(String(a.name).to_upper() + "  ·  " + String(a.where).to_upper(), 22, UITheme.CARROT_LIGHT, true))
	_detail.add_child(UITheme.label(String(a.title), 54, UITheme.CREAM, true))
	_detail.add_child(_text(String(a.brief), 23))
	if not open:
		_detail.add_child(_text("Ends with: %s." % a.get("ends", "?"), 22, Color(UITheme.CREAM, 0.75)))
		_detail.add_child(_text("Sealed. This part of the hunt comes in a later update.", 22, UITheme.BERRY))
		return
	_detail.add_child(_text("Goal: %s" % a.get("goal", ""), 22, UITheme.LEAF))
	_detail.add_child(_text("With you: the Barn Rangers (%s)." % ", ".join(KernelHunt.RANGERS), 19, Color(UITheme.CREAM, 0.8)))
	_detail.add_child(_text(KernelHunt.record_line(id), 20, Color(UITheme.CREAM, 0.8)))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	_detail.add_child(row)
	row.add_child(UITheme.label("Difficulty", 22))
	var diff := OptionButton.new()
	for d in ["Sleepy", "Scrappy", "Savage"]:
		diff.add_item(d)
	diff.selected = int(Settings.get_value(&"difficulty"))
	diff.item_selected.connect(func(i): Settings.set_value(&"difficulty", i))
	row.add_child(diff)
	var go := UITheme.button("Begin" if not KernelHunt.done(id) else "Play it again", func(): play_mission.emit(id))
	go.name = "Begin"
	row.add_child(go)


func _text(t: String, size := 22, c := UITheme.CREAM) -> Label:
	var l := UITheme.label(t, size, c)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(800, 0)
	return l
