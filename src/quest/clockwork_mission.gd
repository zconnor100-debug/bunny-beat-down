class_name ClockworkMission
extends MissionDirector
## The Kernel Hunt's Act II, "The Clockwork Decree" (KernelHunt): the first
## Kernel won't stop humming, and it hums at the House on the shore, so the
## Barn Rangers have brought it across the lake, into the children's toy room
## (Toy Box Bash). The toy box stands open. Critters are marching stiffly
## round the room with keys turning in their backs (the Wound), and high up
## on the bookshelf two red eyes are watching (TyrantWatch). In three parts,
## one after another (`step`):
##
## FREE: four of the Warren's rogues went into the House and never came back:
##   they're Wound now (WOUND), each at a landmark with a few more round them.
##   Beat one down and it doesn't go down: it winds down (Critter.hold_on), its
##   key slowing. Hold interact by it to pull the key out (KeyPull) before it
##   winds itself back up, and it's free: it fights with you from then on.
## BREAK: his winding stations (WindingStation), where the Wound are wound,
##   three of them round Block Castle. Each winds out another of them every so
##   often while you're near. Break all three (tin: aim for the drum, or blow
##   it up).
## STORM: Block Castle, his: the Wound hold the courtyard. Stand in the ring
##   there (HoldRing) with none of them in it till the Warren's flag is up.
##   Then the eyes on the bookshelf find you, and he jumps (Boss.entrance_from):
##   the Tin Tyrant, across the room, down in front of the castle (BossIntro).
## Beat him down and the ending (ClockworkOutro): he shrinks back into Model
## No. 7, three steps, a beep and sparks, and the second Kernel is out.
##
## Go down yourself, or lose everyone on your side, and it's over.

enum Step { FREE, BREAK, STORM, BOSS, DONE }

const START_AT := "Train Station"
const ROGUE_AT := ["Loop-de-Loop", "Brick City", "Dollhouse Manor", "Domino Run"]   ## (KernelHunt.WOUND, in order)
const ROGUE_GUARDS := [2, 3, 3, 3]       ## the Wound round each (Scrappy; COUNT_SCALE for the others)
const GUARD_GUNS := [&"carrot_pistol", &"carrot_smg", &"carrot_rifle", &"carrot_shotgun"]
const STATION_AT := ["Crayon Canyon", "Toy Chest", "Pillow Fort"]
const STATION_GUARDS := 3
const STATION_GUNS := [&"carrot_smg", &"carrot_rifle", &"carrot_shotgun", &"carrot_lmg"]
const CASTLE_GUARDS := 7
const CASTLE_GUNS := [&"carrot_rifle", &"carrot_shotgun", &"carrot_smg", &"carrot_lmg"]
const WIND_BACK := 15.0        ## seconds a wound-down rogue lies there before it winds itself back up...
const WOUND_BACK := 0.4        ## ...with this much of its health
const FREED_HEALTH := 0.6      ## of its health a rogue has, freed
const BOSS_HEALTH := 0.55      ## of a Boss Battle's Tin Tyrant (there are fewer of you)
const OUTRO_AFTER := 3.0       ## seconds after he's down (his fall) that the ending starts
## Where he watches from: peering over the top of the bookshelf against the south wall (ToyRoom), at its front edge.
const SHELF := Vector3(-390.0, ToyFloor.FLOOR + 343.0, ToyFloor.HZ - 1.0)
const LEAP_TIME := 3.6         ## seconds his jump down off the bookshelf takes
const GLARE_FOR := 3.2         ## seconds the eyes glare at the castle before he jumps
const LAND_OUT := 46.0         ## metres out of the castle's gate he comes down

