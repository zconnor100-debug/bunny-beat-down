class_name PatchMission
extends MissionDirector
## The Kernel Hunt's Act I, "The Carrot Patch" (KernelHunt): the tally on the
## Big Red Barn's door says 0, and the Barn Rangers want to know what the
## Touched came out of the Patch for. Built on the prologue (MissionDirector:
## the rangers, the Touched, the talk), in three parts, one after another
## (`step`):
##
## TRACK: the glowing carrots (GlowCarrot), five on a trail from the Barn into
##   the Carrot Patch, lit one at a time (its beam up), the Touched coming up
##   out of the dirt round each as it lights. Pull it up (hold interact) and
##   the next lights. The rangers stick by you.
## BURN: the Patch's rows and the bed beside them (BurnSpot): stand in each
##   ring, with none of the Touched in it, till it goes up, while the Touched
##   rush you from the Bluff side. The rangers hold the rings with you. All
##   three alight, the whole Patch burns and the ground starts to drum.
## WAKE: Boulder Bluff. Get close and Brutus comes for you (the Boss Battle's
##   arrival, and BossIntro), and the Warren answers: rogues who saw the smoke
##   glide in to fight him with you. Beat him down and the ending (PatchOutro):
##   he shrinks back into Little Bru, and the first Starfall Kernel is out.
##
## Go down yourself, or lose everyone on your side, and it's over.

enum Step { TRACK, BURN, WAKE, BOSS, DONE }

const CARROTS := 5
const TRAIL := [0.36, 0.52, 0.67, 0.82, 0.93]   ## how far along from the Barn to the Patch each carrot is...
const TRAIL_SIDE := [11.0, -13.0, 12.0, -10.0, 5.0]   ## ...and how far off to one side (the trail wanders)
const GUARDS := [2, 3, 3, 4, 5]          ## the Touched round each carrot (Scrappy; COUNT_SCALE for the others)
const GUARD_GUNS := [[&"carrot_pistol", &"carrot_smg"], [&"carrot_smg", &"carrot_rifle"], [&"carrot_smg", &"carrot_rifle", &"carrot_shotgun"],
	[&"carrot_rifle", &"carrot_shotgun", &"carrot_smg"], [&"carrot_rifle", &"carrot_shotgun", &"carrot_lmg"]]
const GUARD_RING := Vector2(7.0, 13.0)   ## how far round its carrot a guard stands
const RUSH_EVERY := 21.0       ## seconds between the Touched's rushes at the burning
const RUSH_FIRST := 8.0
const RUSH := 4                ## the Touched in a rush (Scrappy)
const RUSH_FROM := 70.0        ## metres out (on the Bluff side) a rush starts
const RUSH_GUNS := [&"carrot_smg", &"carrot_rifle", &"carrot_shotgun", &"carrot_lmg"]
const WAKE_AT := 85.0          ## metres from the Bluff where he comes for you
const WAKE_ANYWAY := 120.0     ## seconds after the Patch burns that he comes anyway
const BOSS_HEALTH := 0.55      ## of a Boss Battle's Brutus (there are fewer of you)
const ANSWER_AFTER := 7.0      ## seconds after he lands that the Warren answers
const OUTRO_AFTER := 3.4       ## seconds after he's down (his fall) that the ending starts
const FIRST_LIT := 4.0         ## seconds in that the first carrot lights (the act's card has had its moment)

var step := Step.TRACK
var carrots: Array[GlowCarrot] = []
var pulled := 0
var spots: Array[BurnSpot] = []
var answered: Array[Critter] = []
var patch_fire: Fire
var _bluff_mark: Node3D
var _rush_t := RUSH_FIRST
var _down_t := -1.0
var _wake_t := 0.0
var _wake_from := 1.0


func _init() -> void:
	super._init()
	mission = "carrot_patch"
	tally_days = 0


## Everything the prologue sets up (the rangers, the tally, at 0 now), the
## carrots' trail, and Brutus, parked till he's woken.
func setup(mm: MatchManager) -> void:
	super.setup(mm)
	_plan_trail()
	mm._make_boss()
	if mm.boss:
		mm.boss.max_health *= BOSS_HEALTH
		mm.boss.health = mm.boss.max_health


func wants_boss() -> bool:
	return true


