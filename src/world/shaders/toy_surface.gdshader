// Surface detail for the toys of the Hamster Cage and Toy Box Bash (moulded
// plastic, crayon wax, cardboard and paper): a fine bump (orange-peel plastic,
// waxy crayon, paper fibre), soft colour mottling, and faint scuffs and dust
// where hands and paws have been. World-space noise (the meshes are built in
// code, their UVs aren't laid out for textures), mapped from the face's
// dominant axis, so every toy gets it without unwrapping.
shader_type spatial;
render_mode blend_mix, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec3 albedo : source_color = vec3(1.0);
uniform float roughness = 0.32;
uniform float clearcoat = 0.35;
uniform float grain = 1.0;          // fine bump strength
uniform float grain_scale = 1.6;    // fine bump repeats per metre
uniform float mottle = 0.06;        // colour variation
uniform float wear = 1.0;           // scuffs and dust
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D bump_tex : hint_normal, filter_linear_mipmap, repeat_enable;

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

// The face's plane in world space (by its dominant axis).
vec2 plane_uv(vec3 p, vec3 n) {
	vec3 a = abs(n);
	if (a.x > a.y && a.x > a.z) return p.zy;
	if (a.y > a.z) return p.xz;
	return p.xy;
}

void fragment() {
	vec2 uv = plane_uv(wpos, wnrm);
	float macro = texture(noise_tex, uv * 0.045).r;
	float scuffs = texture(noise_tex, uv * 0.33 + vec2(0.37, 0.11)).g;
	float fine = texture(noise_tex, uv * grain_scale).b;
	vec3 col = albedo * mix(1.0 - mottle, 1.0 + mottle * 0.6, macro);
	// scuffs: a little greyer and duller; dust settles on the tops
	float scuff = smoothstep(0.66, 0.86, scuffs) * wear;
	float dust = smoothstep(0.55, 0.95, wnrm.y) * smoothstep(0.45, 0.8, macro) * wear * 0.35;
	col = mix(col, col * 0.78 + vec3(0.05), scuff * 0.55);
	col = mix(col, vec3(0.86, 0.83, 0.78), dust * 0.25);
	ALBEDO = col;
	ROUGHNESS = clamp(roughness + scuff * 0.25 + dust * 0.3 + (fine - 0.5) * 0.08, 0.04, 1.0);
	SPECULAR = 0.5;
	CLEARCOAT = clearcoat * (1.0 - scuff * 0.6);
	CLEARCOAT_ROUGHNESS = 0.22;
	NORMAL_MAP = texture(bump_tex, uv * grain_scale).rgb;
	NORMAL_MAP_DEPTH = 0.35 * grain;
}
