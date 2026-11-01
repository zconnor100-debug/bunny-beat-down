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

float luma(vec3 c) {
	return dot(c, vec3(0.3, 0.59, 0.11));
}

// (Each layer is sampled only where it shows: most of the floor is bedding
// alone, and sampling the sand, gravel and snow everywhere made this the
// costliest thing on screen on a weaker GPU. The texture lookups inside those
// branches take their mip level from derivatives found up here, where every
// pixel still runs, so the layers' edges don't shimmer.)
void fragment() {
	vec2 cuv = (world_pos.xz + terrain_size * 0.5) / terrain_size;
	vec4 ctl = texture(control_map, cuv);
	vec3 bio = texture(biome_map, cuv).rgb;
	vec2 p = world_pos.xz;
	vec2 dx = dFdx(p);
	vec2 dy = dFdy(p);
	float macro = texture(macro_noise, p / 160.0).r;
	float macro2 = texture(macro_noise, p / 33.0).r;
	float w_lag = smoothstep(0.2, 0.55, bio.r);
	float w_snow = smoothstep(0.35, 0.65, bio.g + (macro2 - 0.5) * 0.35);

	vec3 alb = vec3(0.0);
	vec3 nrm = vec3(0.5, 0.5, 1.0);
	float rgh = 0.9;
	if (w_lag < 1.0 && w_snow < 1.0) {   // (under the lagoon's gravel and the snow, the bedding doesn't show)
		// bedding: the shavings texture's light and shade, recoloured pale and warm,
		// with a finer, turned copy layered on top near the camera (single flakes
		// of shaving at a critter's feet, not a smooth beige carpet)
		vec2 buv = p / bedding_tile;
		vec3 blow = textureLod(bedding_albedo, buv, 9.0).rgb;
		float avg = max(luma(blow), 0.05);
		vec3 shav = mix(blow, textureGrad(bedding_albedo, buv, dx / bedding_tile, dy / bedding_tile).rgb, detail);
		float l = luma(shav) / avg;
		mat2 turn = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));
		vec2 q = turn * p;
		float near = 1.0 - smoothstep(20.0, 90.0, length(world_pos - CAMERA_POSITION_WORLD));
		float shade = l;
		nrm = textureGrad(bedding_normal, buv, dx / bedding_tile, dy / bedding_tile).rgb;
		if (near > 0.0) {
			vec2 qx = turn * dx / fine_tile;
			vec2 qy = turn * dy / fine_tile;
			float lf = luma(textureGrad(bedding_albedo, q / fine_tile, qx, qy).rgb) / avg;
			shade = mix(l, l * mix(1.0, lf, 0.75), near);
			nrm = mix(nrm, textureGrad(bedding_normal, q / fine_tile, qx, qy).rgb, 0.55 * near);
		}
		alb = bedding_color * mix(0.64, 1.26, clamp(shade * 0.5, 0.0, 1.0));
		// honey-coloured and paler shavings in patches
		alb *= mix(vec3(1.05, 0.97, 0.86), vec3(0.95, 0.97, 1.02), smoothstep(0.3, 0.7, texture(macro_noise, p / 13.0).r));
		// tufts of paper bedding: white, and in places the pastel kind (pink, sky
		// blue, mint), a patch at a time
		if (ctl.r > 0.0) {
			float hue = texture(macro_noise, p / 420.0 + vec2(0.37, 0.61)).r;
			vec3 pastel = mix(vec3(1.0, 0.78, 0.86), vec3(0.76, 0.86, 1.0), smoothstep(0.42, 0.5, hue));
			pastel = mix(pastel, vec3(0.8, 1.0, 0.84), smoothstep(0.56, 0.64, hue));
			vec3 paper = paper_color * mix(vec3(1.0), pastel, smoothstep(0.3, 0.38, hue) * (1.0 - smoothstep(0.7, 0.78, hue)) * 0.8);
			alb = mix(alb, paper * mix(0.9, 1.05, macro2), ctl.r);
		}
		// trodden trails: packed, darker shavings
		alb = mix(alb, alb * vec3(0.72, 0.66, 0.6), ctl.g * 0.85);
		alb *= mix(1.0, 0.82, ctl.b);
		// the lie of the land: hollows a little darker and warmer, the tops of the
		// hills and heaps paler (dry, loose shavings), so the rolling hills read
		alb *= mix(vec3(0.82, 0.77, 0.7), vec3(1.08, 1.06, 1.01), smoothstep(5.0, 26.0, world_pos.y));
		// bathing sand
		if (ctl.a > 0.0) {
			vec2 suv = p / sand_tile;
			vec2 sx = dx / sand_tile;
			vec2 sy = dy / sand_tile;
			vec3 sand = mix(textureLod(sand_albedo, suv, 9.0).rgb, textureGrad(sand_albedo, suv, sx, sy).rgb, detail);
			alb = mix(alb, sand * vec3(1.08, 1.04, 0.95), ctl.a);
			nrm = mix(nrm, textureGrad(sand_normal, suv, sx, sy).rgb, ctl.a);
		}
	}

	// lagoon: aquarium gravel in pastel tints, dark and glossy under the water
	if (w_lag > 0.0) {
		vec2 puv = p / pebble_tile;
		vec2 px = dx / pebble_tile;
		vec2 py = dy / pebble_tile;
		vec3 peb = mix(textureLod(pebble_albedo, puv, 9.0).rgb, textureGrad(pebble_albedo, puv, px, py).rgb, detail);
		vec3 tint = mix(vec3(0.75, 0.9, 1.15), vec3(1.15, 0.85, 0.95), smoothstep(0.3, 0.7, macro2));
		peb *= mix(vec3(1.0), tint, 0.5) * 1.15;
		alb = mix(alb, peb, w_lag);
		nrm = mix(nrm, textureGrad(pebble_normal, puv, px, py).rgb, w_lag);
		float wet = w_lag * smoothstep(lagoon_level + 0.25, lagoon_level - 0.15, world_pos.y);
		alb *= mix(1.0, 0.6, wet);
		rgh = mix(rgh, 0.3, wet);
	}

	// winter: snow, with a ragged edge where it thins out over the bedding
	if (w_snow > 0.0) {
		vec2 nuv = p / snow_tile;
		vec2 nx = dx / snow_tile;
		vec2 ny = dy / snow_tile;
		vec3 slow = textureLod(snow_albedo, nuv, 9.0).rgb;
		vec3 sn = mix(slow, textureGrad(snow_albedo, nuv, nx, ny).rgb, detail);
		sn = vec3(0.93, 0.96, 1.0) * clamp(luma(sn) / max(luma(slow), 0.05), 0.85, 1.12);
		alb = mix(alb, sn, w_snow);
		nrm = mix(nrm, textureGrad(snow_normal, nuv, nx, ny).rgb, w_snow);
		rgh = mix(rgh, 0.65, w_snow);
	}

	alb *= mix(0.9, 1.06, macro);
	ALBEDO = alb;
	NORMAL_MAP = nrm;
	NORMAL_MAP_DEPTH = bumpiness;
	ROUGHNESS = rgh;
	SPECULAR = 0.25 + w_snow * 0.15;
}
