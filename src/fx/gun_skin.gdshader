shader_type spatial;
// A Workshop gun skin, drawn over the gun's own materials (material_overlay):
// a tint or a pattern in the model's own space, so it sits still on the gun.
//   pattern 0 tint, 1 camo blotches, 2 candy stripes, 3 frost (with
//   sparkles), 4 gilded metal.
render_mode blend_mix, depth_draw_never, cull_back;

uniform int pattern = 0;
uniform vec4 color_a : source_color = vec4(1.0);
uniform vec4 color_b : source_color = vec4(1.0);
uniform vec4 color_c : source_color = vec4(1.0);
uniform float strength = 0.85;
uniform float metallic_v = 0.0;
uniform float roughness_v = 0.5;
uniform float pattern_scale = 18.0;

varying vec3 obj;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x), mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x), mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void vertex() {
	obj = VERTEX;
}

void fragment() {
	vec3 col = color_a.rgb;
	vec3 p = obj * pattern_scale;
	if (pattern == 1) {
		float n = noise(p) * 0.6 + noise(p * 2.3) * 0.4;
		col = n < 0.42 ? color_a.rgb : (n < 0.6 ? color_b.rgb : color_c.rgb);
	} else if (pattern == 2) {
		float s = fract((obj.x + obj.y * 0.8 + obj.z) * pattern_scale * 0.5);
		col = s < 0.5 ? color_a.rgb : color_b.rgb;
	} else if (pattern == 3) {
		col = mix(color_a.rgb, color_b.rgb, noise(p));
		EMISSION = vec3(step(0.9, noise(p * 7.0))) * 0.5;
	} else if (pattern == 4) {
		col = mix(color_a.rgb, color_b.rgb, noise(p * 0.5) * 0.6);
	}
	ALBEDO = col;
	METALLIC = metallic_v;
	ROUGHNESS = roughness_v;
	ALPHA = strength;
}
