extends TestCase
## A gamepad alone can drive the menus: A presses the focused button, B backs
## out, the D-pad moves between buttons, and the character picker answers the
## sticks. Events go through Input like a real pad's, not to the handlers.


func _pad(button: JoyButton) -> void:
	for down in [true, false]:
		var e := InputEventJoypadButton.new()
		e.button_index = button
		e.pressed = down
		Input.parse_input_event(e)
		await wait_frames(2)


func _stick(axis: JoyAxis, value: float) -> void:
	var e := InputEventJoypadMotion.new()
	e.axis = axis
	e.axis_value = value
	Input.parse_input_event(e)
	await wait_frames(1)


func _focus_text() -> String:
	var f := get_viewport().gui_get_focus_owner()
	return (f as Button).text if f is Button else str(f)


func test_menu_buttons_answer_a_and_b() -> void:
	check(InputMap.action_has_event(&"ui_accept", _button_event(JOY_BUTTON_A)), "A is a menu 'accept'")
	check(InputMap.action_has_event(&"ui_cancel", _button_event(JOY_BUTTON_B)), "B is a menu 'back'")
	for a in [&"ui_up", &"ui_down", &"ui_left", &"ui_right"]:
		check(InputMap.action_get_events(a).all(func(e): return not e is InputEventJoypadMotion), "%s ignores the left stick" % a)
	var menu: Node = load("res://scenes/main.tscn").instantiate()
	add_child(menu)
	await wait_frames(4)
	check(_focus_text() == "Play", "the title screen starts on Play (focus: %s)" % _focus_text())

	# A run (the Trail): open with A, B comes back to the same button
	await _pad(JOY_BUTTON_DPAD_DOWN)
	var run_button := _focus_text()
	check(run_button in ["A Run", "Continue the run"], "D-pad down moves to the run (focus: %s)" % run_button)
	await _pad(JOY_BUTTON_A)
	var trail := menu.find_children("*", "TrailPanel", true, false)
	var tf := get_viewport().gui_get_focus_owner()
	check(trail.size() == 1 and tf is Button and trail[0].is_ancestor_of(tf), "A opens the Trail, focus on it (focus: %s)" % tf)
	await _pad(JOY_BUTTON_B)
	await wait_frames(1)
	check(menu.find_children("*", "TrailPanel", true, false).is_empty() and _focus_text() == run_button, "B closes it (focus: %s)" % _focus_text())

	# The Burrow: open with A, B comes back to the same button
	await _pad(JOY_BUTTON_DPAD_DOWN)
	check(_focus_text() == "The Burrow", "D-pad down moves to The Burrow (focus: %s)" % _focus_text())
	await _pad(JOY_BUTTON_A)
	check(menu.find_children("*", "BurrowPanel", true, false).size() == 1, "A opens the Burrow")
	await _pad(JOY_BUTTON_B)
	await wait_frames(1)
	check(menu.find_children("*", "BurrowPanel", true, false).is_empty(), "B closes the Burrow")
	check(_focus_text() == "The Burrow", "and the pad is back on The Burrow (focus: %s)" % _focus_text())

	# The Rogues' Gallery: opens on its first card, B comes back to the same button
	await _pad(JOY_BUTTON_DPAD_DOWN)
	check(_focus_text() == "Rogues' Gallery", "D-pad down moves to the Rogues' Gallery (focus: %s)" % _focus_text())
	await _pad(JOY_BUTTON_A)
	var gallery := menu.find_children("*", "GalleryPanel", true, false)
	check(gallery.size() == 1, "A opens the Rogues' Gallery")
	var card := get_viewport().gui_get_focus_owner()
	check(gallery.size() == 1 and card is Button and gallery[0].is_ancestor_of(card) and card.text != "Back", "it starts on the first card (focus: %s)" % card)
	await _pad(JOY_BUTTON_B)
	await wait_frames(1)
	check(menu.find_children("*", "GalleryPanel", true, false).is_empty(), "B closes the Rogues' Gallery")
	check(_focus_text() == "Rogues' Gallery", "and the pad is back on the Rogues' Gallery (focus: %s)" % _focus_text())

	# The Warren Gazette: opens on Back, B comes back to the same button
	await _pad(JOY_BUTTON_DPAD_DOWN)
	check(_focus_text() == "Warren Gazette", "D-pad down moves to the Warren Gazette (focus: %s)" % _focus_text())
	await _pad(JOY_BUTTON_A)
	check(menu.find_children("*", "GazettePanel", true, false).size() == 1 and _focus_text() == "Back", "A opens it on Back (focus: %s)" % _focus_text())
	await _pad(JOY_BUTTON_B)
	await wait_frames(1)
	check(menu.find_children("*", "GazettePanel", true, false).is_empty() and _focus_text() == "Warren Gazette", "B closes it (focus: %s)" % _focus_text())

	# The Trophy Room: opens on Back, B comes back to the same button
	await _pad(JOY_BUTTON_DPAD_DOWN)
	check(_focus_text() == "Trophy Room", "D-pad down moves to the Trophy Room (focus: %s)" % _focus_text())
	await _pad(JOY_BUTTON_A)
	check(menu.find_children("*", "TrophyPanel", true, false).size() == 1 and _focus_text() == "Back", "A opens it on Back (focus: %s)" % _focus_text())
	await _pad(JOY_BUTTON_B)
	await wait_frames(1)
	check(menu.find_children("*", "TrophyPanel", true, false).is_empty() and _focus_text() == "Trophy Room", "B closes it (focus: %s)" % _focus_text())

	# Settings: open with A, starts on its first option, B comes back to the same button
	await _pad(JOY_BUTTON_DPAD_DOWN)
	check(_focus_text() == "Settings", "D-pad down moves to Settings (focus: %s)" % _focus_text())
	await _pad(JOY_BUTTON_A)
	var panel := menu.find_children("*", "SettingsPanel", true, false)
	check(panel.size() == 1, "A opens Settings")
	var f := get_viewport().gui_get_focus_owner()
	check(f is HSlider and panel.size() == 1 and panel[0].is_ancestor_of(f), "Settings starts on its first slider (focus: %s)" % f)
	await _pad(JOY_BUTTON_B)
	await wait_frames(1)
	check(menu.find_children("*", "SettingsPanel", true, false).is_empty(), "B closes Settings")
	check(_focus_text() == "Settings", "and the pad is back on the Settings button (focus: %s)" % _focus_text())

	# Play: the D-pad steps the opponent count, B goes back
	for i in 6:
		await _pad(JOY_BUTTON_DPAD_UP)
	await _pad(JOY_BUTTON_A)
	check(_focus_text() == "Drop in!", "A on Play opens the match setup on 'Drop in!' (focus: %s)" % _focus_text())
	var spins := menu.find_children("*", "SpinBox", true, false)
	if check(not spins.is_empty(), "match setup has the opponents box"):
		var opp := spins[0] as SpinBox
		var before := opp.value
		opp.get_line_edit().grab_focus()
		await _pad(JOY_BUTTON_DPAD_RIGHT)
		check_near(opp.value, before + 1.0, 0.01, "D-pad right adds an opponent")
		await _pad(JOY_BUTTON_DPAD_LEFT)
		check_near(opp.value, before, 0.01, "D-pad left takes one away")
		check(get_viewport().gui_get_focus_owner() == opp.get_line_edit(), "and focus stays on the box")
	await _pad(JOY_BUTTON_B)
	check(_focus_text() == "Play", "B backs out to Play (focus: %s)" % _focus_text())

	# Credits: opens on Back, B closes it
	for i in 7:
		await _pad(JOY_BUTTON_DPAD_DOWN)
	await _pad(JOY_BUTTON_A)
	check(menu.find_children("*", "CreditsPanel", true, false).size() == 1, "A on Credits opens them")
	check(_focus_text() == "Back", "Credits start on Back (focus: %s)" % _focus_text())
	await _pad(JOY_BUTTON_B)
	await wait_frames(1)
	check(menu.find_children("*", "CreditsPanel", true, false).is_empty(), "B closes Credits")
	check(_focus_text() == "Credits", "and the pad is back on Credits (focus: %s)" % _focus_text())

	# a mouse click on empty space drops focus; the next pad press picks the menu back up
	get_viewport().gui_release_focus()
	await _pad(JOY_BUTTON_DPAD_DOWN)
	check(_focus_text() == "Play", "a press with nothing focused lands on Play (focus: %s)" % _focus_text())


