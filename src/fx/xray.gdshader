// Seen through walls (your Pack Sense boon, CritterVisual.reveal): a hot red
// glow over the whole critter, strongest at its outline, drawn over whatever
// is in the way. Additive, as material_overlay.
shader_type spatial;
render_mode blend_add, unshaded, cull_back, depth_draw_never, depth_test_disabled, shadows_disabled;

uniform vec3 color : source_color = vec3(1.0, 0.28, 0.2);

void fragment() {
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 1.5);
	float pulse = 0.85 + 0.15 * sin(TIME * 8.0);
	ALBEDO = color * (0.22 + 0.9 * rim) * pulse;
}
