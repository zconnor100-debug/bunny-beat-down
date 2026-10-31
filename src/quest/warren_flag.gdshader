shader_type spatial;
// The Warren's flag (WarrenFlag): a pennant flapping off its pole (UV.x 0 at
// the pole, 1 at the tip), acorn-brown with a gold-green acorn on it, a
// little lighter where the cloth turns to the light.
render_mode cull_disabled;

uniform vec3 cloth : source_color = vec3(0.55, 0.33, 0.16);
uniform vec3 mark : source_color = vec3(0.8, 1.0, 0.34);

varying float fold;

void vertex() {
	float u = UV.x;
	float w = sin(TIME * 5.2 - u * 7.0) * 0.55 + sin(TIME * 8.3 - u * 13.0 + UV.y * 2.0) * 0.18;
	fold = w;
	VERTEX.z += w * u * 0.9;
	VERTEX.y -= u * u * 0.35;
}

// an acorn: a round nut under a cap (in the flag's own 0..1 square, aspect corrected)
float acorn(vec2 p) {
	vec2 nut = (p - vec2(0.42, 0.56)) / vec2(0.13, 0.18);
	vec2 cap = (p - vec2(0.42, 0.37)) / vec2(0.17, 0.08);
	float stem = step(abs(p.x - 0.43), 0.012) * step(0.24, p.y) * step(p.y, 0.31);
	return max(max(step(dot(nut, nut), 1.0), step(dot(cap, cap), 1.0)), stem);
}

void fragment() {
	vec2 p = UV;
	// a swallowtail: a notch cut in from the tip
	if (p.x > 0.82 && abs(p.y - 0.5) < (p.x - 0.82) * 1.3) {
		discard;
	}
	float a = acorn(p);
	vec3 c = mix(cloth, mark, a);
	c *= 0.85 + 0.25 * fold;
	ALBEDO = c;
	ROUGHNESS = 0.9;
	EMISSION = mark * a * 0.35;
}
