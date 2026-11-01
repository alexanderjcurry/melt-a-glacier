extends SceneTree
## Headless smoke test: godot --headless -s res://tests/smoke_test.gd
## Builds the valley, walks up onto the glacier, melts with the tool, checks
## the phone controls, jetpack and respawn, buys things, digs up a find, saves,
## fakes time away, and melts everything to the ending. Exits with code 1 if
## anything fails.
## Variables stay untyped: this script compiles before the GameState autoload
## exists, so it can't name classes that use it (World, Player, Hud...).

var ok := true


func check(cond: bool, what: String) -> void:
	print(("  ok    " if cond else "  FAIL  ") + what)
	if not cond:
		ok = false


func _initialize() -> void:
	create_timer(240.0).timeout.connect(func():
		print("SMOKE TEST TIMED OUT")
		quit(2))
	_run.call_deferred()


func _frames(n: int) -> void:
	for _i in n:
		await process_frame


func _touch(index: int, pos: Vector2, pressed: bool) -> void:
	var ev := InputEventScreenTouch.new()
	ev.index = index
	ev.position = pos
	ev.pressed = pressed
	root.push_input(ev, true)


func _drag(index: int, pos: Vector2, rel: Vector2) -> void:
	var ev := InputEventScreenDrag.new()
	ev.index = index
	ev.position = pos
	ev.relative = rel
	root.push_input(ev, true)


func _aim_at(player, target: Vector3) -> void:
	var eye: Vector3 = player.position + Vector3(0, 1.55, 0)
	var d := target - eye
	player.set_view(atan2(-d.x, -d.z), atan2(d.y, Vector2(d.x, d.z).length()))


