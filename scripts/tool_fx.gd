class_name ToolFx
extends Node3D
## What comes out of the tool in your hand, in 3D, from its nozzle to where
## the heat lands, and what the ice does when it's hit. Every tool is its own
## thing:
## - Hair dryer: rings of hot air rushing out and widening in a warm haze,
##   with wind streaks. Snow flurries up where it lands.
## - Heat lamp: a soft cone of warm light with rays and dust glinting in it.
## - Blowtorch: a hard blue flame at the nozzle and a roaring blue jet. Sparks
##   sizzle off the ice.
## - Flamethrower: a roaring flame at the nozzle and fire that billows out
##   bigger as it flies, with embers. Fire splashes across the ice.
## - Lava hose: a heavy molten stream that arcs, drips and splashes.
## - Orbital mirror: an aiming laser, and a column of sunlight from space with
##   shockwaves rolling out where it lands.
## Steam boils up off the ice for all of them (more for the hotter tools).
## Upgrades show: Wider Nozzle makes it wider where it lands, Longer Reach lets
## it go further, Heat Output makes it hotter, brighter and denser.
## The player calls update() every physics frame. It's all CPU particles and a
## few soft meshes, light enough for a phone.

const CONE_SHADER := preload("res://shaders/tool_cone.gdshader")
const COLUMN_SHADER := preload("res://shaders/light_column.gdshader")
const SPARK_SHADER := preload("res://shaders/spark.gdshader")
const BEAM_SHADER := preload("res://shaders/heat_beam.gdshader")
const SUN_DIR := Vector3(0.32, 1.0, 0.18)    # where the orbital mirror's sunlight comes from
const SKY_LEN := 140.0                       # how far up the sunlight column goes
# The colour the ice glows where each tool's heat lands.
const GLOW := [Color(1.0, 0.62, 0.45), Color(1.0, 0.62, 0.25), Color(0.45, 0.62, 1.0),
	Color(1.0, 0.45, 0.12), Color(1.0, 0.34, 0.05), Color(1.0, 0.86, 0.5)]

# The parts of the current tool's effect (rebuilt when the tool or its upgrades change).
var _streams: Array = []     # {p, speed, spread[, size, fall, life]}: fly from the nozzle to the ice
var _impacts: Array = []     # {p[, area, ring, size, lift]}: where it lands, facing out of the ice
var _cones: Array = []       # {mi, kind: "beam" (nozzle to ice) or "flame" (its own length), ...}
var _columns: Array = []     # {mi, width, strength}: the orbital mirror's sunlight
var _drips: CPUParticles3D   # lava dripping off the stream on its way
var _drip_fall := 0.0
var _laser: MeshInstance3D   # the orbital mirror's aiming laser
var _tip: MeshInstance3D     # a glow at the nozzle
var _light: OmniLight3D
var _style: Dictionary = {}
var _built := ""             # which tool and upgrade levels the effects were built for
var _t := 0.0
var _on := 0.0               # fades the glows in and out

