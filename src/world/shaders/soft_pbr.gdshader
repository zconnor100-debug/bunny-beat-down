// Building surfaces (planks, thatch, bark, roofs): the photo textures with
// their fine contrast turned down toward the texture's average colour and
// gentle bumps, so walls and roofs read as smooth, painterly colour at a
// distance instead of grainy speckle. UVs are in metres (see Building).
shader_type spatial;
render_mode blend_mix, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rough_tex : hint_roughness_g, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool use_albedo = true;
uniform bool use_normal = true;
uniform bool use_rough = true;
uniform vec4 tint : source_color = vec4(1.0);
uniform float metres_per_repeat = 2.0;
uniform float detail = 0.7;      // share of the texture's fine contrast kept
uniform float bumpiness = 0.5;
uniform float recolor = 0.0;     // 1: keep only the texture's light and shade, in the tint's colour (paint)

void fragment() {
	vec2 uv = UV / metres_per_repeat;
	vec3 alb = vec3(1.0);
	if (use_albedo) {
		vec3 avg = textureLod(albedo_tex, uv, 8.0).rgb;
		alb = mix(avg, texture(albedo_tex, uv).rgb, detail);
		float shade = dot(alb, vec3(0.3, 0.59, 0.11)) / max(dot(avg, vec3(0.3, 0.59, 0.11)), 0.05);
		alb = mix(alb, vec3(clamp(shade, 0.4, 1.6) * 0.8), recolor);
	}
	ALBEDO = alb * tint.rgb;
	ROUGHNESS = use_rough ? max(texture(rough_tex, uv).g, 0.55) : 0.8;
	SPECULAR = 0.3;
	if (use_normal) {
		NORMAL_MAP = texture(normal_tex, uv).rgb;
		NORMAL_MAP_DEPTH = bumpiness;
	}
}
