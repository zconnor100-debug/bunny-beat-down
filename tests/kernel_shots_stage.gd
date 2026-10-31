extends Node
## Stage for tests/capture_kernel.gd (loaded at runtime, so the autoloads
## exist): screenshots of the Kernel Hunt's prologue in the real game, the
## Warren Gazette's special edition it prints and the Kernel Hunt's page;
## with "boss", a Boss Battle won on the island and its special edition;
## with "act1", Act I (The Carrot Patch) from the first carrot to the ending;
## with "act2", Act II (The Clockwork Decree) from the train station to it;
## with "act3", Act III (Foam at the Falls) from Tube Town to it; with
## "finale", the Finale (The Starfall) from the Barn by night to it.

var out_dir := "user://kernel"
var boss := false
var act1 := false
var act2 := false
var act3 := false
var finale := false
var owl := false     ## ("owl": Old Hoot's Boss Battle, by night, instead)
var epic := false    ## ("epic": shot at the Epic graphics tier, as the game looks on a fast GPU, not High)
var movie := false   ## (recorded with Movie Maker: straight to the ending, its frames marked: OUTRO_AT, END_AT; with "act1", Act I's, and KILL_AT; with "act2", Act II's, and TAKEN_AT, LEAP_AT; with "act3", Act III's, and DAM_AT, WAKE_AT; with "finale", the Finale's, and BRIAR_AT, SHUT_AT, WAKE_AT, POD_AT, SPLIT_AT, KILL_AT)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		out_dir = a[0]
	boss = a.has("boss")
	act1 = a.has("act1")
	act2 = a.has("act2")
	act3 = a.has("act3")
	finale = a.has("finale")
	owl = a.has("owl")
	movie = a.has("movie")
	epic = a.has("epic")
	DirAccess.make_dir_recursive_absolute(out_dir)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	_run.call_deferred()