static var _puff: Texture2D
static var _noise: Texture2D
static var _tube: ArrayMesh


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
	var aim_basis := _facing(dir)
	var wob: float = s.get("wobble", 0.0)

	# What flies out of the nozzle, aimed so it lands on the spot.
	var arc_life := 0.0
	for st in _streams:
		var p: CPUParticles3D = st.p
		p.emitting = active
		if not active:
			continue
		var life := clampf(dist / float(st.speed), 0.05, 3.0)
		var aim := dir
		if st.has("fall"):   # lava falls, so it aims a little high
			aim = (to + Vector3(0.0, 0.5 * float(st.fall) * life * life, 0.0) - from).normalized()
			arc_life = life
		var b := _facing(aim)
		if wob > 0.0:   # hot air wanders about
			b = b * Basis(Vector3.RIGHT, sin(_t * 6.3) * wob) * Basis(Vector3.UP, sin(_t * 4.1 + 1.3) * wob)
		p.global_transform = Transform3D(b, from)
		p.lifetime = life * float(st.get("life", 1.0))
		p.spread = clampf(rad_to_deg(atan2(radius * float(st.spread), dist)), 0.3, 60.0)
		if st.has("size"):   # grows to this share of the heat zone by the time it lands
			var sz: float = radius * float(st.size)
			p.scale_amount_min = sz * 0.8
			p.scale_amount_max = sz * 1.2

	# Lava drips off the stream along its arc.
	if _drips != null:
		_drips.emitting = active and arc_life > 0.0
		if _drips.emitting:
			var g := Vector3(0.0, -_drip_fall, 0.0)
			var v0 := (to - from - 0.5 * g * arc_life * arc_life) / arc_life
			var pts := PackedVector3Array()
			for k in 7:
				var tt := (k + 1.5) / 9.0 * arc_life
				pts.append(from + v0 * tt + 0.5 * g * tt * tt)
			_drips.emission_points = pts

	# Where it lands: steam, sparks, splashes, snow.
	var land := Transform3D(_facing(normal), to + normal * 0.06)
	for im in _impacts:
		var p: CPUParticles3D = im.p
		p.emitting = active and hit
		if not p.emitting:
			continue
		p.global_transform = land
		if im.has("lift"):
			p.global_position += normal * float(im.lift)
		if im.has("area"):
			p.emission_sphere_radius = maxf(radius * float(im.area), 0.05)
		if im.has("ring"):
			p.emission_ring_radius = radius * float(im.ring)
			p.emission_ring_inner_radius = radius * float(im.ring) * 0.75
		if im.has("size"):
			var sz: float = radius * float(im.size)
			p.scale_amount_min = sz * 0.7
			p.scale_amount_max = sz * 1.3

	# Flames and beams: soft glowing cones from the nozzle.
	for c in _cones:
		var mi: MeshInstance3D = c.mi
		mi.visible = _on > 0.01
		if not mi.visible:
			continue
		var m := mi.material_override as ShaderMaterial
		mi.global_transform = Transform3D(aim_basis, from)
		var flick := 1.0
		if c.has("flicker"):
			flick += float(c.flicker) * (0.6 * sin(_t * 41.0) + 0.4 * sin(_t * 23.0 + 1.7))
		if c.kind == "beam":
			m.set_shader_parameter("len", dist)
			m.set_shader_parameter("r1", radius * float(c.width))
		else:
			m.set_shader_parameter("len", float(c.len) * flick * (0.5 + 0.5 * _on))
		m.set_shader_parameter("strength", float(c.strength) * _on * (0.92 + 0.08 * flick))

	# The orbital mirror: sunlight from space, and the laser you aim it with.
	for c in _columns:
		var mi: MeshInstance3D = c.mi
		mi.visible = _on > 0.01 and hit
		if not mi.visible:
			continue
		var up := SUN_DIR.normalized()
		mi.global_transform = Transform3D(_facing(-up), to + up * SKY_LEN)
		var m := mi.material_override as ShaderMaterial
		var w: float = radius * float(c.width) * (0.97 + 0.03 * sin(_t * 9.0))
		m.set_shader_parameter("r0", w)
		m.set_shader_parameter("r1", w)
		m.set_shader_parameter("strength", float(c.strength) * _on * (0.8 + 0.2 * heat))
	if _laser != null:
		_laser.visible = _on > 0.01
		if _laser.visible:
			var m := _laser.material_override as ShaderMaterial
			m.set_shader_parameter("start", from)
			m.set_shader_parameter("dir", dir)
			m.set_shader_parameter("len", dist)
			m.set_shader_parameter("strength", 0.85 * _on)
			m.set_shader_parameter("fade_out", 0.9 if hit else 0.45)   # into thin air when it falls short

	if _tip != null:
		_tip.visible = _on > 0.01
		_tip.global_position = from
		var tm := _tip.material_override as StandardMaterial3D
		var tc: Color = _tip.get_meta("color")
		tm.albedo_color = Color(tc.r, tc.g, tc.b, tc.a * _on * (0.85 + 0.15 * sin(_t * 23.0)))
	# Light where it lands, flickering for flames.
	var flick_l: float = s.get("flicker", 0.0)
	var e: float = float(s.light) * heat * _on * (1.0 + flick_l * 0.3 * sin(_t * 27.0) * sin(_t * 11.0 + 0.7))
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
	for n in get_children():
		n.queue_free()
	_streams.clear()
	_impacts.clear()
	_cones.clear()
	_columns.clear()
	_drips = null
	_laser = null
	_tip = null
	var heat_lv := int(GameState.upgrade_levels.get("heat", 0))
	var heat := 1.0 + heat_lv / 25.0               # 1 .. 2 with Heat Output maxed
	var hot := clampf(heat_lv / 25.0, 0.0, 1.0)    # 0 .. 1: hotter looks brighter and whiter
	var more := 0.85 + 0.35 * hot                  # and denser
	var nozzle: float = GameState.upgrade_mult("nozzle")   # 1 .. 1.7
	var fat := 0.85 + 0.25 * (nozzle - 1.0) / 0.7  # lava blobs get a bit bigger with the nozzle
	_light = OmniLight3D.new()
	_light.top_level = true
	_light.shadow_enabled = false
	_light.omni_attenuation = 1.4
	_light.visible = false
	add_child(_light)
	match tool_i:
		0:
			_build_hair_dryer(gold, heat, hot, more)
		1:
			_build_heat_lamp(heat, hot, more)
		2:
			_build_blowtorch(heat, hot, more)
		3:
			_build_flamethrower(heat, hot, more)
		4:
			_build_lava_hose(heat, hot, more, fat)
		_:
			_build_orbital_mirror(heat, hot, more)


