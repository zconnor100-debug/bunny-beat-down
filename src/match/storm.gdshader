// The Briar: a wall of drifting violet haze laced with dark thorn streaks.
// Rendered on both faces so it reads from inside and out; fades toward the
// sky and pulses gently.
shader_type spatial;
render_mode blend_mix, cull_disabled, unshaded, depth_draw_never, shadows_disabled;

uniform float radius = 100.0;
uniform vec3 haze : source_color = vec3(0.55, 0.25, 0.75);
uniform vec3 thorn : source_color = vec3(0.12, 0.04, 0.16);

varying vec3 local_pos;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}
float fbm(vec2 p) {
	float v = 0.0, a = 0.5;
	for (int i = 0; i < 5; i++) { v += a * noise(p); p *= 2.03; a *= 0.5; }
	return v;
}

void vertex() {
	local_pos = VERTEX;
}

void fragment() {
	float ang = atan(local_pos.z, local_pos.x);
	float around = ang * radius / 6.0;          // ~6 m per noise cell around the ring
	float h = local_pos.y + 0.5;                // 0 bottom .. 1 top
	vec2 uv = vec2(around, h * 30.0);
	float n = fbm(uv * 0.35 + vec2(TIME * 0.15, -TIME * 0.4));
	float vines = smoothstep(0.62, 0.7, fbm(uv * vec2(0.8, 0.25) + vec2(0.0, TIME * 0.05)));
	vec3 col = mix(haze * (0.6 + 0.8 * n), thorn, vines * 0.85);
	float pulse = 0.85 + 0.15 * sin(TIME * 1.7 + around * 0.2);
	ALBEDO = col * pulse;
	ALPHA = clamp((0.45 + 0.4 * n + vines * 0.3) * (1.0 - smoothstep(0.35, 1.0, h)), 0.0, 0.92);
}
