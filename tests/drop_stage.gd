extends Node
## Stage for tests/capture_drop.gd.

var out_dir := "/tmp/bbd_drop"
var map := "cage"
var opponents := 23
var game: Node


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# pads drive every Godot window on the machine: this one ignores them
	for action in InputMap.get_actions():
		for e in InputMap.action_get_events(action):
			if e is InputEventJoypadButton or e is InputEventJoypadMotion:
				InputMap.action_erase_event(action, e)
	var settings: Node = get_node("/root/Settings")
	settings.set_value(&"seed", 777, false)
	settings.set_value(&"map", map, false)
	settings.set_value(&"opponents", opponents, false)
	if opponents > 23:   # (the owner's settings: a full lobby, top quality, a wide lens)
		settings.set_value(&"quality", 3, false)
		settings.set_value(&"fov", 100.0, false)
	game = load("res://scenes/game.tscn").instantiate()
	get_tree().root.add_child.call_deferred(game)
	while game.get("match_manager") == null or game.match_manager.dropship == null:
		await get_tree().process_frame
	var mm = game.match_manager
	await _wait(2.5)
	await _snap("70_ride_start")
	await _wait(5.0)
	await _snap("71_ride_later")
	if opponents > 23:
		# from the plane, everyone else on the way down (wide lens, far away)
		for i in 3:
			await _wait(3.0)
			game.rig.pitch = -0.75
			game.rig.yaw += 0.9
			await _wait(0.4)
			await _snap("71_falling_bots_%d" % i)
	mm.player_jump()
	await _wait(1.6)
	await _snap("72_jumped")
	await _wait(1.8)
	await _snap("73_falling")
	if opponents > 23:
		# look round at everyone else coming down, then up from the ground
		for i in 4:
			game.rig.yaw += PI * 0.5
			game.rig.pitch = -0.6
			await _wait(1.5)
			await _snap("74_around_%d" % i)
		await _wait(12.0)
		game.rig.pitch = 0.5
		await _wait(0.5)
		await _snap("75_sky_from_ground")
	var p = mm.player
	var near := 0
	for c in mm.critters:
		if c != p and c.state in [1, 2] and c.global_position.distance_to(p.global_position) < 80.0:
			near += 1
	print("DROP %s: %d critters skydiving within 80 m of you" % [map, near])
	get_tree().quit()


func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _snap(name_: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out_dir, name_])
