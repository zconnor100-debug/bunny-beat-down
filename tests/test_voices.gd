extends TestCase
## The rogues' voices (RogueVoice, tools/voices): every rogue can say every
## line it can be given (each in its own file, with every name it can call
## you, every rival's name and every score), out loud from where it stands,
## one line at a time, on the Voice bus.


func test_every_rogue_can_say_every_line() -> void:
	var bank: Dictionary = RogueVoice._load()
	check(bank.get("rogues", {}).size() == Cast.names().size(), "a voice for every rogue (%d of %d)" % [bank.get("rogues", {}).size(), Cast.names().size()])
	var yous := ["Bun", "Bandit Bunny", "Squirrel", "Fox", "Raccoon", "Frog", "Beaver", "Hamster"]
	var gaps := []
	for n in Cast.names():
		var voice := RivalBook.personality_of(n)
		var keys := ["says", "hunt"]
		for event in ["spot", "kill", "lose"]:
			for i in RivalBook.PERSONALITIES[voice][event].size():
				keys.append("p.%s.%s.%d" % [voice, event, i])
		for t in range(1, Cast.HEAT_LINES.size()):
			for event in Cast.HEAT_LINES[t]:
				for i in Cast.HEAT_LINES[t][event].size():
					keys.append("h.%d.%s.%d" % [t, event, i])
		for piece in Cast.OUTFIT_LINES:
			for event in Cast.OUTFIT_LINES[piece]:
				for i in Cast.OUTFIT_LINES[piece][event].size():
					keys.append("o.%s.%s.%d" % [piece, event, i])
		for i in Cast.FEUD_LINES.size():
			keys.append("f.%d" % i)
		for i in Cast.DIRECTOR_LINES.size():
			keys.append("d.%d" % i)
		for prefix in Cast.GANG_LINES:
			for i in Cast.GANG_LINES[prefix].size():
				keys.append("%s.%d" % [prefix, i])
		for i in Cast.FLARE_LINES.size():
			keys.append("fl.%d" % i)
		for prefix in Cast.BOSS_LINES:
			for i in Cast.BOSS_LINES[prefix].size():
				keys.append("%s.%d" % [prefix, i])
		for id in Cast.BOSS_NAME_LINES:
			keys.append("bn.%s" % id)
		keys.append("bk")
		for key in keys:
			var fields := {"you": yous[key.hash() % yous.size()], "k": key.length() % 7, "w": 61,
				"them": Cast.names()[(Cast.names().find(n) + 1) % Cast.names().size()]}
			for m in RogueVoice.missing(n, key, fields):
				gaps.append("%s/%s: %s" % [n, key, m])
	check(gaps.is_empty(), "%d lines can't be said: %s" % [gaps.size(), ", ".join(gaps.slice(0, 8))])
	for you in yous:
		check(RogueVoice.missing("Sly", "h.1.spot.1", {"you": you}).is_empty(), "Sly can call you %s" % you)


func test_a_rogue_says_it_from_where_it_stands() -> void:
	make_arena()
	var c := spawn_critter("res://data/critters/squirrel.tres", Vector3.ZERO)
	c.display_name = "Nutsy"
	await wait_physics(2)
	var said := Cast.say("says", String(Cast.member("Nutsy").says))
	var v := RogueVoice.speak(c, said)
	check(v != null and v.get_parent() == c.visual and v.bus == &"Voice", "Nutsy speaks from Nutsy, on the Voice bus")
	check(not v._parts.is_empty() and v.stream != null, "its line, from its own file")
	var again := RogueVoice.speak(c, RivalBook.line_say("Nutsy", "spot", "Bun"))
	await wait_frames(1)
	check(again != null and not is_instance_valid(v) or v.is_queued_for_deletion(), "a new line cuts off the last one")
	var nobody := spawn_critter("res://data/critters/squirrel.tres", Vector3(3, 0, 0))
	nobody.display_name = "Squirrel 7"
	check(RogueVoice.speak(nobody, said) == null, "a critter that isn't a rogue says nothing")
	check(AudioServer.get_bus_index(&"Voice") >= 0, "the Voice bus exists (its volume: Settings voice_volume)")


