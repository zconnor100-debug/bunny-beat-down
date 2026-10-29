// What the coats share (coat_tint.gdshader, coat_glow.gdshader): random
// numbers, smooth noise and Voronoi cells, all in the model's own space, in
// metres (each model comes in its own units), with the world's up in it (a
// model can lie on its side in its file).

// A vertex in metres, in the model's own frame (call from vertex()).
vec3 coat_place(vec3 vertex, mat4 model) {
	return vertex * length(model[0].xyz);
}

// The world's up, in the model's own frame.
vec3 coat_up(mat4 model) {
	return normalize(vec3(model[0].y, model[1].y, model[2].y));
}

// The patchwork's patches: the island's moss, the Hamster Cage's pink and
// teal, the Toy Box's red, blue and yellow.
const vec3 COAT_PATCHES[6] = vec3[6](vec3(0.5, 0.74, 0.32), vec3(1.0, 0.62, 0.76), vec3(0.42, 0.84, 0.84),
	vec3(0.92, 0.3, 0.24), vec3(0.36, 0.52, 0.96), vec3(1.0, 0.84, 0.3));

// A patch's colour, from its cell's random numbers.
vec3 coat_patch(vec3 rnd) {
	return COAT_PATCHES[min(int(rnd.x * 6.0), 5)];
}

vec3 coat_hash3(vec3 p) {
	p = vec3(dot(p, vec3(127.1, 311.7, 74.7)), dot(p, vec3(269.5, 183.3, 246.1)), dot(p, vec3(113.5, 271.9, 124.6)));
	return fract(sin(p) * 43758.5453);
}

float coat_noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n000 = coat_hash3(i).x;
	float n100 = coat_hash3(i + vec3(1, 0, 0)).x;
	float n010 = coat_hash3(i + vec3(0, 1, 0)).x;
	float n110 = coat_hash3(i + vec3(1, 1, 0)).x;
	float n001 = coat_hash3(i + vec3(0, 0, 1)).x;
	float n101 = coat_hash3(i + vec3(1, 0, 1)).x;
	float n011 = coat_hash3(i + vec3(0, 1, 1)).x;
	float n111 = coat_hash3(i + vec3(1, 1, 1)).x;
	return mix(mix(mix(n000, n100, f.x), mix(n010, n110, f.x), f.y), mix(mix(n001, n101, f.x), mix(n011, n111, f.x), f.y), f.z);
}

// The nearest cell's centre (xyz: its offset from p) and the distances to the
// nearest two (w: the gap between them, 0 on a cell's edge).
vec4 coat_cells(vec3 p, out vec3 cell_id) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	float d1 = 8.0;
	float d2 = 8.0;
	vec3 near = vec3(0.0);
	cell_id = i;
	for (int x = -1; x <= 1; x++) {
		for (int y = -1; y <= 1; y++) {
			for (int z = -1; z <= 1; z++) {
				vec3 o = vec3(float(x), float(y), float(z));
				vec3 r = o + coat_hash3(i + o) - f;
				float d = dot(r, r);
				if (d < d1) {
					d2 = d1;
					d1 = d;
					near = r;
					cell_id = i + o;
				} else if (d < d2) {
					d2 = d;
				}
			}
		}
	}
	return vec4(near, sqrt(d2) - sqrt(d1));
}
