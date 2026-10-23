// Overlay for lucky clovers: a soft green glow that breathes, brightest at the
// rim, bright enough to bloom (HDR) so a clover reads from across a meadow.
// Additive on top of the clover's own material.
shader_type spatial;
render_mode blend_add, unshaded, cull_back, depth_draw_never;

uniform vec3 glow : source_color = vec3(0.3, 1.0, 0.35);
uniform float strength = 1.6;

void fragment() {
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	float pulse = 0.75 + 0.25 * sin(TIME * 2.6);
	ALBEDO = glow * strength * pulse * (0.35 + fres * 1.4);
}
