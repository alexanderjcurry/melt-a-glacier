class_name Props
extends RefCounted
## Small models built in code from MeshKit pieces: the six heat tools (held in
## your hand and hung on the shed's tool wall) and the things on the upgrade
## bench. Each one is a single vertex-coloured mesh.
##
## Tools point their business end along -Z, about 0.25 m in front of the
## origin, with the grip below the origin (that's how the player holds them).
## Bench props stand on y = 0 with their front facing -Z.

const GOLD := Color(1.0, 0.8, 0.25)
const DARK := Color(0.16, 0.16, 0.19)
const STEEL := Color(0.72, 0.73, 0.77)
const BRASS := Color(0.86, 0.66, 0.27)
const WOOD := Color(0.55, 0.36, 0.2)
const WHITE := Color(0.95, 0.94, 0.9)
const RED := Color(0.85, 0.14, 0.1)

static var _cache := {}


static func tool_mesh(i: int, golden: bool = false) -> ArrayMesh:
	var key := "tool_%d_%s" % [i, golden]
	if _cache.has(key):
		return _cache[key]
	var st := MeshKit.begin()
	var col: Color = Balance.TOOLS[clampi(i, 0, Balance.TOOLS.size() - 1)].color
	match i:
		0: _hair_dryer(st, GOLD if golden else col)
		1: _heat_lamp(st, col)
		2: _blowtorch(st, col)
		3: _flamethrower(st, col)
		4: _lava_hose(st, col)
		_: _mirror_remote(st, col)
	var mesh := MeshKit.finish(st)
	_cache[key] = mesh
	return mesh


static func upgrade_mesh(key: String) -> ArrayMesh:
	var ck := "upgrade_" + key
	if _cache.has(ck):
		return _cache[ck]
	var st := MeshKit.begin()
	match key:
		"heat": _thermometer(st)
		"nozzle": _big_nozzle(st)
		"reach": _target(st)
		"sell": _water_jug(st)
		"boots": _boots(st)
		_: _fuel_tank(st)
	var mesh := MeshKit.finish(st)
	_cache[ck] = mesh
	return mesh


static func book_mesh() -> ArrayMesh:
	## The catalogue, lying open. Spine along Z, pages spread along X, read from -Z.
	if _cache.has("book"):
		return _cache["book"]
	var st := MeshKit.begin()
	var cover := Color(0.55, 0.13, 0.12)
	var paper := Color(0.97, 0.94, 0.84)
	for side in [-1.0, 1.0]:
		var tilt := Basis(Vector3.BACK, 0.1 * side)   # the pages rise a little toward their edges
		MeshKit.box(st, Vector3(0.13 * side, 0.012, 0.0), Vector3(0.27, 0.014, 0.36), cover, tilt)
		MeshKit.box(st, Vector3(0.125 * side, 0.03, 0.0), Vector3(0.245, 0.03, 0.335), paper, tilt)
		# A few lines of "text" and a picture on each page.
		for k in 5:
			var w := 0.17 if k % 2 == 0 else 0.13
			MeshKit.box(st, Vector3(0.125 * side, 0.046, -0.11 + k * 0.035),
					Vector3(w, 0.002, 0.008), Color(0.45, 0.38, 0.32), tilt)
		MeshKit.box(st, Vector3(0.125 * side, 0.047, 0.1), Vector3(0.12, 0.002, 0.08),
				Color(0.85, 0.45, 0.2) if side < 0.0 else Color(0.35, 0.6, 0.85), tilt)
	MeshKit.box(st, Vector3(0.0, 0.035, 0.0), Vector3(0.02, 0.03, 0.335), paper.darkened(0.08))
	MeshKit.box(st, Vector3(0.02, 0.05, 0.12), Vector3(0.012, 0.003, 0.2), RED)   # bookmark ribbon
	var mesh := MeshKit.finish(st)
	_cache["book"] = mesh
	return mesh


static func instance(mesh: Mesh) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = MeshKit.material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


