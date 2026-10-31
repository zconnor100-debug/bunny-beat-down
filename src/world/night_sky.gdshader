// Night over Wildwood (WorldLighting.make_night: the Kernel Hunt's Finale):
// deep blue going black overhead, stars in three sizes twinkling, the Milky
// Way's band with dust lanes through it, and the moon where the sun would be
// (the scene's directional light), haloed. The reflections and ambient pass
// gets the plain gradient (stars there are only noise).
shader_type sky;

uniform vec3 zenith : source_color = vec3(0.010, 0.016, 0.052);
uniform vec3 horizon : source_color = vec3(0.065, 0.085, 0.165);
uniform vec3 ground : source_color = vec3(0.016, 0.02, 0.034);
uniform vec3 moon_color : source_color = vec3(0.96, 0.95, 0.86);
uniform vec3 band_normal = vec3(0.32, 0.38, 0.87);   // the Milky Way's great circle
uniform float stars = 1.0;
// a glow low on the horizon the way of something bright (the Bluff, gold-green)
uniform vec3 glow_dir = vec3(1.0, 0.0, 0.0);
uniform vec3 glow_color : source_color = vec3(0.62, 0.95, 0.3);
uniform float glow_amount = 0.0;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

vec3 hash33(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.xxy + p.yxx) * p.zyx);
}

float noise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	vec3 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash13(i), hash13(i + vec3(1, 0, 0)), u.x), mix(hash13(i + vec3(0, 1, 0)), hash13(i + vec3(1, 1, 0)), u.x), u.y),
		mix(mix(hash13(i + vec3(0, 0, 1)), hash13(i + vec3(1, 0, 1)), u.x), mix(hash13(i + vec3(0, 1, 1)), hash13(i + vec3(1, 1, 1)), u.x), u.y), u.z);
}

float fbm(vec3 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * noise3(p);
		p = p * 2.03 + vec3(1.7, 9.2, 3.1);
		a *= 0.5;
	}
	return v;
}

// One layer of stars: a random point in some of the cells of a grid the sky
// passes through, `rare` of them lit, each its own size and twinkle.
float star_layer(vec3 dir, float scale, float rare, float size) {
	vec3 p = dir * scale;
	vec3 cell = floor(p);
	float h = hash13(cell);
	if (h < rare) {
		return 0.0;
	}
	vec3 at = hash33(cell) * 0.7 + 0.15;
	float d = length(fract(p) - at);
	float s = size * (0.6 + 0.8 * hash13(cell + 7.1));
	float b = smoothstep(s, 0.0, d);
	float twinkle = 0.7 + 0.3 * sin(TIME * (1.3 + 2.6 * hash13(cell + 3.7)) + h * 61.0);
	return b * b * twinkle * (0.35 + 0.65 * (h - rare) / (1.0 - rare));
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	float up = dir.y;
	vec3 col = mix(horizon, zenith, pow(clamp(up, 0.0, 1.0), 0.55));
	if (up < 0.0) {
		col = mix(horizon * 0.8, ground, clamp(-up * 6.0, 0.0, 1.0));
	}
	vec3 moon = LIGHT0_ENABLED ? LIGHT0_DIRECTION : normalize(vec3(-0.4, 0.55, -0.7));
	float md = dot(dir, moon);
	// the sky's brighter round the moon, and low down the way of the glow
	col += moon_color * (pow(max(md, 0.0), 18.0) * 0.05 + pow(max(md, 0.0), 260.0) * 0.18);
	vec3 flat_dir = normalize(vec3(dir.x, 0.0, dir.z) + vec3(1e-4));
	col += glow_color * glow_amount * pow(max(dot(flat_dir, normalize(glow_dir)), 0.0), 8.0) * exp(-max(up, 0.0) * 9.0);
	if (!AT_CUBEMAP_PASS && up > -0.05) {
		float fade_in = smoothstep(-0.02, 0.12, up) * stars;
		// the Milky Way: a soft band, clumpy, with dark lanes of dust down it
		float across = dot(dir, normalize(band_normal));
		float band = exp(-pow(across / 0.2, 2.0));
		float clumps = fbm(dir * 5.0);
		float lanes = smoothstep(0.55, 0.75, fbm(dir * 9.0 + vec3(4.0))) * exp(-pow(across / 0.07, 2.0));
		col += vec3(0.55, 0.6, 0.78) * band * (0.025 + 0.06 * clumps) * (1.0 - 0.8 * lanes) * fade_in;
		// more, fainter stars in the band
		float s = star_layer(dir, 85.0, 0.965, 0.16) * 1.6;
		s += star_layer(dir, 170.0, 0.93, 0.18) * 0.8;
		s += star_layer(dir, 300.0, mix(0.93, 0.8, band), 0.2) * 0.45;
		vec3 tint = mix(vec3(0.75, 0.82, 1.0), vec3(1.0, 0.9, 0.75), hash13(floor(dir * 85.0)));
		col += tint * s * fade_in;
		// the moon: a disc with darker seas, and its halo
		float disc = smoothstep(0.99955, 0.99975, md);
		float seas = 0.82 + 0.18 * fbm(dir * 900.0);
		col = mix(col, moon_color * 2.6 * seas, disc);
	}
	COLOR = col;
}
