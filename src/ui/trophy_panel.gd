class_name TrophyPanel
extends PanelContainer
## The Trophy Room: your trackers (StatBook). A row for every carrot gun and
## the club (beat-downs, accuracy, headshots, damage, longest beat-down) and
## for every critter you can play (matches, wins, best placing, beat-downs,
## beat-downs per time beaten, accuracy), with totals, your runs and the
## signature guns you've won; on its second page, the milestones (Mastery):
## what each takes, how far along you are, what it gives; on its third, the
## ladders (Mastery.LADDERS), one row each at the tier you're climbing, with
## a star for every tier climbed; and on its fourth, the bosses: how they came
## (BossLore), then one boss at a time, your record against it, its story's
## chapters (each opened by facing it) and the milestones for beating it.
## Fits without scrolling; B or Back closes it.

signal closed

const CRITTERS := [&"bun", &"bandit_bunny", &"squirrel", &"fox", &"raccoon", &"frog", &"beaver", &"hamster"]


func _ready() -> void:
	theme = UITheme.theme()
	custom_minimum_size = Vector2(1180, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	add_child(v)
	var title := UITheme.label("Trophy Room", 52, UITheme.CARROT_LIGHT, true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var pages := HBoxContainer.new()
	pages.alignment = BoxContainer.ALIGNMENT_CENTER
	pages.add_theme_constant_override("separation", 14)
	v.add_child(pages)
	var trackers := VBoxContainer.new()
	trackers.add_theme_constant_override("separation", 10)
	v.add_child(trackers)
	var milestones := VBoxContainer.new()
	milestones.visible = false
	v.add_child(milestones)
	var ladders := VBoxContainer.new()
	ladders.visible = false
	v.add_child(ladders)
	var bosses := _bosses_page()
	bosses.visible = false
	v.add_child(bosses)
	for page in [["Trackers", trackers], ["Milestones", milestones], ["Ladders", ladders], ["Bosses", bosses]]:
		pages.add_child(UITheme.button(page[0], func():
			for p in [trackers, milestones, ladders, bosses]:
				p.visible = p == page[1]))
	trackers.add_child(UITheme.label("Guns", 28, UITheme.CARROT_LIGHT, true))
	trackers.add_child(_table(["", "Beat-downs", "Accuracy", "Headshots", "Damage", "Longest"], gun_rows()))
	trackers.add_child(UITheme.label("Critters", 28, UITheme.CARROT_LIGHT, true))
	trackers.add_child(_table(["", "Matches", "Wins", "Best", "Beat-downs", "Per defeat", "Accuracy"], critter_rows()))
	trackers.add_child(UITheme.label("Runs: " + Run.records_line(), 21, UITheme.CREAM))
	var sigs := RivalBook.signatures()
	trackers.add_child(UITheme.label("Signature guns won: " + (", ".join(sigs.map(func(b): return RivalBook.signature_gun(b).display_name()))
		if not sigs.is_empty() else "none yet (win a nemesis hunt)"), 21, UITheme.CREAM))
	milestones.add_child(_milestones())
	var about := UITheme.label("The long haul: every ladder has three tiers, each harder than the last.", 20, Color(UITheme.CREAM, 0.8))
	about.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ladders.add_child(about)
	ladders.add_child(_milestones(Mastery.ladder_rows(), "Ladder", "The next tier", true))
	var back := UITheme.button("Back", func(): closed.emit())
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(back)
	back.grab_focus.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		closed.emit()


## [name, beat-downs, accuracy, headshots, damage, longest] for each gun, then totals.
static func gun_rows() -> Array:
	var rows := []
	var total := {"kills": 0.0, "shots": 0.0, "hits": 0.0, "heads": 0.0, "damage": 0.0, "longest": 0.0}
	for id in StatBook.GUNS:
		var g := StatBook.gun(id)
		rows.append([StatBook.gun_name(id), "%d" % int(g.kills), StatBook.percent(g), "%d" % int(g.heads),
			"%d" % int(g.damage), "%d m" % roundi(g.longest) if g.longest > 0.0 else "—"])
		for k in total:
			total[k] = maxf(total[k], g[k]) if k == "longest" else total[k] + g[k]
	rows.append(["All", "%d" % int(total.kills), StatBook.percent(total), "%d" % int(total.heads), "%d" % int(total.damage),
		"%d m" % roundi(total.longest) if total.longest > 0.0 else "—"])
	return rows


## [name, matches, wins, best, beat-downs, per defeat, accuracy] for each critter.
static func critter_rows() -> Array:
	var rows := []
	for id in CRITTERS:
		var def: CritterDef = load("res://data/critters/%s.tres" % id)
		var c := StatBook.critter(id)
		var per := "—" if c.matches <= 0.0 else "%.1f" % (c.kills / maxf(c.deaths, 1.0))
		rows.append([def.display_name if def else String(id), "%d" % int(c.matches), "%d" % int(c.wins),
			"#%d" % int(c.best) if c.best > 0.0 else "—", "%d" % int(c.kills), per, StatBook.percent(c)])
	return rows


## The milestones (or the ladders, with what each one's top tier gives): ✓
## and gold once reached.
func _milestones(rows := Mastery.rows(), what := "Milestone", takes := "What it takes", top := false) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 5 if top else 4
	grid.add_theme_constant_override("h_separation", 26)
	grid.add_theme_constant_override("v_separation", 3)
	for h in [what, takes, "", "What it gives"] + (["At the top"] if top else []):
		grid.add_child(UITheme.label(h, 18, Color(UITheme.CREAM, 0.7)))
	for r in rows:
		var c: Color = UITheme.CARROT_LIGHT if r[4] else UITheme.CREAM
		grid.add_child(UITheme.label(("✓ " if r[4] else "") + String(r[0]), 19, c, r[4]))
		grid.add_child(UITheme.label(r[1], 18, Color(UITheme.CREAM, 0.9)))
		grid.add_child(UITheme.label(r[2], 18, c))
		grid.add_child(UITheme.label(r[3], 18, UITheme.LEAF if r[4] else Color(UITheme.CREAM, 0.75)))
		if top:
			grid.add_child(UITheme.label(r[5], 18, UITheme.LEAF if r[4] else Color(UITheme.CARROT_LIGHT, 0.85)))
	return grid


# ---- the bosses ---------------------------------------------------------------------------------

## The Bosses page: the Warren's story of how the giants came, a button for
## each boss, and the boss picked.
func _bosses_page() -> VBoxContainer:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 8)
	page.add_child(UITheme.label(BossLore.MYTH_TITLE, 26, UITheme.CARROT_LIGHT, true))
	var myth := UITheme.label(BossLore.MYTH, 17, Color(UITheme.CREAM, 0.85))
	myth.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	myth.custom_minimum_size = Vector2(1140, 0)
	page.add_child(myth)
	var pick := HBoxContainer.new()
	pick.add_theme_constant_override("separation", 14)
	page.add_child(pick)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 6)
	page.add_child(body)
	for id in BossLore.IDS:
		var b: Dictionary = BossLore.of(id)
		pick.add_child(UITheme.button("%s (%s)" % [b.name, b.where], func(): _show_boss(body, id)))
	_show_boss(body, BossLore.IDS[0])
	return page


