class_name Graphics
extends RefCounted
## The graphics and display options (Settings), applied: the quality tier's
## effects, anti-aliasing and upscaling on the 3D view, the window, V-Sync and
## frame cap, the field of view on wide screens, and which graphics API the
## next start uses.
##
## Quality tiers (Settings "quality"): Low, Medium, High, Ultra, Epic. A tier
## sets the defaults; "anti_aliasing" and "upscaling" can override its
## anti-aliasing. Most options apply at once; the quality tier's foliage
## density and sky apply from the next match, the graphics API from the next
## start.

enum Tier { LOW, MEDIUM, HIGH, ULTRA, EPIC }

const TIER_NAMES := ["Low", "Medium", "High", "Ultra", "Epic"]
const AA_NAMES := ["Auto (by quality)", "Off", "FXAA", "SMAA", "TAA", "MSAA 2× + SMAA", "MSAA 4× + SMAA", "MSAA 8× + SMAA",
	"FSR 2 (native AA)"]
## Auto's choice on each tier (AA_NAMES index): FXAA on Low, MSAA smoothed by
## SMAA above (SMAA catches what MSAA misses: specular sparkle, leaf edges).
const AUTO_AA := [2, 5, 5, 6, 6]
const UPSCALE_NAMES := ["Native", "FSR 2 Quality (67%)", "FSR 2 Balanced (59%)", "FSR 2 Performance (50%)", "Supersample (150%)"]
const UPSCALE_SCALE := [1.0, 0.67, 0.59, 0.5, 1.5]
const WINDOW_NAMES := ["Maximized window", "Fullscreen (borderless)", "Exclusive fullscreen", "Window"]
const VSYNC_NAMES := ["On", "Off", "Adaptive"]
const FPS_CAPS := [0, 30, 60, 120, 144, 165, 240]
const FPS_NAMES := ["Unlimited", "30", "60", "120", "144", "165", "240"]
const HUD_NAMES := ["Full screen width", "21:9 (centre)", "16:9 (centre)"]
## The shape of the whole picture: filling the screen, or kept to 16:9 or
## 21:9 with black bars (a wide screen shows standard, a standard one
## letterboxed ultrawide), whichever the player likes to look at.
const SHAPE_NAMES := ["Widescreen (fill the screen)", "Standard 16:9", "Ultrawide 21:9"]
const SHAPE_SIZE := [Vector2i(1920, 1080), Vector2i(1920, 1080), Vector2i(2520, 1080)]
const HUD_ASPECT := [0.0, 21.0 / 9.0, 16.0 / 9.0]
const WIDE_FOV_NAMES := ["Full width", "Limit stretching"]
const API_NAMES := ["Vulkan (default)", "Direct3D 12 (Windows)", "Compatibility (older GPUs)"]
## Super-ultrawide screens past this aspect see no further sideways when "Limit
## stretching" is on (the view at the edges stretches more the wider it gets).
const WIDE_FOV_ASPECT := 21.0 / 9.0
## Next start's graphics API, read by the engine before anything else
## (project.godot application/config/project_settings_override).
const OVERRIDE_PATH := "user://graphics.cfg"

## Settings keys that change what's on screen right away.
const LIVE_KEYS := [&"quality", &"anti_aliasing", &"upscaling", &"window_mode", &"vsync", &"max_fps", &"screen_shape"]


static func tier() -> int:
	return clampi(int(Settings.get_value(&"quality")), Tier.LOW, Tier.EPIC)


