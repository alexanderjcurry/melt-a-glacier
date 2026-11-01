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

	# Walk up to the ice front and melt for a while.
	var col := Vector2i(grid.sx / 2, -1)
	for z in range(grid.sz - 1, -1, -1):
		if grid.column_top_y(col.x, z) >= 2:
			col.y = z
			break
	var tgt: Vector3 = grid.cell_center(Vector3i(col.x, 1, col.y))
	player.position = Vector3(tgt.x + 0.5, 0.0, tgt.z + 3.2)
	player.unstick()
	_aim_at(player, tgt)
	world.force_melt = true
	gs.debug_speed = 4.0
	await _frames(90)
	await _shot("02_melting")
	world.force_melt = false
	gs.debug_speed = 1.0

	# Stand on top of the glacier, looking at the church spire.
	player.position = Vector3(-6.0, 8.0, -4.0)
	player.unstick()
	_aim_at(player, Vector3(1.0, 8.0, -11.0))
	await _frames(10)
	await _shot("03_on_top")

	# Some helpers and a volcano.
	gs.grant_water(1e7)
	for _i in 6:
		gs.buy_helper(0)
	gs.buy_helper(1)
	gs.buy_helper(2)
	player.position = Vector3(-15.0, 0.0, 12.0)
	player.unstick()
	_aim_at(player, Vector3(-4.0, 3.0, -8.0))
	await _frames(120)
	await _shot("04_helpers")

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
	for c in grid.total_blocks:
		var i: int = grid.inst_cell[c]
		if grid.cell_of(i).y >= 4 and grid.hp[i] > 0.0:
			grid.damage_cell(grid.cell_of(i), 1e9)
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
