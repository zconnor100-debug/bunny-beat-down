class_name MatchManager
extends Node
## Runs one battle royale: spawns the field, flies the balloon, starts the
## Briar, tracks eliminations and declares the last critter standing.

signal phase_changed(phase: Phase)
signal finished(winner: Critter, player_placement: int)
signal player_eliminated(placement: int, killer: Critter)
## A boon draft for the player (an acorn shrine): game.gd shows it (DraftPanel).
signal boons_offered(choices: Array, title: String)

enum Phase { LOADING, DROPPING, PLAYING, ENDED }

const CRITTER_DEFS := ["bandit_bunny", "squirrel", "fox", "raccoon", "frog", "beaver", "hamster"]

var phase := Phase.LOADING
var island: Island
var storm: Storm
var time_keeper: TimeKeeper         ## rewinds (see TimeKeeper)
var kill_cam: KillCam               ## the final shot, replayed (see KillCam)
var dropship: Dropship
var player: Critter
var critters: Array[Critter] = []
var total := 0
var rng := RandomNumberGenerator.new()
var pace := 1.0
var world_root: Node3D
var _alive_cache := 0
## Your rivals (see RivalBook) who made it into this match.
var rivals_here: Array[Critter] = []
## The bot with a price on its head this match (the most radical one you've
## made, or a rival) and the acorns you get for beating it down.
var bounty_name := ""
var bounty := 0
var bounty_paid := false
var _feuded: Dictionary = {}        # "a|b" -> true (a feud line once per pair a match)
var _feud_t := -100.0
var _director_said: Dictionary = {}   # bot -> true (it cursed the director this match)
var _was_shrinking := false
const WANTED_EVERY := 40.0
var _wanted_t := 0.0
## The director: bots that learn you (see PlayerProfile). Camping draws
## hunters, a hot streak makes the bots sharpen up for a while.
const CAMP_RADIUS := 14.0
const CAMP_SECONDS := 25.0
const CAMP_COOLDOWN := 45.0
const STREAK_WINDOW := 30.0
const ADAPT_SECONDS := 60.0
var _camp_anchor := Vector3.INF
var _camp_t := 0.0
var _camp_cooldown := 0.0
var _player_kills: Array[float] = []   # match clock of each of the player's beat-downs
var _adapt_left := 0.0
var _clock := 0.0
var _landed := false
## This match's Briar mood (see Storm.VARIANTS): classic a quarter of the time.
var briar_variant := "classic"
var revenges := 0                    ## rivals the player beat down this match (acorns!)
var _taunted: Dictionary = {}       # "name|event" -> true (spot taunts once a match)
var _supply_t := 0.0
const SUPPLY_INTERVAL := 75.0
## Shrines, gangs, the nemesis: rolled on their own generator, so a seed's
## loot and lobby come out as they always did.
var extra_rng := RandomNumberGenerator.new()
var shrines: Array[AcornShrine] = []
## A gang: a few of the bots you've made radical, dropping in together and
## out for you (they leave each other alone). Its name, and who's in it.
var gang_name := ""
var gang: Array[Critter] = []
const GANG_NAMES := ["the Thorn Gang", "the Bramble Bunch", "the Muddy Paws", "the Acorn Ring", "the Hedge Mob", "the Burrow Bandits"]
## The nemesis hunt: your Nemesis (Cast heat 4; in a run's finale, the
## hottest bot there) hunts you all match, tougher than the rest, and drops
## its signature gun when you beat it down.
var nemesis: Critter
const NEMESIS_EVERY := 20.0         ## seconds between its "where are you?"
const NEMESIS_HEALTH := 1.5
var _nemesis_t := 0.0
var _nemesis_announced := false
## A run's stop (Run): its goal ({top, kills}) and whether you've made it.
var run_goal: Dictionary = {}
var run_goal_met := false


func setup(world_root_: Node3D, island_: Island, opponents: int, difficulty: int, seed_: int, pace_ := 1.0) -> void:
	world_root = world_root_
	island = island_
	pace = pace_
	# this match's Burrow modifiers and perks that act on everyone
	Critter.glass_cannon = Burrow.modifier_on("glass_cannon")
	CritterVisual.name_tag_range_scale = (2.0 if Burrow.has_perk("hawk_eye") else 1.0) * (0.6 if Burrow.modifier_on("pea_soup") else 1.0)
	AIBrain.player_stealth = 0.6 if Burrow.has_perk("light_step") else 1.0
	AIBrain.player_muffled = Workshop.fitted("muffler")
	AIBrain.vision_scale = 0.5 if Burrow.modifier_on("pea_soup") else 1.0
	WeaponDB.only = &"carrot_rocket_launcher" if Burrow.modifier_on("rocket_party") else &""
	Projectiles.own_tracer = Projectiles.tracer_color(Workshop.look("tracer"))
	rng.seed = seed_ * 7 + 1
	extra_rng.seed = seed_ * 13 + 5
	Boons.reset(Run.boons() if Run.in_match else {})
	var moods := Storm.VARIANTS.keys().filter(func(k): return k != "classic")
	briar_variant = "classic" if rng.randf() < 0.25 else moods[rng.randi() % moods.size()]
	storm = Storm.new()
	storm.name = "Storm"
	world_root.add_child(storm)
	time_keeper = TimeKeeper.new()
	time_keeper.name = "TimeKeeper"
	time_keeper.match_manager = self
	add_child(time_keeper)
	kill_cam = KillCam.new()
	kill_cam.name = "KillCam"
	kill_cam.match_manager = self
	add_child(kill_cam)
	Events.critter_died.connect(_on_critter_died)
	Events.critter_damaged.connect(_on_critter_damaged)
	Events.shot_fired.connect(_on_shot_fired)
	var d := clampi(difficulty, 0, 2)
	AIBrain.player_attack_slots = [1, 2, 3][d]
	AIBrain.damage_to_player = [0.45, 0.65, 0.85][d]
	_spawn_loot()
	_spawn_shrines()
	var defs := {}
	for cd in _available_defs():
		defs[String(cd.id)] = cd
	# the cast (Cast): your rivals and the bots you've made radical always
	# come back for more, then the ones with grudges, then anyone
	for n in Cast.lineup(opponents, rng):
		var def: CritterDef = defs.get(Cast.member(n).species)
		if def == null:
			continue
		var c := _spawn_critter(def, n)
		var rival := RivalBook.is_rival(n)
		c.visual.set_enemy_highlight(Cast.title(n), rival, Cast.heat(n))
		if rival:
			rivals_here.append(c)
		RivalBook.note_meeting(n, String(def.id))
		# each rogue in its own fur and outfit (Outfits); the roll is made either
		# way, so a seed lays out the same island whatever the bots wear
		var skins := def.skins()
		var skin_roll := rng.randi()
		if Outfits.look_of(n).is_empty():
			c.visual.apply_skin(String(skins[skin_roll % skins.size()].get("id", "default")))
		else:
			Outfits.dress(c, n)
		var brain := AIBrain.new()
		brain.name = "AIBrain"
		brain.island = island
		brain.match_manager = self
		AIBrain.player_style = PlayerProfile.fighting_style()
		brain.personality = RivalBook.personality_of(n)
		brain.rival = rival
		brain.traits = Cast.traits_for(n)
		brain.grudges = RivalBook.grudges(n)
		var heat := Cast.heat(n)
		var p: Dictionary = RivalBook.PERSONALITIES[brain.personality]
		brain.skill = clampf(_skill_for(difficulty) + rng.randf_range(-0.12, 0.12) + float(p.skill) + (0.06 if rival else 0.0) + 0.04 * heat, 0.05, 0.98)
		c.defies_director = brain.traits.get("defiant", false)
		c.add_child(brain)
		_heat_loadout(c, n, heat)
		_remembers_you(c, n)
		if Burrow.modifier_on("stampede"):
			c.speed_scale = 1.2
	_form_gang()
	_choose_nemesis()
	_choose_bounty()
	RivalBook.save()
	total = critters.size() + 1   # + the player, who joins after picking a critter
	_alive_cache = total
	Events.alive_count_changed.emit(total, total)


