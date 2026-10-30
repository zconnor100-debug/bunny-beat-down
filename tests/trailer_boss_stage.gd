extends "res://tests/trailer_hunt_stage.gd"
## "Boss Battles", a 16:9 trailer: the Warren's legend in two lines, then each
## map's boss arriving the way the game plays it (BossIntro: the fall, the
## slam, its name and the line the Warren knows it by) and what it does:
## Brutus's ground pound and boulder, the Tin Tyrant's eye lasers and its
## wind-down (shoot the key), Nibbles's charge into a wall, and its fall; then
## Bun in the pieces you keep (the Brutus coat, the Tin Tyrant gun skin, the
## Rabid froth) and the card. The rogues round it shout the game's own boss
## lines (Cast.BOSS_LINES) in their own voices, laid in by the cut: the stage
## prints LINE <id> <frame> and SHOUT <rogue> <id> <key>, and the clips come
## from the voice banks (tools/voices/say.py --from-bank). Everything else is
## the real game: the bots fight it with their own brains. Recorded a map at a
## time ("boss island|toybox|cage", tests/capture_trailer.gd) and cut by
## tools/make_hunt_trailer.py --cut boss.

## Where each boss lands: the Carrot Patch (where Brutus ate the glowing
## carrots), Block Castle (where the Tin Tyrant crowned itself), the Sand Bath
## (open sand, the cage's glass not far off for its charge to end in).
const WHERE := {"island": "Carrot Patch", "toybox": "Block Castle", "cage": "Sand Bath"}
const GUNS := [&"carrot_rifle", &"carrot_lmg", &"carrot_smg", &"carrot_shotgun", &"carrot_rifle", &"carrot_rocket_launcher"]

var boss: Boss
var _land := Vector3.ZERO     # (where it lands)
var _fwd := Vector3.FORWARD   # (flat: from there toward the crowd and Bun)
var _crowd: Array = []        # (the bots in the shots, fighting it)


func _ready() -> void:
	get_tree().root.get_node("Settings").set_value(&"mode", "boss", false)
	BossIntro.skippable = false
	super()


# ---- setting up ---------------------------------------------------------------------------------

## Everyone down at once (no drop) in a crowd facing where it'll land, armed;
## the boss's countdown off (the stage lets it in) and the rogues' own boss
## talk off (the stage's lines are laid in by the cut).
func _set_up() -> void:
	while mm.dropship == null or not mm.dropship.flying:
		await _frame()
	await _for(1.2)   # (the loading screen's gone)
	cam.make_current()
	_eject_all()
	await _frame()
	await _frame()
	mm.set("_boss_t", -1.0)
	mm.banter = false
	boss = mm.boss
	boss.thinking = false
	var near := _poi(WHERE[map])
	_land = _clearing(near, MatchManager.BOSS_CLEARING)
	_fwd = _open_way(_land, 60.0)
	var side := _fwd.cross(Vector3.UP)
	_crowd = _bots()
	for i in _crowd.size():
		var c: Critter = _crowd[i]
		var ring := 24.0 + 30.0 * float(i % 4) / 3.0 + _rng.randf_range(-2.0, 2.0)   # (a few close enough to be flung when it lands)
		var across := (float(i) / maxf(_crowd.size() - 1.0, 1.0) - 0.5) * 1.5
		var at := _land + (_fwd * cos(across) + side * sin(across)) * ring
		_place(c, at, _yaw_to(_land - at))
		_hand(c, GUNS[i % GUNS.size()], [Rarity.Tier.GARDEN, Rarity.Tier.PRIZE, Rarity.Tier.GOLDEN][i % 3])
		c.defies_director = true
	_place(bun, _land + _fwd * 60.0 + side * 3.0, _yaw_to(-_fwd))
	_hand(bun, &"carrot_lmg", Rarity.Tier.GOLDEN)
	bun.max_health = 99999.0
	bun.health = bun.max_health
	_tags_off()


## The crowd's own brains on: they fight it, and get out from under its blows.
func _let_them_fight() -> void:
	for c in _crowd:
		var brain: Node = c.get_node_or_null("AIBrain")
		if brain and c.alive:
			brain.process_mode = Node.PROCESS_MODE_INHERIT


func _yaw_to(d: Vector3) -> float:
	return atan2(-d.x, -d.z)


## One of the crowd shouts one of the game's boss lines: its bubble now, its
## voice laid in by the cut at this frame.
func _shout(c: Critter, key: String, text: String, seconds := 2.4) -> void:
	if c == null or not is_instance_valid(c):
		return
	var id := key.replace(".", "_")
	if _said.has(id):
		return
	_said[id] = true
	c.visual.say(text, seconds)
	_bubbles.append(c.visual.get_child(-1))
	print("LINE %s %d" % [id, Engine.get_frames_drawn()])
	print("SHOUT %s|%s|%s" % [c.display_name, id, key])


