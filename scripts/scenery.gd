class_name Scenery
extends RefCounted
## The valley around the glacier: mountains (one heightfield, rock and snow
## shaded per pixel), a sky with clouds, the lake and the meltwater stream.
## Everything is generated from the level description, so a new level with a
## different valley gets its own mountains.

const EXTENT := 230.0        # the mountains reach this far from the middle
const SAMPLES := 120         # grid cells across; spacing grows with distance
const WARP := 1.6            # how strongly the grid bunches up near the valley
const CENTER_Z := -5.0       # the grid's middle (the valley isn't centred on z = 0)
const HOLLOW_RADIUS := 14.0  # Kevin's flat spot (he's 20 m across)
const GAP_RADIUS := 7.0      # half-width of the gap you see Kevin through


# =====================================================================================
# Mountains
# =====================================================================================
static func floor_distance(v: Dictionary, x: float, z: float, hollow: Vector2, gap_to: Vector2) -> float:
	## Metres outside the flat valley floor (negative inside it).
	var hw: float = v.half_width + maxf(0.0, z - v.flare_z) * v.flare
	var d := maxf(absf(x) - hw, maxf(v.back_z - z, z - v.front_z))
	var lk: Array = v.lake
	var ex: float = (x - lk[0]) / lk[2]
	var ez: float = (z - lk[1]) / lk[3]
	d = minf(d, (sqrt(ex * ex + ez * ez) - 1.0) * minf(lk[2], lk[3]))
	if hollow.is_finite():
		var p := Vector2(x, z)
		d = minf(d, p.distance_to(hollow) - HOLLOW_RADIUS)
		d = minf(d, _segment_distance(p, hollow, gap_to) - GAP_RADIUS)
	return d


