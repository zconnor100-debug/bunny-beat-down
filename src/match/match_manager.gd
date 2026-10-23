class_name MatchManager
extends Node
## Runs one battle royale: spawns the field, flies the balloon, starts the
## Briar, tracks eliminations and declares the last critter standing.

signal phase_changed(phase: Phase)
signal finished(winner: Critter, player_placement: int)
signal player_eliminated(placement: int, killer: Critter)

enum Phase { LOADING, DROPPING, PLAYING, ENDED }

const CRITTER_DEFS := ["bandit_bunny", "squirrel", "fox", "raccoon", "frog", "beaver", "hamster"]

var phase := Phase.LOADING
var island: Island
var storm: Storm
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


func setup(world_root_: Node3D, island_: Island, opponents: int, difficulty: int, seed_: int, pace_ := 1.0) -> void:
	world_root = world_root_
	island = island_
	pace = pace_
	# this match's Burrow modifiers and perks that act on everyone
	Critter.glass_cannon = Burrow.modifier_on("glass_cannon")
	CritterVisual.name_tag_range_scale = 2.0 if Burrow.has_perk("hawk_eye") else 1.0
	AIBrain.player_stealth = 0.6 if Burrow.has_perk("light_step") else 1.0
	rng.seed = seed_ * 7 + 1
	var moods := Storm.VARIANTS.keys().filter(func(k): return k != "classic")
	briar_variant = "classic" if rng.randf() < 0.25 else moods[rng.randi() % moods.size()]
	storm = Storm.new()
	storm.name = "Storm"
	world_root.add_child(storm)
	Events.critter_died.connect(_on_critter_died)
	var d := clampi(difficulty, 0, 2)
	AIBrain.player_attack_slots = [1, 2, 3][d]
	AIBrain.damage_to_player = [0.45, 0.65, 0.85][d]
	_spawn_loot()
	var defs := _available_defs()
	var used_names := {}
	# your rivals always come back for more (up to three of them)
	var roster := []
	for r in RivalBook.rivals():
		if roster.size() >= mini(3, opponents):
			break
		for rd in defs:
			if String(rd.id) == r[1] and Array(rd.names).has(r[0]):
				roster.append([rd, r[0]])
				used_names[r[0]] = true
	while roster.size() < opponents:
		var def: CritterDef = _pick_def(defs)
		roster.append([def, _unique_name(def, used_names)])
	for entry in roster:
		var def: CritterDef = entry[0]
		var n: String = entry[1]
		var c := _spawn_critter(def, n)
		var rival := RivalBook.is_rival(n)
		c.visual.set_enemy_highlight(n, rival)
		if rival:
			rivals_here.append(c)
		RivalBook.note_meeting(n, String(def.id))
		var skins := def.skins()
		c.visual.apply_skin(String(skins[rng.randi() % skins.size()].get("id", "default")))
		var brain := AIBrain.new()
		brain.name = "AIBrain"
		brain.island = island
		brain.match_manager = self
		AIBrain.player_style = PlayerProfile.fighting_style()
		brain.personality = RivalBook.personality_of(n)
		brain.rival = rival
		var p: Dictionary = RivalBook.PERSONALITIES[brain.personality]
		brain.skill = clampf(_skill_for(difficulty) + rng.randf_range(-0.12, 0.12) + float(p.skill) + (0.06 if rival else 0.0), 0.05, 0.98)
		c.add_child(brain)
	RivalBook.save()
	total = critters.size() + 1   # + the player, who joins after picking a critter
	_alive_cache = total
	Events.alive_count_changed.emit(total, total)


## The player's critter joins once they've picked it on the loading screen.
func spawn_player(def: CritterDef, skin_id: String) -> Critter:
	var display := "Bun" if def.id == &"bun" else "You (%s)" % def.display_name
	player = _spawn_critter(def, display)
	player.visual.apply_skin(skin_id)
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
	return player


## The perks you took into this match from the Burrow.
func _apply_perks(p: Critter) -> void:
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


func _available_defs() -> Array[CritterDef]:
	var out: Array[CritterDef] = []
	for id in CRITTER_DEFS:
		var d: CritterDef = load("res://data/critters/%s.tres" % id)
		if d:
			out.append(d)
	return out