## The one of the crowd still up nearest `p` (or the camera).
func _nearest_to(p: Vector3, but: Critter = null) -> Critter:
	var best: Critter = null
	for c in _crowd:
		if c != but and is_instance_valid(c) and c.alive and (best == null or c.global_position.distance_to(p) < best.global_position.distance_to(p)):
			best = c
	return best


## It lands (the game's own arrival: BossIntro has the camera till it's done),
## and one of the crowd names it, as the Warren would.
func _arrival(shot: String) -> void:
	_begin(shot)
	mm.release_boss(_land)
	var intro: BossIntro = null
	for i in 5:
		await _frame()
		intro = game.get_node_or_null("BossIntro")
		if intro:
			break
	var named := false
	while intro and is_instance_valid(intro) and intro.playing:
		if not named and boss.fight_time() >= boss.land_time + 0.9:
			named = true
			_shout(_nearest_to(bun.global_position), "bn." + boss.id, Cast.BOSS_NAME_LINES[boss.id], 3.0)
		await _frame()
	_end()   # (as the intro gives the camera back)
	cam.make_current()


## A camera spot `dist` off `at` (flat), `angle` round from the crowd's side
## (from _fwd), or the nearest angle to it with a clear view of `look` (no
## roof, wall or tree trunk in the way, nothing just overhead, not in water),
## `height` over the ground there.
func _cam_spot(at: Vector3, look: Vector3, angle: float, dist: float, height: float) -> Vector3:
	var first := Vector3.INF
	for k in 15:
		var a := angle + 0.3 * ceilf(k / 2.0) * (1.0 if k % 2 == 0 else -1.0)
		var p := at + _fwd.rotated(Vector3.UP, a) * dist
		p.y = game.island.terrain.height_at(p.x, p.z) + height
		if first == Vector3.INF:
			first = p
		if _clear(p, look) and _clear(p, p + Vector3.UP * 6.0) and _dry(p - Vector3.UP * (height - 0.2)) and not _leafy(p, look):
			return p
	return first


## A tree's crown on the way from `p` to `look` (crowns aren't solid: the
## map's Scatter knows where the trunks stand), or one over `p`.
func _leafy(p: Vector3, look: Vector3) -> bool:
	var scatter: Scatter = game.island.get("scatter")
	if scatter == null:
		return false
	if scatter.blocked(Vector2(p.x, p.z), 6.0, false):
		return true
	for i in 10:
		var q := p.lerp(look, 0.09 * (i + 1))
		if scatter.blocked(Vector2(q.x, q.z), 5.0, false):
			return true
	return false


## The nearest spot to `near` that's dry, fairly flat and open: nothing in
## the map's Scatter (trees, rocks, props, building plots) within `r` (else
## the nearest open one, _open_spot's).
func _clearing(near: Vector3, r: float) -> Vector3:
	var scatter: Scatter = game.island.get("scatter")
	if scatter == null:
		return _open_spot(near, 26.0, map == "island")
	for ring in 16:
		for k in maxi(1, ring * 8):
			var a := TAU * k / maxf(1.0, ring * 8.0)
			var p := _ground(near + Vector3(cos(a), 0, sin(a)) * ring * 10.0)
			if not _dry(p) or scatter.blocked(Vector2(p.x, p.z), r, true):   # (building plots too: Block Castle's walls)
				continue
			var flat := true
			for d in 8:
				var far := p + Vector3(cos(d * TAU / 8.0), 0, sin(d * TAU / 8.0)) * r
				if absf(game.island.terrain.height_at(far.x, far.z) - p.y) > r * 0.25 or not _dry(_ground(far)):
					flat = false
					break
			if flat:
				return p
	return _open_spot(near, 26.0, map == "island")


## The angle (round from _fwd) of the way `d` points.
func _angle_of(d: Vector3) -> float:
	return _fwd.signed_angle_to(Vector3(d.x, 0.0, d.z).normalized(), Vector3.UP)


## Looking at it from `from` (pushed in a little over the shot), shaking a bit.
func _watch_boss(from: Vector3, k: float, look_up := 0.0) -> void:
	cam.global_position = from.lerp(Vector3(boss.global_position.x, from.y, boss.global_position.z), k * 0.06)
	cam.look_at(boss.get_chest_position() + Vector3.UP * look_up, Vector3.UP)
	_wobble(0.6)


func _do(a: BossAction) -> void:
	if a:
		boss.start(a)