func _build_hair_dryer(gold: bool, heat: float, hot: float, more: float) -> void:
	_style = {"heat": heat, "wobble": 0.045, "light": 0.0}
	var warm := Color(1.0, 0.74, 0.64).lerp(Color(1.0, 0.56, 0.32), hot)   # hotter air, more orange
	if gold:
		warm = Color(1.0, 0.8, 0.3)
	# Rings of hot air rushing out, widening to the size of the heat zone.
	var rings := _rings([Color(warm, 0.0), Color(warm, 0.55), Color(warm, 0.35), Color(warm, 0.0)],
		int(8 * more), 0.9, true, [0.0, 0.15, 0.7, 1.0])
	rings.initial_velocity_min = 6.0
	rings.initial_velocity_max = 6.4
	rings.scale_amount_curve = _curve(0.1, 1.0)
	_streams.append({"p": rings, "speed": 6.2, "spread": 0.04, "size": 0.8})
	# A warm haze of shimmering air round them.
	var haze := _puffs([Color(warm, 0.0), Color(warm, 0.3 + 0.1 * hot), Color(warm, 0.18), Color(warm, 0.0)], int(16 * more))
	haze.initial_velocity_min = 5.0
	haze.initial_velocity_max = 6.5
	haze.scale_amount_curve = _curve(0.15, 1.0)
	_streams.append({"p": haze, "speed": 5.8, "spread": 0.3, "size": 0.85})
	# Wind streaks whooshing past.
	var wind := _sparks([Color(1, 1, 1, 0.0), Color(1.0, 0.97, 0.95, 0.8), Color(1, 1, 1, 0.0)], 0.03, 10.0, 12)
	wind.initial_velocity_min = 7.5
	wind.initial_velocity_max = 8.5
	_streams.append({"p": wind, "speed": 8.0, "spread": 0.5})
	if gold:   # the golden hair dryer blows glitter
		var glitter := _sparks([Color(1.0, 0.9, 0.4, 1.0), Color(1.0, 0.75, 0.2, 0.9), Color(1.0, 0.7, 0.15, 0.0)], 0.04, 1.6, 26)
		glitter.initial_velocity_min = 5.0
		glitter.initial_velocity_max = 7.0
		_streams.append({"p": glitter, "speed": 6.0, "spread": 0.6})
	# Snow flurries up where it lands.
	var flurry := _puffs([Color(0.82, 0.9, 1.0, 1.0), Color(0.86, 0.92, 1.0, 0.85), Color(0.9, 0.95, 1.0, 0.0)], int(26 * more), false)
	flurry.lifetime = 0.9
	flurry.spread = 70.0
	flurry.initial_velocity_min = 1.5
	flurry.initial_velocity_max = 3.2
	flurry.gravity = Vector3(0, -3.5, 0)
	flurry.damping_min = 1.0
	flurry.damping_max = 2.0
	flurry.scale_amount_min = 0.08
	flurry.scale_amount_max = 0.2
	flurry.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_impacts.append({"p": flurry, "area": 0.35})
	_add_steam(int(18 * more), 0.6, 1.4)


