// Cut log ends (Building's models): growth rings round the log's heart. UV
// is the offset from the log's axis in metres (tools/maps/island.py), so the
// rings sit right on every log, big or small.
shader_type spatial;
render_mode blend_mix, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec3 sapwood : source_color = vec3(0.8, 0.64, 0.43);
uniform vec3 ring_colour : source_color = vec3(0.56, 0.39, 0.23);
uniform float rings_per_metre = 28.0;

void fragment() {
	float r = length(UV);
	float a = atan(UV.y, UV.x);
	float d = r * rings_per_metre + 0.3 * sin(a * 3.0 + r * 9.0) + 0.15 * sin(a * 7.0);
	float f = fract(d);
	float ring = smoothstep(0.62, 0.8, f) * smoothstep(1.0, 0.84, f);
	vec3 col = mix(sapwood, ring_colour, ring * 0.75);
	col = mix(col, ring_colour * 0.85, smoothstep(0.09, 0.0, r) * 0.6);   // the heart
	ALBEDO = col;
	ROUGHNESS = 0.85;
}
