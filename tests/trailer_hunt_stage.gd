extends "res://tests/trailer_reel_stage.gd"
## "The Hunt", the phone trailer: Bun is the quarry of a hunting party of the
## Cast's nobles (the British voices: Buck Toothington, Sir Reynard, Sir
## Toadsworth, Lady Garbage, Duchess, Sir Scamper, Wheelie) across all three
## maps, with slow-motion ragdolls when the quarry bites back. Recorded a map
## at a time like the reel ("hunt island|cage|toybox", tests/capture_trailer.gd)
## and cut by tools/make_hunt_trailer.py, which also lays each spoken line
## (tools/voices/say.py, in the rogue's own voice) where the stage prints
## LINE <id> <frame>. Everyone else in the match is sent off stage.

const HUNTERS := {
	"island": ["Buck Toothington", "Sir Reynard", "Sir Toadsworth", "Lady Garbage", "Duchess"],
	"cage": ["Lady Garbage", "Sir Scamper", "Duchess", "Sir Reynard", "Wheelie"],
	"toybox": ["Duchess", "Buck Toothington", "Sir Toadsworth", "Sir Reynard", "Wheelie"],
}
## What they say (the voice files are made from the same text: tools/voices/say.py)
const LINES := {
	"buck": "Tally-ho! A bunny, on the lawn!",
	"reynard": "Do keep running, old sport. It's terribly sporting.",
	"toad": "I say! Not the hat!",
	"garbage": "Fetch me that rabbit. Gently. Then not gently.",
	"scamper": "En garde, you fluffy cad!",
	"duchess": "A train? How frightfully common.",
	"wheelie": "Jolly good sport! Same time tomorrow?",
}

var _hunters: Array = []   # [{c, seed}]
var _said := {}            # line ids already spoken


func _ready() -> void:
	opponents = 49   # (every rogue in the match: the hunting party's always there)
	super()


# ---- the hunting party -----------------------------------------------------------------

func _rogue(n: String) -> Critter:
	for c in mm.critters:
		if c != bun and String(c.display_name).begins_with(n):
			return c
	return null


## The party for this map, armed, tagged, hard to kill by accident; everyone
## else off stage.
func _gather(names: Array, guns: Array) -> Array:
	var party: Array = []
	for n in names:
		var c := _rogue(n)
		if c:
			party.append(c)
	for c in _bots():
		if not party.has(c):
			c.visible = false
			c.process_mode = Node.PROCESS_MODE_DISABLED
			c.global_position = Vector3(0, -400, 0)
	_hunters.clear()
	for i in party.size():
		var c: Critter = party[i]
		_hand(c, guns[i % guns.size()], Rarity.Tier.PRIZE)
		c.max_health = 600.0
		c.health = 600.0
		c.armor = 0.0
		c.visual.set_enemy_highlight(c.display_name, false, 2)
		_hunters.append({"c": c, "seed": i * 1.7})
	bun.max_health = 99999.0
	bun.health = bun.max_health
	return party


## Now one good hit takes them down (they ragdoll).
func _soften(party: Array, hp := 18.0) -> void:
	for c in party:
		c.max_health = hp
		c.health = hp


## Each hunter after Bun: facing it, running at it (up to `stop` away),
## shooting in bursts with its aim wandering round it so the carrots whizz by.
func _drive_hunters(stop := 4.0, fire := true, run := true) -> void:
	for h in _hunters:
		var c: Critter = h.c
		if not c.alive:
			continue
		var to := bun.global_position + Vector3(h.get("off", Vector3.ZERO)) - c.global_position
		to.y = 0.0
		var d := to.length()
		c.look_yaw = atan2(-to.x, -to.z)
		var go := run and d > stop
		c.move_input = Vector2(0, 1) if go else Vector2.ZERO
		c.want_sprint = go
		var s: float = h.seed
		var at := bun.get_chest_position() + Vector3(sin(_t * 3.1 + s) * 1.4, 0.5 + sin(_t * 2.3 + s) * 0.5, cos(_t * 2.7 + s) * 1.4)
		_aim(c, at)
		c.want_aim = true
		c.want_fire = fire and fmod(_t + s, 1.1) < 0.45