# =====================================================================================
# The tools
# =====================================================================================
static func _hair_dryer(st: SurfaceTool, col: Color) -> void:
	MeshKit.cylinder(st, Vector3(0, 0, 0.09), Vector3(0, 0, -0.15), 0.06, 0.05, col, 16)
	MeshKit.ellipsoid(st, Vector3(0, 0, 0.09), Vector3(0.06, 0.06, 0.035), col.darkened(0.1), Basis.IDENTITY, 8, 16)
	MeshKit.cylinder(st, Vector3(0, 0, 0.118), Vector3(0, 0, 0.128), 0.044, 0.044, DARK, 16)
	MeshKit.cylinder(st, Vector3(0, 0, -0.03), Vector3(0, 0, -0.015), 0.0575, 0.0572, WHITE, 16)
	MeshKit.cylinder(st, Vector3(0, 0, -0.15), Vector3(0, 0, -0.25), 0.042, 0.034, Color(0.24, 0.24, 0.28), 14)
	MeshKit.cylinder(st, Vector3(0, 0, -0.24), Vector3(0, 0, -0.255), 0.037, 0.037, Color(0.3, 0.3, 0.34), 14)
	MeshKit.cylinder(st, Vector3(0, 0, -0.25), Vector3(0, 0, -0.257), 0.029, 0.029, DARK, 14)
	MeshKit.cylinder(st, Vector3(0, -0.03, 0.03), Vector3(0, -0.2, 0.075), 0.03, 0.026, col.darkened(0.15), 12)
	MeshKit.ellipsoid(st, Vector3(0, -0.2, 0.075), Vector3(0.026, 0.018, 0.026), col.darkened(0.2), Basis.IDENTITY, 5, 10)
	MeshKit.box(st, Vector3(0, -0.075, 0.012), Vector3(0.02, 0.04, 0.014), WHITE, Basis(Vector3.RIGHT, 0.26))
	MeshKit.cylinder(st, Vector3(0, -0.21, 0.08), Vector3(0, -0.27, 0.11), 0.008, 0.008, DARK, 6)


static func _heat_lamp(st: SurfaceTool, col: Color) -> void:
	MeshKit.cylinder(st, Vector3(0, 0, 0.03), Vector3(0, 0, -0.16), 0.045, 0.13, col, 18)
	MeshKit.cylinder(st, Vector3(0, 0, -0.158), Vector3(0, 0, -0.172), 0.134, 0.134, col.darkened(0.25), 18)
	MeshKit.ellipsoid(st, Vector3(0, 0, -0.15), Vector3(0.11, 0.11, 0.06), Color(1.0, 0.5, 0.22), Basis.IDENTITY, 8, 18)
	MeshKit.ellipsoid(st, Vector3(0.03, 0.035, -0.19), Vector3(0.025, 0.02, 0.012), Color(1.0, 0.85, 0.6), Basis.IDENTITY, 4, 8)
	MeshKit.cylinder(st, Vector3(0, 0, 0.03), Vector3(0, 0, 0.1), 0.032, 0.032, DARK, 12)
	MeshKit.box(st, Vector3(0, 0, 0.12), Vector3(0.075, 0.075, 0.05), col.darkened(0.3))
	MeshKit.cylinder(st, Vector3(0, -0.03, 0.1), Vector3(0, -0.2, 0.125), 0.026, 0.024, Color(0.24, 0.22, 0.22), 10)
	MeshKit.ellipsoid(st, Vector3(0, -0.2, 0.125), Vector3(0.024, 0.016, 0.024), Color(0.24, 0.22, 0.22), Basis.IDENTITY, 4, 10)
	# Wire guard over the bulb.
	for k in 3:
		var y := -0.06 + 0.06 * k
		MeshKit.box(st, Vector3(0, y, -0.205), Vector3(0.2 - absf(y) * 0.9, 0.008, 0.008), STEEL)


