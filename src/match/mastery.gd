class_name Mastery
extends RefCounted
## Milestones: goals read off your trackers (StatBook), the cast's book
## (RivalBook) and your runs (Run), each unlocking something for good when
## you reach it. Checked as you play (MatchManager, after a beat-down and at
## the end of a match) and shown in the Trophy Room with your progress.
##
## Then the long haul, LADDERS: the same goal again and again, harder each
## time (25, 50, then 100 beat-downs with each gun; bigger numbers for the
## totals), each tier a milestone of its own.
##
## Adding one is adding a row to MILESTONES: `stat` is what it counts (see
## progress(): "kills", "heads", "gun_kills:<gun id>", "gun_heads:<gun id>",
## "wins", "map_wins:<map id>", "matches", "critters_played", "cast_beaten",
## "max_heat", "signatures", "nemeses_beaten", "runs_done", "run_stops",
## "boons_at_once", "gang_beaten", "doppels_beaten", "kernel_done:<mission id>",
## "kernel_all_home" (the prologue), "kernel_all_home:<mission id>"), `need` how many, and
## `reward` what it gives:
##   {"acorns": n}                      once, when it's reached
##   {"look": "category:id"}            a Workshop look, free
##   {"mutation": "<gun id>", "kind": Boons.gun_mutation kind}   that gun's carrots, in your paws
##   {"blast": scale}                   your rockets' blast radius
##   {"club": scale}                    your club's damage
##   {"run_helmets": n} / {"run_rewinds": n}   more of them on every run
##   {"draft": n}                       boon drafts offer this many
## A new stat needs a line in progress(); a new reward kind, a line where it acts.