## The pack keeps a line across `side` (each one's own place beside Bun).
func _spread(side: Vector3, gap := 2.6) -> void:
	for i in _hunters.size():
		_hunters[i].off = side * (i - (_hunters.size() - 1) * 0.5) * gap


func _calm_hunters() -> void:
	for h in _hunters:
		var c: Critter = h.c
		if c.alive:
			c.move_input = Vector2.ZERO
			c.want_fire = false
			c.want_sprint = false


## A hunter speaks (once): its bubble now, its voice laid in by the cut at this frame.
func _line(c: Critter, id: String, seconds := 2.6) -> void:
	if c == null or _said.has(id):
		return
	_said[id] = true
	c.visual.say(LINES[id], seconds)
	print("LINE %s %d" % [id, Engine.get_frames_drawn()])


func _middle(party: Array) -> Vector3:
	var m := Vector3.ZERO
	var n := 0
	for c in party:
		if c.alive:
			m += c.global_position
			n += 1
	return m / n if n > 0 else bun.global_position


## The direction from `p` with the longest clear run (for a chase).
func _open_way(p: Vector3, length := 34.0) -> Vector3:
	var best := Vector3(0, 0, -1)
	var far := -1.0
	for k in 16:
		var d := Vector3(sin(k * TAU / 16.0), 0, cos(k * TAU / 16.0))
		var run := 0.0
		for step in range(1, 9):
			var q := _ground(p + d * length * step / 8.0) + Vector3.UP * 1.0
			if not _dry(q - Vector3.UP) or not _clear(p + Vector3.UP * 1.0 + d * length * (step - 1) / 8.0, q):
				break
			run = step
		if run > far:
			far = run
			best = d
	return best


## A crane from high over the map down to `to`, looking from the map toward `at`.
func _crane(from: Vector3, to: Vector3, look_from: Vector3, at: Callable, seconds: float, each := Callable()) -> void:
	var t0 := _t
	await _for(seconds, func():
		var k := smoothstep(0.0, 1.0, (_t - t0) / seconds)
		cam.global_position = from.lerp(to, k)
		cam.look_at(look_from.lerp(at.call(), smoothstep(0.0, 1.0, minf(1.0, k * 1.4))), Vector3.UP)
		if each.is_valid():
			each.call())


## Slow motion for a ragdoll moment (in real seconds), easing back.
func _slowmo(scale: float, seconds: float, each := Callable()) -> void:
	Engine.time_scale = scale
	await _for(seconds, each)
	var ramp := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS).set_ignore_time_scale(true)
	ramp.tween_property(Engine, "time_scale", 1.0, 0.35)
	await _for(0.4, each)
	Engine.time_scale = 1.0


func _eject_all() -> void:
	for c in mm.critters.duplicate():
		if c.state == Critter.State.IN_DROPSHIP:
			mm.dropship.eject(c)


# ---- the island: the meadow, the party, the chase, the rocket ------------------------------

