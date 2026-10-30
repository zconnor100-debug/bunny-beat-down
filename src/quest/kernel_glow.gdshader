shader_type spatial;
render_mode unshaded, blend_add, cull_back, depth_draw_never;
// The Starfall Acorn's light shining out of something it has got into (a
// glowing carrot: GlowCarrot), drawn over it: its gold-green, strongest round
// the edges, veins of it crawling over the surface, and a slow pulse.

uniform vec4 glow : source_color = vec4(0.8, 1.0, 0.34, 1.0);
uniform float strength = 1.0;
uniform float pulse_speed = 3.0;

void fragment() {
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 1.6);
	vec3 p = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float wave = sin(p.y * 11.0 + sin(p.x * 7.0 + TIME * 0.7) * 1.6 + sin(p.z * 6.0 - TIME * 0.5) * 1.3);
	float vein = smoothstep(0.86, 1.0, abs(wave));
	float pulse = 0.78 + 0.22 * sin(TIME * pulse_speed);
	ALBEDO = glow.rgb * strength * (0.18 + rim * 1.3 + vein * 0.9) * pulse;
}