const MILESTONES := [
	{"id": "first_carrot", "name": "First Carrot", "text": "Beat down a critter.", "stat": "kills", "need": 1,
		"reward": {"acorns": 25}, "gives": "25 acorns"},
	{"id": "trick_shot", "name": "Trick Shot", "text": "Beat down 15 critters with the Carrot Pistol.", "stat": "gun_kills:carrot_pistol", "need": 15,
		"reward": {"mutation": "carrot_pistol", "kind": "bouncy"}, "gives": "your pistol's carrots bounce"},
	{"id": "popcorn", "name": "Popcorn", "text": "Beat down 25 critters with the Carrot SMG.", "stat": "gun_kills:carrot_smg", "need": 25,
		"reward": {"mutation": "carrot_smg", "kind": "popping"}, "gives": "your SMG's carrots pop"},
	{"id": "bell_ringer", "name": "Bell Ringer", "text": "Beat down 20 critters with the Carrot Shotgun.", "stat": "gun_kills:carrot_shotgun", "need": 20,
		"reward": {"mutation": "carrot_shotgun", "kind": "splitting"}, "gives": "your shotgun's pellets split"},
	{"id": "marksbunny", "name": "Marksbunny", "text": "Beat down 20 critters with the Carrot Assault Rifle.", "stat": "gun_kills:carrot_rifle", "need": 20,
		"reward": {"mutation": "carrot_rifle", "kind": "piercing"}, "gives": "your rifle's carrots pierce"},
	{"id": "hopper_feeder", "name": "Hopper Feeder", "text": "Beat down 25 critters with the Carrot LMG.", "stat": "gun_kills:carrot_lmg", "need": 25,
		"reward": {"mutation": "carrot_lmg", "kind": "bouncy"}, "gives": "your LMG's carrots bounce"},
	{"id": "long_carrot", "name": "The Long Carrot", "text": "Land 10 headshots with the sniper.", "stat": "gun_heads:carrot_sniper", "need": 10,
		"reward": {"mutation": "carrot_sniper", "kind": "piercing"}, "gives": "your sniper's carrots pierce"},
	{"id": "big_bang", "name": "Big Bang", "text": "Beat down 10 critters with the Rocket Launcher.", "stat": "gun_kills:carrot_rocket_launcher", "need": 10,
		"reward": {"blast": 1.3}, "gives": "your rockets' blasts are 30% wider"},
	{"id": "bonk_master", "name": "Bonk Master", "text": "Beat down 10 critters with your club.", "stat": "gun_kills:melee", "need": 10,
		"reward": {"club": 1.25}, "gives": "your club hits 25% harder"},
	{"id": "headhunter", "name": "Headhunter", "text": "Land 50 headshots.", "stat": "heads", "need": 50,
		"reward": {"look": "reticle_color:gold"}, "gives": "the gold reticle"},
	{"id": "winner", "name": "Winner Winner", "text": "Win a match.", "stat": "wins", "need": 1,
		"reward": {"look": "skin:gilded"}, "gives": "the Gilded gun skin"},
	{"id": "shape_shifter", "name": "Shape-Shifter", "text": "Play matches as 4 different critters.", "stat": "critters_played", "need": 4,
		"reward": {"acorns": 75}, "gives": "75 acorns"},
	{"id": "rogue_collector", "name": "Rogue Collector", "text": "Beat down 15 different bots from the cast.", "stat": "cast_beaten", "need": 15,
		"reward": {"acorns": 150}, "gives": "150 acorns"},
	{"id": "arch_enemy", "name": "Arch-Enemy", "text": "Make a bot your Nemesis.", "stat": "max_heat", "need": 4,
		"reward": {"look": "flash:rainbow"}, "gives": "the rainbow muzzle flash"},
	{"id": "trophy_hunter", "name": "Trophy Hunter", "text": "Win a nemesis hunt.", "stat": "signatures", "need": 1,
		"reward": {"acorns": 200}, "gives": "200 acorns"},
	{"id": "green_thumb", "name": "Green Thumb", "text": "Hold 6 boons at once.", "stat": "boons_at_once", "need": 6,
		"reward": {"draft": 4}, "gives": "boon drafts offer four"},
	{"id": "halfway_there", "name": "Halfway There", "text": "Clear 3 stops of a run.", "stat": "run_stops", "need": 3,
		"reward": {"run_rewinds": 1}, "gives": "a fourth rewind on every run"},
	{"id": "trailblazer", "name": "Trailblazer", "text": "Finish a run.", "stat": "runs_done", "need": 1,
		"reward": {"run_helmets": 1}, "gives": "a fourth acorn helmet on every run"},
	# wardrobe pieces you can't buy (Workshop: cost -1)
	{"id": "top_of_class", "name": "Top of the Class", "text": "Win 3 matches.", "stat": "wins", "need": 3,
		"reward": {"look": "wear_hat:grad_cap"}, "gives": "the mortarboard"},
	{"id": "court_jester", "name": "Court Jester", "text": "Beat down 30 different bots from the cast.", "stat": "cast_beaten", "need": 30,
		"reward": {"look": "wear_hat:jester_hat"}, "gives": "the jester's cap"},
	{"id": "star_shooter", "name": "Star Shooter", "text": "Land 25 headshots with the sniper.", "stat": "gun_heads:carrot_sniper", "need": 25,
		"reward": {"look": "wear_face:star_glasses"}, "gives": "the star glasses"},
	{"id": "fairy_tale", "name": "Fairy Tale", "text": "Finish 3 runs.", "stat": "runs_done", "need": 3,
		"reward": {"look": "wear_back:fairy_wings"}, "gives": "the fairy wings"},
	{"id": "dark_horse", "name": "Dark Horse", "text": "Win 2 nemesis hunts.", "stat": "signatures", "need": 2,
		"reward": {"look": "wear_back:dark_wings"}, "gives": "the dark wings"},
	# a piece for winning on each map, and one for beating your nemesis
	{"id": "island_hopper", "name": "Island Hopper", "text": "Win a match on Wildwood Island.", "stat": "map_wins:island", "need": 1,
		"reward": {"look": "wear_face:snorkel_mask"}, "gives": "the snorkel mask"},
	{"id": "big_cheese", "name": "The Big Cheese", "text": "Win a match in the Hamster Cage.", "stat": "map_wins:cage", "need": 1,
		"reward": {"look": "wear_hat:cheese_hat"}, "gives": "the cheese hat"},
	{"id": "wound_up", "name": "All Wound Up", "text": "Win a match in Toy Box Bash.", "stat": "map_wins:toybox", "need": 1,
		"reward": {"look": "wear_back:windup_key"}, "gives": "the wind-up key"},
	{"id": "laurels", "name": "Resting on Your Laurels", "text": "Beat down your Nemesis.", "stat": "nemeses_beaten", "need": 1,
		"reward": {"look": "wear_hat:laurel_wreath"}, "gives": "the laurel wreath"},
	{"id": "full_house", "name": "Full House", "text": "Beat down every one of the 49 rogues in the cast.", "stat": "cast_beaten", "need": 49,
		"reward": {"acorns": 500}, "gives": "500 acorns"},
	# the bosses (Boss Battles: on the Trophy Room's Bosses page, `boss`): a piece
	# of each one to keep, and harder ways to beat them
	{"id": "giant_slayer", "name": "Giant Slayer", "text": "Beat Brutus, the Meadow's Nightmare.", "stat": "boss_wins:brute", "need": 1,
		"reward": {"look": "coat:brutus"}, "gives": "the Brutus coat", "boss": "brute"},
	{"id": "unwound", "name": "Unwound", "text": "Beat the Tin Tyrant, the Wind-Up Warlord.", "stat": "boss_wins:robot", "need": 1,
		"reward": {"look": "skin:tin_tyrant"}, "gives": "the Tin Tyrant gun skin", "boss": "robot"},
	{"id": "pest_control", "name": "Pest Control", "text": "Beat Nibbles the Rabid.", "stat": "boss_wins:hamster", "need": 1,
		"reward": {"look": "kill_fx:froth"}, "gives": "the Rabid froth beat-down burst", "boss": "hamster"},
	{"id": "big_three", "name": "The Big Three", "text": "Beat all three bosses.", "stat": "bosses_beaten", "need": 3,
		"reward": {"acorns": 300}, "gives": "300 acorns", "boss": "*"},
	{"id": "still_standing", "name": "Still Standing", "text": "Beat a boss without being beaten down yourself.", "stat": "boss_standing",
		"need": 1, "reward": {"acorns": 150}, "gives": "150 acorns", "boss": "*"},
	{"id": "hard_nut", "name": "A Hard Nut", "text": "Beat a boss on Hard.", "stat": "boss_hard", "need": 1,
		"reward": {"acorns": 250}, "gives": "250 acorns", "boss": "*"},
	# the Kernel Hunt (KernelHunt): its prologue held, and held well
	{"id": "days_since_brutus", "name": "Days Since Brutus: 0", "text": "Hold the Big Red Barn in the Kernel Hunt's prologue.",
		"stat": "kernel_done:prologue", "need": 1, "reward": {"look": "coat:touched"}, "gives": "the Touched coat"},
	{"id": "every_ranger_home", "name": "Every Ranger Home", "text": "Hold the Barn with all seven Barn Rangers still standing.",
		"stat": "kernel_all_home", "need": 1, "reward": {"acorns": 250}, "gives": "250 acorns"},
	# its Act I (PatchMission): Brutus back to Little Bru, and nobody lost doing it
	{"id": "the_first_kernel", "name": "The First Kernel", "text": "Beat Brutus in the Kernel Hunt's Act I, The Carrot Patch.",
		"stat": "kernel_done:carrot_patch", "need": 1, "reward": {"look": "kill_fx:embers"}, "gives": "the Patch fire beat-down burst"},
	{"id": "nobody_singed", "name": "Nobody Singed", "text": "Finish Act I with all seven Barn Rangers still standing.",
		"stat": "kernel_all_home:carrot_patch", "need": 1, "reward": {"acorns": 300}, "gives": "300 acorns"},
	# its Act II (ClockworkMission): the Tin Tyrant back to Model No. 7, and nobody lost doing it
	{"id": "the_second_kernel", "name": "The Second Kernel", "text": "Beat the Tin Tyrant in the Kernel Hunt's Act II, The Clockwork Decree.",
		"stat": "kernel_done:clockwork_decree", "need": 1, "reward": {"look": "kill_fx:cogs"}, "gives": "the Clockwork beat-down burst"},
	{"id": "nobody_left_wound", "name": "Nobody Left Wound", "text": "Finish Act II with all seven Barn Rangers still standing.",
		"stat": "kernel_all_home:clockwork_decree", "need": 1, "reward": {"acorns": 300}, "gives": "300 acorns"},
]

