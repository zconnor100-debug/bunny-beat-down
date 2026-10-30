class_name MissionDirector
extends Node
## A Kernel Hunt mission as it's played (KernelHunt; MatchManager mode
## "kernel"). The prologue, "Days Since Brutus": you and the Barn Rangers
## start at the Big Red Barn (no balloon), each ranger at a post round it, and
## the Touched come in WAVES out of the Carrot Patch (and later round the
## sides too), marching on the Barn and fighting anyone they see. Every Touched
## standing in the Barn's yard wears the Barn down (`barn`, 100 to nothing:
## then they have it). Between waves the rangers patch it up and restock, and
## a crate comes down by the Barn. Beat the last wave and something roars at
## Boulder Bluff (MissionOutro): the tally on the Barn's door goes back to
## zero, and the Barn has held. Lose the Barn, or everyone on your side, and
## it hasn't.
##
## The Touched are critters the Starfall Acorn's light has got into: any
## species, gold-green veins glowing through their fur (the Touched coat),
## silent. They aren't the cast, so nobody keeps score of them (RivalBook).

enum Stage { BRIEFING, WAVE, BREATHER, OUTRO, OVER }

const SPECIES := ["bandit_bunny", "squirrel", "fox", "raccoon", "frog", "beaver", "hamster"]
const YARD := 22.0             ## metres from the Barn's middle that are its yard
const WEAR := 0.9              ## of the Barn, each second, for each Touched in the yard...
const WEAR_MOST := 6           ## ...counting this many at most
const PATCH_UP := 20.0         ## patched back between waves
const FIRST_WAVE := 20.0       ## seconds before the first wave comes
const BREATHER := 24.0         ## seconds between waves
const COME_FROM := 135.0       ## metres out a wave starts from (round the sides: the Carrot Patch's own distance)
const SKILL := [0.3, 0.5, 0.72]                ## the Touched's aim, by difficulty
const GIANT_SCALE := 2.5
const GIANT_HEALTH := [500.0, 700.0, 950.0]
const RANGER_AMMO := 4         ## pickups' worth of ammo a ranger is restocked with
const SAY_EVERY := {"ky": 14.0, "kd": 6.0, "ks": 999.0, "kg": 999.0}
const TALLY_DAYS := 9

var match_manager: MatchManager
var island: Island
var mission := "prologue"
var stage := Stage.BRIEFING
var wave := 0                  ## the wave on now, or the last one (1-based)
var barn := 100.0              ## how much of the Barn the Touched haven't worn away
var barn_pos := Vector3.ZERO
var patch_pos := Vector3.ZERO
var bluff_pos := Vector3.ZERO
var barn_building: Building
var tally: TallySign
var rangers: Array[Critter] = []
var giant: Critter
var spawned := 0               ## Touched sent so far
var _t := 0.0                  ## seconds into the stage
var _clock := 0.0
var _rng := RandomNumberGenerator.new()
var _posts: Array = []         # [post, watch] for each ranger
var _said := {}                # prefix -> clock it was last said
var _sighted := false
var _giant_called := false
var _lost_said := false
var _outro: MissionOutro
var _report := {}


func _init() -> void:
	name = "MissionDirector"


## Find the Barn, the Carrot Patch and Boulder Bluff on the island, and bring
## the rangers (parked till begin()).
func setup(mm: MatchManager) -> void:
	match_manager = mm
	island = mm.island
	_rng.seed = mm.rng.seed * 3 + 11
	var barn_poi := _poi("Big Red Barn", "barn")
	barn_pos = _ground(barn_poi.get("center", Vector2.ZERO))
	if not barn_poi.is_empty() and not (barn_poi.buildings as Array).is_empty():
		barn_building = barn_poi.buildings[0]
		barn_pos = barn_building.global_position
	var patch := _poi("Carrot Patch", "carrot_patch")
	patch_pos = _ground(patch.center) if not patch.is_empty() else barn_pos + _flat(-barn_pos).normalized() * COME_FROM
	var bluff := _poi("Boulder Bluff", "boulders")
	bluff_pos = _ground(bluff.center) if not bluff.is_empty() else barn_pos - _flat(patch_pos - barn_pos).normalized() * 200.0
	for n in KernelHunt.RANGERS:
		_spawn_ranger(n)
	_plan_posts()
	_hang_tally()


