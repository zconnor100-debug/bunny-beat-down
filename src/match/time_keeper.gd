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
## the floor, clears the carrots in flight, and puts the toy train (Toy Box
## Bash) back where it was, so its riders land on it. Critters beaten down in those
## ten seconds stay down (with their loot spilled), and opened crates stay open.
## The rewind plays out: for PLAYBACK seconds the world runs backwards (the
## match paused, everyone gliding back along where they went, the Briar
## growing back) before everything snaps into place.

signal offered(info: DamageInfo)        ## a killing blow is on hold: rewind or accept?
signal rewinding                        ## the playback has started
signal rewound

const REWIND_SECONDS := 10.0
const SNAP_EVERY := 0.25
const CHARGES := 3
const PLAYBACK := 0.9                   ## real seconds of the world running backwards

static var instance: TimeKeeper

var match_manager: MatchManager
var charges := CHARGES
var pending: DamageInfo = null          ## the killing blow on hold while the player decides
var _snaps: Array = []                  # [clock, snapshot], oldest first
var _taken: Array = []                  # [clock, taker, packed spec, position]
var _clock := 0.0
var _since := SNAP_EVERY
var playing_back := false               ## the world is running backwards right now
var _pb_t := 0.0
var _pb_frames: Array = []              # the snapshots to run back through, newest first
var _pb_target := 0                     # index into _snaps of where it lands
var _pb_camera: Node
var _pb_clock := RealClock.new()


func _enter_tree() -> void:
	instance = self
	process_mode = Node.PROCESS_MODE_ALWAYS   # (the playback runs with the match paused)


func _exit_tree() -> void:
	if instance == self:
		instance = null


func _physics_process(delta: float) -> void:
	if match_manager == null or match_manager.phase != MatchManager.Phase.PLAYING or pending != null \
			or playing_back or get_tree().paused:
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
	return charges > 0 and not _snaps.is_empty() and match_manager != null and not playing_back \
		and match_manager.phase == MatchManager.Phase.PLAYING \
		and match_manager.player != null and match_manager.player.alive


## Seconds a rewind would go back right now (up to REWIND_SECONDS).
func depth() -> float:
	return 0.0 if _snaps.is_empty() else minf(REWIND_SECONDS, _clock - float(_snaps[0][0]))


## Go back (up to) ten seconds. Uses a charge. With `smooth`, the world
## runs backwards to get there (PLAYBACK seconds, the match paused) and
## `rewound` comes at the end; otherwise it snaps there at once.
func rewind(smooth := true) -> bool:
	if not can_rewind():
		return false
	charges -= 1
	var want := _clock - REWIND_SECONDS
	var idx := 0
	for i in _snaps.size():
		if float(_snaps[i][0]) <= want:
			idx = i
	if not smooth or not is_inside_tree():
		_land(idx)
		return true
	# run back through every snapshot from now to the target
	_pb_frames = [[_clock, _snapshot()]]
	for i in range(_snaps.size() - 1, idx - 1, -1):
		_pb_frames.append(_snaps[i])
	_pb_target = idx
	_pb_t = 0.0
	_pb_clock.start()
	playing_back = true
	if Projectiles.instance:
		Projectiles.instance.clear_in_flight()
	get_tree().paused = true
	# the camera keeps following you back
	var cam := get_viewport().get_camera_3d()
	_pb_camera = cam.get_parent() if cam else null
	while _pb_camera and not (_pb_camera is CameraRig):
		_pb_camera = _pb_camera.get_parent()
	if _pb_camera:
		_pb_camera.process_mode = Node.PROCESS_MODE_ALWAYS
	rewinding.emit()
	return true


