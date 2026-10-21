// Lake/sea water: two scrolling normal maps, depth-tinted colour read from
// the depth buffer, Fresnel reflection of the sky, and soft shoreline foam.
shader_type spatial;
render_mode blend_mix, cull_back, depth_draw_always, diffuse_burley, specular_schlick_ggx;

uniform sampler2D normal_a : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D depth_texture : hint_depth_texture, filter_linear_mipmap;
uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform vec3 shallow_color : source_color = vec3(0.32, 0.55, 0.5);
uniform vec3 deep_color : source_color = vec3(0.04, 0.17, 0.22);
uniform vec3 foam_color : source_color = vec3(0.92, 0.95, 0.93);
uniform float depth_fade = 3.5;
uniform float tile = 14.0;
uniform float speed = 0.03;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// gentle swell
	VERTEX.y += sin(world_pos.x * 0.15 + TIME * 0.9) * 0.04 + cos(world_pos.z * 0.12 + TIME * 0.7) * 0.04;
}

void fragment() {
	vec2 uv = world_pos.xz / tile;
	vec3 n1 = texture(normal_a, uv + vec2(TIME * speed, TIME * speed * 0.6)).rgb;
	vec3 n2 = texture(normal_a, uv * 0.47 - vec2(TIME * speed * 0.7, -TIME * speed * 0.4)).rgb;
	NORMAL_MAP = normalize(mix(n1, n2, 0.5));
	NORMAL_MAP_DEPTH = 0.6;

	float depth_raw = texture(depth_texture, SCREEN_UV).r;
	vec4 ndc = vec4(SCREEN_UV * 2.0 - 1.0, depth_raw, 1.0);
	vec4 view = INV_PROJECTION_MATRIX * ndc;
	view.xyz /= view.w;
	float water_depth = clamp(VERTEX.z - view.z, 0.0, 100.0);
	float t = clamp(water_depth / depth_fade, 0.0, 1.0);

	vec3 refr = texture(screen_texture, SCREEN_UV + NORMAL_MAP.xy * 0.01 * (1.0 - t)).rgb;
	vec3 col = mix(shallow_color, deep_color, t);
	col = mix(refr * shallow_color * 1.6, col, smoothstep(0.0, 0.6, t));
	float foam = smoothstep(0.35, 0.0, water_depth) * (0.6 + 0.4 * sin(TIME * 2.0 + world_pos.x * 0.8));
	col = mix(col, foam_color, foam * 0.7);

	ALBEDO = col;
	ROUGHNESS = 0.04;
	METALLIC = 0.0;
	SPECULAR = 0.6;
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	ALPHA = clamp(mix(0.82, 1.0, fresnel) * smoothstep(0.0, 0.25, water_depth) + foam * 0.3, 0.0, 1.0);
}