var step := Step.FREE
var wound_rogues: Array[Critter] = []   ## still Wound
var freed: Array[Critter] = []
var stations: Array[WindingStation] = []
var castle_pos := Vector3.ZERO
var castle_out := Vector3.FORWARD       ## (flat) out of the castle's gate
var ring: HoldRing
var watch: TyrantWatch
var flag: WarrenFlag
var _start := Vector3.ZERO
var _rogue_posts := {}          # rogue -> [post, watch]
var _keys := {}                 # rogue -> its WindKey
var _down := {}                 # rogue -> [KeyPull, seconds left]
var _down_t := -1.0
var _seen := false


func _init() -> void:
	super._init()
	mission = "clockwork_decree"


## The toy room: where you start, the Wound rogues at their landmarks, the
## stations, the castle; the rangers, the watching eyes, and the Tin Tyrant,
## parked till he jumps. (Not the prologue's: no Barn here.)
func setup(mm: MatchManager) -> void:
	match_manager = mm
	island = mm.island
	_rng.seed = mm.rng.seed * 5 + 23
	var castle := _poi("Block Castle", "castle")
	castle_pos = _ground(castle.get("center", Vector2(-180, 40)))
	castle_out = _flat(-castle_pos).normalized()   # (it faces the middle of the room: ToyBox._face_centre)
	if not castle.is_empty() and not (castle.buildings as Array).is_empty():
		var b: Node3D = castle.buildings[0]
		castle_pos = b.global_position
		castle_out = _flat(b.global_basis.z).normalized()
	barn_pos = castle_pos   # (what the Touched face, unless they're told otherwise)
	patch_pos = castle_pos
	var st := _poi(START_AT, "station")
	var at := _ground(st.get("center", Vector2(100, 320)))
	_start = _ground_at(at + _flat(-at).normalized() * 30.0)   # (off the platform, on the room's side of it)
	for n in KernelHunt.RANGERS:
		_spawn_ranger(n)
	for i in KernelHunt.WOUND.size():
		_place_rogue(String(KernelHunt.WOUND[i]), i)
	for i in STATION_AT.size():
		_build_station(String(STATION_AT[i]), i)
	watch = TyrantWatch.new()
	mm.world_root.add_child(watch)
	watch.global_position = SHELF
	watch.centre = Vector3(-60.0, ToyFloor.FLOOR, 0.0)
	mm._make_boss()
	if mm.boss:
		mm.boss.max_health *= BOSS_HEALTH
		mm.boss.health = mm.boss.max_health


func wants_boss() -> bool:
	return true


## Where the camera looks as it starts: the room (game.gd).
func facing() -> Vector3:
	return _ground(Vector2(60.0, 120.0))


## You and the rangers off the station's platform, facing into the room.
func begin() -> void:
	var fwd := _flat(facing() - _start).normalized()
	var side := fwd.cross(Vector3.UP)
	for i in rangers.size():
		var r := rangers[i]
		r.place_at(_ground_at(_start - fwd * 4.5 + side * ((i - (rangers.size() - 1) * 0.5) * 2.6)), atan2(-fwd.x, -fwd.z))
		_follow(r)
	_arm_player(_start, atan2(-fwd.x, -fwd.z))
	var p := match_manager.player
	if p:
		p.inventory.grenades = maxi(p.inventory.grenades, 2)
	stage = Stage.WAVE
	step = Step.FREE
	_t = 0.0
	for c in wound_rogues:
		c.add_to_group(&"objectives")
	match_manager._set_phase(MatchManager.Phase.PLAYING)
	get_tree().create_timer(5.0, false).timeout.connect(func(): _shout("ct", 0, _keeper()))


func _process(delta: float) -> void:
	if match_manager == null or match_manager.phase != MatchManager.Phase.PLAYING:
		return
	_clock += delta
	_t += delta
	_tend_down(delta)
	match step:
		Step.FREE:
			_watch_for_them()
		Step.DONE:
			if _down_t >= 0.0:
				_down_t += delta
				if _down_t >= OUTRO_AFTER and stage != Stage.OUTRO:
					stage = Stage.OUTRO
					_play_outro()


