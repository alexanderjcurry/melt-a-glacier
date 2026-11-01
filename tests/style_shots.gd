extends SceneTree
## Before/after shots for the art style test: the penguin, the shed from
## outside, and the village once the ice is gone.
##   xvfb-run -s "-screen 0 1600x900x24" godot --rendering-driver opengl3 -s res://tests/style_shots.gd -- /tmp/style
## (Untyped on purpose; see smoke_test.gd.)

var out_dir := "/tmp/style"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [out_dir, name])
	print("saved ", name)


func _frames(n: int) -> void:
	for _i in n:
		await process_frame


func _aim_at(player, target: Vector3) -> void:
	var eye: Vector3 = player.position + Vector3(0, 1.55, 0)
	var d := target - eye
	player.set_view(atan2(-d.x, -d.z), atan2(d.y, Vector2(d.x, d.z).length()))


func _place(player, at: Vector3, look: Vector3) -> void:
	player.position = at
	player.velocity = Vector3.ZERO
	_aim_at(player, look)


func _run() -> void:
	var gs = root.get_node("GameState")
	gs.wipe_save()
	var world = load("res://scenes/world.tscn").instantiate()
	root.add_child(world)
	var player = world.player
	var grid = world.grid
	world.hud.visible = false
	await _frames(10)

	# The shed from the path.
	player.position = Vector3(3.0, 0.0, 17.0)
	player.unstick()
	_aim_at(player, Vector3(12.0, 2.0, 11.0))
	await _frames(5)
	await _shot("shed")

	# Penguins on the open ground in front of the glacier.
	gs.grant_water(1e7)
	for _i in 3:
		gs.buy_helper(0)
	await _frames(5)
	world.helpers.set_process(false)
	player.set_physics_process(false)
	var spots := [Vector3(-1.0, 0, 8.0), Vector3(0.1, 0, 8.6), Vector3(1.1, 0, 7.9)]
	var i := 0
	for w in world.helpers._walkers:
		if w.type != 0 or i >= spots.size():
			continue
		w.node.global_position = spots[i]
		w.node.rotation = Vector3(0.0, PI + (i - 1) * 0.5, 0.0)   # face +Z, toward the camera
		i += 1
	_place(player, Vector3(0.2, -0.55, 10.4), Vector3(0.1, 0.4, 8.2))
	await _frames(3)
	await _shot("penguins")

	# The village once the ice has gone.
	world.helpers.visible = false
	grid.melt_everything()
	await _frames(30)
	for c in world.hud.popups.get_children():
		world.hud.popups.remove_child(c)
		c.queue_free()
	_place(player, Vector3(2.0, 0.0, -4.0), Vector3(0.0, 2.0, -16.0))
	await _frames(40)
	await _shot("village")
	_place(player, Vector3(-12.0, 1.0, -7.0), Vector3(-3.0, 1.5, -18.0))
	await _frames(5)
	await _shot("village_side")
	gs.wipe_save()
	quit(0)
