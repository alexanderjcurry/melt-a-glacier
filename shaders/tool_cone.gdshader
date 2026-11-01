shader_type spatial;
// A tool's flame or beam, from its nozzle to the ice (see tool_cone.gdshaderinc).
// No depth test: the nozzle is a bit below your eye, so on a bulging slope the
// straight line to the spot you're aiming at dips into the snow on the way.
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, depth_test_disabled, shadows_disabled, fog_disabled;

#include "res://shaders/tool_cone.gdshaderinc"