## The ladders: `text` has a %d for a tier's need, and each tier is [need,
## reward, what it gives]. A tier is a milestone like any other (all(): id
## "<ladder>_<need>", named "<ladder> I", "II", "III"); the Trophy Room's
## Ladders page shows a ladder on one row, at the tier you're climbing. The top
## of each gun's ladder is a gun skin made for it, earned only.
const LADDERS := [
	{"id": "pistolero", "name": "Pistolero", "text": "Beat down %d critters with the Carrot Pistol.", "stat": "gun_kills:carrot_pistol",
		"tiers": [[25, {"acorns": 50}, "50 acorns"], [50, {"acorns": 100}, "100 acorns"], [100, {"look": "skin:ruby"}, "the Ruby gun skin"]]},
	{"id": "spray_and_pray", "name": "Spray and Pray", "text": "Beat down %d critters with the Carrot SMG.", "stat": "gun_kills:carrot_smg",
		"tiers": [[25, {"acorns": 50}, "50 acorns"], [50, {"acorns": 100}, "100 acorns"], [100, {"look": "skin:toxic"}, "the Toxic stripe gun skin"]]},
	{"id": "boomstick", "name": "Boomstick", "text": "Beat down %d critters with the Carrot Shotgun.", "stat": "gun_kills:carrot_shotgun",
		"tiers": [[25, {"acorns": 50}, "50 acorns"], [50, {"acorns": 100}, "100 acorns"], [100, {"look": "skin:ember"}, "the Ember gun skin"]]},
	{"id": "rifleman", "name": "Rifleman", "text": "Beat down %d critters with the Carrot Assault Rifle.", "stat": "gun_kills:carrot_rifle",
		"tiers": [[25, {"acorns": 50}, "50 acorns"], [50, {"acorns": 100}, "100 acorns"], [100, {"look": "skin:jade"}, "the Jade gun skin"]]},
	{"id": "carrot_hose", "name": "The Carrot Hose", "text": "Beat down %d critters with the Carrot LMG.", "stat": "gun_kills:carrot_lmg",
		"tiers": [[25, {"acorns": 50}, "50 acorns"], [50, {"acorns": 100}, "100 acorns"], [100, {"look": "skin:obsidian"}, "the Obsidian gun skin"]]},
	{"id": "long_shot", "name": "Long Shot", "text": "Beat down %d critters with the sniper.", "stat": "gun_kills:carrot_sniper",
		"tiers": [[25, {"acorns": 50}, "50 acorns"], [50, {"acorns": 100}, "100 acorns"], [100, {"look": "skin:pearl"}, "the Pearl gun skin"]]},
	{"id": "kaboom", "name": "Ka-BOOM", "text": "Beat down %d critters with the Rocket Launcher.", "stat": "gun_kills:carrot_rocket_launcher",
		"tiers": [[25, {"acorns": 50}, "50 acorns"], [50, {"acorns": 100}, "100 acorns"], [100, {"look": "skin:royal"}, "the Royal gun skin"]]},
	{"id": "big_bonker", "name": "Big Bonker", "text": "Beat down %d critters with your club.", "stat": "gun_kills:melee",
		"tiers": [[25, {"acorns": 50}, "50 acorns"], [50, {"acorns": 100}, "100 acorns"], [100, {"look": "skin:zebra"}, "the Zebra stripe gun skin"]]},
	{"id": "grenadier", "name": "Grenadier", "text": "Beat down %d critters with carrot grenades.", "stat": "gun_kills:carrot_grenade",
		"tiers": [[25, {"acorns": 50}, "50 acorns"], [50, {"acorns": 100}, "100 acorns"], [100, {"look": "kill_fx:fireworks"}, "the Fireworks beat-down burst"]]},
	{"id": "rumble_on", "name": "Rumble On", "text": "Beat down %d critters with the Root Rumbler.", "stat": "gun_kills:root_rumbler",
		"tiers": [[25, {"acorns": 50}, "50 acorns"], [50, {"acorns": 100}, "100 acorns"], [100, {"look": "skin:carrot_king"}, "the Carrot King gun skin"]]},
	{"id": "lob_star", "name": "Lob Star", "text": "Beat down %d critters with the Carrot Lobber.", "stat": "gun_kills:carrot_lobber",
		"tiers": [[25, {"acorns": 50}, "50 acorns"], [50, {"acorns": 100}, "100 acorns"], [100, {"look": "skin:sapphire"}, "the Sapphire gun skin"]]},
	{"id": "big_game", "name": "Big Game", "text": "Beat down %d critters with the Big Root .50.", "stat": "gun_kills:big_root_50",
		"tiers": [[25, {"acorns": 50}, "50 acorns"], [50, {"acorns": 100}, "100 acorns"], [100, {"look": "skin:diamond"}, "the Diamond gun skin"]]},
	# the totals
	{"id": "carrot_crusher", "name": "Carrot Crusher", "text": "Beat down %d critters.", "stat": "kills",
		"tiers": [[100, {"acorns": 150}, "150 acorns"], [250, {"acorns": 300}, "300 acorns"], [500, {"look": "kill_fx:gold_rush"}, "the Gold rush beat-down burst"]]},
	{"id": "noggin_knocker", "name": "Noggin Knocker", "text": "Land %d headshots.", "stat": "heads",
		"tiers": [[100, {"acorns": 150}, "150 acorns"], [250, {"look": "reticle_color:ruby"}, "the Ruby reticle"], [500, {"look": "tracer:ruby"}, "Ruby tracers"]]},
	{"id": "champion", "name": "Champion", "text": "Win %d matches.", "stat": "wins",
		"tiers": [[10, {"acorns": 200}, "200 acorns"], [25, {"acorns": 400, "look": "flash:gold"}, "400 acorns and the Gold muzzle flash"],
			[50, {"look": "coat:golden_acorn"}, "the Golden Acorn coat"]]},
	{"id": "old_hand", "name": "Old Hand", "text": "Play %d matches.", "stat": "matches",
		"tiers": [[25, {"acorns": 100}, "100 acorns"], [50, {"acorns": 200, "look": "tracer:jade"}, "200 acorns and Jade tracers"],
			[100, {"look": "coat:patchwork"}, "the Patchwork coat"]]},
	{"id": "trail_boss", "name": "Trail Boss", "text": "Finish %d runs.", "stat": "runs_done",
		"tiers": [[5, {"acorns": 250}, "250 acorns"], [10, {"acorns": 500}, "500 acorns"],
			[25, {"acorns": 1000, "look": "coat:starry_night"}, "1,000 acorns and the Starry Night coat"]]},
	{"id": "nemesis_hunter", "name": "Nemesis Hunter", "text": "Beat down a Nemesis %d times.", "stat": "nemeses_beaten",
		"tiers": [[5, {"acorns": 150}, "150 acorns"], [10, {"acorns": 300, "look": "skin:nemesis"}, "300 acorns and the Nemesis gun skin"],
			[25, {"acorns": 600, "look": "coat:smouldering"}, "600 acorns and the Smouldering coat"]]},
	{"id": "pack_breaker", "name": "Pack Breaker", "text": "Beat down %d gang members.", "stat": "gang_beaten",
		"tiers": [[25, {"acorns": 100}, "100 acorns"], [50, {"acorns": 200}, "200 acorns"],
			[100, {"acorns": 400, "look": "coat:tiger_stripe"}, "400 acorns and the Tiger Stripe coat"]]},
	{"id": "mirror_mirror", "name": "Mirror, Mirror", "text": "Beat your Doppelbunny in %d Mirror Matches.", "stat": "doppels_beaten",
		"tiers": [[3, {"acorns": 150}, "150 acorns"], [5, {"look": "skin:looking_glass"}, "the Looking Glass gun skin"],
			[10, {"look": "coat:mended_mirror"}, "the Mended Mirror coat"]]},
	# the bosses' (the Bosses page): the top of each in the Starfall Acorn's glow
	{"id": "giant_killer", "name": "Giant Killer", "text": "Beat %d bosses.", "stat": "boss_wins", "boss": "*",
		"tiers": [[5, {"acorns": 250}, "250 acorns"], [10, {"acorns": 500}, "500 acorns"],
			[25, {"acorns": 1000, "look": "tracer:kernel"}, "1,000 acorns and Starfall tracers"]]},
	{"id": "last_blow", "name": "The Last Blow", "text": "Land the last blow on a boss %d times.", "stat": "boss_last_blows", "boss": "*",
		"tiers": [[2, {"acorns": 100}, "100 acorns"], [5, {"acorns": 250}, "250 acorns"],
			[10, {"acorns": 500, "look": "flash:kernel"}, "500 acorns and the Starfall muzzle flash"]]},
	{"id": "titan_tenderizer", "name": "Titan Tenderizer", "text": "Deal %d damage to bosses.", "stat": "boss_damage", "boss": "*",
		"tiers": [[25000, {"acorns": 150}, "150 acorns"], [50000, {"acorns": 300}, "300 acorns"],
			[100000, {"acorns": 600, "look": "reticle_color:kernel"}, "600 acorns and the Starfall reticle"]]},
]
const TIER_NAMES := ["I", "II", "III", "IV", "V"]

