class_name AIBrain
extends Node
## Bot "player". It writes the same intent fields a human does (move stick,
## look angles, trigger), so it obeys every rule of movement, spread, recoil
## and reloading. Skill only changes how *well* it uses those controls:
## reaction time, aim error, turn speed, and how bravely it fights.
##
## Decision loop (every ~0.2 s): perceive → pick a mode:
##   DROP → LOOT → ROAM, interrupted by FIGHT, HEAL and FLEE_STORM.
##
## Seeing is not knowing: every critter in view fills an awareness meter,
## fast when it is close, moving, in front of the bot or firing, slowly when
## it is far, still, crouched or hidden in grass and bushes. Only a full meter
## makes it a target. Getting shot turns the bot toward the noise; it still
## has to spot the shooter.

enum Mode { DROP, LOOT, ROAM, FIGHT, HEAL, FLEE_STORM }

const THINK_INTERVAL := 0.2
const VISION_RANGE := 75.0
const HEARING_RANGE := 45.0
const FOV_DOT := -0.1             ## ~190° awareness cone
const MEMORY := 4.0               ## seconds a lost target is remembered
const SPOT_RATE := 1.6            ## awareness/s: close, in the open, in front, moving
const AWARENESS_FADE := 0.25      ## awareness/s lost while out of sight
## head, chest and hips: how much each counts toward being seen
const BODY_POINTS := [[0.9, 0.3], [0.6, 0.45], [0.3, 0.25]]

## How many bots may shoot at the player at once (set per difficulty by
## MatchManager): the rest keep their distance and wait their turn, so the
## player gets fights, not a firing squad.
static var player_attack_slots := 2
## Damage bots deal to the player is multiplied by this (per difficulty).
static var damage_to_player := 0.65
## Bots fighting each other hit softer too: at full damage a 50-critter lobby
## was mostly gone in a minute and a half, before the player met anyone.
const DAMAGE_BETWEEN_BOTS := 0.35
## Set by the director (MatchManager.bots_may_kill) while the lobby is thinning
## faster than its curve: bots still fight each other just as often, but hit
## each other this much softer, so most scraps end with the loser running off.
static var kills_held := false
const HELD_DAMAGE := 0.15
static var _player_attackers: Dictionary = {}   # brain instance id -> msec its slot expires
const ATTACK_SLOT_HOLD_MS := 1500
const BRAWL_RANGE := 7.0          ## unarmed bots club anyone this close instead of fleeing
## Fresh off the drop, bots loot before they pick fights with each other (they
## still fight back, still fight whoever lands right next to them, and still
## come for you): without it half the lobby beat each other down in the first
## minute and the player met nobody.
const SETTLE_SECONDS := 30.0
const SETTLE_FIGHT_RANGE := 12.0
## Bots start fights with each other only up close (they come for you from as
## far as they can see you): this is the player's battle royale. Up close they
## always do: bots who see each other and walk on by look like teams.
const BOT_FIGHT_RANGE := 30.0
## Losing a scrap with another bot (this low, and lower than the other), a bot
## breaks off for a while to heal or hide instead of fighting to the last carrot.
const BREAK_OFF_HEALTH := 45.0
const BREAK_OFF_SECONDS := 12.0

var me: Critter
var island: Island
var match_manager: Node           ## MatchManager (duck-typed: storm queries)
var skill := 0.6                  ## 0..1
var mode := Mode.ROAM
var target: Critter
var drop_spot := Vector3.ZERO
var drop_progress := 0.5          ## when along the balloon route to jump
var personality := ""             ## see RivalBook.PERSONALITIES
var rival := false                ## this bot has your number: it hunts you
## How this bot fights (Cast.traits_for: its style, pushed further the more
## radical you've made it). A missing key means the default bot's way.
var traits: Dictionary = {}
## The bots it holds a grudge against (RivalBook.grudges): it goes after them
## first, from further off, even while it's still settling in.
var grudges: Dictionary = {}
const GRUDGE_FIGHT_RANGE := 2.0   ## x its fight range, for a bot it has a grudge against
var _next_sense := 0.0            # (a radical bot's next "where are you?")
## How the player likes to fight, learned over past matches (PlayerProfile):
## "close" → bots keep their distance from you, "far" → they rush you.
static var player_style := ""
static var player_stealth := 1.0  ## the Light Step perk: bots spot you this much slower
## The Muffler (Workshop): bots hear your shots half as far, and your muzzle
## flash doesn't give you away.
static var player_muffled := false
## How far everyone sees, times this (Pea Soup, a run modifier).
static var vision_scale := 1.0
var _hunt_pos := Vector3.INF      # the director sent us to flush the player out of hiding
var _hunt_until := 0.0

