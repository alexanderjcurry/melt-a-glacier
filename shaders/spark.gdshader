shader_type spatial;
// Sparks, embers and wind streaks (ToolFx): a soft dot stretched out along the
// way it's flying. The particles use particle_flag_align_y, so each one's Y axis
// points along its velocity; here the quad is laid along that and turned round
// it to face the camera.
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled, world_vertex_coords;

uniform float stretch = 5.0;   // how many times longer than wide
uniform sampler2D tex : source_color, filter_linear_mipmap;

void vertex() {
	vec3 c = MODEL_MATRIX[3].xyz;
	vec3 ax = MODEL_MATRIX[1].xyz;
	float s = length(MODEL_MATRIX[0].xyz);
	vec3 along = ax / max(length(ax), 1e-5);
	vec3 side = cross(along, CAMERA_POSITION_WORLD - c);
	side = side / max(length(side), 1e-5);
	VERTEX = c + side * (UV.x - 0.5) * s + along * (0.5 - UV.y) * s * stretch;
}

void fragment() {
	ALBEDO = COLOR.rgb;
	ALPHA = COLOR.a * texture(tex, UV).a;
}