## The player's critter joins once they've picked it on the loading screen.
func spawn_player(def: CritterDef, skin_id: String) -> Critter:
	var display := "Bun" if def.id == &"bun" else "You (%s)" % def.display_name
	player = _spawn_critter(def, display)
	player.visual.apply_skin(skin_id)
	Outfits.dress_player(player)   # (your wardrobe, from the Workshop)
	StatBook.begin_match(def.id)
	_apply_perks(player)
	var pc := PlayerController.new()
	pc.name = "PlayerController"
	player.add_child(pc)
	# _spawn_critter already registered it; keep the player first in the list
	# (registering it twice put it on the balloon twice: a second drop at the end of the route)
	critters.erase(player)
	critters.push_front(player)
	total = critters.size()
	Events.alive_count_changed.emit(total, total)
	Boons.apply_all(player)
	if Run.in_match:
		var k := Run.keepsake()
		if k:
			player.give_weapon(k)
			player.inventory.add_ammo(k.data.ammo_type, Inventory.AMMO_PICKUP[k.data.ammo_type] * 2)
		time_keeper.charges = Run.rewinds()
		run_goal = Run.goal(total)
	return player


## The perks you took into this match from the Burrow.
func _apply_perks(p: Critter) -> void:
	# the Workshop's attachments (before any gun goes in the paws)
	if Workshop.fitted("red_dot"):
		p.aim_spread_scale = 0.75
	if Workshop.fitted("laser"):
		p.hip_spread_scale = 0.8
	if Workshop.fitted("stock"):
		p.bloom_scale = 0.7
	if Workshop.fitted("long_mag"):
		p.mag_scale = 1.3
	p.visual.kit = {"sight": Workshop.fitted("red_dot"), "laser": Workshop.fitted("laser"), "skin": Workshop.look("skin")}
	p.flash_look = Workshop.look("flash")
	p.smoke_look = Workshop.look("smoke")
	p.muffled = Workshop.fitted("muffler")
	if Burrow.has_perk("big_appetite"):
		p.clover_heal *= 1.5
	if Burrow.has_perk("deep_pockets"):
		p.inventory.ammo_cap_scale = 1.5
	if Burrow.has_perk("thorn_coat"):
		p.briar_scale = 0.5
	if Burrow.has_perk("regrowth"):
		p.shield_regrow = 25.0
	if Burrow.has_perk("thick_fur"):
		p.armor = 50.0
	if Burrow.has_perk("pocket_clover"):
		p.inventory.clovers += 2
	if Burrow.has_perk("quick_paws"):
		p.reload_scale = 0.75
	if Burrow.has_perk("spring_legs"):
		p.jump_scale *= 1.3
	if Burrow.has_perk("second_wind"):
		p.second_wind = true
	if Burrow.has_perk("lucky_start"):
		var w := WeaponInstance.new(WeaponDB.random_weapon(rng), rng.randi_range(Rarity.Tier.PRIZE, Rarity.Tier.GOLDEN))
		p.give_weapon(w)
		p.inventory.add_ammo(w.data.ammo_type, Inventory.AMMO_PICKUP[w.data.ammo_type] * 2)


## A bot you've radicalised comes prepared: from Vengeful on it drops in with
## its favourite gun (better the angrier it is), from Unhinged in armour.
func _heat_loadout(c: Critter, n: String, heat: int) -> void:
	if heat >= 2:
		var data := WeaponDB.get_weapon(StringName(Cast.member(n).weapon))
		if data:
			var tier: int = [Rarity.Tier.GARDEN, Rarity.Tier.PRIZE, Rarity.Tier.HEIRLOOM][clampi(heat - 2, 0, 2)]
			c.give_weapon(WeaponInstance.new(data, tier))
			c.inventory.add_ammo(data.ammo_type, Inventory.AMMO_PICKUP[data.ammo_type] * 2)
	if heat >= 3:
		c.armor = 50.0 if heat == 3 else 100.0


