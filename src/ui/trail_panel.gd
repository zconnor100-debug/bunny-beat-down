class_name TrailPanel
extends PanelContainer
## The Trail (Run): start a run, see where it can go and pick the next stop,
## and take what you earned between stops. Top: your acorn helmets, rewinds,
## boons and keepsake. Then, in order: a reward waiting (a boon draft, a
## keepsake to pocket), a picnic to settle, or the map: five columns of stops,
## left to right, the ones you can go to next lit up. A run that's over (or
## finished) gets its summary and a new run. Picking a match stop emits
## play_stop (the menu opens the match).

signal closed
signal play_stop

var _v: VBoxContainer
var _abandon_armed := false


func _ready() -> void:
	theme = UITheme.theme()
	custom_minimum_size = Vector2(1500, 0)
	_v = VBoxContainer.new()
	_v.add_theme_constant_override("separation", 14)
	add_child(_v)
	rebuild()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		closed.emit()


func rebuild() -> void:
	for c in _v.get_children():
		_v.remove_child(c)
		c.queue_free()
	var title := UITheme.label("The Trail", 56, UITheme.CARROT_LIGHT, true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_v.add_child(title)
	var s := Run.state()
	if s.get("complete", false) or s.get("over", false):
		_summary(s)
	elif not s.get("active", false):
		_intro()
	else:
		_v.add_child(_status(s))
		if not Run.pending().is_empty():
			_reward(Run.pending()[0])
		elif Run.current().get("kind", "") == "picnic":
			_picnic()
		else:
			_map(s)
	_focus_first.call_deferred()


func _focus_first() -> void:
	var f := UITheme.first_focusable(self)
	if f:
		f.grab_focus()


func _text(t: String, size := 22, c := UITheme.CREAM) -> Label:
	var l := UITheme.label(t, size, c)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(1300, 0)
	return l


func _buttons(items: Array) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 18)
	for it in items:
		var b := UITheme.button(it[0], it[1])
		if it.size() > 2:
			b.disabled = not it[2]
		row.add_child(b)
	return row


func _intro() -> void:
	_v.add_child(_text("A run is five stops down the Trail, one after another, ending at The Big Beat Down. "
		+ "Every stop has a goal: make the top few, or beat down enough critters. Miss it and one of your three acorn helmets cracks; "
		+ "lose all three and the run is over. Your boons, your rewinds (three for the whole run) and one keepsake gun carry from stop to stop."))
	_v.add_child(_text(Run.records_line(), 20, Color(UITheme.CREAM, 0.7)))
	_v.add_child(_buttons([["Start a run", func():
		Run.start(randi_range(1, 999999))
		rebuild()], ["Back", func(): closed.emit()]]))


func _summary(s: Dictionary) -> void:
	var done: bool = s.get("complete", false)
	var head := UITheme.label("RUN COMPLETE!" if done else "RUN OVER", 48, UITheme.CARROT if done else UITheme.BERRY, true)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_v.add_child(head)
	var st: Dictionary = s.get("stats", {})
	_v.add_child(_text("Stops cleared: %d of %d  ·  matches %d  ·  wins %d  ·  beat-downs %d" % [mini(int(s.row), Run.ROWS), Run.ROWS,
		int(st.get("matches", 0)), int(st.get("wins", 0)), int(st.get("kills", 0))]))
	if done:
		_v.add_child(_text("+%d 🌰 for finishing the run." % Run.COMPLETE_ACORNS, 22, UITheme.CARROT_LIGHT))
	Boons.reset(s.get("boons", {}))
	if not Boons.held.is_empty():
		_v.add_child(_text("Your build: " + Boons.summary(), 20, Color(UITheme.CREAM, 0.8)))
	_v.add_child(_text(Run.records_line(), 20, Color(UITheme.CREAM, 0.7)))
	_v.add_child(_buttons([["Start a new run", func():
		Run.start(randi_range(1, 999999))
		rebuild()], ["Back", func():
		Run.clear()
		closed.emit()]]))


## 🌰🌰◌ helmets, rewinds, boons, keepsake (and the last stop's result).
func _status(s: Dictionary) -> Control:
	var v := VBoxContainer.new()
	var h := int(s.get("helmets", Run.HELMETS))
	var shells := "🌰".repeat(h) + "◌".repeat(maxi(0, Run.HELMETS - h))
	var keep := Run.keepsake()
	Boons.reset(Run.boons())
	v.add_child(_text("Helmets %s   ·   Rewinds ⟲ %d   ·   Keepsake: %s" % [shells, int(s.get("rewinds", 0)),
		keep.display_name() if keep else "none"], 24))
	v.add_child(_text("Boons: " + (Boons.summary() if not Boons.held.is_empty() else "none yet"), 20, Color(UITheme.CREAM, 0.8)))
	var last: Dictionary = s.get("last", {})
	if not last.is_empty():
		var how := "placed #%d of %d, %d beat-down%s" % [int(last.placement), int(last.total), int(last.kills), "" if int(last.kills) == 1 else "s"]
		v.add_child(_text(("Goal made: %s." if last.met else "Goal missed: %s. A helmet cracked.") % how, 20,
			UITheme.LEAF if last.met else UITheme.BERRY))
	return v