var _think_t := randf() * THINK_INTERVAL
var _last_seen_pos := Vector3.ZERO
var _last_seen_t := -100.0
var _spotted_t := -100.0
var _aim_err := Vector3.ZERO
var _path := PackedVector3Array()
var _path_i := 0
var _dest := Vector3.INF
var _repath_t := 0.0
var _loot_goal: Node3D
var _strafe := 1.0
var _strafe_t := 0.0
var _stuck_t := 0.0
var _stuck_pos := Vector3.ZERO
var _fire_toggle := false
var _clock := 0.0
var _heard_pos := Vector3.INF
var _heard_t := -100.0
var _awareness: Dictionary = {}   # Critter -> 0..1.5
var _shots_seen: Dictionary = {}  # Critter -> clock of its last shot (a muzzle flash gives you away)
var _last_perceive := 0.0
var _target_vis := 1.0            # how much of the target is showing (0..1)
var _alert_pos := Vector3.INF     # where a shot that hit us came from (roughly)
var _alert_t := -100.0
var _bursting := false
var _burst_t := 0.0
## Loot we couldn't reach (behind rocks, on a roof…): ignored for a while.
var _unreachable: Dictionary = {}   # node -> clock time it can be tried again
var _goal_since := 0.0
var _landed_at := -1.0             # (see SETTLE_SECONDS)
var _provoked: Dictionary = {}     # Critter -> clock it last hurt us
var _avoid: Dictionary = {}        # Critter -> clock until which we leave it alone
var _goal_best := INF
var _goal_tracked: Node3D   # patience is per loot node: re-picking the same one doesn't reset it
const GOAL_PATIENCE := 8.0
const UNREACHABLE_FOR := 60.0


func _ready() -> void:
	me = get_parent() as Critter
	Events.shot_fired.connect(_on_shot_heard)
	Events.critter_damaged.connect(_on_damaged)


func _physics_process(delta: float) -> void:
	if me == null or not me.alive or me.state == Critter.State.IN_DROPSHIP:
		return
	_clock += delta
	if _landed_at < 0.0 and me.state == Critter.State.GROUND:
		_landed_at = _clock
	_think_t -= delta
	if _think_t <= 0.0:
		_think_t = THINK_INTERVAL * randf_range(0.8, 1.2)
		_think()
	match me.state:
		Critter.State.FREEFALL, Critter.State.GLIDING:
			_steer_drop()
		_:
			_act(delta)


# ---- perception -------------------------------------------------------------------------------

func _think() -> void:
	if me.state != Critter.State.GROUND:
		mode = Mode.DROP
		return
	_perceive()
	_choose_mode()


func _perceive() -> void:
	var dt := clampf(_clock - _last_perceive, 0.0, 0.5)
	_last_perceive = _clock
	var eye := me.get_eye_position()
	var fwd := me.look_direction()
	var space := me.get_world_3d().direct_space_state
	var cover: Scatter = island.scatter if island else null
	var best: Critter = null
	var best_score := INF
	var best_vis := 0.0
	var range_ := VISION_RANGE * lerpf(0.7, 1.15, skill) * vision_scale
	var seen := {}
	for c in me.get_tree().get_nodes_in_group(&"critters"):
		var other := c as Critter
		if other == null or other == me or not other.alive or other.state != Critter.State.GROUND:
			continue
		var to := other.get_chest_position() - eye
		var d := to.length()
		if d > range_:
			continue
		var facing := to.normalized().dot(fwd)
		if d > 10.0 and facing < FOV_DOT:
			continue
		var vis := _visibility_of(other, eye, space, cover)
		if vis < 0.02:
			continue
		seen[other] = true
		# fill the awareness meter
		var near := clampf(1.25 - d / range_, 0.2, 1.0)
		var ahead := lerpf(0.4, 1.0, smoothstep(FOV_DOT, 0.8, facing))
		var moving := 0.5 + 0.5 * clampf(Vector2(other.velocity.x, other.velocity.z).length() / 3.0, 0.0, 1.0)
		var flash := 3.0 if _clock - float(_shots_seen.get(other, -100.0)) < 1.0 else 1.0
		var rate := SPOT_RATE * lerpf(0.6, 1.4, skill) * near * ahead * moving * flash * vis * (player_stealth if other.is_player else 1.0) * _t("spot", 1.0)
		var aware := minf(1.5, float(_awareness.get(other, 0.0)) + rate * dt)
		_awareness[other] = aware
		# a target is someone we're sure of (or still tracking)
		if aware < (0.5 if other == target else 1.0):
			continue
		# the other bot is far off, or we just landed and it isn't right here:
		# leave it be, unless it started it (or we've a score to settle)
		var grudge := not other.is_player and grudges.has(other.display_name)
		var reach := _t("fight_range", BOT_FIGHT_RANGE) * (GRUDGE_FIGHT_RANGE if grudge else 1.0)
		if not other.is_player and (d > reach or (settling() and d > SETTLE_FIGHT_RANGE and not grudge)) \
				and _clock - float(_provoked.get(other, -100.0)) > 8.0:
			continue
		if not other.is_player and _clock < float(_avoid.get(other, -1.0)):
			continue   # (one of us broke off from the other)
		# prefer close, weak (a vulture more so), whoever is already our target
		# (a duelist more so), a bot we hold a grudge against, and (a rival,
		# a radical) you
		var score := d * (0.6 + other.health / 200.0 * _t("weak", 1.0)) * (_t("sticky", 0.6) if other == target else 1.0) \
			* (0.35 if rival and other.is_player else 1.0) * (_t("player_focus", 1.0) if other.is_player else 1.0) * (0.4 if grudge else 1.0)
		if score < best_score:
			best_score = score
			best = other
			best_vis = vis
	for k in _awareness.keys():
		if not is_instance_valid(k) or not (k as Critter).alive:
			_awareness.erase(k)
		elif not seen.has(k):
			_awareness[k] = maxf(0.0, float(_awareness[k]) - AWARENESS_FADE * dt)
	if best:
		if best != target or _clock - _last_seen_t > 1.0:
			_spotted_t = _clock
			if best.is_player and match_manager and match_manager.has_method("taunt") and (rival or traits.get("hunts_you", false) or randf() < 0.1):
				match_manager.taunt(me, "spot")
			elif not best.is_player and grudges.has(best.display_name) and match_manager and match_manager.has_method("feud"):
				match_manager.feud(me, best)
			# half-hidden targets are harder to aim at
			_aim_err = _random_aim_error(eye.distance_to(best.get_chest_position())) * (1.0 + (1.0 - best_vis) * 1.5)
		target = best
		_target_vis = best_vis
		_last_seen_pos = best.get_chest_position()
		_last_seen_t = _clock
	elif target and (not target.alive or _clock - _last_seen_t > MEMORY * _t("memory", 1.0)):
		target = null