## You and the rangers on the Patch side of the Barn; the first carrot
## lights a moment later (FIRST_LIT).
func begin() -> void:
	var fwd := _flat(patch_pos - barn_pos).normalized()
	var side := fwd.cross(Vector3.UP)
	var start := _ground_at(barn_pos + fwd * 22.0)
	for i in rangers.size():
		var r := rangers[i]
		r.place_at(_ground_at(start - fwd * 4.5 + side * ((i - (rangers.size() - 1) * 0.5) * 2.6)), atan2(-fwd.x, -fwd.z))
		_follow(r)
	_arm_player(start, atan2(-fwd.x, -fwd.z))
	stage = Stage.WAVE
	step = Step.TRACK
	_t = 0.0
	match_manager._set_phase(MatchManager.Phase.PLAYING)
	get_tree().create_timer(FIRST_LIT, false).timeout.connect(func(): _light(0))
	get_tree().create_timer(5.0, false).timeout.connect(func(): _shout("pt", 0, _keeper()))


func _process(delta: float) -> void:
	if match_manager == null or match_manager.phase != MatchManager.Phase.PLAYING:
		return
	_clock += delta
	_t += delta
	match step:
		Step.BURN:
			_tend_burn(delta)
		Step.WAKE:
			_tend_wake(delta)
		Step.DONE:
			if _down_t >= 0.0:
				_down_t += delta
				if _down_t >= OUTRO_AFTER and stage != Stage.OUTRO:
					stage = Stage.OUTRO
					_play_outro()


# ---- the glowing carrots ---------------------------------------------------------------------------

## The trail: from the Barn out to the Patch, wandering side to side, each
## carrot on clear ground.
func _plan_trail() -> void:
	var to := _flat(patch_pos - barn_pos)
	var fwd := to.normalized()
	var side := fwd.cross(Vector3.UP)
	for i in CARROTS:
		var at := barn_pos + to * float(TRAIL[i]) + side * float(TRAIL_SIDE[i])
		var spot := island.clear_loot_spot(_ground_at(at), Vector3(0.4, 0.9, 0.4)) if island else at
		var c := GlowCarrot.new()
		c.name = "GlowCarrot%d" % (i + 1)
		match_manager.world_root.add_child(c)
		c.global_position = _ground_at(spot if spot != Vector3.INF else at)
		c.used.connect(_on_pulled.bind(i))
		carrots.append(c)


## Carrot `i` lights (its beam up), and the Touched come up out of the dirt round it.
func _light(i: int) -> void:
	var c := carrots[i]
	c.light_up()
	var n := maxi(1, roundi(float(GUARDS[i]) * float(KernelHunt.COUNT_SCALE[clampi(match_manager._difficulty, 0, 2)])))
	var from := match_manager.player.global_position if match_manager.player else barn_pos
	var away := _flat(c.global_position - from).normalized()
	for k in n:
		# round the far side of it from you, spread out
		var a := lerpf(-1.3, 1.3, (k + 0.5) / n) + _rng.randf_range(-0.2, 0.2)
		var at := _ground_at(c.global_position + away.rotated(Vector3.UP, a) * _rng.randf_range(GUARD_RING.x, GUARD_RING.y))
		var guns: Array = GUARD_GUNS[i]
		var t := _spawn_touched(at, guns[_rng.randi() % guns.size()], false, at, c.global_position + Vector3.UP)
		BossFX.dust(at, 2.4, Color(0.42, 0.33, 0.22, 0.7))
		if t:
			t.look_yaw = atan2(-(from - at).x, -(from - at).z)
	Events.alive_count_changed.emit(match_manager.alive_critters().size(), match_manager.total)


func _on_pulled(by: Critter, i: int) -> void:
	pulled += 1
	if pulled < CARROTS:
		Events.announce.emit("GLOWING CARROT %d OF %d" % [pulled, CARROTS], "It's warm, and it hums. The next is lit: follow its light.")
		_light(i + 1)
		# (the rangers take turns: what it's like, then where the next is)
		if pulled % 2 == 1:
			_shout("pp", pulled / 2, ranger_near(by.global_position))
		else:
			var k := pulled / 2 - 1
			get_tree().create_timer(2.6, false).timeout.connect(func(): _shout("pc", k))
	else:
		_start_burn()


# ---- burning the Patch ------------------------------------------------------------------------------

func _start_burn() -> void:
	step = Step.BURN
	_t = 0.0
	_rush_t = RUSH_FIRST
	for at in _burn_spots():
		var s := BurnSpot.new()
		match_manager.world_root.add_child(s)
		s.global_position = at
		s.caught.connect(_on_caught)
		spots.append(s)
	Events.announce.emit("BURN THE CARROT PATCH", "Stand in each ring, with none of the Touched in it, till it goes up.")
	_shout("pf", 0, _keeper())
	_post_rangers()