## The mission starts: everyone on their feet at the Barn, armed.
func begin() -> void:
	var fwd := _flat(patch_pos - barn_pos).normalized()
	for i in rangers.size():
		var r := rangers[i]
		var post: Vector3 = _posts[i % _posts.size()][0]
		var out := _flat(post - barn_pos).normalized()
		r.place_at(post, atan2(-out.x, -out.z))
		var brain := r.get_node_or_null("AIBrain") as AIBrain
		if brain:
			brain.hold(post, _posts[i % _posts.size()][1])
	var p := match_manager.player
	if p:
		p.place_at(_ground_at(barn_pos + fwd * 26.0), atan2(-fwd.x, -fwd.z))   # (out in front of the rangers' line)
		p.give_weapon(WeaponInstance.new(WeaponDB.get_weapon(&"carrot_rifle"), Rarity.Tier.PRIZE))
		p.give_weapon(WeaponInstance.new(WeaponDB.get_weapon(&"carrot_shotgun"), Rarity.Tier.GARDEN))
		for w in p.inventory.weapons:
			if w:
				p.inventory.add_ammo(w.data.ammo_type, Inventory.AMMO_PICKUP[w.data.ammo_type] * 3)
		p.inventory.clovers = maxi(p.inventory.clovers, 2)
	stage = Stage.BRIEFING
	_t = 0.0
	match_manager._set_phase(MatchManager.Phase.PLAYING)
	get_tree().create_timer(6.0, false).timeout.connect(func(): _shout("kt", 0))


func _process(delta: float) -> void:
	if match_manager == null or match_manager.phase != MatchManager.Phase.PLAYING:
		return
	_clock += delta
	_t += delta
	match stage:
		Stage.BRIEFING:
			if _t >= FIRST_WAVE:
				_start_wave(1)
		Stage.WAVE:
			_wear(delta)
			_watch_wave()
			if stage == Stage.WAVE and touched_left() == 0:
				_wave_held()
		Stage.BREATHER:
			if _t >= BREATHER:
				_start_wave(wave + 1)


# ---- waves -------------------------------------------------------------------------------------

func waves() -> int:
	return KernelHunt.WAVES.size()


## The Touched still standing.
func touched_left() -> int:
	return match_manager.alive_critters().filter(func(c): return c.team == 2).size()


## Seconds till the next wave (-1: one's on, or there are no more).
func next_wave_in() -> float:
	match stage:
		Stage.BRIEFING:
			return maxf(0.0, FIRST_WAVE - _t)
		Stage.BREATHER:
			return maxf(0.0, BREATHER - _t)
	return -1.0


## Touched in the Barn's yard right now (they're wearing it down).
func in_yard() -> int:
	var n := 0
	for c in match_manager.alive_critters():
		if c.team == 2 and c.state == Critter.State.GROUND and _flat(c.global_position - barn_pos).length() < YARD:
			n += 1
	return n


func _start_wave(n: int) -> void:
	wave = n
	stage = Stage.WAVE
	_t = 0.0
	_lost_said = false
	var spec: Dictionary = KernelHunt.WAVES[n - 1]
	var count := maxi(2, roundi(float(spec.count) * float(KernelHunt.COUNT_SCALE[clampi(match_manager._difficulty, 0, 2)])))
	var from: Array = spec.from
	for i in count:
		var side: String = from[i % from.size()]
		_spawn_touched(_wave_spot(side), spec.guns[_rng.randi() % spec.guns.size()])
	if spec.get("giant", false):
		giant = _spawn_touched(_wave_spot("patch"), &"carrot_lmg", true)
		count += 1
	var where := "out of the Carrot Patch" if from.size() == 1 else ("out of the Carrot Patch and round the side" if from.size() == 2 \
		else "from the Carrot Patch and round both sides")
	Events.announce.emit("WAVE %d OF %d" % [n, waves()], "%d Touched, coming %s." % [count, where])
	Events.alive_count_changed.emit(match_manager.alive_critters().size(), match_manager.total)
	get_tree().create_timer(2.5, false).timeout.connect(func(): _shout("kw", 0 if n == 1 else 1))


## Where a wave's Touched start: by the Carrot Patch, or out to one side.
func _wave_spot(side: String) -> Vector3:
	var fwd := _flat(patch_pos - barn_pos).normalized()
	var at := patch_pos
	if side != "patch":
		var turn := deg_to_rad(_rng.randf_range(70.0, 100.0)) * (1.0 if side == "left" else -1.0)
		at = barn_pos + fwd.rotated(Vector3.UP, turn) * COME_FROM
	var p := island.random_land_point(2.0, Vector2(at.x, at.z), 14.0) if island else at
	return p if p != Vector3.INF else at


