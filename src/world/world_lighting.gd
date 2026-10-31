class_name WorldLighting
extends Node3D
## Sun, HDRI sky and post-processing, scaled by the quality setting (the
## tiers' effects, anti-aliasing and resolution: Graphics).
## (Only distance fog is used: height fog blanks the viewport on some
## NVIDIA/Vulkan drivers with Godot 4.6.)

const SKY_HDRI := "res://assets/sky/kloofendal_48d_partly_cloudy_puresky_2k.hdr"
const SKY_HDRI_4K := "res://assets/sky/kloofendal_48d_partly_cloudy_puresky_4k.hdr"

const NIGHT_SKY := preload("res://src/world/night_sky.gdshader")

var sun: DirectionalLight3D
var env: Environment
var night := false                   ## make_night()


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


## Night (the Kernel Hunt's Finale, StarfallMission): the stars out over the
## island (night_sky.gdshader), the moon for a sun, low and cold, a blue fill
## so you can still see who's who, the fog gone dark, and the glow turned up
## so whatever's lit (the Touched, the Kernels, the Briar Heart) shines.
func make_night() -> void:
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = NIGHT_SKY
	env.sky.sky_material = sky_mat
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.34, 0.4, 0.66)
	env.ambient_light_energy = 0.62
	env.tonemap_exposure = 1.12
	env.glow_intensity = 0.75
	env.glow_bloom = 0.07
	env.glow_hdr_threshold = 0.95
	env.fog_light_color = Color(0.06, 0.08, 0.15)
	env.fog_density = 0.0024
	env.fog_sun_scatter = 0.04
	env.fog_aerial_perspective = 0.2
	env.adjustment_saturation = 0.96
	env.volumetric_fog_albedo = Color(0.3, 0.34, 0.45)
	sun.rotation_degrees = Vector3(-34.0, 150.0, 0.0)
	sun.light_color = Color(0.64, 0.74, 1.0)
	sun.light_energy = 0.46
	sun.light_volumetric_fog_energy = 0.5
	night = true


## The night sky glowing low on the horizon the way of `dir` (from the camera
## to something big and bright out there: kept up to date as you move).
func glow_toward(dir: Vector3, amount: float) -> void:
	var m := env.sky.sky_material as ShaderMaterial if env and env.sky else null
	if m:
		m.set_shader_parameter(&"glow_dir", Vector3(dir.x, 0.0, dir.z).normalized() if Vector2(dir.x, dir.z).length() > 0.01 else Vector3.RIGHT)
		m.set_shader_parameter(&"glow_amount", amount)


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
	env.ssao_radius = 1.2
	env.ssao_intensity = 1.2
	env.ssao_sharpness = 0.8
	env.sdfgi_enabled = false
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.08
	env.adjustment_contrast = 1.03
	Graphics.apply_environment(env)   # (SSAO, SSIL, reflections, volumetric light by tier)
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
	sun.directional_shadow_max_distance = [80.0, 140.0, 220.0, 320.0, 420.0][clampi(quality, 0, 4)]
	sun.light_volumetric_fog_energy = 1.4   # (Epic's light shafts)
	sun.directional_shadow_split_1 = 0.05
	sun.directional_shadow_split_2 = 0.16
	sun.directional_shadow_split_3 = 0.42
	# (a wide sun disc means noisy PCSS penumbras without TAA to smooth them)
	sun.light_angular_distance = 0.25
	add_child(sun)
	Graphics.apply_global()
	Graphics.apply_viewport(get_viewport())
