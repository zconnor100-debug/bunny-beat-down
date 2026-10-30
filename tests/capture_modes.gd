extends SceneTree
## Screenshots of a Boss Battle or a Team Battle in the real game (needs a GPU window).
##   godot --path . -s tests/capture_modes.gd -- <out_dir> boss|teams [island|cage|toybox]

var out_dir := "user://modes"
var which := "boss"
var map := "island"


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		out_dir = a[0]
	if a.size() > 1:
		which = a[1]
	if a.size() > 2:
		map = a[2]
	DirAccess.make_dir_recursive_absolute(out_dir)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	_run.call_deferred()


func _snap(name: String) -> void:
	await process_frame
	await process_frame
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(out_dir.path_join(name + ".png"))
	print("shot ", name)


func _wait(sec: float) -> void:
	var t := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t < sec * 1000.0:
		await process_frame


## (A pad on this machine drives every Godot window: if it paused the game, carry on.)
func _unpause(g: Node) -> void:
	if g.get("_pause") != null and g._pause:
		g._toggle_pause()


## Point the camera from where it is at `p`, `up` radians above level.
func _look_at(g: Node, p: Vector3, up := 0.0) -> void:
	var from: Vector3 = g.match_manager.player.global_position
	var to := p - from
	g.rig.yaw = atan2(-to.x, -to.z)
	g.rig.pitch = up


func _run() -> void:
	var settings: Node = root.get_node("Settings")
	settings.set_value(&"quality", 2, false)
	settings.set_value(&"seed", 4321, false)
	settings.set_value(&"map", map, false)
	settings.set_value(&"mode", which, false)
	change_scene_to_file("res://scenes/game.tscn")
	await _wait(1.0)
	var g: Node = null
	while g == null or g.match_manager == null:
		await process_frame
		g = current_scene
	await _wait(2.5)
	var mm = g.match_manager
	var p = mm.player
	p.max_health = 100000.0
	p.health = p.max_health
	if which == "teams":
		await _snap("t01_two_balloons")
	mm.player_jump()
	var t0 := Time.get_ticks_msec()
	while p.state != 3 and Time.get_ticks_msec() - t0 < 50000:
		p.want_jump = p.state == 1
		_unpause(g)
		await process_frame
	var playing: int = load("res://src/match/match_manager.gd").Phase.PLAYING
	t0 = Time.get_ticks_msec()
	while mm.phase != playing and Time.get_ticks_msec() - t0 < 50000:
		_unpause(g)
		await process_frame
	mm.phase = playing
	p.give_weapon(load("res://src/weapons/weapon_instance.gd").new(load("res://data/weapons/carrot_lmg.tres"), 3))
	if which == "teams":
		await _teams(g)
	else:
		await _boss(g)
	quit()


