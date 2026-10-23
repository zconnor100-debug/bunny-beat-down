// The rewind look: the screen as an old tape running backwards. Rolling
// tracking bands, jittery lines, colour fringes, scanlines, a cyan cast.
// `amount` fades it in and out.
shader_type canvas_item;

uniform float amount : hint_range(0.0, 1.0) = 1.0;
uniform sampler2D screen : hint_screen_texture, filter_linear_mipmap;

float hash(float n) {
	return fract(sin(n) * 43758.5453);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	float line = floor(uv.y * 160.0);
	// lines slip sideways a little, and a tracking band rolls up the screen
	float jitter = (hash(line + floor(TIME * 30.0) * 7.0) - 0.5) * 0.008;
	float band = smoothstep(0.0, 0.04, fract(uv.y * 1.5 + TIME * 0.9)) * smoothstep(0.1, 0.06, fract(uv.y * 1.5 + TIME * 0.9));
	uv.x += (jitter + band * 0.03) * amount;
	float fringe = 0.004 * amount;
	vec3 c = vec3(texture(screen, uv + vec2(fringe, 0.0)).r, texture(screen, uv).g, texture(screen, uv - vec2(fringe, 0.0)).b);
	c *= mix(1.0, 0.82 + 0.18 * sin(SCREEN_UV.y * 900.0), amount);
	c += band * 0.25 * amount;
	c = mix(c, c * vec3(0.72, 1.0, 1.18) + vec3(0.0, 0.035, 0.07), 0.65 * amount);
	COLOR = vec4(c, 1.0);
}
