extends SceneTree
## Renders a few screenshots of the game for checking the look:
##   xvfb-run -s "-screen 0 1600x900x24" godot --rendering-driver opengl3 -s res://tests/screenshots.gd -- /tmp/shots
## (Untyped on purpose; see smoke_test.gd.)

var out_dir := "/tmp/shots"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png("%s/%s.png" % [out_dir, name])
	print("saved ", name)


func _frames(n: int) -> void:
	for _i in n:
		await process_frame


func _aim_at(player, target: Vector3) -> void:
	var eye: Vector3 = player.position + Vector3(0, 1.55, 0)
	var d := target - eye
	player.set_view(atan2(-d.x, -d.z), atan2(d.y, Vector2(d.x, d.z).length()))


func _run() -> void:
	var gs = root.get_node("GameState")
	gs.wipe_save()
	var world = load("res://scenes/world.tscn").instantiate()
	root.add_child(world)
	var hud = world.hud
	var player = world.player
	var grid = world.grid
	if OS.get_cmdline_user_args().has("touch"):
		hud.set_touch_mode(true)
	await _frames(10)
	await _shot("01_spawn")
	hud.set_touch_mode(true)
	await _frames(2)
	await _shot("01b_spawn_touch")
	hud.set_touch_mode(OS.get_cmdline_user_args().has("touch"))
	# Turn round: the lake and the stream.
	player.set_view(PI + 0.35, -0.08)
	await _frames(5)
	await _shot("01c_lake")
	player.set_view(world.SPAWN_YAW, -0.12)

	# Walk up to the front of the glacier (where it's about chest high) and melt for a while.
	var front_z := 4.0
	while front_z > -10.0 and grid.surface_y(1.0, front_z) < 1.3:
		front_z -= 0.1
	var tgt := Vector3(1.0, 1.0, front_z - 0.8)
	player.position = Vector3(1.4, 0.0, front_z + 2.6)
	player.unstick()
	_aim_at(player, tgt)
	await _frames(5)
	await _shot("02a_ice_front")
	world.force_melt = true
	gs.debug_speed = 3.0
	await _frames(150)
	await _shot("02_melting")
	world.force_melt = false
	gs.debug_speed = 1.0
	await _frames(20)
	await _shot("02b_hole")

	# Stand on top of the glacier, looking at the church spire.
	player.position = Vector3(-6.0, grid.surface_y(-6.0, -4.0) + 0.1, -4.0)
	player.unstick()
	_aim_at(player, Vector3(1.0, 8.0, -11.0))
	await _frames(10)
	await _shot("03_on_top")

	# Some helpers and a volcano.
	gs.grant_water(1e7)
	for _i in 6:
		gs.buy_helper(0)
	for _i in 3:
		gs.buy_helper(1)
	gs.buy_helper(2)
	player.position = Vector3(-15.0, 0.0, 12.0)
	player.unstick()
	_aim_at(player, Vector3(-4.0, 3.0, -8.0))
	await _frames(120)
	await _shot("04_helpers")
	# Close-ups of a penguin and a sauna crew member.
	# Freeze the helpers and pose one of each on a flat bit of untouched
	# glacier, facing the camera.
	world.helpers.set_process(false)
	for w in world.helpers._walkers:
		var node: Node3D = w.node
		var spot := Vector3(-7.0 if w.type == 0 else 7.0, 0.0, -15.0)
		spot.y = grid.surface_y(spot.x, spot.z)
		node.global_position = spot
		node.rotation = Vector3(0.0, 0.0, 0.0)   # faces -Z; the camera stands on that side
		var eye := spot + Vector3(0.5, 1.05 if w.type == 0 else 1.35, -2.3 if w.type == 0 else -2.4)
		eye.y = maxf(eye.y, grid.surface_y(eye.x, eye.z) + 0.5)
		player.position = eye - Vector3(0, 1.55, 0)
		player.velocity = Vector3.ZERO
		player.set_physics_process(false)
		_aim_at(player, spot + Vector3(0, 0.4 if w.type == 0 else 0.85, 0))
		await _frames(3)
		await _shot("04b_penguin" if w.type == 0 else "04c_sauna")
		if w.type == 1:
			break
	world.helpers.set_process(true)
	player.set_physics_process(true)
	# Kevin, seen from the back corner of the valley.
	player.position = Vector3(-16.0, 9.0, -20.0)
	player.velocity = Vector3.ZERO
	_aim_at(player, Vector3(-27.0, 7.0, -38.0))
	await _frames(3)
	await _shot("04d_kevin")

	# The shed.
	player.position = Vector3(5.5, 0.0, 11.5)
	player.unstick()
	_aim_at(player, Vector3(9.5, 1.5, 11.5))
	await _frames(5)
	await _shot("05_shed_door")
	hud.open_shed()
	await _frames(5)
	await _shot("06_shed_menu")
	hud._select_tab(2)
	await _frames(5)
	await _shot("07_shed_helpers")
	hud.close_shed()

	# Halfway: melt the top half of the glacier.
	for i in grid.f.size():
		if grid.f[i] > 0.0 and grid.point_pos(i).y > 3.6:
			grid.f[i] = 0.0
	grid._count()
	grid._update_col_top(0, grid.nx - 1, 0, grid.nz - 1)
	for ci in grid._chunks.size():
		grid._dirty[ci] = true
	grid.flush()
	player.position = Vector3(0.0, 0.0, 12.0)
	player.unstick()
	_aim_at(player, Vector3(0.0, 2.0, -14.0))
	await _frames(30)
	await _shot("08_half_melted")

	# The ending.
	grid.melt_everything()
	await _frames(30)
	await _shot("09_ending_popup")
	for c in hud.popups.get_children():
		hud.popups.remove_child(c)
		c.queue_free()
	player.input_enabled = true
	player.position = Vector3(2.0, 0.0, -4.0)
	player.unstick()
	_aim_at(player, Vector3(0.0, 2.0, -16.0))
	await _frames(60)
	await _shot("10_village")
	gs.wipe_save()
	quit(0)
