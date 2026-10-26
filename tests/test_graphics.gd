extends TestCase
## Graphics options (Graphics, Settings): each anti-aliasing and upscaling
## choice sets the view up as it says, Auto follows the quality tier, a
## super-ultrawide screen can be kept from stretching, and the settings screen
## offers all of it.

const KEYS := [&"quality", &"anti_aliasing", &"upscaling", &"widescreen_fov", &"hud_width", &"screen_shape"]
var _was := {}


func before_each() -> void:
	for k in KEYS:
		_was[k] = Settings.get_value(k)


func after_each() -> void:
	for k in KEYS:
		Settings.set_value(k, _was[k], false)


func test_anti_aliasing_and_upscaling_set_up_the_view() -> void:
	var vp := SubViewport.new()
	add_child(vp)
	Settings.set_value(&"upscaling", 0, false)
	for t in Graphics.TIER_NAMES.size():
		Settings.set_value(&"quality", t, false)
		Settings.set_value(&"anti_aliasing", 0, false)
		Graphics.apply_viewport(vp)
		var want := int(Graphics.AUTO_AA[t])
		check((vp.screen_space_aa == Viewport.SCREEN_SPACE_AA_FXAA) == (want == 2), "%s: Auto picks the tier's AA (FXAA only on Low)" % Graphics.TIER_NAMES[t])
		check(vp.scaling_3d_scale == 1.0 and vp.scaling_3d_mode == Viewport.SCALING_3D_MODE_BILINEAR, "%s: native resolution" % Graphics.TIER_NAMES[t])
	Settings.set_value(&"quality", Graphics.Tier.EPIC, false)
	Settings.set_value(&"anti_aliasing", 7, false)
	Graphics.apply_viewport(vp)
	check(vp.msaa_3d == Viewport.MSAA_8X and vp.screen_space_aa == Viewport.SCREEN_SPACE_AA_SMAA, "MSAA 8x + SMAA")
	Settings.set_value(&"anti_aliasing", 4, false)
	Graphics.apply_viewport(vp)
	check(vp.use_taa and vp.msaa_3d == Viewport.MSAA_DISABLED, "TAA")
	if RenderingServer.get_current_rendering_method() == "forward_plus":
		Settings.set_value(&"upscaling", 2, false)
		Graphics.apply_viewport(vp)
		check(vp.scaling_3d_mode == Viewport.SCALING_3D_MODE_FSR2 and is_equal_approx(vp.scaling_3d_scale, 0.59), "FSR 2 Balanced: 59%")
		check(not vp.use_taa and vp.msaa_3d == Viewport.MSAA_DISABLED, "and nothing else on top of FSR 2")
	Settings.set_value(&"upscaling", 4, false)
	Settings.set_value(&"anti_aliasing", 3, false)
	Graphics.apply_viewport(vp)
	check(vp.scaling_3d_scale == 1.5 and vp.screen_space_aa == Viewport.SCREEN_SPACE_AA_SMAA, "supersampling at 150%, with SMAA")
	check(vp.mesh_lod_threshold < 1.0, "Epic draws finer LODs")
	vp.queue_free()


func test_super_ultrawide_screens_can_be_kept_from_stretching() -> void:
	Settings.set_value(&"widescreen_fov", 1, false)
	check(Graphics.fov_for(80.0, 16.0 / 9.0) == 80.0 and Graphics.fov_for(80.0, 21.0 / 9.0) == 80.0, "16:9 and 21:9: the field of view as set")
	var v32 := Graphics.fov_for(80.0, 32.0 / 9.0)
	var across := 2.0 * atan(tan(deg_to_rad(v32) * 0.5) * 32.0 / 9.0)
	var across_21 := 2.0 * atan(tan(deg_to_rad(80.0) * 0.5) * 21.0 / 9.0)
	check(v32 < 80.0 and absf(across - across_21) < 0.001, "32:9 sees no wider across than 21:9 (%.1f°)" % rad_to_deg(across))
	Settings.set_value(&"widescreen_fov", 0, false)
	check(Graphics.fov_for(80.0, 32.0 / 9.0) == 80.0, "or the full width, if you like")


func test_the_settings_screen_offers_every_graphics_option() -> void:
	var panel := SettingsPanel.new()
	add_child(panel)
	await wait_frames(2)
	var labels := panel.find_children("*", "Label", true, false).map(func(l): return (l as Label).text)
	for want in ["Graphics quality", "Anti-aliasing", "Resolution scaling", "Graphics API (restart)", "Window", "Screen shape",
			"HUD width", "Super-ultrawide view", "V-Sync", "Frame rate cap"]:
		check(labels.has(want), "the settings offer %s" % want)
	var quality: OptionButton = null
	for o in panel.find_children("*", "OptionButton", true, false):
		if (o as OptionButton).item_count == Graphics.TIER_NAMES.size() and (o as OptionButton).get_item_text(4) == "Epic":
			quality = o
	check(quality != null, "quality goes up to Epic")
	check(labels.any(func(t): return String(t).contains("Running on")), "and says what the game is running on")
	panel.queue_free()


func test_the_graphics_check_draws_a_match_like_scene() -> void:
	var was_api: int = Settings.get_value(&"graphics_api")
	var test := GraphicsTest.new()
	add_child(test)
	await wait_frames(3)
	var crits := test.find_children("*", "Critter", true, false)
	check(crits.size() == 3, "three critters: idling, walking, gliding (%d)" % crits.size())
	check(crits.any(func(c): return (c as Critter).visual._glider != null), "one of them under its glider")
	check(test._view.own_world_3d and test._view.get_camera_3d() != null, "in a world of its own, with its own camera")
	check(not test.find_children("*", "WorldEnvironment", true, false).is_empty(), "lit like a match (WorldLighting)")
	var labels := test.find_children("*", "Label", true, false).map(func(l): return (l as Label).text)
	check(labels.any(func(t): return String(t).begins_with("Running on")), "says what it's running on")
	var q: int = Settings.get_value(&"quality")
	test._cycle(&"quality", Graphics.TIER_NAMES.size())
	check(int(Settings.get_value(&"quality")) == (q + 1) % Graphics.TIER_NAMES.size(), "the quality button flips through the tiers")
	Settings.set_value(&"quality", q, false)
	test.restart_into(2)
	check(int(Settings.get_value(&"graphics_api")) == 2 and test.is_inside_tree(), "picking an API notes it (a test run doesn't restart)")
	Settings.set_value(&"graphics_api", was_api, false)
	test.queue_free()
