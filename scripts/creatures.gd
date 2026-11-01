class_name Creatures
extends RefCounted
## Low-poly 3D models for the helpers, built in code from MeshKit primitives.
## Each model faces -Z and stands on y = 0. Parts that animate (flippers,
## feet) are separate child nodes; everything else is one vertex-coloured mesh.

const PENGUIN_BLACK := Color(0.08, 0.1, 0.15)
const PENGUIN_WHITE := Color(0.97, 0.97, 0.95)
const BEAK := Color(1.0, 0.56, 0.12)
const SCARVES := [Color(0.85, 0.18, 0.2), Color(0.2, 0.55, 0.9), Color(0.98, 0.78, 0.2),
	Color(0.35, 0.75, 0.35), Color(0.75, 0.35, 0.85)]
const TOWELS := [Color(0.97, 0.97, 0.94), Color(0.65, 0.82, 0.98), Color(1.0, 0.75, 0.82), Color(1.0, 0.9, 0.55)]
const SKINS := [Color(0.98, 0.78, 0.66), Color(0.86, 0.62, 0.46), Color(0.6, 0.4, 0.28), Color(0.95, 0.72, 0.58)]

static var _cache := {}


static func _mesh_instance(mesh: Mesh, parent: Node3D, pos: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = MeshKit.material()
	mi.position = pos
	parent.add_child(mi)
	return mi


# =====================================================================================
# Penguin with a tiny torch (about 0.75 m tall)
# =====================================================================================
static func penguin(variant: int) -> Node3D:
	## Children: Body (the rig that rolls and leans), and under it FlipperL,
	## FlipperR, FootL, FootR (pivots), and Nozzle (where the torch flame comes out).
	## The model is made in Blender: art/blender/build_penguin.py.
	var root := Node3D.new()
	var body := Node3D.new()
	body.name = "Body"
	root.add_child(body)
	_model_part(Models.mesh("penguin", "Body"), body, SCARVES[variant % SCARVES.size()])
	for side in [-1.0, 1.0]:
		var flipper := Node3D.new()
		flipper.name = "FlipperL" if side < 0.0 else "FlipperR"
		flipper.position = Vector3(0.205 * side, 0.52, 0.0)
		body.add_child(flipper)
		_model_part(Models.mesh("penguin", flipper.name), flipper)
		var foot := Node3D.new()
		foot.name = "FootL" if side < 0.0 else "FootR"
		foot.position = Vector3(0.085 * side, 0.03, -0.04)
		foot.rotation.y = -0.25 * side   # toes out a little
		root.add_child(foot)
		_model_part(Models.mesh("penguin", "Foot"), foot)
	var nozzle := Node3D.new()
	nozzle.name = "Nozzle"
	nozzle.position = Vector3(0.13, 0.2, -0.36)
	body.add_child(nozzle)
	return root


static func _model_part(mesh: Mesh, parent: Node3D, scarf: Variant = null) -> MeshInstance3D:
	## A part of a Blender model. The surface whose material is called "scarf"
	## gets the given colour.
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	if scarf != null:
		for i in mesh.get_surface_count():
			var m := mesh.surface_get_material(i)
			if m != null and m.resource_name.begins_with("scarf") and not m.resource_name.contains("fringe"):
				var key := "scarf_mat_%s" % (scarf as Color).to_html()
				if not _cache.has(key):
					var sm := (m as StandardMaterial3D).duplicate() as StandardMaterial3D
					sm.albedo_color = scarf
					_cache[key] = sm
				mi.set_surface_override_material(i, _cache[key])
	parent.add_child(mi)
	return mi


# =====================================================================================
# Sauna crew member: towel, turban, bucket of hot stones (about 1.25 m tall)
# =====================================================================================
static func sauna(variant: int) -> Node3D:
	## Children: Body (rig), Bucket (where the steam comes from), FootL, FootR.
	## The model is made in Blender: art/blender/build_characters.py.
	var root := Node3D.new()
	var body := Node3D.new()
	body.name = "Body"
	root.add_child(body)
	var towel: Color = TOWELS[variant % TOWELS.size()]
	var skin: Color = SKINS[(variant / TOWELS.size() + variant) % SKINS.size()]
	var colours := {"towel": towel, "towel_stripe": towel.darkened(0.25), "skin": skin}
	body.add_child(Models.baked_instance(Models.baked("characters", "SaunaBody", colours)))
	var bucket := Node3D.new()
	bucket.name = "Bucket"
	bucket.position = Vector3(0, 0.7, -0.27)
	body.add_child(bucket)
	for side in [-1.0, 1.0]:
		var foot := Node3D.new()
		foot.name = "FootL" if side < 0.0 else "FootR"
		foot.position = Vector3(0.085 * side, 0.0, 0.0)
		root.add_child(foot)
		foot.add_child(Models.baked_instance(Models.baked("characters", "SaunaLeg", {"skin": skin})))
	return root


# =====================================================================================
# Kevin, the adopted volcano (with googly eyes)
# =====================================================================================
static func volcano() -> Node3D:
	## Children: Lava (the crater's glow), EyeL/EyeR (pivots; their child Pupil looks around).
	var root := Node3D.new()
	var body := MeshInstance3D.new()
	body.name = "Body"
	body.mesh = _volcano_mesh()
	body.material_override = Scenery.rock_material(0.35)
	root.add_child(body)
	# A smile under the eyes (the face looks along +Z).
	var st := MeshKit.begin()
	var prev := Vector3.INF
	for k in 9:
		var t := -1.0 + 2.0 * k / 8.0
		var ang := t * 0.24
		var y := 6.25 - 0.55 * (1.0 - t * t)
		var r := _volcano_radius(y) + 0.12
		var p := Vector3(sin(ang) * r, y, cos(ang) * r)
		if prev.is_finite():
			MeshKit.cylinder(st, prev, p, 0.2, 0.2, Color(0.12, 0.05, 0.04), 6, false)
		MeshKit.ellipsoid(st, p, Vector3.ONE * 0.2, Color(0.12, 0.05, 0.04), Basis.IDENTITY, 4, 6)
		prev = p
	for side in [-1.0, 1.0]:   # rosy (well, glowing) cheeks
		var ang: float = 0.42 * side
		var y := 6.9
		var r := _volcano_radius(y) - 0.05
		MeshKit.ellipsoid(st, Vector3(sin(ang) * r, y, cos(ang) * r), Vector3(0.7, 0.45, 0.3),
				Color(1.0, 0.45, 0.35), Basis(Vector3.UP, ang), 5, 8)
	var face := MeshInstance3D.new()
	face.mesh = MeshKit.finish(st)
	face.material_override = MeshKit.material()
	root.add_child(face)
	var lava := MeshInstance3D.new()
	lava.name = "Lava"
	var disk := CylinderMesh.new()
	disk.top_radius = 1.85
	disk.bottom_radius = 1.85
	disk.height = 0.3
	disk.radial_segments = 20
	lava.mesh = disk
	lava.position = Vector3(0, 12.55, 0)
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.albedo_color = Color(1.0, 0.55, 0.15)
	lava.material_override = glow
	root.add_child(lava)
	# Googly eyes on the side facing the glacier (+Z after the root is turned).
	var white := StandardMaterial3D.new()
	white.albedo_color = Color(0.98, 0.98, 0.96)
	white.roughness = 0.3
	var black := StandardMaterial3D.new()
	black.albedo_color = Color(0.03, 0.03, 0.04)
	black.roughness = 0.2
	for side in [-1.0, 1.0]:
		var ang: float = 0.33 * side
		var eye := Node3D.new()
		eye.name = "EyeL" if side < 0.0 else "EyeR"
		var er := _volcano_radius(8.4) + 0.55
		eye.position = Vector3(sin(ang) * er, 8.4, cos(ang) * er)
		root.add_child(eye)
		var ball := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 1.25
		sm.height = 2.5
		ball.mesh = sm
		ball.material_override = white
		eye.add_child(ball)
		var pupil := MeshInstance3D.new()
		pupil.name = "Pupil"
		var pm := SphereMesh.new()
		pm.radius = 0.6
		pm.height = 1.2
		pupil.mesh = pm
		pupil.material_override = black
		pupil.position = Vector3(0, 0, 0.85)
		eye.add_child(pupil)
	return root


# Kevin's shape: (height, radius) up the side, then over the crater's lip.
const VOLCANO_PROFILE := [[0.0, 10.0], [1.2, 8.6], [3.0, 7.3], [5.5, 5.9], [8.0, 4.6], [10.4, 3.4],
	[12.2, 2.6], [13.0, 2.35], [12.9, 1.95], [12.4, 1.8]]
const LAVA_STREAKS := [[0.95, 4.0], [3.05, 6.5], [5.0, 2.5]]   # angle, lowest height


static func _volcano_radius(y: float) -> float:
	for i in VOLCANO_PROFILE.size() - 1:
		var a: Array = VOLCANO_PROFILE[i]
		var b: Array = VOLCANO_PROFILE[i + 1]
		if y <= b[0]:
			return lerpf(a[1], b[1], clampf((y - a[0]) / maxf(b[0] - a[0], 0.001), 0.0, 1.0))
	return VOLCANO_PROFILE[6][1]


static func _volcano_mesh() -> ArrayMesh:
	## A lumpy cone with a crater. Vertex colour = rock tint; alpha 0 = lava.
	if _cache.has("volcano"):
		return _cache["volcano"]
	var noise := FastNoiseLite.new()
	noise.seed = 1977
	noise.frequency = 0.6
	var segs := 44
	var rings := VOLCANO_PROFILE.size()
	var pts := []
	for r in rings:
		var prof: Array = VOLCANO_PROFILE[r]
		var row := []
		for sg in segs:
			var a := TAU * float(sg) / segs
			var lump := 1.0 + 0.08 * noise.get_noise_2d(cos(a) * 3.0, prof[0] * 0.35 + sin(a) * 3.0)
			if r >= rings - 3:
				lump = 1.0 + 0.03 * noise.get_noise_2d(cos(a) * 3.0, sin(a) * 3.0)
			var rad: float = prof[1] * lump
			row.append(Vector3(sin(a) * rad, prof[0], cos(a) * rad))
		pts.append(row)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rock := Color(0.36, 0.29, 0.26)
	for r in rings - 1:
		for sg in segs:
			var s2 := (sg + 1) % segs
			var quad := [pts[r][sg], pts[r][s2], pts[r + 1][s2], pts[r + 1][sg]]
			var cols := []
			for q in [[r, sg], [r, s2], [r + 1, s2], [r + 1, sg]]:
				cols.append(_volcano_color(q[0], q[1], segs, rock))
			for tri in [[0, 2, 1], [0, 3, 2]]:
				for t in tri:
					st.set_color(cols[t])
					st.add_vertex(quad[t])
	st.generate_normals()
	var mesh := st.commit()
	_cache["volcano"] = mesh
	return mesh


static func _volcano_color(ring: int, seg: int, segs: int, rock: Color) -> Color:
	var prof: Array = VOLCANO_PROFILE[ring]
	var y: float = prof[0]
	var a := TAU * float(seg) / segs
	if ring >= VOLCANO_PROFILE.size() - 3:
		return Color(0.2, 0.15, 0.14)   # scorched crater lip
	for streak in LAVA_STREAKS:
		var da := absf(wrapf(a - float(streak[0]), -PI, PI))
		var width := lerpf(0.05, 0.2, clampf((y - float(streak[1])) / 8.0, 0.0, 1.0))
		if y >= float(streak[1]) and da < width:
			return Color(1.0, 0.45, 0.1, 0.0)
	var shade := 0.9 + 0.2 * fmod(float(seg * 7 + ring * 3), 5.0) / 5.0
	return Color(rock.r * shade, rock.g * shade, rock.b * shade)