# ---- Wildwood Island: Brutus ----------------------------------------------------------------------

func _island() -> void:
	await _set_up()
	# 1. the legend, over the meadow and the crowd looking out to where it'll land
	_begin("meadow")
	var low := _cam_spot(_land, _land + Vector3.UP * 40.0, 0.25, 76.0, 3.5)
	var high := low + Vector3.UP * 30.0 + _fwd * 10.0
	_say("ONE NIGHT, A STAR FELL ON WILDWOOD", "", 1.6)
	await _crane(high, low, _land, func(): return _land + Vector3.UP * 30.0, 2.0)
	_say("IT WASN'T A STAR", "", 1.2)
	await _for(1.6, func():
		cam.look_at(_land + Vector3.UP * lerpf(30.0, 60.0, (_t - _t0()) / 1.6), Vector3.UP)
		_wobble(0.4))
	_end()
	# 2. Brutus drops out of the sky (the game's own intro)
	await _arrival("arrival")
	_let_them_fight()
	# 3. the ground pound: the crowd round its feet, a RUN!, the shockwave
	boss.global_position = _land
	var near: Array = _crowd.filter(func(c): return c.alive).slice(0, 7)
	for i in near.size():
		var a := (float(i) / maxf(near.size() - 1.0, 1.0) - 0.5) * 1.6
		var at: Vector3 = _land + _fwd.rotated(Vector3.UP, a) * _rng.randf_range(12.0, 20.0)
		_place(near[i], at, _yaw_to(_land - at))
	var from := _cam_spot(_land, boss.get_chest_position(), 0.9, 48.0, 3.0)
	cam.global_position = from
	_begin("pound")
	_say("BOSS BATTLES", "25 of you. 1 of it.", 2.2)
	var t0 := _t
	var watch := func(): _watch_boss(from, (_t - t0) / 3.2, 2.0)
	await _for(0.5, watch)
	_do(boss.call("_pound"))
	await _for(0.25, watch)
	_shout(_nearest_to(cam.global_position), "br.0", Cast.BOSS_RUN_LINES[0], 1.6)
	await _for(0.75, watch)
	await _slowmo(0.35, 0.9, watch)
	await _for(0.8, watch)
	_end()
	# 4. the boulder, thrown at a knot of them (and at the camera behind them)
	var knot: Array = _crowd.filter(func(c): return c.alive).slice(7, 11)
	var spot := _open_spot(_land + _fwd.rotated(Vector3.UP, -0.5) * 62.0, 10.0, true)
	for i in knot.size():
		_place(knot[i], spot + Vector3(_rng.randf_range(-3, 3), 0, _rng.randf_range(-3, 3)), _yaw_to(_land - spot))
	var target: Critter = knot[0] if not knot.is_empty() else bun
	var behind := _cam_spot(spot, boss.get_chest_position(), _angle_of(spot - _land), 14.0, 4.0)
	cam.global_position = behind
	_begin("boulder")
	_do(boss.call("_toss", target))
	await _for(3.0, func():
		cam.look_at(boss.get_chest_position().lerp(target.global_position, 0.25), Vector3.UP)
		_wobble(0.8))
	_end()


# ---- Toy Box Bash: the Tin Tyrant -------------------------------------------------------------------