func _island() -> void:
	_eject_all()
	cam.make_current()
	await _for(0.3)
	var party := _gather(HUNTERS.island, [&"carrot_rifle", &"carrot_shotgun", &"carrot_smg", &"carrot_rifle", &"carrot_pistol"])
	var spot := _open_spot(_poi("Carrot Patch"), 16.0, true)
	var run_dir := _open_way(spot)
	var back := -run_dir
	_place(bun, spot, atan2(-back.x, -back.z))   # (Bun looking back the way the party comes)
	_hand(bun, &"carrot_pistol", Rarity.Tier.GOLDEN)
	for i in party.size():
		var c: Critter = party[i]
		var side := back.cross(Vector3.UP)
		_place(c, spot + back * 17.0 + side * (i - 2) * 2.2, atan2(back.x, back.z))
	_spread(back.cross(Vector3.UP))
	_tags_off()

	# 1. the meadow from the sky, down to Bun: the quarry
	_begin("island_crane")
	_say("THE HUNT", "you're the bunny", 2.2)
	var island_mid: Vector3 = _poi("Carrot Patch")
	var low := spot - back * 5.0 + back.cross(Vector3.UP) * 2.0 + Vector3.UP * 2.6
	await _crane(spot + Vector3.UP * 55.0 - back * 40.0, low, island_mid, func(): return spot + back * 12.0 + Vector3.UP * 1.0, 3.0,
		func(): _tags_off())
	_end()

	# 2. the party walks up, Buck sounds the hunt
	_begin("reveal")
	_say("THEY HUNT IN PACKS", "", 2.0)
	var t0 := _t
	await _for(2.8, func():
		_drive_hunters(9.0, false)
		for h in _hunters:
			h.c.want_sprint = false
		if _t - t0 > 0.35:
			_line(party[0], "buck", 2.6)
		_tags_off()
		var to := _middle(party) - bun.global_position
		to.y = 0
		var f := to.normalized()
		cam.global_position = bun.global_position - f * 5.0 + f.cross(Vector3.UP) * 2.0 + Vector3.UP * 2.6
		cam.look_at(_middle(party) + Vector3.UP * 0.6, Vector3.UP)
		_wobble(1.2))
	_end()

	# 3. the chase: Bun legs it, the party runs it down, carrots whizzing by
	bun.want_sprint = true
	_begin("chase")
	t0 = _t
	await _for(3.0, func():
		bun.look_yaw = atan2(-run_dir.x, -run_dir.z)
		bun.move_input = Vector2(0, 1)
		bun.want_sprint = true
		_drive_hunters(7.0, true)
		_tags_off()
		if _t - t0 > 0.25:
			_line(party[1], "reynard", 3.2)
		var b := bun.global_position
		cam.fov = 42.0   # (a long lens: the pack right on Bun's heels)
		cam.global_position = b + run_dir * 8.0 + run_dir.cross(Vector3.UP) * 1.2 + Vector3.UP * 1.5
		cam.look_at(b - run_dir * 4.0 + Vector3.UP * 0.7, Vector3.UP)
		_wobble(1.6))
	cam.fov = 70.0
	_end()

	# 4. Bun turns: one golden rocket into the party, in slow motion
	bun.move_input = Vector2.ZERO
	bun.want_sprint = false
	_hand(bun, &"carrot_rocket_launcher", Rarity.Tier.GOLDEN)
	_soften(party)
	await _for(0.45, func():
		_aim(bun, _middle(party) + Vector3.UP * 0.6)
		_drive_hunters(6.0, false)
		_tags_off())
	var target := _middle(party)
	var aim_at := func() -> Vector3: return target + Vector3.UP * 0.6
	var across := (target - bun.global_position)
	across.y = 0
	across = across.normalized().cross(Vector3.UP)
	var frame_it := func():
		var k := clampf((_t - _t0()) / 3.2, 0.0, 1.0)
		var around := Basis(Vector3.UP, lerpf(-0.35, 0.5, k)) * across
		cam.global_position = target + around * 8.0 + Vector3.UP * 2.4
		cam.look_at(target + Vector3.UP * 1.2, Vector3.UP)
	_begin("rocket")
	frame_it.call()
	await _for(0.3, func():
		_aim(bun, aim_at.call())
		_drive_hunters(6.0, false)
		frame_it.call())
	bun.want_fire = true
	await _frame()
	bun.want_fire = false
	_line(party[2], "toad", 3.0)
	await _for(0.08, frame_it)
	_say("RAGDOLL PHYSICS", "", 2.0)
	await _slowmo(0.15, 2.0, frame_it)
	await _for(0.3, frame_it)
	_end()
	_calm_hunters()


# ---- the Hamster Cage: the party prowls the cage, Sir Scamper charges --------------------