## A reward waiting: "draft" (a boon) or {"keepsake": [gun dicts]}.
func _reward(r) -> void:
	if str(r) == "draft":
		var d := DraftPanel.new()
		d.heading = "Pick a boon"
		d.choices = Boons.offer(_rng(), 3)
		d.chosen.connect(func(id):
			Run.take_pending(id)
			rebuild())
		var c := CenterContainer.new()
		c.add_child(d)
		_v.add_child(c)
		if d.choices.is_empty():
			Run.take_pending()
			rebuild.call_deferred()
		return
	if r is Dictionary and r.has("keepsake"):
		_v.add_child(_text("Pocket a keepsake: one gun you were holding, for the start of the next stop.", 26, UITheme.CARROT_LIGHT))
		var items := []
		for d in r.keepsake:
			var w := WeaponInstance.from_dict(d)
			if w:
				items.append([w.display_name(), func():
					Run.take_pending("", d)
					rebuild()])
		items.append(["Leave them", func():
			Run.take_pending()
			rebuild()])
		_v.add_child(_buttons(items))


## The same three boons however often the Trail is opened before you pick.
func _rng() -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	var s := Run.state()
	r.seed = int(s.get("seed", 1)) * 97 + int(s.get("row", 0)) * 13 + int(s.get("stats", {}).get("matches", 0)) * 7 + Run.pending().size()
	return r


func _picnic() -> void:
	_v.add_child(_text("A picnic. Nobody's fighting here. Take one:", 26, UITheme.CARROT_LIGHT))
	_v.add_child(_buttons([
		["Mend a helmet", func():
			Run.picnic("mend")
			rebuild(), Run.helmets() < Run.HELMETS],
		["Find %d rewinds" % Run.PICNIC_REWINDS, func():
			Run.picnic("rewinds")
			rebuild()],
		["Take a boon", func():
			Run.picnic("boon")
			rebuild()]]))


func _map(s: Dictionary) -> void:
	var next := Run.choices()
	var grid := HBoxContainer.new()
	grid.alignment = BoxContainer.ALIGNMENT_CENTER
	grid.add_theme_constant_override("separation", 14)
	_v.add_child(grid)
	var path := _path(s)
	for r in Run.ROWS:
		var col := VBoxContainer.new()
		col.alignment = BoxContainer.ALIGNMENT_CENTER
		col.add_theme_constant_override("separation", 10)
		var head := UITheme.label("Stop %d" % (r + 1) if r < Run.ROWS - 1 else "Finale", 20, Color(UITheme.CREAM, 0.7))
		head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(head)
		grid.add_child(col)
		var row: Array = s.trail[r]
		for i in row.size():
			var st: Dictionary = row[i]
			var here := r == int(s.row) and next.has(i)
			var b := UITheme.button(stop_text(st, r, path.get(r, -1) == i), func(): _go(i))
			b.custom_minimum_size = Vector2(270, 150)
			b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			b.add_theme_font_size_override("font_size", 18)
			b.disabled = not here
			col.add_child(b)
	_v.add_child(_text("Next: pick one of the lit stops.", 20, Color(UITheme.CREAM, 0.7)))
	_v.add_child(_buttons([["Abandon run" if not _abandon_armed else "Really give up the run?", func():
		if _abandon_armed:
			Run.abandon()
		_abandon_armed = not _abandon_armed
		rebuild()], ["Back", func(): closed.emit()]]))


## The stops already played: {row: column}.
func _path(s: Dictionary) -> Dictionary:
	var out := {}
	for step in s.get("path", []):
		out[int(step[0])] = int(step[1])
	return out


## A stop's button: kind, map, modifiers and goal.
static func stop_text(st: Dictionary, row: int, visited := false) -> String:
	var kind: Dictionary = Run.KINDS[st.kind]
	var lines := ["%s%s" % ["✓ " if visited else "", kind.name]]
	if st.kind == "picnic":
		lines.append("Rest a while")
	else:
		lines.append(Run.MAP_NAMES.get(st.map, st.map))
		var mods: Array = st.mods.filter(func(m): return m != "golden_hour").map(func(m): return Burrow.MODIFIERS[m].name)
		if not mods.is_empty():
			lines.append(", ".join(mods))
		if st.kind == "finale":
			lines.append("Goal: top %d" % Run.FINALE_TOP)
		else:
			var r := clampi(row, 0, Run.GOAL_TOP.size() - 1)
			var k := 0.7 if st.kind == "golden" else 1.0
			lines.append("Goal: top %d%% or %d beat-downs" % [roundi(Run.GOAL_TOP[r] * k * 100.0), Run.GOAL_KILLS[r] + (1 if st.kind == "golden" else 0)])
	return "\n".join(lines)


func _go(col: int) -> void:
	if not Run.choose(col):
		return
	if Run.current().get("kind", "") == "picnic":
		rebuild()
		return
	Run.in_match = true
	play_stop.emit()
