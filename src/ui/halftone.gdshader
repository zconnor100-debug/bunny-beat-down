// A photo printed in the Warren Gazette (GazettePanel): newsprint halftone,
// the picture's light and dark turned into a screen of ink dots on the
// paper, finer in the light and running together in the shadows, on a
// screen turned 45 degrees like a real press's.
shader_type canvas_item;

uniform float dots_across = 150.0;
uniform vec4 ink : source_color = vec4(0.17, 0.13, 0.09, 1.0);
uniform vec4 paper : source_color = vec4(0.95, 0.91, 0.82, 1.0);
uniform float contrast = 1.35;

void fragment() {
	vec3 c = texture(TEXTURE, UV).rgb;
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	l = clamp((l - 0.5) * contrast + 0.55, 0.0, 1.0);
	float aspect = TEXTURE_PIXEL_SIZE.x / TEXTURE_PIXEL_SIZE.y;   // (height over width)
	vec2 p = UV * vec2(dots_across, dots_across * aspect);
	p = mat2(vec2(0.7071, 0.7071), vec2(-0.7071, 0.7071)) * p;
	vec2 cell = fract(p) - 0.5;
	float r = sqrt(1.0 - l) * 0.72;   // (a dot's radius: its share of ink)
	float d = length(cell);
	float aa = fwidth(d) * 1.2;
	float dot_ink = 1.0 - smoothstep(r - aa, r + aa, d);
	COLOR = vec4(mix(paper.rgb, ink.rgb, clamp(dot_ink * 0.88 + (1.0 - l) * 0.12, 0.0, 1.0)), 1.0);
}
