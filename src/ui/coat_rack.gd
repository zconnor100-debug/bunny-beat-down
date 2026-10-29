class_name CoatRack
extends VBoxContainer
## The coat rack (in the Burrow): every coat at once, each on you (your
## critter, skin, wardrobe and gun) on its own turntable, so you can see them
## side by side. Wear one you've earned; one you haven't is dimmed, with the
## milestone that gives it and how far along you are. Pad friendly: a button
## under each (◂ ▸ between them), and Back.

signal closed

const PORTRAIT := Vector2(205, 330)
const LOCKED := Color(0.42, 0.42, 0.48)   ## (a coat you haven't earned: dimmed)

var _title: Label
var _buttons := {}                         # coat id -> its button
var _portraits := {}                       # coat id -> its CritterPortrait


func _ready() -> void:
	add_theme_constant_override("separation", 10)
	_title = UITheme.label("The coat rack", 30, UITheme.CARROT_LIGHT, true)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_title)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(row)
	for o in Workshop.LOOKS[Workshop.COAT].options:
		row.add_child(_column(o))
	var back := UITheme.button("Back to the Burrow", func(): closed.emit())
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	add_child(back)
	_refresh()
	(_buttons[Workshop.look(Workshop.COAT)] as Button).grab_focus.call_deferred()


## One coat: you in it, its name, how you got it (or how to), and Wear.
func _column(o: Array) -> VBoxContainer:
	var id: String = o[0]
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	var p := CritterPortrait.new(PORTRAIT)
	col.add_child(p)
	p.show_player(Workshop.outfit(), &"carrot_rifle", {}, id)
	_portraits[id] = p
	var name_l := UITheme.label(o[1], 21, UITheme.CREAM, true)
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(name_l)
	var how := UITheme.label(how_to(id), 16)
	how.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	how.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	how.custom_minimum_size = Vector2(PORTRAIT.x, 44)
	col.add_child(how)
	var b := UITheme.button("", func(): _pressed(id))
	col.add_child(b)
	_buttons[id] = b
	return col


## How a coat is yours, or what earns it and how far along you are.
static func how_to(id: String) -> String:
	var item := "%s:%s" % [Workshop.COAT, id]
	if id == Workshop.LOOKS[Workshop.COAT].options[0][0]:
		return "Yours from the start"
	var m := Mastery.giving(item)
	if m.is_empty():
		return ""
	if Workshop.owns(item):
		return "Earned: %s" % m.name
	return "%s (%d / %d)" % [m.text, mini(Mastery.progress(m.stat), int(m.need)), int(m.need)]


func _pressed(id: String) -> void:
	var item := "%s:%s" % [Workshop.COAT, id]
	if not Workshop.owns(item):
		var m := Mastery.giving(item)
		_title.text = "Not yet: %s — %s" % [m.get("name", "a milestone"), m.get("text", "")]
		return
	Workshop.set_look(Workshop.COAT, id)
	_title.text = "The coat rack"
	_refresh()


func _refresh() -> void:
	for id in _buttons:
		var mine := Workshop.owns("%s:%s" % [Workshop.COAT, id])
		(_buttons[id] as Button).text = ("Wearing ✓" if Workshop.look(Workshop.COAT) == id else "Wear") if mine else "Locked"
		(_portraits[id] as Control).modulate = Color.WHITE if mine else LOCKED
