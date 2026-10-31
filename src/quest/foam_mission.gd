class_name FoamMission
extends MissionDirector
## The Kernel Hunt's Act III, "Foam at the Falls" (KernelHunt): the two
## Kernels the Barn Rangers carry pull at the hamster cage, and the rangers
## follow them in, over the glass and down into the bedding. Nibbles has dug
## his tunnels from here toward the toy room, toward the hum, and his water
## bottle has never once run dry: the seed-sized Kernel's in it. In three
## parts, one after another (`step`):
##
## BURROWS: his burrows (BurrowMouth), mouths dug into the hamster's heaps of
##   bedding (HamsterCage.burrows): the Touched keep coming up out of them
##   while you're near. Nothing you can shoot shuts one; a blast caves it in
##   (a grenade: a crate of them comes down; a rocket; a ranger's rocket).
## DAM: Water Bottle Falls (Dam): carry chew blocks (ChewBlock), one at a
##   time over your head, slowly, into the ring under the spout, while the
##   Touched come at you; knocked down, you drop it. Three, and the falls are
##   dammed: the drips stop, the puddle drains away.
## WAKE: the bedding heaves by the dam, and Nibbles bursts up out of it, for
##   his water (his Boss Battle arrival, BossIntro). Beat him down and the
##   ending (FoamOutro): he's a little golden hamster again, the third Kernel
##   comes out, and the three of them together call up the Briar.
##
## Go down yourself, or lose everyone on your side, and it's over.

enum Step { BURROWS, DAM, WAKE, BOSS, DONE }

const START_AT := "Tube Town"
const BURROWS := 4             ## (at most: as many as the heaps have, up to this)
const CLIMB_GUNS := [&"carrot_smg", &"carrot_shotgun", &"carrot_rifle", &"carrot_pistol"]
const RUSH_EVERY := 22.0       ## seconds between the Touched's rushes at the dam...
const RUSH := 3                ## ...this many (Scrappy; COUNT_SCALE for the others)
const RUSH_FROM := 70.0        ## metres out they come from
const RUSH_GUNS := [&"carrot_smg", &"carrot_rifle", &"carrot_shotgun", &"carrot_lmg"]
const BLOCKS_OUT := Vector2(26.0, 42.0)   ## how far from the dam the chew blocks lie
const HEAVE := 3.2             ## seconds the bedding heaves before he comes up
const BOSS_HEALTH := 0.55      ## of a Boss Battle's Nibbles (there are fewer of you)
const OUTRO_AFTER := 3.0       ## seconds after he's down that the ending starts
const GRENADES := 3            ## you start with, and a crate brings more

var step := Step.BURROWS
var burrows: Array[BurrowMouth] = []
var blocks: Array[ChewBlock] = []
var dam: Dam
var falls_pos := Vector3.ZERO  ## the ground under the bottle's spout
var _start := Vector3.ZERO
var _rush_t := 8.0
var _heave_t := -1.0
var _down_t := -1.0


func _init() -> void:
	super._init()
	mission = "foam_at_the_falls"


## The cage: where you start (by Tube Town), the burrows, the falls; the
## rangers, and Nibbles, parked under the bedding till he comes up.
func setup(mm: MatchManager) -> void:
	match_manager = mm
	island = mm.island
	_rng.seed = mm.rng.seed * 7 + 31
	var cage := island as HamsterCage
	var fall_poi := _poi("Water Bottle Falls", "bottle")
	var drip: Vector3 = cage.falls.get("drip", _ground(fall_poi.get("center", Vector2(250, 372)))) if cage else _ground(Vector2(250, 372))
	falls_pos = _ground(Vector2(drip.x, drip.z))
	barn_pos = falls_pos
	patch_pos = falls_pos
	var tubes := _poi(START_AT, "tubes")
	var at := _ground(tubes.get("center", Vector2(-70, -230)))
	_start = _ground_at(at + _flat(falls_pos - at).normalized() * (float(tubes.get("radius", 50.0)) + 14.0))
	for n in KernelHunt.RANGERS:
		_spawn_ranger(n)
	_dig_burrows(cage)
	mm._make_boss()
	if mm.boss:
		mm.boss.max_health *= BOSS_HEALTH
		mm.boss.health = mm.boss.max_health