static func _blowtorch(st: SurfaceTool, col: Color) -> void:
	MeshKit.cylinder(st, Vector3(0, -0.24, 0.05), Vector3(0, -0.05, 0.05), 0.055, 0.055, col, 16)
	MeshKit.ellipsoid(st, Vector3(0, -0.05, 0.05), Vector3(0.055, 0.03, 0.055), col, Basis.IDENTITY, 6, 16)
	MeshKit.cylinder(st, Vector3(0, -0.245, 0.05), Vector3(0, -0.225, 0.05), 0.057, 0.057, col.darkened(0.35), 16)
	MeshKit.cylinder(st, Vector3(0, -0.17, 0.05), Vector3(0, -0.11, 0.05), 0.0555, 0.0555, WHITE, 16)
	MeshKit.cylinder(st, Vector3(0, -0.155, 0.05), Vector3(0, -0.125, 0.05), 0.056, 0.056, Color(1.0, 0.6, 0.15), 16)
	MeshKit.box(st, Vector3(0, -0.005, 0.045), Vector3(0.05, 0.05, 0.07), BRASS)
	MeshKit.cylinder(st, Vector3(0.02, -0.005, 0.05), Vector3(0.06, -0.005, 0.05), 0.012, 0.012, BRASS.darkened(0.2), 8)
	MeshKit.cylinder(st, Vector3(0.06, -0.005, 0.05), Vector3(0.075, -0.005, 0.05), 0.022, 0.022, RED, 12)
	MeshKit.cylinder(st, Vector3(-0.02, -0.005, 0.05), Vector3(-0.06, -0.005, 0.05), 0.012, 0.012, BRASS.darkened(0.2), 8)
	MeshKit.cylinder(st, Vector3(-0.06, -0.005, 0.05), Vector3(-0.075, -0.005, 0.05), 0.022, 0.022, RED, 12)
	MeshKit.cylinder(st, Vector3(0, 0.005, 0.02), Vector3(0, 0.005, -0.17), 0.013, 0.013, STEEL, 10)
	MeshKit.cylinder(st, Vector3(0, 0.005, -0.16), Vector3(0, 0.005, -0.26), 0.02, 0.025, Color(0.36, 0.36, 0.4), 12)
	MeshKit.cylinder(st, Vector3(0, 0.005, -0.255), Vector3(0, 0.005, -0.262), 0.019, 0.019, DARK, 12)
	MeshKit.box(st, Vector3(0, -0.035, -0.005), Vector3(0.016, 0.03, 0.02), DARK)


static func _flamethrower(st: SurfaceTool, col: Color) -> void:
	var gun := Color(0.3, 0.31, 0.34)
	MeshKit.cylinder(st, Vector3(0, 0, 0.17), Vector3(0, 0, -0.27), 0.028, 0.028, gun, 12)
	MeshKit.cylinder(st, Vector3(0, 0, -0.03), Vector3(0, 0, -0.22), 0.046, 0.046, Color(0.2, 0.2, 0.22), 14)
	for k in 5:
		var z := -0.045 - 0.036 * k
		MeshKit.cylinder(st, Vector3(0, 0, z), Vector3(0, 0, z - 0.008), 0.049, 0.049, Color(0.42, 0.42, 0.45), 14)
	MeshKit.cylinder(st, Vector3(0, 0, -0.265), Vector3(0, 0, -0.29), 0.034, 0.034, DARK, 12)
	MeshKit.cylinder(st, Vector3(0, -0.042, -0.23), Vector3(0, -0.042, -0.29), 0.009, 0.009, Color(1.0, 0.55, 0.15), 8)
	# The fuel tank underneath, with a hazard stripe and a gauge.
	MeshKit.cylinder(st, Vector3(0, -0.085, 0.16), Vector3(0, -0.085, -0.03), 0.055, 0.055, col, 16)
	MeshKit.ellipsoid(st, Vector3(0, -0.085, 0.16), Vector3(0.055, 0.055, 0.03), col.darkened(0.1), Basis.IDENTITY, 6, 16)
	MeshKit.ellipsoid(st, Vector3(0, -0.085, -0.03), Vector3(0.055, 0.055, 0.03), col.darkened(0.1), Basis.IDENTITY, 6, 16)
	MeshKit.cylinder(st, Vector3(0, -0.085, 0.05), Vector3(0, -0.085, 0.08), 0.0565, 0.0565, Color(1.0, 0.85, 0.2), 16)
	for side in [-1.0, 1.0]:
		MeshKit.cylinder(st, Vector3(0.05 * side, -0.075, 0.11), Vector3(0.062 * side, -0.075, 0.11), 0.02, 0.02, WHITE, 12)
	MeshKit.box(st, Vector3(0, -0.15, 0.2), Vector3(0.034, 0.12, 0.05), DARK, Basis(Vector3.RIGHT, 0.3))
	MeshKit.box(st, Vector3(0, -0.075, -0.12), Vector3(0.03, 0.1, 0.035), DARK, Basis(Vector3.RIGHT, -0.1))