func _wear(delta: float) -> void:
	var n := in_yard()
	if n <= 0:
		return
	barn = maxf(0.0, barn - WEAR * mini(n, WEAR_MOST) * delta)
	if _say_ok("ky"):
		_shout("ky")
	if barn < 30.0 and not _lost_said:
		_lost_said = _shout("kb", 0)
	if barn <= 0.0:
		Events.announce.emit("THE BARN HAS FALLEN", "The Touched have the Big Red Barn.")
		end(false)


func _watch_wave() -> void:
	for c in match_manager.alive_critters():
		if c.team != 2:
			continue
		var d := _flat(c.global_position - barn_pos).length()
		if not _sighted and wave == 1 and d < 75.0:
			_sighted = _shout("ks", 0)
		if c == giant and not _giant_called and d < 85.0:
			_giant_called = _shout("kg")


func _wave_held() -> void:
	_shout("kc", 0 if wave >= waves() else 1)
	if wave >= waves():
		stage = Stage.OUTRO
		_t = 0.0
		get_tree().create_timer(2.5, false).timeout.connect(_play_outro)
		return
	stage = Stage.BREATHER
	_t = 0.0
	barn = minf(100.0, barn + PATCH_UP)
	for r in rangers:
		if is_instance_valid(r) and r.alive:
			_restock(r)
	_drop_crate()
	Events.announce.emit("WAVE %d HELD" % wave, "The rangers patch up the Barn. The next wave comes in %d seconds." % int(BREATHER))


## A crate down by the Barn, on the side away from the Carrot Patch.
func _drop_crate() -> void:
	var back := _flat(barn_pos - patch_pos).normalized()
	var at := barn_pos + back * 20.0 + back.cross(Vector3.UP) * _rng.randf_range(-8.0, 8.0)
	var spot := _ground(Vector2(at.x, at.z))
	var drop := SupplyDrop.new()
	drop.landing = spot
	drop.rng.seed = _rng.randi()
	match_manager.world_root.add_child(drop)
	drop.global_position = spot + Vector3.UP * 70.0
	Events.supply_drop_incoming.emit(spot)


# ---- the end -------------------------------------------------------------------------------------

## The game plays the ending with your camera, HUD and controls (game.gd:
## MatchManager.mission_outro); with no game round it (a test), it plays here.
func _play_outro() -> void:
	if stage != Stage.OUTRO:
		return
	if match_manager.get_signal_connection_list(&"mission_outro").is_empty():
		play_outro()
	else:
		match_manager.mission_outro.emit(self)


## The ending (MissionOutro), then the mission's over: held.
func play_outro(rig: CameraRig = null, hud: CanvasLayer = null, pc: PlayerController = null) -> MissionOutro:
	_outro = MissionOutro.new(self, rig, hud, pc)
	_outro.finished.connect(func(): end(true))
	add_child(_outro)
	return _outro


## How it went, for the profile (KernelHunt.note_result), the end screen and
## the Gazette.
func report() -> Dictionary:
	if not _report.is_empty():
		return _report
	var home := rangers.filter(func(r): return is_instance_valid(r) and r.alive).size()
	return {"mission": mission, "won": false, "time": _clock, "barn": roundi(barn), "rangers": home,
		"rangers_home": rangers.filter(func(r): return is_instance_valid(r) and r.alive).map(func(r): return r.display_name),
		"touched": spawned - touched_left(), "wave": wave, "you_standing": match_manager.player != null and match_manager.player.alive,
		"difficulty": match_manager._difficulty}


func end(won: bool) -> void:
	if stage == Stage.OVER:
		return
	stage = Stage.OVER
	_report = report()
	_report["won"] = won
	KernelHunt.note_result(mission, _report)
	if won:
		WarrenSim.print_extra("kernel", WarrenSim.mission_news(_report))   # (the Gazette holds the front page)
	match_manager.end_mission(won)


## Everyone on your side is down: the Touched have the Barn.
func check_sides() -> void:
	if stage == Stage.OVER or stage == Stage.OUTRO:
		return
	if match_manager.team_counts()[1] == 0:
		Events.announce.emit("EVERYONE'S DOWN", "There's nobody left to hold the Barn.")
		end(false)


