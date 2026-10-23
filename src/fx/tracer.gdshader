shader_type spatial;
// Carrot tracers: a camera-facing ribbon from the carrot back along its flight
// path, hot at the head and fading out at the tail. Never thinner than a few
// pixels, so a shot from far away still shows where it came from.
//
// The mesh is a strip with x = side (-1 / 1) and z = 0 at the head, 1 at the
// tail; each MultiMesh instance's basis Z is the trail (pointing backwards,
// trail-length long). INSTANCE_CUSTOM is the colour, alpha = strength.
// Opaque-ish (blend_mix), not additive: added light washes out to white
// against a bright sky or sunlit leaves.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, skip_vertex_transform, shadows_disabled, fog_disabled;

uniform float width = 0.14;        // metres, up close
uniform float min_pixels = 6.0;    // ...and at least this wide on screen
uniform vec3 core_colour : source_color = vec3(1.0, 0.85, 0.45);

varying vec4 tint;

void vertex() {
	vec3 p = (MODELVIEW_MATRIX * vec4(0.0, 0.0, VERTEX.z, 1.0)).xyz;
	vec3 axis = (MODELVIEW_MATRIX * vec4(0.0, 0.0, 1.0, 0.0)).xyz;
	vec3 side = cross(axis, p);
	side = length(side) > 1e-6 ? normalize(side) : vec3(1.0, 0.0, 0.0);
	float metres_per_pixel = -p.z * 2.0 / (PROJECTION_MATRIX[1][1] * VIEWPORT_SIZE.y);
	VERTEX = p + side * VERTEX.x * 0.5 * max(width, metres_per_pixel * min_pixels);
	NORMAL = vec3(0.0, 0.0, 1.0);
	tint = INSTANCE_CUSTOM;
}

void fragment() {
	float head = 1.0 - UV.y;
	float across = 1.0 - abs(UV.x * 2.0 - 1.0);   // 1 on the centre line
	ALBEDO = mix(tint.rgb, core_colour, smoothstep(0.45, 0.9, across) * head);
	ALPHA = clamp(sqrt(head) * smoothstep(0.0, 0.35, across) * tint.a, 0.0, 1.0);
}
