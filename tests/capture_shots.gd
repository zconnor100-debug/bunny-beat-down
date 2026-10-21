extends SceneTree
## Renders screenshots for visual review and the README (needs a GPU window).
##   godot --path . -s tests/capture_shots.gd -- <out_dir> [menu|game|all]
## Drives the real game: menu → loading → balloon → landing → a staged fight.

var out_dir := "user://shots"
var which := "all"


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		out_dir = a[0]
	if a.size() > 1:
		which = a[1]
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


func _run() -> void:
	var settings: Node = root.get_node("Settings")
	settings.set_value(&"quality", 2, false)
	settings.set_value(&"opponents", 15, false)
	settings.set_value(&"seed", 1234, false)
	if which in ["menu", "all"]:
		change_scene_to_file("res://scenes/main.tscn")
		await _wait(4.0)
		await _snap("01_menu")
	if which in ["game", "all"]:
		change_scene_to_file("res://scenes/game.tscn")
		await _wait(1.5)
		await _snap("02_loading")
		var game: Node = null
		while game == null or game.match_manager == null:
			await process_frame
			game = current_scene
		await _wait(3.0)
		await _snap("03_balloon")
		var mm = game.match_manager
		mm.player_jump()
		await _wait(2.5)
		await _snap("04_freefall")
		var p = mm.player
		var t0 := Time.get_ticks_msec()
		while p.state != 3 and Time.get_ticks_msec() - t0 < 40000:   # GROUND
			p.want_jump = p.state == 1
			await process_frame
		await _wait(1.0)
		await _snap("05_landed")
		# stage a fight: give Bun a shotgun and bring the nearest bot close
		p.give_weapon(WeaponInstance.new(WeaponDB.get_weapon(&"carrot_shotgun"), 2))
		var rig = game.rig
		rig.yaw = p.rotation.y
		await _wait(1.0)
		await _snap("06_armed")
		var foe = null
		for c in mm.critters:
			if c != p and c.alive and c.state == 3:   # someone already on the ground
				foe = c
				break
		if foe:
			var fwd: Vector3 = -Basis(Vector3.UP, rig.yaw).z
			var spot: Vector3 = p.global_position + fwd * 6.0
			spot.y = game.island.terrain.height_at(spot.x, spot.z) + 0.2
			foe.place_at(spot, rig.yaw + PI)
			foe.process_mode = Node.PROCESS_MODE_DISABLED
			await _wait(0.5)
			foe.process_mode = Node.PROCESS_MODE_INHERIT
			rig.pitch = -0.08
			await _snap("07_face_off")
			for i in 2:
				p.want_fire = true
				await physics_frame
				await physics_frame
				p.want_fire = false
				await _wait(0.9)
			await _wait(0.15)
			await _snap("08_gore")
			await _wait(1.5)
			await _snap("09_aftermath")
		rig.toggle_first_person()
		p.give_weapon(WeaponInstance.new(WeaponDB.get_weapon(&"carrot_lmg"), 4))
		await _wait(1.0)
		await _snap("10_first_person")
		rig.toggle_first_person()
		rig.pitch = 0.25
		await _wait(0.5)
		await _snap("11_vista")
	if which in ["ui"]:
		change_scene_to_file("res://scenes/main.tscn")
		await _wait(3.0)
		current_scene._open_credits()
		await _wait(1.0)
		await _snap("13_credits")
		current_scene._close_overlay()
		current_scene._open_settings()
		await _wait(0.8)
		await _snap("14_settings")
		current_scene._close_overlay()
		current_scene._open_play()
		await _wait(0.8)
		await _snap("15_play")
	if which in ["endings"]:
		change_scene_to_file("res://scenes/game.tscn")
		var g: Node = null
		while g == null or g.match_manager == null:
			await process_frame
			g = current_scene
		await _wait(1.0)
		var m = g.match_manager
		m.player_jump()
		var pl = m.player
		var t1 := Time.get_ticks_msec()
		while pl.state != 3 and Time.get_ticks_msec() - t1 < 40000:
			pl.want_jump = pl.state == 1
			await process_frame
		await _wait(1.0)
		_report_surroundings(g, pl)
		# victory: everyone else gets lost in the Briar
		var dmg_cls = load("res://src/core/damage_info.gd")
		for c in m.critters:
			if c != pl and c.alive:
				var info = dmg_cls.make(999.0, 2, null, &"storm")
				c.state = 3
				c.take_damage(info)
		await _wait(2.5)
		await _snap("12_victory")
	quit()


func _report_surroundings(g: Node, pl: Node3D) -> void:
	var near := []
	for n in g.island.scatter.get_children():
		if n is Node3D and n.scene_file_path != "":
			near.append([pl.global_position.distance_to(n.global_position), n.scene_file_path.get_file(), n.global_position])
	near.sort_custom(func(a, b): return a[0] < b[0])
	print("player at ", pl.global_position, " ground ", g.island.terrain.height_at(pl.global_position.x, pl.global_position.z))
	for i in mini(8, near.size()):
		print("  near: %.1f m  %s at %s" % near[i])