# ---- the Wound rogues --------------------------------------------------------------------------------

## Rogue `n` (KernelHunt.WOUND), Wound, at its landmark, with a few more round it.
func _place_rogue(n: String, i: int) -> void:
	var poi := _poi(String(ROGUE_AT[i]), "")
	var mid := _ground(poi.get("center", Vector2(_rng.randf_range(-200, 300), _rng.randf_range(-200, 200))))
	var toward := _flat(_start - mid).normalized()
	var at := _ground_at(mid + toward * (float(poi.get("radius", 20.0)) * 0.5))
	var c := _spawn_wound_rogue(n, at, at + toward * 30.0)
	_rogue_posts[c] = [at, at + toward * 30.0 + Vector3.UP]
	var guards := maxi(1, roundi(float(ROGUE_GUARDS[i]) * _count_scale()))
	for k in guards:
		var a := lerpf(-1.2, 1.2, (k + 0.5) / guards) + _rng.randf_range(-0.2, 0.2)
		var post := _ground_at(at + toward.rotated(Vector3.UP, a + PI) * _rng.randf_range(5.0, 11.0))
		_spawn_wound(post, GUARD_GUNS[_rng.randi() % GUARD_GUNS.size()], post, post + toward * 30.0 + Vector3.UP)


func _spawn_wound_rogue(n: String, at: Vector3, look: Vector3) -> Critter:
	var def: CritterDef = load("res://data/critters/%s.tres" % String(Cast.member(n).get("species", "squirrel")))
	var c := match_manager._spawn_critter(def, n)
	c.team = 2
	if Outfits.look_of(n).is_empty():
		c.visual.apply_skin("default")
	else:
		Outfits.dress(c, n)
	Outfits.wear_coat(c.visual, "touched")
	c.place_at(at, atan2(-(look - at).x, -(look - at).z))
	var title := "Wound %s" % n
	c.visual.set_enemy_highlight(title)
	if c.visual.name_tag:
		c.visual.name_tag.modulate = Workshop.COLORS["kernel"]
		c.visual.name_tag.text = "▼ %s" % title.to_upper()
	var gun := WeaponDB.get_weapon(StringName(Cast.member(n).get("weapon", "carrot_smg")))
	c.give_weapon(WeaponInstance.new(gun if gun else WeaponDB.get_weapon(&"carrot_smg"), Rarity.Tier.GARDEN))
	for w in c.inventory.weapons:
		if w:
			c.inventory.add_ammo(w.data.ammo_type, Inventory.AMMO_PICKUP[w.data.ammo_type] * 6)
	_touched_brain(c, SKILL[clampi(match_manager._difficulty, 0, 2)] + 0.08).hold(at, look)
	c.hold_on = true
	c.held_on.connect(_wind_down.bind(c))
	_keys[c] = WindKey.fit(c)
	wound_rogues.append(c)
	return c


## One of the Wound, at `at`, carrying `gun`, holding `post` and watching `look`.
func _spawn_wound(at: Vector3, gun: StringName, post: Vector3, look: Vector3) -> Critter:
	var c := _spawn_touched(at, gun, false, post, look, "Wound")
	if c:
		c.look_yaw = atan2(-(look - at).x, -(look - at).z)
		var key := WindKey.fit(c)
		if key:
			key.speed = _rng.randf_range(220.0, 380.0)
	return c


## A Touched brain for `c` (as MissionDirector's), at `skill`.
func _touched_brain(c: Critter, skill: float) -> AIBrain:
	var brain := AIBrain.new()
	brain.name = "AIBrain"
	brain.island = island
	brain.match_manager = match_manager
	brain.personality = "touched"
	brain.traits = {"break_off": 0.0, "heal_at": 0.0, "spot": 1.3, "fight_range": 70.0, "settle": 0.0, "sticky": 0.4}
	brain.skill = skill
	brain.hold_low = false
	brain.hold_run = false
	c.add_child(brain)
	return brain