static func _lava_hose(st: SurfaceTool, col: Color) -> void:
	MeshKit.cylinder(st, Vector3(0, 0, -0.02), Vector3(0, 0, -0.24), 0.042, 0.022, BRASS, 16)
	MeshKit.cylinder(st, Vector3(0, 0, 0.0), Vector3(0, 0, -0.035), 0.048, 0.048, BRASS.darkened(0.25), 16)
	MeshKit.cylinder(st, Vector3(0, 0, -0.16), Vector3(0, 0, -0.175), 0.034, 0.033, BRASS.darkened(0.25), 14)
	MeshKit.ellipsoid(st, Vector3(0, 0, -0.243), Vector3(0.019, 0.019, 0.012), Color(1.0, 0.6, 0.12), Basis.IDENTITY, 5, 10)
	MeshKit.box(st, Vector3(0, 0.05, -0.07), Vector3(0.014, 0.014, 0.1), Color(0.8, 0.12, 0.08), Basis(Vector3.RIGHT, 0.2))
	MeshKit.box(st, Vector3(0, 0.035, -0.02), Vector3(0.02, 0.03, 0.02), BRASS.darkened(0.3))
	MeshKit.box(st, Vector3(0, -0.085, 0.0), Vector3(0.036, 0.12, 0.046), Color(0.16, 0.13, 0.11), Basis(Vector3.RIGHT, 0.25))
	# The hose: a corrugated tube curving back and down.
	var p0 := Vector3(0, 0, 0.02)
	var p1 := Vector3(0, 0, 0.24)
	var p2 := Vector3(0, -0.28, 0.26)
	var prev := p0
	for k in range(1, 9):
		var t := float(k) / 8.0
		var p := p0.lerp(p1, t).lerp(p1.lerp(p2, t), t)
		MeshKit.cylinder(st, prev, p, 0.026, 0.026, col.darkened(0.1), 12, false)
		MeshKit.ellipsoid(st, p, Vector3(0.03, 0.03, 0.03), col.darkened(0.35), Basis.IDENTITY, 4, 12)
		prev = p