func _run() -> void:
	var gs = root.get_node("GameState")
	gs.wipe_save()
	var world = load("res://scenes/world.tscn").instantiate()
	root.add_child(world)
	await _frames(3)
	var grid = gs.grid
	var player = gs.player
	check(grid != null and grid.total > 20000, "glacier built (%d points, %.0f m3)" % [grid.total, grid.volume_left()])
	check(grid.remaining == grid.total, "glacier starts full")
	check(not player.collides(player.position), "player spawns in free space at %s" % player.position)
	check(world._find_markers.size() == Balance.DISCOVERIES.size(), "all %d finds placed" % world._find_markers.size())

	# --- Walking at the glacier: up the gentle snout and onto the ice, never inside it.
	player.set_view(0.0, 0.0)
	player.move_input = Vector2(0, 1)
	var ok_path := true
	for _i in 600:
		player._move(1.0 / 60.0)
		if player.collides(player.position + Vector3(0, 0.05, 0)):
			ok_path = false
	player.move_input = Vector2.ZERO
	check(ok_path, "walked 10 s into the glacier without ending up inside it (at %s)" % player.position)
	check(player.position.z < world.SPAWN.z - 12.0 and player.position.y > 1.0, "walked up onto the ice (at %s)" % player.position)

	# --- Aim at the front of the glacier and melt it with the hair dryer.
	# Find where the snout is about chest high, stand 2.5 m in front of it and
	# aim a little way into the ice.
	var front_z := 4.0
	while front_z > -10.0 and grid.surface_y(1.0, front_z) < 1.3:
		front_z -= 0.1
	var target := Vector3(1.0, 0.9, front_z - 0.6)
	player.respawn(Vector3(1.0, 0.0, front_z + 2.5), 0.0)
	player._move(1.0 / 60.0)
	_aim_at(player, target)
	player._update_tool(0.0)
	check(player.target.hit, "the crosshair finds the ice (%.1f m away)" % (player.target.dist if player.target.hit else -1.0))
	var first_hit: Vector3 = player.target.pos if player.target.hit else Vector3.ZERO
	player.melting = true
	var water0: float = gs.water
	var left0: int = grid.remaining
	for _i in 30:
		player._update_tool(1.0 / 30.0)
		grid.flush()
	player.melting = false
	player._update_tool(0.0)
	check(grid.remaining < left0, "the hair dryer melted %.2f m3" % ((left0 - grid.remaining) * 0.125))
	check(gs.water > water0, "melting paid out (%s water)" % gs.water)
	check(player.target.hit and player.target.pos.distance_to(first_hit) > 0.4, "it dug a hole: the ice surface moved back %.2f m" % (player.target.pos.distance_to(first_hit) if player.target.hit else 0.0))

	# --- Phone controls: hold to melt, the stick, drag to look.
	world.hud.set_touch_mode(true)
	await _frames(1)
	var touch = world.hud.touch
	print("    touch area: ", touch.size, "  viewport: ", root.get_visible_rect().size)
	_touch(0, touch.melt_center(), true)
	await _frames(1)
	check(touch.melting and player.melting, "holding the 🔥 button melts")
	_touch(1, Vector2(200, touch.size.y - 160), true)
	_drag(1, Vector2(200, touch.size.y - 240), Vector2(0, -80))
	check(touch.move_vector.y > 0.8, "pushing the stick up walks forward (%s)" % touch.move_vector)
	var yaw0: float = player.yaw
	_touch(2, Vector2(touch.size.x * 0.6, 200), true)
	_drag(2, Vector2(touch.size.x * 0.6 + 60, 200), Vector2(60, 0))
	await _frames(1)
	check(player.yaw < yaw0, "dragging right turns right")
	# Moving the stick while another finger looks must not turn the view.
	await _frames(1)
	var yaw1: float = player.yaw
	_drag(1, Vector2(260, touch.size.y - 240), Vector2(500, 300))   # bogus relative on purpose
	await _frames(1)
	check(absf(player.yaw - yaw1) < 0.0001, "moving the stick doesn't turn the camera")
	_touch(0, touch.melt_center(), false)
	_touch(1, Vector2(200, touch.size.y - 240), false)
	_touch(2, Vector2(touch.size.x * 0.6 + 60, 200), false)
	await _frames(1)
	check(not touch.melting and touch.move_vector == Vector2.ZERO, "letting go stops everything")
	# A second finger on the left takes over the stick instead of looking around.
	_touch(3, Vector2(150, touch.size.y - 150), true)
	_touch(4, Vector2(300, touch.size.y - 300), true)
	_drag(4, Vector2(300, touch.size.y - 380), Vector2(0, -80))
	await _frames(1)
	var yaw2: float = player.yaw
	await _frames(1)
	check(touch.move_vector.y > 0.5 and absf(player.yaw - yaw2) < 0.0001, "two fingers on the left = still the stick")
	# A lost lift-off (index reused) doesn't leave the melt button stuck on.
	_touch(5, touch.melt_center(), true)
	_touch(5, Vector2(touch.size.x * 0.7, 250), true)
	check(not touch.melting, "a reused finger index lets go of the melt button")
	touch.release_all()
	# Respawn button works with a thumb already on the stick.
	player.position = Vector3(3.0, 0.0, 6.0)
	_touch(6, Vector2(150, touch.size.y - 150), true)
	var rb: Control = world.hud.respawn_button
	_touch(7, rb.get_global_rect().get_center(), true)
	await _frames(1)
	check(player.position.distance_to(world.SPAWN) < 0.6, "respawn button (second finger) puts you back at the start")
	touch.release_all()
	# Jetpack: hold jump to fly up, fuel runs down, landing refills it.
	player.position = Vector3(world.SPAWN.x, 0.0, world.SPAWN.z)
	player.velocity = Vector3.ZERO
	player._move(0.02)
	player.jump()
	player.jet_held = true
	for _i in 60:
		player._move(1.0 / 60.0)
	check(player.position.y > 3.0 and player.fuel < 0.9, "holding jump flies with the jetpack (y=%.1f, fuel %.2f)" % [player.position.y, player.fuel])
	player.jet_held = false
	for _i in 400:
		player._move(1.0 / 60.0)
	check(player.on_floor and player.fuel > 0.99, "landing refills the fuel")

	# --- The shed: buy a tool, an upgrade and a helper; every tab builds.
	gs.grant_water(1e6)
	check(gs.buy_tool(1) and gs.tool_index == 1, "bought the Heat Lamp")
	check(gs.buy_upgrade("heat"), "bought Heat Output")
	check(gs.buy_helper(0) and gs.helper_counts[0] == 1, "hired a penguin")
	world.hud.open_shed()
	for t in world.hud.TABS.size():
		world.hud._select_tab(t)
		await _frames(1)
	world.hud.close_shed()
	await _frames(2)
	check(world.helpers._walkers.size() == 1, "the penguin is out on the ice")

	# --- The helpers walk on top of the ice (give them a second of game time).
	var waited := 0.0
	while waited < 1.0:
		await process_frame
		waited += root.get_process_delta_time()
	var w0 = world.helpers._walkers[0]
	var wp: Vector3 = w0.pos
	check(absf(wp.y - grid.surface_y(wp.x, wp.z)) < 0.4, "the penguin stands on the ice surface (%.2f vs %.2f)" % [wp.y, grid.surface_y(wp.x, wp.z)])

	# --- Dig up a find.
	var find := 0
	var marker: Node3D = world._find_markers[find]
	check(not marker.visible, "the %s starts frozen and hidden" % Balance.DISCOVERIES[find].name)
	grid.damage_sphere(marker.position, 1.2, 1e9)
	check(gs.discovered[find], "melting around it discovers %s" % Balance.DISCOVERIES[find].name)
	check(marker.visible, "the find shows up in the world")

	# --- Glacier save string round trip (into a second, fresh glacier).
	var saved: String = grid.to_save_string()
	var copy = IceField.new()
	world.add_child(copy)
	copy.generate(world.level, [])
	check(copy.load_save_string(saved) and copy.remaining <= grid.remaining + 5 and copy.remaining >= grid.remaining - 5,
		"glacier save/load round trip (%d vs %d)" % [copy.remaining, grid.remaining])
	copy.queue_free()

	# --- Time away: helpers keep melting.
	var got := []
	gs.offline_earned.connect(func(r): got.append(r))
	gs.last_active_time -= 3600.0
	gs.check_offline()
	check(got.size() == 1 and got[0].blocks > 0, "an hour away melted %s blocks" % (got[0].blocks if got.size() > 0 else 0))
	check(world.hud.popups.get_child_count() > 0, "welcome back popup shown")
	gs._last_tick_time -= 600.0
	await _frames(2)
	check(got.size() == 2 and absf(got[1].seconds - 600.0) < 5.0, "a frozen app (locked phone) also pays out")

	# --- Melt everything: all finds, the ending.
	var won := [false]
	gs.won.connect(func(): won[0] = true)
	grid.melt_everything()
	await _frames(2)
	check(won[0] and gs.has_won, "melting everything wins")
	check(not gs.discovered.has(false), "every find was discovered")
	check(world._villagers[0].visible, "the villagers came out")

	# --- Game state save round trip.
	gs.save_game()
	var water_saved: float = gs.water
	gs.reset_state()
	gs.load_game()
	check(gs.has_won and gs.tool_index == 1 and absf(gs.water - water_saved) < 0.01, "save/load round trip")
	check(gs.glacier_data.begins_with("v3:"), "glacier stored in the save (%d KB)" % (gs.glacier_data.length() / 1024))

	# --- Start over: a fresh valley.
	gs.wipe_save()
	world.queue_free()
	await _frames(2)
	var world2 = load("res://scenes/world.tscn").instantiate()
	root.add_child(world2)
	await _frames(3)
	check(gs.grid.remaining == gs.grid.total and not gs.has_won, "start over gives a full glacier")
	await _frames(20)
	gs.wipe_save()
	print("SMOKE TEST ", "PASSED" if ok else "FAILED")
	quit(0 if ok else 1)
