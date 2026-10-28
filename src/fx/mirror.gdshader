// The Doppelbunny's look (DoppelBrain.look): a cracked mirror over your own
// critter. A cold silver rim on the silhouette, and a web of hairline cracks
// across it (the edges of Voronoi cells in the model's own space, so they stay
// put on it as it moves) that glint in a slow sweep, with now and then the
// brief flash of a bad reflection. Additive, as material_overlay, so it goes
// over any fur, skin or outfit piece. Also your Mended Mirror coat
// (Workshop.coat_material): the cracks mended in gold, a softer rim and no
// flashes.
shader_type spatial;
render_mode blend_add, unshaded, cull_back, depth_draw_never, shadows_disabled;

uniform vec3 rim_color : source_color = vec3(0.72, 0.86, 1.0);
uniform vec3 crack_color : source_color = vec3(0.9, 0.97, 1.0);
uniform float cells = 7.0;            // cracks per metre, about
uniform float crack_width = 0.05;
uniform float rim_strength = 1.1;
uniform float flashes = 1.0;          // 0: never a bad reflection

varying vec3 model_pos;

void vertex() {
	model_pos = VERTEX;
}

vec3 hash3(vec3 p) {
	p = vec3(dot(p, vec3(127.1, 311.7, 74.7)), dot(p, vec3(269.5, 183.3, 246.1)), dot(p, vec3(113.5, 271.9, 124.6)));
	return fract(sin(p) * 43758.5453);
}

// How far from a crack: the gap between the nearest two cell centres (0 on an edge).
float crack(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	float d1 = 8.0;
	float d2 = 8.0;
	for (int x = -1; x <= 1; x++) {
		for (int y = -1; y <= 1; y++) {
			for (int z = -1; z <= 1; z++) {
				vec3 o = vec3(float(x), float(y), float(z));
				vec3 r = o + hash3(i + o) - f;
				float d = dot(r, r);
				if (d < d1) {
					d2 = d1;
					d1 = d;
				} else if (d < d2) {
					d2 = d;
				}
			}
		}
	}
	return sqrt(d2) - sqrt(d1);
}

void fragment() {
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	float edge = 1.0 - smoothstep(0.0, crack_width, crack(model_pos * cells));
	float sweep = 0.5 + 0.5 * sin(TIME * 2.3 - model_pos.y * 9.0);
	float flash = step(0.94, fract(sin(floor(TIME * 8.0) * 12.9898) * 43758.5453));
	ALBEDO = rim_color * rim * rim_strength + crack_color * edge * (0.3 + 0.7 * sweep) + rim_color * flash * flashes * (0.15 + 0.35 * rim);
}
