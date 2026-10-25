class_name Boons
extends RefCounted
## Boons: the build you put together as you go. You pick one of three
## (DraftPanel) at an acorn shrine (AcornShrine, a few on every map) and, in a
## run (Run), after every match you get through. Four families: Bramble
## (thorns and bleeding), Sugar Rush (speed), Mutations (carrots that split,
## pierce, bounce and pop) and Deep Roots (staying alive). Picking a boon
## again levels it up (to MAX_LEVEL); once you hold boons from two families,
## their DUO boon can turn up. Only the player has boons: in a single match
## they last the match, in a run the whole run.
##
## Stat boons are applied to your critter (apply_level); the rest are read
## where they act: Projectiles (mutations), Critter (bleeding, Cruel Thorns,
## Bark Skin, Carrot Frenzy) and MatchManager (hits, hurts and beat-downs).

const MAX_LEVEL := 3
const BLEED_SECONDS := 4.0
const SPLINTER_DPS := 5.0
const DUO_HEAL := 15.0
const BARK_RANGE := 10.0

const FAMILIES := {
	"bramble": {"name": "Bramble", "color": Color(0.86, 0.3, 0.32), "text": "Thorns and bleeding"},
	"sugar": {"name": "Sugar Rush", "color": Color(1.0, 0.56, 0.8), "text": "Faster everything"},
	"mutation": {"name": "Mutations", "color": Color(0.55, 0.88, 0.32), "text": "Carrots that misbehave"},
	"roots": {"name": "Deep Roots", "color": Color(0.85, 0.62, 0.34), "text": "Staying on your paws"},
}

## Each boon: its family, name, what it does ("{v}" is this level's value) and
## the value at levels 1, 2 and 3.
const BOONS := {
	"thorny": {"family": "bramble", "name": "Thorny Carrots", "text": "Your hits make critters bleed for 4 s: {v} damage a second.", "v": [3, 5, 7]},
	"bramble_coat": {"family": "bramble", "name": "Bramble Coat", "text": "Critters that hit you take {v}% of it back in thorns.", "v": [25, 40, 55]},
	"cruel_thorns": {"family": "bramble", "name": "Cruel Thorns", "text": "Bleeding critters take {v}% more damage from you.", "v": [20, 35, 50]},
	"splinters": {"family": "bramble", "name": "Splinters", "text": "A beat-down makes every critter within {v} m bleed.", "v": [6, 9, 12]},
	"sugar_rush": {"family": "sugar", "name": "Sugar Rush", "text": "Run {v}% faster.", "v": [10, 18, 25]},
	"bunny_hop": {"family": "sugar", "name": "Bunny Hop", "text": "Jump {v}% higher.", "v": [20, 35, 50]},
	"quick_draw": {"family": "sugar", "name": "Quick Draw", "text": "Reload {v}% faster.", "v": [20, 30, 40]},
	"frenzy": {"family": "sugar", "name": "Carrot Frenzy", "text": "Every beat-down: {v} s of firing and running 30% faster.", "v": [4, 6, 8]},
	"splitting": {"family": "mutation", "name": "Splitting Carrots", "text": "A carrot that hits a critter bursts into {v} shards that fly on (40% damage each).", "v": [2, 3, 4]},
	"piercing": {"family": "mutation", "name": "Piercing Carrots", "text": "Carrots go through {v} critter(s), losing 30% each time.", "v": [1, 2, 3]},
	"bouncy": {"family": "mutation", "name": "Bouncy Carrots", "text": "Carrots bounce off walls and floors {v} time(s).", "v": [1, 2, 3]},
	"popping": {"family": "mutation", "name": "Popping Carrots", "text": "One carrot in {v} pops where it lands: a little blast.", "v": [6, 4, 3]},
	"thick_skin": {"family": "roots", "name": "Thick Skin", "text": "+{v} health.", "v": [20, 40, 60]},
	"carrot_juice": {"family": "roots", "name": "Carrot Juice", "text": "Heal {v}% of the damage you deal.", "v": [8, 12, 16]},
	"acorn_shell": {"family": "roots", "name": "Acorn Shell", "text": "+{v} shield, and you drop in with it every match.", "v": [25, 50, 75]},
	"hush": {"family": "roots", "name": "Hush", "text": "Bots take {v}% longer to spot you.", "v": [25, 40, 55]},
}

## Duo boons: one level, offered once you hold a boon from both families.
const DUOS := {
	"briar_shards": {"families": ["bramble", "mutation"], "name": "Briar Shards", "text": "Shards, and carrots that pierced or bounced, make critters bleed."},
	"second_breakfast": {"families": ["sugar", "roots"], "name": "Second Breakfast", "text": "Every beat-down heals you 15."},
	"ricochet_rush": {"families": ["mutation", "sugar"], "name": "Ricochet Rush", "text": "After a bounce or a pierce, carrots fly 40% faster and hit 25% harder."},
	"bark_skin": {"families": ["bramble", "roots"], "name": "Bark Skin", "text": "Take 20% less damage while a critter within 10 m of you is bleeding."},
}

## The player's boons: {id: level}.
static var held: Dictionary = {}
static var _pop_count := 0


## Start over with these boons (a run's), or none.
static func reset(from: Dictionary = {}) -> void:
	held = from.duplicate()
	_pop_count = 0


static func level(id: String) -> int:
	return int(held.get(id, 0))


static func has(id: String) -> bool:
	return level(id) > 0


