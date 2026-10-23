// The kid's bedroom floor in Toy Box Bash: waxed oak floorboards, the printed
// town play rug (a texture made in code, with a woven-fabric bump), a
// patchwork quilt of gingham and plaid squares over the pillow hills, and the
// dark, glossy wet patch where the fishbowl's water spilled.
// Biome map: R spill, G pillows, B floor. Control map: R scuffs, B steep folds.
shader_type spatial;
render_mode blend_mix, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D control_map : filter_linear, repeat_disable;
uniform sampler2D biome_map : filter_linear, repeat_disable;
uniform sampler2D macro_noise : filter_linear_mipmap, repeat_enable;
uniform sampler2D playmat : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D oak_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D oak_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D weave_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D gingham_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D plaid_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float terrain_size = 1536.0;
uniform vec4 rug_rect = vec4(-60.0, -250.0, 480.0, 510.0);   // x, z, width, depth
uniform float spill_level = 3.75;
uniform float oak_tile = 60.0;
uniform float patch_size = 34.0;
uniform float detail = 0.75;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

vec3 soft(sampler2D tex, vec2 uv) {
	return mix(textureLod(tex, uv, 9.0).rgb, texture(tex, uv).rgb, detail);
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 p = world_pos.xz;
	vec2 cuv = (p + terrain_size * 0.5) / terrain_size;
	vec4 ctl = texture(control_map, cuv);
	vec3 bio = texture(biome_map, cuv).rgb;
	float macro = texture(macro_noise, p / 140.0).r;

	// oak floorboards, scuffed here and there
	vec3 alb = soft(oak_albedo, p / oak_tile) * mix(1.0, 0.86, ctl.r * 0.6);
	vec3 nrm = texture(oak_normal, p / oak_tile).rgb;
	float rgh = mix(0.35, 0.6, ctl.r);

	// the play rug
	vec2 ruv = (p - rug_rect.xy) / rug_rect.zw;
	float in_rug = step(0.0, ruv.x) * step(ruv.x, 1.0) * step(0.0, ruv.y) * step(ruv.y, 1.0);
	vec3 weave = texture(weave_normal, p / 3.0).rgb;
	vec3 mat = texture(playmat, ruv).rgb * mix(0.92, 1.04, texture(plaid_albedo, p / 3.0).g);
	alb = mix(alb, mat, in_rug);
	nrm = mix(nrm, weave, in_rug);
	rgh = mix(rgh, 0.95, in_rug);

	// the quilt over the pillow hills: patchwork squares with darker seams
	float w_quilt = smoothstep(0.2, 0.45, bio.g);
	vec2 cell = floor(p / patch_size);
	vec2 f = fract(p / patch_size);
	float pick = hash(cell);
	vec3 gingham = soft(gingham_albedo, p / 9.0);
	vec3 plaid = soft(plaid_albedo, p / 9.0);
	vec3 tint = pick < 0.33 ? vec3(1.0) : (pick < 0.66 ? vec3(0.75, 0.85, 1.15) : vec3(1.15, 1.05, 0.7));
	vec3 quilt = pick < 0.45 ? gingham : plaid * tint;
	float seam = 1.0 - smoothstep(0.0, 0.025, min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y)));
	quilt *= mix(1.0, 0.6, seam);
	alb = mix(alb, quilt, w_quilt);
	nrm = mix(nrm, weave, w_quilt);
	rgh = mix(rgh, 0.95, w_quilt);
	alb *= mix(1.0, 0.85, ctl.b * w_quilt);

	// the spill: darker, glossy wet wood
	float wet = smoothstep(0.25, 0.55, bio.r) * smoothstep(spill_level + 0.35, spill_level - 0.05, world_pos.y);
	alb *= mix(1.0, 0.65, wet);
	rgh = mix(rgh, 0.12, wet);

	alb *= mix(0.92, 1.05, macro);
	ALBEDO = alb;
	NORMAL_MAP = nrm;
	NORMAL_MAP_DEPTH = 0.5;
	ROUGHNESS = rgh;
	SPECULAR = 0.3;
}
