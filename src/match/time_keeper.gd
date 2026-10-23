class_name TimeKeeper
extends Node
## Rewind: impossible online, delightful offline. The keeper records the match
## every SNAP_EVERY seconds (every critter still standing: where it is, how it's
## moving, its health, shield, guns, ammo and clovers; the Briar) and keeps the
## last REWIND_SECONDS or so, plus a log of the loot taken in that time. The
## player has CHARGES rewinds a match: use one any time ([T], or the pause
## menu), or when a killing blow lands the game freezes and offers one.
## A rewind puts everyone still standing back where they were ten seconds ago
## (with what they were carrying then), puts the loot they took since back on
## the floor, and clears the carrots in flight. Critters beaten down in those
## ten seconds stay down (with their loot spilled), and opened crates stay open.

signal offered(info: DamageInfo)        ## a killing blow is on hold: rewind or accept?
signal rewound

const REWIND_SECONDS := 10.0
const SNAP_EVERY := 0.25
const CHARGES := 3

static var instance: TimeKeeper

var match_manager: MatchManager
var charges := CHARGES
var pending: DamageInfo = null          ## the killing blow on hold while the player decides
var _snaps: Array = []                  # [clock, snapshot], oldest first
var _taken: Array = []                  # [clock, taker, packed spec, position]
var _clock := 0.0
var _since := SNAP_EVERY


func _enter_tree() -> void:
	instance = self


func _exit_tree() -> void:
	if instance == self:
		instance = null


func _physics_process(delta: float) -> void:
	if match_manager == null or match_manager.phase != MatchManager.Phase.PLAYING or pending != null:
		return
	_clock += delta
	_since += delta
	if _since >= SNAP_EVERY:
		_since = 0.0
		_snaps.append([_clock, _snapshot()])
		var keep := _clock - REWIND_SECONDS - 1.0
		while _snaps.size() > 1 and float(_snaps[0][0]) < keep:
			_snaps.pop_front()
		while not _taken.is_empty() and float(_taken[0][0]) < keep:
			_taken.pop_front()


func can_rewind() -> bool:
	return charges > 0 and not _snaps.is_empty() and match_manager != null \
		and match_manager.phase == MatchManager.Phase.PLAYING \
		and match_manager.player != null and match_manager.player.alive


## Seconds a rewind would go back right now (up to REWIND_SECONDS).
func depth() -> float:
	return 0.0 if _snaps.is_empty() else minf(REWIND_SECONDS, _clock - float(_snaps[0][0]))


## Go back (up to) ten seconds. Uses a charge.
func rewind() -> bool:
	if not can_rewind():
		return false
	charges -= 1
	var want := _clock - REWIND_SECONDS
	var idx := 0
	for i in _snaps.size():
		if float(_snaps[i][0]) <= want:
			idx = i
	var at := float(_snaps[idx][0])
	_restore(_snaps[idx][1], at)
	_clock = at
	_snaps = _snaps.slice(0, idx + 1)
	_since = 0.0
	rewound.emit()
	return true


## Pickup calls this when a critter takes something, so a rewind can put it back.
func note_taken(taker: Critter, spec: Dictionary, pos: Vector3) -> void:
	_taken.append([_clock, taker, _pack(spec), pos])


## Called by Critter.take_damage when a blow would beat the player down:
## freezes the match and offers a rewind (true), or lets it land (false).
## Only when something is listening to answer (the game's prompt; not tests
## that don't ask for one).
func hold_killing_blow(player: Critter, info: DamageInfo) -> bool:
	if pending != null:
		player.health = 1.0   # a second pellet of the same blast: still on hold
		return true
	if not can_rewind() or offered.get_connections().is_empty():
		return false
	pending = info
	player.health = 1.0
	get_tree().paused = true
	offered.emit(info)
	return true


## The player chose: rewind (true) or take the blow (false).
func resolve(rewind_it: bool) -> void:
	var info := pending
	pending = null
	get_tree().paused = false
	var player := match_manager.player
	if rewind_it:
		rewind()
	elif info and player and player.alive:
		player.health = 0.0
		player._die(info)


# ---- snapshots ---------------------------------------------------------------------------------

