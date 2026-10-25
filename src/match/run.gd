class_name Run
extends RefCounted
## A run: five stops down the Trail, picked one at a time from a branching
## map, ending at The Big Beat Down. Each stop is a map with its own run
## modifiers and a goal (make the top N, or beat down K critters); fall
## short and one of your three acorn helmets cracks, and when the last one
## goes the run is over. What carries from stop to stop is what makes it a
## run: your boons (Boons: a draft after every goal you make, two after a
## Grudge Match), your rewinds (one pool for the whole run, not three a
## match), and a keepsake: one gun you were holding at the end of a match,
## pocketed for the start of the next. Picnics are rests: mend a helmet,
## find two rewinds, or take a boon. Saved with the PlayerProfile after every
## step, so a run survives quitting the game.

const ROWS := 5
const HELMETS := 3
const REWINDS := 3
const MAPS := ["island", "cage", "toybox"]
const MAP_NAMES := {"island": "Wildwood Island", "cage": "Hamster Cage", "toybox": "Toy Box Bash"}
const KINDS := {
	"skirmish": {"name": "Skirmish", "text": "An ordinary beat-down. A boon if you make the goal."},
	"grudge": {"name": "Grudge Match", "text": "The bots you've made radical come for you, as a gang. Two boons if you make the goal."},
	"golden": {"name": "Golden Grove", "text": "All loot one rarity better and double acorns, for a harder goal."},
	"picnic": {"name": "Picnic", "text": "No fighting: mend a helmet, find two rewinds, or take a boon."},
	"finale": {"name": "The Big Beat Down", "text": "A full lobby and a nemesis hunting you. Make the top 3 to finish the run."},
}
## The goal at each row: make the top this share of the lobby (at least 3)...
const GOAL_TOP := [0.5, 0.4, 0.3, 0.2]
## ... or beat down this many.
const GOAL_KILLS := [2, 3, 4, 5]
const FINALE_TOP := 3
const FINALE_LOBBY := 24           ## the finale's lobby is at least this big (with you)
const COMPLETE_ACORNS := 150
const PICNIC_REWINDS := 2

## Set by the Trail when it starts a match stop; the match reads it.
static var in_match := false


static func _book() -> ConfigFile:
	return PlayerProfile._book()


static func state() -> Dictionary:
	return _book().get_value("run", "state", {})


static func _save(s: Dictionary) -> void:
	_book().set_value("run", "state", s)
	PlayerProfile.save()


static func active() -> bool:
	return state().get("active", false)


## Start a new run (the old one, if any, is given up).
static func start(seed_: int) -> void:
	var s := {"active": true, "seed": seed_, "trail": generate(seed_), "row": 0, "at": -1, "playing": -1,
		"helmets": max_helmets(), "rewinds": REWINDS + Mastery.run_rewinds(), "boons": {}, "keepsake": {},
		"pending": [], "last": {}, "over": false, "complete": false,
		"stats": {"matches": 0, "wins": 0, "kills": 0, "goals": 0}}
	_record("started", 1)
	_save(s)