static var _all: Array = []


## Every milestone: MILESTONES, then each ladder's tiers.
static func all() -> Array:
	if _all.is_empty():
		_all = MILESTONES.duplicate()
		for l in LADDERS:
			for i in l.tiers.size():
				var t: Array = l.tiers[i]
				var m := {"id": "%s_%d" % [l.id, int(t[0])], "name": "%s %s" % [l.name, TIER_NAMES[i]], "text": String(l.text).replace("%d", grouped(int(t[0]))),
					"stat": l.stat, "need": int(t[0]), "reward": t[1], "gives": t[2], "ladder": l.id, "tier": i}
				if l.has("boss"):
					m["boss"] = l.boss
				_all.append(m)
	return _all


static func _book() -> ConfigFile:
	return PlayerProfile._book()


static func milestone(id: String) -> Dictionary:
	for m in all():
		if m.id == id:
			return m
	return {}


static func has(id: String) -> bool:
	return _book().get_value("mastery", id, false)


## Where you are on a stat (see MILESTONES).
static func progress(stat: String) -> int:
	if stat.begins_with("gun_kills:"):
		return int(StatBook.gun(StringName(stat.get_slice(":", 1))).kills)
	if stat.begins_with("gun_heads:"):
		return int(StatBook.gun(StringName(stat.get_slice(":", 1))).heads)
	if stat.begins_with("map_wins:"):
		return StatBook.map_wins(stat.get_slice(":", 1))
	if stat.begins_with("boss_wins:"):
		return int(StatBook.boss(stat.get_slice(":", 1)).beaten)
	if stat.begins_with("kernel_done:"):
		return 1 if KernelHunt.done(stat.get_slice(":", 1)) else 0
	if stat.begins_with("kernel_all_home:"):
		return 1 if int(KernelHunt.best(stat.get_slice(":", 1)).get("rangers", 0)) >= KernelHunt.RANGERS.size() else 0
	match stat:
		"boss_wins":
			return int(StatBook.boss_total("beaten"))
		"bosses_beaten":
			return BossLore.IDS.filter(func(id): return StatBook.boss(id).beaten > 0.0).size()
		"boss_standing":
			return int(StatBook.boss_total("standing"))
		"boss_hard":
			return int(StatBook.boss_total("hard"))
		"boss_last_blows":
			return int(StatBook.boss_total("last_blows"))
		"boss_damage":
			return int(StatBook.boss_total("damage"))
		"kills", "heads":
			var n := 0.0
			for g in StatBook.GUNS:
				n += float(StatBook.gun(g)[stat])
			return int(n)
		"wins":
			return _critters().reduce(func(a, c): return a + int(StatBook.critter(c).wins), 0)
		"critters_played":
			return _critters().filter(func(c): return StatBook.critter(c).matches > 0.0).size()
		"cast_beaten":
			return Cast.names().filter(func(n): return RivalBook.your_kills(n) > 0).size()
		"max_heat":
			return Cast.names().reduce(func(a, n): return maxi(a, Cast.heat(n)), 0)
		"signatures":
			return RivalBook.signatures().size()
		"runs_done":
			return Run.record("completed")
		"run_stops":
			return Run.record("best_row")
		"boons_at_once":
			return int(_book().get_value("mastery_stats", "boons_at_once", 0))
		"nemeses_beaten":
			return int(_book().get_value("mastery_stats", "nemeses_beaten", 0))
		"matches":
			return _critters().reduce(func(a, c): return a + int(StatBook.critter(c).matches), 0)
		"gang_beaten":
			return int(_book().get_value("mastery_stats", "gang_beaten", 0))
		"doppels_beaten":
			return DoppelData.mirror("beaten")
		"kernel_all_home":
			return 1 if int(KernelHunt.best("prologue").get("rangers", 0)) >= KernelHunt.RANGERS.size() else 0
	return 0


