// A coat's glow, added over its colour (coat_tint.gdshader, the pass before).
//   1 golden acorn: a gold sheen at the edges and in the light, and a glint
//     now and then in its scales
//   2 starry night: stars in every colour, twinkling, each with a sparkle's
//     four rays, and a violet rim
//   3 tiger stripe: the amber lit up warm (so it's bright on any fur), the
//     stripes left black
//   4 smouldering: embers glowing red-hot in its cracks, white-hot at their
//     hearts, breathing
//   5 patchwork: each patch's own colour, lifted (so it shows on dark fur
//     as well as white), the seams left dark
//   6 brutus: his claw rakes glowing red, beating like a heart, and a dull
//     red rim
shader_type spatial;
render_mode blend_add, unshaded, cull_back, depth_draw_never, shadows_disabled, fog_disabled;

#include "res://src/fx/coat_lib.gdshaderinc"

uniform int pattern = 1;
uniform vec3 glow_color : source_color = vec3(1.0, 0.82, 0.4);
uniform float scale = 7.0;
uniform float strength = 1.0;

varying vec3 model_pos;   // (metres)
varying vec3 model_normal;
varying float height;     // (metres up from the model's origin)

void vertex() {
	model_pos = coat_place(VERTEX, MODEL_MATRIX);
	model_normal = NORMAL;
	height = dot(model_pos, coat_up(MODEL_MATRIX));
}

// The stars' colours: starlight, ice blue, rose, gold and mint.
const vec3 STAR_COLORS[5] = vec3[5](vec3(1.0, 0.96, 0.82), vec3(0.55, 0.85, 1.0), vec3(1.0, 0.55, 0.85),
	vec3(1.0, 0.82, 0.3), vec3(0.55, 1.0, 0.75));

// Stars in a flat patch of sky: one now and then in each cell, twinkling,
// each its own colour, the bigger ones with a sparkle's four rays.
vec3 sky(vec2 uv, float seed) {
	vec2 i = floor(uv);
	vec2 f = fract(uv);
	vec3 s = vec3(0.0);
	for (int x = -1; x <= 1; x++) {
		for (int y = -1; y <= 1; y++) {
			vec2 o = vec2(float(x), float(y));
			vec3 r = coat_hash3(vec3(i + o, seed));
			if (r.x < 0.75) {
				float size = mix(0.07, 0.19, r.x / 0.75);
				vec2 d2 = o + r.yz - f;
				float d = length(d2);
				float twinkle = 0.6 + 0.4 * sin(TIME * (1.5 + r.y * 3.0) + r.z * 30.0);
				float core = pow(max(1.0 - d / size, 0.0), 1.2);
				float halo = max(1.0 - d / (size * 3.0), 0.0) * 0.3;   // (a soft glow round it)
				float rays = (max(1.0 - abs(d2.x) / (size * 0.18), 0.0) * max(1.0 - abs(d2.y) / (size * 3.2), 0.0)
					+ max(1.0 - abs(d2.y) / (size * 0.18), 0.0) * max(1.0 - abs(d2.x) / (size * 3.2), 0.0)) * step(0.35, r.x);
				vec3 col = STAR_COLORS[min(int(fract(r.y * 7.13) * 5.0), 4)];
				s = max(s, col * (core + halo + rays * 0.9) * twinkle);
			}
		}
	}
	return s;
}

void fragment() {
	vec3 p = model_pos;
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float rim = pow(1.0 - facing, 2.5);
	vec3 c = vec3(0.0);
	if (pattern == 1) {
		vec3 id;
		vec4 cell = coat_cells(p * scale, id);
		vec3 rnd = coat_hash3(id);
		float sheen = pow(max(dot(reflect(-VIEW, NORMAL), normalize(vec3(0.35, 0.8, 0.45))), 0.0), 5.0);
		float glint = pow(max(sin(TIME * (0.7 + rnd.y) + rnd.x * 40.0), 0.0), 40.0) * (1.0 - smoothstep(0.0, 0.3, length(cell.xyz)));
		c = glow_color * (rim * 0.9 + sheen * 0.55 + glint * 2.5);
	} else if (pattern == 2) {
		vec3 w = pow(abs(normalize(model_normal)), vec3(4.0));   // (the sky seen from three sides, blended by which way the skin faces)
		w /= w.x + w.y + w.z;
		vec3 star = w.x * sky(p.yz * scale, 1.0) + w.y * sky(p.xz * scale, 2.0) + w.z * sky(p.xy * scale, 3.0);
		c = glow_color * star * 6.5 + vec3(0.5, 0.38, 0.95) * rim * 0.55;
	} else if (pattern == 3) {
		c = glow_color * (1.0 - coat_tiger(p, height, scale)) * (0.32 + rim * 0.45);
	} else if (pattern == 4) {
		vec3 id;
		vec4 cell = coat_cells(p * scale, id);
		float crack = 1.0 - smoothstep(0.0, 0.16, cell.w);
		float heart = 1.0 - smoothstep(0.0, 0.045, cell.w);   // (white-hot down the middle)
		float breath = 0.7 + 0.3 * sin(TIME * 1.6 + coat_noise(p * 3.0) * 6.0);
		c = (glow_color * crack * 4.2 + vec3(1.0, 0.75, 0.4) * heart * 2.2) * breath + glow_color * rim * 0.3;
	} else if (pattern == 5) {
		vec3 id;
		vec4 cell = coat_cells(p * scale, id);
		c = glow_color * coat_patch(coat_hash3(id)) * smoothstep(0.02, 0.05, cell.w) * (1.0 + rim * 0.6);
	} else if (pattern == 6) {
		float beat = pow(0.5 + 0.5 * sin(TIME * 2.4), 6.0);
		c = glow_color * coat_rakes(p, scale) * (1.5 + 1.6 * beat) + glow_color * rim * 0.22;
	}
	ALBEDO = c * strength;
}
