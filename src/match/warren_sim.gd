class_name WarrenSim
extends RefCounted
## The rogues live while you're away. Every few hours of real time they play
## a match of their own, off-screen: not a physics one, a quick reckoning of
## who runs into whom (grudges and temper) and who comes out on top (each
## rogue's real record: RivalBook's trackers, its wins, its scars). What
## happens is written into RivalBook like anything that happens in your
## matches (wins, grudges, scars from the rogue that dealt them), so it
## carries into the next match you play, and the Warren Gazette (GazettePanel)
## prints the news.
##
## The warren's clock is kept in its own file; automated test runs use their
## own, like Settings.

const PATH := "user://gazette.cfg"
const TEST_PATH := "user://gazette_test.cfg"
const HOURS_PER_MATCH := 3.0    ## real hours between off-screen matches
const MAX_MATCHES := 12         ## at most this many to catch up on (the rest are forgotten)
const FIRST_EDITION := 2        ## matches in the very first paper (a new warren has news already)
const LOBBY := [20, 30]         ## rogues in an off-screen match
const SCAR_CHANCE := 0.04       ## a beat-down leaves a scar this often (they heal: RivalBook.HEAL_DAYS)
const STRENGTH := 2.5           ## how much the stronger rogue's edge counts (win_chance)
const PRIOR_ACCURACY := 0.3     ## a rogue's accuracy before it has fired much...
const PRIOR_SHOTS := 60.0       ## ...counted as this many shots
## Where off-screen matches happen ([in the paper, opening a sentence]).
const MAPS := [["on Wildwood Island", "On Wildwood Island"], ["in the Hamster Cage", "In the Hamster Cage"],
	["in the Toy Box", "In the Toy Box"]]
## How a score settled ends a story ({w} settled it with {l}).
const SETTLED := ["That's a score settled.", "Revenge, served cold.", "{w} says {l} had it coming.", "Call it even. {l} won't."]
## How a scar reads in the paper ([headline, story]; {w} dealt it, {l} wears it, {map} where).
const SCAR_NEWS := {
	"eye_patch": ["%s TAKES %s'S EYE", "{map}, {w} caught {l} with a headshot. {l} wears an eye patch now."],
	"arm_l": ["%s LEAVES %s IN BANDAGES", "{map}, {l} lost an arm to {w}. It's bandaged now, and {l} is not happy about it."],
	"arm_r": ["%s LEAVES %s IN BANDAGES", "{map}, {l} lost an arm to {w}. It's bandaged now, and {l} is not happy about it."],
	"leg_l": ["%s PUTS %s IN A SPLINT", "{map}, {w} took {l}'s leg off. {l} is limping about in a splint, blaming {w}."],
	"leg_r": ["%s PUTS %s IN A SPLINT", "{map}, {w} took {l}'s leg off. {l} is limping about in a splint, blaming {w}."],
	"singed": ["%s SINGES %s", "{map}, {w} blew {l} up. {l}'s fur is still smoking."],
}

static var _cfg: ConfigFile


static func path() -> String:
	return TEST_PATH if Settings.is_test_run() else PATH


static func _file() -> ConfigFile:
	if _cfg == null:
		_cfg = ConfigFile.new()
		_cfg.load(path())
	return _cfg


static func reset_for_tests() -> void:
	assert(Settings.is_test_run())
	_cfg = ConfigFile.new()
	_cfg.save(path())


## Play the matches the rogues had while you were away (one per
## HOURS_PER_MATCH since the warren's clock last moved, at most MAX_MATCHES),
## and print them: the new edition of the Gazette, or {} if there's no news.
static func catch_up(now := Time.get_unix_time_from_system()) -> Dictionary:
	var f := _file()
	var step := HOURS_PER_MATCH * 3600.0
	if not f.has_section_key("warren", "clock"):
		f.set_value("warren", "clock", now - FIRST_EDITION * step)   # (the very first paper)
	var clock := float(f.get_value("warren", "clock"))
	var due := int(floor((now - clock) / step))
	if due <= 0:
		return {}
	var n := mini(due, MAX_MATCHES)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(int(clock))
	var played := []
	for i in n:   # (each when it happened: the last one just now if some were forgotten)
		played.append(play_match(rng, (now - (n - 1 - i) * step) if due > MAX_MATCHES else clock + (i + 1) * step))
	# (the clock keeps the part-hours toward the next match, unless it had to forget some)
	f.set_value("warren", "clock", now if due > MAX_MATCHES else clock + n * step)
	var ed := edition_of(played, now, rng)
	f.set_value("warren", "edition", ed)
	f.save(path())
	RivalBook.save()
	return ed


## The latest Gazette ({} if there's never been one).
static func edition() -> Dictionary:
	return _file().get_value("warren", "edition", {})