## How much of `other` shows from `eye`: head, chest and hips each count if no
## solid thing is in the way, and less through the leaves. 0 = hidden.
func _visibility_of(other: Critter, eye: Vector3, space: PhysicsDirectSpaceState3D, cover: Scatter) -> float:
	# crouching lowers the outline; lying flat puts it down in the grass
	var h := (other.visual.rig.world_head_top if other.visual and other.visual.rig else 1.0) \
		* (1.0 - 0.3 * other.crouch_amount()) * lerpf(1.0, 0.25, other.prone_amount())
	var pts := PackedVector3Array()
	var shown := 0.0
	for bp in BODY_POINTS:
		var pt := other.global_position + Vector3.UP * h * float(bp[0])
		var q := PhysicsRayQueryParameters3D.create(eye, pt, Layers.SIGHT_MASK)
		if not space.intersect_ray(q):
			pts.append(pt)
			shown += float(bp[1])
	if pts.is_empty():
		return 0.0
	return shown * (cover.visibility(eye, pts) if cover else 1.0)


## How sure this bot is that it has seen `c` (0..1.5; 1 = spotted).
func awareness_of(c: Critter) -> float:
	return float(_awareness.get(c, 0.0))


func _random_aim_error(dist: float) -> Vector3:
	var mag := dist * lerpf(0.11, 0.025, skill) + lerpf(0.6, 0.15, skill)
	return Vector3(randf_range(-1, 1), randf_range(-0.6, 0.8), randf_range(-1, 1)).normalized() * mag


func _on_shot_heard(shooter: Node, origin: Vector3, _id: StringName) -> void:
	if shooter == me or me == null or not me.alive:
		return
	var muffled := player_muffled and shooter is Critter and (shooter as Critter).is_player
	if not muffled:
		_shots_seen[shooter] = _clock
	if origin.distance_to(me.global_position) < HEARING_RANGE * _t("gunfire", 1.0) * (0.5 if muffled else 1.0):
		_heard_pos = origin
		_heard_t = _clock


func _on_damaged(victim: Node, info: DamageInfo) -> void:
	if victim != me or info.attacker == null or info.attacker == me or not info.attacker is Critter:
		return
	# getting shot says roughly where it came from: turn that way and go and
	# look (the bot still has to spot the shooter before it fires back)
	var attacker := info.attacker as Critter
	_provoked[attacker] = _clock
	var err := me.global_position.distance_to(attacker.global_position) * 0.15
	_alert_pos = attacker.global_position + Vector3(randf_range(-err, err), 0.0, randf_range(-err, err))
	_alert_t = _clock
	_heard_pos = _alert_pos
	_heard_t = _clock
	_awareness[attacker] = maxf(float(_awareness.get(attacker, 0.0)), 0.6)
	_think_t = minf(_think_t, 0.05)