func wants_boss() -> bool:
	return true


## Where the camera looks as it starts: the way the Kernels pull (the falls).
func facing() -> Vector3:
	return falls_pos


## The burrows to cave in: the ones nearest the way from Tube Town to the
## falls (the tunnels run that way).
func _dig_burrows(cage: HamsterCage) -> void:
	if cage == null:
		return
	var mid := (_start + falls_pos) * 0.5
	var near: Array = cage.burrows.duplicate()
	near.sort_custom(func(a, b): return _flat((a.mouth as Vector3) - mid).length() < _flat((b.mouth as Vector3) - mid).length())
	for b in near.slice(0, BURROWS):
		var burrow := BurrowMouth.new()
		burrow.out = b.out
		burrow.tube = b.tube
		match_manager.world_root.add_child(burrow)
		burrow.global_position = b.mouth
		burrow.climb_out.connect(_climbed_out.bind(burrow))
		burrow.caved_in.connect(_on_caved)
		burrows.append(burrow)


## You and the rangers out of Tube Town, facing the falls; the burrows open.
func begin() -> void:
	var fwd := _flat(falls_pos - _start).normalized()
	var side := fwd.cross(Vector3.UP)
	for i in rangers.size():
		var r := rangers[i]
		r.place_at(_ground_at(_start - fwd * 4.5 + side * ((i - (rangers.size() - 1) * 0.5) * 2.6)), atan2(-fwd.x, -fwd.z))
		_follow(r)
	_arm_player(_start, atan2(-fwd.x, -fwd.z))
	var p := match_manager.player
	if p:
		p.inventory.grenades = maxi(p.inventory.grenades, GRENADES)
	stage = Stage.WAVE
	step = Step.BURROWS
	_t = 0.0
	for b in burrows:
		b.open_up()
	match_manager._set_phase(MatchManager.Phase.PLAYING)
	get_tree().create_timer(5.0, false).timeout.connect(func(): _shout("ft", 0, _keeper()))
	get_tree().create_timer(9.0, false).timeout.connect(_drop_grenades)
	if burrows.is_empty():
		get_tree().create_timer(6.0, false).timeout.connect(_start_dam)


func _process(delta: float) -> void:
	if match_manager == null or match_manager.phase != MatchManager.Phase.PLAYING:
		return
	_clock += delta
	_t += delta
	match step:
		Step.DAM:
			_rush_t -= delta
			if _rush_t <= 0.0:
				_rush_t = RUSH_EVERY
				_rush()
		Step.WAKE:
			_heave(delta)
		Step.DONE:
			if _down_t >= 0.0:
				_down_t += delta
				if _down_t >= OUTRO_AFTER and stage != Stage.OUTRO:
					stage = Stage.OUTRO
					_play_outro()


# ---- the burrows ---------------------------------------------------------------------------------

## A crate down by you as the burrows open: grenades (and a launcher).
func _drop_grenades() -> void:
	var p := match_manager.player
	var by := p.global_position if p and p.alive else _start
	var out := _flat(falls_pos - by).normalized()
	var at := island.random_land_point(2.0, Vector2(by.x + out.x * 12.0, by.z + out.z * 12.0), 8.0) if island else by
	var spot := at if at != Vector3.INF else by
	var drop := SupplyDrop.new()
	drop.landing = spot
	drop.rng.seed = _rng.randi()
	var rockets := WeaponInstance.new(WeaponDB.get_weapon(&"carrot_rocket_launcher"), Rarity.Tier.PRIZE)
	drop.contents = [Pickup.grenade_spec(4), Pickup.weapon_spec(rockets),
		Pickup.ammo_spec(rockets.data.ammo_type, Inventory.AMMO_PICKUP[rockets.data.ammo_type] * 3)]
	match_manager.world_root.add_child(drop)
	drop.global_position = spot + Vector3.UP * 70.0
	Events.supply_drop_incoming.emit(spot)
	Events.headline.emit("A crate's coming down: grenades. Nothing else shuts a burrow.")


