extends "res://tests/trailer_hunt_stage.gd"
## "Your Arsenal", a short 16:9 trailer: a gang spots Bun and charges, Bun
## calls its arsenal in (MatchManager.call_in: the crate drops beside it),
## and each of the three guns gets a shot: the Root Rumbler mows the gang
## down, the Carrot Lobber lobs carrot bombs into a huddle, and the Big Root
## .50 goes through a gang member into Bun's Doppelbunny. The gang shout their
## game lines in their own voices (laid in by the cut, see _shout).
## Recorded on the island ("arsenal", tests/capture_trailer.gd) and cut by
## tools/make_hunt_trailer.py --cut arsenal.

const GANG := ["Rocco", "Fennick", "Bog Boss", "Chompers", "Nutsy"]
const HUDDLE := ["Pudge", "Trash Panda", "Hops McGee", "Twitch"]
const IN_FRONT := "Masky"   ## the one between Bun and its Doppelbunny
const GANG_NAME := "the Thorn Gang"

var _benched: Array = []


## Off stage until its shot.
func _bench(c: Critter) -> void:
	c.visible = false
	c.process_mode = Node.PROCESS_MODE_DISABLED
	c.global_position = Vector3(0, -400, 0)
	_benched.append(c)


func _unbench(c: Critter, at: Vector3, yaw: float) -> void:
	c.visible = true
	c.process_mode = Node.PROCESS_MODE_INHERIT
	_benched.erase(c)
	_place(c, at, yaw)


## A gang member shouts one of the gang's lines (once): its speech bubble now,
## and its voice, the game's own clip of that line (tools/voices/say.py
## --from-bank), laid in by the cut at this frame (heard from the camera, a
## shout across the field was lost under the gunfire).
func _shout(c: Critter, key: String, lines: Array, i: int, seconds := 2.4) -> void:
	if c == null or _said.has(key):
		return
	_said[key] = true
	c.visual.say(lines[i], seconds)
	_bubbles.append(c.visual.get_child(-1))
	print("LINE %s %d" % [key, Engine.get_frames_drawn()])
	print("SHOUT %s %s.%d" % [c.display_name, key, i])


func _yaw_to(d: Vector3) -> float:
	return atan2(-d.x, -d.z)


func _nearest(team: Array) -> Critter:
	var best: Critter = null
	for c in team:
		if c.alive and (best == null or c.global_position.distance_to(bun.global_position) < best.global_position.distance_to(bun.global_position)):
			best = c
	return best


## Between shots: the guns the beaten dropped, and any speech bubble still up.
func _tidy() -> void:
	for n in mm.world_root.get_children():
		if n is Pickup or n is LootCrate:
			(n as Node).queue_free()
	for c in mm.critters:
		for b in c.visual.get_children():
			if b is Label3D and b != c.visual.name_tag:
				b.queue_free()


func _pull_trigger() -> void:
	bun.want_fire = true
	await _frame()
	bun.want_fire = false