func test_a_taunt_carries_across_the_field_over_the_gunfire() -> void:
	make_arena()
	var c := spawn_critter("res://data/critters/squirrel.tres", Vector3.ZERO)
	c.display_name = "Nutsy"
	await wait_physics(2)
	var v := RogueVoice.speak(c, Cast.say("says", String(Cast.member("Nutsy").says)))
	check(v != null, "Nutsy speaks")
	# inverse-distance falloff: how much quieter it is 40 m off, against a shot there
	var at40 := linear_to_db(v.unit_size / 40.0) + v.volume_db
	var shot40 := linear_to_db(6.0 / 40.0)
	check(at40 > -3.0 and at40 > shot40 + 10.0, "40 m off a taunt is still loud (%.1f dB, a shot %.1f dB)" % [at40, shot40])
	check(v.max_distance >= 140.0 and v.attenuation_filter_cutoff_hz >= 10000.0, "and heard, not mumbled, as far as the gunfire carries")
	var voice := AudioServer.get_bus_index(&"Voice")
	var limited := false
	for i in AudioServer.get_bus_effect_count(voice):
		limited = limited or AudioServer.get_bus_effect(voice, i) is AudioEffectHardLimiter
	check(limited, "played hot, the Voice bus limits its peaks")
	var sfx := AudioServer.get_bus_index(&"SFX")
	var ducks := false
	for i in AudioServer.get_bus_effect_count(sfx):
		var e := AudioServer.get_bus_effect(sfx, i)
		ducks = ducks or (e is AudioEffectCompressor and (e as AudioEffectCompressor).sidechain == &"Voice")
	check(ducks, "the sound effects dip under a rogue talking")
	v.stop()
	v.queue_free()
	await wait_frames(2)


func test_lines_added_later_play_from_their_own_file() -> void:
	# (build_voices_maya.py --new-lines speaks new lines into a file beside the rogue's: <rogue>_2.ogg)
	var nutsy: Dictionary = RogueVoice._load().rogues["Nutsy"]
	var was: Dictionary = nutsy.clips
	nutsy.clips = was.duplicate()
	nutsy.clips["says"] = [0.0, 0.4, "rocco.ogg"]
	make_arena()
	var c := spawn_critter("res://data/critters/squirrel.tres", Vector3.ZERO)
	c.display_name = "Nutsy"
	await wait_physics(2)
	var v := RogueVoice.speak(c, Cast.say("says", String(Cast.member("Nutsy").says)))
	check(v != null and v._parts[0][2] == "rocco.ogg" and v.stream == RogueVoice._stream("rocco.ogg"), "a clip comes from the file it was added in")
	var voice := RivalBook.personality_of("Nutsy")
	var key := "p.%s.spot.0" % voice
	var line := Cast.say(key, RivalBook.PERSONALITIES[voice].spot[0], {"you": "Bun", "k": 1, "w": 2})
	check(not RogueVoice.plan("Nutsy", key, line.fields).is_empty() and RogueVoice.plan("Nutsy", key, line.fields)[0][2] == "nutsy.ogg",
		"the rest from the rogue's own file")
	check(not RogueVoice.plan("Nutsy", key, {"you": "Mister Nobody", "k": 1, "w": 2}).is_empty(), "a name it can't say is left out of the line")
	var words: Array = RogueVoice.steps("Nutsy", key, line.fields).filter(func(s): return s is String and not s.contains(":"))
	nutsy.clips.erase(words[0])
	check(RogueVoice.plan("Nutsy", key, line.fields).is_empty(), "but a line whose words it wasn't given yet isn't said (only shown)")
	nutsy.clips = was
	v.queue_free()
	await wait_frames(2)
