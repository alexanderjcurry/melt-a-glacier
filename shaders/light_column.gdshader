shader_type spatial;
// The orbital mirror's column of sunlight coming down from space (see
// tool_cone.gdshaderinc). Unlike the tools' flames it's hidden behind things
// that stand in front of it.
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

#include "res://shaders/tool_cone.gdshaderinc"