func _snap(name: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var img := get_tree().root.get_viewport().get_texture().get_image()
	img.save_png(out_dir.path_join(name + ".png"))
	print("shot ", name)


## `sec` of game time (physics ticks), so a slow GPU still shoots the same moments.
func _wait(sec: float) -> void:
	var t := 0.0
	while t < sec:
		await get_tree().physics_frame
		t += 1.0 / Engine.physics_ticks_per_second


## (A pad on this machine drives every Godot window: if it paused the game, carry on.)
func _unpause(g: Node) -> void:
	if g.get("_pause") != null and g._pause:
		g._toggle_pause()


## Turn your camera from where you stand toward `p`, `up` radians above level.
func _look_at(g: Node, p: Vector3, up := 0.0) -> void:
	var from: Vector3 = g.match_manager.player.global_position
	var to := p - from
	g.rig.yaw = atan2(-to.x, -to.z)
	g.rig.pitch = up


func _game() -> Node:
	get_tree().change_scene_to_file("res://scenes/game.tscn")
	await _wait(1.0)
	var g: Node = null
	while g == null or g.get("match_manager") == null or g.match_manager.phase == MatchManager.Phase.LOADING:
		await get_tree().process_frame
		g = get_tree().current_scene
	return g


func _run() -> void:
	var settings: Node = get_tree().root.get_node("Settings")
	settings.set_value(&"quality", 4 if epic else 2, false)
	settings.set_value(&"difficulty", Settings.Difficulty.NORMAL, false)
	if movie:
		if act1:
			await _act_one_movie()
		elif act2:
			await _act_two_movie()
		elif act3:
			await _act_three_movie()
		elif finale:
			await _finale_movie()
		elif owl:
			await _owl_movie()
		else:
			await _ending_movie()
		get_tree().quit()
		return
	if owl:
		await _owl()
	elif boss:
		await _boss_news()
	elif act1:
		await _act_one()
	elif act2:
		await _act_two()
	elif act3:
		await _act_three()
	elif finale:
		await _finale()
	else:
		await _prologue()
	await _menu()
	get_tree().quit()


## Through the three waves at once, then the ending as it plays, the end screen after.
func _ending_movie() -> void:
	KernelHunt.playing = "prologue"
	var g: Node = await _game()
	var mm: MatchManager = g.match_manager
	while mm.phase != MatchManager.Phase.PLAYING:
		await get_tree().process_frame
	var d := mm.mission
	mm.player.max_health = 100000.0
	mm.player.health = mm.player.max_health
	await _wait(9.0)   # ("Nine days without Brutus...": said and done)
	d._t = MissionDirector.FIRST_WAVE
	for n in 3:
		await _wait(4.5)   # (each wave's call, said and done)
		_beat(mm)
		if n < 2:
			await _wait(0.6)
			d._t = MissionDirector.BREATHER
	while d._outro == null:
		await get_tree().process_frame
	print("OUTRO_AT %d" % Engine.get_frames_drawn())
	while mm.phase != MatchManager.Phase.ENDED:
		await get_tree().process_frame
	await _wait(3.5)
	print("END_AT %d" % Engine.get_frames_drawn())
	KernelHunt.playing = ""


## Act I hurried through (time sped up) to Brutus, a few seconds of the
## fight, then him beaten and the ending as it plays, the end screen after.
func _act_one_movie() -> void:
	KernelHunt.playing = "carrot_patch"
	var g: Node = await _game()
	var mm: MatchManager = g.match_manager
	while mm.phase != MatchManager.Phase.PLAYING:
		await get_tree().process_frame
	var d := mm.mission as PatchMission
	var p := mm.player
	p.max_health = 100000.0
	p.health = p.max_health
	Engine.time_scale = 6.0
	await _wait(PatchMission.FIRST_LIT + 0.5)
	for i in PatchMission.CARROTS:
		var c: GlowCarrot = d.carrots[i]
		_beat(mm)
		var to := MissionDirector._flat(c.global_position - p.global_position).normalized()
		p.place_at(d._ground_at(c.global_position - to * 1.4), atan2(-to.x, -to.z))
		await _wait(0.2)
		while not c.opened:
			c.channel(p, 1.0 / 60.0)
			await get_tree().physics_frame
	for spot in d.spots:
		p.place_at(spot.global_position + Vector3(1.5, 0.0, 0.0))
		while not spot.lit:
			_beat(mm)
			await _wait(0.3)
	_beat(mm)
	var to_bluff := MissionDirector._flat(d.bluff_pos - d.patch_pos).normalized()
	p.place_at(d._ground_at(d.bluff_pos - to_bluff * (PatchMission.WAKE_AT - 10.0)))
	while d.step != PatchMission.Step.BOSS:
		await get_tree().process_frame
	Engine.time_scale = 1.0
	while d.answered.is_empty():
		await get_tree().process_frame
	await _wait(6.0)
	var to := mm.boss.get_chest_position() - p.get_eye_position()
	_look_at(g, mm.boss.get_chest_position(), atan2(to.y, Vector2(to.x, to.z).length()) * 0.8)
	print("FIGHT_AT %d" % Engine.get_frames_drawn())
	await _wait(5.0)
	print("KILL_AT %d" % Engine.get_frames_drawn())
	mm.boss.take_damage(DamageInfo.make(1e9, DamageInfo.Kind.BULLET, p, &"carrot_sniper"))
	while d._outro == null:
		await get_tree().process_frame
	print("OUTRO_AT %d" % Engine.get_frames_drawn())
	while mm.phase != MatchManager.Phase.ENDED:
		await get_tree().process_frame
	await _wait(3.5)
	print("END_AT %d" % Engine.get_frames_drawn())
	KernelHunt.playing = ""


func _prologue() -> void:
	KernelHunt.playing = "prologue"
	var g: Node = await _game()
	var mm: MatchManager = g.match_manager
	while mm.phase != MatchManager.Phase.PLAYING:
		await get_tree().process_frame
	var d := mm.mission
	var p := mm.player
	p.max_health = 100000.0
	p.health = p.max_health
	await _wait(1.6)
	await _snap("k01_start")
	# the Barn behind you, the rangers at their posts
	_look_at(g, d.barn_pos + Vector3.UP * 4.0, -0.04)
	await _wait(1.2)
	await _snap("k02_barn")
	# the tally on its door, nine days
	var cam := Camera3D.new()
	get_tree().root.add_child(cam)
	cam.fov = 42.0
	cam.global_position = d.tally.global_position + d.tally.global_transform.basis.z * 3.3 + Vector3.UP * 0.1
	cam.look_at(d.tally.global_position, Vector3.UP)
	cam.make_current()
	g.hud.visible = false
	await _wait(0.6)
	await _snap("k03_tally_nine")
	cam.clear_current(false)
	g.rig.camera.make_current()
	g.hud.visible = true
	# the first wave, marching on the Barn
	d._t = MissionDirector.FIRST_WAVE
	_look_at(g, d.patch_pos + Vector3.UP * 2.0, -0.02)
	await _wait(7.5)
	var near := _nearest(mm, p.global_position)
	if near:
		_look_at(g, near.get_chest_position(), 0.0)
	await _wait(0.4)
	await _snap("k04_touched")
	# one of them, up close
	var close := _nearest(mm, p.global_position)
	if close:
		var brain := close.get_node_or_null("AIBrain")
		if brain:
			brain.process_mode = Node.PROCESS_MODE_DISABLED
		close.move_input = Vector2.ZERO
		close.want_fire = false
		var toward := MissionDirector._flat(p.global_position - d.patch_pos).normalized()
		var spot: Vector3 = d._ground_at(p.global_position - toward * 9.0)
		close.place_at(spot, atan2(-toward.x, -toward.z))
		var cam2 := Camera3D.new()
		get_tree().root.add_child(cam2)
		cam2.fov = 38.0
		await _wait(0.3)
		cam2.global_position = spot + toward * 3.0 + toward.cross(Vector3.UP) * 0.8 + Vector3.UP * 1.0
		cam2.look_at(close.get_chest_position() + Vector3.UP * 0.1, Vector3.UP)
		cam2.make_current()
		g.hud.visible = false
		await _wait(0.4)
		await _snap("k04b_touched_close")
		cam2.clear_current(false)
		cam2.queue_free()
		g.rig.camera.make_current()
		g.hud.visible = true
		if brain:
			brain.process_mode = Node.PROCESS_MODE_INHERIT
	# some of them in the yard
	var fwd := MissionDirector._flat(d.patch_pos - d.barn_pos).normalized()
	var side := fwd.cross(Vector3.UP)
	var i := 0
	for c in mm.alive_critters().filter(func(c): return c.team == 2):
		if i < 3:
			c.place_at(d.barn_pos + fwd * 13.0 + side * (-6.0 + i * 6.0), atan2(fwd.x, fwd.z))
		i += 1
	d.barn = 58.0
	_look_at(g, d.barn_pos + fwd * 13.0 + Vector3.UP * 1.0, -0.05)
	await _wait(0.8)
	await _snap("k05_yard")
	# on to the third wave and its giant
	for n in 2:
		_beat(mm)
		await _wait(0.6)
		d._t = MissionDirector.BREATHER
		await _wait(0.6)
	var giant := d.giant
	if giant:
		var at := p.global_position + fwd * 16.0
		giant.place_at(Vector3(at.x, d.island.terrain.height_at(at.x, at.z), at.z), atan2(fwd.x, fwd.z))
		await _wait(0.5)
		_look_at(g, giant.get_chest_position() + Vector3.UP * 0.5, 0.08)
		await _wait(0.5)
		await _snap("k06_giant")
	_beat(mm)
	# the ending
	while d._outro == null:
		await get_tree().process_frame
	var o := d._outro
	while o.t < 4.0:
		await get_tree().process_frame
	await _snap("k07_bluff")
	while o.t < MissionOutro.REACT_AT + 2.8:
		await get_tree().process_frame
	await _snap("k07b_faces")
	while o.t < MissionOutro.TALLY_AT + 3.0:
		await get_tree().process_frame
	await _snap("k08_tally_zero")
	while o.t < MissionOutro.CARD_AT + 1.2:
		await get_tree().process_frame
	await _snap("k09_card")
	while mm.phase != MatchManager.Phase.ENDED:
		await get_tree().process_frame
	await _wait(1.5)
	await _snap("k10_end")
	KernelHunt.playing = ""


func _boss_news() -> void:
	PlayerProfile.reset_for_tests()   # (the test profile: its first Brutus, for the first headline)
	WarrenSim.reset_for_tests()
	var settings: Node = get_tree().root.get_node("Settings")
	settings.set_value(&"map", "island", false)
	settings.set_value(&"mode", "boss", false)
	settings.set_value(&"boss_intro", false, false)
	settings.set_value(&"seed", 4321, false)
	var g: Node = await _game()
	var mm: MatchManager = g.match_manager
	var p := mm.player
	p.max_health = 100000.0
	p.health = p.max_health
	mm.player_jump()
	var sim := 0.0   # (game time: a slow GPU takes longer, not less far)
	while p.state != Critter.State.GROUND and sim < 60.0:
		p.want_jump = p.state == Critter.State.FREEFALL
		_unpause(g)
		await get_tree().physics_frame
		sim += 1.0 / Engine.physics_ticks_per_second
	while mm.phase != MatchManager.Phase.PLAYING and sim < 120.0:
		_unpause(g)
		await get_tree().physics_frame
		sim += 1.0 / Engine.physics_ticks_per_second
	mm.release_boss()
	var b := mm.boss
	var at := b.global_position
	var spot := p.global_position
	for k in 60:
		var a := randf() * TAU
		var q := at + Vector3(cos(a), 0, sin(a)) * 42.0
		q.y = g.island.terrain.height_at(q.x, q.z)
		if g.island.terrain.normal_at(q.x, q.z).y > 0.95 and not g.island.scatter.blocked(Vector2(q.x, q.z), 8.0, false):
			spot = q
			break
	p.place_at(spot + Vector3.UP * 0.3, 0.0)
	await _wait(3.5)
	for i in 2:
		var to := b.get_chest_position() - p.get_eye_position()
		_look_at(g, b.get_chest_position(), atan2(to.y, Vector2(to.x, to.z).length()) * 0.85)
		await _wait(0.4)
	b.take_damage(DamageInfo.make(1e9, DamageInfo.Kind.BULLET, p, &"carrot_sniper"))
	g._photo_for_the_gazette(String(BossLore.NEWS["brute"].caption), 0.6)
	await _wait(3.0)
	await _snap("b01_end")
	settings.set_value(&"mode", "royale", false)
	settings.set_value(&"boss_intro", true, false)


## Old Hoot's Boss Battle, by night: her arrival (gliding in out of the
## dark, her name, her hoot), circling up high, a Snatch (the dive, a bot
## carried off), a perch (up close on her face, the sliver glowing), shot
## down out of a dive, her Feather Volley, and going down.
func _owl() -> void:
	PlayerProfile.reset_for_tests()
	WarrenSim.reset_for_tests()
	var settings: Node = get_tree().root.get_node("Settings")
	settings.set_value(&"map", "island", false)
	settings.set_value(&"mode", "boss", false)
	settings.set_value(&"boss", "owl", false)
	settings.set_value(&"boss_intro", true, false)
	settings.set_value(&"seed", 4321, false)
	var g: Node = await _game()
	var mm: MatchManager = g.match_manager
	var p := mm.player
	p.max_health = 100000.0
	p.health = p.max_health
	mm.player_jump()
	var sim := 0.0
	while p.state != Critter.State.GROUND and sim < 60.0:
		p.want_jump = p.state == Critter.State.FREEFALL
		_unpause(g)
		await get_tree().physics_frame
		sim += 1.0 / Engine.physics_ticks_per_second
	while mm.phase != MatchManager.Phase.PLAYING and sim < 120.0:
		_unpause(g)
		await get_tree().physics_frame
		sim += 1.0 / Engine.physics_ticks_per_second
	mm.release_boss()
	print("OWL_AT %d" % Engine.get_frames_drawn())
	var b := mm.boss as OwlBoss
	# her arrival: gliding in out of the dark, her name, her hoot
	await _wait(2.6)
	await _snap("o01_gliding_in")
	for i in 900:
		var intro := g.find_children("*", "BossIntro", false, false)
		if not intro.is_empty() and intro[0]._card_shown:
			break
		await get_tree().process_frame
	await _wait(0.8)
	await _snap("o02_named")
	await _wait(1.6)
	await _snap("o03_hoot")
	for i in 1200:
		if g.find_children("*", "BossIntro", false, false).is_empty():
			break
		await get_tree().process_frame
	_unpause(g)
	# up again, circling the fight
	b.thinking = false
	b.start(b._take_off())
	await _wait(2.2)
	for k in [&"snatch", &"rake", &"volley", &"perch", &"hoot"]:
		b.cooldown(k, 99.0)
	b.thinking = true
	p.place_at(_dry_spot(g, b._ground_below(), 45.0) + Vector3.UP * 0.3, 0.0)   # (on land: she skims the lake)
	await _wait(5.0)
	var to := Vector3.ZERO
	for i in 30:   # (she's quick: keep turned to her)
		to = b.get_chest_position() - p.get_eye_position()
		_look_at(g, b.get_chest_position(), atan2(to.y, Vector2(to.x, to.z).length()))
		await get_tree().physics_frame
	await _snap("o04_circling")
	# a Snatch: down onto you (the bots get out of her ring: you stand there), and off with you
	b.thinking = false
	var cam := Camera3D.new()
	get_tree().root.add_child(cam)
	cam.fov = 60.0
	cam.far = 3000.0
	var side := _clear_side(g, p.global_position, 75.0)
	b.start(b._snatch(p))
	await _wait(1.0)
	cam.global_position = p.global_position + side * 75.0 + Vector3.UP * 4.0
	cam.look_at(p.global_position + Vector3.UP * 16.0, Vector3.UP)
	cam.make_current()
	g.hud.visible = false
	await _wait(0.9)
	await _snap("o05_dive")
	await _wait(1.2)
	cam.look_at(b.get_chest_position().lerp(p.global_position, 0.5), Vector3.UP)
	await _wait(0.1)
	await _snap("o06_carried_off")
	while b.action != null:
		await get_tree().process_frame
	await _wait(2.0)   # (you, down again)
	# a perch, on open ground: up close on her face
	var bot2 := _nearest_ally(mm, p.global_position)
	if bot2:
		b.start(b._perch(bot2))
		while b._air or b.action != null:
			await get_tree().process_frame
		await _wait(0.6)
		var eyes := b.eye_positions()
		var face: Vector3 = (eyes[0] + eyes[1]) * 0.5
		var fwd := Vector3(b.forward().x, 0.0, b.forward().z).normalized()
		var view := _clear_side(g, b.global_position, 45.0, fwd)
		var vside := view.cross(Vector3.UP)
		cam.global_position = face + view * 42.0 + vside * 8.0 + Vector3.DOWN * 9.0
		cam.look_at(face + Vector3.DOWN * 6.0, Vector3.UP)
		b.rotation.y = atan2(-view.x, -view.z)   # (turned to the camera: her face)
		cam.make_current()
		g.hud.visible = false
		await _wait(0.3)
		await _snap("o07_perched")
		eyes = b.eye_positions()
		face = (eyes[0] + eyes[1]) * 0.5
		cam.global_position = face + view * 15.0 + vside * 3.0 + Vector3.DOWN * 2.0
		cam.look_at(face, Vector3.UP)
		await _wait(0.2)
		await _snap("o08_the_sliver")
	# shot out of a dive: grounded
	b.start(b._take_off())
	while b.action != null:
		await get_tree().process_frame
	var bot3 := _nearest_ally(mm, p.global_position)
	if bot3:
		b.start(b._snatch(bot3))
		await _wait(1.6)
		for i in int(OwlBoss.GROUND_AT) + 1:
			var hit := DamageInfo.make(5.0, DamageInfo.Kind.BULLET, p, &"carrot_rifle")
			hit.bone_role = &"l_upper_arm"
			b.take_damage(hit)
		while b._air:
			await get_tree().process_frame
		await _wait(0.8)
		var at := b.global_position
		var w := Vector3(b.forward().x, 0.0, b.forward().z).normalized()
		cam.global_position = at + w * 55.0 + w.cross(Vector3.UP) * 25.0 + Vector3.UP * 14.0
		cam.look_at(at + Vector3.UP * 8.0, Vector3.UP)
		cam.make_current()
		g.hud.visible = false
		await _wait(0.2)
		await _snap("o09_grounded")
		while b.action != null:
			await get_tree().process_frame
	# her Feather Volley
	b.start(b._take_off())
	while b.action != null:
		await get_tree().process_frame
	var t := _nearest_ally(mm, p.global_position)
	if t:
		b.start(b._volley(t))
		await _wait(1.2)
		cam.global_position = t.global_position + (b.global_position - t.global_position).normalized().cross(Vector3.UP) * 50.0 + Vector3.UP * 8.0
		cam.look_at(t.global_position.lerp(b.get_chest_position(), 0.5), Vector3.UP)
		cam.make_current()
		g.hud.visible = false
		await _wait(0.1)
		await _snap("o10_volley")
		while b.action != null:
			await get_tree().process_frame
	# down, out of the sky
	var fall_from := _clear_side(g, b._ground_below(), 80.0)
	cam.global_position = b._ground_below() + fall_from * 80.0 + Vector3.UP * 6.0
	cam.look_at(b.get_chest_position(), Vector3.UP)
	b.take_damage(DamageInfo.make(1e9, DamageInfo.Kind.BULLET, p, &"carrot_sniper"))
	g._photo_for_the_gazette(String(BossLore.NEWS["owl"].caption), 1.8)
	await _wait(0.7)
	if g._end:
		g._end.visible = false
	cam.look_at(b.get_chest_position(), Vector3.UP)
	await _snap("o11_falling")
	g.rig.camera.make_current()
	g.hud.visible = true
	if g._end:
		g._end.visible = true
	await _wait(3.0)
	await _snap("o12_end")
	print("END_AT %d" % Engine.get_frames_drawn())
	settings.set_value(&"mode", "royale", false)
	settings.set_value(&"boss", "", false)


## A spot on dry, open, flat land about `dist` from `at` (on the island).
func _dry_spot(g: Node, at: Vector3, dist: float) -> Vector3:
	for k in 48:
		var a := TAU * k / 16.0
		var q := at + Vector3(cos(a), 0.0, sin(a)) * dist * (1.0 + 0.25 * float(k / 16))
		q.y = g.island.terrain.height_at(q.x, q.z)
		if q.y > Terrain.WATER_LEVEL + 0.6 and g.island.terrain.normal_at(q.x, q.z).y > 0.94 \
				and not g.island.scatter.blocked(Vector2(q.x, q.z), 6.0, false):
			return q
	return at


## Which way from `at` (flat) a camera `dist` out has the fewest trees between
## them (the map's Scatter knows every trunk): `prefer` first, then round.
func _clear_side(g: Node, at: Vector3, dist: float, prefer := Vector3.INF) -> Vector3:
	var scatter: Scatter = g.island.scatter if g.island else null
	var first := prefer if prefer != Vector3.INF else Vector3.FORWARD
	var best := first
	var best_n := 1 << 20
	for k in 16:
		var d := first.rotated(Vector3.UP, (1.0 if k % 2 == 0 else -1.0) * float((k + 1) / 2) * TAU / 16.0)
		var n := 0
		for i in 10:
			var q := at + d * dist * (0.15 + 0.085 * i)
			if scatter and scatter.blocked(Vector2(q.x, q.z), 7.0, false):
				n += 1
		if n < best_n:
			best_n = n
			best = d
		if n == 0:
			break
	return best


## Old Hoot's Boss Battle as a film (Movie Maker): her arrival's own
## cinematic, then a camera chasing her round the fight for half a minute
## (she does as she likes: the bots are fighting her), then down she comes.
## Frames marked OWL_AT, CHASE_AT, KILL_AT, END_AT.
func _owl_movie() -> void:
	var settings: Node = get_tree().root.get_node("Settings")
	settings.set_value(&"map", "island", false)
	settings.set_value(&"mode", "boss", false)
	settings.set_value(&"boss", "owl", false)
	settings.set_value(&"boss_intro", true, false)
	settings.set_value(&"seed", 4321, false)
	var g: Node = await _game()
	var mm: MatchManager = g.match_manager
	var p := mm.player
	p.max_health = 100000.0
	p.health = p.max_health
	mm.player_jump()
	Engine.time_scale = 6.0   # (the drop: quick)
	var sim := 0.0
	while mm.phase != MatchManager.Phase.PLAYING and sim < 150.0:
		p.want_jump = p.state == Critter.State.FREEFALL
		await get_tree().physics_frame
		sim += Engine.time_scale / Engine.physics_ticks_per_second
	Engine.time_scale = 1.0
	p.place_at(_dry_spot(g, p.global_position, 20.0) + Vector3.UP * 0.3, 0.0)
	await _wait(1.0)
	mm.release_boss()
	print("OWL_AT %d" % Engine.get_frames_drawn())
	var b := mm.boss as OwlBoss
	for i in 1800:   # (her arrival's own camera, till it's done)
		if g.find_children("*", "BossIntro", false, false).is_empty() and b.state == Boss.State.FIGHTING:
			break
		await get_tree().process_frame
	print("CHASE_AT %d" % Engine.get_frames_drawn())
	var cam := Camera3D.new()
	get_tree().root.add_child(cam)
	cam.fov = 55.0
	cam.far = 3000.0
	cam.make_current()
	g.hud.visible = false
	var place := func(snap: bool) -> void:
		var fwd := Vector3(b.forward().x, 0.0, b.forward().z).normalized()
		var want := b.global_position - fwd * 72.0 + fwd.cross(Vector3.UP) * 30.0 + Vector3.UP * 22.0
		want.y = maxf(want.y, g.island.terrain.height_at(want.x, want.z) + 30.0)   # (over the treetops)
		cam.global_position = want if snap else cam.global_position.lerp(want, 0.06)
		cam.look_at(b.get_chest_position(), Vector3.UP)
	place.call(true)
	var chase := 0.0
	while chase < 30.0 and b.alive:
		place.call(false)
		await get_tree().process_frame
		chase += 1.0 / 30.0
	print("KILL_AT %d" % Engine.get_frames_drawn())
	if b.alive:
		b.take_damage(DamageInfo.make(1e9, DamageInfo.Kind.BULLET, p, &"carrot_sniper"))
	for i in 150:   # (down she comes)
		place.call(false)
		if g._end:
			g._end.visible = false
		await get_tree().process_frame
	g.rig.camera.make_current()
	g.hud.visible = true
	if g._end:
		g._end.visible = true
	await _wait(3.0)
	print("END_AT %d" % Engine.get_frames_drawn())
	settings.set_value(&"mode", "royale", false)
	settings.set_value(&"boss", "", false)


## The bot on your side nearest `to` that's up and on the ground (null if none).
func _nearest_ally(mm: MatchManager, to: Vector3) -> Critter:
	var best: Critter = null
	var best_d := INF
	for c in mm.alive_critters():
		if c == mm.player or c.team != 1 or c.state != Critter.State.GROUND or c.held_by != null:
			continue
		var d := c.global_position.distance_to(to)
		if d < best_d:
			best_d = d
			best = c
	return best


## Act I: the trail of glowing carrots, the Patch burning, Brutus woken at
## Boulder Bluff, and the ending (Little Bru, and the first Kernel).
func _act_one() -> void:
	KernelHunt.playing = "carrot_patch"
	var g: Node = await _game()
	var mm: MatchManager = g.match_manager
	while mm.phase != MatchManager.Phase.PLAYING:
		await get_tree().process_frame
	var d := mm.mission as PatchMission
	var p := mm.player
	p.max_health = 100000.0
	p.health = p.max_health
	await _wait(PatchMission.FIRST_LIT + 0.8)
	_look_at(g, d.carrots[0].global_position + Vector3.UP * 8.0, 0.02)
	await _wait(1.0)
	await _snap("a01_start")
	# the first carrot, lit, the Touched come up round it
	var c0: GlowCarrot = d.carrots[0]
	var cam := Camera3D.new()
	get_tree().root.add_child(cam)
	cam.fov = 50.0
	var back := MissionDirector._flat(p.global_position - c0.global_position).normalized()
	cam.global_position = c0.global_position + back * 6.5 + back.cross(Vector3.UP) * 2.0 + Vector3.UP * 2.4
	cam.look_at(c0.global_position + Vector3.UP * 1.4, Vector3.UP)
	cam.make_current()
	g.hud.visible = false
	await _wait(0.8)
	await _snap("a02_carrot")
	cam.clear_current(false)
	g.rig.camera.make_current()
	g.hud.visible = true
	# pulling it up
	_beat(mm)
	p.place_at(c0.global_position + back * 1.4, atan2(back.x, back.z))
	await _wait(0.4)
	_look_at(g, c0.global_position + Vector3.UP * 0.6, -0.35)
	for k in 40:
		c0.channel(p, 1.0 / 60.0)
		await get_tree().physics_frame
	await _snap("a03_pulling")
	while not c0.opened:
		c0.channel(p, 1.0 / 60.0)
		await get_tree().physics_frame
	await _wait(0.5)
	await _snap("a04_pulled")
	# on down the trail: the next ones lit in turn
	for i in range(1, PatchMission.CARROTS):
		var c: GlowCarrot = d.carrots[i]
		_beat(mm)
		var to := MissionDirector._flat(c.global_position - p.global_position).normalized()
		p.place_at(d._ground_at(c.global_position - to * 1.4), atan2(-to.x, -to.z))
		await _wait(0.3)
		if i == 2:
			_look_at(g, d.carrots[3].global_position + Vector3.UP * 12.0, 0.05)
			await _wait(0.5)
			await _snap("a05_trail")
		while not c.opened:
			c.channel(p, 1.0 / 60.0)
			await get_tree().physics_frame
		await _wait(0.4)
	# the rings: one catching, with you in it
	_beat(mm)
	var s0: BurnSpot = d.spots[0]
	p.place_at(s0.global_position + Vector3(1.5, 0.0, 0.0))
	await _wait(5.0)
	_beat(mm)
	cam.global_position = s0.global_position + Vector3(9.0, 7.0, 9.0)
	cam.look_at(s0.global_position, Vector3.UP)
	cam.make_current()
	await _wait(0.3)
	await _snap("a06_ring_catching")
	g.rig.camera.make_current()
	for s in d.spots:
		p.place_at(s.global_position + Vector3(1.5, 0.0, 0.0))
		while not s.lit:
			_beat(mm)
			await _wait(0.5)
		if s == d.spots[0]:
			await _wait(1.8)
			cam.global_position = s.global_position + MissionDirector._flat(d.barn_pos - s.global_position).normalized() * 16.0 + Vector3.UP * 6.5
			cam.look_at(s.global_position + Vector3.UP * 2.5, Vector3.UP)
			cam.make_current()
			g.hud.visible = false
			await _wait(0.4)
			await _snap("a07_fire")
			g.rig.camera.make_current()
			g.hud.visible = true
	# the whole Patch going up: off to the Bluff
	await _wait(9.0)
	var away := MissionDirector._flat(d.barn_pos - d.patch_pos).normalized()
	cam.global_position = d.patch_pos + away * 70.0 + Vector3.UP * 22.0
	cam.look_at(d.patch_pos + Vector3.UP * 12.0, Vector3.UP)
	cam.make_current()
	g.hud.visible = false
	await _wait(0.5)
	await _snap("a08_patch_burns")
	g.rig.camera.make_current()
	g.hud.visible = true
	_beat(mm)
	var to_bluff := MissionDirector._flat(d.bluff_pos - d.patch_pos).normalized()
	var off := MissionDirector._flat(d.bluff_pos - d.patch_pos).length() - PatchMission.WAKE_AT
	p.place_at(d._ground_at(d.patch_pos + to_bluff * clampf(off * 0.6, 26.0, maxf(off - 5.0, 26.0))))
	_look_at(g, d.bluff_pos + Vector3.UP * 10.0, 0.03)
	await _wait(1.0)
	await _snap("a09_to_the_bluff")
	# he comes
	p.place_at(d._ground_at(d.bluff_pos - to_bluff * (PatchMission.WAKE_AT - 10.0)))
	while d.step != PatchMission.Step.BOSS:
		await get_tree().process_frame
	await _wait(3.4)
	await _snap("a10_brutus")
	while d.answered.is_empty():
		await get_tree().process_frame
	await _wait(2.5)
	var r: Critter = d.answered[0]
	if is_instance_valid(r):
		_look_at(g, r.global_position, 0.35)
	await _wait(0.3)
	await _snap("a11_warren_answers")
	await _wait(6.0)
	_look_at(g, mm.boss.get_chest_position(), 0.1)
	await _wait(0.5)
	await _snap("a12_fight")
	mm.boss.take_damage(DamageInfo.make(1e9, DamageInfo.Kind.BULLET, p, &"carrot_sniper"))
	# the ending
	while d._outro == null:
		await get_tree().process_frame
	var o := d._outro as PatchOutro
	while o.t < PatchOutro.SHRINK_AT + 1.4:
		await get_tree().process_frame
	await _snap("a13_shrinking")
	while o.t < PatchOutro.FACES_AT - 0.6:
		await get_tree().process_frame
	await _snap("a14_bru")
	while o.t < PatchOutro.FACES_AT + 2.0:
		await get_tree().process_frame
	await _snap("a15_faces")
	while o.t < PatchOutro.BRU_AT + 3.0:
		await get_tree().process_frame
	await _snap("a16_kernel")
	while o.t < PatchOutro.CARD_AT + 1.4:
		await get_tree().process_frame
	await _snap("a17_card")
	while mm.phase != MatchManager.Phase.ENDED:
		await get_tree().process_frame
	await _wait(1.5)
	await _snap("a18_end")
	cam.queue_free()
	KernelHunt.playing = ""


## Act II hurried through (time sped up) to the castle; then the flag going
## up, the eyes on the bookshelf, his jump and a few seconds of the fight,
## him beaten and the ending as it plays, the end screen after.
func _act_two_movie() -> void:
	KernelHunt.playing = "clockwork_decree"
	var g: Node = await _game()
	var mm: MatchManager = g.match_manager
	while mm.phase != MatchManager.Phase.PLAYING:
		await get_tree().process_frame
	var d := mm.mission as ClockworkMission
	var p := mm.player
	p.max_health = 100000.0
	p.health = p.max_health
	Engine.time_scale = 6.0
	await _wait(1.0)
	for c in d.wound_rogues.duplicate():
		_beat(mm)
		c.take_damage(DamageInfo.make(1e6, DamageInfo.Kind.BULLET, p, &"carrot_rifle"))
		p.place_at(c.global_position + Vector3(1.0, 0.0, 0.6))
		var pull: KeyPull = d._down[c][0] if d._down.has(c) else null
		if is_instance_valid(pull):
			pull.open(p)   # (straight out: at this speed it'd wind itself back up first, and it's not in the clip)
	while d.step != ClockworkMission.Step.BREAK:
		await get_tree().process_frame
	for s in d.stations:
		s.break_down(p)
	while d.step != ClockworkMission.Step.STORM:
		await get_tree().process_frame
	p.place_at(d.ring.global_position + Vector3(1.0, 0.0, 0.0))
	while d.ring.progress < 0.9:
		_beat(mm)
		await _wait(0.3)
	_beat(mm)
	Engine.time_scale = 1.0
	while not d.ring.lit:
		await get_tree().process_frame
	print("TAKEN_AT %d" % Engine.get_frames_drawn())
	# out of the gate, looking up at the bookshelf as the eyes find you
	var out := d.castle_out
	p.place_at(d._ground_at(d.castle_pos + out * 34.0), atan2(out.x, out.z))
	var to := ClockworkMission.SHELF - p.get_eye_position()
	_look_at(g, ClockworkMission.SHELF, atan2(to.y, Vector2(to.x, to.z).length()) * 0.75)
	while d.step != ClockworkMission.Step.BOSS:
		await get_tree().process_frame
	print("LEAP_AT %d" % Engine.get_frames_drawn())
	while mm.boss.state != Boss.State.FIGHTING:
		await get_tree().process_frame
	await _wait(2.5)
	var at := mm.boss.get_chest_position() - p.get_eye_position()
	_look_at(g, mm.boss.get_chest_position(), atan2(at.y, Vector2(at.x, at.z).length()) * 0.8)
	await _wait(5.0)
	print("KILL_AT %d" % Engine.get_frames_drawn())
	mm.boss.take_damage(DamageInfo.make(1e9, DamageInfo.Kind.BULLET, p, &"carrot_sniper"))
	while d._outro == null:
		await get_tree().process_frame
	print("OUTRO_AT %d" % Engine.get_frames_drawn())
	while mm.phase != MatchManager.Phase.ENDED:
		await get_tree().process_frame
	await _wait(3.5)
	print("END_AT %d" % Engine.get_frames_drawn())
	KernelHunt.playing = ""


## Act III hurried through (time sped up) to the last chew block, then the
## falls dammed, the bedding heaving and Nibbles bursting up out of it, a few
## seconds of the fight, him beaten and the ending as it plays, the end screen.
func _act_three_movie() -> void:
	KernelHunt.playing = "foam_at_the_falls"
	var g: Node = await _game()
	var mm: MatchManager = g.match_manager
	while mm.phase != MatchManager.Phase.PLAYING:
		await get_tree().process_frame
	var d := mm.mission as FoamMission
	var p := mm.player
	p.max_health = 100000.0
	p.health = p.max_health
	Engine.time_scale = 6.0
	await _wait(1.0)
	for b in d.burrows:
		_beat(mm)
		Events.explosion.emit(b.global_position + b.out * 1.5, 5.0)
	while d.step != FoamMission.Step.DAM:
		await get_tree().process_frame
	var into := MissionDirector._flat(-d.falls_pos).normalized()
	for b in d.blocks:
		_beat(mm)
		p.place_at(b.global_position + Vector3(1.2, 0.0, 0.8))
		await _wait(0.2)
		while b.carrier == null:
			b.channel(p, 1.0 / 60.0)
			await get_tree().physics_frame
		if b == d.blocks.back():
			# the last one in as it plays: the drips stop, and the bedding heaves
			Engine.time_scale = 1.0
			_beat(mm)
			p.place_at(d._ground_at(d.falls_pos + into * 6.0), atan2(into.x, into.z))
			_look_at(g, d.falls_pos + Vector3.UP * 6.0, 0.2)
			print("DAM_AT %d" % Engine.get_frames_drawn())
		else:
			p.place_at(d._ground_at(d.falls_pos + into * 4.0))
		while not b.placed:
			await get_tree().physics_frame
	await _wait(1.6)
	var spot := d._boss_spot()
	var to := spot - p.get_eye_position()
	_look_at(g, spot, atan2(to.y, Vector2(to.x, to.z).length()) + 0.15)
	print("WAKE_AT %d" % Engine.get_frames_drawn())
	while mm.boss == null or mm.boss.state != Boss.State.FIGHTING:
		await get_tree().process_frame
	# out in the open while his intro plays (he'd be on top of you by its end,
	# out of the shot), and the camera kept on him as he comes
	p.place_at(d._ground_at(d.falls_pos + into * 34.0))
	await _wait(2.5)
	var fight := 0.0
	while fight < 5.0:
		var at := mm.boss.get_chest_position() - p.get_eye_position()
		_look_at(g, mm.boss.get_chest_position(), atan2(at.y, Vector2(at.x, at.z).length()) * 0.8)
		await get_tree().physics_frame
		fight += 1.0 / Engine.physics_ticks_per_second
	print("KILL_AT %d" % Engine.get_frames_drawn())
	var nibbles := mm.boss
	nibbles.take_damage(DamageInfo.make(1e9, DamageInfo.Kind.BULLET, p, &"carrot_sniper"))
	while d._outro == null:
		if is_instance_valid(nibbles):   # (on him as he goes down)
			_look_at(g, nibbles.global_position + Vector3.UP * 2.0, 0.05)
		await get_tree().process_frame
	print("OUTRO_AT %d" % Engine.get_frames_drawn())
	while mm.phase != MatchManager.Phase.ENDED:
		await get_tree().process_frame
	await _wait(3.5)
	print("END_AT %d" % Engine.get_frames_drawn())
	KernelHunt.playing = ""

## The Finale hurried through (time sped up) to the Briar coming up round the
## Bluff and the Warren gliding in, then the Heart up out of the Bluff, a pod
## broken and its Kernel free, split open, beaten, and the ending as it plays,
## the end screen.
func _finale_movie() -> void:
	KernelHunt.playing = "starfall"
	var g: Node = await _game()
	var unpause := _unpause.bind(g)
	get_tree().process_frame.connect(unpause)   # (every frame of it)
	var mm: MatchManager = g.match_manager
	while mm.phase != MatchManager.Phase.PLAYING:
		await get_tree().process_frame
	var d := mm.mission as StarfallMission
	var p := mm.player
	p.max_health = 100000.0
	p.health = p.max_health
	Engine.time_scale = 6.0
	await _wait(1.0)
	for r in d.roots:
		_beat(mm)
		r.receive_blast(r.knot_point(), 6.0, 1e5, p, &"carrot_rocket_launcher")
	while d.step != StarfallMission.Step.BRIAR:
		await get_tree().process_frame
	# the Briar up round the Bluff, closing, and the Warren gliding in
	Engine.time_scale = 1.0
	var toward := MissionDirector._flat(d.barn_pos - d.heart_pos).normalized()
	p.place_at(d._ground_at(d.heart_pos + toward * 75.0), atan2(toward.x, toward.z))
	_look_at(g, d.heart_pos + Vector3.UP * 25.0, 0.12)
	print("BRIAR_AT %d" % Engine.get_frames_drawn())
	await _wait(9.0)
	Engine.time_scale = 6.0
	p.place_at(d._ground_at(d.heart_pos + toward * 40.0), atan2(toward.x, toward.z))
	while mm.storm.shrinking:
		_beat(mm)
		await get_tree().process_frame
	Engine.time_scale = 1.0
	_look_at(g, d.heart_pos + Vector3.UP * 6.0, 0.1)
	print("SHUT_AT %d" % Engine.get_frames_drawn())
	while d.step != StarfallMission.Step.BOSS:
		await get_tree().process_frame
	print("WAKE_AT %d" % Engine.get_frames_drawn())
	var heart := mm.boss as BriarHeart
	while heart.state != Boss.State.FIGHTING:
		await get_tree().process_frame
	for i in 1200:   # (its arrival over: the camera's yours)
		if g.find_children("*", "BossIntro", false, false).is_empty():
			break
		await get_tree().process_frame
	# up close for the fight, just outside its Lash
	p.place_at(d._ground_at(d.heart_pos + toward * (BriarHeart.LASH_R + 4.0)), atan2(toward.x, toward.z))
	heart._bloom_t = 1.5
	var fight := 0.0
	var broke := false
	while fight < 14.0:
		var aim := heart.get_eye_position()
		var at := aim - p.get_eye_position()
		_look_at(g, aim, atan2(at.y, Vector2(at.x, at.z).length()))
		if not broke and heart.bloom_i >= 0 and heart.pod_open(heart.bloom_i) and fight > 4.0:
			broke = true
			print("POD_AT %d" % Engine.get_frames_drawn())
			var shot := DamageInfo.make(heart.pod_max / BriarHeart.POD_OPEN + 1.0, DamageInfo.Kind.BULLET, p, &"carrot_rifle")
			shot.bone_role = StringName("pod_%d" % heart.bloom_i)
			heart.take_damage(shot)
		await get_tree().physics_frame
		fight += 1.0 / Engine.physics_ticks_per_second
	# the other two, and it splits open
	for i in BriarHeart.PODS:
		if not heart._pods[i].broken:
			var hit := DamageInfo.make(heart.pod_max / BriarHeart.POD_SHUT + 1.0, DamageInfo.Kind.BULLET, p, &"carrot_rifle")
			hit.bone_role = StringName("pod_%d" % i)
			heart.take_damage(hit)
	print("SPLIT_AT %d" % Engine.get_frames_drawn())
	fight = 0.0
	while fight < 5.0:
		var at := heart.get_chest_position() - p.get_eye_position()
		_look_at(g, heart.get_chest_position(), atan2(at.y, Vector2(at.x, at.z).length()))
		await get_tree().physics_frame
		fight += 1.0 / Engine.physics_ticks_per_second
	print("KILL_AT %d" % Engine.get_frames_drawn())
	var core := DamageInfo.make(1e7, DamageInfo.Kind.BULLET, p, &"carrot_sniper")
	core.bone_role = &"core"
	heart.take_damage(core)
	while d._outro == null:
		var at := heart.get_chest_position() - p.get_eye_position()
		_look_at(g, heart.get_chest_position(), atan2(at.y, Vector2(at.x, at.z).length()))
		await get_tree().process_frame
	print("OUTRO_AT %d" % Engine.get_frames_drawn())
	while mm.phase != MatchManager.Phase.ENDED:
		await get_tree().process_frame
	await _wait(3.5)
	print("END_AT %d" % Engine.get_frames_drawn())
	get_tree().process_frame.disconnect(unpause)
	KernelHunt.playing = ""

## Act II: from the train station to the ending, every part of it.
func _act_two() -> void:
	KernelHunt.playing = "clockwork_decree"
	var g: Node = await _game()
	var mm: MatchManager = g.match_manager
	while mm.phase != MatchManager.Phase.PLAYING:
		await get_tree().process_frame
	var d := mm.mission as ClockworkMission
	var p := mm.player
	p.max_health = 100000.0
	p.health = p.max_health
	await _wait(2.5)
	await _snap("c01_start")
	await _wait(5.0)   # (the act's card gone)
	var cam := Camera3D.new()
	get_tree().root.add_child(cam)
	cam.fov = 50.0
	# a Wound rogue, the key in its back
	var w: Critter = d.wound_rogues[0]
	var wb := -MissionDirector._flat(w.global_basis.z).normalized()   # (its front is -z: its back's this way)
	cam.global_position = w.global_position - wb * 4.5 + wb.cross(Vector3.UP) * 2.2 + Vector3.UP * 2.0
	cam.look_at(w.get_chest_position(), Vector3.UP)
	cam.make_current()
	g.hud.visible = false
	await _wait(0.6)
	await _snap("c02_wound")
	# the eyes on the bookshelf, and their light on the floor
	cam.global_position = d.castle_pos + Vector3(60.0, 14.0, 120.0)
	cam.look_at(ClockworkMission.SHELF, Vector3.UP)
	cam.fov = 60.0
	await _wait(0.4)
	await _snap("c03_watching")
	# ...and where their light is on the floor
	var pool: Vector3 = d.watch._at
	cam.global_position = pool + Vector3(40.0, 45.0, 40.0)
	cam.look_at(pool, Vector3.UP)
	await _wait(0.3)
	await _snap("c03_light")
	cam.fov = 50.0
	cam.clear_current(false)
	g.rig.camera.make_current()
	g.hud.visible = true
	# beaten down: it winds down, and you pull its key
	for c in mm.alive_critters().filter(func(c): return c.team == 2 and c != w and c.global_position.distance_to(w.global_position) < 40.0):
		c.take_damage(DamageInfo.make(1e6, DamageInfo.Kind.BULLET, p, &"carrot_rifle"))
	var to := MissionDirector._flat(w.global_position - p.global_position).normalized()
	p.place_at(d._ground_at(w.global_position - to * 2.0), atan2(-to.x, -to.z))
	w.take_damage(DamageInfo.make(1e6, DamageInfo.Kind.BULLET, p, &"carrot_rifle"))
	await _wait(1.6)
	_look_at(g, w.get_chest_position(), -0.25)
	await _wait(0.3)
	await _snap("c04_wound_down")
	var kp: KeyPull = d._down[w][0]
	for k in 50:
		kp.channel(p, 1.0 / 60.0)
		await get_tree().physics_frame
	await _snap("c05_pulling")
	while is_instance_valid(kp) and not kp.opened:
		kp.channel(p, 1.0 / 60.0)
		await get_tree().physics_frame
	await _wait(1.6)
	await _snap("c06_freed")
	# the rest unwound
	for c in d.wound_rogues.duplicate():
		_beat(mm)
		c.take_damage(DamageInfo.make(1e6, DamageInfo.Kind.BULLET, p, &"carrot_rifle"))
		p.place_at(c.global_position + Vector3(1.0, 0.0, 0.6))
		var pull: KeyPull = d._down[c][0] if d._down.has(c) else null
		while is_instance_valid(pull) and not pull.opened:
			pull.channel(p, 1.0 / 60.0)
			await get_tree().physics_frame
		await _wait(0.3)
	while d.step != ClockworkMission.Step.BREAK:
		await get_tree().process_frame
	# a winding station, at it
	var s0: WindingStation = d.stations[0]
	var front := s0.global_basis.z.normalized()
	p.place_at(d._ground_at(s0.global_position + front * 30.0), atan2(front.x, front.z))
	await _wait(1.0)
	cam.global_position = s0.global_position + front.rotated(Vector3.UP, 0.6) * 22.0 + Vector3.UP * 7.0
	cam.look_at(s0.global_position + Vector3.UP * 5.0, Vector3.UP)
	cam.make_current()
	g.hud.visible = false
	s0._wind_t = 0.0
	await _wait(1.0)
	await _snap("c07_station")
	await _wait(2.0)
	await _snap("c08_winding_out")
	g.rig.camera.make_current()
	g.hud.visible = true
	_look_at(g, s0.global_position + Vector3.UP * 6.0, 0.05)
	var rifle := WeaponDB.get_weapon(&"carrot_rifle")
	for k in 6:
		s0.receive_shot(p, rifle, 60.0, s0.global_position + Vector3.UP * 7.0 + front * 2.0, -front, &"spring")
		await _wait(0.12)
	await _snap("c09_station_hit")
	cam.make_current()
	g.hud.visible = false
	s0.break_down(p)
	await _wait(0.35)
	await _snap("c10_station_breaks")
	await _wait(2.0)
	await _snap("c11_scrap")
	g.rig.camera.make_current()
	g.hud.visible = true
	for s in d.stations:
		s.break_down(p)
	while d.step != ClockworkMission.Step.STORM:
		await get_tree().process_frame
	await _wait(1.0)
	# the castle: its courtyard held by the Wound
	var out := d.castle_out
	p.place_at(d._ground_at(d.castle_pos + out * 40.0), atan2(out.x, out.z))
	_look_at(g, d.castle_pos + Vector3.UP * 4.0, 0.05)
	await _wait(1.5)
	await _snap("c12_castle")
	p.place_at(d.ring.global_position + Vector3(1.0, 0.0, 0.0))
	while not d.ring.lit:
		_beat(mm)
		await _wait(0.4)
	await _wait(2.4)
	cam.global_position = d.castle_pos + out * 40.0 + out.cross(Vector3.UP) * 14.0 + Vector3.UP * 12.0
	cam.look_at(d.castle_pos + Vector3.UP * 15.0, Vector3.UP)
	cam.make_current()
	g.hud.visible = false
	await _snap("c13_flag")
	await _wait(1.6)
	cam.global_position = d.castle_pos + out * 70.0 + Vector3.UP * 26.0
	cam.look_at(d.castle_pos.lerp(ClockworkMission.SHELF, 0.45), Vector3.UP)
	cam.fov = 62.0
	await _wait(0.3)
	await _snap("c14_glare")
	cam.fov = 50.0
	g.rig.camera.make_current()
	g.hud.visible = true
	while d.step != ClockworkMission.Step.BOSS:
		await get_tree().process_frame
	await _wait(1.8)
	await _snap("c15_leap")
	await _wait(2.6)
	await _snap("c16_tyrant")
	while mm.boss.state != Boss.State.FIGHTING:
		await get_tree().process_frame
	await _wait(5.0)
	_look_at(g, mm.boss.get_chest_position(), 0.2)
	await _wait(0.5)
	await _snap("c17_fight")
	mm.boss.take_damage(DamageInfo.make(1e9, DamageInfo.Kind.BULLET, p, &"carrot_sniper"))
	# the ending
	while d._outro == null:
		await get_tree().process_frame
	var o := d._outro as ClockworkOutro
	for shot in [["c18_key_stops", ClockworkOutro.GLOW_AT + 0.6], ["c19_shrinking", ClockworkOutro.SHRINK_AT + 2.0],
			["c20_kernel_out", ClockworkOutro.KERNEL_AT + 0.6], ["c21_faces", ClockworkOutro.FACES_AT + 1.5],
			["c22_gets_up", ClockworkOutro.TURN_AT + 0.4], ["c23_steps", ClockworkOutro.WALK_AT + 1.0], ["c24_beep", ClockworkOutro.BEEP_AT + 0.15],
			["c25_kernels", ClockworkOutro.KERNELS_AT + 2.6], ["c26_pulling", ClockworkOutro.PULL_AT + 2.0], ["c27_card", ClockworkOutro.CARD_AT + 1.4]]:
		while o.playing and o.t < float(shot[1]):
			await get_tree().process_frame
		await _snap(String(shot[0]))
	while mm.phase != MatchManager.Phase.ENDED:
		await get_tree().process_frame
	await _wait(1.5)
	await _snap("c28_end")
	cam.queue_free()
	KernelHunt.playing = ""

## Act III: from Tube Town to the ending, every part of it.
func _act_three() -> void:
	KernelHunt.playing = "foam_at_the_falls"
	var g: Node = await _game()
	var mm: MatchManager = g.match_manager
	while mm.phase != MatchManager.Phase.PLAYING:
		await get_tree().process_frame
	var d := mm.mission as FoamMission
	var p := mm.player
	p.max_health = 100000.0
	p.health = p.max_health
	await _wait(2.5)
	await _snap("d01_start")
	await _wait(5.0)   # (the act's card gone)
	var cam := Camera3D.new()
	get_tree().root.add_child(cam)
	cam.fov = 50.0
	# a burrow, and the Touched coming up out of it
	var b0: BurrowMouth = d.burrows[0]
	p.place_at(d._ground_at(b0.global_position + b0.out * 30.0))
	b0._t = 0.0
	await _wait(1.0)
	var side := b0.out.cross(Vector3.UP)
	cam.global_position = b0.global_position + b0.out * 13.0 + side * 6.0 + Vector3.UP * 5.0
	cam.look_at(b0.global_position + Vector3.UP * 1.5, Vector3.UP)
	cam.make_current()
	g.hud.visible = false
	await _wait(0.4)
	await _snap("d02_burrow")
	# caved in by a grenade
	Events.explosion.emit(b0.global_position + b0.out * 1.5, 5.0)
	await _wait(0.4)
	await _snap("d03_cave_in")
	await _wait(1.5)
	await _snap("d04_caved")
	g.rig.camera.make_current()
	g.hud.visible = true
	for b in d.burrows:
		_beat(mm)
		Events.explosion.emit(b.global_position + b.out * 1.5, 5.0)
	while d.step != FoamMission.Step.DAM:
		await get_tree().process_frame
	await _wait(1.0)
	# the falls, the ring, the blocks
	var into := MissionDirector._flat(-d.falls_pos).normalized()
	cam.global_position = d.falls_pos + into * 52.0 + into.cross(Vector3.UP) * 14.0 + Vector3.UP * 26.0
	cam.look_at(d.falls_pos + Vector3.UP * 8.0, Vector3.UP)
	cam.make_current()
	g.hud.visible = false
	await _wait(0.4)
	await _snap("d05_falls")
	g.rig.camera.make_current()
	g.hud.visible = true
	# carrying one
	var blk: ChewBlock = d.blocks[0]
	_beat(mm)
	p.place_at(blk.global_position + Vector3(1.2, 0.0, 0.8))
	await _wait(0.3)
	while blk.carrier == null:
		blk.channel(p, 1.0 / 60.0)
		await get_tree().physics_frame
	var to := d.falls_pos - p.global_position
	p.place_at(p.global_position, atan2(-to.x, -to.z))
	_look_at(g, d.falls_pos + Vector3.UP * 4.0, 0.1)
	await _wait(0.8)
	await _snap("d06_carrying")
	for b in d.blocks:
		_beat(mm)
		if b.placed:
			continue
		if b.carrier == null:
			p.place_at(b.global_position + Vector3(1.2, 0.0, 0.8))
			await _wait(0.2)
			while b.carrier == null:
				b.channel(p, 1.0 / 60.0)
				await get_tree().physics_frame
		p.place_at(d._ground_at(d.falls_pos + into * 4.0))
		while not b.placed:
			await get_tree().physics_frame
		await _wait(0.5)
		p.place_at(d._ground_at(d.falls_pos + into * 22.0), atan2(into.x, into.z))
	cam.global_position = d.falls_pos + into * 16.0 + into.cross(Vector3.UP) * 6.0 + Vector3.UP * 6.0
	cam.look_at(d.falls_pos + Vector3.UP * 1.5, Vector3.UP)
	cam.make_current()
	g.hud.visible = false
	await _wait(0.6)
	await _snap("d07_dammed")
	g.rig.camera.make_current()
	g.hud.visible = true
	await _wait(1.2)
	await _snap("d08_heave")
	while d.step != FoamMission.Step.BOSS:
		await get_tree().process_frame
	await _wait(2.0)
	await _snap("d09_nibbles")
	# up close as his name comes up
	for i in 600:
		var intro := g.find_children("*", "BossIntro", false, false)
		if not intro.is_empty() and intro[0]._card_shown:
			break
		await get_tree().process_frame
	await _wait(0.8)
	await _snap("d09b_named")
	while mm.boss.state != Boss.State.FIGHTING:
		await get_tree().process_frame
	await _wait(4.0)
	_look_at(g, mm.boss.get_chest_position(), 0.15)
	await _wait(0.5)
	await _snap("d10_fight")
	mm.boss.take_damage(DamageInfo.make(1e9, DamageInfo.Kind.BULLET, p, &"carrot_sniper"))
	while d._outro == null:
		await get_tree().process_frame
	var o := d._outro as FoamOutro
	for shot in [["d11_glow", FoamOutro.GLOW_AT + 0.8], ["d12_shrinking", FoamOutro.SHRINK_AT + 2.0],
			["d13_little", FoamOutro.SPIT_AT - 0.2], ["d14_spit", FoamOutro.SPIT_AT + 0.8], ["d15_faces", FoamOutro.FACES_AT + 1.5],
			["d16_kernels", FoamOutro.KERNELS_AT + 3.0], ["d17_briar", FoamOutro.BRIAR_AT + 1.8], ["d18_card", FoamOutro.CARD_AT + 1.4]]:
		while o.playing and o.t < float(shot[1]):
			await get_tree().process_frame
		await _snap(String(shot[0]))
	while mm.phase != MatchManager.Phase.ENDED:
		await get_tree().process_frame
	await _wait(1.5)
	await _snap("d19_end")
	cam.queue_free()
	KernelHunt.playing = ""

## The Finale by night: the Barn facing the Bluff's light, a root and its
## knot, the Briar closing, the Heart up out of the Bluff and named, its pods,
## split open, then the ending as it plays, and the end screen.
func _finale() -> void:
	KernelHunt.playing = "starfall"
	var g: Node = await _game()
	var mm: MatchManager = g.match_manager
	while mm.phase != MatchManager.Phase.PLAYING:
		await get_tree().process_frame
	var d := mm.mission as StarfallMission
	var p := mm.player
	p.max_health = 100000.0
	p.health = p.max_health
	await _wait(2.5)
	await _snap("e01_start")
	await _wait(5.0)   # (the act's card gone)
	var cam := Camera3D.new()
	get_tree().root.add_child(cam)
	cam.fov = 50.0
	cam.far = 3000.0
	# a root's knot, the root running off to the Bluff, the Touched growing up by it
	var r0: BriarRoot = d.roots[1]
	var out := MissionDirector._flat(r0.global_position - d.heart_pos).normalized()
	var side := out.cross(Vector3.UP)
	p.place_at(d._ground_at(r0.global_position + out * 30.0))
	r0._sprout_t = 0.0
	await _wait(1.2)
	cam.global_position = r0.global_position + out * 14.0 + side * 7.0 + Vector3.UP * 4.5
	cam.look_at(r0.knot_point() - out * 6.0, Vector3.UP)
	cam.make_current()
	g.hud.visible = false
	await _wait(0.4)
	await _snap("e02_root")
	r0.receive_blast(r0.knot_point(), 6.0, 1e5, p, &"carrot_rocket_launcher")
	await _wait(0.3)
	await _snap("e03_knot_bursts")
	await _wait(2.5)
	await _snap("e04_withered")
	g.rig.camera.make_current()
	g.hud.visible = true
	for r in d.roots:
		_beat(mm)
		r.receive_blast(r.knot_point(), 6.0, 1e5, p, &"carrot_rocket_launcher")
	while d.step != StarfallMission.Step.BRIAR:
		await get_tree().process_frame
	await _wait(3.0)
	# the Briar coming up round the Bluff, closing in
	var toward := MissionDirector._flat(d.barn_pos - d.heart_pos).normalized()
	p.place_at(d._ground_at(d.heart_pos + toward * 90.0))
	_look_at(g, d.heart_pos + Vector3.UP * 20.0, 0.1)
	await _wait(1.0)
	await _snap("e05_briar_closing")
	await _wait(4.0)
	await _snap("e06_warren")
	p.place_at(d._ground_at(d.heart_pos + toward * 40.0))
	_beat(mm)
	Engine.time_scale = 4.0
	while mm.storm.shrinking:
		await get_tree().process_frame
	Engine.time_scale = 1.0
	while d.step != StarfallMission.Step.BOSS:
		await get_tree().process_frame
	await _wait(1.6)
	await _snap("e07_rising")
	for i in 900:
		var intro := g.find_children("*", "BossIntro", false, false)
		if not intro.is_empty() and intro[0]._card_shown:
			break
		await get_tree().process_frame
	await _wait(0.8)
	await _snap("e08_named")
	var heart := mm.boss as BriarHeart
	while heart.state != Boss.State.FIGHTING:
		await get_tree().process_frame
	await _wait(3.0)
	_look_at(g, heart.get_chest_position(), 0.2)
	await _wait(0.5)
	await _snap("e09_fight")
	heart.thinking = false
	heart._bloom_t = 0.0
	while heart.bloom_i < 0 or not heart.pod_open(heart.bloom_i):
		await get_tree().process_frame
	await _wait(0.6)
	var pod := heart.pod_point(heart.bloom_i)
	var pod_out := MissionDirector._flat(pod - heart.global_position).normalized()
	cam.global_position = pod + pod_out * 9.0 + heart.forward() * 8.0 + Vector3.DOWN * 3.0
	cam.look_at(pod, Vector3.UP)
	cam.make_current()
	g.hud.visible = false
	await _wait(0.2)
	await _snap("e10_pod_open")
	var shot := DamageInfo.make(heart.pod_max / BriarHeart.POD_OPEN + 1.0, DamageInfo.Kind.BULLET, p, &"carrot_rifle")
	shot.bone_role = StringName("pod_%d" % heart.bloom_i)
	heart.take_damage(shot)
	await _wait(0.4)
	await _snap("e11_pod_broken")
	for i in BriarHeart.PODS:
		if not heart._pods[i].broken:
			var hit := DamageInfo.make(heart.pod_max / BriarHeart.POD_SHUT + 1.0, DamageInfo.Kind.BULLET, p, &"carrot_rifle")
			hit.bone_role = StringName("pod_%d" % i)
			heart.take_damage(hit)
	await _wait(2.4)
	cam.global_position = heart.global_position + heart.forward() * 44.0 + Vector3.UP * 9.0
	cam.look_at(heart.get_chest_position(), Vector3.UP)
	await _wait(0.2)
	await _snap("e12_split_open")
	g.rig.camera.make_current()
	g.hud.visible = true
	_look_at(g, heart.get_chest_position(), 0.2)
	await _wait(0.6)
	await _snap("e13_fight_open")
	var core := DamageInfo.make(1e7, DamageInfo.Kind.BULLET, p, &"carrot_sniper")
	core.bone_role = &"core"
	heart.take_damage(core)
	while d._outro == null:
		await get_tree().process_frame
	var o := d._outro as StarfallOutro
	for s in [["e14_drained", StarfallOutro.GATHER_AT + 2.0], ["e15_husk", StarfallOutro.HUSK_AT + 2.0],
			["e16_whole", StarfallOutro.WHOLE_AT + 0.9], ["e17_faces", StarfallOutro.WHOLE_AT + 2.6],
			["e18_rising", StarfallOutro.RISE_AT + 3.0], ["e19_going", StarfallOutro.RISE_AT + 6.5],
			["e20_star", StarfallOutro.STAR_AT + 1.6], ["e21_card", StarfallOutro.CARD_AT + 1.4]]:
		while o.playing and o.t < float(s[1]):
			await get_tree().process_frame
		await _snap(String(s[0]))
	while mm.phase != MatchManager.Phase.ENDED:
		await get_tree().process_frame
	await _wait(1.5)
	await _snap("e22_end")
	cam.queue_free()
	KernelHunt.playing = ""

## The menu: the Gazette's special edition, then the Kernel Hunt's page.
func _menu() -> void:
	get_tree().change_scene_to_file("res://scenes/main.tscn")
	await _wait(3.0)
	var menu: Node = get_tree().current_scene
	menu._open_gazette()
	await _wait(1.2)
	var tag := "o" if owl else ("b" if boss else ("a" if act1 else ("c" if act2 else ("d" if act3 else ("e" if finale else "k")))))
	await _snap(tag + "11_gazette")
	menu._close_overlay()
	if not (boss or owl):
		menu._open_quest()
		await _wait(1.0)
		await _snap(tag + "12_quest")


func _beat(mm: MatchManager) -> void:
	for c in mm.alive_critters().filter(func(c): return c.team == 2):
		c.take_damage(DamageInfo.make(1e6, DamageInfo.Kind.BULLET, mm.player, &"carrot_rifle"))


func _nearest(mm: MatchManager, to: Vector3) -> Critter:
	var best: Critter = null
	var best_d := INF
	for c in mm.alive_critters():
		if c.team == 2 and c.global_position.distance_to(to) < best_d:
			best_d = c.global_position.distance_to(to)
			best = c
	return best