static func _mirror_remote(st: SurfaceTool, col: Color) -> void:
	MeshKit.box(st, Vector3(0, -0.02, 0.0), Vector3(0.09, 0.045, 0.22), col)
	MeshKit.box(st, Vector3(0, -0.02, 0.0), Vector3(0.094, 0.02, 0.224), col.darkened(0.3))
	MeshKit.box(st, Vector3(0, 0.003, 0.05), Vector3(0.062, 0.004, 0.065), Color(0.1, 0.22, 0.38))
	MeshKit.box(st, Vector3(-0.012, 0.0055, 0.04), Vector3(0.02, 0.002, 0.02), Color(0.4, 0.95, 0.6))
	MeshKit.cylinder(st, Vector3(0, 0.0, -0.045), Vector3(0, 0.016, -0.045), 0.019, 0.019, RED, 14)
	var dots := [Color(1.0, 0.85, 0.2), Color(0.3, 0.8, 0.35), Color(0.3, 0.55, 0.95)]
	for k in 3:
		MeshKit.cylinder(st, Vector3(-0.026 + 0.026 * k, 0.0, -0.085), Vector3(-0.026 + 0.026 * k, 0.007, -0.085), 0.008, 0.008, dots[k], 8)
	MeshKit.cylinder(st, Vector3(0.032, 0.0, -0.09), Vector3(0.032, 0.13, -0.13), 0.004, 0.003, STEEL, 6)
	MeshKit.ellipsoid(st, Vector3(0.032, 0.13, -0.13), Vector3(0.009, 0.009, 0.009), RED, Basis.IDENTITY, 4, 8)
	# A tiny satellite dish, so you know what it talks to.
	MeshKit.cylinder(st, Vector3(0, 0.0, 0.085), Vector3(0, 0.03, 0.085), 0.008, 0.008, STEEL, 8)
	MeshKit.cylinder(st, Vector3(0, 0.025, 0.085), Vector3(0, 0.06, 0.085), 0.012, 0.06, WHITE, 16)
	MeshKit.cylinder(st, Vector3(0, 0.06, 0.085), Vector3(0, 0.1, 0.085), 0.004, 0.004, STEEL, 6)
	MeshKit.ellipsoid(st, Vector3(0, 0.1, 0.085), Vector3(0.01, 0.01, 0.01), DARK, Basis.IDENTITY, 4, 8)


# =====================================================================================
# The upgrade bench
# =====================================================================================
static func _thermometer(st: SurfaceTool) -> void:
	MeshKit.box(st, Vector3(0, 0.02, 0.0), Vector3(0.2, 0.04, 0.12), WOOD)
	MeshKit.box(st, Vector3(0, 0.29, 0.02), Vector3(0.13, 0.5, 0.02), WHITE)
	MeshKit.box(st, Vector3(0, 0.29, 0.025), Vector3(0.145, 0.515, 0.015), Color(0.75, 0.2, 0.15))
	MeshKit.cylinder(st, Vector3(0, 0.1, 0.0), Vector3(0, 0.42, 0.0), 0.014, 0.014, RED, 10)
	MeshKit.cylinder(st, Vector3(0, 0.42, 0.0), Vector3(0, 0.5, 0.0), 0.014, 0.014, Color(0.82, 0.88, 0.93), 10)
	MeshKit.ellipsoid(st, Vector3(0, 0.09, 0.0), Vector3(0.032, 0.032, 0.032), RED, Basis.IDENTITY, 6, 12)
	for k in 8:
		var w := 0.03 if k % 2 == 0 else 0.018
		MeshKit.box(st, Vector3(-0.03 - w * 0.5, 0.14 + 0.045 * k, 0.008), Vector3(w, 0.006, 0.004), DARK)
		MeshKit.box(st, Vector3(0.03 + w * 0.5, 0.14 + 0.045 * k, 0.008), Vector3(w, 0.006, 0.004), DARK)


static func _big_nozzle(st: SurfaceTool) -> void:
	MeshKit.box(st, Vector3(0, 0.03, 0.04), Vector3(0.2, 0.06, 0.16), WOOD)
	MeshKit.cylinder(st, Vector3(0, 0.06, 0.06), Vector3(0, 0.16, 0.06), 0.016, 0.016, DARK, 8)
	MeshKit.cylinder(st, Vector3(0, 0.2, 0.14), Vector3(0, 0.2, -0.04), 0.03, 0.05, BRASS.darkened(0.15), 16)
	MeshKit.cylinder(st, Vector3(0, 0.2, 0.14), Vector3(0, 0.2, 0.16), 0.036, 0.036, BRASS.darkened(0.35), 16)
	MeshKit.cylinder(st, Vector3(0, 0.2, -0.04), Vector3(0, 0.2, -0.15), 0.05, 0.15, BRASS, 20, false)
	MeshKit.cylinder(st, Vector3(0, 0.2, -0.04), Vector3(0, 0.2, -0.15), 0.05, 0.15, BRASS.darkened(0.35), 20, false, true)
	MeshKit.cylinder(st, Vector3(0, 0.2, -0.14), Vector3(0, 0.2, -0.152), 0.148, 0.154, BRASS.darkened(0.1), 20, false)
	MeshKit.cylinder(st, Vector3(0, 0.2, -0.03), Vector3(0, 0.2, -0.045), 0.045, 0.045, DARK, 16)
	MeshKit.box(st, Vector3(0, 0.12, 0.06), Vector3(0.06, 0.03, 0.03), BRASS.darkened(0.3))