func _build_heat_lamp(heat: float, hot: float, more: float) -> void:
	_style = {"heat": heat, "light": 0.9 + 0.4 * hot}
	# A soft cone of warm light from the lamp to the ice, with rays in it.
	var lc := Color(1.0, 0.78, 0.3).lerp(Color(1.0, 0.92, 0.6), hot * 0.5)
	_add_cone("beam", lc, Color(1.0, 0.6, 0.15), {"r0": 0.12, "width": 1.0, "strength": 0.5 + 0.15 * hot,
		"soft_edge": 0.12, "fade_in": 0.02, "fade_out": 0.85, "noise_amount": 0.2, "noise_scale": 0.25,
		"scroll": 0.6, "stripes": 0.75})
	# Dust glinting in the light, drifting along.
	var motes := _sparks([Color(1.0, 0.9, 0.5, 0.0), Color(1.0, 0.88, 0.45, 1.0), Color(1.0, 0.8, 0.35, 0.15),
		Color(1.0, 0.9, 0.5, 0.95), Color(1.0, 0.8, 0.3, 0.0)], 0.07, 1.0, int(50 * more))
	motes.initial_velocity_min = 1.0
	motes.initial_velocity_max = 1.6
	_streams.append({"p": motes, "speed": 1.3, "spread": 0.8})
	_tip = _glow_tip(0.36, Color(1.0, 0.82, 0.45, 0.9))
	_add_steam(int(20 * more), 0.6, 1.6)


func _build_blowtorch(heat: float, hot: float, more: float) -> void:
	_style = {"heat": heat, "light": 1.1 + 0.4 * hot, "flicker": 0.6}
	var core := Color(0.75, 0.9, 1.0).lerp(Color.WHITE, hot * 0.6)
	# The flame at the nozzle: a white-blue inner cone in a blue outer one.
	_add_cone("flame", core, Color(0.6, 0.8, 1.0), {"len": 0.24, "r0": 0.03, "r1": 0.004, "bulge": 0.015,
		"strength": 0.95, "soft_edge": 0.5, "fade_in": 0.0, "fade_out": 0.75, "noise_amount": 0.25,
		"noise_scale": 3.0, "scroll": 6.0, "flicker": 0.08})
	_add_cone("flame", Color(0.3, 0.5, 1.0), Color(0.35, 0.3, 0.95), {"len": 0.6 + 0.2 * hot, "r0": 0.045,
		"r1": 0.012, "bulge": 0.04, "strength": 0.75, "soft_edge": 0.45, "fade_in": 0.0, "fade_out": 0.55,
		"noise_amount": 0.5, "noise_scale": 2.0, "scroll": 8.0, "flicker": 0.12})
	# The jet roaring out to the ice.
	_add_cone("beam", Color(0.45, 0.65, 1.0), Color(0.35, 0.4, 1.0), {"r0": 0.035, "width": 0.3,
		"strength": 0.36 + 0.15 * hot, "soft_edge": 0.3, "fade_in": 0.08, "fade_out": 0.9,
		"noise_amount": 0.9, "noise_scale": 0.6, "scroll": 10.0})
	var jet := _puffs([Color(core, 0.9), Color(0.35, 0.55, 1.0, 0.75), Color(0.3, 0.35, 0.95, 0.4),
		Color(0.4, 0.3, 0.9, 0.0)], int(50 * more))
	jet.initial_velocity_min = 11.0
	jet.initial_velocity_max = 13.0
	jet.scale_amount_curve = _curve(0.15, 1.0)
	_streams.append({"p": jet, "speed": 12.0, "spread": 0.2, "size": 0.35})
	# Sparks sizzling off the ice.
	var sparks := _sparks([Color(1, 1, 1, 1), Color(0.7, 0.85, 1.0, 1.0), Color(0.4, 0.6, 1.0, 0.0)], 0.035, 6.0, int(26 * more))
	_spray(sparks, 65.0, 3.0, 6.5, -9.0, 0.55)
	_impacts.append({"p": sparks, "area": 0.2})
	_tip = _glow_tip(0.2, Color(0.55, 0.75, 1.0, 1.0))
	_add_steam(int(26 * more), 0.65, 2.2)


