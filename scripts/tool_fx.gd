class_name ToolFx
extends Node3D
## What comes out of the tool in your hand, drawn from its nozzle to where the
## heat lands. Every tool looks different: the hair dryer blows wavy hot air,
## the heat lamp shines a warm glow, the blowtorch has a hard blue flame, the
## flamethrower roars, the lava hose pours lava, and the orbital mirror brings
## a sunbeam down from space. Your upgrades show too: Wider Nozzle makes the
## stream wider where it lands, Longer Reach lets it go further, and Heat
## Output makes it brighter, denser and hotter.
## The player calls update() every physics frame.

const BEAM_SHADER := preload("res://shaders/heat_beam.gdshader")
const SUN_DIR := Vector3(0.32, 1.0, 0.18)    # where the orbital mirror's sunbeam comes from
# The colour the ice glows where each tool's heat lands.
const GLOW := [Color(1.0, 0.62, 0.45), Color(1.0, 0.62, 0.25), Color(0.45, 0.62, 1.0),
	Color(1.0, 0.45, 0.12), Color(1.0, 0.34, 0.05), Color(1.0, 0.86, 0.5)]

var _stream: CPUParticles3D        # what flies out of the nozzle
var _extra: CPUParticles3D         # sparks, embers, glitter riding along with it
var _splash: CPUParticles3D        # what happens where it lands
var _beam: MeshInstance3D          # a soft glowing ribbon from the nozzle to the ice
var _sky: MeshInstance3D           # the orbital mirror's sunbeam
var _tip: MeshInstance3D           # a glow at the nozzle
var _light: OmniLight3D
var _style: Dictionary = {}
var _built := ""                   # which tool and upgrade levels the effects were built for
var _t := 0.0
var _on := 0.0                     # fades the glow in and out


func update(active: bool, from: Vector3, to: Vector3, hit: bool, normal: Vector3, delta: float) -> void:
	## active: the melt button is held. from: the nozzle. to: where it lands
	## (the ice, or as far as the tool reaches). hit: it's landing on ice.
	var tool_i: int = GameState.tool_index
	var gold: bool = GameState.golden_equipped and tool_i == 0
	var key := "%d/%s/%d/%d" % [tool_i, gold, int(GameState.upgrade_levels.get("nozzle", 0)), int(GameState.upgrade_levels.get("heat", 0))]
	if key != _built:
		_build(tool_i, gold)
		_built = key
	_t += delta
	_on = move_toward(_on, 1.0 if active else 0.0, delta * (8.0 if active else 5.0))
	var s := _style
	var d := to - from
	var dist := maxf(d.length(), 0.05)
	var dir := d / dist
	var radius: float = GameState.tool_radius()
	var heat: float = s.heat
	_stream.emitting = active
	if _extra != null:
		_extra.emitting = active
	if _splash != null:
		_splash.emitting = active and hit
	if active:
		# Point the stream at the target (lava falls, so it aims a little high).
		var speed: float = s.speed
		var life := clampf(dist / speed, 0.05, 3.0)
		var aim := dir
		if s.has("fall"):
			var drop := 0.5 * float(s.fall) * life * life
			aim = (to + Vector3(0.0, drop, 0.0) - from).normalized()
		var wob: float = s.get("wobble", 0.0)
		var basis := _facing(aim)
		if wob > 0.0:   # hot air wanders about
			basis = basis * Basis(Vector3.RIGHT, sin(_t * 6.3) * wob) * Basis(Vector3.UP, sin(_t * 4.1 + 1.3) * wob)
		_stream.global_transform = Transform3D(basis, from)
		_stream.lifetime = life
		_stream.spread = clampf(rad_to_deg(atan2(radius * float(s.spread), dist)), 1.0, 60.0)
		if _extra != null:
			_extra.global_transform = _stream.global_transform
			_extra.lifetime = life
			_extra.spread = _stream.spread * 1.3
		if _splash != null and hit:
			_splash.global_position = to + normal * 0.08
			if _splash.emission_shape == CPUParticles3D.EMISSION_SHAPE_RING:
				_splash.emission_ring_axis = normal
				_splash.emission_ring_radius = radius * 0.8
				_splash.emission_ring_inner_radius = radius * 0.6
	# The glow: a ribbon from the nozzle to the ice, as wide as the heat zone where it lands.
	var glow: float = s.beam * _on
	_beam.visible = glow > 0.002
	if _beam.visible:
		var m := _beam.material_override as ShaderMaterial
		m.set_shader_parameter("start", from)
		m.set_shader_parameter("dir", dir)
		m.set_shader_parameter("len", dist)
		m.set_shader_parameter("r1", radius * float(s.width))
		m.set_shader_parameter("strength", glow)
		m.set_shader_parameter("core", float(s.get("core", 0.0)) * _on)
		m.set_shader_parameter("fade_out", 0.86 if hit else 0.45)   # into thin air when it falls short
	if _sky != null:
		_sky.visible = _on > 0.01 and hit
		if _sky.visible:
			var m := _sky.material_override as ShaderMaterial
			m.set_shader_parameter("start", to - SUN_DIR.normalized() * 0.5)
			m.set_shader_parameter("r0", radius * 0.55)
			m.set_shader_parameter("r1", radius * 1.1)
			m.set_shader_parameter("strength", 0.42 * _on * (0.8 + 0.2 * heat))
			m.set_shader_parameter("core", 0.5 * _on)
	if _tip != null:
		_tip.visible = _on > 0.01
		_tip.global_position = from
		var tm := _tip.material_override as StandardMaterial3D
		var tc: Color = _tip.get_meta("color")
		tm.albedo_color = Color(tc.r, tc.g, tc.b, tc.a * _on * (0.85 + 0.15 * sin(_t * 23.0)))
	# Light where it lands, flickering for flames.
	var flick: float = s.get("flicker", 0.0)
	var e: float = float(s.light) * heat * _on * (1.0 + flick * 0.3 * sin(_t * 27.0) * sin(_t * 11.0 + 0.7))
	_light.visible = e > 0.01
	if _light.visible:
		_light.global_position = (to if hit else from.lerp(to, 0.7)) + normal * (0.4 + radius * 0.35)
		_light.light_energy = e
		_light.omni_range = 2.5 + radius * 2.5


