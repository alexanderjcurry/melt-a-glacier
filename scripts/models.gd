class_name Models
extends RefCounted
## Models made in Blender (see art/blender/), loaded from models/*.glb.
## Each file is loaded once; `instance` gives a fresh copy, `mesh` pulls one
## named mesh out (for rigs that animate parts separately, like the penguin).

static var _scenes := {}
static var _meshes := {}


static func scene(file: String) -> PackedScene:
	if not _scenes.has(file):
		_scenes[file] = load("res://models/%s.glb" % file)
	return _scenes[file]


static func instance(file: String, shadows: bool = true) -> Node3D:
	var n: Node3D = scene(file).instantiate()
	if not shadows:
		_no_shadows(n)
	return n


static func mesh(file: String, node_name: String) -> Mesh:
	var key := file + "/" + node_name
	if not _meshes.has(key):
		var n := scene(file).instantiate()
		var mi := n.find_child(node_name, true, false) as MeshInstance3D
		assert(mi != null, "no mesh %s in %s.glb" % [node_name, file])
		_meshes[key] = mi.mesh
		n.free()
	return _meshes[key]


static func _no_shadows(n: Node) -> void:
	if n is GeometryInstance3D:
		(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for c in n.get_children():
		_no_shadows(c)


static func baked(file: String, node_name: String = "", recolor: Dictionary = {}) -> ArrayMesh:
	## One named mesh (or the whole file) as a single vertex-coloured mesh for
	## MeshKit.material(): each surface's material colour is baked into its
	## vertices, so a model with many colours is one draw call. `recolor` maps
	## a material name (as named in Blender) to a colour to use instead.
	var key := "baked/%s/%s/%s" % [file, node_name, str(recolor)]
	if _meshes.has(key):
		return _meshes[key]
	var root := scene(file).instantiate()
	var parts: Array = []
	if node_name == "":
		_collect(root, Transform3D.IDENTITY, parts)
	else:
		var mi := root.find_child(node_name, true, false) as MeshInstance3D
		assert(mi != null, "no mesh %s in %s.glb" % [node_name, file])
		parts.append([mi.mesh, Transform3D.IDENTITY])
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	for part in parts:
		var mesh: Mesh = part[0]
		var xf: Transform3D = part[1]
		for s in mesh.get_surface_count():
			var arr := mesh.surface_get_arrays(s)
			var mat := mesh.surface_get_material(s) as BaseMaterial3D
			var col := Color.WHITE
			if mat != null:
				col = mat.albedo_color
				for k in recolor:
					if mat.resource_name == k:
						col = recolor[k]
			var base := verts.size()
			var pv: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var pn: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			for i in pv.size():
				verts.append(xf * pv[i])
				normals.append((xf.basis * pn[i]).normalized())
				colors.append(col)
			var idx = arr[Mesh.ARRAY_INDEX]
			if idx == null:
				for i in pv.size():
					indices.append(base + i)
			else:
				for i in (idx as PackedInt32Array):
					indices.append(base + i)
	root.free()
	var out_arr := []
	out_arr.resize(Mesh.ARRAY_MAX)
	out_arr[Mesh.ARRAY_VERTEX] = verts
	out_arr[Mesh.ARRAY_NORMAL] = normals
	out_arr[Mesh.ARRAY_COLOR] = colors
	out_arr[Mesh.ARRAY_INDEX] = indices
	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out_arr)
	_meshes[key] = out
	return out


static func _collect(n: Node, xf: Transform3D, parts: Array) -> void:
	var t := xf
	if n is Node3D:
		t = xf * (n as Node3D).transform
	if n is MeshInstance3D:
		parts.append([(n as MeshInstance3D).mesh, t])
	for c in n.get_children():
		_collect(c, t, parts)


static func baked_instance(mesh: Mesh) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = MeshKit.material()
	return mi


static func fitted(mesh: Mesh, size: float, bottom: float = 0.0) -> Node3D:
	## A vertex-coloured model scaled so its biggest side is `size`, centred on
	## x/z with its bottom at y = `bottom`, wrapped in a Node3D you can spin.
	var n := Node3D.new()
	var mi := baked_instance(mesh)
	var box := mesh.get_aabb()
	var s := size / maxf(box.size.x, maxf(box.size.y, box.size.z))
	mi.scale = Vector3.ONE * s
	var c := box.get_center()
	mi.position = Vector3(-c.x * s, bottom - box.position.y * s, -c.z * s)
	n.add_child(mi)
	return n
