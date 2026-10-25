class_name GalleryPanel
extends PanelContainer
## The Rogues' Gallery: all 49 bots (Cast), the ones with the most history
## with you first. Each card: the rogue itself, turning on a little stand in
## its own outfit with its favourite gun (CritterPortrait), its name (and how radical you've made it), its
## species, way of fighting, voice and favourite gun, who it is, the score
## between you, its wins, its trackers (accuracy, headshots, damage,
## beat-downs by gun, longest beat-down), and the grudges it holds (against
## bots, and the director). Pad friendly: every card is a button, so the list scrolls with
## the focus.

signal closed

const SPECIES := {"bandit_bunny": "Bandit Bunny", "squirrel": "Squirrel", "fox": "Fox", "raccoon": "Raccoon",
	"frog": "Frog", "beaver": "Beaver", "hamster": "Hamster"}

var _list: VBoxContainer
var _name: Label
var _detail: Label
var _portrait: CritterPortrait


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
	_portrait = CritterPortrait.new(Vector2(580, 250))
	side.add_child(_portrait)
	_name = UITheme.label("", 34, UITheme.CARROT_LIGHT, true)
	_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	side.add_child(_name)
	# (the card scrolls under the portrait: a rogue with a long history has a lot to say)
	var card_scroll := ScrollContainer.new()
	card_scroll.custom_minimum_size = Vector2(580, 250)
	card_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	side.add_child(card_scroll)
	_detail = UITheme.label("", 21)
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card_scroll.add_child(_detail)
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
	lines.append_array(tracker_lines(n))
	lines.append_array(memory_lines(n))
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


## The bot's trackers: accuracy, headshots and damage, then its beat-downs
## by gun (the top three) and its longest. Nothing before it's fired a carrot.
static func tracker_lines(n: String) -> Array:
	var out := []
	var s := RivalBook.bot_stats(n)
	if s.shots > 0.0:
		out.append("Accuracy %s  ·  %s  ·  %d damage" % [StatBook.percent(s), _count(int(s.heads), "headshot", "headshots"), int(s.damage)])
	var g := RivalBook.gun_kills(n)
	if not g.is_empty():
		var ids := g.keys()
		ids.sort_custom(func(a, b): return int(g[a]) > int(g[b]) if int(g[a]) != int(g[b]) else a < b)
		out.append("Beat-downs by gun: %s  ·  longest %d m" % [", ".join(ids.slice(0, 3).map(
			func(id): return "%s %d" % [StatBook.gun_name(StringName(id)), int(g[id])])), roundi(RivalBook.longest(n))])
	return out


## What it remembers of you: its scars (and what it learned from them),
## the gun it took off you, and its signature gun if you won its nemesis hunt.
static func memory_lines(n: String) -> Array:
	var out := []
	var sc := RivalBook.scars(n)
	if not sc.is_empty():
		out.append("Scars: %s. It learned: %s." % [", ".join(sc.map(func(x): return "%s (%s)" % [RivalBook.SCARS[x].text, RivalBook.SCARS[x].why])),
			"; ".join(sc.map(func(x): return RivalBook.SCARS[x].learned))])
	var took := RivalBook.took_gun(n)
	if not took.is_empty():
		var w := WeaponInstance.from_dict(took)
		out.append("It has your %s. Beat it down to get it back." % (w.display_name() if w else "gun"))
	if RivalBook.signature_won(n):
		var sig := RivalBook.signature_gun(n)
		out.append("You won its nemesis hunt: %s, with %s." % [sig.display_name(), Boons.name_of(sig.mutation)] if sig else "You won its nemesis hunt.")
	return out


static func _count(k: int, one: String, many: String) -> String:
	return "%d %s" % [k, one if k == 1 else many]


static func _times(k: int) -> String:
	return "once" if k == 1 else ("twice" if k == 2 else "%d times" % k)


func _show(n: String) -> void:
	_portrait.show_rogue(n)
	_name.text = Cast.title(n)
	_name.add_theme_color_override("font_color", Cast.HEAT_COLORS[Cast.heat(n)] if Cast.heat(n) > 0 else UITheme.CARROT_LIGHT)
	_detail.text = card(n)