## One of the Touched up out of a burrow: it holds the ground in front of it.
func _climbed_out(at: Vector3, out: Vector3, b: BurrowMouth) -> void:
	if step != Step.BURROWS or b.caved:
		return
	var post := _ground_at(at + out.rotated(Vector3.UP, _rng.randf_range(-0.9, 0.9)) * _rng.randf_range(4.0, 10.0))
	var c := _spawn_touched(_ground_at(at), CLIMB_GUNS[_rng.randi() % CLIMB_GUNS.size()], false, post, post + out * 30.0 + Vector3.UP)
	if c:
		b.climbed.append(c)
		Events.alive_count_changed.emit(match_manager.alive_critters().size(), match_manager.total)
	if _say_ok("fb"):
		_shout("fb", 0)


func _on_caved() -> void:
	var left := burrows.filter(func(b): return not b.caved).size()
	if left > 0:
		Events.announce.emit("%d OF %d CAVED IN" % [burrows.size() - left, burrows.size()], "%s." % ("One to go" if left == 1 else "%d to go" % left))
		_shout("fx", (burrows.size() - left - 1) % 2)
		return
	get_tree().create_timer(2.5, false).timeout.connect(_start_dam)


# ---- the dam -------------------------------------------------------------------------------------

func _start_dam() -> void:
	if step != Step.BURROWS:
		return
	step = Step.DAM
	_t = 0.0
	_rush_t = 8.0
	var cage := island as HamsterCage
	dam = Dam.new()
	if cage:
		dam.drips = cage.falls.get("drips")
		dam.puddle = cage.falls.get("puddle")
	match_manager.world_root.add_child(dam)
	dam.global_position = falls_pos
	dam.took.connect(_on_took)
	dam.dammed.connect(_on_dammed)
	# the blocks, lying out round it on clear bedding (off the glass)
	var into := _flat(-falls_pos).normalized()
	for i in Dam.NEEDED:
		var a := lerpf(-1.1, 1.1, (i + 0.5) / Dam.NEEDED) + _rng.randf_range(-0.2, 0.2)
		var want := falls_pos + into.rotated(Vector3.UP, a) * _rng.randf_range(BLOCKS_OUT.x, BLOCKS_OUT.y)
		var spot := island.clear_loot_spot(_ground_at(want), Vector3.ONE * ChewBlock.SIZE * 0.5) if island else want
		var block := ChewBlock.new(i)
		match_manager.world_root.add_child(block)
		block.global_position = _ground_at(spot if spot != Vector3.INF else want)
		blocks.append(block)
	Events.announce.emit("DAM WATER BOTTLE FALLS", "Carry three chew blocks into the ring under the spout. Get knocked down and you drop it.")
	_shout("fd", 0, _keeper())
	_post_rangers()


## The Touched come over the bedding at the dam (and whoever's carrying).
func _rush() -> void:
	var n := maxi(2, roundi(RUSH * float(KernelHunt.COUNT_SCALE[clampi(match_manager._difficulty, 0, 2)])))
	var into := _flat(-falls_pos).normalized()
	for k in n:
		var a := _rng.randf_range(-1.2, 1.2)
		var from := falls_pos + into.rotated(Vector3.UP, a) * RUSH_FROM
		var at := island.random_land_point(2.0, Vector2(from.x, from.z), 12.0) if island else from
		var post := _ground_at(falls_pos + into.rotated(Vector3.UP, a) * _rng.randf_range(6.0, 14.0))
		_spawn_touched(at if at != Vector3.INF else from, RUSH_GUNS[_rng.randi() % RUSH_GUNS.size()], false, post, falls_pos + Vector3.UP)
	Events.alive_count_changed.emit(match_manager.alive_critters().size(), match_manager.total)
	if _say_ok("kw"):
		_shout("kw", 0)