func _process(delta: float) -> void:
	if not playing_back:
		return
	_pb_t += _pb_clock.step(delta)   # (see RealClock: the match is paused)
	if _pb_frames.size() < 2 or _pb_t > PLAYBACK + 2.0:
		_finish_playback()   # (never leave the match stuck paused)
		return
	var u := clampf(_pb_t / PLAYBACK, 0.0, 1.0)
	u = u * u * (3.0 - 2.0 * u)                     # ease in and out
	var pos := u * float(_pb_frames.size() - 1)     # how far back through the frames
	var i := mini(int(pos), _pb_frames.size() - 2)
	var k := pos - i
	var a: Dictionary = _pb_frames[i][1]
	var b: Dictionary = _pb_frames[i + 1][1]
	var target: Dictionary = _snaps[_pb_target][1]
	for c in target.critters:
		if not is_instance_valid(c) or not (c as Critter).alive:
			continue
		var ra: Dictionary = a.critters.get(c, b.critters.get(c, {}))
		var rb: Dictionary = b.critters.get(c, ra)
		if ra.is_empty():
			continue
		var xf := (ra.xf as Transform3D).interpolate_with(rb.xf, k)
		(c as Critter).global_transform = xf
		(c as Critter).visual.global_transform = xf
	var train := _train()
	if train and float(a.get("train", -1.0)) >= 0.0 and float(b.get("train", -1.0)) >= 0.0:
		# back along the loop (the shorter way round), riders and all
		var back := fposmod(float(b.train) - float(a.train) + train.total * 0.5, train.total) - train.total * 0.5
		train.set_distance(float(a.train) + back * k)
	var boss := _boss()
	var ba: Dictionary = a.get("boss", {})
	var bb: Dictionary = b.get("boss", {})
	if boss and not ba.is_empty() and not bb.is_empty():
		boss.global_transform = (ba.xf as Transform3D).interpolate_with(bb.xf, k)
	var s := match_manager.storm
	if s and s.active and not (a.storm as Dictionary).is_empty() and not (b.storm as Dictionary).is_empty():
		s.center = (a.storm.center as Vector2).lerp(b.storm.center, k)
		s.radius = lerpf(a.storm.radius, b.storm.radius, k)
		s._update_wall()
	if u >= 1.0:
		_finish_playback()


func _finish_playback() -> void:
	playing_back = false
	_pb_frames.clear()
	if _pb_camera and is_instance_valid(_pb_camera):
		_pb_camera.process_mode = Node.PROCESS_MODE_INHERIT
	get_tree().paused = false
	_land(_pb_target)


func _land(idx: int) -> void:
	var at := float(_snaps[idx][0])
	_restore(_snaps[idx][1], at)
	_clock = at
	_snaps = _snaps.slice(0, idx + 1)
	_since = 0.0
	rewound.emit()


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
			guns.append(null if w == null else w.pack())
		critters[c] = {"xf": c.global_transform, "vel": c.velocity, "yaw": c.look_yaw, "pitch": c.look_pitch,
			"hp": c.health, "armor": c.armor, "state": c.state, "slot": c.current_slot, "guns": guns,
			"ammo": c.inventory.ammo.duplicate(), "clovers": c.inventory.clovers, "grenades": c.inventory.grenades, "shields": c.inventory.shields,
			"second_wind": c.second_wind}
	var loot := {}
	for n in get_tree().get_nodes_in_group(&"pickups"):
		loot[n.get_instance_id()] = true
	var storm := {}
	var s := match_manager.storm
	if s and s.active:
		storm = {"stage": s.stage, "center": s.center, "radius": s.radius, "next_center": s.next_center,
			"next_radius": s.next_radius, "time_left": s.time_left, "shrinking": s.shrinking, "dps": s.dps,
			"nap_left": s.nap_left, "from_center": s._from_center, "from_radius": s._from_radius}
	var train := _train()
	var b := _boss()
	return {"critters": critters, "loot": loot, "storm": storm, "train": train.distance if train else -1.0,
		"boss": b.snapshot() if b else {}}


## A Boss Battle's boss, once it's out and still standing (it goes back too).
func _boss() -> Boss:
	var b: Boss = match_manager.boss if match_manager else null
	return b if b and is_instance_valid(b) and b.alive and b.state != Boss.State.WAITING else null


func _train() -> ToyTrain:
	var island := match_manager.island if match_manager else null
	return island.get("train") as ToyTrain if island and "train" in island else null


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
	var train := _train()
	if train and float(snap.get("train", -1.0)) >= 0.0:
		train.set_distance(snap.train)
	var b := _boss()
	if b and not (snap.get("boss", {}) as Dictionary).is_empty():
		b.restore(snap.boss)


func _restore_critter(c: Critter, r: Dictionary) -> void:
	c.end_knock()
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
	c.inventory.grenades = r.get("grenades", 0)
	c.inventory.shields = r.get("shields", 0)
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
	return WeaponInstance.unpack(g)


static func _pack(spec: Dictionary) -> Dictionary:
	var s := spec.duplicate()
	if s.get("weapon") is WeaponInstance:
		var w: WeaponInstance = s["weapon"]
		s["weapon"] = w.pack()
	return s


static func _unpack(spec: Dictionary) -> Dictionary:
	var s := spec.duplicate()
	if s.get("weapon") is Array:
		s["weapon"] = _weapon(s["weapon"])
	return s