## The boon's value at `at` (its level now, by default); 0 if it isn't held.
static func value(id: String, at := -1) -> float:
	var lv := level(id) if at < 0 else at
	if lv <= 0 or not BOONS.has(id):
		return 1.0 if lv > 0 and DUOS.has(id) else 0.0
	var v: Array = BOONS[id].v
	return float(v[clampi(lv, 1, v.size()) - 1])


static func name_of(id: String) -> String:
	return String(BOONS.get(id, DUOS.get(id, {})).get("name", id))


static func family_of(id: String) -> String:
	return String(BOONS[id].family) if BOONS.has(id) else "duo"


static func color_of(id: String) -> Color:
	if DUOS.has(id):
		return Color(1.0, 0.85, 0.35)
	return FAMILIES[family_of(id)].color


## What the boon does at `at` (its next level, by default).
static func describe(id: String, at := -1) -> String:
	if DUOS.has(id):
		return DUOS[id].text
	var lv := level(id) + 1 if at < 0 else at
	var v := value(id, mini(lv, MAX_LEVEL))
	return String(BOONS[id].text).replace("{v}", "%d" % roundi(v))


## "Thorny Carrots II" style.
static func title(id: String, at := -1) -> String:
	var lv := level(id) if at < 0 else at
	if DUOS.has(id) or lv <= 1:
		return name_of(id)
	return "%s %s" % [name_of(id), ["", "I", "II", "III"][clampi(lv, 1, 3)]]


static func family_count(f: String) -> int:
	var n := 0
	for id in held:
		if BOONS.has(id) and BOONS[id].family == f:
			n += 1
	return n


## A draft: `n` different boons to pick from (ones you hold come back as their
## next level; a duo you qualify for is twice as likely to turn up).
static func offer(rng: RandomNumberGenerator, n := 3) -> Array:
	var pool := []
	var weights := []
	for id in BOONS:
		if level(id) < MAX_LEVEL:
			pool.append(id)
			weights.append(1.0)
	for id in DUOS:
		var fams: Array = DUOS[id].families
		if not has(id) and family_count(fams[0]) > 0 and family_count(fams[1]) > 0:
			pool.append(id)
			weights.append(2.0)
	var out := []
	while out.size() < n and not pool.is_empty():
		var total := 0.0
		for w in weights:
			total += w
		var r := rng.randf() * total
		var i := 0
		while i < pool.size() - 1 and r > weights[i]:
			r -= weights[i]
			i += 1
		out.append(pool[i])
		pool.remove_at(i)
		weights.remove_at(i)
	return out


## Take a boon (or its next level). Returns the level it was at.
static func add(id: String) -> int:
	var was := level(id)
	if DUOS.has(id):
		held[id] = 1
	elif BOONS.has(id):
		held[id] = mini(was + 1, MAX_LEVEL)
	return was


## Stat boons, onto the player's critter: from level `from` to `to` (0 → its
## level when a run's critter drops in; was → was + 1 when picked).
static func apply_level(c: Critter, id: String, from: int, to: int) -> void:
	if c == null or to <= from:
		return
	var a := value(id, from) if from > 0 else 0.0
	var b := value(id, to)
	match id:
		"thick_skin":
			c.max_health += b - a
			c.health += b - a
		"sugar_rush":
			c.speed_scale *= (1.0 + b / 100.0) / (1.0 + a / 100.0)
		"bunny_hop":
			c.jump_scale *= (1.0 + b / 100.0) / (1.0 + a / 100.0)
		"quick_draw":
			c.reload_scale *= (1.0 - b / 100.0) / (1.0 - a / 100.0)
		"acorn_shell":
			c.armor = minf(c.max_armor, c.armor + (b if from == 0 else b - a))
		"hush":
			AIBrain.player_stealth *= (1.0 + a / 100.0) / (1.0 + b / 100.0)


## Every boon held, onto a critter that's just joined the match.
static func apply_all(c: Critter) -> void:
	for id in held:
		apply_level(c, id, 0, level(id))


## The mutations on the player's carrots right now: {"split": n, "pierce": n,
## "bounce": n, "pop": one-in-n, "bleed": bool (Briar Shards), "rush": bool}.
static func carrot_mutations() -> Dictionary:
	var m := {}
	if has("splitting"):
		m["split"] = int(value("splitting"))
	if has("piercing"):
		m["pierce"] = int(value("piercing"))
	if has("bouncy"):
		m["bounce"] = int(value("bouncy"))
	if has("popping"):
		m["pop"] = int(value("popping"))
	if has("briar_shards"):
		m["bleed"] = true
	if has("ricochet_rush"):
		m["rush"] = true
	return m


## Popping Carrots: is this carrot (of the player's) the one in n that pops?
static func next_pops(every: int) -> bool:
	_pop_count += 1
	return every > 0 and _pop_count % every == 0


## Mutations a gun has built in (a nemesis's signature gun, a mastered gun):
## the same keys as carrot_mutations(), at level 1.
static func gun_mutation(kind: String) -> Dictionary:
	match kind:
		"splitting":
			return {"split": 2}
		"piercing":
			return {"pierce": 1}
		"bouncy":
			return {"bounce": 1}
		"popping":
			return {"pop": 4}
	return {}


## Your boons, in a line (HUD, run screen).
static func summary() -> String:
	var ids := held.keys()
	ids.sort_custom(func(a, b): return family_of(a) < family_of(b) if family_of(a) != family_of(b) else a < b)
	return ", ".join(ids.map(func(id): return title(id)))
