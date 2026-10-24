extends Node

var game: Node


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var a := OS.get_cmdline_user_args()
	var settings: Node = get_node("/root/Settings")
	settings.set_value(&"map", a[0] if a.size() > 0 else "toybox", false)
	settings.set_value(&"opponents", 5, false)
	get_tree().change_scene_to_file("res://scenes/game.tscn")
	while game == null or game.get("hud") == null:
		await get_tree().process_frame
		game = get_tree().current_scene
	var mm = game.match_manager
	await _secs(1.0)
	mm.player_jump()
	while mm.player.state != Critter.State.GROUND:
		await get_tree().process_frame
	await _secs(1.0)
	print("landed; scene ", get_tree().current_scene.name)
	await _pad(JOY_BUTTON_START)
	print("after Start: paused=%s pause menu=%s focus=%s" % [get_tree().paused, game._pause != null, _focus_text()])
	for i in 8:
		if _focus_text().contains("Quit"):
			break
		await _pad(JOY_BUTTON_DPAD_DOWN)
		print("  D-pad down → focus %s" % _focus_text())
	await _pad(JOY_BUTTON_A)
	await _secs(1.0)
	var sc := get_tree().current_scene
	print("after A on Quit: scene=%s paused=%s" % [sc.name if sc else "null", get_tree().paused])
	get_tree().quit()


func _secs(s: float) -> void:
	var until := Time.get_ticks_msec() + int(s * 1000)
	while Time.get_ticks_msec() < until:
		await get_tree().process_frame


func _pad(button: JoyButton) -> void:
	for down in [true, false]:
		var e := InputEventJoypadButton.new()
		e.button_index = button
		e.pressed = down
		Input.parse_input_event(e)
		for i in 3:
			await get_tree().process_frame


func _focus_text() -> String:
	var f := get_viewport().gui_get_focus_owner()
	return (f as Button).text if f is Button else str(f)
