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
var _supply_t := 0.0
const SUPPLY_INTERVAL := 75.0


func setup(world_root_: Node3D, island_: Island, opponents: int, difficulty: int, seed_: int, pace_ := 1.0) -> void:
	world_root = world_root_
	island = island_
	pace = pace_
	rng.seed = seed_ * 7 + 1
	storm = Storm.new()
	storm.name = "Storm"
	world_root.add_child(storm)
	Events.critter_died.connect(_on_critter_died)
	_spawn_loot()
	player = _spawn_critter(load("res://data/critters/bun.tres"), "Bun")
	var pc := PlayerController.new()
	pc.name = "PlayerController"
	player.add_child(pc)
	var defs := _available_defs()
	var used_names := {}
	for i in opponents:
		var def: CritterDef = _pick_def(defs)
		var n := _unique_name(def, used_names)
		var c := _spawn_critter(def, n)
		var brain := AIBrain.new()
		brain.name = "AIBrain"
		brain.island = island
		brain.match_manager = self
		brain.skill = clampf(_skill_for(difficulty) + rng.randf_range(-0.12, 0.12), 0.05, 0.98)
		c.add_child(brain)
	total = critters.size()
	_alive_cache = total
	Events.alive_count_changed.emit(total, total)


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
	c.name = "Critter_%s" % display.replace(" ", "_")
	world_root.add_child(c)
	critters.append(c)
	return c


func _spawn_loot() -> void:
	for lp in island.loot_points:
		var pos: Vector3 = lp.pos
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
			var w := WeaponInstance.new(WeaponDB.random_weapon(rng), Rarity.roll(Rarity.FLOOR_WEIGHTS, rng))
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


## Board everyone and launch the balloon.
func begin_drop() -> void:
	dropship = Dropship.new()
	dropship.name = "Dropship"
	world_root.add_child(dropship)
	dropship.setup(island.terrain.island_radius, rng)
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
			brain.drop_spot = spot
			brain.drop_progress = clampf(dropship.progress_nearest(spot) + rng.randf_range(-0.06, 0.03), 0.02, 0.98)
	dropship.launch()
	_set_phase(Phase.DROPPING)


func _process(delta: float) -> void:
	if phase == Phase.PLAYING:
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
			storm.start(island, island.terrain.island_radius + 50.0, pace)
			_set_phase(Phase.PLAYING)


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
	if c == player:
		player_eliminated.emit(c.placement, info.attacker as Critter)
	if alive.size() <= 1 and phase != Phase.ENDED:
		var winner: Critter = alive[0] if alive.size() == 1 else null
		if winner:
			winner.placement = 1
		_set_phase(Phase.ENDED)
		storm.active = false
		finished.emit(winner, player.placement if not player.alive else 1)


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