## The Patch's two rows, and the bed beside them (square to the rows, on the
## side away from the Barn).
func _burn_spots() -> Array:
	var patch := _poi("Carrot Patch", "carrot_patch")
	var out := []
	for row in patch.get("rows", []):
		out.append(_ground(row as Vector2))
	var fwd := _flat(patch_pos - barn_pos).normalized()
	if out.size() < 2:
		var side := fwd.cross(Vector3.UP)
		out = [_ground_at(patch_pos + side * 7.0), _ground_at(patch_pos - side * 7.0)]
	var across := _flat(out[1] - out[0]).normalized().cross(Vector3.UP)
	if across.dot(fwd) < 0.0:
		across = -across
	out.append(_ground_at(patch_pos + across * 11.0))
	return out


func _tend_burn(delta: float) -> void:
	_rush_t -= delta
	if _rush_t <= 0.0:
		_rush_t = RUSH_EVERY
		_rush()


## The Touched rush the rings still to go up, from the Bluff side.
func _rush() -> void:
	var left := spots.filter(func(s): return not s.lit)
	if left.is_empty():
		return
	var n := maxi(2, roundi(RUSH * float(KernelHunt.COUNT_SCALE[clampi(match_manager._difficulty, 0, 2)])))
	var to_bluff := _flat(bluff_pos - patch_pos).normalized()
	for k in n:
		var s: BurnSpot = left[k % left.size()]
		var a := _rng.randf_range(-0.8, 0.8)
		var from := patch_pos + to_bluff.rotated(Vector3.UP, a) * RUSH_FROM
		var at := island.random_land_point(2.0, Vector2(from.x, from.z), 12.0) if island else from
		var post := _ground_at(s.global_position + Vector3(_rng.randf_range(-2.5, 2.5), 0.0, _rng.randf_range(-2.5, 2.5)))
		_spawn_touched(at if at != Vector3.INF else from, RUSH_GUNS[_rng.randi() % RUSH_GUNS.size()], false, post, s.global_position)
	Events.alive_count_changed.emit(match_manager.alive_critters().size(), match_manager.total)
	if _say_ok("kw"):
		_shout("kw", 0)


func _on_caught() -> void:
	var lit := spots.filter(func(s): return s.lit).size()
	if lit < spots.size():
		Events.announce.emit("%d OF %d ALIGHT" % [lit, spots.size()], "Keep the Touched off the rest.")
		_shout("pl", (lit - 1) % 2)
		_post_rangers()
		return
	_patch_burns()


## A ranger or two in each ring still to go up (they fight whoever comes,
## and go back to it); the rest stick by you.
func _post_rangers() -> void:
	var left := spots.filter(func(s): return not s.lit)
	var k := 0
	for r in rangers:
		if not is_instance_valid(r) or not r.alive:
			continue
		var brain := r.get_node_or_null("AIBrain") as AIBrain
		if brain == null:
			continue
		if left.is_empty() or k >= left.size() * 2:
			_follow(r)
			continue
		var s: BurnSpot = left[k % left.size()]
		var a := TAU * k / maxf(1.0, left.size() * 2.0)
		brain.escort = null
		brain.hold(_ground_at(s.global_position + Vector3(cos(a), 0.0, sin(a)) * BurnSpot.RADIUS * 0.45), s.global_position + Vector3.UP, 600.0)
		k += 1


## The whole Patch goes up, and the ground starts to drum: off to the Bluff.
func _patch_burns() -> void:
	step = Step.WAKE
	_t = 0.0
	_wake_t = 0.0
	patch_fire = Fire.new(20.0, false)
	match_manager.world_root.add_child(patch_fire)
	patch_fire.global_position = patch_pos
	patch_fire.grow(4.0)
	for r in rangers:
		if is_instance_valid(r) and r.alive:
			_follow(r)
	_bluff_mark = Node3D.new()
	_bluff_mark.name = "BoulderBluff"
	_bluff_mark.add_to_group(&"objectives")
	match_manager.world_root.add_child(_bluff_mark)
	_bluff_mark.global_position = bluff_pos + Vector3.UP * 4.0
	var p := match_manager.player
	_wake_from = maxf(1.0, _flat(bluff_pos - p.global_position).length() - WAKE_AT) if p else 1.0
	Events.announce.emit("THE PATCH IS BURNING", "And the ground is drumming. Something under Boulder Bluff is waking up.")
	get_tree().create_timer(2.5, false).timeout.connect(_drum)
	get_tree().create_timer(3.0, false).timeout.connect(func(): _shout("pd", 0, _keeper()))
	get_tree().create_timer(7.0, false).timeout.connect(func(): _shout("pd", 1))


