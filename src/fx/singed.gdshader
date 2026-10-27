// Singed fur, on a bot you blew up once (RivalBook "singed"): sooty, scorched
// blotches darkening its own fur. A next_pass on each of its materials
// (CritterVisual._singe), multiplied over them, in the model's UVs so the
// patches stay put on the fur as it moves.
shader_type spatial;
render_mode blend_mul, unshaded, cull_back, depth_draw_never, shadows_disabled;

uniform vec3 soot : source_color = vec3(0.24, 0.19, 0.16);
uniform float scale = 7.0;
uniform float cover = 0.48;   // how much of the fur is scorched

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void fragment() {
	vec2 p = UV * scale;
	float n = noise(p) * 0.6 + noise(p * 2.7 + 13.1) * 0.3 + noise(p * 7.3 + 5.7) * 0.1;
	float burnt = smoothstep(1.0 - cover - 0.08, 1.0 - cover + 0.12, n);
	ALBEDO = mix(vec3(1.0), soot, burnt * 0.85);
}
