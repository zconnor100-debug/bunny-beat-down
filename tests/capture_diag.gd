extends SceneTree
## Diagnostic captures: FPS sampling and close-ups of a named env model.
##   godot --path . -s tests/capture_diag.gd -- <out_dir> <model_id>

var out_dir := "user://diag"
var model_id := "stump_a"


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		out_dir = a[0]
	if a.size() > 1:
		model_id = a[1]
	DirAccess.make_dir_recursive_absolute(out_dir)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	_run.call_deferred()


func _snap(name: String) -> void:
	await process_frame
	await process_frame
	root.get_viewport().get_texture().get_image().save_png(out_dir.path_join(name + ".png"))
	print("shot ", name)


func _wait(sec: float) -> void:
	var t := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t < sec * 1000.0:
		await process_frame


func _run() -> void:
	var settings: Node = root.get_node("Settings")
	settings.set_value(&"quality", 2, false)
	settings.set_value(&"opponents", 23, false)
	settings.set_value(&"seed", 1234, false)
	change_scene_to_file("res://scenes/game.tscn")
	var game: Node = null
	while game == null or game.match_manager == null:
		await process_frame
		game = current_scene
	await _wait(2.0)
	print("fps in balloon: ", Engine.get_frames_per_second())
	var mm = game.match_manager
	var p = mm.player
	mm.player_jump()
	var t0 := Time.get_ticks_msec()
	while p.state != 3 and Time.get_ticks_msec() - t0 < 40000:
		p.want_jump = p.state == 1
		await process_frame
	await _wait(2.0)
	print("fps on ground: ", Engine.get_frames_per_second())
	# find the model and stand next to it
	var target: Node3D = null
	for n in game.island.scatter.get_children():
		if n is Node3D and String(n.scene_file_path).contains(model_id):
			target = n
			break
	if target == null:
		print("model not found: ", model_id)
		quit()
		return
	var tp: Vector3 = target.global_position
	var spot := tp + Vector3(4.5, 0, 4.5)
	spot.y = game.island.terrain.height_at(spot.x, spot.z) + 0.3
	p.place_at(spot, 0.0)
	var rig = game.rig
	var to := tp - spot
	rig.yaw = atan2(-to.x, -to.z)
	rig.pitch = -0.1
	await _wait(1.5)
	var near := {}
	for n in game.island.scatter.get_children():
		if n is Node3D and n.scene_file_path != "" and spot.distance_to(n.global_position) < 25.0:
			var k: String = n.scene_file_path.get_file()
			near[k] = near.get(k, 0) + 1
	print("within 25 m: ", near)
	await _snap("diag_%s_lod_on" % model_id)
	ProjectSettings.set_setting("rendering/mesh_lod/lod_change/threshold_pixels", 0.0)
	root.get_viewport().mesh_lod_threshold = 0.0
	await _wait(0.5)
	await _snap("diag_%s_lod_off" % model_id)
	quit()