## A trait number (see `traits`), or the default bot's.
func _t(key: String, default: float) -> float:
	return float(traits.get(key, default))


## Still settling in after the drop (see SETTLE_SECONDS).
func settling() -> bool:
	return _landed_at >= 0.0 and _clock - _landed_at < SETTLE_SECONDS * _t("settle", 1.0)


## Recently shot: keep looking toward where it came from.
func _alerted() -> bool:
	return _alert_pos != Vector3.INF and _clock - _alert_t < 2.5


# ---- decisions -------------------------------------------------------------------------------------

func _choose_mode() -> void:
	var armed := me.inventory.has_any_weapon() and _usable_weapon_slot() >= 0
	var threatened := _storm_unsafe(me.global_position)
	if not threatened and mode == Mode.FLEE_STORM:
		# keep running until comfortably inside, or bots dither on the edge
		# (step in → loot just outside looks good → step out → flee → …)
		var c: Vector2 = match_manager.safe_center()
		var away := Vector3(me.global_position.x - c.x, 0.0, me.global_position.z - c.y)
		threatened = away.length() > 0.5 and _storm_unsafe(me.global_position + away.normalized() * STORM_MARGIN)
	if threatened:
		if target == null or not armed or me.health < 40.0:
			mode = Mode.FLEE_STORM
			return
	if target and not target.is_player and me.health < _t("break_off", BREAK_OFF_HEALTH) and me.health < target.health:
		# losing to another bot: break off, run, patch up (two beaten-up bots
		# still have it out: running from everyone, they'd wander about together)
		_avoid[target] = _clock + BREAK_OFF_SECONDS
		var away := me.global_position - target.global_position
		away.y = 0.0
		_set_dest(me.global_position + away.normalized() * 30.0)
		target = null
		mode = Mode.HEAL if me.inventory.clovers > 0 else Mode.ROAM
		return
	if target and armed:
		mode = Mode.FIGHT
		return
	if target and not armed:
		# bare paws: club them if they're right here, else go find a gun
		mode = Mode.FIGHT if target.global_position.distance_to(me.global_position) < BRAWL_RANGE else Mode.LOOT
		return
	if me.health < _t("heal_at", 60.0) and me.inventory.clovers > 0:
		mode = Mode.HEAL
		return
	if traits.get("hunts_you", false) and armed and _clock >= _next_sense and match_manager and match_manager.player \
			and match_manager.player.alive and match_manager.player.state == Critter.State.GROUND and not settling():
		# radical: it goes looking for you (roughly where you are)
		_next_sense = _clock + (25.0 if traits.get("no_slot", false) else 45.0)
		var you: Vector3 = match_manager.player.global_position
		hunt(you + Vector3(randf_range(-15, 15), 0, randf_range(-15, 15)), 20.0)
	if _hunt_pos != Vector3.INF and _clock < _hunt_until and armed:
		_set_dest(_hunt_pos)   # (roaming toward where the player is hiding)
		mode = Mode.ROAM
		return
	if _wants_loot():
		mode = Mode.LOOT
		return
	if _heard_pos != Vector3.INF and _clock - _heard_t < 6.0 and armed and skill * _t("gunfire", 1.0) > 0.35:
		_set_dest(_heard_pos)
		_heard_pos = Vector3.INF
	mode = Mode.ROAM


const STORM_MARGIN := 8.0


func _storm_unsafe(pos: Vector3) -> bool:
	return match_manager != null and match_manager.has_method("storm_threat") and match_manager.storm_threat(pos) > 0.0


func _wants_loot() -> bool:
	_loot_goal = _find_loot()
	return _loot_goal != null


