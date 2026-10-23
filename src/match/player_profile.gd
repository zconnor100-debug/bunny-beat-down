class_name PlayerProfile
extends RefCounted
## What the bots have learned about you, kept between runs: where you like
## to land and which guns you win with. The match director (MatchManager)
## uses it so the bots feel like they learn you: more of them drop where you
## always drop, and they fight you at the range your favourite guns hate.
## Automated test runs use their own file, like Settings.

const PATH := "user://profile.cfg"
const TEST_PATH := "user://profile_test.cfg"
## Weapons that want you close, and ones that want you far away.
const CLOSE := [&"carrot_shotgun", &"carrot_smg", &"carrot_pistol", &"melee"]
const FAR := [&"carrot_sniper", &"carrot_rifle"]

static var _cfg: ConfigFile


static func path() -> String:
	return TEST_PATH if Settings.is_test_run() else PATH


static func _book() -> ConfigFile:
	if _cfg == null:
		_cfg = ConfigFile.new()
		_cfg.load(path())
	return _cfg


static func save() -> void:
	_book().save(path())


static func reset_for_tests() -> void:
	assert(Settings.is_test_run())
	_cfg = ConfigFile.new()
	save()


static func note_landing(poi: String) -> void:
	_book().set_value("landings", poi, int(_book().get_value("landings", poi, 0)) + 1)
	save()


static func note_kill(weapon_id: StringName) -> void:
	_book().set_value("kills", String(weapon_id), int(_book().get_value("kills", String(weapon_id), 0)) + 1)
	save()


## The landmark you land at most (at least twice), or "".
static func favourite_landing(on: Array) -> String:
	var best := ""
	var best_n := 1
	if not _book().has_section("landings"):
		return ""
	for poi in _book().get_section_keys("landings"):
		var n := int(_book().get_value("landings", poi, 0))
		if n > best_n and on.has(poi):
			best = poi
			best_n = n
	return best


## "close" if most of your beat-downs come from close-range guns, "far" if
## from long-range ones, "" if there's no clear habit yet (fewer than 4).
static func fighting_style() -> String:
	if not _book().has_section("kills"):
		return ""
	var close := 0
	var far := 0
	var total := 0
	for w in _book().get_section_keys("kills"):
		var n := int(_book().get_value("kills", w, 0))
		total += n
		if StringName(w) in CLOSE:
			close += n
		elif StringName(w) in FAR:
			far += n
	if total < 4:
		return ""
	if close >= total * 0.6:
		return "close"
	if far >= total * 0.6:
		return "far"
	return ""