## The ground drums (from the Bluff): a thump you feel.
func _drum() -> void:
	if step != Step.WAKE:
		return
	Audio.play_at(&"boss_stomp", bluff_pos, 10.0, 0.0, {"max_distance": 3000.0, "unit_size": 120.0})
	var p := match_manager.player
	if p:
		Events.explosion.emit(p.global_position + _flat(bluff_pos - p.global_position).normalized() * 30.0, 9.0)


func _tend_wake(delta: float) -> void:
	_wake_t += delta
	if fmod(_wake_t, 9.0) < delta:
		_drum()
	var p := match_manager.player
	var near := p != null and p.alive and _flat(bluff_pos - p.global_position).length() < WAKE_AT
	if near or _wake_t > WAKE_ANYWAY:
		_wake()


## He comes: down off the Bluff onto open ground between it and you.
func _wake() -> void:
	step = Step.BOSS
	_t = 0.0
	if _bluff_mark:
		_bluff_mark.queue_free()
		_bluff_mark = null
	for r in rangers:
		if is_instance_valid(r) and r.alive:
			var brain := r.get_node_or_null("AIBrain") as AIBrain
			if brain:
				brain.release()
	match_manager.release_boss(_boss_spot())
	get_tree().create_timer(match_manager.boss.land_time + ANSWER_AFTER if match_manager.boss else ANSWER_AFTER, false).timeout.connect(_answer)


func _boss_spot() -> Vector3:
	var p := match_manager.player
	var from := p.global_position if p and p.alive else patch_pos
	var to := _flat(from - bluff_pos)
	var at := bluff_pos + to.normalized() * maxf(to.length() - 34.0, 0.0)
	for i in 24:
		var tries := _ground(Vector2(at.x, at.z) + Vector2.from_angle(TAU * i / 8.0) * (i / 8) * 9.0)
		if island == null or island.scatter == null or not island.scatter.blocked(Vector2(tries.x, tries.z), MatchManager.BOSS_CLEARING, false):
			return tries
	return _ground(Vector2(at.x, at.z))


## The Warren answers: rogues who saw the smoke, gliding down round you.
func _answer() -> void:
	if step != Step.BOSS:
		return
	var p := match_manager.player
	var round_ := p.global_position if p and p.alive else bluff_pos
	var names: Array = KernelHunt.ANSWER
	for i in names.size():
		var a := TAU * i / names.size() + _rng.randf_range(-0.3, 0.3)
		var land := _ground_at(round_ + Vector3(cos(a), 0.0, sin(a)) * _rng.randf_range(12.0, 22.0))
		var c := _spawn_ranger(String(names[i]))
		rangers.erase(c)   # (they aren't the Barn's: the report counts the rangers)
		answered.append(c)
		var brain := c.get_node_or_null("AIBrain") as AIBrain
		if brain:
			brain.drop_spot = land
		c.begin_freefall(land + Vector3(cos(a), 0.0, sin(a)) * 25.0 + Vector3.UP * 70.0, Vector3.ZERO)
	Events.announce.emit("THE WARREN ANSWERS", "%d rogues saw the smoke and came." % names.size())
	Events.alive_count_changed.emit(match_manager.alive_critters().size(), match_manager.total)
	get_tree().create_timer(3.0, false).timeout.connect(func():
		if not answered.is_empty() and is_instance_valid(answered[0]) and answered[0].alive:
			_shout("pw", 0, answered[0]))


## You're down: nobody else can pull the carrots or carry it on (in the
## prologue the rangers hold the Barn without you; not here).
func critter_down(c: Critter, info: DamageInfo) -> void:
	super.critter_down(c, info)
	if c == match_manager.player and stage != Stage.OVER and stage != Stage.OUTRO:
		end(false)


## Brutus is down (MatchManager routes it here in a mission): his fall, then the ending.
func boss_down(_by: Node) -> void:
	if step == Step.DONE:
		return
	step = Step.DONE
	_down_t = 0.0


func play_outro(rig: CameraRig = null, hud: CanvasLayer = null, pc: PlayerController = null) -> MissionCinematic:
	_outro = PatchOutro.new(self, rig, hud, pc)
	_outro.finished.connect(func(): end(true))
	add_child(_outro)
	return _outro


# ---- the bar on the HUD, the report -----------------------------------------------------------------