static func glow_color(tool_i: int) -> Color:
	return GLOW[clampi(tool_i, 0, GLOW.size() - 1)]


static func _facing(dir: Vector3) -> Basis:
	## A basis with -Z along dir.
	var up := Vector3.UP if absf(dir.y) < 0.98 else Vector3.BACK
	return Basis.looking_at(dir, up)


# =====================================================================================
# The looks, one per tool
# =====================================================================================
func _build(tool_i: int, gold: bool) -> void:
	for n in [_stream, _extra, _splash, _beam, _sky, _tip, _light]:
		if n != null:
			n.queue_free()
	_stream = null
	_extra = null
	_splash = null
	_sky = null
	_tip = null
	var heat_lv := int(GameState.upgrade_levels.get("heat", 0))
	var heat := 1.0 + heat_lv / 25.0               # 1 .. 2 with Heat Output maxed
	var hot := clampf(heat_lv / 25.0, 0.0, 1.0)    # 0 .. 1: colours go whiter
	var more := 0.85 + 0.3 * hot                   # more particles the hotter it is
	var nozzle: float = GameState.upgrade_mult("nozzle")   # 1 .. 1.7
	var fat := 0.85 + 0.25 * (nozzle - 1.0) / 0.7  # particles get a bit bigger with the nozzle
	_beam = _beam_node()
	_light = OmniLight3D.new()
	_light.top_level = true
	_light.shadow_enabled = false
	_light.omni_attenuation = 1.4
	add_child(_light)
	var bm := _beam.material_override as ShaderMaterial
	match tool_i:
		0:   # Hair dryer: bands of warm air rolling out, wavy and see-through
			_style = {"speed": 6.5, "spread": 0.75, "wobble": 0.07, "beam": 0.62 + 0.18 * hot, "width": 0.8,
				"light": 0.0, "heat": heat}
			_beam_colors(bm, Color(1.0, 0.48, 0.38), Color(1.0, 0.6, 0.48), 0.0, 1.0, 0.0, 0.0, 3.0)
			_stream = _dots([Color(1.0, 0.85, 0.8, 0.0), Color(1.0, 0.72, 0.62, 0.4 + 0.12 * hot), Color(1.0, 0.75, 0.7, 0.0)],
				0.34 * fat, int(30 * more), false)
			_stream.scale_amount_curve = _curve(0.35, 1.0)
			_stream.initial_velocity_min = 5.5
			_stream.initial_velocity_max = 7.0
			if gold:   # the golden hair dryer blows glitter
				_extra = _dots([Color(1.0, 0.85, 0.3, 1.0), Color(1.0, 0.7, 0.15, 0.0)], 0.06, 26, false)
				_extra.initial_velocity_min = 5.0
				_extra.initial_velocity_max = 7.0
		1:   # Heat lamp: a cone of warm light, with dust glinting in it
			_style = {"speed": 3.0, "spread": 0.6, "beam": 0.6 + 0.2 * hot, "width": 0.9, "light": 0.9, "heat": heat}
			_beam_colors(bm, Color(1.0, 0.78, 0.25), Color(1.0, 0.55, 0.12), 0.0, 0.0, 0.8, 0.0, 1.0)
			_stream = _dots([Color(1.0, 0.8, 0.3, 0.0), Color(1.0, 0.72, 0.2, 0.95), Color(1.0, 0.55, 0.1, 0.0)],
				0.07, int(36 * more), false)
			_stream.initial_velocity_min = 2.5
			_stream.initial_velocity_max = 3.5
			_light.light_color = Color(1.0, 0.7, 0.35)
			_tip = _glow_tip(0.32, Color(1.0, 0.8, 0.45, 0.9))
		2:   # Blowtorch: a hard, roaring blue flame
			_style = {"speed": 12.0, "spread": 0.35, "beam": 0.72 + 0.2 * hot, "width": 0.5, "core": 0.45 + 0.3 * hot,
				"light": 1.1, "flicker": 0.6, "heat": heat}
			_beam_colors(bm, Color(0.22, 0.45, 1.0), Color(0.32, 0.28, 0.95), 0.0, 0.0, 0.0, 0.7, 9.0)
			var core := Color(0.7, 0.85, 1.0).lerp(Color.WHITE, hot * 0.5)
			_stream = _dots([Color(core.r, core.g, core.b, 1.0), Color(0.25, 0.5, 1.0, 0.95), Color(0.2, 0.25, 0.9, 0.6),
				Color(0.3, 0.2, 0.8, 0.0)], 0.16 * fat, int(100 * more), false)
			_stream.scale_amount_curve = _curve(0.4, 1.0)
			_stream.initial_velocity_min = 11.0
			_stream.initial_velocity_max = 13.0
			_light.light_color = Color(0.5, 0.65, 1.0)
			_tip = _glow_tip(0.16, Color(0.55, 0.75, 1.0, 1.0))
			_splash = _dots([Color(0.7, 0.85, 1.0, 1.0), Color(0.3, 0.45, 1.0, 0.0)], 0.07, 18, false, false)
			_splash_burst(_splash, 2.0, 4.0, 0.35)
		3:   # Flamethrower: big rolling fire, smoke and embers
			_style = {"speed": 10.0, "spread": 0.7, "beam": 0.68 + 0.2 * hot, "width": 0.7, "core": 0.25 + 0.3 * hot,
				"light": 2.0, "flicker": 1.0, "heat": heat}
			_beam_colors(bm, Color(1.0, 0.55, 0.1), Color(0.95, 0.28, 0.05), 0.0, 0.0, 0.0, 1.0, 7.0)
			var core := Color(1.0, 0.92, 0.55).lerp(Color.WHITE, hot * 0.4)
			_stream = _dots([Color(core.r, core.g, core.b, 1.0), Color(1.0, 0.6, 0.1, 1.0), Color(0.95, 0.28, 0.05, 0.85),
				Color(0.35, 0.25, 0.22, 0.45), Color(0.3, 0.27, 0.27, 0.0)], 0.42 * fat, int(160 * more), false)
			_stream.scale_amount_curve = _curve(0.3, 1.0)
			_stream.initial_velocity_min = 9.0
			_stream.initial_velocity_max = 11.5
			_stream.angle_max = 180.0
			_extra = _dots([Color(1.0, 0.85, 0.4, 1.0), Color(1.0, 0.4, 0.1, 0.0)], 0.05, 30, true)
			_extra.initial_velocity_min = 7.0
			_extra.initial_velocity_max = 12.0
			_extra.gravity = Vector3(0, 2.5, 0)
			_light.light_color = Color(1.0, 0.55, 0.2)
			_tip = _glow_tip(0.26, Color(1.0, 0.6, 0.2, 0.9))
			_splash = _dots([Color(1.0, 0.75, 0.3, 1.0), Color(1.0, 0.35, 0.1, 0.0)], 0.07, 26, false, false)
			_splash_burst(_splash, 2.0, 5.0, 0.6)
		4:   # Lava hose: a heavy stream of glowing lava that splashes
			_style = {"speed": 12.0, "spread": 0.18, "fall": 4.0, "beam": 0.0, "width": 0.6,
				"light": 2.4, "flicker": 0.4, "heat": heat}
			var bright := Color(1.0, 0.72, 0.18).lerp(Color(1.0, 0.95, 0.6), hot * 0.6)
			_stream = _blobs([bright, Color(1.0, 0.42, 0.06), Color(0.85, 0.18, 0.04), Color(0.5, 0.08, 0.03)],
				0.13 * fat, int(170 * more))
			_stream.gravity = Vector3(0, -4.0, 0)
			_stream.initial_velocity_min = 11.5
			_stream.initial_velocity_max = 12.5
			_stream.scale_amount_min = 0.7
			_stream.scale_amount_max = 1.4
			_stream.scale_amount_curve = _curve(0.55, 1.0)
			_light.light_color = Color(1.0, 0.42, 0.12)
			_tip = _glow_tip(0.22, Color(1.0, 0.5, 0.15, 0.8))
			_splash = _blobs([Color(1.0, 0.6, 0.15), Color(0.9, 0.25, 0.05), Color(0.4, 0.08, 0.04)], 0.1 * fat, 30, false)
			_splash_burst(_splash, 2.5, 5.5, 0.7)
			_splash.gravity = Vector3(0, -14.0, 0)
		_:   # Orbital mirror: a thin aiming laser, and a sunbeam from space where it lands
			_style = {"speed": 30.0, "spread": 0.05, "beam": 0.85, "width": 0.012, "core": 0.6, "light": 3.2, "heat": heat}
			_beam_colors(bm, Color(1.0, 0.8, 0.3), Color(1.0, 0.7, 0.25), 0.0, 0.0, 0.0, 0.0, 0.0)
			bm.set_shader_parameter("r0", 0.008)
			_stream = _dots([Color(1.0, 0.9, 0.6, 0.0), Color(1.0, 0.85, 0.45, 0.9), Color(1.0, 0.75, 0.3, 0.0)], 0.05, 20, false)
			_stream.initial_velocity_min = 28.0
			_stream.initial_velocity_max = 32.0
			_sky = _beam_node()
			var sm := _sky.material_override as ShaderMaterial
			_beam_colors(sm, Color(1.0, 0.95, 0.72).lerp(Color.WHITE, hot * 0.5), Color(1.0, 0.9, 0.6), 0.0, 0.0, 0.6, 0.0, 0.0)
			sm.set_shader_parameter("dir", SUN_DIR.normalized())
			sm.set_shader_parameter("len", 160.0)
			sm.set_shader_parameter("fade_in", 0.0)
			sm.set_shader_parameter("fade_out", 0.15)
			_light.light_color = Color(1.0, 0.95, 0.8)
			_splash = _dots([Color(1.0, 0.95, 0.65, 1.0), Color(1.0, 0.8, 0.3, 0.0)], 0.14, 60, true, false)
			_splash.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
			_splash.emission_ring_height = 0.1
			_splash.direction = Vector3(0, 1, 0)
			_splash.spread = 15.0
			_splash.gravity = Vector3(0, 3.0, 0)
			_splash.initial_velocity_min = 0.5
			_splash.initial_velocity_max = 2.0
			_splash.lifetime = 1.0
	for n in [_stream, _extra, _splash]:
		if n != null:
			n.top_level = true
			add_child(n)


