shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
// Rock with snow on the gentle high slopes, worked out per pixel so the snow
// line is crisp and patchy. Vertex colour = the rock's own tint; vertex alpha
// < 1 marks glowing lava (Kevin's streaks). Also used for boulders.
// Colours are used as they are: the Compatibility renderer lights them in
// display space, like StandardMaterial3D's albedo.

uniform sampler2D detail_tex : filter_linear_mipmap, repeat_enable;
uniform vec3 snow_color : source_color = vec3(0.84, 0.87, 0.92);
uniform vec3 foot_color : source_color = vec3(0.55, 0.46, 0.34);   // same as the valley floor
uniform float snow_line = 17.0;
uniform float foot_amount = 0.9;          // how much the bottom few metres take the floor colour
uniform vec3 lava_color : source_color = vec3(1.0, 0.42, 0.08);
uniform vec3 glacier_source = vec3(0.0, 0.0, -36.0);   // the snowfield the glacier comes from

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 n = normalize(wnrm);
	vec3 bw = pow(abs(n), vec3(4.0));
	bw /= bw.x + bw.y + bw.z;
	vec3 p = wpos * 0.045;
	vec3 d = texture(detail_tex, p.zy).rgb * bw.x
		+ texture(detail_tex, p.xz).rgb * bw.y
		+ texture(detail_tex, p.xy).rgb * bw.z;
	float fine = texture(detail_tex, wpos.xz * 0.31 + wpos.y * 0.13).r;

	vec3 rock = COLOR.rgb;
	rock *= 0.66 + 0.55 * d.r + 0.15 * fine;                    // grain
	rock *= 0.88 + 0.16 * sin(wpos.y * 1.4 + d.b * 6.0);         // strata
	rock = mix(rock, rock * vec3(1.08, 0.98, 0.9), d.g);         // warmer patches

	// Snow: on the gentle slopes above a ragged snow line, which drops low
	// around the snowfield that feeds the glacier.
	float source = 1.0 - smoothstep(8.0, 30.0, length(wpos.xz - glacier_source.xz));
	float line = snow_line + (d.g - 0.5) * 12.0 - source * 9.0;
	float high = smoothstep(line - 1.2, line + 1.2, wpos.y);
	float flat_enough = smoothstep(0.38, 0.6, n.y + (d.r - 0.5) * 0.35 + source * 0.25);
	float snow = high * flat_enough;
	// Valley floor colour (scree and grass) where the slopes meet the ground.
	float foot = 1.0 - smoothstep(0.4, 3.0, wpos.y + (d.g - 0.5) * 2.5);
	vec3 col = mix(rock, foot_color * (0.72 + 0.4 * d.r), foot * foot_amount);
	col = mix(col, snow_color * (0.9 + 0.1 * fine), snow);
	float lava = 1.0 - COLOR.a;
	vec3 hot = lava_color * (0.75 + 0.5 * fine);
	col = mix(col, hot, lava);

	ALBEDO = col;
	ROUGHNESS = mix(mix(0.93, 0.7, snow), 0.4, lava);
	SPECULAR = mix(0.25, 0.4, snow);
	EMISSION = hot * lava * 1.2;
}
