// Overlay for Golden-rarity guns: a warm metallic sheen plus a slow glint that
// sweeps along the gun. Additive on top of the gun's own PBR material, so it
// works on any single-atlas model.
shader_type spatial;
render_mode blend_add, unshaded, cull_back, depth_draw_never;

uniform vec3 gold : source_color = vec3(1.0, 0.72, 0.22);

varying vec3 local_pos;

void vertex() {
	local_pos = VERTEX;
}

void fragment() {
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.5);
	float sweep = smoothstep(0.92, 1.0, sin(local_pos.z * 9.0 - TIME * 2.4) * 0.5 + 0.5);
	ALBEDO = gold * (0.16 + fres * 0.55 + sweep * 0.45);
}