## What a bot remembers of you: the scars you gave it (it comes back wearing
## them, and tougher), and the gun it took off you (it's carrying it, in your skin).
func _remembers_you(c: Critter, n: String) -> void:
	var scars := RivalBook.scars(n)
	if not scars.is_empty():
		c.visual.add_scars(scars)
		if scars.has("eye_patch"):
			c.head_guard = 0.75
		if scars.has("singed"):
			c.blast_guard = 0.7
		var limbs := scars.filter(func(x): return String(x).begins_with("arm") or String(x).begins_with("leg")).size()
		c.max_health += 10.0 * limbs
		c.health = c.max_health
	var took := RivalBook.took_gun(n)
	if not took.is_empty():
		var w := WeaponInstance.from_dict(took)
		if w:
			c.visual.kit = {"skin": String(took.get("skin", "stock"))}
			c.give_weapon(w)
			c.switch_to(c.inventory.weapons.find(w))   # (it shows it off)
			c.inventory.add_ammo(w.data.ammo_type, Inventory.AMMO_PICKUP[w.data.ammo_type] * 2)
			c.set_meta(&"your_gun", w.display_name())


## A gang forms when two or more of the bots here are ones you've made
## Vengeful or worse (in a run's Grudge Match, any you've made Sore), or
## your rivals: the three hottest drop in together and hunt you.
func _form_gang() -> void:
	var grudge: bool = Run.in_match and Run.current().get("kind", "") == "grudge"
	var hot := critters.filter(func(c): return c != player and (Cast.heat(c.display_name) >= (1 if grudge else 2) or RivalBook.is_rival(c.display_name)))
	if hot.size() < 2:
		return
	hot.sort_custom(func(a, b): return Cast.heat(a.display_name) > Cast.heat(b.display_name))
	gang_name = GANG_NAMES[extra_rng.randi() % GANG_NAMES.size()]
	for c in hot.slice(0, 3):
		gang.append(c)
		c.gang = gang_name
		var brain := c.get_node_or_null("AIBrain") as AIBrain
		if brain:
			brain.traits = brain.traits.duplicate()
			brain.traits["hunts_you"] = true
		if c.visual.name_tag:
			c.visual.name_tag.text += "\n" + gang_name


## Your Nemesis, if one's here (a run's finale always has one: the hottest bot).
func _choose_nemesis() -> void:
	var forced: bool = Run.in_match and Run.current().get("kind", "") == "finale"
	var best: Critter = null
	var best_heat := -1.0
	for c in critters:
		if c == player:
			continue
		var h := Cast.heat(c.display_name) + (0.5 if RivalBook.is_rival(c.display_name) else 0.0) + RivalBook.your_kills(c.display_name) * 0.01
		if h > best_heat:
			best_heat = h
			best = c
	if best == null or (Cast.heat(best.display_name) < 4 and not forced):
		return
	nemesis = best
	nemesis.max_health *= NEMESIS_HEALTH
	nemesis.health = nemesis.max_health
	nemesis.armor = nemesis.max_armor
	var brain := nemesis.get_node_or_null("AIBrain") as AIBrain
	if brain:
		brain.traits = brain.traits.duplicate()
		brain.traits["hunts_you"] = true
		brain.traits["no_slot"] = true
		brain.skill = minf(brain.skill + 0.1, 0.98)
	if nemesis.visual.name_tag:
		nemesis.visual.name_tag.text = "☠ NEMESIS %s" % nemesis.display_name + ("\n" + gang_name if nemesis.gang != "" else "")
		nemesis.visual.name_tag.modulate = Color(1.0, 0.2, 0.25)


## The acorn shrines: a few on every map, somewhere out in the open.
func _spawn_shrines() -> void:
	var n := 3 if island is HamsterCage or island is ToyBox else 4
	var keep := island.rng.state
	island.rng.seed = extra_rng.randi()
	var spots: Array[Vector3] = []
	for i in 40:
		if spots.size() >= n:
			break
		var p := island.random_land_point(2.5)
		if spots.any(func(q): return q.distance_to(p) < island.terrain.island_radius * 0.45):
			continue
		p = island.clear_loot_spot(p, Vector3(0.6, 0.5, 0.6))
		if p == Vector3.INF:
			continue
		spots.append(p)
	island.rng.state = keep
	for p in spots:
		var sh := AcornShrine.new()
		world_root.add_child(sh)
		sh.global_position = p
		sh.rotation.y = extra_rng.randf() * TAU
		sh.used.connect(_on_shrine_used)
		shrines.append(sh)


func _on_shrine_used(by: Critter) -> void:
	if by == player:
		offer_boons("The acorn shrine offers a boon")


## Offer the player a draft of boons (DraftPanel, via game.gd).
func offer_boons(title: String) -> void:
	var choices := Boons.offer(extra_rng, Mastery.draft_size())
	if not choices.is_empty():
		boons_offered.emit(choices, title)


## The player took a boon (or its next level).
func choose_boon(id: String) -> void:
	var was := Boons.add(id)
	if player:
		Boons.apply_level(player, id, was, Boons.level(id))
	Events.headline.emit("Boon: %s" % Boons.title(id))
	Mastery.note_boons(Boons.held.size())
	_check_mastery()


## Milestones (Mastery) reached just now: announced, one at a time.
func _check_mastery() -> void:
	var fresh := Mastery.check()
	for i in fresh.size():
		var m: Dictionary = fresh[i]
		if i == 0:
			Events.announce.emit("MILESTONE: %s" % String(m.name).to_upper(), "%s: %s." % [m.text.trim_suffix("."), m.gives])
		else:
			Events.headline.emit("Milestone: %s (%s)" % [m.name, m.gives])


## The bounty: the most radical bot you've made (Vengeful or worse), else
## your worst rival, is worth acorns this match.
func _choose_bounty() -> void:
	var best := -1.0
	for c in critters:
		var n := c.display_name
		var worth := Cast.heat(n) * 10.0 + (8.0 if RivalBook.is_rival(n) else 0.0) + RivalBook.kills_on_you(n)
		if (Cast.heat(n) >= 2 or RivalBook.is_rival(n)) and worth > best:
			best = worth
			bounty_name = n
	if bounty_name != "":
		bounty = 15 + 10 * Cast.heat(bounty_name) + (10 if RivalBook.is_rival(bounty_name) else 0)


