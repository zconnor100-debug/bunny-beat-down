class_name SettingsPanel
extends PanelContainer
## Every player-facing option, bound straight to the Settings autoload.

signal closed
signal test_graphics   ## "Test graphics" pressed (offered when allow_test: the main menu opens GraphicsTest)

var allow_test := false

var _grid: GridContainer


func _ready() -> void:
	theme = UITheme.theme()
	custom_minimum_size = Vector2(900, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	add_child(v)
	var title := UITheme.label("Settings", 52, UITheme.CARROT_LIGHT, true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	# (scrolls on a short screen; the focused option is kept in view for pads)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	scroll.custom_minimum_size = Vector2(0, clampf(get_viewport().get_visible_rect().size.y - 330.0, 280.0, 680.0))
	v.add_child(scroll)
	_grid = GridContainer.new()
	_grid.columns = 2
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 30)
	_grid.add_theme_constant_override("v_separation", 12)
	scroll.add_child(_grid)
	_section("Controls")
	_slider("Mouse sensitivity", &"mouse_sensitivity", 0.03, 0.4, 0.01)
	_slider("Aim-down-sights sensitivity", &"aim_sensitivity_scale", 0.3, 1.0, 0.05)
	_check("Invert look", &"invert_y")
	_slider("Field of view", &"fov", 60.0, 110.0, 1.0)
	_option("Camera", &"camera_mode", ["Third person", "First person"])
	_section("Graphics")
	_option("Graphics quality", &"quality", Graphics.TIER_NAMES)
	_option("Anti-aliasing", &"anti_aliasing", Graphics.AA_NAMES)
	_option("Resolution scaling", &"upscaling", Graphics.UPSCALE_NAMES)
	_option("Graphics API (restart)", &"graphics_api", Graphics.API_NAMES)
	if allow_test:
		_row_label("See how it all looks")
		var test := UITheme.button("Test graphics", func(): test_graphics.emit())
		test.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		_grid.add_child(test)
	_section("Display")
	_option("Window", &"window_mode", Graphics.WINDOW_NAMES)
	_option("Screen shape", &"screen_shape", Graphics.SHAPE_NAMES)
	_option("HUD width", &"hud_width", Graphics.HUD_NAMES)
	_option("Super-ultrawide view", &"widescreen_fov", Graphics.WIDE_FOV_NAMES)
	_option("V-Sync", &"vsync", Graphics.VSYNC_NAMES)
	_option("Frame rate cap", &"max_fps", Graphics.FPS_NAMES)
	_check("Show FPS", &"show_fps")
	_section("Game")
	_option("Gore", &"gore", ["Full (blood & limbs)", "Plushie (stuffing)", "Off"])
	_check("Boss arrival cinematics", &"boss_intro")
	_check("Check for updates", &"check_updates")
	_section("Audio")
	_slider("Master volume", &"master_volume", 0.0, 1.0, 0.05)
	_slider("Music volume", &"music_volume", 0.0, 1.0, 0.05)
	_slider("Effects volume", &"sfx_volume", 0.0, 1.0, 0.05)
	_slider("Voice volume", &"voice_volume", 0.0, 1.0, 0.05)
	var back := UITheme.button("Back", func(): closed.emit())
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(back)
	var note := UITheme.label("Graphics options apply at once; the quality's foliage and sky from the next match, the graphics API "
		+ "after a restart.\nRunning on %s" % Graphics.running_on(), 16, Color(UITheme.CREAM, 0.7))
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size = Vector2(860, 0)
	v.add_child(note)
	# pads and keyboards start on the first option (D-pad ← → changes it)
	UITheme.first_focusable(_grid).grab_focus.call_deferred()


## A heading across both columns.
func _section(text: String) -> void:
	var l := UITheme.label(text.to_upper(), 20, UITheme.CARROT_LIGHT, true)
	_grid.add_child(l)
	_grid.add_child(Control.new())


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		closed.emit()


func _row_label(text: String) -> void:
	var l := UITheme.label(text, 22)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_child(l)


func _slider(text: String, key: StringName, lo: float, hi: float, step: float) -> void:
	_row_label(text)
	var h := HBoxContainer.new()
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = Settings.get_value(key)
	s.custom_minimum_size = Vector2(300, 32)
	var val := UITheme.label(_fmt(s.value, step), 20)
	val.custom_minimum_size = Vector2(70, 0)
	s.value_changed.connect(func(x):
		Settings.set_value(key, x)
		val.text = _fmt(x, step))
	h.add_child(s)
	h.add_child(val)
	_grid.add_child(h)


func _fmt(x: float, step: float) -> String:
	return "%d" % roundi(x) if step >= 1.0 else ("%d%%" % roundi(x * 100.0) if step >= 0.05 else "%.2f" % x)


func _check(text: String, key: StringName) -> void:
	_row_label(text)
	var c := CheckButton.new()
	c.button_pressed = Settings.get_value(key)
	c.toggled.connect(func(on): Settings.set_value(key, on))
	_grid.add_child(c)


func _option(text: String, key: StringName, items: Array) -> void:
	_row_label(text)
	var o := OptionButton.new()
	for i in items.size():
		o.add_item(items[i], i)
	o.selected = int(Settings.get_value(key))
	o.item_selected.connect(func(i): Settings.set_value(key, i))
	o.custom_minimum_size = Vector2(300, 0)
	_grid.add_child(o)