func _cage() -> void:
	_eject_all()
	cam.make_current()
	await _for(0.3)
	var party := _gather(HUNTERS.cage, [&"carrot_smg", &"carrot_shotgun", &"carrot_rifle", &"carrot_lmg", &"carrot_pistol"])
	var spot := _open_spot(Vector3.ZERO, 16.0)
	var run_dir := _open_way(spot, 24.0)
	var back := -run_dir
	_place(bun, spot + run_dir * 6.0, atan2(-back.x, -back.z))
	_hand(bun, &"carrot_shotgun", Rarity.Tier.GOLDEN)
	var side := back.cross(Vector3.UP)
	for i in party.size():
		_place(party[i], spot + back * (12.0 + (i % 2) * 2.5) + side * (i - 2) * 2.4, atan2(back.x, back.z))
	_spread(side)
	_tags_off()

	# 1. the cage from above, down to the party prowling in, Lady Garbage giving orders
	_begin("cage_crane")
	_say("THE HAMSTER CAGE", "", 2.2)
	var t0 := _t
	var low := spot + side * 9.0 + run_dir * 2.0 + Vector3.UP * 3.4
	await _crane(spot + Vector3.UP * 42.0 + side * 24.0, low, spot, func(): return _middle(party) + Vector3.UP * 0.8, 3.0,
		func():
			_drive_hunters(8.0, false)
			for h in _hunters:
				h.c.want_sprint = false
			if _t - t0 > 0.15:
				_line(party[0], "garbage", 3.0))
	_end()

	# 2. Sir Scamper charges with his sword drawn (a carrot rifle); Bun's golden shotgun
	var scamper: Critter = party[1]
	_calm_hunters()
	for h in _hunters.duplicate():
		if h.c != scamper:
			_hunters.erase(h)
	_soften([scamper], 14.0)
	for c in party:
		if c != scamper:
			c.visible = false
			c.process_mode = Node.PROCESS_MODE_DISABLED
			c.global_position = Vector3(0, -400, 0)
	var arena := _open_spot(Vector3.ZERO, 14.0)
	var way := _open_way(arena, 14.0)
	_place(bun, arena + way * 3.0, atan2(way.x, way.z))
	_place(scamper, arena - way * 7.0, atan2(-way.x, -way.z))
	var aside := way.cross(Vector3.UP)
	for k in 8:   # (the side the cage's bars and toys don't hide)
		var c := arena + (Basis(Vector3.UP, k * 0.4 * (1 if k % 2 else -1)) * way.cross(Vector3.UP)) * 7.0 + Vector3.UP * 1.4
		if _clear(c, arena + Vector3.UP * 0.9) and _clear(c, arena + way * 5.0 + Vector3.UP * 0.9):
			aside = (c - arena - Vector3.UP * 1.4).normalized()
			break
	_aim(bun, scamper.get_chest_position())
	_begin("cage_charge")
	t0 = _t
	var frame_it := func():   # (over Bun's shoulder: a tall frame wants depth, not width)
		cam.global_position = arena + way * 5.6 + way.cross(Vector3.UP) * 1.0 + Vector3.UP * 1.5
		cam.look_at(arena - way * 3.0 + Vector3.UP * 0.7, Vector3.UP)
	await _for(1.2, func():
		_drive_hunters(1.0, false)
		if true:
			_line(scamper, "scamper", 2.4)
		_aim(bun, scamper.get_chest_position())
		frame_it.call()
		_wobble(1.0))
	bun.want_fire = true
	await _frame()
	bun.want_fire = false
	await _slowmo(0.2, 1.6, frame_it)
	await _for(0.2, frame_it)
	_end()


# ---- Toy Box Bash: the party on the track, too busy hunting to see the train, and Wheelie -----