## The lobby's news, for the feed as the drop starts: who you've made
## radical, who's feuding with whom, who's furious with the director, and
## the bounty.
func headlines() -> Array:
	var out := []
	var here := critters.filter(func(c): return is_instance_valid(c) and c != player).map(func(c): return c.display_name)
	var hot := here.filter(func(n): return Cast.heat(n) >= 2)
	hot.sort_custom(func(a, b): return Cast.heat(a) > Cast.heat(b))
	for n in hot.slice(0, 2):
		out.append("%s is here. You've beaten them down %d times." % [Cast.title(n), RivalBook.your_kills(n)])
	var feuds := []
	for n in here:
		var g := RivalBook.grudges(n)
		for other in g:
			if other in here:
				feuds.append([int(g[other]), n, other])
	feuds.sort_custom(func(a, b): return a[0] > b[0])
	for f in feuds.slice(0, 2):
		out.append("%s has a score to settle with %s." % [f[1], f[2]])
	if nemesis:
		out.push_front("NEMESIS HUNT: %s is hunting you. Beat them down for their signature gun." % Cast.title(nemesis.display_name))
	if gang.size() > 1:
		out.append("%s %s have ganged up on you, as %s." % [", ".join(gang.slice(0, gang.size() - 1).map(func(c): return c.display_name)),
			"and " + gang.back().display_name, gang_name])
	for c in critters:
		if is_instance_valid(c) and c.has_meta(&"your_gun"):
			out.append("%s is carrying your %s. Get it back." % [c.display_name, c.get_meta(&"your_gun")])
	var angry := here.filter(func(n): return RivalBook.director_grudge(n) >= Cast.DEFIANT_AT)
	if not angry.is_empty():
		out.append("%s is furious with the director, and won't play by its rules." % angry[0])
	if bounty_name != "":
		out.append("BOUNTY: %s. Beat them down for %d acorns." % [Cast.title(bounty_name), bounty])
	return out


## A bot spots one it holds a grudge against: it says so (once per pair a
## match, and not too often across the lobby).
func feud(c: Critter, other: Critter) -> void:
	var key := "%s|%s" % [c.display_name, other.display_name]
	if _feuded.has(key) or _clock - _feud_t < 6.0 or player == null:
		return
	_feuded[key] = true
	_feud_t = _clock
	Events.taunt.emit(c, Cast.pick(Cast.FEUD_LINES, rng, {"them": other.display_name}))


func _available_defs() -> Array[CritterDef]:
	var out: Array[CritterDef] = []
	for id in CRITTER_DEFS:
		var d: CritterDef = load("res://data/critters/%s.tres" % id)
		if d:
			out.append(d)
	return out


static func _skill_for(difficulty: int) -> float:
	return [0.28, 0.55, 0.82][clampi(difficulty, 0, 2)]


func _spawn_critter(def: CritterDef, display: String) -> Critter:
	var c := Critter.new()
	c.def = def
	c.display_name = display
	if Burrow.modifier_on("low_gravity"):
		c._gravity *= 0.55
		c.jump_scale = 1.8
	c.name = "Critter_%s" % display.replace(" ", "_")
	world_root.add_child(c)
	critters.append(c)
	if Burrow.modifier_on("fragile"):
		c.max_health *= 0.5
		c.health = c.max_health
	if Burrow.modifier_on("clover_drought"):
		c.clover_heal *= 0.5
	# everyone waits, parked out of harm's way, until the drop vehicle takes
	# them (while you pick your critter: left standing at the origin, bots fell
	# out of any map with no floor there, the Toy Box's being 4 m up)
	c.board_dropship()
	return c


func _spawn_loot() -> void:
	for lp in island.loot_points:
		var pos: Vector3 = lp.pos
		# (chests and crates are bigger than a carrot gun lying about)
		var half := Vector3(0.9, 0.5, 0.9) if lp.has("chest") or lp.get("crate", false) else Vector3(0.35, 0.3, 0.35)
		pos = island.clear_loot_spot(pos, half, not lp.get("inside", false))
		if pos == Vector3.INF:
			continue
		if lp.has("chest"):
			var chest := TreasureChest.new(lp.chest == "golden")
			chest.rng.seed = rng.randi()
			world_root.add_child(chest)
			chest.global_position = pos
			chest.rotation.y = lp.get("yaw", 0.0)
			continue
		if lp.crate:
			var crate := LootCrate.new()
			crate.model_scale = LootCrate.CRATE_SCALE
			crate.rng.seed = rng.randi()
			world_root.add_child(crate)
			crate.global_position = pos
			crate.rotation.y = lp.get("yaw", 0.0)
			continue
		var roll := rng.randf()
		var spec: Dictionary
		if roll < 0.45:
			var tier := Rarity.roll(Rarity.FLOOR_WEIGHTS, rng)
			if Burrow.modifier_on("golden_hour"):
				tier = mini(tier + 1, Rarity.Tier.GOLDEN)
			var w := WeaponInstance.new(WeaponDB.random_weapon(rng), tier)
			Pickup.spawn(world_root, Pickup.weapon_spec(w), pos + Vector3.UP * 0.3)
			spec = Pickup.ammo_spec(w.data.ammo_type, Inventory.AMMO_PICKUP[w.data.ammo_type])
			pos += Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1))
		elif roll < 0.8:
			var t := rng.randi_range(0, 3)
			spec = Pickup.ammo_spec(t, Inventory.AMMO_PICKUP[t])
		elif roll < 0.92:
			spec = Pickup.clover_spec(rng.randi_range(1, 2))
		else:
			spec = Pickup.armor_spec(50.0)
		Pickup.spawn(world_root, spec, pos + Vector3.UP * 0.3)