func _beam_colors(m: ShaderMaterial, near: Color, far: Color, core: float, waves: float, rays: float,
		flicker: float, scroll: float) -> void:
	m.set_shader_parameter("color_near", Vector3(near.r, near.g, near.b))
	m.set_shader_parameter("color_far", Vector3(far.r, far.g, far.b))
	m.set_shader_parameter("core", core)
	m.set_shader_parameter("waves", waves)
	m.set_shader_parameter("rays", rays)
	m.set_shader_parameter("flicker", flicker)
	m.set_shader_parameter("scroll", scroll)


static var _strip: ArrayMesh


static func _strip_mesh() -> ArrayMesh:
	## UV.x across, UV.y = 0..1 along (the shader puts it in the world).
	if _strip == null:
		var verts := PackedVector3Array()
		var uvs := PackedVector2Array()
		var steps := 24
		for k in steps + 1:
			var y := float(k) / steps
			verts.append(Vector3(-0.5, y, 0.0))
			verts.append(Vector3(0.5, y, 0.0))
			uvs.append(Vector2(0.0, y))
			uvs.append(Vector2(1.0, y))
		var idx := PackedInt32Array()
		for k in steps:
			var a := k * 2
			idx.append_array([a, a + 1, a + 2, a + 1, a + 3, a + 2])
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = verts
		arr[Mesh.ARRAY_TEX_UV] = uvs
		arr[Mesh.ARRAY_INDEX] = idx
		_strip = ArrayMesh.new()
		_strip.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return _strip