func _find_loot() -> Node3D:
	var best: Node3D = null
	var best_d := 38.0
	var pos := me.global_position
	var weapons_full := me.inventory.first_free_slot() < 0
	var worst := INF
	for w in me.inventory.weapons:
		worst = minf(worst, Inventory.weapon_score(w))
	for n in me.get_tree().get_nodes_in_group(&"pickups"):
		var p := n as Pickup
		if p == null:
			continue
		var d := p.global_position.distance_to(pos)
		if d >= best_d or _clock < float(_unreachable.get(p, -1.0)) or _storm_unsafe(p.global_position):
			continue
		# never re-grab what we just dropped (prevents swap ping-pong)
		if p.dropped_by == me and Time.get_ticks_msec() - p.dropped_msec < 30000:
			continue
		match p.spec.get("type"):
			"weapon":
				var fav: bool = p.spec["weapon"] is WeaponInstance and String((p.spec["weapon"] as WeaponInstance).data.id) == traits.get("favorite", "")
				if weapons_full and not fav and Inventory.weapon_score(p.spec["weapon"]) <= worst * 1.1:
					continue
				if fav:
					d *= 0.5   # (its favourite gun: worth a longer walk)
			"ammo":
				if not _owns_ammo_type(p.spec["ammo_type"]) or me.inventory.ammo[p.spec["ammo_type"]] > 60:
					continue
			"clover":
				if me.inventory.clovers >= 3:
					continue
			"armor":
				if me.armor >= me.max_armor - 10.0:
					continue
		best_d = d
		best = p
	# supply drops are worth a long run (and braver bots will make it)
	for n in me.get_tree().get_nodes_in_group(&"supply_crates"):
		var sc := n as LootCrate
		var sd := sc.global_position.distance_to(pos)
		if sc and not sc.opened and sd < 60.0 + skill * 60.0 and sd * 0.5 < best_d and not _storm_unsafe(sc.global_position):
			best_d = sd * 0.5
			best = sc
	# treasure chests are worth a detour even when armed (but not mid-storm)
	for n in me.get_tree().get_nodes_in_group(&"treasure"):
		var tc := n as LootCrate
		if tc and not tc.opened and (tc.channeler() == null or tc.channeler() == me) and _clock >= float(_unreachable.get(tc, -1.0)) and not _storm_unsafe(tc.global_position):
			var td := tc.global_position.distance_to(pos) * 0.6
			if td < best_d:
				best_d = td
				best = tc
	if me.inventory.weapon_count() < 2:
		for n in me.get_tree().get_nodes_in_group(&"crates"):
			var c := n as LootCrate
			if c and not c.opened and _clock >= float(_unreachable.get(c, -1.0)) and not _storm_unsafe(c.global_position):
				var d := c.global_position.distance_to(pos)
				if d < best_d:
					best_d = d
					best = c
	return best


func _worst_slot() -> int:
	var worst := 0
	var worst_score := INF
	for i in Inventory.SLOTS:
		var s := Inventory.weapon_score(me.inventory.weapons[i])
		if s < worst_score:
			worst_score = s
			worst = i
	return worst


func _owns_ammo_type(t: int) -> bool:
	for w in me.inventory.weapons:
		if w and (w as WeaponInstance).data.ammo_type == t:
			return true
	return false


func _usable_weapon_slot() -> int:
	for i in Inventory.SLOTS:
		var w: WeaponInstance = me.inventory.weapons[i]
		if w and (w.ammo_in_mag > 0 or me.inventory.ammo[w.data.ammo_type] > 0):
			return i
	return -1


# ---- acting ----------------------------------------------------------------------------------------------

func _act(delta: float) -> void:
	me.want_fire = false
	me.want_aim = false
	me.want_sprint = false
	me.want_crouch = false
	match mode:
		Mode.FIGHT:
			_fight(delta)
		Mode.LOOT:
			_loot(delta)
		Mode.HEAL:
			me.move_input = Vector2.ZERO
			me.use_clover()
			mode = Mode.ROAM
		Mode.FLEE_STORM:
			if match_manager:
				_set_dest(match_manager.safe_point_for(me.global_position))
			me.want_sprint = true
			_follow_path(true)
		_:
			_roam()
	_unstick(delta)


## The match director wants this bot to go and flush the player out.
## Rewind (see TimeKeeper): the last ten seconds haven't happened yet, so
## whatever the bot learned in them goes too.
func forget() -> void:
	target = null
	mode = Mode.ROAM
	_path = PackedVector3Array()
	_path_i = 0
	_dest = Vector3.INF
	_loot_goal = null
	_awareness.clear()
	_shots_seen.clear()
	_heard_pos = Vector3.INF
	_alert_pos = Vector3.INF
	_bursting = false
	_stuck_t = 0.0
	_think_t = 0.0
	_provoked.clear()
	_avoid.clear()


func hunt(pos: Vector3, seconds := 30.0) -> void:
	_hunt_pos = pos
	_hunt_until = _clock + seconds


func _roam() -> void:
	if _hunt_pos != Vector3.INF and (_clock >= _hunt_until or me.global_position.distance_to(_hunt_pos) < 6.0):
		_hunt_pos = Vector3.INF
	if _dest == Vector3.INF or me.global_position.distance_to(_dest) < 4.0:
		var center := Vector2.ZERO
		var radius := 1e9
		if match_manager:
			center = match_manager.safe_center()
			radius = match_manager.safe_radius() * 0.8
		var p := island.random_land_point(2.0, center, radius) if island else me.global_position + Vector3(randf_range(-30, 30), 0, randf_range(-30, 30))
		# drift toward POIs: that's where the loot (and the fights) are
		if island and randf() < 0.5 and not island.pois.is_empty():
			var poi: Dictionary = island.pois.pick_random()
			var c: Vector2 = poi.center
			if c.distance_to(center) < radius:
				p = Vector3(c.x, island.terrain.height_at(c.x, c.y), c.y)
		_set_dest(p)
	_follow_path(false)