## A few rangers by the dam (they fight whoever comes, and go back to it);
## the rest stick by you.
func _post_rangers() -> void:
	var k := 0
	for r in rangers:
		if not is_instance_valid(r) or not r.alive:
			continue
		var brain := r.get_node_or_null("AIBrain") as AIBrain
		if brain == null:
			continue
		if k >= 3:
			_follow(r)
			continue
		var a := TAU * k / 3.0
		brain.escort = null
		brain.hold(_ground_at(falls_pos + Vector3(cos(a), 0.0, sin(a)) * (Dam.RADIUS + 3.0)), falls_pos + Vector3.UP, 600.0)
		k += 1


func _on_took(placed: int) -> void:
	if placed < Dam.NEEDED:
		Events.announce.emit("%d OF %d" % [placed, Dam.NEEDED], "The water's slowing. Fetch the next.")
		_shout("fp", (placed - 1) % 2)


## Dammed: the water stops, and the bedding by the dam starts to heave.
func _on_dammed() -> void:
	step = Step.WAKE
	_t = 0.0
	_heave_t = 0.0
	for r in rangers:
		if is_instance_valid(r) and r.alive:
			_follow(r)
	Events.announce.emit("THE FALLS ARE DAMMED", "The water's stopped. Something under the bedding wants a drink.")
	get_tree().create_timer(1.2, false).timeout.connect(func(): _shout("fw", 0, _keeper()))


func _heave(delta: float) -> void:
	if _heave_t < 0.0:
		return
	_heave_t += delta
	if fmod(_heave_t, 0.5) < delta:
		var spot := _boss_spot()
		BossFX.dust(spot + Vector3(_rng.randf_range(-6, 6), 0.0, _rng.randf_range(-6, 6)), 5.0, Color(0.62, 0.5, 0.32, 0.7))
		Events.explosion.emit(spot, 3.0)
	if _heave_t >= HEAVE:
		_heave_t = -1.0
		_wake()


## He comes up: out of the bedding beside the dam.
func _wake() -> void:
	step = Step.BOSS
	_t = 0.0
	for r in rangers:
		if is_instance_valid(r) and r.alive:
			var brain := r.get_node_or_null("AIBrain") as AIBrain
			if brain:
				brain.release()
	match_manager.release_boss(_boss_spot())


func _boss_spot() -> Vector3:
	var p := match_manager.player
	var you := p.global_position if p and p.alive else _start
	var to := _flat(you - falls_pos)
	var side := (to.normalized() if to.length() > 1.0 else Vector3.FORWARD).cross(Vector3.UP)
	# beside the dam, on whichever side is further from you (never under you:
	# coming up through the bedding, he'd throw you through it)
	var at := falls_pos + side * 32.0
	if _flat(falls_pos - side * 32.0 - you).length() > _flat(at - you).length():
		at = falls_pos - side * 32.0
	at += _flat(-falls_pos).normalized() * 8.0   # (off the glass)
	for i in 24:
		var tries := _ground(Vector2(at.x, at.z) + Vector2.from_angle(TAU * i / 8.0) * (i / 8) * 9.0)
		if _flat(tries - you).length() < 24.0:
			continue
		if island == null or island.scatter == null or not island.scatter.blocked(Vector2(tries.x, tries.z), MatchManager.BOSS_CLEARING, false):
			return tries
	return _ground(Vector2(at.x, at.z))


# ---- the end ------------------------------------------------------------------------------------------

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
	_outro = FoamOutro.new(self, rig, hud, pc)
	_outro.finished.connect(func(): end(true))
	add_child(_outro)
	return _outro


# ---- the bar on the HUD, the report -----------------------------------------------------------------

func bar_title() -> String:
	match step:
		Step.BURROWS:
			return "HIS BURROWS"
	return "WATER BOTTLE FALLS"