func _build_flamethrower(heat: float, hot: float, more: float) -> void:
	_style = {"heat": heat, "light": 2.0 + 0.6 * hot, "flicker": 1.0}
	var core := Color(1.0, 0.95, 0.7).lerp(Color.WHITE, hot * 0.4)
	# A roaring flame at the nozzle and a core of fire reaching out.
	_add_cone("flame", core, Color(1.0, 0.6, 0.15), {"len": 0.42, "r0": 0.05, "r1": 0.02, "bulge": 0.06,
		"strength": 0.8, "soft_edge": 0.4, "fade_in": 0.0, "fade_out": 0.5, "noise_amount": 0.6,
		"noise_scale": 2.0, "scroll": 7.0, "flicker": 0.15})
	_add_cone("beam", Color(1.0, 0.82, 0.3), Color(1.0, 0.4, 0.08), {"r0": 0.06, "width": 0.4,
		"strength": 0.45 + 0.15 * hot, "soft_edge": 0.3, "fade_in": 0.04, "fade_out": 0.8,
		"noise_amount": 0.8, "noise_scale": 0.5, "scroll": 9.0})
	# Fire billowing out, growing as it flies and going smoky at the end.
	var fire := _puffs([Color(core, 1.0), Color(1.0, 0.75, 0.25, 1.0), Color(1.0, 0.45, 0.08, 0.9),
		Color(0.75, 0.2, 0.05, 0.7), Color(0.28, 0.22, 0.2, 0.0)], int(46 * more), true, [0.0, 0.18, 0.45, 0.72, 1.0])
	fire.initial_velocity_min = 9.5
	fire.initial_velocity_max = 11.0
	fire.scale_amount_curve = _curve(0.06, 1.0)
	fire.gravity = Vector3(0, 2.0, 0)
	_streams.append({"p": fire, "speed": 10.0, "spread": 0.45, "size": 0.68})
	# Embers.
	var embers := _sparks([Color(1.0, 0.9, 0.5, 1.0), Color(1.0, 0.5, 0.1, 0.9), Color(1.0, 0.3, 0.05, 0.0)], 0.03, 4.0, 26)
	embers.initial_velocity_min = 7.0
	embers.initial_velocity_max = 11.0
	embers.gravity = Vector3(0, 3.0, 0)
	_streams.append({"p": embers, "speed": 9.0, "spread": 0.8, "life": 1.3})
	# Fire splashing across the ice.
	var splash := _puffs([Color(1.0, 0.85, 0.4, 0.9), Color(1.0, 0.45, 0.1, 0.7), Color(0.4, 0.25, 0.2, 0.0)], int(22 * more), false)
	_spray(splash, 80.0, 2.0, 4.5, 1.0, 0.55)
	splash.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_impacts.append({"p": splash, "area": 0.25, "size": 0.35})
	_tip = _glow_tip(0.3, Color(1.0, 0.6, 0.2, 0.9))
	_add_steam(int(30 * more), 0.75, 2.6)


func _build_lava_hose(heat: float, hot: float, more: float, fat: float) -> void:
	_style = {"heat": heat, "light": 2.4 + 0.6 * hot, "flicker": 0.4}
	var bright := Color(1.0, 0.6, 0.1).lerp(Color(1.0, 0.85, 0.35), hot * 0.6)
	# A heavy stream of molten lumps, stretched out along the arc.
	var lava := _blobs([bright, Color(1.0, 0.4, 0.05), Color(0.85, 0.2, 0.04), Color(0.5, 0.1, 0.03)],
		0.17 * fat, int(190 * more), 3.0)
	lava.gravity = Vector3(0, -4.0, 0)
	lava.initial_velocity_min = 11.6
	lava.initial_velocity_max = 12.4
	lava.scale_amount_min = 0.75
	lava.scale_amount_max = 1.35
	lava.scale_amount_curve = _curve(0.65, 1.0)
	lava.color_initial_ramp = _ramp([Color.WHITE, Color(1.0, 0.8, 0.6), Color(0.55, 0.42, 0.38)])   # crusty bits
	_streams.append({"p": lava, "speed": 12.0, "spread": 0.12, "fall": 4.0})
	# Drips falling off it on the way.
	_drips = _blobs([bright, Color(0.9, 0.3, 0.05), Color(0.4, 0.08, 0.03)], 0.09 * fat, 18, 1.6)
	_drips.emission_shape = CPUParticles3D.EMISSION_SHAPE_POINTS
	_drips.emission_points = PackedVector3Array([Vector3.ZERO])
	_drips.direction = Vector3(0, -1, 0)
	_drips.spread = 20.0
	_drips.initial_velocity_min = 0.0
	_drips.initial_velocity_max = 0.5
	_drips.gravity = Vector3(0, -12.0, 0)
	_drips.lifetime = 0.7
	_drips.global_transform = Transform3D.IDENTITY   # the drip points are in the world
	_drip_fall = 4.0
	# Splashing where it lands.
	var splash := _blobs([bright, Color(0.95, 0.3, 0.05), Color(0.35, 0.07, 0.03)], 0.11 * fat, int(34 * more), 1.4, false)
	_spray(splash, 70.0, 2.5, 5.5, -14.0, 0.75)
	splash.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_impacts.append({"p": splash, "area": 0.3})
	_tip = _glow_tip(0.24, Color(1.0, 0.5, 0.15, 0.8))
	_add_steam(int(30 * more), 0.8, 3.2)


