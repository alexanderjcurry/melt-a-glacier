shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
// Glacier meltwater: milky turquoise, darker where it's deep, with moving
// ripples. still = 1 for the lake; 0 for the stream, which flows along UV.y.
// Vertex alpha = depth (0 at the shore, 1 in the deep middle).

uniform sampler2D ripples : filter_linear_mipmap, repeat_enable;
uniform float still = 1.0;
uniform vec3 shallow_color : source_color = vec3(0.42, 0.72, 0.74);
uniform vec3 deep_color : source_color = vec3(0.1, 0.36, 0.5);

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float height(vec2 p, float lake) {
	// p is world x/z on the lake, or (across, along) on the stream.
	vec2 a = lake > 0.5 ? p * 0.09 + TIME * vec2(0.012, 0.007) : vec2(p.x * 0.35, p.y * 0.18 - TIME * 0.55);
	vec2 b = lake > 0.5 ? p * 0.21 - TIME * vec2(0.009, 0.015) : vec2(p.x * 0.6 + 0.3, p.y * 0.33 - TIME * 0.9);
	return texture(ripples, a).r * 0.6 + texture(ripples, b).r * 0.4;
}

void fragment() {
	float depth = COLOR.a;
	vec2 p = still > 0.5 ? wpos.xz : UV;
	float e = 0.15;
	float h = height(p, still);
	float hx = height(p + vec2(e, 0.0), still);
	float hz = height(p + vec2(0.0, e), still);
	float k = still > 0.5 ? 0.9 : 1.6;
	vec3 wn = normalize(vec3(-(hx - h) / e * k, 1.0, -(hz - h) / e * k));
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);

	vec3 col = mix(shallow_color, deep_color, smoothstep(0.0, 0.8, depth));
	col *= 0.92 + 0.16 * h;
	if (still < 0.5) {
		// White water along the stream's edges and in fast streaks.
		float edge = 1.0 - smoothstep(0.0, 0.22, min(UV.x, 1.0 - UV.x));
		float foam = smoothstep(0.66, 0.85, h) * 0.35 + edge * 0.3;
		col = mix(col, vec3(0.62, 0.7, 0.72), clamp(foam, 0.0, 0.5));
	} else {
		col = mix(col, vec3(0.8, 0.86, 0.84), (1.0 - smoothstep(0.0, 0.06, depth)) * 0.6);   // pale shallows
	}
	ALBEDO = col;
	ROUGHNESS = 0.06;
	SPECULAR = 0.55;
}