func bar_fill() -> float:
	match step:
		Step.BURROWS:
			return float(burrows.filter(func(b): return b.caved).size()) / maxf(1.0, burrows.size())
		Step.DAM:
			return float(dam.placed) / Dam.NEEDED if dam else 0.0
	return 1.0


func bar_color() -> Color:
	return Color(0.62, 0.5, 0.32) if step == Step.BURROWS else Dam.RING


func bar_status() -> String:
	var p := match_manager.player
	match step:
		Step.BURROWS:
			var open := burrows.filter(func(b): return not b.caved)
			var near := INF
			for b in open:
				near = minf(near, _flat((b as Node3D).global_position - p.global_position).length() if p else INF)
			return "%d of %d caved in  ·  blast them  ·  %d m" % [burrows.size() - open.size(), burrows.size(), roundi(near)] if near < INF \
				else "%d of %d caved in" % [burrows.size() - open.size(), burrows.size()]
		Step.DAM:
			var d := roundi(_flat(falls_pos - p.global_position).length()) if p else 0
			if p and ChewBlock.carried_by(p):
				return "%d of %d  ·  carry it into the ring  ·  %d m" % [dam.placed if dam else 0, Dam.NEEDED, d]
			return "%d of %d  ·  fetch a chew block" % [dam.placed if dam else 0, Dam.NEEDED]
		Step.WAKE:
			return "THE BEDDING'S MOVING!"
	return "NIBBLES IS DOWN!" if step == Step.DONE else ""


func bar_warn() -> bool:
	return step == Step.WAKE


func bar_good() -> bool:
	return step == Step.DONE


func bar_shown() -> bool:
	return step in [Step.BURROWS, Step.DAM, Step.WAKE]


func report() -> Dictionary:
	var r := super.report()
	r.erase("barn")
	r.erase("wave")
	r["caved"] = burrows.filter(func(b): return b.caved).size()
	r["burrows"] = burrows.size()
	r["placed"] = dam.placed if dam else 0
	r["step"] = Step.keys()[step].to_lower()
	if match_manager.boss:
		r["boss_time"] = match_manager.boss.fight_time()
	return r


func news(r: Dictionary) -> Array:
	return WarrenSim.foam_news(r)


func lost_text() -> String:
	return "There's nobody left to dam the falls."


func opening() -> Array:
	return ["CAVE IN HIS BURROWS", "The Touched keep coming up out of them. Shooting won't shut one: a blast will (%s throws a grenade)." % GameInput.prompt(&"grenade")]


func you_down_text(who: String, _left: int) -> String:
	return "Taken out by %s. Without you, the rangers climb back out of the cage." % who


func result(won: bool, r: Dictionary) -> Array:
	if won:
		return ["ACT III COMPLETE!", "Foam at the Falls: Nibbles is a good boy again, and the third Kernel is out. %d Touched beaten down, %d of %d rangers home." % [
			int(r.get("touched", 0)), int(r.get("rangers", 0)), KernelHunt.RANGERS.size()]]
	match step:
		Step.BURROWS:
			return ["THE BURROWS STAY OPEN", "%d of %d caved in before the Touched stopped you." % [int(r.get("caved", 0)), int(r.get("burrows", 0))]]
		Step.DAM:
			return ["THE FALLS STILL RUN", "%d of %d chew blocks in the dam." % [int(r.get("placed", 0)), Dam.NEEDED]]
	return ["NIBBLES WINS", "He came up out of the bedding and beat you at the falls. He's still thirsty."]


# ---- helpers -------------------------------------------------------------------------------------------

func _follow(r: Critter) -> void:
	var brain := r.get_node_or_null("AIBrain") as AIBrain
	if brain:
		brain.release()
		brain.escort = match_manager.player


## Buck Toothington (he carries the Kernels), if he's standing.
func _keeper() -> Critter:
	for r in rangers:
		if is_instance_valid(r) and r.alive and r.display_name == KernelHunt.RANGERS[0]:
			return r
	return null
