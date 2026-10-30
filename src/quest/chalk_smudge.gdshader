// What rubbing chalk off a board leaves (TallySign.wipe_to): a pale smear,
// in streaks along the way the rag went, soft at its edges, as faint as
// `amount`.
shader_type spatial;
render_mode unshaded, cull_back, depth_draw_never, shadows_disabled;

uniform float amount = 0.0;
uniform vec3 chalk : source_color = vec3(0.86, 0.89, 0.85);

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
	vec2 uv = UV;
	// streaks: stretched along the rag's sweep, broken up a little across it
	float streak = noise(vec2(uv.x * 2.5, uv.y * 18.0)) * 0.6 + noise(vec2(uv.x * 7.0, uv.y * 41.0)) * 0.4;
	float clump = noise(uv * vec2(5.0, 3.0));
	float edge = smoothstep(0.0, 0.22, uv.x) * smoothstep(0.0, 0.22, 1.0 - uv.x) * smoothstep(0.0, 0.3, uv.y) * smoothstep(0.0, 0.3, 1.0 - uv.y);
	ALBEDO = chalk;
	ALPHA = amount * edge * (0.25 + 0.75 * streak) * (0.6 + 0.4 * clump) * 0.55;
}