## The first time one of yours sees the Wound: what's in their backs.
func _watch_for_them() -> void:
	if _seen:
		return
	var p := match_manager.player
	if p == null:
		return
	for c in match_manager.alive_critters():
		if c.team == 2 and c.global_position.distance_to(p.global_position) < 60.0:
			_seen = _shout("cs", 0)
			return


## A Wound rogue's been beaten down, and it holds on: it winds down instead,
## and its key's there to be pulled (before it winds itself back up).
func _wind_down(_info: DamageInfo, c: Critter) -> void:
	if _down.has(c) or not wound_rogues.has(c):
		return
	c.spared = true
	_pause(c, true)
	var key: WindKey = _keys.get(c)
	if key and is_instance_valid(key):
		var tw := key.create_tween()
		tw.tween_property(key, "speed", 0.0, 1.6).set_ease(Tween.EASE_OUT)
	var pull := KeyPull.new(c, key)
	match_manager.world_root.add_child(pull)
	pull.used.connect(_on_key_pulled.bind(c))
	_down[c] = [pull, WIND_BACK]
	c.remove_from_group(&"objectives")   # (the key's what's marked now)
	Audio.play_at(&"wind_key", c.global_position + Vector3.UP, 0.0, 0.0).pitch_scale = 0.6
	Events.headline.emit("%s is winding down: pull the key out of its back!" % c.display_name)
	if _say_ok("cu"):
		_shout("cu", 0)


func _tend_down(delta: float) -> void:
	for c in _down.keys():
		if not is_instance_valid(c) or not c.alive:
			_down.erase(c)
			continue
		_down[c][1] = float(_down[c][1]) - delta
		if float(_down[c][1]) <= 0.0:
			_wind_up(c)


## Nobody pulled it: it winds itself back up, and it's back at it.
func _wind_up(c: Critter) -> void:
	var pull: KeyPull = _down[c][0]
	_down.erase(c)
	if is_instance_valid(pull):
		pull.queue_free()
	c.spared = false
	c.health = c.max_health * WOUND_BACK
	_pause(c, false)
	var key: WindKey = _keys.get(c)
	if key and is_instance_valid(key):
		key.speed = 900.0
		var tw := key.create_tween()
		tw.tween_property(key, "speed", 300.0, 1.5)
	c.add_to_group(&"objectives")
	Audio.play_at(&"wind_key", c.global_position + Vector3.UP, 2.0, 0.05)
	Events.headline.emit("%s wound itself back up!" % c.display_name)


## The Wound rogue's brain off (wound down: it kneels there, still) or back on.
func _pause(c: Critter, off: bool) -> void:
	var brain := c.get_node_or_null("AIBrain") as AIBrain
	if brain:
		brain.set_physics_process(not off)
		if not off:
			brain.forget()
	c.move_input = Vector2.ZERO
	c.want_fire = false
	c.want_aim = false
	c.want_sprint = false
	c.want_jump = false
	c.want_crouch = off
	if off:
		c.look_pitch = -0.6