func test_character_picker_follows_the_pad() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var picker := CharacterSelect.new()
	layer.add_child(picker)
	await wait_frames(4)
	picker.ready_to_drop = true
	var drops := [0]
	picker.confirmed.connect(func(): drops[0] += 1)
	check(get_viewport().gui_get_focus_owner() == null, "the picker's buttons don't take focus")

	var start: int = picker._index
	await _pad(JOY_BUTTON_DPAD_RIGHT)
	check(picker._index == (start + 1) % picker._defs.size(), "D-pad right shows the next critter")
	await _pad(JOY_BUTTON_DPAD_LEFT)
	check(picker._index == start, "D-pad left goes back")

	# the left stick is too twitchy for picking: it does nothing here
	for v in [0.2, 0.5, 0.7, 0.95, 0.8, 1.0, 0.65, 0.9, 0.0, -1.0, 0.0]:
		await _stick(JOY_AXIS_LEFT_X, v)
	check(picker._index == start, "the left stick doesn't change the critter (index %d)" % picker._index)

	var skin: int = picker._skin_index
	await _pad(JOY_BUTTON_DPAD_UP)
	check(picker._skin_index == (skin + 1) % picker._defs[picker._index].skins().size(), "D-pad up shows the next skin")
	await _pad(JOY_BUTTON_DPAD_DOWN)
	check(picker._skin_index == skin, "D-pad down goes back a skin")

	# the right stick spins the preview
	await _stick(JOY_AXIS_RIGHT_X, 1.0)
	await wait_frames(20)
	await _stick(JOY_AXIS_RIGHT_X, 0.0)
	check(picker._spin > 0.2, "right stick spins the critter (spin %.2f)" % picker._spin)

	await _pad(JOY_BUTTON_A)
	await _pad(JOY_BUTTON_A)
	check(drops[0] == 1, "A drops in, once (%d)" % drops[0])
	layer.queue_free()


