shader_type spatial;
// A glowing ribbon of heat from a tool's nozzle to where it lands (ToolFx).
// The mesh is a strip (UV.x across, UV.y = 0..1 along) on a node that's never
// moved. Each vertex is placed in the world here, along the beam and turned to
// face the camera, so
// it looks like a soft glowing stream from any angle. It widens from r0 at
// the nozzle to r1 at the far end (the tool's heat zone). It's see-through
// colour rather than added light, so it still shows up against bright snow.
// No depth test: the nozzle is a bit below your eye, so on a bulging slope the
// straight line to the spot you're aiming at dips into the snow on the way.
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, depth_test_disabled, shadows_disabled, fog_disabled, world_vertex_coords;

uniform vec3 start = vec3(0.0);
uniform vec3 dir = vec3(0.0, 0.0, -1.0);
uniform float len = 5.0;
uniform float r0 = 0.05;
uniform float r1 = 1.0;
uniform vec3 color_near : source_color = vec3(1.0, 0.8, 0.5);
uniform vec3 color_far : source_color = vec3(1.0, 0.4, 0.1);
uniform float strength = 0.5;
uniform float core = 0.0;         // a white-hot thin line down the middle
uniform float fade_in = 0.06;     // share of the length it takes to fade in at the nozzle
uniform float fade_out = 0.8;     // where it starts to fade out at the far end
uniform float waves = 0.0;        // ripples of hot air moving out (hair dryer)
uniform float rays = 0.0;         // streaks of light along it (heat lamp, sunbeam)
uniform float flicker = 0.0;      // flames
uniform float scroll = 4.0;       // how fast the pattern travels along it, m/s

varying float t;
varying float across;
varying float along;

void vertex() {
	t = UV.y;
	across = UV.x * 2.0 - 1.0;
	along = t * len;
	vec3 p = start + dir * along;
	vec3 to_cam = CAMERA_POSITION_WORLD - p;
	vec3 side = cross(dir, to_cam);
	if (dot(side, side) < 1e-8) {
		side = INV_VIEW_MATRIX[0].xyz;
	}
	p += normalize(side) * across * mix(r0, r1, t);
	VERTEX = p;
}

void fragment() {
	float x = abs(across);
	float soft = 1.0 - x * x;
	float a = strength * soft * (0.55 + 0.45 * soft);
	float c = core * exp(-x * x * 40.0);
	float ends = smoothstep(0.0, max(fade_in, 0.0001), t) * (1.0 - smoothstep(fade_out, 1.0, t));
	if (waves > 0.0) {
		// Bands of shimmering hot air rolling out from the nozzle, a little wobbly.
		float w = 0.5 + 0.5 * sin(along * 6.0 - TIME * scroll * 2.5 + sin(across * 2.5 + TIME * 4.0) * 1.3);
		a *= mix(1.0, 0.35 + 1.3 * w * w, waves);
	}
	if (rays > 0.0) {
		float r = 0.5 + 0.5 * sin(across * 9.0 + sin(along * 0.5 - TIME * 0.9) * 1.5);
		a *= mix(1.0, 0.4 + 1.0 * r * r, rays);
	}
	if (flicker > 0.0) {
		float f = sin(TIME * 31.0 + along * 1.7) * 0.5 + sin(TIME * 17.0 - along * 2.9 + across * 3.0) * 0.5;
		a *= 1.0 + flicker * 0.4 * f;
	}
	a = max(a, 0.0) * ends;
	c *= ends;
	ALBEDO = mix(mix(color_near, color_far, t), vec3(1.0), clamp(c, 0.0, 1.0));
	ALPHA = clamp(a + c, 0.0, 1.0);
}
