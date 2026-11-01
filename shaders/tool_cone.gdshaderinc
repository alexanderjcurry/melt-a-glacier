// A soft glowing cone of heat or light (ToolFx): a torch's flame, the jet
// reaching out to the ice, the heat lamp's light, the orbital mirror's column
// of sunlight. Shared by tool_cone.gdshader and light_column.gdshader.
//
// The mesh is a unit tube: VERTEX.xy is round the tube, UV.x goes round it and
// UV.y runs 0 (start) .. 1 (end). Here it becomes a cone `len` long down the
// node's -Z, r0 wide at the start and r1 at the end (fatter in the middle with
// `bulge`, like a flame). It's densest where you look through the thick of it
// and fades out towards its edges, so it reads as a glowing volume from any
// side, not a flat sheet. Cloudy noise rushes along it.

uniform float len = 4.0;
uniform float r0 = 0.05;
uniform float r1 = 1.0;
uniform float bulge = 0.0;
uniform vec3 color_start : source_color = vec3(1.0, 0.9, 0.6);
uniform vec3 color_end : source_color = vec3(1.0, 0.5, 0.1);
uniform float strength = 0.6;
uniform float soft_edge = 0.3;    // how gently it fades out towards its edges
uniform float fade_in = 0.05;     // share of the length it takes to fade in
uniform float fade_out = 0.75;    // where it starts to fade out (keep below 1)
uniform float noise_amount = 0.5;
uniform float noise_scale = 0.35; // how big the clouds in it are (per metre along it)
uniform float scroll = 3.0;       // how fast they rush along it, m/s
uniform float stripes = 0.0;      // rays of light along it
uniform float whiten = 0.0;       // white-hot where it's thickest
uniform sampler2D noise : repeat_enable, filter_linear_mipmap;

varying float t;

void vertex() {
	t = UV.y;
	float r = mix(r0, r1, t) + bulge * sin(t * PI);
	vec2 around = VERTEX.xy;
	VERTEX = vec3(around * r, -t * len);
	NORMAL = normalize(vec3(around * len, r1 - r0));
}

void fragment() {
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float a = strength * smoothstep(0.0, soft_edge, facing);
	float n = texture(noise, vec2(UV.x * 2.0, (t * len - TIME * scroll) * noise_scale)).r;
	a *= mix(1.0, 0.2 + 1.6 * n, noise_amount);
	if (stripes > 0.0) {
		float s = texture(noise, vec2(UV.x * 4.0, 0.37 + TIME * 0.015)).r;
		a *= mix(1.0, 0.15 + 1.8 * s * s, stripes);
	}
	a *= smoothstep(0.0, max(fade_in, 0.0001), t) * (1.0 - smoothstep(fade_out, 1.0, t));
	vec3 col = mix(color_start, color_end, t);
	ALBEDO = mix(col, vec3(1.0), clamp(whiten * n * (1.0 - t), 0.0, 1.0));
	ALPHA = clamp(a, 0.0, 1.0);
}