func _button_event(button: JoyButton) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.button_index = button
	return e


func test_the_gallery_card_reads_on_with_the_right_stick() -> void:
	var g := GalleryPanel.new()
	add_child(g)
	await wait_frames(2)
	var first := get_viewport().gui_get_focus_owner()
	# (a card longer than its box: a rogue with a lot of history)
	g._detail.text = "\n".join(range(60).map(func(i): return "A long memory, line %d." % i))
	await wait_frames(3)
	var bar: VScrollBar = g._card_scroll.get_v_scroll_bar()
	check(bar.max_value > bar.page, "the card is longer than its box (%.0f > %.0f)" % [bar.max_value, bar.page])
	check(g._more.modulate.a > 0.5, "and says there's more below")
	await _stick(JOY_AXIS_RIGHT_Y, 1.0)
	await wait_frames(20)
	await _stick(JOY_AXIS_RIGHT_Y, 0.0)
	check(g._card_scroll.scroll_vertical > 40, "the right stick reads on down the card (%d)" % g._card_scroll.scroll_vertical)
	check(get_viewport().gui_get_focus_owner() == first, "and leaves the list where it was")
	bar.value = bar.max_value
	await wait_frames(2)
	check(g._more.modulate.a < 0.5, "at the bottom, nothing more below")
	g._show("Sly")
	await wait_frames(2)
	check(g._card_scroll.scroll_vertical == 0, "the next card starts at its top")
	g.queue_free()