static func _target(st: SurfaceTool) -> void:
	MeshKit.cylinder(st, Vector3(0, 0, 0.04), Vector3(0, 0.03, 0.04), 0.09, 0.09, Color(0.3, 0.3, 0.33), 16)
	MeshKit.cylinder(st, Vector3(0, 0.03, 0.04), Vector3(0, 0.2, 0.04), 0.018, 0.018, STEEL, 10)
	MeshKit.cylinder(st, Vector3(0, 0.2, 0.04), Vector3(0, 0.33, 0.04), 0.014, 0.014, STEEL.lightened(0.15), 10)
	MeshKit.cylinder(st, Vector3(0, 0.33, 0.04), Vector3(0, 0.44, 0.04), 0.01, 0.01, STEEL.lightened(0.3), 10)
	MeshKit.cylinder(st, Vector3(0, 0.19, 0.04), Vector3(0, 0.215, 0.04), 0.023, 0.023, DARK, 10)
	MeshKit.cylinder(st, Vector3(0, 0.32, 0.04), Vector3(0, 0.345, 0.04), 0.019, 0.019, DARK, 10)
	var rings := [[0.15, WHITE], [0.12, RED], [0.085, WHITE], [0.05, RED], [0.02, Color(1.0, 0.85, 0.2)]]
	for k in rings.size():
		var z := 0.03 - 0.004 * k
		MeshKit.cylinder(st, Vector3(0, 0.44, z), Vector3(0, 0.44, z - 0.01), rings[k][0], rings[k][0], rings[k][1], 24)
	MeshKit.box(st, Vector3(0.1, 0.5, -0.015), Vector3(0.012, 0.012, 0.12), WOOD, Basis(Vector3.UP, 0.5) * Basis(Vector3.RIGHT, 0.3))


static func _water_jug(st: SurfaceTool) -> void:
	var blue := Color(0.55, 0.78, 0.95)
	MeshKit.cylinder(st, Vector3(-0.05, 0, 0.02), Vector3(-0.05, 0.25, 0.02), 0.09, 0.09, blue, 18)
	MeshKit.cylinder(st, Vector3(-0.05, 0.25, 0.02), Vector3(-0.05, 0.31, 0.02), 0.09, 0.034, blue, 18, false)
	MeshKit.cylinder(st, Vector3(-0.05, 0.31, 0.02), Vector3(-0.05, 0.35, 0.02), 0.03, 0.03, blue.lightened(0.2), 12)
	MeshKit.cylinder(st, Vector3(-0.05, 0.35, 0.02), Vector3(-0.05, 0.375, 0.02), 0.034, 0.034, Color(0.2, 0.45, 0.85), 12)
	MeshKit.cylinder(st, Vector3(-0.05, 0.08, 0.02), Vector3(-0.05, 0.18, 0.02), 0.0915, 0.0915, WHITE, 18)
	MeshKit.ellipsoid(st, Vector3(-0.05, 0.13, -0.072), Vector3(0.022, 0.03, 0.004), Color(0.25, 0.55, 0.95), Basis.IDENTITY, 5, 10)
	# Stacks of gold coins: what the water sells for.
	var coin := Color(0.98, 0.76, 0.2)
	for k in 6:
		var off := Vector3(0.006 * sin(k * 2.1), 0.0, 0.006 * cos(k * 1.7))
		MeshKit.cylinder(st, Vector3(0.11, 0.012 * k, -0.05) + off, Vector3(0.11, 0.012 * k + 0.011, -0.05) + off,
				0.035, 0.035, coin if k % 2 == 0 else coin.darkened(0.08), 16)
	for k in 3:
		MeshKit.cylinder(st, Vector3(0.12, 0.012 * k, 0.06), Vector3(0.12, 0.012 * k + 0.011, 0.06), 0.035, 0.035, coin, 16)
	MeshKit.cylinder(st, Vector3(0.035, 0.036, -0.125), Vector3(0.035, 0.036, -0.136), 0.035, 0.035, coin, 16)   # one on its edge