func _build_orbital_mirror(heat: float, hot: float, more: float) -> void:
	_style = {"heat": heat, "light": 3.2 + 0.8 * hot}
	# A thin aiming laser from the remote.
	_laser = MeshInstance3D.new()
	_laser.mesh = _strip_mesh()
	var lm := ShaderMaterial.new()
	lm.shader = BEAM_SHADER
	lm.set_shader_parameter("color_near", Vector3(1.0, 0.8, 0.3))
	lm.set_shader_parameter("color_far", Vector3(1.0, 0.7, 0.25))
	lm.set_shader_parameter("r0", 0.008)
	lm.set_shader_parameter("r1", 0.012)
	lm.set_shader_parameter("core", 0.6)
	_laser.material_override = lm
	_laser.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_laser.top_level = true
	_laser.custom_aabb = AABB(Vector3(-2000, -2000, -2000), Vector3(4000, 4000, 4000))   # placed by the shader
	_laser.visible = false
	add_child(_laser)
	# A column of sunlight from space, with a white-hot middle.
	var sun := Color(1.0, 0.95, 0.75).lerp(Color.WHITE, hot * 0.5)
	_add_column(sun, Color(1.0, 0.88, 0.55), 0.62, 0.36 + 0.1 * hot, 0.7)
	_add_column(Color.WHITE, Color(1.0, 0.97, 0.85), 0.22, 0.5, 0.3)
	# Shockwaves rolling out across the ice.
	var shock := _rings([Color(1.0, 0.97, 0.75, 0.95), Color(1.0, 0.85, 0.5, 0.5), Color(1.0, 0.8, 0.4, 0.0)], 3, 0.88, false)
	shock.lifetime = 0.8
	shock.initial_velocity_min = 0.05   # just enough to lie them flat on the ice (align_y)
	shock.initial_velocity_max = 0.05
	shock.spread = 0.0
	shock.scale_amount_curve = _curve(0.15, 1.0)
	_impacts.append({"p": shock, "size": 1.15, "lift": 0.35})
	# Sparkles rising in a ring round the spot.
	var sparkle := _sparks([Color(1.0, 0.97, 0.7, 1.0), Color(1.0, 0.85, 0.4, 0.8), Color(1.0, 0.8, 0.3, 0.0)], 0.06, 2.5, int(50 * more))
	sparkle.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	sparkle.emission_ring_axis = Vector3(0, 0, 1)
	sparkle.emission_ring_height = 0.1
	_spray(sparkle, 15.0, 1.0, 3.0, 3.0, 1.0)
	_impacts.append({"p": sparkle, "ring": 0.8})
	_add_steam(int(34 * more), 0.85, 3.6)


# =====================================================================================
# Building blocks
# =====================================================================================
func _add_steam(amount: int, size: float, rise: float) -> void:
	## Clouds of steam boiling up off the ice where the heat lands.
	var p := _puffs([Color(0.8, 0.84, 0.9, 0.0), Color(0.82, 0.86, 0.92, 0.85), Color(0.88, 0.91, 0.96, 0.45),
		Color(0.95, 0.97, 1.0, 0.0)], amount, false, [0.0, 0.1, 0.55, 1.0])
	_spray(p, 30.0, rise * 0.6, rise * 1.2, 2.0, 2.0)
	p.damping_min = 0.5
	p.damping_max = 1.0
	p.scale_amount_curve = _curve(0.35, 1.0)
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_impacts.append({"p": p, "area": 0.3, "size": size * 1.3, "lift": 0.2})