func _loot(delta: float) -> void:
	if _loot_goal == null or not is_instance_valid(_loot_goal) or (_loot_goal is LootCrate and (_loot_goal as LootCrate).opened):
		_loot_goal = _find_loot()
		if _loot_goal == null:
			mode = Mode.ROAM
			return
	if _loot_goal != _goal_tracked:
		_goal_tracked = _loot_goal
		_goal_since = _clock
		_goal_best = INF
	_set_dest(_loot_goal.global_position)
	var d := me.global_position.distance_to(_loot_goal.global_position)
	# give up on loot we aren't getting any closer to
	if d < _goal_best - 1.0:
		_goal_best = d
		_goal_since = _clock
	elif _clock - _goal_since > GOAL_PATIENCE:
		_unreachable[_loot_goal] = _clock + UNREACHABLE_FOR
		_loot_goal = null
		mode = Mode.ROAM
		return
	if d < 1.7 * maxf(me.visual.rig.world_scale, 1.0):
		if _loot_goal is Pickup:
			var pk := _loot_goal as Pickup
			if pk.is_weapon() and me.inventory.first_free_slot() < 0:
				# hands full: swap out the weakest gun, not whatever is held
				me.switch_to(_worst_slot())
			if not pk.try_collect(me):
				# couldn't take it (full up, or it's lodged somewhere): stop circling it
				_unreachable[pk] = _clock + UNREACHABLE_FOR
		elif _loot_goal is LootCrate:
			var crate := _loot_goal as LootCrate
			if crate.open_time > 0.0 and not crate.opened:
				# stand still and work the lock (fights interrupt via _choose_mode)
				me.move_input = Vector2.ZERO
				var to := crate.global_position - me.global_position
				me.look_yaw = atan2(-to.x, -to.z)
				if not crate.channel(me, delta):
					return
			else:
				crate.open(me)
		_loot_goal = null
		_progress_t = 0.0
		_progress_from = me.global_position
		_think_t = 0.4   # glance around before grabbing the next thing
		return
	me.want_sprint = target != null
	_follow_path(target == null)


func _fight(delta: float) -> void:
	if target == null or not is_instance_valid(target) or not target.alive:
		target = null
		mode = Mode.ROAM
		return
	_pick_weapon_for_range()
	var w := me.current_weapon()
	if w == null:
		if target.global_position.distance_to(me.global_position) < BRAWL_RANGE:
			_brawl()
		else:
			mode = Mode.LOOT
		return
	var eye := me.get_eye_position()
	var visible := _clock - _last_seen_t < 0.35
	var tpos := target.get_chest_position() if visible else _last_seen_pos
	var dist := eye.distance_to(tpos)

	# --- positioning
	var pref := w.data.ai_preferred_range * lerpf(1.2, 0.9, skill) * _t("range", 1.0)
	if target.is_player and player_style != "":
		pref *= 1.6 if player_style == "close" else 0.5   # fight you where your guns are weakest
	_strafe_t -= delta
	if _strafe_t <= 0.0:
		_strafe = -_strafe if randf() < 0.7 else _strafe
		_strafe_t = randf_range(0.6, 1.8) / _t("strafe", 1.0)
		if randf() < 0.25 * skill * _t("jump", 1.0) and me.is_on_floor():
			me.want_jump = true
	var forward := 0.0
	if not visible or dist > w.data.ai_max_range * 0.8:
		# close in along the navmesh
		_set_dest(_last_seen_pos)
		_follow_path(true)
		forward = 1.0
	else:
		if dist > pref * 1.3:
			forward = 1.0
		elif dist < pref * 0.6 and w.data.id != &"carrot_shotgun":
			forward = -1.0
		me.move_input = Vector2(_strafe * lerpf(0.5, 1.0, skill), forward * 0.8)
		me.want_crouch = (skill > 0.7 and dist > 30.0 and randf() < 0.02) or (_t("crouch", 0.0) >= 1.0 and forward == 0.0 and dist > 12.0)

	# --- aiming (turn-rate limited, error decays while tracking)
	var aim := tpos
	if visible:
		var lead := target.velocity * (dist / maxf(w.data.projectile_speed, 1.0)) * skill
		aim += lead
		if w.data.projectile == WeaponData.ProjectileKind.ROCKET or (_t("feet", 0.0) > 0.0 and target.is_on_floor()):
			aim = target.global_position + Vector3.UP * 0.15 + lead
		elif randf() < skill * 0.3:
			aim = target.get_eye_position() + lead
		_aim_err = _aim_err.lerp(Vector3.ZERO, IKMath.damp(lerpf(0.6, 2.4, skill) * (0.3 + 0.7 * _target_vis), delta))
	aim += _aim_err
	var want := (aim - eye).normalized()
	var want_yaw := atan2(-want.x, -want.z)
	var want_pitch := asin(clampf(want.y, -1.0, 1.0))
	var turn := deg_to_rad(lerpf(180.0, 540.0, skill)) * delta
	me.look_yaw = me.look_yaw + clampf(wrapf(want_yaw - me.look_yaw, -PI, PI), -turn, turn)
	me.look_pitch = me.look_pitch + clampf(want_pitch - me.look_pitch, -turn, turn)
	me.aim_point = eye + me.look_direction() * dist
	# when strafing while not chasing, move relative to the look direction
	# (move_input is already look-relative)

	# --- point-blank: sometimes a bash with the club beats a shot
	var flat := Vector2(target.global_position.x - me.global_position.x, target.global_position.z - me.global_position.z).length()
	if visible and flat < me.melee_reach() * 1.1 and not me.is_swinging() and randf() < 0.05 * skill * _t("melee", 1.0) \
			and (not target.is_player or _may_shoot_player()):
		me.want_melee = true
		return

	# --- shooting
	var reaction := lerpf(0.75, 0.22, skill)
	var on_target := me.look_direction().angle_to(want) < deg_to_rad(4.0 if w.data.pellets == 1 else 9.0)
	var in_range := dist <= w.data.ai_max_range and dist >= w.data.ai_min_range
	if w.ammo_in_mag <= 0:
		me.start_reload()
	elif visible and on_target and in_range and _clock - _spotted_t > reaction and (not target.is_player or _may_shoot_player()):
		me.want_aim = (dist > 18.0 and skill > 0.5) or w.data.scoped
		if w.data.fire_mode == WeaponData.FireMode.AUTO:
			# bursts with pauses between, like a person (not a sprinkler)
			_burst_t -= delta
			if _burst_t <= 0.0:
				_bursting = not _bursting
				_burst_t = randf_range(0.3, 0.8) * lerpf(0.8, 1.4, skill) * _t("burst", 1.0) if _bursting else randf_range(0.25, 0.6) * lerpf(1.3, 0.8, skill)
			me.want_fire = _bursting
		else:
			# tap the trigger: press on one tick, release on the next
			_fire_toggle = not _fire_toggle
			me.want_fire = _fire_toggle and randf() < lerpf(0.12, 0.35, skill)


