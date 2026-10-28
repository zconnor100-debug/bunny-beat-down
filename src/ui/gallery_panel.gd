class_name GalleryPanel
extends PanelContainer
## The Rogues' Gallery: all 49 bots (Cast), the ones with the most history
## with you first. Each card: the rogue itself, turning on a little stand in
## its own outfit with its favourite gun (CritterPortrait), its name (and how radical you've made it), its
## species, way of fighting, voice and favourite gun, who it is, the score
## between you, its wins, its trackers (accuracy, headshots, damage,
## beat-downs by gun, longest beat-down), and the grudges it holds (against
## bots, and the director). Pad friendly: every card is a button, so the list scrolls with
## the focus; the right stick (or the mouse wheel, or Page Up / Down) reads on down a long card.
## "Reset all rogues" (asked first) starts every one of them over, so new
## rivals and nemeses can rise (RivalBook.reset_rogues).

signal closed

const SPECIES := {"bandit_bunny": "Bandit Bunny", "squirrel": "Squirrel", "fox": "Fox", "raccoon": "Raccoon",
	"frog": "Frog", "beaver": "Beaver", "hamster": "Hamster"}
const STICK_SCROLL := 900.0   # px/s at full right-stick tilt

var _list: VBoxContainer
var _name: Label
var _detail: Label
var _portrait: CritterPortrait
var _card_scroll: ScrollContainer
var _more: Label   # "more below" under a card that doesn't fit
var _sub: Label
var _buttons: HBoxContainer   # Back, Reset all rogues
var _reset: Button
var _confirm: HBoxContainer   # "Are You Sure...?" Yes / No
var _no: Button


func _ready() -> void:
	theme = UITheme.theme()
	custom_minimum_size = Vector2(1180, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	add_child(v)
	var title := UITheme.label("Rogues' Gallery", 52, UITheme.CARROT_LIGHT, true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	_sub = UITheme.label("The same 49 critters every run. They remember you, and each other.", 22, UITheme.CREAM)
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_sub)
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
	_card_scroll = card_scroll
	_more = UITheme.label("▼  right stick or mouse wheel to read on", 16, Color(UITheme.CREAM, 0.6))
	_more.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_more.modulate.a = 0.0
	side.add_child(_more)
	card_scroll.get_v_scroll_bar().value_changed.connect(func(_v: float): _update_more())
	card_scroll.get_v_scroll_bar().changed.connect(_update_more)
	_buttons = HBoxContainer.new()
	_buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	_buttons.add_theme_constant_override("separation", 24)
	v.add_child(_buttons)
	_buttons.add_child(UITheme.button("Back", func(): closed.emit()))
	_reset = UITheme.button("Reset all rogues", _ask_reset)
	_buttons.add_child(_reset)
	# (asked first, with No in focus: a stray press of the pad doesn't wipe them)
	_confirm = HBoxContainer.new()
	_confirm.alignment = BoxContainer.ALIGNMENT_CENTER
	_confirm.add_theme_constant_override("separation", 18)
	_confirm.visible = false
	v.add_child(_confirm)
	_confirm.add_child(UITheme.label("Are You Sure you want to reset all rogues to original?", 24, UITheme.CARROT_LIGHT, true))
	_confirm.add_child(UITheme.button("Yes, reset them", _reset_all))
	_no = UITheme.button("No", _cancel_reset)
	_confirm.add_child(_no)
	_fill_list()


## The cast as buttons, the ones with the most history with you first; the first in focus.
func _fill_list() -> void:
	for old in _list.get_children():
		_list.remove_child(old)
		old.queue_free()
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


func _ask_reset() -> void:
	_buttons.visible = false
	_confirm.visible = true
	_no.grab_focus()


func _cancel_reset() -> void:
	_confirm.visible = false
	_buttons.visible = true
	_reset.grab_focus()


## Every rogue back to how it started (your trophies stay yours).
func _reset_all() -> void:
	RivalBook.reset_rogues()
	_confirm.visible = false
	_buttons.visible = true
	_sub.text = "Every rogue is back to how it started: no rivals, no nemeses, no scars. Your trophies stay yours."
	_fill_list()


## The right stick reads on down the card (the left stick and the D-pad walk the list).
func _process(delta: float) -> void:
	var tilt := Input.get_axis(&"look_up", &"look_down")
	if tilt != 0.0:
		_card_scroll.get_v_scroll_bar().value += clampf(tilt, -1.0, 1.0) * STICK_SCROLL * delta


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		if _confirm.visible:
			_cancel_reset()   # (backing out of the question, not the gallery)
		else:
			closed.emit()
	elif event.is_action_pressed(&"ui_page_down") or event.is_action_pressed(&"ui_page_up"):
		var bar := _card_scroll.get_v_scroll_bar()
		bar.value += _card_scroll.size.y * 0.8 * (1.0 if event.is_action_pressed(&"ui_page_down") else -1.0)
		get_viewport().set_input_as_handled()


## "More below" while there's more of the card under the bottom edge.
func _update_more() -> void:
	var bar := _card_scroll.get_v_scroll_bar()
	_more.modulate.a = 1.0 if bar.max_value - bar.page > 1.0 and bar.value < bar.max_value - bar.page - 1.0 else 0.0


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
	var scarred := "  ·  scarred" if not RivalBook.all_scars(n).is_empty() else ""   # (its portrait wears them)
	return "%s%s  ·  %s%s" % [tag, Cast.title(n), SPECIES.get(Cast.member(n).species, ""), scarred]


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
## And of its time away from you (WarrenSim): scars other rogues gave it, and its mood;
## and who turned on it in a gang.
static func memory_lines(n: String) -> Array:
	var out := []
	var sc := RivalBook.scars(n)
	if not sc.is_empty():
		out.append("Scars: %s. It learned: %s." % [", ".join(sc.map(func(x): return "%s (%s)" % [RivalBook.SCARS[x].text, RivalBook.SCARS[x].why])),
			"; ".join(sc.map(func(x): return RivalBook.SCARS[x].learned))])
	var from := RivalBook.scars_from(n)
	if not from.is_empty():
		out.append("Scars from other rogues while you were away (they heal in a few days): %s." % ", ".join(from.keys().map(
			func(x): return "%s (from %s)" % [RivalBook.SCARS[x].text, from[x]])))
	match RivalBook.mood(n):
		"cocky":
			out.append("Cocky: it's been winning while you were away, and fights braver (and a little sloppier) for it.")
		"wary":
			out.append("Wary: fresh from a beating while you were away, it keeps its distance.")
	var betrayed := RivalBook.betrayed_by(n)
	if not betrayed.is_empty():
		out.append("Betrayed by %s. It'll never gang up with them again." % ", ".join(betrayed.keys().map(
			func(b): return "%s (%s)" % [b, _times(int(betrayed[b]))])))
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
	_card_scroll.scroll_vertical = 0   # (each card from its top)