## You pulled its key out: it's free, and it's with you.
func _on_key_pulled(_by: Critter, c: Critter) -> void:
	_down.erase(c)
	if not is_instance_valid(c) or not c.alive:
		return
	wound_rogues.erase(c)
	freed.append(c)
	_keys.erase(c)
	c.spared = false
	c.hold_on = false
	c.team = 1
	c.health = c.max_health * FREED_HEALTH
	c.visual.clear_enemy_highlight()
	Outfits.wear_coat(c.visual, "")
	c.visual.set_ally_tag(c.display_name)
	var old := c.get_node_or_null("AIBrain")
	if old:
		c.remove_child(old)
		old.queue_free()
	var brain := AIBrain.new()
	brain.name = "AIBrain"
	brain.island = island
	brain.match_manager = match_manager
	brain.personality = RivalBook.personality_of(c.display_name)
	var traits := Cast.traits_for(c.display_name)
	for k in ["hunts_you", "no_slot", "defiant"]:
		traits.erase(k)
	brain.traits = traits
	brain.skill = clampf(MatchManager._skill_for(match_manager._difficulty) + 0.1, 0.2, 0.95)
	c.add_child(brain)
	_pause(c, false)
	c.want_crouch = false
	c.look_pitch = 0.0
	brain.escort = match_manager.player
	_restock(c)
	FX.muzzle(c.get_chest_position(), Vector3.UP, true, Color(1.0, 0.9, 0.6))
	Events.announce.emit("%s IS FREE!" % c.display_name.to_upper(), "%d of %d unwound. They're with you now." % [freed.size(), KernelHunt.WOUND.size()])
	get_tree().create_timer(1.2, false).timeout.connect(func():
		if is_instance_valid(c) and c.alive:
			_shout("cf", (freed.size() - 1) % 2, c))
	if wound_rogues.is_empty() and step == Step.FREE:
		get_tree().create_timer(3.5, false).timeout.connect(_start_break)


# ---- the winding stations ------------------------------------------------------------------------------

func _build_station(where: String, i: int) -> void:
	var poi := _poi(where, "")
	var mid: Vector2 = poi.get("center", Vector2(castle_pos.x, castle_pos.z) + Vector2.from_angle(TAU * i / 3.0) * 150.0)
	# out in front of the landmark, toward the castle (on clear floor)
	var toward := (Vector2(castle_pos.x, castle_pos.z) - mid).normalized()
	var at := mid + toward * (float(poi.get("radius", 24.0)) + 12.0)
	for k in 12:
		if island == null or island.scatter == null or not island.scatter.blocked(at, 9.0, false):
			break
		at += toward.rotated(_rng.randf_range(-1.2, 1.2)) * 6.0
	var s := WindingStation.new(match_manager._difficulty)
	s.name = "WindingStation%d" % (i + 1)
	match_manager.world_root.add_child(s)
	s.global_position = _ground(at)
	var face := _flat(facing() - s.global_position).normalized()
	s.rotation.y = atan2(face.x, face.z)   # (its chute, and its gears, toward the room's middle: the way you'll come)
	s.wound_out.connect(_station_wound.bind(s))
	s.broken_down.connect(_on_station_broken)
	stations.append(s)


func _start_break() -> void:
	if step != Step.FREE:
		return
	step = Step.BREAK
	_t = 0.0
	var n := maxi(1, roundi(STATION_GUARDS * _count_scale()))
	for s in stations:
		s.active = true
		s.mark(true)
		var front := s.global_basis.z.normalized()
		for k in n:
			var a := lerpf(-1.0, 1.0, (k + 0.5) / n)
			var post := _ground_at(s.global_position + front.rotated(Vector3.UP, a) * _rng.randf_range(9.0, 14.0))
			_spawn_wound(post, STATION_GUNS[_rng.randi() % STATION_GUNS.size()], post, post + front * 30.0 + Vector3.UP)
	Events.alive_count_changed.emit(match_manager.alive_critters().size(), match_manager.total)
	Events.announce.emit("BREAK HIS WINDING STATIONS", "That's where they're wound. Tin: aim for the drum, or blow it up.")
	_shout("cw", 0, _keeper())
	_drop_tins()


