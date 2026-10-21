// Grass, flowers, ferns: the model's own PBR textures plus wind. Sway grows
// with height above the model's base so roots stay planted; each instance
// gets its own phase from its world position. Critters brushing past push
// the blades aside (player_pos).
shader_type spatial;
render_mode blend_mix, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool use_normal = false;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform float roughness = 0.8;
uniform float alpha_scissor = 0.4;
uniform float model_height = 1.0;
uniform float wind_strength = 0.12;
uniform float wind_speed = 1.6;
uniform vec2 wind_dir = vec2(0.8, 0.6);
uniform vec3 player_pos = vec3(0.0, -1000.0, 0.0);
uniform float push_radius = 1.2;
uniform float translucency = 0.35;

void vertex() {
	vec3 origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float h = clamp(VERTEX.y / max(model_height, 0.01), 0.0, 1.0);
	float bend = h * h;
	float phase = dot(origin.xz, vec2(0.37, 0.21));
	float gust = sin(TIME * wind_speed + phase) * 0.6 + sin(TIME * wind_speed * 2.3 + phase * 1.7) * 0.25;
	vec3 world_off = vec3(wind_dir.x, 0.0, wind_dir.y) * gust * wind_strength * model_height * bend;
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 away = wp - player_pos;
	away.y = 0.0;
	float d = length(away);
	float push = smoothstep(push_radius, 0.0, d) * bend;
	world_off += normalize(away + vec3(0.001, 0.0, 0.0)) * push * 0.5 * model_height;
	world_off.y -= push * 0.2 * model_height;
	VERTEX += (inverse(MODEL_MATRIX) * vec4(world_off, 0.0)).xyz;
}

void fragment() {
	vec4 c = texture(albedo_tex, UV) * albedo_color;
	ALBEDO = c.rgb;
	// leaves right in front of the camera dissolve (screen-door) instead of
	// filling the view; VERTEX is view-space here, so its length is the distance
	float cam_d = length(VERTEX);
	float keep = smoothstep(0.5, 1.6, cam_d);
	float dither = fract(sin(dot(floor(FRAGCOORD.xy), vec2(12.9898, 78.233))) * 43758.5453);
	ALPHA = c.a * step(dither, keep);
	ALPHA_SCISSOR_THRESHOLD = alpha_scissor;
	ROUGHNESS = roughness;
	// double-sided cards: light the back face as if it faced the camera,
	// otherwise leaves seen from behind/above render almost black
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
	if (use_normal) {
		NORMAL_MAP = texture(normal_tex, UV).rgb;
	}
	BACKLIGHT = c.rgb * translucency;
}