func _island() -> void:
	_eject_all()
	cam.make_current()
	# heard from the camera, not from Bun: the gang's shouts as loud as they look
	var ear := AudioListener3D.new()
	cam.add_child(ear)
	ear.make_current()
	Audio.listener = ear
	await _for(0.3)
	var everyone := _gather(GANG + HUDDLE + [IN_FRONT], [&"carrot_smg", &"carrot_shotgun", &"carrot_lmg", &"carrot_smg", &"carrot_rifle"])
	var gang := everyone.filter(func(c): return GANG.any(func(n): return String(c.display_name).begins_with(n)))
	var huddle := everyone.filter(func(c): return HUDDLE.any(func(n): return String(c.display_name).begins_with(n)))
	var masky := _rogue(IN_FRONT)
	_hunters = _hunters.filter(func(h): return gang.has(h.c))
	for c in huddle + [masky]:
		_bench(c)
	# Bun's Doppelbunny, in its cracked mirror (as MatchManager._spawn_doppel dresses one)
	var doppel := mm._spawn_critter(bun.def, DoppelBrain.name_for(bun.def))
	if doppel.state == Critter.State.IN_DROPSHIP and mm.dropship:
		mm.dropship.eject(doppel)
	doppel.visual.apply_skin(bun.visual.skin_id)
	doppel.visual.set_enemy_highlight(doppel.display_name, true)
	DoppelBrain.look(doppel)
	mm.doppel = doppel   # (the match's own: silent, and "MIRROR BROKEN!" when it's beaten down)
	_bench(doppel)
	for id in [&"root_rumbler", &"carrot_lobber", &"big_root_50"]:
		Arsenal.unlock(id)
	var waited := 0
	while mm.phase != MatchManager.Phase.PLAYING and waited < 300:
		await _frame()
		waited += 1

	var spot := _open_spot(_poi("Carrot Patch"), 16.0, true)
	var way := _open_way(spot, 50.0)   # (the gang comes from there, the camera behind them on open ground too)
	var side := way.cross(Vector3.UP)
	_place(bun, spot, _yaw_to(way))
	_hand(bun, &"carrot_pistol", Rarity.Tier.PRIZE)
	for i in gang.size():
		_place(gang[i], spot + way * (40.0 + (i % 2) * 2.5) + side * (i - 2) * 2.6, _yaw_to(-way))
	_spread(side, 2.8)
	mm.make_gang(gang, null, GANG_NAME)

	# 1. the gang, on the prowl; Rocco spots Bun
	_begin("gang")
	_say("GANGS HUNT IN PACKS", "", 2.2)
	var t0 := _t
	await _for(3.2, func():
		_drive_hunters(9.0, false)
		for h in _hunters:
			h.c.want_sprint = false
			h.c.move_input *= 0.45
		_tags_off([gang[0]])   # (the leader's: its name, and the gang's)
		if _t - t0 > 0.6:
			_shout(gang[0], "gspot", Cast.GANG_SPOT_LINES, 1)
		var mid := _middle(gang)
		var f := bun.global_position - mid
		f.y = 0.0
		f = f.normalized()
		cam.global_position = mid - f * 6.5 + f.cross(Vector3.UP) * 1.6 + Vector3.UP * 2.0
		cam.look_at(mid + f * 14.0 + Vector3.UP * 0.6, Vector3.UP)
		_wobble(1.0))
	_end()

	# 2. the charge, over Bun's shoulder; Bog Boss calls it
	_begin("charge")
	t0 = _t
	await _for(2.4, func():
		_drive_hunters(6.0, true)
		_tags_off()
		if _t - t0 > 0.25:
			_shout(gang[2], "grush", Cast.GANG_RUSH_LINES, 2)
		_aim(bun, _middle(gang) + Vector3.UP * 0.6)
		cam.fov = 42.0
		cam.global_position = bun.global_position - way * 2.4 + side * 1.7 + Vector3.UP * 1.0
		cam.look_at(bun.global_position + way * 12.0 + side * 0.3 + Vector3.UP * 0.8, Vector3.UP)
		_wobble(1.4))
	cam.fov = 70.0
	_end()

	# 3. the call-in: the crate drops beside Bun and spills its three guns
	_calm_hunters()
	for c in gang:
		_bench(c)   # (the cut comes back to them, closer)
	mm.player_beat_downs = maxi(mm.player_beat_downs, Arsenal.CALL_AT)
	mm.called_in = false
	var called := mm.call_in()
	print("CALL_IN %s phase %d" % [called, mm.phase])
	var drop: SupplyDrop = null
	for d in get_tree().get_nodes_in_group(&"supply_drops"):
		drop = d
	var land: Vector3 = drop.landing if drop else bun.global_position + way * Arsenal.CALL_DISTANCE
	if drop:
		drop.global_position.y = land.y + 11.0   # (down in a little over a second)
	var crate: LootCrate = null
	_begin("call")
	_say("CALL IN YOUR ARSENAL", "from your 3rd beat-down", 2.2)
	t0 = _t
	await _for(2.8, func():
		_tags_off()
		var f := land - bun.global_position
		f.y = 0.0
		f = f.normalized()
		var s := f.cross(Vector3.UP)
		cam.fov = 58.0
		cam.global_position = bun.global_position + f * 3.0 + s * 5.2 + Vector3.UP * 1.2
		cam.look_at(bun.global_position + f * 3.0 + Vector3.UP * 1.7, Vector3.UP)
		var falling := get_tree().get_nodes_in_group(&"supply_drops")
		_aim(bun, (falling[0] as Node3D).global_position if not falling.is_empty() else land + Vector3.UP * 0.6)
		if crate == null and falling.is_empty():
			for n in mm.world_root.get_children():
				if n is LootCrate and (n as Node3D).global_position.distance_to(land) < 0.5:
					crate = n
		if crate and not crate.opened and _t - t0 > 1.75:
			crate.open(bun))
	_end()

	# 4. the Root Rumbler: spin up, then mow the charge down
	cam.fov = 70.0
	_hand(bun, &"root_rumbler", Rarity.Tier.PRIZE)
	_tidy()
	_soften(gang, 30.0)
	for i in gang.size():
		_unbench(gang[i], spot + way * (24.0 + (i % 2) * 3.0) + side * (i - 2) * 2.4, _yaw_to(-way))
	_place(bun, spot, _yaw_to(way))
	_begin("rumbler")
	_say("ROOT RUMBLER", "1,200 carrots a minute", 2.4)
	t0 = _t
	var mow := func():
		_drive_hunters(3.0, _t - t0 < 1.6)
		_tags_off()
		var tgt := _nearest(gang)
		if tgt:
			_aim(bun, tgt.get_chest_position() + side * sin(_t * 9.0) * 0.25)
		bun.want_aim = true
		bun.want_fire = tgt != null and _t - t0 > 0.15
		cam.fov = 58.0
		cam.global_position = bun.global_position - way * 2.4 + side * 1.7 + Vector3.UP * 1.0
		cam.look_at(bun.global_position + way * 10.0 + side * 0.2 + Vector3.UP * 0.8, Vector3.UP)
		_wobble(1.0 + bun.spin * 1.5)
	await _for(2.3, mow)
	await _slowmo(0.35, 1.4, mow)
	await _for(0.3, mow)
	bun.want_fire = false
	bun.want_aim = false
	cam.fov = 70.0
	_end()
	_calm_hunters()

	# 5. the Carrot Lobber: from behind Bun as it lobs, then beside the huddle, slowed, as it lands
	_tidy()
	var turn := way.rotated(Vector3.UP, PI * 0.5)
	var camp := _open_spot(spot + turn * 16.0, 5.0)
	var lob_dir := camp - bun.global_position
	lob_dir.y = 0.0
	lob_dir = lob_dir.normalized()
	_hand(bun, &"carrot_lobber", Rarity.Tier.PRIZE)
	_place(bun, bun.global_position, _yaw_to(lob_dir))
	for i in huddle.size():
		var a := TAU * i / huddle.size()
		var at := camp + Vector3(cos(a), 0, sin(a)) * 1.3
		_unbench(huddle[i], at, _yaw_to(camp - at))
	_soften(huddle, 30.0)
	var lob_side := lob_dir.cross(Vector3.UP)
	var behind := func():
		_tags_off()
		cam.fov = 50.0
		cam.global_position = bun.global_position - lob_dir * 4.0 + lob_side * 1.8 + Vector3.UP * 2.6
		cam.look_at(camp + Vector3.UP * 1.2, Vector3.UP)
	var beside := func():
		_tags_off()
		cam.fov = 55.0
		cam.global_position = camp + lob_side * 6.5 - lob_dir * 2.0 + Vector3.UP * 2.3
		cam.look_at(camp + Vector3.UP * 0.6, Vector3.UP)
	var near := _nearest(huddle)
	var lob_at := func() -> Vector3: return near.get_chest_position() + Vector3.UP * 0.5   # (a little high: it lands among them)
	await _for(1.0, func():   # (off camera: the Lobber in its paws, ready)
		_aim(bun, lob_at.call())
		behind.call())
	_begin("lobber")
	_say("CARROT LOBBER", "lobbed in an arc", 2.6)
	await _for(0.5, func():
		_aim(bun, lob_at.call())
		behind.call())
	await _pull_trigger()
	await _for(0.3, behind)
	await _slowmo(0.3, 2.2, beside)
	await _for(0.3, beside)
	_end()

	# 6. your Doppelbunny, waiting further off, with a gang member in front of it
	_tidy()
	var back := way.rotated(Vector3.UP, -PI * 0.5)
	var line_from := bun.global_position
	var far := _open_spot(line_from + back * 34.0, 4.0)
	var aim_dir := far - line_from
	aim_dir.y = 0.0
	aim_dir = aim_dir.normalized()
	_hand(doppel, &"carrot_rifle", Rarity.Tier.PRIZE)
	_unbench(doppel, line_from + aim_dir * 34.0, _yaw_to(-aim_dir))
	_place(bun, line_from, _yaw_to(aim_dir))
	bun.want_crouch = true
	for i in 20:   # (settled, crouched, before the gang member is put on the line from the muzzle to the Doppelbunny's chest)
		await _frame()
	var muzzle := bun.get_eye_position() + Vector3.DOWN * 0.15
	var on_line := muzzle.lerp(doppel.get_chest_position(), 29.0 / 34.0)
	_unbench(masky, on_line, _yaw_to(-aim_dir))
	doppel.max_health = 40.0
	doppel.health = 40.0
	_soften([masky], 40.0)
	_hand(bun, &"big_root_50", Rarity.Tier.PRIZE)
	var ds := aim_dir.cross(Vector3.UP)
	_begin("doppel")
	_say("YOUR DOPPELBUNNY FIGHTS LIKE YOU", "", 1.8)
	t0 = _t
	await _for(2.2, func():
		_tags_off([doppel])
		_aim(doppel, bun.get_chest_position())
		doppel.want_aim = true
		_aim(masky, bun.get_chest_position())
		_aim(bun, doppel.get_chest_position())
		var k := (_t - t0) / 2.2
		var d := doppel.global_position
		cam.fov = 45.0
		cam.global_position = d - aim_dir * lerpf(4.4, 3.2, k) + ds * 0.9 + Vector3.UP * 1.0
		cam.look_at(d + Vector3.UP * 0.75, Vector3.UP))
	_end()

	# 7. the Big Root .50, kneeling: through the gang member, into the Doppelbunny
	_begin("fifty")
	_say("BIG ROOT .50", "through two critters", 2.8)
	await _for(1.0, func():
		_tags_off([doppel])
		_aim(bun, doppel.get_chest_position())
		bun.want_aim = true
		cam.fov = 30.0
		cam.global_position = bun.global_position - aim_dir * 3.6 + ds * 1.6 + Vector3.UP * 1.25
		cam.look_at(bun.global_position + aim_dir * 31.0 + Vector3.UP * 0.5, Vector3.UP))
	var both := (masky.global_position + doppel.global_position) * 0.5
	var hit_cam := func():
		_tags_off([doppel])
		cam.fov = 50.0
		cam.global_position = both - ds * 8.5 - aim_dir * 2.5 + Vector3.UP * 1.4
		cam.look_at(both + Vector3.UP * 0.6, Vector3.UP)
	Engine.time_scale = 0.1
	hit_cam.call()
	await _pull_trigger()
	await _for(1.9, hit_cam)
	var ramp := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS).set_ignore_time_scale(true)
	ramp.tween_property(Engine, "time_scale", 1.0, 0.4)
	await _for(0.5, hit_cam)
	Engine.time_scale = 1.0
	bun.want_crouch = false
	bun.want_aim = false
	_end()

	# 8. the end card
	_begin("card")
	_card.visible = true
	_card.modulate.a = 1.0
	_title_box.modulate.a = 0.0
	_slam_title("YOUR ARSENAL")
	await _for(0.8)
	var lines := [_label("Root Rumbler  ·  Carrot Lobber  ·  Big Root .50", 62, UITheme.CREAM),
		_label("Win them on the Trail. Call them in mid-match. Only you carry them.", 42, UITheme.CARROT_LIGHT),
		_label("FREE TO PLAY  ·  github.com/zconnor100-debug/bunny-beat-down", 38, UITheme.CREAM)]
	for i in lines.size():
		var l: Label = lines[i]
		_title_box.add_child(l)
		l.modulate.a = 0.0
		l.create_tween().set_ignore_time_scale(true).tween_property(l, "modulate:a", 1.0, 0.3).set_delay(i * 0.35)
	await _for(3.2)
	_end()