## Bare paws and someone close: run straight at them and swing the club.
func _brawl() -> void:
	var to := target.global_position - me.global_position
	var dist := Vector2(to.x, to.z).length()
	me.look_yaw = lerp_angle(me.look_yaw, atan2(-to.x, -to.z), 0.3)
	me.look_pitch = lerpf(me.look_pitch, 0.0, 0.2)
	me.aim_point = target.get_chest_position()
	var reach := me.melee_reach()
	me.move_input = Vector2(0, 1) if dist > reach * 0.8 else Vector2.ZERO
	me.want_sprint = dist > reach * 2.0
	var ready := _clock - _spotted_t > lerpf(0.75, 0.22, skill)
	if dist < reach * 1.3 and not me.is_swinging() and ready and (not target.is_player or _may_shoot_player()):
		me.want_melee = true


## Only `player_attack_slots` bots shoot at the player at once; a slot is held
## while firing and freed 1.5 s after the bot stops.
func _may_shoot_player() -> bool:
	if rival or traits.get("no_slot", false):
		return true   # a rival (or a bot you've driven round the bend) doesn't wait its turn
	var now := Time.get_ticks_msec()
	var id := get_instance_id()
	for k in _player_attackers.keys():
		if _player_attackers[k] < now or k == id and not me.alive:
			_player_attackers.erase(k)
	if _player_attackers.has(id) or _player_attackers.size() < player_attack_slots:
		_player_attackers[id] = now + ATTACK_SLOT_HOLD_MS
		return true
	return false


func _pick_weapon_for_range() -> void:
	if me.is_reloading() or target == null:
		return
	var dist := me.global_position.distance_to(target.global_position)
	var best := -1
	var best_fit := INF
	for i in Inventory.SLOTS:
		var w: WeaponInstance = me.inventory.weapons[i]
		if w == null or (w.ammo_in_mag <= 0 and me.inventory.ammo[w.data.ammo_type] <= 0):
			continue
		if dist < w.data.ai_min_range:
			continue
		var fit := absf(dist - w.data.ai_preferred_range) / w.data.ai_preferred_range - w.damage_scale() * 0.2 \
			- (0.35 if String(w.data.id) == traits.get("favorite", "") else 0.0)
		if fit < best_fit:
			best_fit = fit
			best = i
	if best >= 0 and best != me.current_slot:
		me.switch_to(best)


# ---- movement ----------------------------------------------------------------------------------------------

