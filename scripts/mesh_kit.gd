class_name MeshKit
extends RefCounted
## Tiny modelling kit: adds coloured, smooth-shaded primitives (ellipsoids,
## cones, cylinders, boxes) to one SurfaceTool, so a whole character can be a
## single mesh with vertex colours (one draw call). Used for the helpers.

static var _material: StandardMaterial3D


static func material() -> StandardMaterial3D:
	## The shared material for vertex-coloured models.
	if _material == null:
		_material = StandardMaterial3D.new()
		_material.vertex_color_use_as_albedo = true
		_material.vertex_color_is_srgb = true
		_material.roughness = 0.62
		_material.rim_enabled = true
		_material.rim = 0.25
		_material.rim_tint = 0.6
	return _material


static func begin() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st


static func finish(st: SurfaceTool) -> ArrayMesh:
	st.index()
	return st.commit()


static func ellipsoid(st: SurfaceTool, center: Vector3, radii: Vector3, color: Color,
		basis: Basis = Basis.IDENTITY, rings: int = 8, segs: int = 14) -> void:
	## A squashed sphere. `basis` rotates it around its centre.
	var rows: Array = []
	for r in rings + 1:
		var v := float(r) / rings
		var phi := v * PI
		var row: Array = []
		for sgm in segs + 1:
			var u := float(sgm) / segs
			var th := u * TAU
			var unit := Vector3(sin(phi) * cos(th), cos(phi), sin(phi) * sin(th))
			var p := center + basis * (unit * radii)
			var n := (basis * (unit / radii)).normalized()
			row.append([p, n])
		rows.append(row)
	for r in rings:
		for sgm in segs:
			var a: Array = rows[r][sgm]
			var b: Array = rows[r][sgm + 1]
			var c: Array = rows[r + 1][sgm + 1]
			var d: Array = rows[r + 1][sgm]
			_tri(st, a, c, b, color)
			_tri(st, a, d, c, color)


static func cylinder(st: SurfaceTool, from: Vector3, to: Vector3, r_from: float, r_to: float, color: Color,
		segs: int = 12, caps: bool = true, inside: bool = false) -> void:
	## A (possibly tapered) tube from `from` to `to`. r_to = 0 makes a cone.
	## `inside` turns it inside out: the inner wall of a cup, a lamp shade or a nozzle.
	var axis := to - from
	var up := axis.normalized()
	var side := up.cross(Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	var side2 := up.cross(side)
	var slope := (r_from - r_to) / maxf(axis.length(), 0.0001)
	var ring_a: Array = []
	var ring_b: Array = []
	for sgm in segs + 1:
		var th := TAU * float(sgm) / segs
		var dir := side * cos(th) + side2 * sin(th)
		var n := (dir + up * slope).normalized()
		if inside:
			n = -n
		ring_a.append([from + dir * r_from, n])
		ring_b.append([to + dir * r_to, n])
	for sgm in segs:
		_tri(st, ring_a[sgm], ring_b[sgm + 1], ring_b[sgm], color)
		_tri(st, ring_a[sgm], ring_a[sgm + 1], ring_b[sgm + 1], color)
	if caps:
		for sgm in segs:
			if r_from > 0.0:
				_tri(st, [from, -up], [ring_a[sgm][0], -up], [ring_a[sgm + 1][0], -up], color)
			if r_to > 0.0:
				_tri(st, [to, up], [ring_b[sgm + 1][0], up], [ring_b[sgm][0], up], color)


static func box(st: SurfaceTool, center: Vector3, size: Vector3, color: Color, basis: Basis = Basis.IDENTITY) -> void:
	var h := size * 0.5
	var faces := [
		[Vector3.RIGHT, Vector3.UP, Vector3.BACK], [Vector3.LEFT, Vector3.UP, Vector3.FORWARD],
		[Vector3.UP, Vector3.BACK, Vector3.RIGHT], [Vector3.DOWN, Vector3.FORWARD, Vector3.RIGHT],
		[Vector3.BACK, Vector3.UP, Vector3.LEFT], [Vector3.FORWARD, Vector3.UP, Vector3.RIGHT],
	]
	for fc in faces:
		var n: Vector3 = fc[0]
		var u: Vector3 = fc[1]
		var v: Vector3 = fc[2]
		var c := n * h
		var du := u * h
		var dv := v * h
		var nn := basis * n
		var p0 := center + basis * (c - du - dv)
		var p1 := center + basis * (c - du + dv)
		var p2 := center + basis * (c + du + dv)
		var p3 := center + basis * (c + du - dv)
		_tri(st, [p0, nn], [p1, nn], [p2, nn], color)
		_tri(st, [p0, nn], [p2, nn], [p3, nn], color)


static func triangle(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, normal: Vector3, color: Color) -> void:
	## A flat triangle facing `normal`.
	_tri(st, [a, normal], [b, normal], [c, normal], color)


static func _tri(st: SurfaceTool, a: Array, b: Array, c: Array, color: Color) -> void:
	## Adds one triangle, wound so its front faces where the normals point.
	var pa: Vector3 = a[0]
	var pb: Vector3 = b[0]
	var pc: Vector3 = c[0]
	var face := (pc - pa).cross(pb - pa)   # Godot's front faces are clockwise
	var avg: Vector3 = a[1] + b[1] + c[1]
	if face.dot(avg) < 0.0:
		var t := b
		b = c
		c = t
	for v in [a, b, c]:
		st.set_color(color)
		st.set_normal(v[1])
		st.add_vertex(v[0])
