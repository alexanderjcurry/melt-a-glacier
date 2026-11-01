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