func _toybox() -> void:
	await _set_up()
	_begin("toy_wide")
	var low := _cam_spot(_land, _land + Vector3.UP * 30.0, 0.2, 72.0, 3.0)
	await _crane(low + Vector3.UP * 24.0, low, _land, func(): return _land + Vector3.UP * 25.0, 1.5)
	_end()
	await _arrival("tyrant")
	_let_them_fight()
	# the eye lasers, sweeping in at a knot of them (and the camera behind)
	boss.global_position = _land
	var knot: Array = _crowd.filter(func(c): return c.alive).slice(0, 5)
	var spot := _open_spot(_land + _fwd * 46.0, 10.0)
	for i in knot.size():
		_place(knot[i], spot + _fwd.cross(Vector3.UP) * (i - 2.0) * 3.0, _yaw_to(_land - spot))
	var target: Critter = knot[2] if knot.size() > 2 else bun
	cam.global_position = _cam_spot(spot, boss.get_eye_position(), _angle_of(spot - _land) + 0.35, 13.0, 3.0)
	_begin("lasers")
	_say("EVERY MAP HAS ONE", "Brutus  ·  the Tin Tyrant  ·  Nibbles", 2.4)
	_do(boss.call("_lasers", target))
	await _for(0.6)
	_shout(knot[0] if not knot.is_empty() else null, "br.1", Cast.BOSS_RUN_LINES[1], 2.0)
	await _for(3.2, func():
		cam.look_at(boss.get_eye_position().lerp(target.global_position, 0.55), Vector3.UP)
		_wobble(0.7))
	_end()
	# the missiles
	_begin("barrage")
	cam.global_position = _cam_spot(_land, target.global_position, -0.8, 70.0, 14.0)
	_do(boss.call("_barrage", target))
	await _for(3.4, func():
		cam.look_at(_land.lerp(target.global_position, 0.6) + Vector3.UP * 6.0, Vector3.UP)
		_wobble(0.5))
	_end()
	# it winds down: everyone on its key. The camera goes where it has a clear
	# view of the key (the castle's walls are tall), and it's turned with its
	# back to the camera; the crowd between, pouring it on.
	await _for(0.3)
	boss.action = null
	boss.global_position = _land
	var key_at := _land + Vector3.UP * 15.0
	var back := _fwd
	var key_cam := Vector3.INF
	for dist: float in [26.0, 20.0, 14.0]:
		for k in 21:
			var d := _fwd.rotated(Vector3.UP, 0.3 * ceilf(k / 2.0) * (1.0 if k % 2 == 0 else -1.0))
			var p := key_at + d * dist + d.cross(Vector3.UP) * 6.0 + Vector3.DOWN * 4.0
			if _clear(p, key_at) and _clear(p, key_at + Vector3.DOWN * 10.0) and _clear(p + Vector3.UP * 2.0, p):
				key_cam = p
				back = d
				break
		if key_cam != Vector3.INF:
			break
	boss.rotation.y = _yaw_to(-back)
	if key_cam == Vector3.INF:
		key_cam = key_at + back * 26.0 + Vector3.DOWN * 4.0
	for i in _crowd.size():
		var c: Critter = _crowd[i]
		if c.alive and i < 9:
			var at := _land + back.rotated(Vector3.UP, (i - 4.0) * 0.16) * _rng.randf_range(12.0, 20.0)
			_place(c, at, _yaw_to(_land - at))
	_do(boss.call("_wind_down"))
	_begin("key")
	_say("FIND ITS WEAK SPOT", "", 1.8)
	var shooter := _nearest_to(key_cam)
	cam.global_position = key_cam
	var watch_key := func():
		var key := boss.bone_point(&"key", 0.5) if boss.poser.has(&"key") else boss.get_chest_position()
		cam.look_at(key, Vector3.UP)
		_wobble(0.5)
	await _for(0.5, watch_key)
	_shout(shooter, "bk", Cast.BOSS_KEY_LINE, 2.4)
	await _for(3.0, watch_key)
	_end()


# ---- the Hamster Cage: Nibbles --------------------------------------------------------------------