func _snapshot() -> Dictionary:
	var critters := {}
	for c in match_manager.critters:
		if not is_instance_valid(c) or not c.alive or c.state == Critter.State.IN_DROPSHIP:
			continue
		var guns := []
		for w in c.inventory.weapons:
			guns.append(null if w == null else [w.data, w.rarity, w.ammo_in_mag])
		critters[c] = {"xf": c.global_transform, "vel": c.velocity, "yaw": c.look_yaw, "pitch": c.look_pitch,
			"hp": c.health, "armor": c.armor, "state": c.state, "slot": c.current_slot, "guns": guns,
			"ammo": c.inventory.ammo.duplicate(), "clovers": c.inventory.clovers, "second_wind": c.second_wind}
	var loot := {}
	for n in get_tree().get_nodes_in_group(&"pickups"):
		loot[n.get_instance_id()] = true
	var storm := {}
	var s := match_manager.storm
	if s and s.active:
		storm = {"stage": s.stage, "center": s.center, "radius": s.radius, "next_center": s.next_center,
			"next_radius": s.next_radius, "time_left": s.time_left, "shrinking": s.shrinking, "dps": s.dps,
			"nap_left": s.nap_left, "from_center": s._from_center, "from_radius": s._from_radius}
	return {"critters": critters, "loot": loot, "storm": storm}


func _restore(snap: Dictionary, at: float) -> void:
	var restored := {}
	for c in snap.critters:
		if not is_instance_valid(c) or not (c as Critter).alive:
			continue   # beaten down since: they stay down
		_restore_critter(c, snap.critters[c])
		restored[c] = true
	# loot: what the restored critters took since goes back on the floor, and
	# the guns they swapped out since leave it (they're holding them again)
	for t in _taken:
		if float(t[0]) > at and restored.has(t[1]):
			Pickup.spawn(match_manager.world_root, _unpack(t[2]), t[3])
	_taken = _taken.filter(func(t): return float(t[0]) <= at)
	for n in get_tree().get_nodes_in_group(&"pickups"):
		var p := n as Pickup
		if p and not snap.loot.has(p.get_instance_id()) and restored.has(p.dropped_by):
			p.queue_free()
	if Projectiles.instance:
		Projectiles.instance.clear_in_flight()
	var st: Dictionary = snap.storm
	var s := match_manager.storm
	if s and s.active and not st.is_empty():
		s.stage = st.stage
		s.center = st.center
		s.radius = st.radius
		s.next_center = st.next_center
		s.next_radius = st.next_radius
		s.time_left = st.time_left
		s.shrinking = st.shrinking
		s.dps = st.dps
		s.nap_left = st.nap_left
		s._from_center = st.from_center
		s._from_radius = st.from_radius
		s._update_wall()


func _restore_critter(c: Critter, r: Dictionary) -> void:
	c.global_transform = r.xf
	c.velocity = r.vel
	if not c.is_player:   # (the player keeps looking where their camera is)
		c.look_yaw = r.yaw
		c.look_pitch = r.pitch
	c.health = r.hp
	c.armor = r.armor
	c.second_wind = r.second_wind
	if c.state != r.state:
		c._set_state(r.state)
	for i in Inventory.SLOTS:
		c.inventory.weapons[i] = null if r.guns[i] == null else _weapon(r.guns[i])
	c.inventory.ammo = (r.ammo as Dictionary).duplicate()
	c.inventory.clovers = r.clovers
	c.reset_actions()
	c.current_slot = -1
	if r.slot >= 0 and c.inventory.weapons[r.slot] != null:
		c.switch_to(r.slot)
	else:
		c.current_slot = maxi(r.slot, 0)
		c.visual.set_weapon(null)
	c.inventory.changed.emit()
	c.visual.physics_tick(c.global_transform, true)
	var brain := c.get_node_or_null("AIBrain") as AIBrain
	if brain:
		brain.forget()


static func _weapon(g: Array) -> WeaponInstance:
	var w := WeaponInstance.new(g[0], g[1], false)
	w.ammo_in_mag = g[2]
	return w


static func _pack(spec: Dictionary) -> Dictionary:
	var s := spec.duplicate()
	if s.get("weapon") is WeaponInstance:
		var w: WeaponInstance = s["weapon"]
		s["weapon"] = [w.data, w.rarity, w.ammo_in_mag]
	return s


static func _unpack(spec: Dictionary) -> Dictionary:
	var s := spec.duplicate()
	if s.get("weapon") is Array:
		s["weapon"] = _weapon(s["weapon"])
	return s