func _toybox() -> void:
	_eject_all()
	cam.make_current()
	await _for(0.3)
	var party := _gather(HUNTERS.toybox, [&"carrot_rifle", &"carrot_smg", &"carrot_shotgun", &"carrot_lmg", &"carrot_pistol"])
	var train: ToyTrain = game.island.train
	var s := 0.0
	var best := -1.0
	for i in 40:
		var at := train.total * i / 40.0
		var straight := (-train.frame_at(at).basis.z).dot(-train.frame_at(at + 20.0).basis.z)
		if straight > best:
			best = straight
			s = at + 10.0
	var xf := train.frame_at(s)
	var along := -xf.basis.z.normalized()
	along.y = 0
	along = along.normalized()
	var across := along.cross(Vector3.UP)
	var spot := xf.origin
	var wheelie := _rogue("Wheelie")
	var on_track := party.filter(func(c): return c != wheelie)
	_place(bun, spot + across * 16.0, 0.0)
	_hand(bun, &"carrot_rifle", Rarity.Tier.GOLDEN)
	for i in on_track.size():
		_place(on_track[i], spot + along * (i - 1.5) * 1.6 - across * 0.4 * (i % 2), atan2(across.x, across.z))
	if wheelie:
		_place(wheelie, spot - across * 6.5 + along * 5.0, atan2(across.x, across.z))
	_soften(on_track, 12.0)
	_tags_off()
	# the locomotive reaches the party just as the train shot goes slow (3.1 s in)
	train.set_distance(fposmod(s - ToyTrain.SPEED * 3.8, train.total))

	# 1. over the toy box, down to the party on the track, the Duchess unimpressed
	_begin("toy_crane")
	_say("TOY BOX BASH", "", 2.2)
	var t0 := _t
	var low := spot + across * 7.5 - along * 7.0 + Vector3.UP * 2.4
	await _crane(spot + Vector3.UP * 48.0 + across * 30.0 - along * 20.0, low, spot,
		func(): return spot + Vector3.UP * 1.0 + along * 1.0, 2.7,
		func():
			_drive_hunters(30.0, true, false)
			if _t - t0 > 0.5:
				_line(_rogue("Duchess"), "duchess", 2.6))
	_end()

	# 2. the train, in slow motion
	_begin("train")
	var ahead := along if along.dot(-train.frame_at(s).basis.z) > 0.0 else -along   # (the way the train runs)
	var frame_it := func():
		cam.global_position = spot + ahead * 12.0 + across * 3.5 + Vector3.UP * 7.0
		cam.look_at(spot + Vector3.UP * 1.0 - ahead * 1.0, Vector3.UP)
	await _for(0.35, func():
		_drive_hunters(30.0, true, false)
		frame_it.call())
	_say("MIND THE TRAIN", "", 1.6)
	await _slowmo(0.25, 2.2, func():
		_drive_hunters(30.0, false, false)
		frame_it.call())
	_end()

	# 3. Wheelie, the last of the party, and a sporting suggestion
	if wheelie:
		_calm_hunters()
		_hunters = _hunters.filter(func(h): return h.c == wheelie)
		_soften([wheelie], 10.0)
		var duel := _open_spot(spot + across * 22.0, 8.0)
		_place(bun, duel + along * 2.6, atan2(along.x, along.z))
		_place(wheelie, duel - along * 2.6, atan2(-along.x, -along.z))
		_aim(bun, wheelie.get_chest_position() + Vector3.UP * 0.15)
		_begin("last")
		_line(wheelie, "wheelie", 3.0)
		var over := func():
			cam.global_position = duel + along * 5.2 + across * 1.1 + Vector3.UP * 1.25
			cam.look_at(duel - along * 2.6 + Vector3.UP * 0.5, Vector3.UP)
		await _for(2.4, func():
			_aim(bun, wheelie.get_chest_position() + Vector3.UP * 0.15)
			var to := bun.global_position - wheelie.global_position
			wheelie.look_yaw = atan2(-to.x, -to.z)
			over.call())
		bun.want_fire = true
		await _frame()
		bun.want_fire = false
		await _slowmo(0.3, 0.9, over)
		_end()

	# 4. the end card
	_begin("card")
	_card.visible = true
	_card.modulate.a = 1.0
	_title_box.modulate.a = 0.0
	_slam_title("49 rogues who remember you\nthree maps · carrot guns · ragdolls")
	await _for(0.9)
	var get := _label("FREE TO PLAY", 84, UITheme.CREAM)
	var link := _label("github.com/zconnor100-debug/\nbunny-beat-down", 48, UITheme.CARROT_LIGHT)
	for l in [get, link]:
		_title_box.add_child(l)
		l.modulate.a = 0.0
		l.create_tween().set_ignore_time_scale(true).tween_property(l, "modulate:a", 1.0, 0.3)
	await _for(2.9)
	_end()