## Anti-aliasing and resolution of the 3D view in `vp`: the tier's own, or
## the player's choice.
static func apply_viewport(vp: Viewport) -> void:
	if vp == null:
		return
	var t := tier()
	var forward := RenderingServer.get_current_rendering_method() == "forward_plus"
	var aa := int(Settings.get_value(&"anti_aliasing"))
	if aa <= 0 or aa >= AA_NAMES.size():
		aa = AUTO_AA[t]
	var up := clampi(int(Settings.get_value(&"upscaling")), 0, UPSCALE_SCALE.size() - 1)
	var msaa := Viewport.MSAA_DISABLED
	var ssaa := Viewport.SCREEN_SPACE_AA_DISABLED
	var taa := false
	match aa:
		2:
			ssaa = Viewport.SCREEN_SPACE_AA_FXAA
		3:
			ssaa = Viewport.SCREEN_SPACE_AA_SMAA
		4:
			taa = true
		5, 6, 7:
			msaa = [Viewport.MSAA_2X, Viewport.MSAA_4X, Viewport.MSAA_8X][aa - 5]
			ssaa = Viewport.SCREEN_SPACE_AA_SMAA
	var mode := Viewport.SCALING_3D_MODE_BILINEAR
	var scale: float = UPSCALE_SCALE[up]
	if forward and (up in [1, 2, 3] or aa == 8):
		# FSR 2 does its own temporal anti-aliasing: nothing else on top
		mode = Viewport.SCALING_3D_MODE_FSR2
		msaa = Viewport.MSAA_DISABLED
		ssaa = Viewport.SCREEN_SPACE_AA_DISABLED
		taa = false
	elif not forward:
		# (the Compatibility renderer has MSAA and FXAA only, and no upscalers)
		taa = false
		if ssaa == Viewport.SCREEN_SPACE_AA_SMAA:
			ssaa = Viewport.SCREEN_SPACE_AA_FXAA
		scale = 1.0
	vp.msaa_3d = msaa
	vp.screen_space_aa = ssaa
	vp.use_taa = taa
	vp.scaling_3d_mode = mode
	vp.scaling_3d_scale = scale
	vp.fsr_sharpness = 0.25
	vp.use_debanding = true
	# how many pixels a mesh's simpler LOD may be off by before the finer one is drawn
	vp.mesh_lod_threshold = [4.0, 2.0, 1.0, 1.0, 0.5][t]


## Engine-wide quality: shadows, ambient occlusion, light bounce, reflections,
## glow and volumetric fog filtering.
static func apply_global() -> void:
	var t := tier()
	RenderingServer.directional_shadow_atlas_set_size([2048, 4096, 4096, 8192, 8192][t], true)
	RenderingServer.directional_soft_shadow_filter_set_quality(
		[RenderingServer.SHADOW_QUALITY_SOFT_LOW, RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM, RenderingServer.SHADOW_QUALITY_SOFT_HIGH,
		RenderingServer.SHADOW_QUALITY_SOFT_HIGH, RenderingServer.SHADOW_QUALITY_SOFT_ULTRA][t])
	RenderingServer.positional_soft_shadow_filter_set_quality(
		[RenderingServer.SHADOW_QUALITY_SOFT_LOW, RenderingServer.SHADOW_QUALITY_SOFT_LOW, RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM,
		RenderingServer.SHADOW_QUALITY_SOFT_HIGH, RenderingServer.SHADOW_QUALITY_SOFT_ULTRA][t])
	RenderingServer.environment_set_ssao_quality(
		[RenderingServer.ENV_SSAO_QUALITY_LOW, RenderingServer.ENV_SSAO_QUALITY_MEDIUM, RenderingServer.ENV_SSAO_QUALITY_HIGH,
		RenderingServer.ENV_SSAO_QUALITY_HIGH, RenderingServer.ENV_SSAO_QUALITY_ULTRA][t], t <= Tier.MEDIUM, 0.5, 2, 50.0, 300.0)
	RenderingServer.environment_set_ssil_quality(
		RenderingServer.ENV_SSIL_QUALITY_HIGH if t >= Tier.EPIC else RenderingServer.ENV_SSIL_QUALITY_MEDIUM, t < Tier.EPIC, 0.5, 4, 50.0, 300.0)
	RenderingServer.environment_set_ssr_roughness_quality(
		RenderingServer.ENV_SSR_ROUGHNESS_QUALITY_HIGH if t >= Tier.EPIC else RenderingServer.ENV_SSR_ROUGHNESS_QUALITY_MEDIUM)
	RenderingServer.environment_glow_set_use_bicubic_upscale(t >= Tier.HIGH)
	RenderingServer.environment_set_volumetric_fog_filter_active(t >= Tier.EPIC)
	RenderingServer.environment_set_volumetric_fog_volume_size(128 if t >= Tier.EPIC else 64, 64 if t >= Tier.EPIC else 48)


