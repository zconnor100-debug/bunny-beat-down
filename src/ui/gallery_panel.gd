class_name GalleryPanel
extends PanelContainer
## The Rogues' Gallery: all 49 bots (Cast), the ones with the most history
## with you first. Each card: its name (and how radical you've made it), its
## species, way of fighting, voice and favourite gun, who it is, the score
## between you, its wins, and the grudges it holds (against bots, and the
## director). Pad friendly: every card is a button, so the list scrolls with
## the focus.

signal closed

const SPECIES := {"bandit_bunny": "Bandit Bunny", "squirrel": "Squirrel", "fox": "Fox", "raccoon": "Raccoon",
	"frog": "Frog", "beaver": "Beaver", "hamster": "Hamster"}

var _list: VBoxContainer
var _name: Label
var _detail: Label


func _ready() -> void:
	theme = UITheme.theme()
	custom_minimum_size = Vector2(1180, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	add_child(v)
	var title := UITheme.label("Rogues' Gallery", 52, UITheme.CARROT_LIGHT, true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var sub := UITheme.label("The same 49 critters every run. They remember you, and each other.", 22, UITheme.CREAM)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 18)
	v.add_child(h)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(560, 560)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	h.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 6)
	scroll.add_child(_list)
	var side := VBoxContainer.new()
	side.custom_minimum_size = Vector2(580, 0)
	side.add_theme_constant_override("separation", 6)
	h.add_child(side)
	_name = UITheme.label("", 34, UITheme.CARROT_LIGHT, true)
	_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	side.add_child(_name)
	_detail = UITheme.label("", 21)
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	side.add_child(_detail)
	var back := UITheme.button("Back", func(): closed.emit())
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(back)
	var first: Button = null
	for n in order():
		var b := UITheme.button(card_title(n), func(): _show(n))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_color_override("font_color", Cast.HEAT_COLORS[Cast.heat(n)] if Cast.heat(n) > 0 else UITheme.CREAM)
		b.focus_entered.connect(func(): _show(n))
		_list.add_child(b)
		if first == null:
			first = b
	if first:
		first.grab_focus.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		closed.emit()


## The cast, the ones with the most history with you first.
static func order() -> Array:
	var all := Cast.names()
	var history := func(n: String) -> float:
		return (100.0 if RivalBook.is_rival(n) else 0.0) + Cast.heat(n) * 10.0 + RivalBook.your_kills(n) + RivalBook.kills_on_you(n) \
			+ RivalBook.meetings(n) * 0.01
	var keyed := all.map(func(n): return [history.call(n), n])
	keyed.sort_custom(func(a, b): return a[0] > b[0] if a[0] != b[0] else a[1] < b[1])
	return keyed.map(func(k): return k[1])


static func card_title(n: String) -> String:
	var tag := "⚔ " if RivalBook.is_rival(n) else ""
	return "%s%s  ·  %s" % [tag, Cast.title(n), SPECIES.get(Cast.member(n).species, "")]


## Everything the game knows about a bot, as text.
static func card(n: String) -> String:
	var m := Cast.member(n)
	var style: Dictionary = Cast.STYLES.get(m.style, {})
	var voice: Dictionary = RivalBook.PERSONALITIES.get(m.voice, {})
	var gun := WeaponDB.get_weapon(StringName(m.weapon))
	var lines := []
	lines.append("%s  ·  %s  ·  %s%s" % [SPECIES.get(m.species, ""), style.get("label", ""), voice.get("label", ""),
		"   ⚔ YOUR RIVAL" if RivalBook.is_rival(n) else ""])
	lines.append("“%s”" % m.says)
	lines.append(m.bio)
	lines.append("")
	lines.append("Fights: %s" % style.get("text", ""))
	lines.append("Favourite gun: %s" % (gun.display_name if gun else m.weapon))
	lines.append("")
	var yours := RivalBook.your_kills(n)
	var theirs := RivalBook.kills_on_you(n)
	if yours + theirs + RivalBook.meetings(n) == 0:
		lines.append("You haven't met yet.")
	else:
		lines.append("You %d – %d %s   ·   met %s" % [yours, theirs, n, _times(RivalBook.meetings(n))])
	var t := Cast.heat(n)
	if t > 0:
		lines.append("Mood: %s. %s" % [Cast.HEAT_LABELS[t], [
			"", "It noticed.", "It drops in with its favourite gun, comes looking for you, and taunts you.",
			"Armour, its favourite gun, and it won't wait its turn to shoot at you.",
			"Your nemesis: heavily armed, armoured, and it always jumps when you do."][t]])
	if RivalBook.wins(n) > 0 or RivalBook.bot_kills(n) > 0:
		lines.append("Won %s  ·  beat down %s" % [_count(RivalBook.wins(n), "match", "matches"), _count(RivalBook.bot_kills(n), "other critter", "other critters")])
	var g := RivalBook.grudges(n)
	if not g.is_empty():
		var keys := g.keys()
		keys.sort_custom(func(a, b): return int(g[a]) > int(g[b]))
		lines.append("Holds grudges against: %s" % ", ".join(keys.slice(0, 4).map(func(k): return "%s (%d)" % [k, int(g[k])])))
	var d := RivalBook.director_grudge(n)
	if d >= Cast.DEFIANT_AT:
		lines.append("Furious with the director: it ignores the director's pacing.")
	elif d > 0:
		lines.append("Grumbling about the director (%d)." % d)
	return "\n".join(lines)


static func _count(k: int, one: String, many: String) -> String:
	return "%d %s" % [k, one if k == 1 else many]


static func _times(k: int) -> String:
	return "once" if k == 1 else ("twice" if k == 2 else "%d times" % k)


func _show(n: String) -> void:
	_name.text = Cast.title(n)
	_name.add_theme_color_override("font_color", Cast.HEAT_COLORS[Cast.heat(n)] if Cast.heat(n) > 0 else UITheme.CARROT_LIGHT)
	_detail.text = card(n)
