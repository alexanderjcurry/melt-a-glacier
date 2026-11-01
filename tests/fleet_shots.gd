extends SceneTree
## Shots of the goblin pirate fleet in the frozen lake: masts poking out of the
## ice, a ship half dug out, and the fleet afloat once the lake thaws.
##   xvfb-run -s "-screen 0 1600x900x24" godot --rendering-driver opengl3 -s res://tests/fleet_shots.gd -- /tmp/fleet
## (Untyped on purpose; see smoke_test.gd.)

var out_dir := "/tmp/fleet"


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


func _place(player, at: Vector3, look: Vector3) -> void:
	player.position = at
	player.velocity = Vector3.ZERO
	var eye: Vector3 = at + Vector3(0, 1.55, 0)
	var d := look - eye
	player.set_view(atan2(-d.x, -d.z), atan2(d.y, Vector2(d.x, d.z).length()))


func _clear_popups(world) -> void:
	for c in world.hud.popups.get_children():
		world.hud.popups.remove_child(c)
		c.queue_free()


func _run() -> void:
	var gs = root.get_node("GameState")
	gs.wipe_save()
	var world = load("res://scenes/world.tscn").instantiate()
	root.add_child(world)
	var player = world.player
	player.set_physics_process(false)
	await _frames(10)

	# From the gate: masts and flags sticking out of the lake ice.
	world.hud.visible = false
	_place(player, Vector3(2.0, 0.0, 20.0), Vector3(4.0, 9.0, 52.0))
	await _frames(10)
	await _shot("fleet_from_gate")
	world.hud.visible = true

	# Free the village, then dig the flagship half out.
	world.glaciers[0].melt_everything()
	await _frames(30)
	_clear_popups(world)
	var lake = world.glaciers[1]
	for x in range(-14, -1, 1):
		for z in range(38, 62, 1):
			for y in range(1, 13, 1):
				lake.damage_sphere(Vector3(x, y, z), 2.2, 1e9)
	for _i in 120:
		lake.flush()
		await process_frame
	world.hud.visible = false
	_place(player, Vector3(-12.0, 0.0, 42.0), Vector3(4.0, 3.5, 50.0))
	await _frames(20)
	await _shot("fleet_dig")

	# The whole lake glacier gone: the crews wake up and pay out.
	lake.melt_everything()
	await _frames(60)
	_clear_popups(world)
	world.hud.visible = false
	_place(player, Vector3(-12.0, 0.0, 40.0), Vector3(4.0, 4.0, 50.0))
	await _frames(30)
	await _shot("fleet_free_close")
	_place(player, Vector3(-36.0, 6.0, 40.0), Vector3(0.0, 2.0, 62.0))
	await _frames(10)
	await _shot("fleet_afloat")
	print("freed: ", world.fleet.ships.map(func(s): return s.freed), " won: ", gs.has_won)
	# Thawed crews must be back in colour (the vertex-colour material, not none).
	for s in world.fleet.ships:
		for holder in s.crew:
			var mi = holder.get_child(0)
			if mi.material_override != MeshKit.material():
				push_error("a thawed goblin has lost its colours")
	# Close up on the galleon's crew.
	_place(player, Vector3(6.5, 3.0, 59.5), Vector3(4.0, 3.2, 54.0))
	await _frames(10)
	await _shot("fleet_crew")
	gs.wipe_save()
	quit(0)