## Board everyone and launch the balloon (or the toy plane).
func begin_drop() -> void:
	dropship = Dropship.new()
	dropship.name = "Dropship"
	world_root.add_child(dropship)
	dropship.setup(island.terrain.island_radius, rng, island.drop_vehicle, island.play_bounds())
	# the bots know where you like to land
	var fav := PlayerProfile.favourite_landing(island.pois.map(func(p): return p.name))
	var fav_poi: Dictionary = {}
	for p in island.pois:
		if p.name == fav:
			fav_poi = p
	if not fav_poi.is_empty():
		get_tree().create_timer(12.0).timeout.connect(func():
			Events.announce.emit("THEY KNOW WHERE YOU LAND", "More critters are heading for %s this time." % fav))
	# landmarks are popular, but only so popular: a full lobby piling into the
	# same few spots beat each other down within a minute of landing
	var per_poi := {}
	var poi_cap := maxi(2, ceili(critters.size() / maxf(island.pois.size() * 1.5, 1.0)))
	for c in critters:
		dropship.board(c)
		var brain := c.get_node_or_null("AIBrain") as AIBrain
		if brain:
			# pick a landing spot (POIs are popular) and jump when the balloon is closest
			var spot := island.random_land_point(2.5)
			if rng.randf() < 0.65 and not island.pois.is_empty():
				var poi: Dictionary = island.pois[rng.randi() % island.pois.size()]
				if int(per_poi.get(poi.name, 0)) < poi_cap:
					per_poi[poi.name] = int(per_poi.get(poi.name, 0)) + 1
					var cc: Vector2 = poi.center + Vector2(rng.randf_range(-12, 12), rng.randf_range(-12, 12))
					spot = Vector3(cc.x, island.terrain.height_at(cc.x, cc.y), cc.y)
			if not fav_poi.is_empty() and rng.randf() < 0.3:
				var fc: Vector2 = fav_poi.center + Vector2(rng.randf_range(-10, 10), rng.randf_range(-10, 10))
				spot = Vector3(fc.x, island.terrain.height_at(fc.x, fc.y), fc.y)
			brain.drop_spot = spot
			brain.drop_progress = clampf(dropship.progress_nearest(spot) + rng.randf_range(-0.06, 0.03), 0.02, 0.98)
	if gang.size() > 1:
		var lead := gang[0].get_node_or_null("AIBrain") as AIBrain
		for i in range(1, gang.size()):
			var b := gang[i].get_node_or_null("AIBrain") as AIBrain
			if lead and b:
				b.drop_spot = lead.drop_spot + Vector3(extra_rng.randf_range(-4, 4), 0.0, extra_rng.randf_range(-4, 4))
				b.drop_progress = lead.drop_progress
	dropship.launch()
	_set_phase(Phase.DROPPING)
	# the lobby's news, a line at a time once everyone's aboard
	var news := headlines()
	for i in news.size():
		get_tree().create_timer(4.0 + i * 2.5).timeout.connect(func(): Events.headline.emit(news[i]))


func _exit_tree() -> void:
	AIBrain.kills_held = false   # (statics: none of this match's rules outside it)
	AIBrain.player_muffled = false
	AIBrain.vision_scale = 1.0
	WeaponDB.only = &""
	RivalBook.save()             # (the bots' grudges and wins from this match)


## The Briar closes in: a bot sore at the director lets it know (once a match).
func _on_briar_moves(shrinking: bool) -> void:
	if shrinking and player:
		var sore := alive_critters().filter(func(c): return c != player and not _director_said.has(c.display_name) \
			and RivalBook.director_grudge(c.display_name) >= 2)
		if not sore.is_empty():
			var c: Critter = sore[rng.randi() % sore.size()]
			_director_said[c.display_name] = true
			Events.taunt.emit(c, Cast.pick(Cast.DIRECTOR_LINES, rng))
	_was_shrinking = shrinking


func _process(delta: float) -> void:
	_clock += delta
	AIBrain.kills_held = not bots_may_kill()
	if storm and storm.shrinking != _was_shrinking:
		_on_briar_moves(storm.shrinking)
	if phase == Phase.PLAYING:
		_direct(delta)
		_supply_t += delta
		if _supply_t >= SUPPLY_INTERVAL * pace:
			_supply_t = 0.0
			_spawn_supply_drop()
	if phase == Phase.DROPPING:
		if dropship and is_instance_valid(dropship):
			for c in critters:
				if c.state == Critter.State.IN_DROPSHIP:
					c.global_position = dropship.global_position + Vector3.UP * 1.0
					var brain := c.get_node_or_null("AIBrain") as AIBrain
					if brain and dropship.progress >= brain.drop_progress:
						dropship.eject(c)
		var anyone_aboard := false
		for c in critters:
			if c.state == Critter.State.IN_DROPSHIP:
				anyone_aboard = true
		if not anyone_aboard:
			storm.player = player
			storm.rush = Burrow.modifier_on("briar_rush")
			storm.start(island, island.terrain.island_radius + 50.0, pace, briar_variant)
			var v: Dictionary = Storm.VARIANTS[storm.variant]
			Events.announce.emit(String(v.title).to_upper(), v.rule)
			_set_phase(Phase.PLAYING)


## The director: notices where the player landed, camping, and hot streaks.
func _direct(delta: float) -> void:
	if player == null or not is_instance_valid(player) or not player.alive:
		return
	if not _landed and player.state == Critter.State.GROUND:
		_landed = true
		var p := Vector2(player.global_position.x, player.global_position.z)
		var near := island.in_poi(p, 1.6)
		if not near.is_empty():
			PlayerProfile.note_landing(near.name)
	# Most Wanted (a run modifier): every so often the nearest bots are told
	# where you are
	if Burrow.modifier_on("most_wanted"):
		_wanted_t += delta
		if _wanted_t >= WANTED_EVERY and player.state == Critter.State.GROUND:
			_wanted_t = 0.0
			var bots := alive_critters().filter(func(c): return c != player and c.has_node("AIBrain"))
			bots.sort_custom(func(a, b): return a.global_position.distance_squared_to(player.global_position) < b.global_position.distance_squared_to(player.global_position))
			for b in bots.slice(0, 3):
				(b.get_node("AIBrain") as AIBrain).hunt(player.global_position, 25.0)
			Events.headline.emit("The bots know where you are.")
	_hunt_you(delta)
	_check_run_goal()
	# camping: sitting in one small spot for a while draws a few hunters
	_camp_cooldown = maxf(0.0, _camp_cooldown - delta)
	if _camp_anchor == Vector3.INF or player.global_position.distance_to(_camp_anchor) > CAMP_RADIUS:
		_camp_anchor = player.global_position
		_camp_t = 0.0
	else:
		_camp_t += delta
		if _camp_t > CAMP_SECONDS and _camp_cooldown <= 0.0:
			_camp_t = 0.0
			_camp_cooldown = CAMP_COOLDOWN
			flush_out_player()
	# a hot streak: the bots sharpen up for a while
	if _adapt_left > 0.0:
		_adapt_left -= delta
		if _adapt_left <= 0.0:
			_set_adapted(false)


