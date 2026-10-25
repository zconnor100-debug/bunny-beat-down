class_name Mastery
extends RefCounted
## Milestones: goals read off your trackers (StatBook), the cast's book
## (RivalBook) and your runs (Run), each unlocking something for good when
## you reach it. Checked as you play (MatchManager, after a beat-down and at
## the end of a match) and shown in the Trophy Room with your progress.
##
## Adding one is adding a row to MILESTONES: `stat` is what it counts (see
## progress(): "kills", "heads", "gun_kills:<gun id>", "gun_heads:<gun id>",
## "wins", "map_wins:<map id>", "critters_played", "cast_beaten", "max_heat",
## "signatures", "nemeses_beaten", "runs_done", "run_stops", "boons_at_once"),
## `need` how many, and `reward`
## what it gives:
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
]


static func _book() -> ConfigFile:
	return PlayerProfile._book()


static func milestone(id: String) -> Dictionary:
	for m in MILESTONES:
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
	match stat:
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
	return 0


static func _critters() -> Array:
	return TrophyPanel.CRITTERS


## You beat down a bot that was your Nemesis (for Resting on Your Laurels).
static func note_nemesis_beaten() -> void:
	_book().set_value("mastery_stats", "nemeses_beaten", int(_book().get_value("mastery_stats", "nemeses_beaten", 0)) + 1)


## How many boons you've held at once (for Green Thumb).
static func note_boons(n: int) -> void:
	if n > int(_book().get_value("mastery_stats", "boons_at_once", 0)):
		_book().set_value("mastery_stats", "boons_at_once", n)


## Check every milestone: the ones newly reached are marked (and their
## one-time rewards given). Returns them, for the game to announce.
static func check() -> Array:
	var fresh := []
	for m in MILESTONES:
		if has(m.id) or progress(m.stat) < int(m.need):
			continue
		_book().set_value("mastery", m.id, true)
		var r: Dictionary = m.reward
		if r.has("acorns"):
			Burrow.add_acorns(int(r.acorns))
		if r.has("look"):
			var owned: Array = (_book().get_value("workshop", "owned", []) as Array).duplicate()
			if not owned.has(r.look):
				owned.append(r.look)
				_book().set_value("workshop", "owned", owned)
		fresh.append(m)
	if not fresh.is_empty():
		PlayerProfile.save()
	return fresh


# ---- the rewards, where they act ---------------------------------------------------------------

## A mastered gun's mutation, for your carrots (Projectiles.mutations_for).
## The milestone that gives a Workshop look ("category:id"), or {}.
static func giving(look: String) -> Dictionary:
	for m in MILESTONES:
		if m.reward.get("look", "") == look:
			return m
	return {}


static func gun_mutation(gun_id: StringName) -> Dictionary:
	for m in MILESTONES:
		if m.reward.get("mutation", "") == String(gun_id) and has(m.id):
			return Boons.gun_mutation(m.reward.kind)
	return {}


static func _reward(key: String, default: float) -> float:
	for m in MILESTONES:
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


## [name, what it takes, progress "12 / 20", what it gives, reached] for each milestone.
static func rows() -> Array:
	return MILESTONES.map(func(m): return [m.name, m.text, "%d / %d" % [mini(progress(m.stat), int(m.need)), int(m.need)], m.gives, has(m.id)])
