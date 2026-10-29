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
	# on a pad X does both: picks up / opens what's right in front of you,
	# reloads otherwise (A is only jump: you kept grabbing guns by accident)
	&"reload": [[KEY, KEY_R], [PAD_BUTTON, JOY_BUTTON_X]],
	&"interact": [[KEY, KEY_E], [PAD_BUTTON, JOY_BUTTON_X]],
	&"heal": [[KEY, KEY_H], [PAD_BUTTON, JOY_BUTTON_DPAD_DOWN]],
	# put on an Acorn Shield you carry: J (beside H), or tap D-pad → (held, it
	# swaps the camera's shoulder: PlayerController.SHOULDER_HOLD)
	&"shield": [[KEY, KEY_J], [PAD_BUTTON, JOY_BUTTON_DPAD_RIGHT]],
	# carrot grenade: hold to aim along its arc, let go to throw (LB on a pad)
	&"grenade": [[KEY, KEY_X], [MOUSE, MOUSE_BUTTON_MIDDLE], [PAD_BUTTON, JOY_BUTTON_LEFT_SHOULDER]],
	&"weapon_1": [[KEY, KEY_1]],
	&"weapon_2": [[KEY, KEY_2]],
	&"weapon_3": [[KEY, KEY_3]],
	# (Y on a pad steps round your three guns)
	&"weapon_next": [[MOUSE, MOUSE_BUTTON_WHEEL_DOWN], [PAD_BUTTON, JOY_BUTTON_Y]],
	&"weapon_prev": [[MOUSE, MOUSE_BUTTON_WHEEL_UP]],
	&"drop_weapon": [[KEY, KEY_G], [PAD_BUTTON, JOY_BUTTON_DPAD_LEFT]],
	# melee: F / R3 swing the club, even with a gun out (it's stowed for the
	# swing); fire with empty paws swings too, and so does B on a pad
	&"melee": [[KEY, KEY_F], [PAD_BUTTON, JOY_BUTTON_RIGHT_STICK]],
	# first person: V / Back, or both stick clicks (or back paddles) together
	&"toggle_camera": [[KEY, KEY_V], [PAD_BUTTON, JOY_BUTTON_BACK]],
	&"swap_shoulder": [[KEY, KEY_Q]],   # (on a pad: hold D-pad →)
	&"map": [[KEY, KEY_M], [PAD_BUTTON, JOY_BUTTON_DPAD_UP]],
	# call your arsenal in (Arsenal): B / RB opens the pick of your guns; pick
	# one, then hold B / RB to aim its flare along the arc and let go to throw
	&"call_in": [[KEY, KEY_B], [PAD_BUTTON, JOY_BUTTON_RIGHT_SHOULDER]],
	# rewind ten seconds (see TimeKeeper): T, or from the pause menu on a pad
	&"rewind": [[KEY, KEY_T]],
	&"pause": [[KEY, KEY_ESCAPE], [PAD_BUTTON, JOY_BUTTON_START]],
	&"screenshot": [[KEY, KEY_F12]],
}

## Godot's built-in menu actions have no gamepad button for "press the focused
## button" or "back", so A selects and B goes back (alongside Enter / Space and
## Escape, which stay).
const UI_PAD := {&"ui_accept": JOY_BUTTON_A, &"ui_cancel": JOY_BUTTON_B}
## Menus move with the D-pad only: Godot also steers them with the left stick,
## which skips past choices (and the stick is for walking anyway).
const UI_DIRECTIONS := [&"ui_up", &"ui_down", &"ui_left", &"ui_right"]

## Short on-screen names for pad inputs, so prompts can say "[Y]" not "[E]".
const PAD_BUTTON_NAMES := {
	JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y",
	JOY_BUTTON_LEFT_SHOULDER: "LB", JOY_BUTTON_RIGHT_SHOULDER: "RB",
	JOY_BUTTON_LEFT_STICK: "L3", JOY_BUTTON_RIGHT_STICK: "R3",
	JOY_BUTTON_BACK: "Back", JOY_BUTTON_START: "Start",
	JOY_BUTTON_DPAD_UP: "D-pad ↑", JOY_BUTTON_DPAD_DOWN: "D-pad ↓",
	JOY_BUTTON_DPAD_LEFT: "D-pad ←", JOY_BUTTON_DPAD_RIGHT: "D-pad →",
	JOY_BUTTON_PADDLE1: "P1", JOY_BUTTON_PADDLE2: "P2",
}
## Pressing both buttons of a pair within CHORD_SECONDS of each other is a
## chord: L3 + R3 (or the two back paddles) flips first / third person. On an
## 8BitDo Ultimate, map L4 → L3 and R4 → R3 on the pad and L4 + R4 does it.
const CHORDS := [[JOY_BUTTON_LEFT_STICK, JOY_BUTTON_RIGHT_STICK], [JOY_BUTTON_PADDLE1, JOY_BUTTON_PADDLE2]]
const CHORD_SECONDS := 0.15
const PAD_AXIS_NAMES := {JOY_AXIS_TRIGGER_LEFT: "LT", JOY_AXIS_TRIGGER_RIGHT: "RT"}

## True while the player is on a gamepad (their last button or stick push came
## from one); prompts then name pad buttons instead of keys.
var using_pad := false


func _enter_tree() -> void:
	for action in BINDINGS:
		if InputMap.has_action(action):
			InputMap.erase_action(action)
		InputMap.add_action(action, 0.25)
		for b in BINDINGS[action]:
			InputMap.action_add_event(action, _make_event(b))
	for action in UI_PAD:
		var e := _make_event([PAD_BUTTON, UI_PAD[action]])
		if not InputMap.action_has_event(action, e):
			InputMap.action_add_event(action, e)
	for action in UI_DIRECTIONS:
		for e in InputMap.action_get_events(action):
			if e is InputEventJoypadMotion:
				InputMap.action_erase_event(action, e)
	using_pad = not Input.get_connected_joypads().is_empty()


## The button to show in a prompt for `action` on the device in use:
## "SPACE" / "E" on keyboard, "A" / "Y" on a gamepad.
func prompt(action: StringName) -> String:
	for b in BINDINGS.get(action, []):
		if using_pad and b[0] == PAD_BUTTON:
			return PAD_BUTTON_NAMES.get(b[1], "?")
		if using_pad and b[0] == PAD_AXIS and PAD_AXIS_NAMES.has(b[1]):
			return PAD_AXIS_NAMES[b[1]]
		if not using_pad and b[0] == KEY:
			return OS.get_keycode_string(b[1]).to_upper()
	return String(action).capitalize()


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


func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton or (event is InputEventJoypadMotion and absf(event.axis_value) > 0.5):
		using_pad = true
	elif event is InputEventKey or event is InputEventMouseButton:
		using_pad = false


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"screenshot"):
		var img := get_viewport().get_texture().get_image()
		var dir := "user://screenshots"
		DirAccess.make_dir_recursive_absolute(dir)
		img.save_png("%s/bbd_%s.png" % [dir, Time.get_datetime_string_from_system().replace(":", "-")])