## [what it's counted, how many] for your record against a boss, as shown.
static func boss_record(id: String) -> Array:
	var r := StatBook.boss(id)
	var best := "—" if r.best <= 0.0 else "%d:%02d" % [int(r.best) / 60, int(r.best) % 60]
	return [["Faced", "%d" % int(r.fought)], ["Beaten", "%d" % int(r.beaten)], ["Still standing", "%d" % int(r.standing)],
		["Last blows", "%d" % int(r.last_blows)], ["On Hard", "%d" % int(r.hard)], ["Fastest", best],
		["Your damage", Mastery.grouped(int(r.damage))]]


## One boss on the Bosses page: its name, your record, the chapters of its
## story (the latest one you've opened shown; a closed one says what opens
## it), its milestone and the ones for every boss, and the bosses' ladders.
func _show_boss(body: VBoxContainer, id: String) -> void:
	for c in body.get_children():
		c.queue_free()
	var b: Dictionary = BossLore.of(id)
	body.add_child(UITheme.label("%s, %s" % [String(b.name).to_upper(), b.title], 30, UITheme.CREAM, true))
	body.add_child(UITheme.label("   •   ".join(boss_record(id).map(func(r): return "%s %s" % r)), 19, UITheme.CARROT_LIGHT))
	var chapters := HBoxContainer.new()
	chapters.add_theme_constant_override("separation", 10)
	body.add_child(chapters)
	var text := UITheme.label("", 18, UITheme.CREAM)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.custom_minimum_size = Vector2(1140, 112)
	body.add_child(text)
	var read := func(i: int):
		var ch: Array = b.chapters[i]
		text.text = ch[1] if BossLore.is_open(id, i) else BossLore.opens_when(id, i)
		text.add_theme_color_override("font_color", UITheme.CREAM if BossLore.is_open(id, i) else Color(UITheme.CREAM, 0.6))
	for i in b.chapters.size():
		var open := BossLore.is_open(id, i)
		var btn := UITheme.button("%s. %s" % [Mastery.TIER_NAMES[i], b.chapters[i][0] if open else "? ? ?"], read.bind(i))
		chapters.add_child(btn)
	read.call(BossLore.chapters_open(id) - 1)
	body.add_child(_milestones(Mastery.rows(id) + Mastery.rows("*")))
	body.add_child(_milestones(Mastery.ladder_rows(true), "Ladder", "The next tier", true))


func _table(headers: Array, rows: Array) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = headers.size()
	grid.add_theme_constant_override("h_separation", 34)
	grid.add_theme_constant_override("v_separation", 4)
	for h in headers:
		grid.add_child(UITheme.label(h, 19, Color(UITheme.CREAM, 0.7)))
	for r in rows:
		for i in r.size():
			var l := UITheme.label(r[i], 21, UITheme.CARROT_LIGHT if r[0] == "All" else UITheme.CREAM)
			if i == 0:
				l.custom_minimum_size = Vector2(260, 0)
			grid.add_child(l)
	return grid
