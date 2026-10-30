class_name KernelHunt
extends RefCounted
## The Kernel Hunt: the quest line the bosses' story is building toward
## (docs/LORE.md), player against the environment. You and a squad of rogues
## against the Touched, critters the Starfall Acorn's light has got into,
## mission by mission through the acts, each ending in one of the boss
## fights. Its prologue, "Days Since Brutus": hold the Big Red Barn with the
## Barn Rangers against three waves of the Touched out of the Carrot Patch
## (MissionDirector), until something roars at Boulder Bluff. Act I, "The
## Carrot Patch", opens once the Barn's held: track the glowing carrots, burn
## the Patch and wake Brutus at Boulder Bluff (PatchMission). The acts after
## it are on the Kernel Hunt's page (QuestPanel), sealed.
##
## Which missions you've finished, and your best at each, are kept with the
## PlayerProfile.

## The acts, in order. `open`: playable (the rest are sealed for now), once
## the act `after` names is done.
const ACTS := [
	{"id": "prologue", "name": "Prologue", "title": "Days Since Brutus", "where": "Wildwood Island", "map": "island", "open": true,
		"brief": "The tally on the Big Red Barn's door says nine days since anyone saw Brutus. It has never got past nine. Now something is coming out of the Carrot Patch: critters with gold-green eyes. Hold the Barn with the Barn Rangers.",
		"goal": "Hold the Big Red Barn through three waves of the Touched."},
	{"id": "carrot_patch", "name": "Act I", "title": "The Carrot Patch", "where": "Wildwood Island", "open": true, "after": "prologue",
		"brief": "The tally on the Barn's door says nought. The Touched came out of the Carrot Patch, and something there is glowing. Track the glowing carrots back to where they grow, burn the Patch, and wake him at Boulder Bluff.",
		"goal": "Pull the five glowing carrots, burn the Carrot Patch, and beat Brutus at Boulder Bluff.", "ends": "Brutus"},
	{"id": "clockwork_decree", "name": "Act II", "title": "The Clockwork Decree", "where": "Toy Box Bash",
		"brief": "Free the toys he's wound, break his winding stations and storm Block Castle.", "ends": "the Tin Tyrant"},
	{"id": "foam_at_the_falls", "name": "Act III", "title": "Foam at the Falls", "where": "the Hamster Cage",
		"brief": "Down the tunnels under the bedding, toward the hum, and dam Water Bottle Falls.", "ends": "Nibbles"},
	{"id": "starfall", "name": "Finale", "title": "The Starfall", "where": "All three, then somewhere new",
		"brief": "The Kernels, together at last. The Briar comes for them.", "ends": "the Briar Heart"},
]

## The prologue's island (its Big Red Barn, Carrot Patch and Boulder Bluff
## where the mission wants them), and the Barn Rangers who hold it with you.
const SEED := 137
const RANGERS := ["Buck Toothington", "Dam Dan", "Hazel", "Kernel", "Duchess", "Captain Carrot", "Lily Pad Lou"]
## Act I: the rogues who see the Patch's smoke and come when Brutus wakes.
const ANSWER := ["Cottontail Kate", "Hops McGee", "Acorn Al", "Ember", "Rocco", "Bog Boss", "Timber", "Cheeks McGee"]
## The Touched's waves: how many at Scrappy (COUNT_SCALE for the others),
## the guns they carry, which ways they come (from the Carrot Patch, and
## round the sides), and whether a Touched giant comes with them.
const WAVES := [
	{"count": 6, "guns": [&"carrot_pistol", &"carrot_smg"], "from": ["patch"]},
	{"count": 9, "guns": [&"carrot_smg", &"carrot_rifle", &"carrot_shotgun"], "from": ["patch", "left"]},
	{"count": 12, "guns": [&"carrot_rifle", &"carrot_shotgun", &"carrot_smg", &"carrot_lmg"], "from": ["patch", "left", "right"],
		"giant": true},
]
const COUNT_SCALE := [0.7, 1.0, 1.35]   ## by difficulty (Sleepy, Scrappy, Savage)

## The mission being played (set by the QuestPanel as it starts one; "" in an
## ordinary match). The game reads it like Run.in_match.
static var playing := ""


static func _book() -> ConfigFile:
	return PlayerProfile._book()


static func act(id: String) -> Dictionary:
	for a in ACTS:
		if a.id == id:
			return a
	return {}


static func done(id: String) -> bool:
	return (_book().get_value("kernel", "done", {}) as Dictionary).has(id)


## Playable now: open, and the act before it done.
static func unlocked(id: String) -> bool:
	var a := act(id)
	return a.get("open", false) and (String(a.get("after", "")) == "" or done(String(a.after)))


## Your best at a mission: {time (seconds, fastest), barn (the most of the
## Barn left), rangers (the most rangers standing), touched (Touched beaten
## down, the most in one go)}, or {} if you've never finished it.
static func best(id: String) -> Dictionary:
	return (_book().get_value("kernel", "best", {}) as Dictionary).get(id, {})


static func played(id: String) -> int:
	return int((_book().get_value("kernel", "played", {}) as Dictionary).get(id, 0))


## How a mission went: `report` {won, time, barn, rangers, touched, wave}.
## Kept with the profile (and the Trophy Room's milestones read it).
static func note_result(id: String, report: Dictionary) -> void:
	var f := _book()
	var p: Dictionary = f.get_value("kernel", "played", {})
	p[id] = int(p.get(id, 0)) + 1
	f.set_value("kernel", "played", p)
	f.set_value("kernel", "touched", int(f.get_value("kernel", "touched", 0)) + int(report.get("touched", 0)))
	if report.get("won", false):
		var d: Dictionary = f.get_value("kernel", "done", {})
		d[id] = true
		f.set_value("kernel", "done", d)
		var all: Dictionary = f.get_value("kernel", "best", {})
		var b: Dictionary = all.get(id, {})
		b["time"] = minf(float(b.get("time", INF)), float(report.get("time", INF)))
		for k in ["barn", "rangers", "touched"]:
			b[k] = maxf(float(b.get(k, 0.0)), float(report.get(k, 0.0)))
		all[id] = b
		f.set_value("kernel", "best", all)
	PlayerProfile.save()


## Touched beaten down, in every mission you've played.
static func touched_beaten() -> int:
	return int(_book().get_value("kernel", "touched", 0))


## "Held · fastest 6:12 · every ranger home" (the Kernel Hunt's page).
static func record_line(id: String) -> String:
	var b := best(id)
	var verb := "Held" if id == "prologue" else "Done"
	if b.is_empty():
		return "Played %d time%s, not %s yet." % [played(id), "" if played(id) == 1 else "s", verb.to_lower()] if played(id) > 0 else "Not played yet."
	var t := roundi(float(b.time))
	var home := int(b.rangers)
	return "%s  ·  fastest %d:%02d  ·  %s" % [verb, t / 60, t % 60,
		"every ranger home" if home >= RANGERS.size() else "%d of %d rangers home, at best" % [home, RANGERS.size()]]