func _beam_node() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _strip_mesh()
	var m := ShaderMaterial.new()
	m.shader = BEAM_SHADER
	m.set_shader_parameter("r0", 0.04)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.top_level = true
	mi.custom_aabb = AABB(Vector3(-2000, -2000, -2000), Vector3(4000, 4000, 4000))   # placed by the shader
	mi.visible = false
	add_child(mi)
	return mi


func _glow_tip(size: float, color: Color) -> MeshInstance3D:
	## A soft glow at the nozzle.
	var mi := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	mi.mesh = quad
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_texture = UiTheme.soft_dot()
	m.no_depth_test = false
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.top_level = true
	mi.visible = false
	mi.set_meta("color", color)
	add_child(mi)
	return mi


static func _ramp(colors: Array) -> Gradient:
	var g := Gradient.new()
	var offs := PackedFloat32Array()
	var cols := PackedColorArray()
	for i in colors.size():
		offs.append(float(i) / float(colors.size() - 1))
		cols.append(colors[i])
	g.offsets = offs
	g.colors = cols
	return g


static func _curve(a: float, b: float) -> Curve:
	var c := Curve.new()
	c.add_point(Vector2(0.0, a))
	c.add_point(Vector2(1.0, b))
	return c


func _dots(colors: Array, size: float, amount: int, additive: bool, on_top: bool = true) -> CPUParticles3D:
	## Soft round billboards: air, flame, sparks. on_top: drawn over the snow
	## (the stream from the nozzle; see heat_beam.gdshader for why).
	var p := CPUParticles3D.new()
	p.amount = maxi(amount, 1)
	p.emitting = false
	p.local_coords = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.no_depth_test = on_top
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = UiTheme.soft_dot()
	quad.material = m
	p.mesh = quad
	p.color_ramp = _ramp(colors)
	p.direction = Vector3(0, 0, -1)
	p.gravity = Vector3.ZERO
	p.scale_amount_min = 0.7
	p.scale_amount_max = 1.3
	return p


func _blobs(colors: Array, size: float, amount: int, on_top: bool = true) -> CPUParticles3D:
	## Little balls (lava).
	var p := CPUParticles3D.new()
	p.amount = maxi(amount, 1)
	p.emitting = false
	p.local_coords = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var sm := SphereMesh.new()
	sm.radius = size * 0.5
	sm.height = size
	sm.radial_segments = 8
	sm.rings = 4
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.no_depth_test = on_top
	sm.material = m
	p.mesh = sm
	p.color_ramp = _ramp(colors)
	p.direction = Vector3(0, 0, -1)
	p.gravity = Vector3.ZERO
	return p


static func _splash_burst(p: CPUParticles3D, v0: float, v1: float, life: float) -> void:
	## Bits flying up off the ice where the stream lands.
	p.direction = Vector3(0, 1, 0)
	p.spread = 65.0
	p.gravity = Vector3(0, -9.0, 0)
	p.initial_velocity_min = v0
	p.initial_velocity_max = v1
	p.lifetime = life
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.3
