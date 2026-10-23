// The hamster tank's glass walls: nearly clear, brighter at grazing angles
// (so you can tell where the wall is), a few faint smudges, and frost that
// creeps up the panes near the open fridge.
shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_never, diffuse_burley, specular_schlick_ggx;

uniform vec3 tint : source_color = vec3(0.86, 0.95, 1.0);
uniform float base_alpha = 0.03;
uniform vec3 frost_center = vec3(420.0, 0.0, -400.0);
uniform float frost_radius = 300.0;
uniform float frost_height = 110.0;
uniform sampler2D smudge_tex : filter_linear_mipmap, repeat_enable;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float fres = pow(1.0 - abs(dot(NORMAL, VIEW)), 3.0);
	vec2 uv = vec2(world_pos.x + world_pos.z, world_pos.y) * 0.004;
	float smudge = texture(smudge_tex, uv).r;
	float near = smoothstep(frost_radius, frost_radius * 0.25, distance(world_pos.xz, frost_center.xz));
	float frost = near * smoothstep(frost_height, frost_height * 0.2, world_pos.y + smudge * 40.0);
	frost *= smoothstep(0.25, 0.6, smudge + near * 0.4);
	ALBEDO = mix(tint, vec3(0.94, 0.97, 1.0), frost);
	ROUGHNESS = mix(0.04, 0.55, frost);
	SPECULAR = 0.7;
	ALPHA = clamp(base_alpha + fres * 0.14 + smoothstep(0.55, 0.9, smudge) * 0.04 + frost * 0.8, 0.0, 0.92);
}
