class_name GazettePanel
extends PanelContainer
## The Warren Gazette: the news from the matches the rogues played while you
## were away (WarrenSim), on a sheet of newsprint. The front-page headline
## and the other stories, then Feud Watch (the hottest grudges between
## rogues), Wanted (who's after you) and the standings. It opens by itself
## when there's a new edition (MainMenu), and from the menu any time after.

signal closed

const PAPER := Color("f2e8d0")
const RULE := Color("2b2118")
const STICK_SCROLL := 900.0   # px/s at full right-stick tilt

var _scroll: ScrollContainer
var _back: Button
var _headline: Label


func _ready() -> void:
	theme = UITheme.theme()
	custom_minimum_size = Vector2(1180, 0)
	var paper := StyleBoxFlat.new()
	paper.bg_color = PAPER
	paper.border_color = RULE
	paper.set_border_width_all(3)
	paper.set_corner_radius_all(6)
	paper.set_content_margin_all(28)
	add_theme_stylebox_override("panel", paper)
	var ed := WarrenSim.edition()
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	add_child(v)
	var mast := UITheme.label("THE WARREN GAZETTE", 64, UITheme.INK, true)
	mast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(mast)
	v.add_child(_rule(3))
	var line := UITheme.label(dateline(ed), 19, UITheme.INK)
	line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(line)
	v.add_child(_rule(1))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 26)
	v.add_child(h)
	_scroll = ScrollContainer.new()
	_scroll.custom_minimum_size = Vector2(700, 500)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	h.add_child(_scroll)
	var news := VBoxContainer.new()
	news.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	news.add_theme_constant_override("separation", 8)
	_scroll.add_child(news)
	var stories: Array = ed.get("stories", [])
	if stories.is_empty():
		news.add_child(_text("No news yet. The rogues are still sleeping off the last match.", 24))
	for i in stories.size():
		var head := UITheme.label(String(stories[i].title), 42 if i == 0 else 26, UITheme.INK, true)
		head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		news.add_child(head)
		if i == 0:
			_headline = head
		news.add_child(_text(String(stories[i].text), 22 if i == 0 else 19))
		if i < stories.size() - 1:
			news.add_child(_rule(1))
	var side := VBoxContainer.new()
	side.custom_minimum_size = Vector2(380, 0)
	side.add_theme_constant_override("separation", 6)
	h.add_child(side)
	_section(side, "FEUD WATCH", WarrenSim.feuds().map(func(f): return "%s wants %s (%s)" % [f[0], f[1], "betrayed!" if f[3] else ("once" if f[2] == 1 else "%d times" % f[2])]),
		"No feuds. Suspiciously peaceful.")
	_section(side, "WANTED", WarrenSim.wanted().map(func(n): return "%s  ·  %s" % [Cast.title(n), "your rival" if RivalBook.is_rival(n) else "out for you"]),
		"Nobody's after you. Yet.")
	_section(side, "STANDINGS", (ed.get("standings", []) as Array).map(func(s): return "%s  ·  %s" % [s[0], "1 win" if int(s[1]) == 1 else "%d wins" % int(s[1])]),
		"No matches played.")
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(row)
	_back = UITheme.button("Back", func(): closed.emit())
	row.add_child(_back)
	_back.grab_focus.call_deferred()
	for l in find_children("*", "Label", true, false):
		(l as Label).add_theme_constant_override("outline_size", 0)   # (ink on paper: no outline)
	WarrenSim.mark_read()


## "Wednesday 28 October · 4 matches while you were away · One acorn"
static func dateline(ed: Dictionary) -> String:
	if ed.is_empty():
		return "No edition yet"
	var when := int(ed.get("when", 0)) + int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	var d := Time.get_datetime_dict_from_unix_time(when)
	const DAYS := ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
	const MONTHS := ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
	var n := int(ed.get("matches", 0))
	return "%s %d %s  ·  %d %s while you were away  ·  One acorn" % [DAYS[int(d.weekday)], int(d.day), MONTHS[int(d.month) - 1], n, "match" if n == 1 else "matches"]


## The headline as shown (tests).
func headline() -> String:
	return _headline.text if _headline else ""


## The right stick (or the mouse wheel) reads on down the news, like the gallery's cards.
func _process(delta: float) -> void:
	var tilt := Input.get_axis(&"look_up", &"look_down")
	if tilt != 0.0:
		_scroll.get_v_scroll_bar().value += clampf(tilt, -1.0, 1.0) * STICK_SCROLL * delta


func _section(parent: Control, title: String, lines: Array, none: String) -> void:
	var t := UITheme.label(title, 26, UITheme.BERRY, true)
	parent.add_child(t)
	parent.add_child(_rule(2))
	for s in (lines if not lines.is_empty() else [none]):
		parent.add_child(_text(String(s), 18))
	parent.add_child(Control.new())


func _text(s: String, size: int) -> Label:
	var l := UITheme.label(s, size, UITheme.INK)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


func _rule(px: int) -> ColorRect:
	var r := ColorRect.new()
	r.color = RULE
	r.custom_minimum_size = Vector2(0, px)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r