static func _critters() -> Array:
	return TrophyPanel.CRITTERS


## You beat down a bot that was your Nemesis (for Resting on Your Laurels).
static func note_nemesis_beaten() -> void:
	_book().set_value("mastery_stats", "nemeses_beaten", int(_book().get_value("mastery_stats", "nemeses_beaten", 0)) + 1)


## You beat down a gang member (for Pack Breaker).
static func note_gang_beaten() -> void:
	_book().set_value("mastery_stats", "gang_beaten", int(_book().get_value("mastery_stats", "gang_beaten", 0)) + 1)


## How many boons you've held at once (for Green Thumb).
static func note_boons(n: int) -> void:
	if n > int(_book().get_value("mastery_stats", "boons_at_once", 0)):
		_book().set_value("mastery_stats", "boons_at_once", n)


## Check every milestone: the ones newly reached are marked (and their
## one-time rewards given). Returns them, for the game to announce. A look
## that's since moved to a tier you'd already reached is yours too.
static func check() -> Array:
	var fresh := []
	var owned: Array = (_book().get_value("workshop", "owned", []) as Array).duplicate()
	var looks := owned.size()
	for m in all():
		var r: Dictionary = m.reward
		if has(m.id):
			if r.has("look") and not owned.has(r.look):
				owned.append(r.look)
			continue
		if progress(m.stat) < int(m.need):
			continue
		_book().set_value("mastery", m.id, true)
		if r.has("acorns"):
			Burrow.add_acorns(int(r.acorns))
		if r.has("look") and not owned.has(r.look):
			owned.append(r.look)
		fresh.append(m)
	if owned.size() > looks:
		_book().set_value("workshop", "owned", owned)
	if not fresh.is_empty() or owned.size() > looks:
		PlayerProfile.save()
	return fresh


