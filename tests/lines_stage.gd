extends Node
## Stage for tests/export_lines.gd: every line a rogue can say, as templates
## keyed the way Cast.say keys them, for tools/voices/build_voices.py.

var out_path := "res://tools/voices/lines.json"


func _ready() -> void:
	var templates := {}
	for voice in RivalBook.PERSONALITIES:
		for event in ["spot", "kill", "lose"]:
			var lines: Array = RivalBook.PERSONALITIES[voice][event]
			for i in lines.size():
				templates["p.%s.%s.%d" % [voice, event, i]] = lines[i]
	for t in range(1, Cast.HEAT_LINES.size()):
		for event in Cast.HEAT_LINES[t]:
			var lines: Array = Cast.HEAT_LINES[t][event]
			for i in lines.size():
				templates["h.%d.%s.%d" % [t, event, i]] = lines[i]
	for piece in Cast.OUTFIT_LINES:
		for event in Cast.OUTFIT_LINES[piece]:
			var lines: Array = Cast.OUTFIT_LINES[piece][event]
			for i in lines.size():
				templates["o.%s.%s.%d" % [piece, event, i]] = lines[i]
	for i in Cast.FEUD_LINES.size():
		templates["f.%d" % i] = Cast.FEUD_LINES[i]
	for i in Cast.DIRECTOR_LINES.size():
		templates["d.%d" % i] = Cast.DIRECTOR_LINES[i]
	templates["hunt"] = Cast.HUNT_LINE
	for i in Cast.FLARE_LINES.size():
		templates["fl.%d" % i] = Cast.FLARE_LINES[i]
	for prefix in Cast.GANG_LINES:
		var lines: Array = Cast.GANG_LINES[prefix]
		for i in lines.size():
			templates["%s.%d" % [prefix, i]] = lines[i]
	for prefix in Cast.BOSS_LINES:
		var lines: Array = Cast.BOSS_LINES[prefix]
		for i in lines.size():
			templates["%s.%d" % [prefix, i]] = lines[i]
	for id in Cast.BOSS_NAME_LINES:
		templates["bn.%s" % id] = Cast.BOSS_NAME_LINES[id]
	templates["bk"] = Cast.BOSS_KEY_LINE
	var rogues := []
	for n in Cast.names():
		var m := Cast.member(n)
		rogues.append({"name": n, "species": m.species, "voice": m.voice, "says": m.says, "bio": m.bio})
	# what you can be called: your critter's name
	var you := []
	for f in DirAccess.get_files_at("res://data/critters"):
		if f.ends_with(".tres"):
			var d: CritterDef = load("res://data/critters/" + f)
			if d and d.id != &"test_critter" and not you.has(String(d.display_name)):
				you.append(String(d.display_name))
	you.sort()
	var data := {"templates": templates, "rogues": rogues, "you": you}
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(data, "  ", true) + "\n")
	f.close()
	print("LINES %d templates, %d rogues, %d names" % [templates.size(), rogues.size(), you.size()])
	get_tree().quit()
