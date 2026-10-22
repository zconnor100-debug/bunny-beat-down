// Overlay that makes enemy critters pop out of the foliage: a warm additive
// rim light on the silhouette (strongest where the surface turns away from the
// camera), with a gentle pulse. Applied as material_overlay, so it works on top
// of any model/skin.
shader_type spatial;
render_mode blend_add, unshaded, cull_back, depth_draw_never, shadows_disabled;

uniform vec3 rim_color : source_color = vec3(1.0, 0.32, 0.16);
uniform float strength = 0.95;
uniform float power = 2.2;

void fragment() {
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), power);
	float pulse = 0.85 + 0.15 * sin(TIME * 3.0);
	ALBEDO = rim_color * rim * strength * pulse;
}
