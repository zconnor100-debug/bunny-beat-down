// A coat's glow, added over its colour (coat_tint.gdshader, the pass before).
//   1 golden acorn: a gold sheen at the edges and in the light, and a glint
//     now and then in its scales
//   2 starry night: stars, twinkling, and a faint violet rim
//   4 smouldering: embers glowing in its cracks, breathing
shader_type spatial;
render_mode blend_add, unshaded, cull_back, depth_draw_never, shadows_disabled, fog_disabled;

#include "res://src/fx/coat_lib.gdshaderinc"

uniform int pattern = 1;
uniform vec3 glow_color : source_color = vec3(1.0, 0.82, 0.4);
uniform float scale = 7.0;
uniform float strength = 1.0;

varying vec3 model_pos;   // (metres)
varying vec3 model_normal;

void vertex() {
	model_pos = coat_place(VERTEX, MODEL_MATRIX);
	model_normal = NORMAL;
}

// Stars in a flat patch of sky: one now and then in each cell, twinkling.
float sky(vec2 uv, float seed) {
	vec2 i = floor(uv);
	vec2 f = fract(uv);
	float s = 0.0;
	for (int x = -1; x <= 1; x++) {
		for (int y = -1; y <= 1; y++) {
			vec2 o = vec2(float(x), float(y));
			vec3 r = coat_hash3(vec3(i + o, seed));
			if (r.x < 0.6) {
				float size = mix(0.07, 0.17, r.x / 0.6);
				float d = length(o + r.yz - f);
				float twinkle = 0.5 + 0.5 * sin(TIME * (1.5 + r.y * 3.0) + r.z * 30.0);
				float core = pow(max(1.0 - d / size, 0.0), 1.2);
				float halo = max(1.0 - d / (size * 3.0), 0.0) * 0.18;   // (a soft glow round it)
				s = max(s, (core + halo) * twinkle);
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
		float star = w.x * sky(p.yz * scale, 1.0) + w.y * sky(p.xz * scale, 2.0) + w.z * sky(p.xy * scale, 3.0);
		c = glow_color * star * 4.5 + vec3(0.45, 0.32, 0.85) * rim * 0.4;
	} else if (pattern == 4) {
		vec3 id;
		vec4 cell = coat_cells(p * scale, id);
		float crack = 1.0 - smoothstep(0.0, 0.13, cell.w);
		float breath = 0.55 + 0.45 * sin(TIME * 1.6 + coat_noise(p * 3.0) * 6.0);
		c = glow_color * (crack * breath * 2.2 + rim * 0.25);
	}
	ALBEDO = c * strength;
}