## Send the nearest armed bots to where the player is hiding (and say so).
func flush_out_player() -> Array[Critter]:
	var hunters: Array[Critter] = []
	var bots := alive_critters().filter(func(c): return c != player and c.inventory.has_any_weapon())
	bots.sort_custom(func(a, b): return a.global_position.distance_to(player.global_position) < b.global_position.distance_to(player.global_position))
	for c in bots.slice(0, 3):
		var brain := c.get_node_or_null("AIBrain") as AIBrain
		if brain:
			brain.hunt(player.global_position + Vector3(rng.randf_range(-6, 6), 0, rng.randf_range(-6, 6)))
			hunters.append(c)
	if not hunters.is_empty():
		Events.taunt.emit(hunters[0], "Somebody's been sitting still... coming for you, %s!" % player.def.display_name)
	return hunters


func _note_player_kill(info: DamageInfo) -> void:
	PlayerProfile.note_kill(info.weapon_id if info.weapon_id != &"" else &"melee")
	_player_kills.append(_clock)
	_player_kills = _player_kills.filter(func(t): return _clock - t < STREAK_WINDOW)
	if _player_kills.size() >= 2 and _adapt_left <= 0.0:
		_set_adapted(true)
		Events.announce.emit("THE BOTS ARE ADAPTING", "They've seen that trick before...")
	elif _adapt_left > 0.0:
		_adapt_left = ADAPT_SECONDS


func _set_adapted(on: bool) -> void:
	_adapt_left = ADAPT_SECONDS if on else 0.0
	AIBrain.player_attack_slots += 1 if on else -1
	for c in critters:
		var brain := c.get_node_or_null("AIBrain") if is_instance_valid(c) else null
		if brain:
			(brain as AIBrain).skill = clampf((brain as AIBrain).skill + (0.08 if on else -0.08), 0.05, 0.98)


func _spawn_supply_drop() -> void:
	var c := storm.next_center if storm and storm.active else Vector2.ZERO
	var r := storm.next_radius * 0.8 if storm and storm.active else island.terrain.island_radius * 0.6
	if r < 6.0:
		return
	var spot := island.random_land_point(2.0, c, r)
	var drop := SupplyDrop.new()
	drop.landing = spot
	drop.rng.seed = rng.randi()
	world_root.add_child(drop)
	drop.global_position = spot + Vector3.UP * 70.0
	Events.supply_drop_incoming.emit(spot)


## The player pressed jump while aboard.
func player_jump() -> void:
	if phase == Phase.DROPPING and player.state == Critter.State.IN_DROPSHIP and dropship:
		dropship.eject(player)
		_jump_buddies()


## A few critters still aboard jump right after you (a second or two apart)
## and head for ground near yours: you never drop alone.
const JUMP_BUDDIES := Vector2i(2, 4)

func _jump_buddies() -> void:
	var aboard := critters.filter(func(c): return c != player and c.state == Critter.State.IN_DROPSHIP and c.has_node("AIBrain"))
	if aboard.is_empty():
		return
	# bots you've made radical jump after you; then the ones who meant to
	# jump around here anyway
	var order := func(c: Critter) -> float:
		return absf(c.get_node("AIBrain").drop_progress - dropship.progress) - (10.0 if c.get_node("AIBrain").traits.get("hunts_you", false) else 0.0)
	aboard.sort_custom(func(a, b): return order.call(a) < order.call(b))
	var under := dropship.global_position
	var fwd := (dropship.finish - dropship.start).normalized()
	for i in mini(rng.randi_range(JUMP_BUDDIES.x, JUMP_BUDDIES.y), aboard.size()):
		var brain := (aboard[i] as Critter).get_node("AIBrain") as AIBrain
		brain.drop_progress = dropship.progress + (0.4 + i * 0.7) / dropship.duration
		var near := Vector2(under.x, under.z) + Vector2(fwd.x, fwd.z) * rng.randf_range(10.0, 40.0)
		var land := island.random_land_point(2.5, near, 60.0)
		if island.water_level_at(land) > land.y:
			land = island.random_land_point(2.5)   # (over the sea: anywhere will do)
		brain.drop_spot = land