## Someone went down (MatchManager routes every beat-down in a mission here).
func critter_down(c: Critter, _info: DamageInfo) -> void:
	if rangers.has(c) and _say_ok("kd"):
		_shout("kd", 0)
	if c == giant:
		Events.headline.emit("The Touched giant is down.")
	check_sides()


# ---- who's here ------------------------------------------------------------------------------------

func _spawn_ranger(n: String) -> Critter:
	var def: CritterDef = load("res://data/critters/%s.tres" % String(Cast.member(n).get("species", "beaver")))
	var c := match_manager._spawn_critter(def, n)
	c.team = 1
	if Outfits.look_of(n).is_empty():
		c.visual.apply_skin("default")
	else:
		Outfits.dress(c, n)
	c.visual.set_ally_tag(n)
	var brain := AIBrain.new()
	brain.name = "AIBrain"
	brain.island = island
	brain.match_manager = match_manager
	brain.personality = RivalBook.personality_of(n)
	var traits := Cast.traits_for(n)
	for k in ["hunts_you", "no_slot", "defiant"]:
		traits.erase(k)   # (on your side: none of that)
	brain.traits = traits
	brain.skill = clampf(MatchManager._skill_for(match_manager._difficulty) + 0.1, 0.2, 0.95)
	c.add_child(brain)
	var gun := WeaponDB.get_weapon(StringName(Cast.member(n).get("weapon", "carrot_rifle")))
	c.give_weapon(WeaponInstance.new(gun if gun else WeaponDB.get_weapon(&"carrot_rifle"), Rarity.Tier.PRIZE))
	_restock(c)
	c.inventory.clovers = 2
	c.inventory.grenades = 1
	rangers.append(c)
	return c


func _restock(c: Critter) -> void:
	for w in c.inventory.weapons:
		if w:
			c.inventory.add_ammo(w.data.ammo_type, Inventory.AMMO_PICKUP[w.data.ammo_type] * RANGER_AMMO)


## One of the Touched, at `at`, carrying `gun`, marching on the Barn (and
## fighting anyone it sees on the way): a giant one, with `giant`.
func _spawn_touched(at: Vector3, gun: StringName, is_giant := false) -> Critter:
	var species: String = "beaver" if is_giant else SPECIES[_rng.randi() % SPECIES.size()]
	var def: CritterDef = load("res://data/critters/%s.tres" % species)
	if is_giant:
		def = def.duplicate() as CritterDef
		def.body_scale *= GIANT_SCALE
		def.max_health = GIANT_HEALTH[clampi(match_manager._difficulty, 0, 2)]
		def.move_speed *= 0.85
		def.sprint_speed *= 0.8
	var title := ("Touched Giant" if is_giant else "Touched %s" % def.display_name)
	var c := match_manager._spawn_critter(def, title)
	c.team = 2
	var skins := def.skins()
	c.visual.apply_skin(String(skins[_rng.randi() % skins.size()].get("id", "default")))
	c.place_at(at, atan2(-(barn_pos - at).x, -(barn_pos - at).z))
	c.visual.set_enemy_highlight(title)
	if c.visual.name_tag:
		c.visual.name_tag.modulate = Workshop.COLORS["kernel"]
		c.visual.name_tag.text = "▼ %s" % title.to_upper() if is_giant else c.visual.name_tag.text
	Outfits.wear_coat(c.visual, "touched")
	c.give_weapon(WeaponInstance.new(WeaponDB.get_weapon(gun), Rarity.Tier.PRIZE if is_giant else Rarity.Tier.GARDEN))
	for w in c.inventory.weapons:
		if w:
			c.inventory.add_ammo(w.data.ammo_type, Inventory.AMMO_PICKUP[w.data.ammo_type] * 4)
	var brain := AIBrain.new()
	brain.name = "AIBrain"
	brain.island = island
	brain.match_manager = match_manager
	brain.personality = "touched"
	brain.traits = {"break_off": 0.0, "heal_at": 0.0, "spot": 1.3, "fight_range": 70.0, "settle": 0.0, "sticky": 0.4}
	brain.skill = SKILL[clampi(match_manager._difficulty, 0, 2)] + (0.15 if is_giant else 0.0)
	brain.hold_low = false
	brain.hold_run = false   # (they march: the open ground is where to stop them)
	c.add_child(brain)
	brain.hold(_yard_spot(at), barn_pos)
	spawned += 1
	return c