static func _segment_distance(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return p.distance_to(a + ab * t)


static func _axis(i: int) -> float:
	## Grid line i (0..SAMPLES) -> metres from the middle, closer together near it.
	var u := float(i) / SAMPLES * 2.0 - 1.0
	return signf(u) * EXTENT * pow(absf(u), WARP)


static func mountains(level: Dictionary, hollow: Vector2, detail: Texture2D) -> MeshInstance3D:
	## The ring of mountains around the valley as one mesh. `hollow` is a flat
	## spot outside the valley (Kevin the volcano lives there), with a gap
	## toward the glacier so you can see him.
	var v: Dictionary = level.valley
	var seed_base := int(level.seed)
	var ridged := FastNoiseLite.new()
	ridged.seed = seed_base + 41
	ridged.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	ridged.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	ridged.frequency = 0.012
	ridged.fractal_octaves = 5
	var soft := FastNoiseLite.new()
	soft.seed = seed_base + 42
	soft.frequency = 0.007
	soft.fractal_octaves = 2
	var tint := FastNoiseLite.new()
	tint.seed = seed_base + 43
	tint.frequency = 0.02
	var gap_to := Vector2(-17.0, -24.0) if hollow.x < 0.0 else Vector2(17.0, -24.0)
	var scale: float = v.get("peaks", 1.0)

	var n := SAMPLES + 1
	var xs := PackedFloat32Array()
	var zs := PackedFloat32Array()
	xs.resize(n)
	zs.resize(n)
	for i in n:
		xs[i] = _axis(i)
		zs[i] = CENTER_Z + _axis(i)
	var h := PackedFloat32Array()
	var outside := PackedByteArray()
	h.resize(n * n)
	outside.resize(n * n)
	for k in n:
		var z := zs[k]
		for i in n:
			var x := xs[i]
			var d := floor_distance(v, x, z, hollow, gap_to)
			var y := -1.5
			if d > 0.0:
				outside[k * n + i] = 1
				var rise := 1.0 - exp(-d / 11.0)
				var r := ridged.get_noise_2d(x, z) * 0.5 + 0.5
				var s := soft.get_noise_2d(x, z) * 0.5 + 0.5
				var top := 10.0 + 30.0 * r * r + 12.0 * s
				top *= 1.0 + clampf((d - 25.0) / 90.0, 0.0, 1.0) * 0.9   # bigger further out
				y = rise * top * scale - 0.6
			h[k * n + i] = y

	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	verts.resize(n * n)
	normals.resize(n * n)
	colors.resize(n * n)
	var rock_a := Color(0.44, 0.41, 0.38)
	var rock_b := Color(0.36, 0.37, 0.4)
	for k in n:
		for i in n:
			var idx := k * n + i
			var p := Vector3(xs[i], h[idx], zs[k])
			verts[idx] = p
			var i0 := maxi(i - 1, 0)
			var i1 := mini(i + 1, n - 1)
			var k0 := maxi(k - 1, 0)
			var k1 := mini(k + 1, n - 1)
			var dx := Vector3(xs[i1] - xs[i0], h[k * n + i1] - h[k * n + i0], 0.0)
			var dz := Vector3(0.0, h[k1 * n + i] - h[k0 * n + i], zs[k1] - zs[k0])
			normals[idx] = dz.cross(dx).normalized()
			colors[idx] = rock_a.lerp(rock_b, tint.get_noise_2d(p.x, p.z) * 0.5 + 0.5)

	var idxs := PackedInt32Array()
	for k in SAMPLES:
		for i in SAMPLES:
			var a := k * n + i
			var b := a + 1
			var c := a + n
			var dd := c + 1
			if outside[a] + outside[b] + outside[c] + outside[dd] == 0:
				continue   # flat valley floor: the ground plane covers it
			# Godot's front faces are clockwise seen from the front (above).
			idxs.append_array([a, b, dd, a, dd, c])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = idxs
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/mountain.gdshader")
	mat.set_shader_parameter("detail_tex", detail)
	mat.set_shader_parameter("snow_line", float(v.get("snow_line", 17.0)))
	mat.set_shader_parameter("glacier_source", Vector3(0.0, 0.0, float(v.back_z) - 7.0))
	var mi := MeshInstance3D.new()
	mi.name = "Mountains"
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


static var _rock_mats := {}


static func rock_material(foot: float = 0.0) -> ShaderMaterial:
	## The mountains' rock shader without snow, for boulders and Kevin.
	## foot = how much the bottom metres blend into the valley floor.
	if not _rock_mats.has(foot):
		var m := ShaderMaterial.new()
		m.shader = load("res://shaders/mountain.gdshader")
		m.set_shader_parameter("detail_tex", IceField.detail_texture(int(Levels.current().seed)))
		m.set_shader_parameter("snow_line", 1000.0)
		m.set_shader_parameter("foot_amount", foot)
		_rock_mats[foot] = m
	return _rock_mats[foot]


static func boulder_mesh(variant: int) -> ArrayMesh:
	## A lumpy, flat-bottomed rock about 1 m across.
	var noise := FastNoiseLite.new()
	noise.seed = 300 + variant
	noise.frequency = 1.1
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings := 7
	var segs := 10
	var pts := []
	for r in rings + 1:
		var phi := PI * float(r) / rings
		var row := []
		for sg in segs:
			var th := TAU * float(sg) / segs
			var dir := Vector3(sin(phi) * cos(th), cos(phi), sin(phi) * sin(th))
			var rad := 0.5 * (1.0 + 0.28 * noise.get_noise_3dv(dir * 1.5))
			var p := dir * rad * Vector3(1.0, 0.72, 0.9)
			p.y = maxf(p.y, -0.12)   # sits flat on the ground
			row.append(p)
		pts.append(row)
	var tint := Color(0.58, 0.56, 0.53).lerp(Color(0.5, 0.51, 0.54), float(variant % 3) / 2.0)
	for r in rings:
		for sg in segs:
			var s2 := (sg + 1) % segs
			var quad := [pts[r][sg], pts[r][s2], pts[r + 1][s2], pts[r + 1][sg]]
			for tri in [[0, 2, 1], [0, 3, 2]]:
				for t in tri:
					st.set_color(tint)
					st.add_vertex(quad[t])
	st.generate_normals()
	return st.commit()


static func pine_mesh(variant: int) -> ArrayMesh:
	## A pine tree about 4 m tall, with drooping layers of branches
	## (art/blender/build_nature.py).
	return Models.baked("nature", "Pine%d" % (variant % 4))


static func forest(spots: Array, shadows: bool) -> Node3D:
	## Pines at the given spots ([position, scale, turn]), one MultiMesh per
	## tree shape, so a whole forest is only a few draw calls.
	var root := Node3D.new()
	root.name = "Forest"
	var variants := 4
	for v in variants:
		var mine := []
		for i in spots.size():
			if i % variants == v:
				mine.append(spots[i])
		if mine.is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = pine_mesh(v)
		mm.instance_count = mine.size()
		for i in mine.size():
			var sp: Array = mine[i]
			var b := Basis(Vector3.UP, float(sp[2])).scaled(Vector3.ONE * float(sp[1]))
			mm.set_instance_transform(i, Transform3D(b, sp[0]))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = MeshKit.material()
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mmi)
	return root