## A crate down by you as the stations go up on the map: something for tin.
func _drop_tins() -> void:
	var p := match_manager.player
	var by := p.global_position if p and p.alive else _start
	var out := _flat(castle_pos - by).normalized()
	var at := island.random_land_point(2.0, Vector2(by.x + out.x * 14.0, by.z + out.z * 14.0), 8.0) if island else by
	var spot := at if at != Vector3.INF else by
	var drop := SupplyDrop.new()
	drop.landing = spot
	drop.rng.seed = _rng.randi()
	var rockets := WeaponInstance.new(WeaponDB.get_weapon(&"carrot_rocket_launcher"), Rarity.Tier.PRIZE)
	drop.contents = [Pickup.weapon_spec(rockets), Pickup.ammo_spec(rockets.data.ammo_type, Inventory.AMMO_PICKUP[rockets.data.ammo_type] * 3),
		Pickup.grenade_spec(2)]
	match_manager.world_root.add_child(drop)
	drop.global_position = spot + Vector3.UP * 70.0
	Events.supply_drop_incoming.emit(spot)


## A station's wound one out of its chute: it marches out and holds in front.
func _station_wound(at: Vector3, facing: Vector3, s: WindingStation) -> void:
	if step != Step.BREAK or s.broken:
		return
	var post := _ground_at(at + facing.rotated(Vector3.UP, _rng.randf_range(-0.8, 0.8)) * _rng.randf_range(6.0, 12.0))
	var c := _spawn_wound(_ground_at(at), STATION_GUNS[_rng.randi() % STATION_GUNS.size()], post, post + facing * 30.0 + Vector3.UP)
	if c:
		s.wound.append(c)
		Events.alive_count_changed.emit(match_manager.alive_critters().size(), match_manager.total)


func _on_station_broken(_by: Node) -> void:
	var left := stations.filter(func(s): return not s.broken).size()
	if left > 0:
		Events.announce.emit("%d OF %d BROKEN" % [stations.size() - left, stations.size()], "%s." % ("Two to go" if left == 2 else "One to go"))
		_shout("cb", (stations.size() - left - 1) % 2)
		return
	get_tree().create_timer(2.5, false).timeout.connect(_start_storm)


# ---- storming the castle ------------------------------------------------------------------------------

func _start_storm() -> void:
	if step != Step.BREAK:
		return
	step = Step.STORM
	_t = 0.0
	ring = HoldRing.new(9.0, 14.0)
	match_manager.world_root.add_child(ring)
	ring.global_position = _ground_at(castle_pos + castle_out * 3.0)
	ring.caught.connect(_castle_taken)
	var n := maxi(3, roundi(CASTLE_GUARDS * _count_scale()))
	var side := castle_out.cross(Vector3.UP)
	for k in n:
		# in the courtyard, and out in front of the gate
		var inside := k < n - 2
		var post := castle_pos + castle_out * (_rng.randf_range(-6.0, 6.0) if inside else _rng.randf_range(18.0, 24.0)) \
			+ side * _rng.randf_range(-8.0, 8.0)
		post = _ground_at(post)
		_spawn_wound(post, CASTLE_GUNS[_rng.randi() % CASTLE_GUNS.size()], post, post + castle_out * 30.0 + Vector3.UP)
	Events.alive_count_changed.emit(match_manager.alive_critters().size(), match_manager.total)
	Events.announce.emit("STORM BLOCK CASTLE", "His castle. Take the courtyard: stand in the ring, with none of the Wound in it.")
	_shout("cc", 0, _keeper())
	_post_rangers()


## A ranger or two in the ring (they fight whoever comes, and go back to it);
## the rest stick by you.
func _post_rangers() -> void:
	var k := 0
	for r in rangers + freed:
		if not is_instance_valid(r) or not r.alive:
			continue
		var brain := r.get_node_or_null("AIBrain") as AIBrain
		if brain == null:
			continue
		if ring == null or ring.lit or k >= 4:
			_follow(r)
			continue
		var a := TAU * k / 4.0
		brain.escort = null
		brain.hold(_ground_at(ring.global_position + Vector3(cos(a), 0.0, sin(a)) * ring.radius * 0.5), ring.global_position + Vector3.UP, 600.0)
		k += 1