## Somewhere in the Barn's yard, on the side `from` is (where a Touched stands its ground).
func _yard_spot(from: Vector3) -> Vector3:
	var dir := _flat(from - barn_pos).normalized().rotated(Vector3.UP, _rng.randf_range(-0.9, 0.9))
	var at := barn_pos + dir * _rng.randf_range(8.0, 17.0)
	return _ground(Vector2(at.x, at.z))


## The rangers' posts round the Barn: four on the Carrot Patch side, one out
## each side, one round the back, each watching outward.
func _plan_posts() -> void:
	var fwd := _flat(patch_pos - barn_pos).normalized()
	var side := fwd.cross(Vector3.UP)
	var spots := [fwd * 18.0 - side * 9.0, fwd * 18.0 - side * 3.0, fwd * 18.0 + side * 3.0, fwd * 18.0 + side * 9.0,
		side * 18.0 + fwd * 4.0, -side * 18.0 + fwd * 4.0, -fwd * 17.0]
	_posts.clear()
	for s in spots:
		var p := _ground(Vector2(barn_pos.x + s.x, barn_pos.z + s.z))
		var out := _flat(p - barn_pos).normalized()
		_posts.append([p, p + out * 30.0 + Vector3.UP * 1.0])


## The tally, on the Barn's open door at the Carrot Patch end.
func _hang_tally() -> void:
	tally = TallySign.new(TALLY_DAYS)
	if barn_building == null:
		match_manager.world_root.add_child(tally)
		tally.global_position = barn_pos + Vector3.UP * 2.8
		return
	var local := barn_building.global_transform.basis.inverse() * (patch_pos - barn_pos)
	var zs := 1.0 if local.z >= 0.0 else -1.0
	barn_building.add_child(tally)
	tally.position = Vector3(5.65 * zs, barn_building.floor_y + 2.7, zs * 12.32)
	tally.rotation.y = 0.0 if zs > 0.0 else PI


# ---- the rangers talk --------------------------------------------------------------------------------

func _say_ok(prefix: String) -> bool:
	return _clock - float(_said.get(prefix, -INF)) >= float(SAY_EVERY.get(prefix, 3.0))


## A ranger says one of the Kernel Hunt's lines (Cast.KERNEL_LINES): line `i`
## of `prefix` (or any), by `who` (or the ranger nearest you). True if said.
func _shout(prefix: String, i := -1, who: Critter = null) -> bool:
	var lines: Array = Cast.KERNEL_LINES.get(prefix, [])
	if lines.is_empty():
		return false
	if who == null:
		who = ranger_near(match_manager.player.global_position if match_manager.player and match_manager.player.alive else barn_pos)
	if who == null:
		return false
	var k := i if i >= 0 else _rng.randi() % lines.size()
	_said[prefix] = _clock
	match_manager._say(who, Cast.say("%s.%d" % [prefix, k], lines[k]))
	return true


## The ranger still standing nearest `at` (null if there's none), not `but`.
func ranger_near(at: Vector3, but: Critter = null) -> Critter:
	var best: Critter = null
	var best_d := INF
	for r in rangers:
		if not is_instance_valid(r) or not r.alive or r == but:
			continue
		var d := r.global_position.distance_to(at)
		if d < best_d:
			best_d = d
			best = r
	return best


# ---- the map ------------------------------------------------------------------------------------

func _poi(poi_name: String, kit: String) -> Dictionary:
	if island == null:
		return {}
	for p in island.pois:
		if p.name == poi_name:
			return p
	for p in island.pois:
		if p.kit == kit:
			return p
	return {}


func _ground(at: Vector2) -> Vector3:
	if island == null or island.terrain == null:
		return Vector3(at.x, 0.0, at.y)
	return Vector3(at.x, island.terrain.height_at(at.x, at.y), at.y)


## `at` put down on the ground, and on the navmesh if that's close by (clear of
## props: somewhere a critter can stand).
func _ground_at(at: Vector3) -> Vector3:
	var p := _ground(Vector2(at.x, at.z))
	var world := get_viewport().find_world_3d() if is_inside_tree() else null
	if world:
		var on := NavigationServer3D.map_get_closest_point(world.navigation_map, p)
		if on.distance_to(p) < 4.0:
			p = on
	return p


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)