func _set_dest(p: Vector3) -> void:
	if _dest != Vector3.INF and _dest.distance_to(p) < 2.0 and _clock < _repath_t:
		return
	_dest = p
	_repath_t = _clock + 1.5
	var map := me.get_world_3d().navigation_map
	var from := NavigationServer3D.map_get_closest_point(map, me.global_position)
	var to := NavigationServer3D.map_get_closest_point(map, p)
	_path = Island.find_path(map, from, to)
	_path_i = 0
	if _path.is_empty():
		_path = PackedVector3Array([p])


func _follow_path(look_ahead: bool) -> void:
	if _path.is_empty():
		me.move_input = Vector2.ZERO
		if _alerted():
			me.look_yaw = lerp_angle(me.look_yaw, _yaw_to(_alert_pos), 0.15)
		return
	var pos := me.global_position
	while _path_i < _path.size() - 1 and Vector2(_path[_path_i].x - pos.x, _path[_path_i].z - pos.z).length() < 1.2:
		_path_i += 1
	var wp := _path[_path_i]
	var to := Vector3(wp.x - pos.x, 0, wp.z - pos.z)
	if to.length() < 0.6 and _path_i >= _path.size() - 1:
		me.move_input = Vector2.ZERO
		return
	var dir := to.normalized()
	if look_ahead or mode != Mode.FIGHT:
		# face where we're going, like a human would (or where the shots came from)
		var yaw := _yaw_to(_alert_pos) if _alerted() and mode != Mode.FIGHT else atan2(-dir.x, -dir.z)
		me.look_yaw = lerp_angle(me.look_yaw, yaw, 0.2)
		me.look_pitch = lerpf(me.look_pitch, 0.0, 0.1)
		me.aim_point = me.get_eye_position() + me.look_direction() * 30.0
	# convert the world direction into a look-relative stick input
	var local := Basis(Vector3.UP, -me.look_yaw) * dir
	me.move_input = Vector2(local.x, -local.z).limit_length(1.0)
	if mode == Mode.ROAM:
		me.want_sprint = to.length() > 20.0 and randf() < 0.5


func _yaw_to(p: Vector3) -> float:
	var to := p - me.global_position
	return atan2(-to.x, -to.z)


func _unstick(delta: float) -> void:
	if me.move_input.length() < 0.3:
		_stuck_t = 0.0
		_stuck_pos = me.global_position
		return
	_stuck_t += delta
	if _stuck_t > 1.2:
		if me.global_position.distance_to(_stuck_pos) < 0.6:
			me.want_jump = true
			_repath_t = 0.0
			if _dest != Vector3.INF:
				_set_dest(_dest + Vector3(randf_range(-4, 4), 0, randf_range(-4, 4)))
		_stuck_t = 0.0
		_stuck_pos = me.global_position
	_check_progress(delta)


## Long-window check for bots that keep moving but get nowhere (circling a
## waypoint they can't reach, walking a loop inside a hollow landmark…):
## no 4.5 m of net progress in 10 s → abandon the goal; by 16 s → hop to open ground.
const PROGRESS_WINDOW := 10.0
const PROGRESS_RESCUE := 16.0
const PROGRESS_RADIUS := 4.5
var _progress_t := 0.0
var _progress_from := Vector3.ZERO


func _check_progress(delta: float) -> void:
	if mode == Mode.FIGHT or me.move_input.length() < 0.3:
		_progress_t = 0.0
		_progress_from = me.global_position
		return
	# a wide radius: bots that hop back and forth against a wall travel a few
	# metres each way without getting anywhere
	var moved := Vector2(me.global_position.x - _progress_from.x, me.global_position.z - _progress_from.z).length()
	if moved > PROGRESS_RADIUS:
		_progress_t = 0.0
		_progress_from = me.global_position
		return
	_progress_t += delta
	if _progress_t > PROGRESS_WINDOW and _progress_t - delta <= PROGRESS_WINDOW:
		if _loot_goal and is_instance_valid(_loot_goal):
			_unreachable[_loot_goal] = _clock + UNREACHABLE_FOR
		_loot_goal = null
		_dest = Vector3.INF
		mode = Mode.ROAM
	elif _progress_t > PROGRESS_RESCUE:
		_progress_t = 0.0
		_progress_from = me.global_position
		me.rescue_to_open_ground()
		_dest = Vector3.INF


# ---- the drop -------------------------------------------------------------------------------------------------

func _steer_drop() -> void:
	var to := drop_spot - me.global_position
	to.y = 0.0
	me.look_yaw = atan2(-to.x, -to.z)
	me.look_pitch = -0.3
	me.move_input = Vector2(0, clampf(to.length() / 20.0, 0.0, 1.0))
	# deploy the glider early if we still have a long way to go
	if me.state == Critter.State.FREEFALL and to.length() > 60.0 and me.global_position.y < 90.0:
		me.want_jump = true
