extends Node
## Registers every input action in code (keyboard/mouse + gamepad) so the
## bindings live in one readable table instead of serialized InputEvents in
## project.godot.

const KEY := 0
const MOUSE := 1
const PAD_BUTTON := 2
const PAD_AXIS := 3

# action: [[kind, code(, axis_sign)], ...]
const BINDINGS := {
	&"move_forward": [[KEY, KEY_W], [PAD_AXIS, JOY_AXIS_LEFT_Y, -1.0]],
	&"move_back": [[KEY, KEY_S], [PAD_AXIS, JOY_AXIS_LEFT_Y, 1.0]],
	&"move_left": [[KEY, KEY_A], [PAD_AXIS, JOY_AXIS_LEFT_X, -1.0]],
	&"move_right": [[KEY, KEY_D], [PAD_AXIS, JOY_AXIS_LEFT_X, 1.0]],
	&"look_up": [[PAD_AXIS, JOY_AXIS_RIGHT_Y, -1.0]],
	&"look_down": [[PAD_AXIS, JOY_AXIS_RIGHT_Y, 1.0]],
	&"look_left": [[PAD_AXIS, JOY_AXIS_RIGHT_X, -1.0]],
	&"look_right": [[PAD_AXIS, JOY_AXIS_RIGHT_X, 1.0]],
	&"jump": [[KEY, KEY_SPACE], [PAD_BUTTON, JOY_BUTTON_A]],
	&"sprint": [[KEY, KEY_SHIFT], [PAD_BUTTON, JOY_BUTTON_LEFT_STICK]],
	&"crouch": [[KEY, KEY_CTRL], [KEY, KEY_C], [PAD_BUTTON, JOY_BUTTON_B]],
	&"fire": [[MOUSE, MOUSE_BUTTON_LEFT], [PAD_AXIS, JOY_AXIS_TRIGGER_RIGHT, 1.0]],
	&"aim": [[MOUSE, MOUSE_BUTTON_RIGHT], [PAD_AXIS, JOY_AXIS_TRIGGER_LEFT, 1.0]],
	&"reload": [[KEY, KEY_R], [PAD_BUTTON, JOY_BUTTON_X]],
	&"interact": [[KEY, KEY_E], [PAD_BUTTON, JOY_BUTTON_Y]],
	&"heal": [[KEY, KEY_H], [PAD_BUTTON, JOY_BUTTON_DPAD_DOWN]],
	&"weapon_1": [[KEY, KEY_1]],
	&"weapon_2": [[KEY, KEY_2]],
	&"weapon_3": [[KEY, KEY_3]],
	&"weapon_next": [[MOUSE, MOUSE_BUTTON_WHEEL_DOWN], [PAD_BUTTON, JOY_BUTTON_RIGHT_SHOULDER]],
	&"weapon_prev": [[MOUSE, MOUSE_BUTTON_WHEEL_UP], [PAD_BUTTON, JOY_BUTTON_LEFT_SHOULDER]],
	&"drop_weapon": [[KEY, KEY_G]],
	&"toggle_camera": [[KEY, KEY_V], [PAD_BUTTON, JOY_BUTTON_BACK]],
	&"swap_shoulder": [[KEY, KEY_Q], [PAD_BUTTON, JOY_BUTTON_RIGHT_STICK]],
	&"map": [[KEY, KEY_M], [PAD_BUTTON, JOY_BUTTON_DPAD_UP]],
	&"pause": [[KEY, KEY_ESCAPE], [PAD_BUTTON, JOY_BUTTON_START]],
	&"screenshot": [[KEY, KEY_F12]],
}


func _enter_tree() -> void:
	for action in BINDINGS:
		if InputMap.has_action(action):
			InputMap.erase_action(action)
		InputMap.add_action(action, 0.25)
		for b in BINDINGS[action]:
			InputMap.action_add_event(action, _make_event(b))


func _make_event(b: Array) -> InputEvent:
	match b[0]:
		KEY:
			var e := InputEventKey.new()
			e.physical_keycode = b[1]
			return e
		MOUSE:
			var e := InputEventMouseButton.new()
			e.button_index = b[1]
			return e
		PAD_BUTTON:
			var e := InputEventJoypadButton.new()
			e.button_index = b[1]
			return e
		_:
			var e := InputEventJoypadMotion.new()
			e.axis = b[1]
			e.axis_value = b[2]
			return e


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"screenshot"):
		var img := get_viewport().get_texture().get_image()
		var dir := "user://screenshots"
		DirAccess.make_dir_recursive_absolute(dir)
		img.save_png("%s/bbd_%s.png" % [dir, Time.get_datetime_string_from_system().replace(":", "-")])