static func near_stream(level: Dictionary, x: float, z: float, margin: float) -> bool:
	var pts: Array = level.valley.get("stream", [])
	for i in pts.size() - 1:
		if _segment_distance(Vector2(x, z), pts[i], pts[i + 1]) < margin:
			return true
	return false


# =====================================================================================
# Sky
# =====================================================================================
static func sky(seed_base: int) -> Sky:
	var shader_mat := ShaderMaterial.new()
	shader_mat.shader = load("res://shaders/sky.gdshader")
	var big := FastNoiseLite.new()
	big.seed = seed_base + 51
	big.frequency = 0.012
	big.fractal_octaves = 5
	var puff := FastNoiseLite.new()
	puff.seed = seed_base + 52
	puff.noise_type = FastNoiseLite.TYPE_CELLULAR
	puff.cellular_return_type = FastNoiseLite.RETURN_DISTANCE
	puff.frequency = 0.03
	puff.fractal_type = FastNoiseLite.FRACTAL_FBM
	puff.fractal_octaves = 3
	var a := big.get_seamless_image(256, 256)
	var b := puff.get_seamless_image(256, 256)
	a.generate_mipmaps()
	b.generate_mipmaps()
	shader_mat.set_shader_parameter("clouds", ImageTexture.create_from_image(a))
	shader_mat.set_shader_parameter("puffs", ImageTexture.create_from_image(b))
	var s := Sky.new()
	s.sky_material = shader_mat
	s.radiance_size = Sky.RADIANCE_SIZE_64
	return s


