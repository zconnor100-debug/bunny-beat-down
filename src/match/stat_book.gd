class_name StatBook
extends RefCounted
## Your trackers, kept between runs with the PlayerProfile. For every carrot
## gun (and the club): beat-downs, carrots fired, hits, headshots, damage and
## the longest beat-down. For every critter you've played as: matches, wins,
## best placing, beat-downs, times beaten, headshots, damage and accuracy.
## Shotgun pellets count one by one; a rocket counts as a hit once, however
## many it catches in its blast. `this_match` holds the current match's
## numbers for the end screen. Only the player is tracked (MatchManager calls in).

const GUNS := [&"carrot_pistol", &"carrot_smg", &"carrot_shotgun", &"carrot_rifle", &"carrot_lmg", &"carrot_sniper",
	&"carrot_rocket_launcher", &"root_rumbler", &"carrot_lobber", &"big_root_50", &"carrot_grenade", &"melee"]   # (your arsenal's too)
const GUN_KEYS := ["kills", "shots", "hits", "heads", "damage", "longest"]
const CRITTER_KEYS := ["matches", "wins", "best", "kills", "deaths", "heads", "damage", "shots", "hits"]

## This match: totals and per gun ({gun id: {kills, shots, ...}}), and who you are.
static var this_match: Dictionary = {}
static var _blast_frame := -1         # (a rocket's blast is one hit, not one per critter)


static func _book() -> ConfigFile:
	return PlayerProfile._book()


static func begin_match(critter_id: StringName, map_id := "") -> void:
	this_match = {"critter": String(critter_id), "map": map_id, "guns": {}, "kills": 0, "shots": 0, "hits": 0, "heads": 0,
		"damage": 0.0, "longest": 0.0, "ended": false}


static func _bump(gun_id: StringName, key: String, by: float) -> void:
	if gun_id == &"":
		gun_id = &"melee"
	var section := "gun:" + String(gun_id)
	if key == "longest":
		_book().set_value(section, key, maxf(float(_book().get_value(section, key, 0.0)), by))
	else:
		_book().set_value(section, key, float(_book().get_value(section, key, 0.0)) + by)
	if this_match.is_empty():
		return
	var g: Dictionary = this_match.guns.get(String(gun_id), {})
	g[key] = maxf(float(g.get(key, 0.0)), by) if key == "longest" else float(g.get(key, 0.0)) + by
	this_match.guns[String(gun_id)] = g
	if key == "longest":
		this_match.longest = maxf(float(this_match.longest), by)
	elif this_match.has(key):
		this_match[key] = float(this_match[key]) + by


## You fired (`pellets` carrots at once) or swung the club.
static func note_shot(gun_id: StringName, pellets := 1) -> void:
	_bump(gun_id, "shots", pellets)


## One of your carrots (or a swing, or a blast) hurt a critter.
static func note_hit(gun_id: StringName, damage: float, headshot: bool, blast := false) -> void:
	_bump(gun_id, "damage", damage)
	if blast:
		if Engine.get_process_frames() == _blast_frame:
			return
		_blast_frame = Engine.get_process_frames()
	_bump(gun_id, "hits", 1)
	if headshot:
		_bump(gun_id, "heads", 1)


## You beat a critter down from `distance` metres.
static func note_kill(gun_id: StringName, distance: float) -> void:
	_bump(gun_id, "kills", 1)
	_bump(gun_id, "longest", distance)


## The match is over for you: placing (1 = won) out of `total`. Saved.
static func end_match(placement: int, total: int, beaten: bool) -> void:
	if this_match.is_empty() or this_match.ended:
		return
	this_match.ended = true
	this_match["placement"] = placement
	var section := "critter:" + String(this_match.critter)
	var b := _book()
	b.set_value(section, "matches", int(b.get_value(section, "matches", 0)) + 1)
	if placement == 1:
		b.set_value(section, "wins", int(b.get_value(section, "wins", 0)) + 1)
		if String(this_match.get("map", "")) != "":
			b.set_value("maps", String(this_match.map), map_wins(String(this_match.map)) + 1)
	var best := int(b.get_value(section, "best", 0))
	b.set_value(section, "best", placement if best == 0 else mini(best, placement))
	if beaten:
		b.set_value(section, "deaths", int(b.get_value(section, "deaths", 0)) + 1)
	for key in ["kills", "heads", "damage", "shots", "hits"]:
		b.set_value(section, key, float(b.get_value(section, key, 0.0)) + float(this_match[key]))
	PlayerProfile.save()


## Matches you've won on a map ("island", "cage", "toybox").
static func map_wins(map_id: String) -> int:
	return int(_book().get_value("maps", map_id, 0))


## A gun's lifetime numbers ({kills, shots, hits, heads, damage, longest}).
static func gun(gun_id: StringName) -> Dictionary:
	var out := {}
	for key in GUN_KEYS:
		out[key] = float(_book().get_value("gun:" + String(gun_id), key, 0.0))
	return out


## A critter's lifetime numbers ({matches, wins, best, kills, deaths, ...}).
static func critter(critter_id: StringName) -> Dictionary:
	var out := {}
	for key in CRITTER_KEYS:
		out[key] = float(_book().get_value("critter:" + String(critter_id), key, 0.0))
	return out


## Hits per carrot (0..1), or -1 before the first shot.
static func accuracy(d: Dictionary) -> float:
	var shots := float(d.get("shots", 0.0))
	return clampf(float(d.get("hits", 0.0)) / shots, 0.0, 1.0) if shots > 0.0 else -1.0


static func percent(d: Dictionary) -> String:
	var a := accuracy(d)
	return "—" if a < 0.0 else "%d%%" % roundi(a * 100.0)


static func gun_name(gun_id: StringName) -> String:
	if gun_id == &"melee":
		return "Club"
	var w := WeaponDB.get_weapon(gun_id)
	return w.display_name if w else String(gun_id)


## The end screen's line for this match.
static func match_line() -> String:
	if this_match.is_empty():
		return ""
	var best_gun := ""
	var best_kills := 0.0
	for id in this_match.guns:
		var k := float(this_match.guns[id].get("kills", 0.0))
		if k > best_kills:
			best_kills = k
			best_gun = id
	var parts := ["Accuracy %s" % percent(this_match), "Headshots %d" % int(this_match.heads),
		"Damage %d" % int(this_match.damage)]
	if float(this_match.longest) > 0.0:
		parts.append("Longest beat-down %d m" % roundi(float(this_match.longest)))
	if best_gun != "":
		parts.append("Best gun: %s (%d)" % [gun_name(StringName(best_gun)), int(best_kills)])
	return "   •   ".join(parts)
