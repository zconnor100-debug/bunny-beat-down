// Island terrain: seven PBR layers blended by a splat control map (R grass,
// G dirt path, B rock, A moss; forest floor underneath, sand by height) and a
// biome map (R swamp, G grassland, B forest): swamp mud around the still
// water, sun-warmed grass on the grasslands.
// World-space UVs at critter scale, macro colour variation to hide tiling,
// and tri-planar rock on steep slopes.
shader_type spatial;
render_mode blend_mix, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D control_map : filter_linear, repeat_disable;
uniform float terrain_size = 512.0;

uniform sampler2D floor_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D floor_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D floor_rough : hint_roughness_g, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_rough : hint_roughness_g, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_rough : hint_roughness_g, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_rough : hint_roughness_g, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D moss_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D moss_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D moss_rough : hint_roughness_g, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D sand_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D sand_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D sand_rough : hint_roughness_g, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D mud_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D mud_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D mud_rough : hint_roughness_g, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D biome_map : filter_linear, repeat_disable;
uniform sampler2D macro_noise : filter_linear_mipmap, repeat_enable;
uniform float swamp_level = 2.6;
uniform float mud_tile = 5.0;

// metres covered by one texture repeat (critter-scale ground looks "big")
uniform float floor_tile = 7.0;
uniform float grass_tile = 6.0;
uniform float dirt_tile = 6.0;
uniform float rock_tile = 9.0;
uniform float moss_tile = 6.0;
uniform float sand_tile = 6.0;
uniform float sand_height = 1.6;
uniform vec3 grass_tint : source_color = vec3(1.0);

varying vec3 world_pos;
varying vec3 world_nrm;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

vec2 rot(vec2 p, float a) {
	float c = cos(a), s = sin(a);
	return vec2(c * p.x - s * p.y, s * p.x + c * p.y);
}

// two decorrelated samples blended by macro noise: hides the tile grid
vec4 anti_tile(sampler2D tex, vec2 uv, float m) {
	vec4 a = texture(tex, uv);
	vec4 b = texture(tex, rot(uv, 1.7) * 0.73 + 0.31);
	return mix(a, b, smoothstep(0.35, 0.65, m));
}

void fragment() {
	vec2 cuv = (world_pos.xz + terrain_size * 0.5) / terrain_size;
	vec4 ctl = texture(control_map, cuv);
	vec3 bio = texture(biome_map, cuv).rgb;
	float macro = texture(macro_noise, world_pos.xz / 180.0).r;
	float macro2 = texture(macro_noise, world_pos.xz / 37.0).r;

	vec2 p = world_pos.xz;
	vec3 alb = anti_tile(floor_albedo, p / floor_tile, macro2).rgb;
	vec3 nrm = anti_tile(floor_normal, p / floor_tile, macro2).rgb;
	float rgh = anti_tile(floor_rough, p / floor_tile, macro2).g;

	float w_sand = smoothstep(sand_height + 0.5, sand_height - 0.4, world_pos.y) * (1.0 - bio.r);
	float w_grass = ctl.r * (1.0 - w_sand);
	float w_moss = ctl.a * (1.0 - w_sand);
	float w_dirt = ctl.g;
	float w_rock = ctl.b;

	vec3 g_alb = anti_tile(grass_albedo, p / grass_tile, macro2).rgb * grass_tint;
	g_alb *= mix(vec3(1.0), vec3(1.1, 1.05, 0.82), bio.g);   // sunny meadow grass
	alb = mix(alb, g_alb, w_grass);
	nrm = mix(nrm, anti_tile(grass_normal, p / grass_tile, macro2).rgb, w_grass);
	rgh = mix(rgh, texture(grass_rough, p / grass_tile).g, w_grass);

	alb = mix(alb, texture(moss_albedo, p / moss_tile).rgb, w_moss);
	nrm = mix(nrm, texture(moss_normal, p / moss_tile).rgb, w_moss);
	rgh = mix(rgh, texture(moss_rough, p / moss_tile).g, w_moss);

	// swamp mud: on the low ground around (and under) the still water
	float w_mud = bio.r * smoothstep(swamp_level + 1.6, swamp_level + 0.3, world_pos.y) * (1.0 - w_rock) * (1.0 - ctl.g);
	alb = mix(alb, anti_tile(mud_albedo, p / mud_tile, macro2).rgb, w_mud);
	nrm = mix(nrm, texture(mud_normal, p / mud_tile).rgb, w_mud);
	rgh = mix(rgh, texture(mud_rough, p / mud_tile).g * 0.7, w_mud);

	alb = mix(alb, texture(sand_albedo, p / sand_tile).rgb, w_sand);
	nrm = mix(nrm, texture(sand_normal, p / sand_tile).rgb, w_sand);
	rgh = mix(rgh, texture(sand_rough, p / sand_tile).g, w_sand);

	alb = mix(alb, anti_tile(dirt_albedo, p / dirt_tile, macro2).rgb, w_dirt);
	nrm = mix(nrm, texture(dirt_normal, p / dirt_tile).rgb, w_dirt);
	rgh = mix(rgh, texture(dirt_rough, p / dirt_tile).g, w_dirt);

	if (w_rock > 0.01) {
		// tri-planar rock so cliffs do not smear
		vec3 bw = pow(abs(world_nrm), vec3(4.0));
		bw /= (bw.x + bw.y + bw.z);
		vec3 r_alb = texture(rock_albedo, world_pos.zy / rock_tile).rgb * bw.x
			+ texture(rock_albedo, world_pos.xz / rock_tile).rgb * bw.y
			+ texture(rock_albedo, world_pos.xy / rock_tile).rgb * bw.z;
		vec3 r_nrm = texture(rock_normal, world_pos.zy / rock_tile).rgb * bw.x
			+ texture(rock_normal, world_pos.xz / rock_tile).rgb * bw.y
			+ texture(rock_normal, world_pos.xy / rock_tile).rgb * bw.z;
		float r_rgh = texture(rock_rough, world_pos.xz / rock_tile).g;
		alb = mix(alb, r_alb, w_rock);
		nrm = mix(nrm, r_nrm, w_rock);
		rgh = mix(rgh, r_rgh, w_rock);
	}

	// large-scale colour drift so a meadow is never one flat tone
	alb *= mix(0.82, 1.12, macro);
	// wet darkening at the waterline (the sea's, and the swamp's)
	float wet = max(smoothstep(0.6, 0.0, world_pos.y), bio.r * smoothstep(swamp_level + 0.4, swamp_level - 0.1, world_pos.y));
	alb *= mix(1.0, 0.62, wet);
	rgh = mix(rgh, 0.25, wet);

	ALBEDO = alb;
	NORMAL_MAP = nrm;
	NORMAL_MAP_DEPTH = 1.0;
	ROUGHNESS = clamp(rgh, 0.05, 1.0);
	SPECULAR = 0.35;
}