static func _boots(st: SurfaceTool) -> void:
	var leather := Color(0.5, 0.29, 0.15)
	for side in [-1.0, 1.0]:
		var x: float = 0.075 * side
		MeshKit.box(st, Vector3(x, 0.045, -0.025), Vector3(0.085, 0.03, 0.23), Color(0.15, 0.13, 0.12))
		MeshKit.ellipsoid(st, Vector3(x, 0.09, -0.07), Vector3(0.046, 0.046, 0.085), leather, Basis.IDENTITY, 6, 12)
		MeshKit.cylinder(st, Vector3(x, 0.06, 0.035), Vector3(x, 0.23, 0.04), 0.05, 0.052, leather, 14)
		MeshKit.cylinder(st, Vector3(x, 0.21, 0.04), Vector3(x, 0.245, 0.04), 0.056, 0.056, Color(0.78, 0.2, 0.16), 14)
		MeshKit.cylinder(st, Vector3(x, 0.23, 0.04), Vector3(x, 0.237, 0.04), 0.0565, 0.0565, WHITE, 14)
		for k in 4:
			MeshKit.box(st, Vector3(x, 0.1 + 0.03 * k, -0.012 - 0.004 * (3 - k)), Vector3(0.05, 0.007, 0.006), WHITE)
		for k in 4:   # the crampon spikes
			for s2 in [-1.0, 1.0]:
				var p := Vector3(x + 0.028 * s2, 0.03, -0.12 + 0.075 * k)
				MeshKit.cylinder(st, p, p + Vector3(0, -0.03, 0), 0.009, 0.0, STEEL, 6, false)


static func _fuel_tank(st: SurfaceTool) -> void:
	var red := Color(0.86, 0.16, 0.12)
	MeshKit.cylinder(st, Vector3(0, 0.03, 0), Vector3(0, 0.07, 0), 0.05, 0.04, Color(0.3, 0.3, 0.33), 14)
	MeshKit.cylinder(st, Vector3(0, 0.07, 0), Vector3(0, 0.33, 0), 0.072, 0.072, red, 18)
	MeshKit.ellipsoid(st, Vector3(0, 0.33, 0), Vector3(0.072, 0.08, 0.072), red, Basis.IDENTITY, 8, 18)
	MeshKit.cylinder(st, Vector3(0, 0.2, 0), Vector3(0, 0.235, 0), 0.0735, 0.0735, WHITE, 18)
	MeshKit.cylinder(st, Vector3(0, 0.15, -0.068), Vector3(0, 0.15, -0.08), 0.027, 0.027, WHITE, 14)
	MeshKit.box(st, Vector3(0.007, 0.157, -0.082), Vector3(0.004, 0.022, 0.003), RED, Basis(Vector3.BACK, -0.6))
	for k in 3:
		var a := k * TAU / 3.0 + PI / 2.0
		var dir := Vector3(cos(a), 0, sin(a))
		MeshKit.box(st, Vector3(0, 0.075, 0) + dir * 0.095, Vector3(0.065, 0.15, 0.012), WHITE, Basis(Vector3.UP, -a))