func _pick_def(defs: Array[CritterDef]) -> CritterDef:
	var total_w := 0.0
	for d in defs:
		total_w += d.spawn_weight
	var r := rng.randf() * total_w
	for d in defs:
		r -= d.spawn_weight
		if r <= 0.0:
			return d
	return defs.back()


func _unique_name(def: CritterDef, used: Dictionary) -> String:
	var options: Array = Array(def.names) if not def.names.is_empty() else [def.display_name]
	options.shuffle()
	for n in options:
		if not used.has(n):
			used[n] = true
			return n
	var base: String = options[0]
	var k := 2
	while used.has("%s %d" % [base, k]):
		k += 1
	var n2 := "%s %d" % [base, k]
	used[n2] = true
	return n2


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
	return c


func _spawn_loot() -> void:
	for lp in island.loot_points:
		var pos: Vector3 = lp.pos
		if lp.has("chest"):
			var chest := TreasureChest.new(lp.chest == "golden")
			chest.rng.seed = rng.randi()
			world_root.add_child(chest)
			chest.global_position = pos
			chest.rotation.y = lp.get("yaw", 0.0)
			continue
		if lp.crate:
			var crate := LootCrate.new()
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
	for c in critters:
		dropship.board(c)
		var brain := c.get_node_or_null("AIBrain") as AIBrain
		if brain:
			# pick a landing spot (POIs are popular) and jump when the balloon is closest
			var spot := island.random_land_point(2.5)
			if rng.randf() < 0.65 and not island.pois.is_empty():
				var poi: Dictionary = island.pois[rng.randi() % island.pois.size()]
				var cc: Vector2 = poi.center + Vector2(rng.randf_range(-12, 12), rng.randf_range(-12, 12))
				spot = Vector3(cc.x, island.terrain.height_at(cc.x, cc.y), cc.y)
			if not fav_poi.is_empty() and rng.randf() < 0.3:
				var fc: Vector2 = fav_poi.center + Vector2(rng.randf_range(-10, 10), rng.randf_range(-10, 10))
				spot = Vector3(fc.x, island.terrain.height_at(fc.x, fc.y), fc.y)
			brain.drop_spot = spot
			brain.drop_progress = clampf(dropship.progress_nearest(spot) + rng.randf_range(-0.06, 0.03), 0.02, 0.98)
	dropship.launch()
	_set_phase(Phase.DROPPING)


func _process(delta: float) -> void:
	_clock += delta
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


func _on_critter_died(victim: Node, info: DamageInfo) -> void:
	var c := victim as Critter
	if c == null or not critters.has(c):
		return
	var alive := alive_critters()
	c.placement = alive.size() + 1
	_alive_cache = alive.size()
	Events.alive_count_changed.emit(alive.size(), total)
	var killer := info.attacker as Critter
	if c == player and killer and killer != player:
		if RivalBook.note_you_died_to(killer.display_name, String(killer.def.id)):
			killer.set_meta(&"new_rival", true)
		taunt(killer, "kill")
	elif killer == player and c != player:
		_note_player_kill(info)
		if RivalBook.note_you_beat(c.display_name, String(c.def.id)):
			revenges += 1
			Events.rival_news.emit("REVENGE!", "You beat down your rival %s — now %s" % [c.display_name, RivalBook.score(c.display_name)])
		if c.display_name in _rival_names() or rng.randf() < 0.35:
			taunt(c, "lose")
	if c == player:
		player_eliminated.emit(c.placement, info.attacker as Critter)
	if alive.size() <= 1 and phase != Phase.ENDED:
		var winner: Critter = alive[0] if alive.size() == 1 else null
		if winner:
			winner.placement = 1
		_set_phase(Phase.ENDED)
		storm.active = false
		finished.emit(winner, player.placement if not player.alive else 1)


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
	Events.taunt.emit(c, RivalBook.line(c.display_name, event, String(player.def.display_name), rng))


func alive_critters() -> Array[Critter]:
	var out: Array[Critter] = []
	for c in critters:
		if is_instance_valid(c) and c.alive:
			out.append(c)
	return out


func _set_phase(p: Phase) -> void:
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