func bar_title() -> String:
	match step:
		Step.TRACK:
			return "THE GLOWING CARROTS"
		Step.BURN:
			return "BURN THE CARROT PATCH"
	return "BOULDER BLUFF"


func bar_fill() -> float:
	match step:
		Step.TRACK:
			return float(pulled) / CARROTS
		Step.BURN:
			return spots.reduce(func(a, s): return a + s.progress, 0.0) / maxf(1.0, spots.size())
		Step.WAKE:
			var p := match_manager.player
			return clampf(1.0 - (_flat(bluff_pos - p.global_position).length() - WAKE_AT) / _wake_from, 0.0, 1.0) if p else 0.0
	return 1.0


func bar_color() -> Color:
	return Fire.FLAME if step in [Step.BURN, Step.WAKE] else GlowCarrot.GLOW


func bar_status() -> String:
	var p := match_manager.player
	match step:
		Step.TRACK:
			var c := carrots[mini(pulled, CARROTS - 1)]
			var d := roundi(c.global_position.distance_to(p.global_position)) if p else 0
			return "Carrot %d of %d  ·  %d m" % [pulled + 1, CARROTS, d]
		Step.BURN:
			var lit := spots.filter(func(s): return s.lit).size()
			if spots.any(func(s): return not s.lit and s.theirs > 0 and s.ours > 0):
				return "THE TOUCHED ARE IN THE RING!  ·  %d of %d alight" % [lit, spots.size()]
			return "%d of %d alight  ·  stand in a ring" % [lit, spots.size()]
		Step.WAKE:
			var d := roundi(_flat(bluff_pos - p.global_position).length()) if p else 0
			return "Something's waking at Boulder Bluff  ·  %d m" % d
	return "BRUTUS IS DOWN!" if step == Step.DONE else ""


func bar_warn() -> bool:
	return step == Step.BURN and spots.any(func(s): return not s.lit and s.theirs > 0)


func bar_good() -> bool:
	return step == Step.DONE


## Up while there's no boss bar (the boss's bar takes over once he's here).
func bar_shown() -> bool:
	return step in [Step.TRACK, Step.BURN, Step.WAKE]


func report() -> Dictionary:
	var r := super.report()
	r.erase("barn")
	r.erase("wave")
	r["carrots"] = pulled
	r["alight"] = spots.filter(func(s): return s.lit).size()
	r["step"] = Step.keys()[step].to_lower()
	r["answered"] = answered.filter(func(c): return is_instance_valid(c) and c.alive).map(func(c): return c.display_name)
	if match_manager.boss:
		r["boss_time"] = match_manager.boss.fight_time()
	return r


func news(r: Dictionary) -> Array:
	return WarrenSim.patch_news(r)


func lost_text() -> String:
	return "There's nobody left to take the Patch."


func opening() -> Array:
	return ["FOLLOW THE GLOWING CARROTS", "The first is lit: its light goes up over the grass. Hold %s by it to pull it up." % GameInput.prompt(&"interact")]


func you_down_text(who: String, _left: int) -> String:
	return "Taken out by %s. Without you, the rangers fall back to the Barn." % who


func result(won: bool, r: Dictionary) -> Array:
	if won:
		return ["ACT I COMPLETE!", "The Carrot Patch: Brutus is Little Bru again, and the first Kernel is out. %d Touched beaten down, %d of %d rangers home." % [
			int(r.get("touched", 0)), int(r.get("rangers", 0)), KernelHunt.RANGERS.size()]]
	match step:
		Step.TRACK:
			return ["THE TRAIL WENT COLD", "The Touched stopped you on the trail: %d of %d glowing carrots pulled." % [pulled, CARROTS]]
		Step.BURN:
			return ["THE PATCH WON'T BURN", "The Touched held the Carrot Patch: %d of %d rings alight." % [spots.filter(func(s): return s.lit).size(), spots.size()]]
	return ["BRUTUS WINS", "He beat you at Boulder Bluff. %d Touched beaten down on the way." % int(r.get("touched", 0))]


# ---- helpers -------------------------------------------------------------------------------------------

## A ranger sticks by you (as your squad does in a Team Battle).
func _follow(r: Critter) -> void:
	var brain := r.get_node_or_null("AIBrain") as AIBrain
	if brain:
		brain.release()
		brain.escort = match_manager.player


## Buck Toothington, who keeps the tally, if he's standing (else whoever's nearest you).
func _keeper() -> Critter:
	for r in rangers:
		if is_instance_valid(r) and r.alive and r.display_name == KernelHunt.RANGERS[0]:
			return r
	return null