# ---- the rewards, where they act ---------------------------------------------------------------

## A mastered gun's mutation, for your carrots (Projectiles.mutations_for).
## The milestone that gives a Workshop look ("category:id"), or {}.
static func giving(look: String) -> Dictionary:
	for m in all():
		if m.reward.get("look", "") == look:
			return m
	return {}


static func gun_mutation(gun_id: StringName) -> Dictionary:
	for m in all():
		if m.reward.get("mutation", "") == String(gun_id) and has(m.id):
			return Boons.gun_mutation(m.reward.kind)
	return {}


static func _reward(key: String, default: float) -> float:
	for m in all():
		if m.reward.has(key) and has(m.id):
			return float(m.reward[key])
	return default


static func blast_scale() -> float:
	return _reward("blast", 1.0)


static func club_scale() -> float:
	return _reward("club", 1.0)


static func run_helmets() -> int:
	return int(_reward("run_helmets", 0.0))


static func run_rewinds() -> int:
	return int(_reward("run_rewinds", 0.0))


static func draft_size() -> int:
	return int(_reward("draft", 3.0))


## [name, what it takes, progress "12 / 20", what it gives, reached] for each
## milestone (not the ladders'; the bosses' with `bosses`: a boss's id, or
## "*" for the ones about every boss).
static func rows(bosses := "") -> Array:
	return MILESTONES.filter(func(m): return String(m.get("boss", "")) == bosses).map(func(m):
		return [m.name, m.text, "%s / %s" % [grouped(mini(progress(m.stat), int(m.need))), grouped(int(m.need))], m.gives, has(m.id)])