func _on_critter_died(victim: Node, info: DamageInfo) -> void:
	var c := victim as Critter
	if c == null or not critters.has(c):
		return
	var alive := alive_critters()
	c.placement = alive.size() + 1
	_alive_cache = alive.size()
	Events.alive_count_changed.emit(alive.size(), total)
	if player == null:
		return   # (no match ends before you've joined it)
	var killer := info.attacker as Critter
	if killer and killer != player and killer != c and critters.has(killer):
		RivalBook.note_bot_kill(killer.display_name, info.weapon_id, killer.global_position.distance_to(c.global_position))
	if c == nemesis and killer != player:
		nemesis = null
		Events.headline.emit("%s was beaten down%s. Your nemesis hunt is off." % [c.display_name, " by %s" % killer.display_name if killer and killer != c else ""])
	if c == player and killer and killer != player:
		if RivalBook.note_you_died_to(killer.display_name, String(killer.def.id)):
			killer.set_meta(&"new_rival", true)
		_steal_gun(killer)
		taunt(killer, "kill")
	elif killer == player and c != player:
		_note_player_kill(info)
		StatBook.note_kill(info.weapon_id, player.global_position.distance_to(c.global_position))
		var heat_was := Cast.heat(c.display_name)
		if RivalBook.note_you_beat(c.display_name, String(c.def.id)):
			revenges += 1
			Events.rival_news.emit("REVENGE!", "You beat down your rival %s — now %s" % [c.display_name, RivalBook.score(c.display_name)])
		elif c.display_name == bounty_name and not bounty_paid:
			bounty_paid = true
			Events.rival_news.emit("BOUNTY!", "You beat down %s: +%d acorns" % [c.display_name, bounty])
		if Burrow.has_perk("adrenaline"):
			player.health = minf(player.max_health, player.health + 20.0)
		_boons_on_kill(c)
		_scar(c, info)
		_check_mastery()
		if not RivalBook.took_gun(c.display_name).is_empty():
			RivalBook.clear_took_gun(c.display_name)
			Events.headline.emit("You got your %s back from %s." % [c.get_meta(&"your_gun", "gun"), c.display_name])
		if c == nemesis:
			_nemesis_beaten(c)
		if Burrow.has_perk("scavenger"):
			Pickup.spawn(world_root, Pickup.clover_spec(1), c.global_position + Vector3.UP * 0.6, Vector3(0, 3.0, 0))
		FX.beat_down(c.get_chest_position(), Workshop.look("kill_fx"))
		var heat_now := Cast.heat(c.display_name)
		if heat_now > heat_was:
			Events.headline.emit("%s won't forget this. They're %s now." % [c.display_name, Cast.HEAT_LABELS[heat_now]])
		if c.display_name in _rival_names() or heat_now >= 2 or rng.randf() < 0.35:
			taunt(c, "lose")
	elif killer and killer != c and c != player:
		# bots keep score among themselves too
		if RivalBook.note_bot_beat(killer.display_name, c.display_name):
			Events.headline.emit("%s got even with %s." % [killer.display_name, c.display_name])
	if c != player and info.kind == DamageInfo.Kind.STORM:
		RivalBook.note_director(c.display_name, 2)   # (the Briar took it: the director's fault)

	if alive.size() <= 1 and phase != Phase.ENDED and kill_cam:
		kill_cam.note_final(c, info)   # (before anyone hears the match is over)
	if c == player:
		StatBook.end_match(c.placement, total, true)
		_check_mastery()
		player_eliminated.emit(c.placement, info.attacker as Critter)
	if alive.size() <= 1 and phase != Phase.ENDED:
		var winner: Critter = alive[0] if alive.size() == 1 else null
		if winner:
			winner.placement = 1
			if winner != player:
				RivalBook.note_win(winner.display_name)
			else:
				StatBook.end_match(1, total, false)
				_check_mastery()
		_set_phase(Phase.ENDED)
		storm.active = false
		finished.emit(winner, player.placement if not player.alive else 1)


## Hits, for the trackers (yours: StatBook; the bots' own: RivalBook) and
## your boons (Boons: bleeding, Carrot Juice, Bramble Coat's thorns).
func _on_critter_damaged(victim: Node, info: DamageInfo) -> void:
	if player == null or not victim is Critter or info.attacker == victim:
		return
	var blast := info.kind == DamageInfo.Kind.EXPLOSION
	var thorns := info.kind == DamageInfo.Kind.BLEED
	if info.attacker == player:
		if not thorns:
			StatBook.note_hit(info.weapon_id, info.amount, info.headshot, blast)
			_boons_on_hit(victim as Critter, info)
	elif info.attacker is Critter and critters.has(info.attacker):
		RivalBook.note_bot_hit(info.attacker.display_name, info.weapon_id, info.amount, info.headshot, blast)
		if victim == player and not thorns and Boons.has("bramble_coat") and (info.attacker as Critter).alive:
			var back := DamageInfo.make(info.amount * Boons.value("bramble_coat") / 100.0, DamageInfo.Kind.BLEED, player, &"bramble")
			back.position = (info.attacker as Critter).get_chest_position()
			(info.attacker as Critter).take_damage(back)


func _boons_on_hit(v: Critter, info: DamageInfo) -> void:
	if Boons.held.is_empty():
		return
	var dps := Boons.value("thorny")
	if info.mutated and Boons.has("briar_shards"):
		dps = maxf(dps, Boons.SPLINTER_DPS)
	if dps > 0.0 and v.alive:
		v.bleed(dps, Boons.BLEED_SECONDS, player, info.weapon_id)
	if Boons.has("carrot_juice") and player.alive:
		player.health = minf(player.max_health, player.health + info.amount * Boons.value("carrot_juice") / 100.0)


## Your beat-down, for your boons: Splinters, Carrot Frenzy, Second Breakfast.
func _boons_on_kill(c: Critter) -> void:
	if Boons.has("splinters"):
		var reach := Boons.value("splinters")
		for o in alive_critters():
			if o != player and o != c and o.global_position.distance_to(c.global_position) <= reach:
				o.bleed(Boons.SPLINTER_DPS, Boons.BLEED_SECONDS, player, &"bramble")
	if Boons.has("frenzy"):
		player.frenzy_t = maxf(player.frenzy_t, Boons.value("frenzy"))
	if Boons.has("second_breakfast"):
		player.health = minf(player.max_health, player.health + Boons.DUO_HEAL)


## The bot that beat you down takes the gun you were holding (it'll be back
## with it, until you beat it down again).
func _steal_gun(killer: Critter) -> void:
	var held: Array = player.last_weapons
	var w: WeaponInstance = null
	if player.current_slot >= 0 and player.current_slot < held.size():
		w = held[player.current_slot]
	if w == null:
		for g in held:
			if g and (w == null or g.rarity > w.rarity):
				w = g
	if w == null or not RivalBook.took_gun(killer.display_name).is_empty():
		return
	var d := w.to_dict()
	d["skin"] = Workshop.look("skin")
	RivalBook.note_took_gun(killer.display_name, d)
	player.set_meta(&"stolen", w)
	Events.headline.emit("%s took your %s. Beat them down to get it back." % [killer.display_name, w.display_name()])


