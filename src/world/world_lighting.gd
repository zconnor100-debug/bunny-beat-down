class_name WorldLighting
extends Node3D
## Sun, HDRI sky and post-processing, scaled by the quality setting.
## (Only distance fog is used: height fog blanks the viewport on some
## NVIDIA/Vulkan drivers with Godot 4.6.)

const SKY_HDRI := "res://assets/sky/kloofendal_48d_partly_cloudy_puresky_2k.hdr"
const SKY_HDRI_4K := "res://assets/sky/kloofendal_48d_partly_cloudy_puresky_4k.hdr"

var sun: DirectionalLight3D
var env: Environment


## Indoors (the hamster tank, the bedroom): pale toys under a room's light
## washed out with the island's settings, so a warmer key light, a little less
## ambient fill, deeper contact shadows and a touch more colour and contrast.
func make_indoor() -> void:
	sun.light_color = Color(1.0, 0.9, 0.76)
	sun.light_energy *= 1.12
	env.ambient_light_energy *= 0.8
	env.ssao_intensity = 1.8
	env.ssao_radius = 1.6
	env.adjustment_saturation = 1.2
	env.adjustment_contrast = 1.1
	env.fog_density *= 0.6


func build(quality: int) -> void:
	var we := WorldEnvironment.new()
	env = Environment.new()
	var sky := Sky.new()
	var hdri_path := SKY_HDRI_4K if quality >= 3 and ResourceLoader.exists(SKY_HDRI_4K) else SKY_HDRI
	if ResourceLoader.exists(hdri_path):
		var pano := PanoramaSkyMaterial.new()
		pano.panorama = load(hdri_path)
		pano.energy_multiplier = 1.0
		sky.sky_material = pano
	else:
		var proc := ProceduralSkyMaterial.new()
		proc.sky_top_color = Color(0.32, 0.55, 0.85)
		proc.sky_horizon_color = Color(0.72, 0.82, 0.9)
		sky.sky_material = proc
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.9
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.0
	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.2
	env.fog_enabled = true
	env.fog_light_color = Color(0.7, 0.78, 0.86)
	env.fog_density = 0.0016
	env.fog_sun_scatter = 0.25
	env.fog_aerial_perspective = 0.5
	env.ssao_enabled = quality >= 1
	env.ssao_radius = 1.2
	env.ssao_intensity = 1.2
	env.ssao_sharpness = 0.8
	env.ssil_enabled = quality >= 3
	env.sdfgi_enabled = false
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.08
	env.adjustment_contrast = 1.03
	we.environment = env
	add_child(we)

	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-48.0, -35.0, 0.0)
	sun.light_color = Color(1.0, 0.95, 0.86)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	sun.shadow_blur = 1.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = [80.0, 140.0, 220.0, 320.0][clampi(quality, 0, 3)]
	sun.directional_shadow_split_1 = 0.05
	sun.directional_shadow_split_2 = 0.16
	sun.directional_shadow_split_3 = 0.42
	# (a wide sun disc means noisy PCSS penumbras without TAA to smooth them)
	sun.light_angular_distance = 0.25
	add_child(sun)
	var vp := get_viewport()
	if vp:
		vp.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_2X, Viewport.MSAA_4X][clampi(quality, 0, 3)]
		# SMAA on top of MSAA smooths what MSAA misses: specular sparkle on
		# bumpy ground, thin twigs and leaf-card edges (the "grainy" look)
		vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if quality == 0 else Viewport.SCREEN_SPACE_AA_SMAA
		vp.use_taa = false
		RenderingServer.directional_shadow_atlas_set_size([2048, 4096, 4096, 8192][clampi(quality, 0, 3)], true)
