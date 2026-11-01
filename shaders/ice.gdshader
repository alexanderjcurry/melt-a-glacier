shader_type spatial;
// The glacier. Vertex colours carry the ice colour for each depth (with a
// little ambient occlusion baked in) and, in alpha, how much of the original
// snowy top is left. Everything else is done here from world position:
// patchy snow on top, glossy layered blue ice where you've carved, a dirty
// base near the ground, a wet glowing spot where the heat lands, and a faint
// blue glow at grazing angles.
render_mode diffuse_burley, specular_schlick_ggx;

uniform sampler2D detail_tex : filter_linear_mipmap, repeat_enable;
uniform vec3 heat_pos = vec3(0.0, -100.0, 0.0);
uniform float heat_amount = 0.0;
uniform float heat_radius = 0.9;                       // the tool's heat zone, metres
uniform vec3 heat_color = vec3(1.0, 0.45, 0.12);       // each tool glows its own colour
uniform float glow = 0.0;

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

// A contrast curve: keeps sunlit snow from washing out and makes carved ice a
// deeper, more saturated blue. (Not a colour-space conversion: the
// Compatibility renderer lights colours as they are.)
vec3 deepen(vec3 c) {
	return c * c * (c * 0.305 + 0.683) + c * 0.012;
}

vec3 tri(vec3 p, vec3 bw, float s) {
	return texture(detail_tex, p.zy * s).rgb * bw.x
		+ texture(detail_tex, p.xz * s).rgb * bw.y
		+ texture(detail_tex, p.xy * s).rgb * bw.z;
}

// Bump mapping from screen-space derivatives (no UVs or tangents needed).
vec3 bump(vec3 n, vec3 p, float h) {
	vec3 dpdx = dFdx(p);
	vec3 dpdy = dFdy(p);
	float dhdx = dFdx(h);
	float dhdy = dFdy(h);
	vec3 r1 = cross(dpdy, n);
	vec3 r2 = cross(n, dpdx);
	float det = dot(dpdx, r1);
	vec3 g = sign(det) * (dhdx * r1 + dhdy * r2);
	return normalize(abs(det) * n - g);
}

void fragment() {
	vec3 n = normalize(wnrm);
	vec3 bw = pow(abs(n), vec3(4.0));
	bw /= (bw.x + bw.y + bw.z);
	vec3 d = tri(wpos, bw, 0.09);          // r = grain, g = blotches, b = streaks
	float fine = tri(wpos, bw, 0.55).r;

	// Snow lies on the untouched, flatter parts of the top, in patches.
	float cover = COLOR.a * smoothstep(0.35, 0.75, n.y);
	float snow = smoothstep(0.4, 0.62, cover + (d.g - 0.5) * 0.7);

	// Exposed ice: blue, with thin darker layers and a little grit.
	vec3 ice = COLOR.rgb * vec3(0.95, 0.98, 1.0);
	float bands = sin(wpos.y * 6.0 + d.b * 6.0 + d.g * 2.0);
	ice *= 1.0 + 0.08 * bands;
	ice *= 0.88 + 0.22 * d.r;
	float grit = smoothstep(0.66, 0.85, d.g) * 0.25 + (1.0 - smoothstep(0.0, 1.2, wpos.y)) * 0.35 * smoothstep(0.35, 0.75, d.r + 0.15);
	ice = mix(ice, vec3(0.6, 0.58, 0.55), clamp(grit, 0.0, 0.45));
	// Snow: bright, a touch blue in the dips.
	vec3 snow_col = mix(vec3(0.8, 0.86, 0.95), vec3(0.93, 0.95, 0.98), clamp(fine * 1.3 - 0.1, 0.0, 1.0));
	vec3 col = deepen(mix(ice, snow_col, snow));

	// The heat: wet and glossy around where it lands, glowing at the centre.
	float hd = length(wpos - heat_pos);
	float wet = heat_amount * (1.0 - smoothstep(0.33 * heat_radius, 2.2 * heat_radius, hd));
	float hot = heat_amount * (1.0 - smoothstep(0.0, heat_radius, hd));
	col = mix(col, col * vec3(0.78, 0.88, 1.0), wet * 0.5);

	ALBEDO = col;
	ROUGHNESS = mix(mix(0.12, 0.35, d.r), 0.9, snow);
	ROUGHNESS = mix(ROUGHNESS, 0.04, wet);
	SPECULAR = mix(0.45, 0.25, snow);
	NORMAL = bump(NORMAL, VERTEX, (d.r * 0.05 + fine * 0.012) * (1.0 - wet * 0.7));

	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	vec3 sss = vec3(0.1, 0.35, 0.6) * fres * 0.18 * (1.0 - snow);
	float sparkle = smoothstep(0.8, 0.86, fine) * snow * step(0.6, fract(dot(VIEW, vec3(13.0, 7.0, 11.0)) + d.r * 3.0));
	EMISSION = sss + heat_color * hot * hot * 0.55 + vec3(1.0, 0.72, 0.3) * glow * 0.55 + vec3(sparkle) * 0.3;
}