func _spray(p: CPUParticles3D, spread: float, v_min: float, v_max: float, up: float, life: float) -> void:
	## Out of the ice: `spread` degrees round the way it faces, `up` = gravity (+ rises).
	p.spread = spread
	p.initial_velocity_min = v_min
	p.initial_velocity_max = v_max
	p.gravity = Vector3(0, up, 0)
	p.lifetime = life


func _add_cone(kind: String, near: Color, far: Color, params: Dictionary) -> void:
	## A flame ("flame": its own length at the nozzle) or a beam ("beam": nozzle to ice, as
	## wide as `width` times the heat zone where it lands).
	var mi := _cone_mesh(CONE_SHADER, near, far)
	var m := mi.material_override as ShaderMaterial
	var entry := {"mi": mi, "kind": kind, "strength": params.get("strength", 0.6)}
	for k in params:
		match k:
			"width", "len", "flicker":
				entry[k] = params[k]
			"strength":
				pass
			_:
				m.set_shader_parameter(k, params[k])
	if kind == "flame":
		m.set_shader_parameter("len", params.get("len", 0.5))
	_cones.append(entry)


func _add_column(near: Color, far: Color, width: float, strength: float, stripes: float) -> void:
	## A column of sunlight from the sky down to the spot (orbital mirror).
	var mi := _cone_mesh(COLUMN_SHADER, near, far)
	var m := mi.material_override as ShaderMaterial
	m.set_shader_parameter("len", SKY_LEN + 1.0)
	m.set_shader_parameter("soft_edge", 0.55)
	m.set_shader_parameter("fade_in", 0.45)
	m.set_shader_parameter("fade_out", 0.995)
	m.set_shader_parameter("noise_amount", 0.35)
	m.set_shader_parameter("noise_scale", 0.06)
	m.set_shader_parameter("scroll", 25.0)
	m.set_shader_parameter("stripes", stripes)
	_columns.append({"mi": mi, "width": width, "strength": strength})


