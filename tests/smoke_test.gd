extends SceneTree
## Headless smoke test: godot --headless -s res://tests/smoke_test.gd
## Builds the valley, walks into the ice, melts with the tool, checks the phone
## controls, buys things, digs up a find, saves, fakes time away, and melts
## everything to the ending. Exits with code 1 if anything fails.
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
	check(grid != null and grid.total_blocks > 1500, "glacier built (%d blocks)" % grid.total_blocks)
	check(grid.remaining == grid.total_blocks, "glacier starts full")
	check(not player.collides(player.position), "player spawns in free space at %s" % player.position)
	check(world._find_markers.size() == Balance.DISCOVERIES.size(), "all %d finds placed" % world._find_markers.size())

	# --- Walking into the glacier never ends up inside the ice.
	player.set_view(0.0, 0.0)
	player.move_input = Vector2(0, 1)
	for _i in 300:
		player._move(1.0 / 30.0)
	player.move_input = Vector2.ZERO
	check(not player.collides(player.position), "walked forward 10 s, still outside the ice (at %s)" % player.position)
	check(player.position.z < world.SPAWN.z - 3.0, "actually moved forward")

	# --- Aim at the ice in front and melt it with the hair dryer.
	var col := Vector2i(grid.sx / 2, -1)
	for z in range(grid.sz - 1, -1, -1):
		if grid.column_top_y(col.x, z) >= 1:
			col.y = z
			break
	var top: int = grid.column_top_y(col.x, col.y)
	var target: Vector3 = grid.cell_center(Vector3i(col.x, top, col.y))
	player.position = Vector3(target.x, 0.0, target.z + 3.0)
	player.unstick()
	_aim_at(player, target)
	player.melting = true
	var water0: float = gs.water
	var left0: int = grid.remaining
	for _i in 60:
		player._update_tool(0.05)
	player.melting = false
	check(grid.remaining < left0, "the hair dryer melted %d blocks" % (left0 - grid.remaining))
	check(gs.water > water0, "melting paid out (%s water)" % gs.water)

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
	_touch(0, touch.melt_center(), false)
	_touch(1, Vector2(200, touch.size.y - 240), false)
	_touch(2, Vector2(touch.size.x * 0.6 + 60, 200), false)
	await _frames(1)
	check(not touch.melting and touch.move_vector == Vector2.ZERO, "letting go stops everything")

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

	# --- Dig up a find.
	var cell_index: int = world._find_cells.keys()[0]
	var find: int = world._find_cells[cell_index]
	grid.damage_cell(grid.cell_of(cell_index), 1e9)
	check(gs.discovered[find], "melting its block discovers %s" % Balance.DISCOVERIES[find].name)
	check(world._find_markers[find].visible, "the find shows up in the world")

	# --- Glacier save string round trip.
	var saved: String = grid.to_save_string()
	var remaining_saved: int = grid.remaining
	grid.damage_sphere(target, 3.0, 1e9)
	check(grid.load_save_string(saved) and grid.remaining == remaining_saved, "glacier save/load round trip")

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
	check(gs.glacier_data.begins_with("%d:" % grid.total_blocks), "glacier stored in the save")

	# --- Start over: a fresh valley.
	gs.wipe_save()
	world.queue_free()
	await _frames(2)
	var world2 = load("res://scenes/world.tscn").instantiate()
	root.add_child(world2)
	await _frames(3)
	check(gs.grid.remaining == gs.grid.total_blocks and not gs.has_won, "start over gives a full glacier")
	await _frames(20)
	gs.wipe_save()
	print("SMOKE TEST ", "PASSED" if ok else "FAILED")
	quit(0 if ok else 1)