## The courtyard's yours: the flag goes up, and then the eyes on the bookshelf find you.
func _castle_taken() -> void:
	flag = WarrenFlag.new()
	match_manager.world_root.add_child(flag)
	flag.global_position = ring.global_position
	flag.raise()
	Events.announce.emit("BLOCK CASTLE IS OURS", "The Warren's flag is up over his castle.")
	for r in rangers + freed:
		if is_instance_valid(r) and r.alive:
			_follow(r)
	get_tree().create_timer(2.6, false).timeout.connect(func():
		watch.glare(ring.global_position)
		Audio.play_at(&"boss_clank", SHELF, 10.0, 0.0, {"max_distance": 3000.0, "unit_size": 200.0})
		_shout("cl", 0, _keeper()))
	get_tree().create_timer(2.6 + GLARE_FOR, false).timeout.connect(_leap)


## He jumps: off the bookshelf, across the room, down in front of his castle.
func _leap() -> void:
	if step != Step.STORM:
		return
	step = Step.BOSS
	_t = 0.0
	watch.leave()
	for r in rangers + freed:
		if is_instance_valid(r) and r.alive:
			var brain := r.get_node_or_null("AIBrain") as AIBrain
			if brain:
				brain.release()
	var b := match_manager.boss
	if b:
		b.entrance_from = SHELF
		b.land_time = LEAP_TIME
	match_manager.release_boss(_boss_spot())


## Out in front of the castle's gate, on open floor.
func _boss_spot() -> Vector3:
	var at := castle_pos + castle_out * LAND_OUT
	for i in 24:
		var tries := _ground(Vector2(at.x, at.z) + Vector2.from_angle(TAU * i / 8.0) * (i / 8) * 9.0)
		if island == null or island.scatter == null or not island.scatter.blocked(Vector2(tries.x, tries.z), MatchManager.BOSS_CLEARING, false):
			return tries
	return _ground(Vector2(at.x, at.z))


# ---- the end ------------------------------------------------------------------------------------------

## You're down: nobody else can carry it on.
func critter_down(c: Critter, info: DamageInfo) -> void:
	super.critter_down(c, info)
	if c == match_manager.player and stage != Stage.OVER and stage != Stage.OUTRO:
		end(false)


func boss_down(_by: Node) -> void:
	if step == Step.DONE:
		return
	step = Step.DONE
	_down_t = 0.0


func play_outro(rig: CameraRig = null, hud: CanvasLayer = null, pc: PlayerController = null) -> MissionCinematic:
	_outro = ClockworkOutro.new(self, rig, hud, pc)
	_outro.finished.connect(func(): end(true))
	add_child(_outro)
	return _outro


# ---- the bar on the HUD, the report -----------------------------------------------------------------

func bar_title() -> String:
	match step:
		Step.FREE:
			return "THE WOUND"
		Step.BREAK:
			return "HIS WINDING STATIONS"
	return "BLOCK CASTLE"


func bar_fill() -> float:
	match step:
		Step.FREE:
			return float(freed.size()) / KernelHunt.WOUND.size()
		Step.BREAK:
			return stations.reduce(func(a, s): return a + (1.0 - s.health / maxf(s.max_health, 1.0)), 0.0) / maxf(1.0, stations.size())
		Step.STORM:
			return ring.progress if ring else 0.0
	return 1.0


func bar_color() -> Color:
	return WindKey.BRASS if step in [Step.FREE, Step.BREAK] else WarrenFlag.CLOTH