func _cone_mesh(shader: Shader, near: Color, far: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _tube_mesh()
	var m := ShaderMaterial.new()
	m.shader = shader
	m.set_shader_parameter("noise", noise_texture())
	m.set_shader_parameter("color_start", Vector3(near.r, near.g, near.b))
	m.set_shader_parameter("color_end", Vector3(far.r, far.g, far.b))
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.top_level = true
	mi.custom_aabb = AABB(Vector3(-1000, -1000, -1000), Vector3(2000, 2000, 2000))   # shaped by the shader
	mi.visible = false
	add_child(mi)
	return mi


func _particles(amount: int) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = maxi(amount, 1)
	p.emitting = false
	p.local_coords = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.direction = Vector3(0, 0, -1)
	p.gravity = Vector3.ZERO
	p.top_level = true
	add_child(p)
	return p


func _puffs(colors: Array, amount: int, on_top: bool = true, offsets: Array = []) -> CPUParticles3D:
	## Soft lumpy puffs that turn as they go: fire, smoke, steam, hot air. on_top:
	## drawn over the snow (what flies from the nozzle; see tool_cone.gdshader).
	var p := _particles(amount)
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.no_depth_test = on_top
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = puff_texture()
	quad.material = m
	p.mesh = quad
	p.color_ramp = _ramp(colors, offsets)
	p.angle_min = -180.0
	p.angle_max = 180.0
	p.angular_velocity_min = -70.0
	p.angular_velocity_max = 70.0
	return p


func _sparks(colors: Array, width: float, stretch: float, amount: int) -> CPUParticles3D:
	## Bright streaks stretched out along the way they fly: sparks, embers, wind.
	var p := _particles(amount)
	p.particle_flag_align_y = true
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var m := ShaderMaterial.new()
	m.shader = SPARK_SHADER
	m.set_shader_parameter("tex", UiTheme.soft_dot())
	m.set_shader_parameter("stretch", stretch)
	quad.material = m
	p.mesh = quad
	p.color_ramp = _ramp(colors)
	p.scale_amount_min = width * 0.7
	p.scale_amount_max = width * 1.3
	return p


func _rings(colors: Array, amount: int, inner: float, on_top: bool, offsets: Array = []) -> CPUParticles3D:
	## Rings flying along, square to the way they go (hot air, shockwaves).
	var p := _particles(amount)
	p.particle_flag_align_y = true
	var torus := TorusMesh.new()
	torus.inner_radius = inner
	torus.outer_radius = 1.0
	torus.rings = 28
	torus.ring_segments = 6
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = on_top
	m.vertex_color_use_as_albedo = true
	torus.material = m
	p.mesh = torus
	p.color_ramp = _ramp(colors, offsets)
	return p


func _blobs(colors: Array, size: float, amount: int, stretch: float = 1.0, on_top: bool = true) -> CPUParticles3D:
	## Lumps of lava, drawn out along the way they fly.
	var p := _particles(amount)
	var sm := SphereMesh.new()
	sm.radius = size * 0.5
	sm.height = size * stretch
	sm.radial_segments = 8
	sm.rings = 4
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.no_depth_test = on_top
	sm.material = m
	p.mesh = sm
	p.color_ramp = _ramp(colors)
	p.particle_flag_align_y = stretch > 1.0
	return p


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
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.top_level = true
	mi.visible = false
	mi.set_meta("color", color)
	add_child(mi)
	return mi


static func _ramp(colors: Array, offsets: Array = []) -> Gradient:
	var g := Gradient.new()
	var offs := PackedFloat32Array()
	var cols := PackedColorArray()
	for i in colors.size():
		offs.append(float(offsets[i]) if i < offsets.size() else float(i) / float(maxi(colors.size() - 1, 1)))
		cols.append(colors[i])
	g.offsets = offs
	g.colors = cols
	return g


static func _curve(a: float, b: float) -> Curve:
	var c := Curve.new()
	c.add_point(Vector2(0.0, a))
	c.add_point(Vector2(1.0, b))
	return c


static func puff_texture() -> Texture2D:
	## A soft, lumpy puff (fire, smoke, steam, hot air): a round blob with cloudy
	## noise in it. Built from an Image with mipmaps (see UiTheme.soft_dot()).
	if _puff == null:
		var n := 64
		var fn := FastNoiseLite.new()
		fn.seed = 7
		fn.frequency = 0.08
		fn.fractal_octaves = 3
		var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
		for y in n:
			for x in n:
				var d := Vector2(x + 0.5 - n * 0.5, y + 0.5 - n * 0.5).length() / (n * 0.5)
				var r := clampf(1.0 - d, 0.0, 1.0)
				var soft := r * r * (3.0 - 2.0 * r)
				var cloud := clampf(0.6 + 0.9 * fn.get_noise_2d(x, y), 0.15, 1.0)
				img.set_pixel(x, y, Color(1, 1, 1, clampf(soft * cloud * 1.25, 0.0, 1.0)))
		img.generate_mipmaps()
		_puff = ImageTexture.create_from_image(img)
	return _puff


static func noise_texture() -> Texture2D:
	## Seamless cloudy noise for the flames and beams to scroll along.
	if _noise == null:
		var fn := FastNoiseLite.new()
		fn.seed = 3
		fn.frequency = 0.03
		fn.fractal_octaves = 3
		var img := fn.get_seamless_image(128, 128)
		img.convert(Image.FORMAT_RGBA8)
		img.generate_mipmaps()
		_noise = ImageTexture.create_from_image(img)
	return _noise


static func _tube_mesh() -> ArrayMesh:
	## A unit tube: x, y round it (radius 1), UV.x round it, UV.y = 0..1 along it.
	## The cone shader gives it its length and widths.
	if _tube == null:
		var seg := 16
		var rows := 12
		var verts := PackedVector3Array()
		var norms := PackedVector3Array()
		var uvs := PackedVector2Array()
		for j in rows + 1:
			for i in seg + 1:
				var a := TAU * i / seg
				var v := Vector3(cos(a), sin(a), 0.0)
				verts.append(v)
				norms.append(v)
				uvs.append(Vector2(float(i) / seg, float(j) / rows))
		var idx := PackedInt32Array()
		for j in rows:
			for i in seg:
				var a := j * (seg + 1) + i
				var b := a + seg + 1
				idx.append_array([a, b, a + 1, a + 1, b, b + 1])
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = verts
		arr[Mesh.ARRAY_NORMAL] = norms
		arr[Mesh.ARRAY_TEX_UV] = uvs
		arr[Mesh.ARRAY_INDEX] = idx
		_tube = ArrayMesh.new()
		_tube.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return _tube


static var _strip: ArrayMesh


static func _strip_mesh() -> ArrayMesh:
	## For the laser (heat_beam.gdshader): UV.x across, UV.y = 0..1 along.
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
