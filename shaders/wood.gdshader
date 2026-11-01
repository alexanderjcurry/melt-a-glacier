shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
// Painted wood for the shed, worked out from the world position so the
// meshes need no UVs. Vertex colour = the paint or stain. Vertex alpha picks
// the pattern: 1 = boards (floors and tops run along x, walls stand upright),
// 0.5 = roof shingles, 0.2 = pegboard, 0 = plain paint or metal.
// Colours are used as they are: the Compatibility renderer lights them in
// display space, like StandardMaterial3D's albedo.

uniform sampler2D detail_tex : filter_linear_mipmap, repeat_enable;
uniform float board_width = 0.19;

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float hash(float n) {
	return fract(sin(n * 12.9898) * 43758.5453);
}

void fragment() {
	vec3 n = normalize(wnrm);
	vec3 col = COLOR.rgb;
	float kind = COLOR.a;
	float rough = 0.8;
	if (kind > 0.75) {
		// p.x runs across the boards, p.y along them.
		bool is_flat = abs(n.y) > 0.6;
		vec2 p = is_flat ? vec2(wpos.z, wpos.x) : (abs(n.x) > abs(n.z) ? vec2(wpos.z, wpos.y) : vec2(wpos.x, wpos.y));
		float a = p.x / board_width;
		float idx = floor(a);
		float f = fract(a);
		float h = hash(idx);
		float seam = smoothstep(0.0, 0.05, f) * smoothstep(1.0, 0.95, f);
		if (is_flat) {
			// Floor boards end every couple of metres, staggered.
			float g = fract((p.y + h * 3.0) / 2.3);
			seam *= smoothstep(0.0, 0.012, g) * smoothstep(1.0, 0.988, g);
		}
		float grain = texture(detail_tex, vec2(p.x * 1.4 + h * 7.0, p.y * 0.11)).r;
		float fine = texture(detail_tex, vec2(p.x * 4.5 + h, p.y * 0.45)).b;
		col *= (0.86 + 0.26 * h) * (0.8 + 0.34 * grain) * (0.93 + 0.12 * fine);
		col *= mix(0.42, 1.0, seam);
	} else if (kind > 0.35) {
		// Shingles: rows stepping up the roof, joints staggered row to row.
		float r = wpos.y / 0.09;
		float ri = floor(r);
		float rf = fract(r);
		float x = (abs(n.x) > abs(n.z) ? wpos.z : wpos.x) / 0.34 + ri * 0.5;
		float xi = floor(x);
		float xf = fract(x);
		float h = hash(ri * 17.0 + xi);
		col *= 0.84 + 0.24 * h;
		col *= mix(0.55, 1.0, smoothstep(0.0, 0.3, rf));
		col *= mix(0.62, 1.0, smoothstep(0.0, 0.05, xf) * smoothstep(1.0, 0.95, xf));
		rough = 0.9;
	} else if (kind > 0.1) {
		// Pegboard: a grid of holes, fading to an even tone in the distance
		// so it doesn't shimmer.
		vec2 p = abs(n.z) > abs(n.x) ? wpos.xy : wpos.zy;
		vec2 g = p / 0.05;
		float d = length(fract(g) - 0.5);
		float blur = clamp(length(fwidth(g)) * 1.6 - 0.4, 0.0, 1.0);
		float hole = mix(smoothstep(0.13, 0.19, d), 0.88, blur);
		col *= mix(0.3, 1.0, hole);
		rough = 0.85;
	} else {
		float g = texture(detail_tex, wpos.xz * 0.37 + wpos.y * 0.21).r;
		col *= 0.93 + 0.12 * g;
		rough = 0.55;
	}
	ALBEDO = col;
	ROUGHNESS = rough;
	SPECULAR = 0.3;
}