## A count with its thousands set apart ("25,000").
static func grouped(n: int) -> String:
	var digits := str(absi(n))
	var out := ""
	while digits.length() > 3:
		out = "," + digits.substr(digits.length() - 3) + out
		digits = digits.substr(0, digits.length() - 3)
	return ("-" if n < 0 else "") + digits + out


## A ladder's tiers (milestones), in order.
static func tiers(ladder: String) -> Array:
	return all().filter(func(m): return m.get("ladder", "") == ladder)


## [name and stars ("Pistolero ★★☆"), what the tier you're on takes, progress
## toward it, what it gives, every tier climbed, what the top tier gives] for
## each ladder (the bosses', on their own page, with `bosses`).
static func ladder_rows(bosses := false) -> Array:
	var out := []
	for l in LADDERS:
		if l.has("boss") != bosses:
			continue
		var t := tiers(l.id)
		var done := t.filter(func(m): return has(m.id)).size()
		var on: Dictionary = t[mini(done, t.size() - 1)]
		out.append(["%s %s" % [l.name, "★".repeat(done) + "☆".repeat(t.size() - done)], on.text,
			"%s / %s" % [grouped(mini(progress(l.stat), int(on.need))), grouped(int(on.need))], on.gives, done == t.size(), t[-1].gives])
	return out
