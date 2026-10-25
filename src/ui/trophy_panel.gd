class_name TrophyPanel
extends PanelContainer
## The Trophy Room: your trackers (StatBook). A row for every carrot gun and
## the club (beat-downs, accuracy, headshots, damage, longest beat-down) and
## for every critter you can play (matches, wins, best placing, beat-downs,
## beat-downs per time beaten, accuracy), with totals. Fits without
## scrolling; B or Back closes it.

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
	v.add_child(UITheme.label("Guns", 28, UITheme.CARROT_LIGHT, true))
	v.add_child(_table(["", "Beat-downs", "Accuracy", "Headshots", "Damage", "Longest"], gun_rows()))
	v.add_child(UITheme.label("Critters", 28, UITheme.CARROT_LIGHT, true))
	v.add_child(_table(["", "Matches", "Wins", "Best", "Beat-downs", "Per defeat", "Accuracy"], critter_rows()))
	v.add_child(UITheme.label("Runs: " + Run.records_line(), 21, UITheme.CREAM))
	var sigs := RivalBook.signatures()
	v.add_child(UITheme.label("Signature guns won: " + (", ".join(sigs.map(func(b): return RivalBook.signature_gun(b).display_name()))
		if not sigs.is_empty() else "none yet (win a nemesis hunt)"), 21, UITheme.CREAM))
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
