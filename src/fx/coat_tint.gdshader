// A coat's colour (Workshop.coat_material): multiplied over your fur and all
// you wear, so its shading, eyes and stitches still show through. Its glow is
// the next pass (coat_glow.gdshader). In the model's own space, so the
// pattern goes where you go.
//   1 golden acorn: gilded, in an acorn cup's scales
//   2 starry night: the night sky, violet up top
//   3 tiger stripe: amber, with black stripes round you
//   4 smouldering: charcoal
//   5 patchwork: a crazy quilt, its patches in the three maps' colours
//     (plain, plaid or dotted), sewn together with big stitches (colour a:
//     the thread, b: the seams), lit up by its glow so the colours show on
//     any fur
shader_type spatial;
render_mode blend_mul, unshaded, cull_back, depth_draw_never, shadows_disabled, fog_disabled;

#include "res://src/fx/coat_lib.gdshaderinc"

uniform int pattern = 1;
uniform vec3 color_a : source_color = vec3(1.0, 0.78, 0.32);
uniform vec3 color_b : source_color = vec3(0.78, 0.5, 0.12);
uniform float scale = 7.0;

varying vec3 model_pos;   // (metres)
varying float height;     // (metres up from the model's origin)

void vertex() {
	model_pos = coat_place(VERTEX, MODEL_MATRIX);
	height = dot(model_pos, coat_up(MODEL_MATRIX));
}

void fragment() {
	vec3 c = vec3(1.0);
	vec3 p = model_pos;
	if (pattern == 1) {
		vec3 id;
		vec4 cell = coat_cells(p * scale, id);
		c = mix(color_a, color_b, smoothstep(0.15, 0.75, length(cell.xyz)));   // (each scale darker toward its rim)
	} else if (pattern == 2) {
		c = mix(color_a, color_b, smoothstep(0.2, 3.0, height + (coat_noise(p * 1.2) - 0.5) * 0.8));
	} else if (pattern == 3) {
		float w = height * scale + (coat_noise(p * 1.4) - 0.5) * 1.6;
		float band = abs(fract(w) - 0.5) * 2.0;   // (1 in a stripe's middle)
		float width = 0.72 + 0.18 * coat_noise(p * 3.0);   // (stripes thin out and break up)
		c = mix(color_a, color_b, smoothstep(width, width + 0.06, band));
	} else if (pattern == 4) {
		c = mix(color_a, color_b, coat_noise(p * scale));
	} else if (pattern == 5) {
		vec3 id;
		vec4 cell = coat_cells(p * scale, id);
		vec3 rnd = coat_hash3(id);
		c = coat_patch(rnd);
		if (rnd.y < 0.35) {   // (plaid: stripes three ways, so any cut through it is checked)
			vec3 g = step(0.5, fract(p * scale * 4.0 + rnd));
			c *= 1.0 - 0.13 * (g.x + g.y + g.z);
		} else if (rnd.y < 0.7) {   // (dotted)
			vec3 dot_id;
			vec4 dots = coat_cells(p * scale * 5.0, dot_id);
			c = mix(c, mix(c, vec3(1.0), 0.75), 1.0 - smoothstep(0.24, 0.3, length(dots.xyz)));
		}
		float stitch = step(0.5, fract(dot(p, vec3(0.8, 1.0, 0.9)) * scale * 9.0));   // (a running stitch: on, off)
		c = mix(c, color_a, stitch * (smoothstep(0.05, 0.065, cell.w) - smoothstep(0.1, 0.115, cell.w)));
		c = mix(c, color_b, 1.0 - smoothstep(0.02, 0.035, cell.w));
	}
	ALBEDO = c;
}