# =====================================================================================
# Water
# =====================================================================================
static func lake(level: Dictionary) -> MeshInstance3D:
	## A lake with a wobbly shoreline. Vertex alpha = depth (1 in the middle).
	var lk: Array = level.valley.lake
	var noise := FastNoiseLite.new()
	noise.seed = int(level.seed) + 61
	noise.frequency = 1.3
	var segs := 72
	var rings := 5
	var verts := PackedVector3Array()
	var colors := PackedColorArray()
	var normals := PackedVector3Array()
	verts.append(Vector3(lk[0], 0.0, lk[1]))
	colors.append(Color(1, 1, 1, 1))
	normals.append(Vector3.UP)
	for r in range(1, rings + 1):
		var f := float(r) / rings
		for sgm in segs:
			var a := TAU * float(sgm) / segs
			var wob := 1.0 + 0.09 * noise.get_noise_2d(cos(a), sin(a)) * f
			verts.append(Vector3(lk[0] + cos(a) * lk[2] * f * wob * 1.04, 0.0, lk[1] + sin(a) * lk[3] * f * wob * 1.04))
			colors.append(Color(1, 1, 1, 1.0 - f * f))
			normals.append(Vector3.UP)
	var idxs := PackedInt32Array()
	for sgm in segs:
		var nx := (sgm + 1) % segs
		idxs.append_array([0, 1 + sgm, 1 + nx])
	for r in range(1, rings):
		var base0 := 1 + (r - 1) * segs
		var base1 := 1 + r * segs
		for sgm in segs:
			var nx := (sgm + 1) % segs
			idxs.append_array([base0 + sgm, base1 + nx, base0 + nx, base0 + sgm, base1 + sgm, base1 + nx])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = idxs
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance3D.new()
	mi.name = "Lake"
	mi.mesh = mesh
	mi.position.y = 0.06
	mi.material_override = water_material(1.0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


static func stream(level: Dictionary) -> MeshInstance3D:
	## Meltwater running from under the glacier's snout down to the lake.
	var pts: Array = level.valley.get("stream", [])
	if pts.size() < 2:
		return null
	var curve := Curve2D.new()
	for i in pts.size():
		var p: Vector2 = pts[i]
		var prev: Vector2 = pts[maxi(i - 1, 0)]
		var nxt: Vector2 = pts[mini(i + 1, pts.size() - 1)]
		var tangent := (nxt - prev) * 0.25
		curve.add_point(p, -tangent, tangent)
	curve.bake_interval = 0.6
	var baked := curve.get_baked_points()
	var verts := PackedVector3Array()
	var colors := PackedColorArray()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var dist := 0.0
	for i in baked.size():
		var p := baked[i]
		if i > 0:
			dist += p.distance_to(baked[i - 1])
		var dir := (baked[mini(i + 1, baked.size() - 1)] - baked[maxi(i - 1, 0)]).normalized()
		var side := Vector2(-dir.y, dir.x)
		var t := float(i) / (baked.size() - 1)
		var w := lerpf(0.55, 1.1, t) * (1.0 + 0.18 * sin(dist * 0.7))
		for s in [-1.0, 1.0]:
			var q: Vector2 = p + side * w * s
			verts.append(Vector3(q.x, 0.0, q.y))
			colors.append(Color(1, 1, 1, 0.35))
			normals.append(Vector3.UP)
			uvs.append(Vector2(s * 0.5 + 0.5, dist))
	var idxs := PackedInt32Array()
	for i in baked.size() - 1:
		var a := i * 2
		idxs.append_array([a, a + 3, a + 1, a, a + 2, a + 3])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idxs
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance3D.new()
	mi.name = "Stream"
	mi.mesh = mesh
	mi.position.y = 0.035
	mi.material_override = water_material(0.0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


static var _water_mats := {}


static func water_material(still: float) -> ShaderMaterial:
	## still = 1 for the lake (gentle ripples), 0 for the stream (flows along its UV).
	if not _water_mats.has(still):
		var noise := FastNoiseLite.new()
		noise.seed = 77
		noise.frequency = 0.04
		noise.fractal_octaves = 3
		var img := noise.get_seamless_image(128, 128)
		img.generate_mipmaps()
		var m := ShaderMaterial.new()
		m.shader = load("res://shaders/water.gdshader")
		m.set_shader_parameter("ripples", ImageTexture.create_from_image(img))
		m.set_shader_parameter("still", still)
		if still < 0.5:   # the stream: milky grey-green meltwater
			m.set_shader_parameter("shallow_color", Color(0.4, 0.55, 0.56))
			m.set_shader_parameter("deep_color", Color(0.2, 0.36, 0.42))
		_water_mats[still] = m
	return _water_mats[still]


static func on_lake(level: Dictionary, x: float, z: float, margin: float = 0.0) -> bool:
	var lk: Array = level.valley.lake
	var ex: float = (x - lk[0]) / (lk[2] * 1.12 + margin)
	var ez: float = (z - lk[1]) / (lk[3] * 1.12 + margin)
	return ex * ex + ez * ez < 1.0