## The tier's effects on a world's Environment (WorldLighting builds it).
static func apply_environment(env: Environment) -> void:
	if env == null:
		return
	var t := tier()
	var forward := RenderingServer.get_current_rendering_method() == "forward_plus"
	env.ssao_enabled = t >= Tier.MEDIUM
	env.ssil_enabled = forward and t >= Tier.ULTRA
	# reflections in water, glass and glossy toys
	env.ssr_enabled = forward and t >= Tier.ULTRA
	env.ssr_max_steps = 96 if t >= Tier.EPIC else 56
	env.ssr_fade_in = 0.15
	env.ssr_fade_out = 2.0
	env.ssr_depth_tolerance = 0.3
	# light shafts through the trees and the fog (Epic): a thin volumetric fog
	# that takes the sun's colour, on top of the distance fog
	env.volumetric_fog_enabled = forward and t >= Tier.EPIC
	env.volumetric_fog_density = 0.004
	env.volumetric_fog_albedo = Color(0.92, 0.94, 1.0)
	env.volumetric_fog_anisotropy = 0.55
	env.volumetric_fog_length = 96.0
	env.volumetric_fog_detail_spread = 2.0
	env.volumetric_fog_ambient_inject = 0.15
	env.volumetric_fog_sky_affect = 0.0
	env.glow_intensity = 0.42 if t >= Tier.EPIC else 0.35


## The window, the screen shape, V-Sync and frame cap (not in automated runs:
## those place their own windows).
static func apply_display() -> void:
	if Settings.is_test_run() or DisplayServer.get_name() == "headless":
		return
	var root := (Engine.get_main_loop() as SceneTree).root if Engine.get_main_loop() is SceneTree else null
	if root:
		var shape := clampi(int(Settings.get_value(&"screen_shape")), 0, SHAPE_SIZE.size() - 1)
		root.content_scale_size = SHAPE_SIZE[shape]
		root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND if shape == 0 else Window.CONTENT_SCALE_ASPECT_KEEP
	var mode := int(Settings.get_value(&"window_mode"))
	var want: DisplayServer.WindowMode = [DisplayServer.WINDOW_MODE_MAXIMIZED, DisplayServer.WINDOW_MODE_FULLSCREEN,
		DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN, DisplayServer.WINDOW_MODE_WINDOWED][clampi(mode, 0, 3)]
	if DisplayServer.window_get_mode() != want:
		DisplayServer.window_set_mode(want)
	DisplayServer.window_set_vsync_mode([DisplayServer.VSYNC_ENABLED, DisplayServer.VSYNC_DISABLED,
		DisplayServer.VSYNC_ADAPTIVE][clampi(int(Settings.get_value(&"vsync")), 0, 2)])
	Engine.max_fps = FPS_CAPS[clampi(int(Settings.get_value(&"max_fps")), 0, FPS_CAPS.size() - 1)]


## Everything that applies at once, on the game's main view.
static func apply_all() -> void:
	var root := (Engine.get_main_loop() as SceneTree).root if Engine.get_main_loop() is SceneTree else null
	apply_global()
	apply_viewport(root)
	if root:
		for we in root.find_children("*", "WorldEnvironment", true, false):
			if we.get_viewport() == root:
				apply_environment((we as WorldEnvironment).environment)
	apply_display()


## The vertical field of view to use for `fov` (the setting, degrees) on a
## view `aspect` wide: unchanged up to 21:9; past that, with "Limit
## stretching", no wider across than a 21:9 screen sees.
static func fov_for(fov: float, aspect: float) -> float:
	if int(Settings.get_value(&"widescreen_fov")) != 1 or aspect <= WIDE_FOV_ASPECT:
		return fov
	var half := deg_to_rad(fov) * 0.5
	return rad_to_deg(2.0 * atan(tan(half) * WIDE_FOV_ASPECT / aspect))


## The graphics API for the next start ("graphics_api": Vulkan, Direct3D 12 or
## the Compatibility renderer), written where the engine reads it at start-up.
static func write_api_override(api: int) -> void:
	if Settings.is_test_run():
		return
	var cfg := ConfigFile.new()
	match api:
		1:
			cfg.set_value("rendering", "rendering_device/driver.windows", "d3d12")
		2:
			cfg.set_value("rendering", "renderer/rendering_method", "gl_compatibility")
			cfg.set_value("rendering", "renderer/rendering_method.mobile", "gl_compatibility")
	if api == 0:
		if FileAccess.file_exists(OVERRIDE_PATH):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(OVERRIDE_PATH))
		return
	cfg.save(OVERRIDE_PATH)


## What the game is running on, for the settings screen ("Vulkan · NVIDIA GeForce RTX 5080").
static func running_on() -> String:
	var api := RenderingServer.get_current_rendering_driver_name()
	var names := {"vulkan": "Vulkan", "d3d12": "Direct3D 12", "opengl3": "OpenGL (Compatibility)", "metal": "Metal"}
	return "%s · %s" % [names.get(api, api), RenderingServer.get_video_adapter_name()]
