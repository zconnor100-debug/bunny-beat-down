// The Briar's vines and roots (VineMesh: BriarRoot, BriarHeart): dark bark
// in knobbly ridges with a violet sheen, the Starfall Acorn's light showing
// gold-green in the cracks between the ridges, in pulses running along it
// (UV.x is metres along it) or steady (`glow_base`), and gone grey once it's
// withered (`alive` 0).
shader_type spatial;

uniform vec3 bark : source_color = vec3(0.17, 0.1, 0.14);
uniform vec3 sheen : source_color = vec3(0.55, 0.22, 0.75);
uniform vec3 glow : source_color = vec3(0.8, 1.0, 0.34);
uniform float alive = 1.0;           // 0: withered, grey, unlit
uniform float pulse_speed = 9.0;     // metres a second the pulses run along it
uniform float pulse_every = 14.0;    // metres between them
uniform float pulse_amount = 1.0;    // 0: no pulses
uniform float glow_base = 0.0;       // a steady glow in the cracks all along
uniform float hurt = 0.0;            // a flash where it's been hit

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
	float along = UV.x;
	float around = UV.y;
	float ridge = 0.5 + 0.5 * sin(around * 6.2831 * 7.0 + sin(along * 0.9) * 1.5 + noise(vec2(along * 0.6, around * 3.0)) * 2.0);
	float n = noise(vec2(along * 1.3, around * 9.0));
	vec3 base = bark * (0.65 + 0.55 * ridge * n);
	vec3 dead = vec3(0.25, 0.23, 0.21) * (0.7 + 0.4 * n);
	ALBEDO = mix(dead, base, alive);
	ROUGHNESS = mix(0.95, 0.72, alive);
	float ph = fract((along - TIME * pulse_speed) / pulse_every);
	float band = smoothstep(0.0, 0.06, ph) * smoothstep(0.24, 0.06, ph);
	// the light shows in thin cracks between the ridges, broken here and there
	float crack = smoothstep(0.84, 0.985, 1.0 - ridge) * smoothstep(0.3, 0.7, noise(vec2(along * 0.7, around * 7.0 + 3.0)));
	float e = (band * pulse_amount * (0.3 + 0.7 * crack) + glow_base * crack) * alive;
	EMISSION = glow * e * 2.6 + sheen * 0.05 * alive + vec3(1.0, 0.55, 0.3) * hurt * 0.6;
	RIM = 0.35 * alive;
	RIM_TINT = 0.6;
}