## No news (RivalBook.reset_rogues: the rogues it was about start over). The
## warren's clock keeps running.
static func forget_news() -> void:
	if _file().has_section_key("warren", "edition"):
		_file().erase_section_key("warren", "edition")
		_file().save(path())


static func mark_read() -> void:
	var ed := edition()
	if not ed.is_empty() and not ed.get("read", false):
		ed["read"] = true
		_file().set_value("warren", "edition", ed)
		_file().save(path())


## One off-screen match: a lobby meets, two at a time, until one is left.
## Written into RivalBook as it goes. Returns what happened:
## {map, lobby, winner, beats: [{winner, loser, chance, paid_back, scar, left}]}.
## `at`: when it was played (unix time; scars heal from then).
static func play_match(rng: RandomNumberGenerator, at := Time.get_unix_time_from_system()) -> Dictionary:
	var all := Cast.names()
	for i in range(all.size() - 1, 0, -1):   # (shuffled by the match's own rng: the same news for the same absence)
		var j := rng.randi_range(0, i)
		var t = all[i]
		all[i] = all[j]
		all[j] = t
	var alive: Array = all.slice(0, rng.randi_range(LOBBY[0], LOBBY[1]))
	var map: int = rng.randi() % MAPS.size()
	var out := {"map": map, "lobby": alive.size(), "beats": []}
	while alive.size() > 1:
		var a: String = _pick_weighted(alive, func(n): return temper(n), rng)
		var b := _opponent(a, alive, rng)
		var chance := win_chance(a, b)
		var won := rng.randf() < chance
		var w := a if won else b
		var l := b if won else a
		alive.erase(l)
		var beat := {"winner": w, "loser": l, "chance": chance if won else 1.0 - chance,
			"paid_back": RivalBook.note_bot_beat(w, l), "scar": "", "left": alive.size()}
		if rng.randf() < SCAR_CHANCE:
			var scar := _scar_by(w, rng)
			if RivalBook.add_scar_from(l, scar, w, at):
				beat["scar"] = scar
		out.beats.append(beat)
	out["winner"] = alive[0]
	RivalBook.note_win(alive[0])
	return out


## How strong a rogue is off-screen: its way of fighting, its record (how
## well it really shoots, in your matches), its wins, and the scars it came
## back wiser from.
static func power(n: String) -> float:
	var p := float(RivalBook.PERSONALITIES[RivalBook.personality_of(n)].skill) * 5.0
	var st := RivalBook.bot_stats(n)
	var acc := (float(st.hits) + PRIOR_ACCURACY * PRIOR_SHOTS) / (float(st.shots) + PRIOR_SHOTS)
	p += (acc - PRIOR_ACCURACY) * 2.0
	p += 0.04 * minf(RivalBook.wins(n), 10.0)
	p += 0.03 * RivalBook.all_scars(n).size()
	return p


## The chance `a` beats `b` down when they meet.
static func win_chance(a: String, b: String) -> float:
	return 1.0 / (1.0 + exp(-(power(a) - power(b)) * STRENGTH))


## How keen a rogue is to start something (its temper, and how far off it picks fights).
static func temper(n: String) -> float:
	var style: Dictionary = Cast.STYLES.get(Cast.member(n).get("style", ""), {})
	return float(RivalBook.PERSONALITIES[RivalBook.personality_of(n)].aggression) \
		* float(style.get("fight_range", AIBrain.BOT_FIGHT_RANGE)) / AIBrain.BOT_FIGHT_RANGE


## Who `a` runs into: the one it holds the biggest grudge against, often, else anyone.
static func _opponent(a: String, alive: Array, rng: RandomNumberGenerator) -> String:
	var g := RivalBook.grudges(a)
	var best := ""
	for n in alive:
		if n != a and int(g.get(n, 0)) > int(g.get(best, 0)):
			best = n
	if best != "" and rng.randf() < 0.6:
		return best
	var others := alive.filter(func(n): return n != a)
	return others[rng.randi() % others.size()]


static func _pick_weighted(list: Array, weight: Callable, rng: RandomNumberGenerator) -> String:
	var total := 0.0
	for n in list:
		total += weight.call(n)
	var r := rng.randf() * total
	for n in list:
		r -= weight.call(n)
		if r <= 0.0:
			return n
	return list.back()


## The scar its favourite gun leaves: a rocket singes, a sniper takes an eye, anything else a limb.
static func _scar_by(w: String, rng: RandomNumberGenerator) -> String:
	match String(Cast.member(w).get("weapon", "")):
		"carrot_rocket_launcher":
			return "singed"
		"carrot_sniper":
			return "eye_patch"
	return ["arm_l", "arm_r", "leg_l", "leg_r", "eye_patch"][rng.randi() % 5]