func _boss(g: Node) -> void:
	var mm = g.match_manager
	var p = mm.player
	await _wait(1.0)
	_unpause(g)
	await _snap("b01_waiting")   # (its bar counting down)
	mm.release_boss()
	var b = mm.boss
	var at: Vector3 = b.global_position
	# you, 75 m off where it lands, facing it, on open ground if there is any
	var spot: Vector3 = p.global_position
	for k in 60:
		var a := randf() * TAU
		var q: Vector3 = at + Vector3(cos(a), 0, sin(a)) * 48.0
		q.y = g.island.terrain.height_at(q.x, q.z)
		if g.island.terrain.normal_at(q.x, q.z).y > 0.95 and (g.island.scatter == null or not g.island.scatter.blocked(Vector2(q.x, q.z), 8.0, false)):
			spot = q
			break
	p.place_at(spot + Vector3.UP * 0.3, 0.0)
	# the bots gather round where it lands, so there's a fight to see
	var k := 0
	for c in mm.critters:
		if c == p or not c.alive:
			continue
		var a2 := TAU * k / 12.0 + 0.4
		var cp: Vector3 = at + Vector3(cos(a2), 0, sin(a2)) * (40.0 + (k % 3) * 9.0)
		cp.y = g.island.terrain.height_at(cp.x, cp.z) + 0.3
		c.place_at(cp, 0.0)
		c.give_weapon(load("res://src/weapons/weapon_instance.gd").new(load("res://data/weapons/carrot_rifle.tres"), 1))
		c.inventory.ammo[0] = 300
		c.inventory.ammo[1] = 300
		k += 1
	_look_at(g, at + Vector3.UP * 60.0, 0.32)
	await _wait(1.2)
	_unpause(g)
	await _snap("b02_arriving")
	await _wait(1.6)
	_look_at(g, at + Vector3.UP * 12.0, 0.18)
	await _wait(0.6)
	_unpause(g)
	await _snap("b03_landed")
	for shot in [["b04_fight", 5.0], ["b05_fight", 4.0], ["b06_fight", 4.0]]:
		await _wait(shot[1])
		_look_at(g, b.global_position + Vector3.UP * 12.0, 0.16)
		await _wait(0.1)
		_unpause(g)
		await _snap(shot[0])
	# a free camera over the foliage, for a clear look at it in the fight
	var cam := Camera3D.new()
	cam.fov = 62.0
	cam.far = 3000.0
	g.add_child(cam)
	for shot in [["b06c_cine", 2.0, 0.0], ["b06d_cine", 3.0, 1.2], ["b06e_cine", 3.0, 2.6]]:
		await _wait(shot[1])
		var fwd: Vector3 = -b.global_basis.z
		var dir := fwd.rotated(Vector3.UP, shot[2])
		cam.global_position = b.global_position + dir * 52.0 + Vector3.UP * 16.0
		cam.look_at(b.global_position + Vector3.UP * 12.0, Vector3.UP)
		cam.current = true
		_unpause(g)
		await _snap(shot[0])
	cam.current = false
	g.rig.camera.current = true
	b.health = b.max_health * 0.52
	b.take_damage(DamageInfo.make(b.max_health * 0.03, DamageInfo.Kind.BULLET, p, &"carrot_lmg"))   # (enraged)
	await _wait(1.0)
	_look_at(g, b.global_position + Vector3.UP * 14.0, 0.18)
	_unpause(g)
	await _snap("b07_enraged")
	await _wait(5.0)
	_look_at(g, b.global_position + Vector3.UP * 12.0, 0.16)
	_unpause(g)
	await _snap("b08_enraged_fight")
	b.take_damage(DamageInfo.make(1e9, DamageInfo.Kind.BULLET, p, &"carrot_lmg"))
	await _wait(0.9)
	_look_at(g, b.global_position + Vector3.UP * 10.0, 0.12)
	await _snap("b09_falling")
	await _wait(5.0)
	await _snap("b10_beaten")


func _teams(g: Node) -> void:
	var mm = g.match_manager
	var p = mm.player
	await _wait(1.0)
	# a few of your team round you, a few of theirs out in front
	var fwd: Vector3 = -Basis(Vector3.UP, g.rig.yaw).z
	var side: Vector3 = fwd.cross(Vector3.UP)
	var mates := 0
	var foes := 0
	for c in mm.critters:
		if c == p or not c.alive:
			continue
		var cp: Vector3
		if c.team == p.team and mates < 4:
			cp = p.global_position + side * (mates - 1.5) * 4.0 + fwd * 3.0
			mates += 1
		elif c.team != p.team and foes < 4:
			cp = p.global_position + fwd * 45.0 + side * (foes - 1.5) * 8.0
			foes += 1
		else:
			continue
		cp.y = g.island.terrain.height_at(cp.x, cp.z) + 0.3
		c.place_at(cp, g.rig.yaw + (0.0 if c.team == p.team else PI))
		c.give_weapon(load("res://src/weapons/weapon_instance.gd").new(load("res://data/weapons/carrot_rifle.tres"), 1))
	g.rig.pitch = -0.08
	await _wait(1.5)
	_unpause(g)
	await _snap("t02_your_team")
	await _wait(5.0)
	_unpause(g)
	await _snap("t03_fight")
	Input.action_press(&"map")   # (the big map: the HUD shows it while it's held)
	await _wait(0.3)
	await _snap("t04_map")
	Input.action_release(&"map")
