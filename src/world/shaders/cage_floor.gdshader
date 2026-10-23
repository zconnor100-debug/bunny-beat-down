// The hamster tank's floor: pale wood-shaving bedding with tufts of white
// paper bedding and darker trodden trails, aquarium gravel under the lagoon,
// snow in the winter corner and bathing sand. Splat control map (R paper,
// G trail, B steep, A sand) and biome map (R lagoon, G winter, B bedding),
// soft photo textures toned toward their average colour like the island's.
shader_type spatial;
render_mode blend_mix, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D control_map : filter_linear, repeat_disable;
uniform sampler2D biome_map : filter_linear, repeat_disable;
uniform sampler2D macro_noise : filter_linear_mipmap, repeat_enable;
uniform float terrain_size = 1536.0;
uniform float lagoon_level = 3.2;

uniform sampler2D bedding_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D bedding_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D snow_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D snow_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D pebble_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D pebble_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D sand_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D sand_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;

uniform float bedding_tile = 9.0;
uniform float snow_tile = 14.0;
uniform float pebble_tile = 5.0;
uniform float sand_tile = 6.0;
uniform vec3 bedding_color : source_color = vec3(0.93, 0.8, 0.58);
uniform vec3 paper_color : source_color = vec3(0.97, 0.95, 0.9);
uniform float detail = 0.85;
uniform float bumpiness = 0.85;
uniform float fine_tile = 2.3;      // a second, finer layer of shavings up close

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

vec3 soft(sampler2D tex, vec2 uv) {
	return mix(textureLod(tex, uv, 9.0).rgb, texture(tex, uv).rgb, detail);
}

float luma(vec3 c) {
	return dot(c, vec3(0.3, 0.59, 0.11));
}

void fragment() {
	vec2 cuv = (world_pos.xz + terrain_size * 0.5) / terrain_size;
	vec4 ctl = texture(control_map, cuv);
	vec3 bio = texture(biome_map, cuv).rgb;
	vec2 p = world_pos.xz;
	float macro = texture(macro_noise, p / 160.0).r;
	float macro2 = texture(macro_noise, p / 33.0).r;

	// bedding: the shavings texture's light and shade, recoloured pale and warm,
	// with a finer, turned copy layered on top near the camera (single flakes
	// of shaving at a critter's feet, not a smooth beige carpet)
	float avg = max(luma(textureLod(bedding_albedo, p / bedding_tile, 9.0).rgb), 0.05);
	vec3 shav = soft(bedding_albedo, p / bedding_tile);
	float l = luma(shav) / avg;
	vec2 q = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8)) * p;
	float near = 1.0 - smoothstep(20.0, 90.0, length(world_pos - CAMERA_POSITION_WORLD));
	float lf = luma(texture(bedding_albedo, q / fine_tile).rgb) / avg;
	float shade = mix(l, l * mix(1.0, lf, 0.75), near);
	vec3 alb = bedding_color * mix(0.64, 1.26, clamp(shade * 0.5, 0.0, 1.0));
	// honey-coloured and paler shavings in patches
	alb *= mix(vec3(1.05, 0.97, 0.86), vec3(0.95, 0.97, 1.02), smoothstep(0.3, 0.7, texture(macro_noise, p / 13.0).r));
	vec3 nrm = mix(texture(bedding_normal, p / bedding_tile).rgb, texture(bedding_normal, q / fine_tile).rgb, 0.55 * near);
	float rgh = 0.9;
	// tufts of white paper bedding
	alb = mix(alb, paper_color * mix(0.9, 1.05, macro2), ctl.r);
	// trodden trails: packed, darker shavings
	alb = mix(alb, alb * vec3(0.72, 0.66, 0.6), ctl.g * 0.85);
	alb *= mix(1.0, 0.82, ctl.b);
	// bathing sand
	alb = mix(alb, soft(sand_albedo, p / sand_tile) * vec3(1.08, 1.04, 0.95), ctl.a);
	nrm = mix(nrm, texture(sand_normal, p / sand_tile).rgb, ctl.a);

	// lagoon: aquarium gravel in pastel tints, dark and glossy under the water
	float w_lag = smoothstep(0.2, 0.55, bio.r);
	vec3 peb = soft(pebble_albedo, p / pebble_tile);
	vec3 tint = mix(vec3(0.75, 0.9, 1.15), vec3(1.15, 0.85, 0.95), smoothstep(0.3, 0.7, macro2));
	peb *= mix(vec3(1.0), tint, 0.5) * 1.15;
	alb = mix(alb, peb, w_lag);
	nrm = mix(nrm, texture(pebble_normal, p / pebble_tile).rgb, w_lag);
	float wet = w_lag * smoothstep(lagoon_level + 0.25, lagoon_level - 0.15, world_pos.y);
	alb *= mix(1.0, 0.6, wet);
	rgh = mix(rgh, 0.3, wet);

	// winter: snow, with a ragged edge where it thins out over the bedding
	float w_snow = smoothstep(0.35, 0.65, bio.g + (macro2 - 0.5) * 0.35);
	vec3 sn = soft(snow_albedo, p / snow_tile);
	sn = vec3(0.93, 0.96, 1.0) * clamp(luma(sn) / max(luma(textureLod(snow_albedo, p / snow_tile, 9.0).rgb), 0.05), 0.85, 1.12);
	alb = mix(alb, sn, w_snow);
	nrm = mix(nrm, texture(snow_normal, p / snow_tile).rgb, w_snow);
	rgh = mix(rgh, 0.65, w_snow);

	alb *= mix(0.9, 1.06, macro);
	ALBEDO = alb;
	NORMAL_MAP = nrm;
	NORMAL_MAP_DEPTH = bumpiness;
	ROUGHNESS = rgh;
	SPECULAR = 0.25 + w_snow * 0.15;
}