## The paper: the best stories first (the first is the headline), the
## standings, and the rogues' moods (a winning streak makes one cocky, a
## fresh scar makes one wary: Cast.traits_for).
static func edition_of(played: Array, now: float, rng: RandomNumberGenerator) -> Dictionary:
	var stories := []   # [weight, {title, text}, kind]
	var endings := 0    # (the scores settled take turns at SETTLED's endings)
	var wins := {}
	var scarred := {}
	for m in played:
		var where: Array = MAPS[int(m.map)]
		wins[m.winner] = int(wins.get(m.winner, 0)) + 1
		var downs := {}
		for b in m.beats:
			downs[b.winner] = int(downs.get(b.winner, 0)) + 1
			var fields := {"w": b.winner, "l": b.loser, "map": where[1]}
			if b.scar != "":
				scarred[b.loser] = true
				var sn: Array = SCAR_NEWS[b.scar]
				var settled := ""
				if b.paid_back:
					settled = " " + String(SETTLED[endings % SETTLED.size()]).format(fields)
					endings += 1
				stories.append([5.0 if b.paid_back else 4.0, {"title": sn[0] % [b.winner.to_upper(), b.loser.to_upper()],
					"text": String(sn[1]).format(fields) + settled}, "scar:" + String(b.scar).trim_suffix("_l").trim_suffix("_r")])
			elif b.paid_back:
				stories.append([2.5, {"title": "%s PAYS %s BACK" % [b.winner.to_upper(), b.loser.to_upper()],
					"text": "{map}, {w} had a score to settle with {l}, and settled it.".format(fields)}, "settled"])
			elif b.chance < 0.3 and b.left <= 3:
				stories.append([3.0, {"title": "UPSET: %s BEATS %s" % [b.winner.to_upper(), b.loser.to_upper()],
					"text": "Nobody gave {w} a chance against {l} {where}. Nobody told {w}.".format({"w": b.winner, "l": b.loser, "where": where[0]})}, "upset"])
		if int(wins[m.winner]) == 1:
			stories.append([2.0, {"title": "%s WINS %s" % [String(m.winner).to_upper(), String(where[0]).to_upper()],
				"text": "Last critter standing out of %d: %s, with %s on the way." % [m.lobby, m.winner, _count(int(downs.get(m.winner, 0)), "beat-down", "beat-downs")]}, "win"])
	var moods := {}
	for n in wins:
		if int(wins[n]) >= 2:
			moods[n] = "cocky"
			stories.append([3.5, {"title": "%s WINS %d" % [String(n).to_upper(), wins[n]],
				"text": "%s won %d of the %d matches while you were away. Expect it to be cocky." % [n, wins[n], played.size()]}, "streak"])
	for n in scarred:
		if not moods.has(n):
			moods[n] = "wary"
	for n in Cast.names():
		RivalBook.set_mood(n, moods.get(n, ""))
	# the weightiest first, but not six eye patches in a row: each story of a
	# kind already printed counts for less (among equals, the earlier one)
	var printed := []
	var kinds := {}
	while printed.size() < 6 and not stories.is_empty():
		var best := 0
		var best_w := -INF
		for i in stories.size():
			var w := float(stories[i][0]) - 1.5 * int(kinds.get(stories[i][2], 0))
			if w > best_w:
				best_w = w
				best = i
		var s: Array = stories.pop_at(best)
		kinds[s[2]] = int(kinds.get(s[2], 0)) + 1
		printed.append(s[1])
	var standings := wins.keys()
	standings.sort_custom(func(a, b): return int(wins[a]) > int(wins[b]) or (int(wins[a]) == int(wins[b]) and String(a) < String(b)))
	return {"when": now, "matches": played.size(), "stories": printed,
		"standings": standings.slice(0, 5).map(func(n): return [n, int(wins[n])]), "read": false}


## The hottest grudges between rogues: [[holder, against, beat-downs not yet paid back], ...].
static func feuds(count := 4) -> Array:
	var out := []
	for n in Cast.names():
		var g := RivalBook.grudges(n)
		for other in g:
			out.append([n, other, int(g[other])])
	out.sort_custom(func(a, b): return a[2] > b[2] or (a[2] == b[2] and String(a[0]) < String(b[0])))
	return out.slice(0, count)


## Who's after you: your rivals and the rogues you've made radical, the worst first.
static func wanted(count := 4) -> Array:
	var out := []
	for n in Cast.names():
		if RivalBook.is_rival(n) or Cast.heat(n) >= 2:
			out.append(n)
	out.sort_custom(func(a, b): return Cast.heat(a) + (5 if RivalBook.is_rival(a) else 0) > Cast.heat(b) + (5 if RivalBook.is_rival(b) else 0))
	return out.slice(0, count)


static func _count(k: int, one: String, many: String) -> String:
	return "%d %s" % [k, one if k == 1 else many]
