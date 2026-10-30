// A coat's colour (Workshop.coat_material): multiplied over your fur and all
// you wear, so its shading, eyes and stitches still show through. Its glow is
// the next pass (coat_glow.gdshader). In the model's own space, so the
// pattern goes where you go.
//   1 golden acorn: gilded, in an acorn cup's scales
//   2 starry night: a twilight sky, violet up top
//   3 tiger stripe: amber, with bold black stripes round you
//   4 smouldering: charcoal
//   5 patchwork: a crazy quilt, its patches in the three maps' colours
//     (plain, plaid or dotted), sewn together with big stitches (colour a:
//     the thread, b: the seams), lit up by its glow so the colours show on
//     any fur
//   6 brutus: matted, grizzled grey (hanging, like his), torn by claw rakes
//     healed pale
//   7 touched: the Starfall Acorn's light got in (the Kernel Hunt's Touched):
//     the fur gone a sickly olive, darker veins running through it
shader_type spatial;
render_mode blend_mul, unshaded, cull_back, depth_draw_never, shadows_disabled, fog_disabled;

#include "res://src/fx/coat_lib.gdshaderinc"

uniform int pattern = 1;
uniform vec3 color_a : source_color = vec3(1.0, 0.78, 0.32);
uniform vec3 color_b : source_color = vec3(0.78, 0.5, 0.12);
uniform float scale = 7.0;

varying vec3 model_pos;   // (metres)
varying float height;     // (metres up from the model's origin)
varying vec3 up_dir;      // (the world's up, in the model's frame)

void vertex() {
	model_pos = coat_place(VERTEX, MODEL_MATRIX);
	up_dir = coat_up(MODEL_MATRIX);
	height = dot(model_pos, up_dir);
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
		c = mix(color_a, color_b, coat_tiger(p, height, scale));
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
	} else if (pattern == 6) {
		vec3 hang = p - up_dir * height * 0.75;   // (squashed up and down: the mats hang)
		float mat = coat_noise(hang * scale * 2.5) * 0.65 + coat_noise(hang * scale * 9.0) * 0.35;
		c = mix(color_a, color_b, smoothstep(0.32, 0.72, mat));
		c = mix(c, vec3(1.0, 0.86, 0.84), coat_rakes(p, scale));
	} else if (pattern == 7) {
		vec3 id;
		vec4 cell = coat_cells(p * scale + vec3(0.0, coat_noise(p * 2.0) * 0.8, 0.0), id);
		float vein = 1.0 - smoothstep(0.0, 0.05, cell.w);
		c = mix(color_a, color_b, max(vein, smoothstep(0.55, 0.9, coat_noise(p * scale * 0.6)) * 0.3));
	}
	ALBEDO = c;
}