func bar_status() -> String:
	var p := match_manager.player
	match step:
		Step.FREE:
			for c in _down:
				return "PULL %s'S KEY!  ·  %d s" % [String(c.display_name).to_upper(), ceili(float(_down[c][1]))]
			var near := _nearest_of(wound_rogues, p)
			return "%d of %d unwound  ·  %d m" % [freed.size(), KernelHunt.WOUND.size(), roundi(near)] if near < INF \
				else "%d of %d unwound" % [freed.size(), KernelHunt.WOUND.size()]
		Step.BREAK:
			var left := stations.filter(func(s): return not s.broken)
			var near := _nearest_of(left, p)
			return "%d of %d broken  ·  %d m" % [stations.size() - left.size(), stations.size(), roundi(near)] if near < INF \
				else "%d of %d broken" % [stations.size() - left.size(), stations.size()]
		Step.STORM:
			if ring and ring.theirs > 0 and ring.ours > 0:
				return "THE WOUND ARE IN THE RING!"
			var d := roundi(_flat(ring.global_position - p.global_position).length()) if ring and p else 0
			return "Take the courtyard  ·  %d m" % d if d > ring.radius else "Hold the ring!"
	return "THE TIN TYRANT IS DOWN!" if step == Step.DONE else ""


func bar_warn() -> bool:
	return (step == Step.FREE and not _down.is_empty()) or (step == Step.STORM and ring != null and ring.theirs > 0)


func bar_good() -> bool:
	return step == Step.DONE


func bar_shown() -> bool:
	return step in [Step.FREE, Step.BREAK, Step.STORM]


func _nearest_of(things: Array, p: Critter) -> float:
	if p == null:
		return INF
	var best := INF
	for t in things:
		if is_instance_valid(t):
			best = minf(best, _flat((t as Node3D).global_position - p.global_position).length())
	return best


func report() -> Dictionary:
	var r := super.report()
	r.erase("barn")
	r.erase("wave")
	r["freed"] = freed.map(func(c): return c.display_name)
	r["freed_home"] = freed.filter(func(c): return is_instance_valid(c) and c.alive).map(func(c): return c.display_name)
	r["broken"] = stations.filter(func(s): return s.broken).size()
	r["step"] = Step.keys()[step].to_lower()
	if match_manager.boss:
		r["boss_time"] = match_manager.boss.fight_time()
	return r


func news(r: Dictionary) -> Array:
	return WarrenSim.clockwork_news(r)


func lost_text() -> String:
	return "There's nobody left to stand up to the Decree."


func opening() -> Array:
	return ["FREE THE WOUND", "Rogues with keys in their backs. Beat one down and it winds down: hold %s by it to pull its key out." % GameInput.prompt(&"interact")]


func you_down_text(who: String, _left: int) -> String:
	return "Taken out by %s. Without you, the rangers head back across the lake." % who


func result(won: bool, r: Dictionary) -> Array:
	if won:
		return ["ACT II COMPLETE!", "The Clockwork Decree: the Tin Tyrant is Model No. 7 again, and the second Kernel is out. %d Touched beaten down, %d of %d rangers home." % [
			int(r.get("touched", 0)), int(r.get("rangers", 0)), KernelHunt.RANGERS.size()]]
	match step:
		Step.FREE:
			return ["STILL WOUND", "%d of %d rogues unwound before the Wound stopped you." % [freed.size(), KernelHunt.WOUND.size()]]
		Step.BREAK:
			return ["THE STATIONS STILL TURN", "%d of %d winding stations broken." % [stations.filter(func(s): return s.broken).size(), stations.size()]]
		Step.STORM:
			return ["THE CASTLE HOLDS", "The Wound kept Block Castle. %d of them beaten down." % int(r.get("touched", 0))]
	return ["THE TIN TYRANT WINS", "He beat you in front of his castle. Every toy shall be wound."]


# ---- helpers -------------------------------------------------------------------------------------------

func _count_scale() -> float:
	return float(KernelHunt.COUNT_SCALE[clampi(match_manager._difficulty, 0, 2)])


func _follow(r: Critter) -> void:
	var brain := r.get_node_or_null("AIBrain") as AIBrain
	if brain:
		brain.release()
		brain.escort = match_manager.player


## Buck Toothington (he carries the first Kernel), if he's standing.
func _keeper() -> Critter:
	for r in rangers:
		if is_instance_valid(r) and r.alive and r.display_name == KernelHunt.RANGERS[0]:
			return r
	return null