## Scars: what you did to a bot when you beat it down, it comes back wearing.
func _scar(c: Critter, info: DamageInfo) -> void:
	var got := []
	if c.visual.dismembered.has(&"head") or info.headshot:
		got.append("eye_patch")
	for role in c.visual.dismembered:
		var r := String(role)
		if r.ends_with("arm"):
			got.append("arm_" + r.left(1))
		elif r.ends_with("leg"):
			got.append("leg_" + r.left(1))
	if info.kind == DamageInfo.Kind.EXPLOSION:
		got.append("singed")
	var fresh := got.filter(func(sc): return RivalBook.add_scar(c.display_name, sc))
	if not fresh.is_empty():
		Events.headline.emit("%s will remember that: %s." % [c.display_name, RivalBook.SCARS[fresh[0]].text])


## You won the nemesis hunt: its signature gun drops where it fell.
func _nemesis_beaten(c: Critter) -> void:
	nemesis = null
	var sig := RivalBook.signature_gun(c.display_name)
	RivalBook.note_signature_won(c.display_name)
	if sig:
		Pickup.spawn(Despawner.debris_parent(c), Pickup.weapon_spec(sig), c.global_position + Vector3.UP * 0.8, Vector3(0, 4.0, 0))
		Events.rival_news.emit("NEMESIS DOWN!", "%s dropped their signature gun: %s (%s)" % [c.display_name, sig.display_name(), Boons.name_of(sig.mutation)])


## The nemesis hunt: it knows roughly where you are every NEMESIS_EVERY seconds.
func _hunt_you(delta: float) -> void:
	if nemesis == null or not is_instance_valid(nemesis) or not nemesis.alive or player.state != Critter.State.GROUND:
		return
	if not _nemesis_announced:
		_nemesis_announced = true
		Events.announce.emit("NEMESIS HUNT", "%s is hunting you. Beat them down for their signature gun." % nemesis.display_name)
	_nemesis_t += delta
	if _nemesis_t >= NEMESIS_EVERY:
		_nemesis_t = 0.0
		var brain := nemesis.get_node_or_null("AIBrain") as AIBrain
		if brain:
			brain.hunt(player.global_position + Vector3(extra_rng.randf_range(-8, 8), 0, extra_rng.randf_range(-8, 8)), 18.0)


## A run's goal: made it? (Placing in the top N is certain once only N are left.)
func _check_run_goal() -> void:
	if run_goal.is_empty() or run_goal_met:
		return
	if player.kills >= int(run_goal.kills) or _alive_cache <= int(run_goal.top):
		run_goal_met = true
		Events.announce.emit("GOAL MET!", "The run goes on. Every place higher is a bonus.")


## The bots' carrots fired, for their trackers (yours count in Critter._fire).
func _on_shot_fired(shooter: Node, _origin: Vector3, weapon_id: StringName) -> void:
	if player and shooter != player and shooter is Critter and critters.has(shooter):
		var w := WeaponDB.get_weapon(weapon_id)
		RivalBook.note_bot_shot(shooter.display_name, w.pellets if w else 1)


func _rival_names() -> Array:
	return rivals_here.filter(func(r): return is_instance_valid(r)).map(func(r): return r.display_name)


## A bot says something in its own voice ("spot" taunts once a match).
func taunt(c: Critter, event: String) -> void:
	if c == null or not is_instance_valid(c) or c == player or player == null:
		return
	var key := "%s|%s" % [c.display_name, event]
	if event == "spot" and _taunted.has(key):
		return
	_taunted[key] = true
	var you := String(player.def.display_name)
	# a radical bot sounds it; otherwise its own voice, or now and then its own line
	var said := Cast.heat_line(c.display_name, event, you, rng) if rng.randf() < 0.75 else ""
	if said == "" and event == "spot" and rng.randf() < 0.4:
		said = Cast.member(c.display_name).get("says", "")
	if said == "":
		said = RivalBook.line(c.display_name, event, you, rng)
	Events.taunt.emit(c, said)


func alive_critters() -> Array[Critter]:
	var out: Array[Critter] = []
	for c in critters:
		if is_instance_valid(c) and c.alive:
			out.append(c)
	return out


## The director paces how deadly the bots' scraps with each other are: while
## the lobby is thinning faster than this curve (a few at first, then a steady
## share over about seven minutes), bots hit each other softer
## (AIBrain.HELD_DAMAGE) and most fights end with the loser running off.
## Without it half a full lobby beat each other down within two minutes of
## landing, before the player ever met them. It never stops a fight starting
## (bots that met and walked on by read as teams), and never softens anyone's
## hits on the player.
const BRAWL_START := 0.08
const BRAWL_SECONDS := 420.0
var _play_start := -1.0

func bots_may_kill() -> bool:
	if phase == Phase.LOADING or phase == Phase.ENDED:
		return true
	# (the curve starts once everyone's down; until then, early landers
	# scrapping on the ground get the starting share)
	var played := _clock - _play_start if _play_start >= 0.0 else 0.0
	var allowed := total * clampf(BRAWL_START + played / BRAWL_SECONDS, 0.0, 0.95)
	return float(total - _alive_cache) < allowed


func _set_phase(p: Phase) -> void:
	if p == Phase.PLAYING and _play_start < 0.0:
		_play_start = _clock
	phase = p
	phase_changed.emit(p)
	Events.match_phase_changed.emit(p)


# ---- storm queries used by the AI ----------------------------------------------------------

func storm_threat(pos: Vector3) -> float:
	return storm.threat(pos) if storm and storm.active else 0.0


func safe_point_for(pos: Vector3) -> Vector3:
	return storm.safe_point(pos) if storm and storm.active else pos


func safe_center() -> Vector2:
	return storm.next_center if storm and storm.active else Vector2.ZERO


func safe_radius() -> float:
	return storm.next_radius if storm and storm.active else island.terrain.island_radius
