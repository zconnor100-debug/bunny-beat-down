extends Node
## Stage for tests/capture_kernel.gd (loaded at runtime, so the autoloads
## exist): screenshots of the Kernel Hunt's prologue in the real game, the
## Warren Gazette's special edition it prints and the Kernel Hunt's page;
## with "boss", a Boss Battle won on the island and its special edition;
## with "act1", Act I (The Carrot Patch) from the first carrot to the ending;
## with "act2", Act II (The Clockwork Decree) from the train station to it.

var out_dir := "user://kernel"
var boss := false
var act1 := false
var act2 := false
var movie := false   ## (recorded with Movie Maker: straight to the ending, its frames marked: OUTRO_AT, END_AT; with "act1", Act I's, and KILL_AT; with "act2", Act II's, and TAKEN_AT, LEAP_AT)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		out_dir = a[0]
	boss = a.has("boss")
	act1 = a.has("act1")
	act2 = a.has("act2")
	movie = a.has("movie")
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
	settings.set_value(&"quality", 2, false)
	settings.set_value(&"difficulty", Settings.Difficulty.NORMAL, false)
	if movie:
		if act1:
			await _act_one_movie()
		elif act2:
			await _act_two_movie()
		else:
			await _ending_movie()
		get_tree().quit()
		return
	if boss:
		await _boss_news()
	elif act1:
		await _act_one()
	elif act2:
		await _act_two()
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
		while is_instance_valid(pull) and not pull.opened:
			pull.channel(p, 1.0 / 60.0)
			await get_tree().physics_frame
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

## The menu: the Gazette's special edition, then the Kernel Hunt's page.
func _menu() -> void:
	get_tree().change_scene_to_file("res://scenes/main.tscn")
	await _wait(3.0)
	var menu: Node = get_tree().current_scene
	menu._open_gazette()
	await _wait(1.2)
	var tag := "b" if boss else ("a" if act1 else ("c" if act2 else "k"))
	await _snap(tag + "11_gazette")
	menu._close_overlay()
	if not boss:
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
