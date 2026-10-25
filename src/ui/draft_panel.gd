class_name DraftPanel
extends PanelContainer
## A boon draft (Boons): three cards, pick one. Each card shows the boon's
## name (and the level it would go to), its family in the family's colour,
## and what it does. Used at an acorn shrine mid-match (game.gd pauses the
## match under it) and on the Trail between a run's stops. Pad friendly:
## the cards are buttons, the first one focused.

signal chosen(id: String)

var choices: Array = []
var heading := "Pick a boon"


func _ready() -> void:
	theme = UITheme.theme()
	process_mode = Node.PROCESS_MODE_ALWAYS
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	add_child(v)
	var t := UITheme.label(heading, 44, UITheme.CARROT_LIGHT, true)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 18)
	v.add_child(row)
	var first: Button = null
	for id in choices:
		var b := card(id)
		b.pressed.connect(func(): chosen.emit(id))
		row.add_child(b)
		if first == null:
			first = b
	var mine := UITheme.label("Your boons: " + (Boons.summary() if not Boons.held.is_empty() else "none yet"), 19, Color(UITheme.CREAM, 0.75))
	mine.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mine.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mine.custom_minimum_size = Vector2(1100, 0)
	v.add_child(mine)
	if first:
		first.grab_focus.call_deferred()


## One boon's card.
static func card(id: String) -> Button:
	var lv := Boons.level(id)
	var next := 1 if Boons.DUOS.has(id) else mini(lv + 1, Boons.MAX_LEVEL)
	var family := "Duo: %s + %s" % [Boons.FAMILIES[Boons.DUOS[id].families[0]].name, Boons.FAMILIES[Boons.DUOS[id].families[1]].name] \
		if Boons.DUOS.has(id) else String(Boons.FAMILIES[Boons.family_of(id)].name)
	var up := "  ▲" if lv > 0 else ""
	var b := UITheme.button("%s%s\n%s\n\n%s" % [Boons.title(id, next), up, family, Boons.describe(id, next)], func(): pass)
	b.custom_minimum_size = Vector2(360, 250)
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.add_theme_font_size_override("font_size", 22)
	var c := Boons.color_of(id)
	for state in ["normal", "hover", "focus", "pressed"]:
		var base := UITheme.theme().get_stylebox(state, "Button")
		var sb: StyleBoxFlat = base.duplicate() if base is StyleBoxFlat else StyleBoxFlat.new()
		sb.border_color = c
		sb.set_border_width_all(4 if state == "normal" else 7)
		b.add_theme_stylebox_override(state, sb)
	return b