func _cage() -> void:
	await _set_up()
	await _arrival("nibbles")
	_let_them_fight()
	# the charge: through a line of them and head first into the wall behind
	var run := _wall_run(_land)
	var dir: Vector3 = run[0]
	var wall: float = run[1]
	boss.global_position = _land
	boss.rotation.y = _yaw_to(dir)
	var line: Array = _crowd.filter(func(c): return c.alive).slice(0, 6)
	var at := _land + dir * clampf(wall - 22.0, 30.0, 110.0)   # (within its charge's reach of the wall: it crashes)
	for i in line.size():
		var p := at + dir.cross(Vector3.UP) * (i - 2.5) * 3.2
		_place(line[i], p, _yaw_to(-dir))
	var target: Critter = line[2] if line.size() > 2 else bun
	var side := dir.cross(Vector3.UP)
	var mid := _land + dir * (wall * 0.5)
	cam.global_position = _cam_spot(mid, mid + Vector3.UP * 8.0, _angle_of(side), 46.0, 8.0)
	_begin("charge")
	_do(boss.call("_charge", target))
	var stunned_said := false
	await _for(4.6, func():
		cam.look_at(boss.get_chest_position(), Vector3.UP)
		_wobble(0.5)
		if boss.vulnerable() and not stunned_said:
			stunned_said = true
			_shout(_nearest_to(boss.global_position), "bw.0", Cast.BOSS_WEAK_LINES[0], 2.2))
	_end()
	# it goes down; the crowd cheers (and the match is over, but not on screen)
	if mm.finished.is_connected(game._on_match_finished):
		mm.finished.disconnect(game._on_match_finished)
	cam.global_position = _cam_spot(boss.global_position, boss.get_chest_position(), _angle_of(side - dir * 0.5), 44.0, 4.0)
	_begin("down")
	await _for(0.3, func(): cam.look_at(boss.get_chest_position(), Vector3.UP))
	boss.take_damage(DamageInfo.make(1e9, DamageInfo.Kind.BULLET, bun, &"carrot_lmg"))
	var first := _nearest_to(cam.global_position)
	await _for(0.9, func(): cam.look_at(boss.get_chest_position(), Vector3.UP))
	_shout(first, "bd.0", Cast.BOSS_DOWN_LINES[0], 2.2)
	await _for(1.0, func(): cam.look_at(boss.get_chest_position(), Vector3.UP))
	_shout(_nearest_to(cam.global_position, first), "bd.1", Cast.BOSS_DOWN_LINES[1], 2.0)
	await _for(1.6, func(): cam.look_at(boss.get_chest_position(), Vector3.UP))
	_end()
	# Bun, in the pieces you keep (the guns the beaten dropped, and the bubbles, cleared away)
	for n in mm.world_root.get_children():
		if n is Pickup or n is LootCrate:
			(n as Node).queue_free()
	for c in _crowd:
		var brain: Node = c.get_node_or_null("AIBrain")
		if brain:
			brain.process_mode = Node.PROCESS_MODE_DISABLED
		if c.alive and c.global_position.distance_to(boss.global_position) < 70.0:
			c.move_input = Vector2.ZERO
			c.want_fire = false
	var stand := boss.global_position + side * 36.0   # (clear of it, lying there)
	for c in _crowd:   # (nobody between Bun and the camera)
		if c.alive and c.global_position.distance_to(stand) < 16.0:
			c.visible = false
			c.process_mode = Node.PROCESS_MODE_DISABLED
			c.global_position = Vector3(0, -400, 0)
	Outfits.wear_coat(bun.visual, "brutus")
	bun.visual.kit = {"skin": "tin_tyrant"}
	_hand(bun, &"carrot_lmg", Rarity.Tier.PRIZE)   # (a golden gun wears no skin)
	_place(bun, stand, _yaw_to(stand - boss.global_position))   # (to the camera, the giant lying behind)
	_begin("reward")
	_say("BEAT THEM. KEEP A PIECE OF THEM.", "the Brutus coat  ·  the Tin Tyrant skin  ·  the Rabid froth", 2.8)
	var burst_at := [0.6, 1.3, 2.0]
	var t0 := _t
	await _for(3.6, func():
		var k := (_t - t0) / 3.6
		var orbit := side.rotated(Vector3.UP, lerpf(-0.45, 0.25, k))
		cam.global_position = bun.global_position + orbit * lerpf(4.6, 3.6, k) + Vector3.UP * 1.4
		cam.look_at(bun.get_chest_position() + Vector3.UP * 0.3 - orbit * 1.5, Vector3.UP)
		for b in burst_at.duplicate():
			if _t - t0 >= b:
				burst_at.erase(b)
				FX.beat_down(bun.global_position + orbit.cross(Vector3.UP) * _rng.randf_range(-2.2, 2.2) - orbit * 2.5 + Vector3.UP * 1.2, "froth"))
	_end()
	# the card
	_begin("card")
	_card.visible = true
	_card.modulate.a = 1.0
	_title_box.modulate.a = 0.0
	_slam_title("BOSS BATTLES")
	await _for(0.8)
	var lines := [_label("Brutus  ·  the Tin Tyrant  ·  Nibbles the Rabid", 62, UITheme.CREAM),
		_label("Twenty-five of you. One of it. Every map has its own.", 42, UITheme.CARROT_LIGHT),
		_label("FREE TO PLAY  ·  github.com/zconnor100-debug/bunny-beat-down", 38, UITheme.CREAM)]
	for i in lines.size():
		var l: Label = lines[i]
		_title_box.add_child(l)
		l.modulate.a = 0.0
		l.create_tween().set_ignore_time_scale(true).tween_property(l, "modulate:a", 1.0, 0.3).set_delay(i * 0.35)
	await _for(3.4)
	_end()


## The way from `p` with a wall (the cage's glass, a big toy) 60 to 140 m off
## at Nibbles's head height: [the way, how far].
func _wall_run(p: Vector3) -> Array:
	var space := get_viewport().get_world_3d().direct_space_state
	var best := [_fwd, 140.0]
	var best_score := INF
	for k in 24:
		var d := Vector3(sin(k * TAU / 24.0), 0, cos(k * TAU / 24.0))
		var o := p + Vector3.UP * 6.0
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(o, o + d * 140.0, Layers.WORLD))
		if hit.is_empty():
			continue
		var dist := o.distance_to(hit.position)
		var score := absf(dist - 95.0)
		if dist > 60.0 and score < best_score:
			best_score = score
			best = [d, dist]
	return best