## The Trail: ROWS rows of stops (the last is the finale), each stop
## {map, kind, mods, links} where links are the stops in the next row it leads to.
static func generate(seed_: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	var mods := Burrow.MODIFIERS.keys().filter(func(m): return m != "golden_hour")
	var trail := []
	for r in ROWS:
		var row := []
		var n := 1 if r == ROWS - 1 else rng.randi_range(2, 3)
		var picnic_done := false
		for i in n:
			var kind := "skirmish"
			if r == ROWS - 1:
				kind = "finale"
			else:
				var roll := rng.randf()
				if r > 0 and not picnic_done and roll < 0.25:
					kind = "picnic"
					picnic_done = true
				elif roll < 0.47:
					kind = "grudge"
				elif roll < 0.67:
					kind = "golden"
			var stop := {"map": MAPS[rng.randi() % MAPS.size()], "kind": kind, "mods": [], "links": []}
			if kind != "picnic":
				var k := clampi(r / 2 + rng.randi_range(0, 1), 0, 2)
				var pool := mods.duplicate()
				for j in k:
					stop.mods.append(pool.pop_at(rng.randi() % pool.size()))
				if kind == "golden":
					stop.mods.append("golden_hour")
			row.append(stop)
		trail.append(row)
	# paths: each stop leads to the stops nearest it in the next row (every
	# stop is reachable, none a dead end)
	for r in ROWS - 1:
		var a: Array = trail[r]
		var b: Array = trail[r + 1]
		for i in a.size():
			var pi := float(i) / maxf(a.size() - 1, 1)
			for j in b.size():
				var pj := float(j) / maxf(b.size() - 1, 1)
				if absf(pi - pj) <= 0.5 or b.size() == 1:
					a[i].links.append(j)
		for j in b.size():
			if not a.any(func(st): return st.links.has(j)):
				var near := roundi(float(j) / maxf(b.size() - 1, 1) * (a.size() - 1))
				a[near].links.append(j)
	return trail


## The stops you can go to next (indices into the current row).
static func choices() -> Array:
	var s := state()
	if not s.get("active", false) or s.over or s.complete:
		return []
	var row: int = s.row
	if row >= ROWS:
		return []
	if s.at < 0 or row == 0:
		return range(s.trail[0].size())
	return s.trail[row - 1][s.at].links.duplicate()


static func stop(row: int, col: int) -> Dictionary:
	var t: Array = state().get("trail", [])
	return t[row][col] if row < t.size() and col < t[row].size() else {}


## The stop being played right now ({} between stops).
static func current() -> Dictionary:
	var s := state()
	return stop(s.row, s.playing) if s.get("playing", -1) >= 0 else {}


## Go to stop `col` of the current row. Match stops are then played (the
## Trail opens the match with in_match set); picnics wait for picnic().
static func choose(col: int) -> bool:
	if not choices().has(col):
		return false
	var s := state()
	s.playing = col
	_save(s)
	return true


## A match stop's lobby size (the finale is always a big one).
static func opponents(setting: int) -> int:
	return maxi(setting, FINALE_LOBBY - 1) if current().get("kind", "") == "finale" else setting


## The current stop's goal: {"top": placing to make, "kills": or this many beat-downs}.
static func goal(total: int) -> Dictionary:
	var s := state()
	if current().get("kind", "") == "finale":
		return {"top": FINALE_TOP, "kills": 999}
	var r := clampi(int(s.get("row", 0)), 0, GOAL_TOP.size() - 1)
	var share: float = GOAL_TOP[r] * (0.7 if current().get("kind", "") == "golden" else 1.0)
	return {"top": maxi(3, ceili(total * share)), "kills": GOAL_KILLS[r] + (1 if current().get("kind", "") == "golden" else 0)}


static func goal_text(total: int) -> String:
	var g := goal(total)
	if g.kills >= 999:
		return "make the top %d" % g.top
	return "make the top %d, or beat down %d" % [g.top, g.kills]


static func goal_met(placement: int, total: int, kills: int) -> bool:
	var g := goal(total)
	return placement <= int(g.top) or kills >= int(g.kills)


## A match stop is over for you. `keep`: the guns you were holding at the end
## (a keepsake comes from these). Returns {met, helmets, over, complete}.
static func finish_match(placement: int, total: int, kills: int, won: bool, keep: Array, rewinds_left: int, boons: Dictionary) -> Dictionary:
	var s := state()
	if not s.get("active", false) or s.get("playing", -1) < 0:
		return {}
	var kind: String = current().get("kind", "skirmish")
	var met := goal_met(placement, total, kills)
	s.stats.matches += 1
	s.stats.kills += kills
	if won:
		s.stats.wins += 1
	s.rewinds = rewinds_left
	s.boons = boons.duplicate()
	s.keepsake = {}
	var pending := []
	if met:
		s.stats.goals += 1
		pending.append("draft")
		if kind == "grudge":
			pending.append("draft")
	else:
		s.helmets -= 1
		_record("helmets_lost", 1)
	var options := keep.filter(func(w): return w is WeaponInstance).map(func(w): return (w as WeaponInstance).to_dict())
	if not options.is_empty() and s.helmets > 0:
		pending.append({"keepsake": options})
	s.pending = pending
	s.last = {"kind": kind, "placement": placement, "total": total, "kills": kills, "won": won, "met": met}
	if s.helmets <= 0:
		s.over = true
		s.active = false
		s.pending = []
	elif kind == "finale" and met:
		s.complete = true
		s.active = false
		_record("completed", 1)
		Burrow.add_acorns(COMPLETE_ACORNS)
	elif kind != "finale" or met:
		_advance(s)
	# (missing the finale costs a helmet; you can try it again)
	s.playing = -1
	_record_best(s)
	_save(s)
	return {"met": met, "helmets": s.helmets, "over": s.over, "complete": s.complete}


static func _advance(s: Dictionary) -> void:
	var path: Array = s.get("path", [])
	path.append([s.row, s.playing])
	s.path = path
	s.at = s.playing
	s.row += 1


## A picnic: "mend" (a cracked helmet back), "rewinds" (two more) or "boon"
## (a draft).
static func picnic(choice: String) -> void:
	var s := state()
	if current().get("kind", "") != "picnic":
		return
	match choice:
		"mend":
			s.helmets = mini(s.helmets + 1, max_helmets())
		"rewinds":
			s.rewinds += PICNIC_REWINDS
		"boon":
			s.pending = ["draft"]
	_advance(s)
	s.playing = -1
	_record_best(s)
	_save(s)


static func pending() -> Array:
	return state().get("pending", [])


## A reward waiting has been taken (a draft's boon, a keepsake, or skipped).
static func take_pending(boon := "", keepsake: Dictionary = {}) -> void:
	var s := state()
	if s.get("pending", []).is_empty():
		return
	var first = s.pending.pop_front()
	if boon != "" and str(first) == "draft":
		Boons.reset(s.boons)
		Boons.add(boon)
		s.boons = Boons.held.duplicate()
		Mastery.note_boons(Boons.held.size())
	if first is Dictionary and first.has("keepsake"):
		s.keepsake = keepsake
	_save(s)


## The boons to start a run match with.
static func boons() -> Dictionary:
	return state().get("boons", {})


static func keepsake() -> WeaponInstance:
	var k: Dictionary = state().get("keepsake", {})
	return WeaponInstance.from_dict(k) if not k.is_empty() else null


static func rewinds() -> int:
	return int(state().get("rewinds", REWINDS))


## Acorn helmets a run starts with (Trailblazer adds one: Mastery).
static func max_helmets() -> int:
	return HELMETS + Mastery.run_helmets()


static func helmets() -> int:
	return int(state().get("helmets", HELMETS))


## The run modifiers of the stop being played (plus Golden Hour for a golden one).
static func mods() -> Array:
	return current().get("mods", [])


## Give the run up.
static func abandon() -> void:
	var s := state()
	s.active = false
	s.over = true
	s.pending = []
	_save(s)


## Forget the finished run (so the Trail offers a new one).
static func clear() -> void:
	_book().set_value("run", "state", {})
	PlayerProfile.save()


# ---- records (the Trophy Room) ---------------------------------------------------------------

static func _record(key: String, by: int) -> void:
	_book().set_value("runs", key, int(_book().get_value("runs", key, 0)) + by)


static func _record_best(s: Dictionary) -> void:
	var reached := int(s.row) + (1 if s.complete else 0)
	if reached > int(_book().get_value("runs", "best_row", 0)):
		_book().set_value("runs", "best_row", reached)


static func record(key: String) -> int:
	return int(_book().get_value("runs", key, 0))


## "3 runs · 1 finished · deepest: stop 4 of 5"
static func records_line() -> String:
	if record("started") == 0:
		return "No runs yet."
	return "%d run%s started  ·  %d finished  ·  furthest: stop %d of %d" % [record("started"), "" if record("started") == 1 else "s",
		record("completed"), mini(record("best_row") + 1, ROWS), ROWS]
