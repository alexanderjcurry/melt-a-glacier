extends SceneTree
## Times building and re-meshing the ice field, and checks it's watertight-ish.
##   godot --headless -s res://tests/field_bench.gd [-- lake]

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var t0 := Time.get_ticks_usec()
	var field = load("res://scripts/ice_field.gd").new()
	root.add_child(field)
	var carve := [AABB(Vector3(-9, 0, -21), Vector3(3, 4.3, 3)), AABB(Vector3(0, 0, -12), Vector3(2, 6, 2))]
	var lv = load("res://scripts/levels.gd").VALLEY
	var which := 1 if OS.get_cmdline_user_args().has("lake") else 0
	field.generate(lv.glaciers[which], int(lv.seed) + 1000 * which, carve if which == 0 else [])
	var t1 := Time.get_ticks_usec()
	print("grid %dx%dx%d, chunks %d, ice points %d (%.0f m3)" % [field.nx, field.ny, field.nz, field._chunks.size(), field.total, field.volume_left()])
	print("generate + mesh all: %.1f ms" % ((t1 - t0) / 1000.0))
	var tris := 0
	var verts := 0
	for ch in field._chunks:
		var m: ArrayMesh = ch.mesh.mesh
		if m != null:
			verts += m.surface_get_array_len(0)
			tris += m.surface_get_array_index_len(0) / 3
	print("verts %d, tris %d" % [verts, tris])
	# hp total
	var hp := 0.0
	for s in field.f.size():
		if field.f[s] > 0.5:
			hp += field.layer_hp(field.lay[s])
	print("total hp x m3: %.0f" % (hp * field.point_volume))
	# Time single chunk re-mesh (middle of the glacier)
	var ci: int = 4 + 5 * field.ncx
	var t2 := Time.get_ticks_usec()
	for _i in 10:
		field._remesh(ci)
	print("one chunk re-mesh: %.2f ms" % ((Time.get_ticks_usec() - t2) / 10000.0))
	# Time a damage sphere
	var t3 := Time.get_ticks_usec()
	for _i in 100:
		field.damage_sphere(Vector3(0, 7.5, -15), 1.4, 2.0 / 60.0)
	print("damage_sphere r1.4: %.3f ms" % ((Time.get_ticks_usec() - t3) / 100000.0))
	# melt rate: hair dryer on the surface for 1 s at 60 fps, re-aiming at the surface
	var before: int = field.remaining
	for _i in 60:
		var top: float = field.surface_y(3.0, -15.0)
		field.damage_sphere(Vector3(3.0, top - 0.2, -15.0), 0.9, 2.0 / 60.0)
	print("hair dryer 1s on snow: %.2f m3" % ((before - field.remaining) * field.point_volume))
	before = field.remaining
	for _i in 60:
		var top: float = field.surface_y(3.0, -15.0)
		field.damage_sphere(Vector3(3.0, top - 0.2, -15.0), 0.9, 2.0 / 60.0)
	print("hair dryer next 1s: %.2f m3, now %.2f m deep" % [(before - field.remaining) * field.point_volume, field.original_top(3.0, -15.0) - field.surface_y(3.0, -15.0)])
	quit(0)
