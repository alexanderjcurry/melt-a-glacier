extends SceneTree
## Headless smoke test: godot --headless -s res://tests/smoke_test.gd
## Builds the valley, walks up onto the glacier, melts with the tool, checks
## the phone controls, jetpack and respawn, buys things, digs up a find, checks
## that loose ice melts by itself, saves, melts the village glacier (the gate
## to the frozen lake opens, the helpers retire), then the lake: the ending.
## Exits with code 1 if anything fails.
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
	grid.find_floating_now()
	check(grid.floating_count() == 0, "a fresh glacier has no floating ice")
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
	# Find where the snout is head high, stand 2.5 m in front of it and aim a
	# little way into the ice.
	var front_z := 4.0
	while front_z > -10.0 and grid.surface_y(1.0, front_z) < 2.2:
		front_z -= 0.1
	var target := Vector3(1.0, 1.1, front_z - 0.6)
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
	# New collision shapes only reach physics queries after a physics step.
	await physics_frame
	await physics_frame
	player._update_tool(0.0)
	check(grid.remaining < left0, "the hair dryer melted %.2f m3" % ((left0 - grid.remaining) * grid.point_volume))
	check(gs.water > water0, "melting paid out (%s water)" % gs.water)
	check(player.target.hit and player.target.pos.distance_to(first_hit) > 0.4, "it dug a hole: the ice surface moved back %.2f m" % (player.target.pos.distance_to(first_hit) if player.target.hit else 0.0))

	await _sound(world, player)

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
	# iPhone Safari hands out big finger ids that can be negative. Letting go of
	# one has to let go (it used to leave the heat on and the stick walking).
	_touch(-1525662976, touch.melt_center(), true)
	_touch(-1525662977, Vector2(200, touch.size.y - 160), true)
	_drag(-1525662977, Vector2(200, touch.size.y - 240), Vector2(0, -80))
	check(touch.melting and touch.move_vector.y > 0.5, "negative finger ids (iPhone Safari) melt and walk")
	_touch(-1525662976, touch.melt_center(), false)
	_touch(-1525662977, Vector2(200, touch.size.y - 240), false)
	check(not touch.melting and touch.move_vector == Vector2.ZERO, "letting go of negative finger ids stops both")
	_touch(2147483000, touch.melt_center(), true)
	_touch(2147483000, touch.melt_center(), false)
	_touch(-1, Vector2(200, touch.size.y - 160), true)
	_drag(-1, Vector2(200, touch.size.y - 240), Vector2(0, -80))
	_touch(-1, Vector2(200, touch.size.y - 240), false)
	check(not touch.melting and touch.move_vector == Vector2.ZERO, "huge and -1 finger ids let go too")
	# Leaving the app (or the browser tab) with a thumb down lets go of it.
	_touch(8, touch.melt_center(), true)
	touch.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(not touch.melting, "switching away lets go of the melt button")
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
	# On a computer: once the Respawn button has been clicked, letting go of
	# Space (jump / fly) must not press it again and send you back to the start.
	world.hud.set_touch_mode(false)
	await _frames(1)
	var rbtn: Button = world.hud.respawn_button
	player.position = world.SPAWN + Vector3(6.0, 0.0, -6.0)
	for down in [true, false]:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.position = rbtn.get_global_rect().get_center()
		click.global_position = click.position
		click.pressed = down
		root.push_input(click, true)
	await _frames(1)
	check(player.position.distance_to(world.SPAWN) < 0.6, "clicking the Respawn button with the mouse respawns")
	player.position = world.SPAWN + Vector3(8.0, 4.0, -8.0)
	player.velocity = Vector3.ZERO
	for down in [true, false]:
		var sp := InputEventKey.new()
		sp.keycode = KEY_SPACE
		sp.physical_keycode = KEY_SPACE
		sp.pressed = down
		root.push_input(sp)
	await _frames(1)
	check(player.position.distance_to(world.SPAWN) > 3.0, "letting go of Space doesn't press the Respawn button (PC)")
	world.hud.set_touch_mode(true)

	# --- You can walk all the way round the glacier, behind it too.
	player.respawn(Vector3(-19.0, 0.0, -34.5), -PI / 2.0)   # back left corner, facing +x
	player.move_input = Vector2(0, 1)
	for _i in 720:
		player._move(1.0 / 60.0)
	player.move_input = Vector2.ZERO
	check(player.position.x > 19.0, "walked all the way behind the glacier (to x=%.1f)" % player.position.x)
	# --- The fence in front of the lake stops you until the village is free.
	var gate_z: float = world.level.valley.gate_z
	check(world.glaciers.size() == 2 and not world.glaciers[1].collide, "the frozen lake is there, out of reach")
	player.respawn(Vector3(0.0, 0.0, gate_z - 4.0), PI)   # facing the gate (+z)
	player.move_input = Vector2(0, 1)
	for _i in 180:
		player._move(1.0 / 60.0)
	player.move_input = Vector2.ZERO
	check(player.position.z < gate_z, "the locked gate keeps you off the lake (z=%.1f)" % player.position.z)

	# --- The shed: walk in through the door, look at things and buy them.
	gs.grant_water(1e6)
	var shed = world.shed
	var hud = world.hud
	player.respawn(Vector3(7.0, 0.0, 9.0), -PI / 2.0)   # outside the west wall, facing it
	player.move_input = Vector2(0, 1)
	for _i in 90:
		player._move(1.0 / 60.0)
	check(player.position.x < 8.6, "the shed's walls are solid (stopped at x=%.2f)" % player.position.x)
	player.respawn(Vector3(6.5, 0.0, 11.5), -PI / 2.0)  # in front of the door
	for _i in 60:
		player._move(1.0 / 60.0)
	player.move_input = Vector2.ZERO
	check(shed.contains(player.position) and not player.collides(player.position + Vector3(0, 0.05, 0)),
		"walked in through the shed door (at %s)" % player.position)
	await _frames(2)
	check(world._in_shed and not shed.marker.visible, "the game knows you're in the shed")
	# Look at the Heat Lamp on the tool wall and tap BUY.
	hud.set_touch_mode(true)
	var lamp = shed.item("tool", 1)
	player.position = Vector3(11.6, 0.0, 10.8)
	_aim_at(player, lamp.node.global_position)
	await _frames(2)
	check(int(world._aimed.get("index", -1)) == lamp.index and hud.shop_card.visible
		and hud._card_title.text.contains("Heat Lamp"), "looking at the Heat Lamp shows its card (%s)" % hud._card_title.text)
	check(touch.action_text == "BUY" and touch.action_ok, "the 🔥 button turned into BUY (%s %s)" % [touch.action_text, touch.action_sub])
	_touch(0, touch.melt_center(), true)
	_touch(0, touch.melt_center(), false)
	await _frames(2)
	check(gs.tool_index == 1 and not player.melting, "tapping BUY bought the Heat Lamp")
	check(not lamp.node.visible and touch.action_text == "IN USE", "it's off the wall and in your hands (%s)" % touch.action_text)
	var dryer = shed.item("tool", 0)
	check(dryer.node.visible and dryer.price.text.contains("Owned"), "the hair dryer hangs on the wall as owned")
	hud.set_touch_mode(false)
	# An upgrade from the bench, with the E key.
	var thermo = shed.item("upgrade", "heat")
	player.position = Vector3(10.6, 0.0, 13.0)
	_aim_at(player, thermo.node.global_position + Vector3(0, 0.25, 0))
	await _frames(2)
	var key := InputEventKey.new()
	key.physical_keycode = KEY_E
	key.pressed = true
	root.push_input(key)
	await _frames(1)
	check(int(gs.upgrade_levels["heat"]) == 1, "bought Heat Output at the bench (%s)" % hud._card_title.text)
	# Hire a penguin in the corner.
	var peng = shed.item("helper", 0)
	player.position = Vector3(14.8, 0.0, 9.6)
	_aim_at(player, peng.node.global_position + Vector3(0, 0.4, 0))
	await _frames(2)
	world.use_aimed()
	check(gs.helper_counts[0] == 1, "hired a penguin in the hiring corner")
	# The finds shelf shows what's still frozen.
	var mitten = shed.item("find", 0)
	player.position = Vector3(10.8, 0.0, 8.9)
	_aim_at(player, mitten.node.global_position)
	await _frames(2)
	check(int(world._aimed.get("index", -1)) == mitten.index and hud._card_title.text.contains("frozen")
		and shed._ice_cubes[0].visible, "the finds shelf: the mitten is still in its ice cube")
	# The catalogue opens and closes.
	var book = shed.item("catalogue", 0)
	player.position = Vector3(10.7, 0.0, 13.4)
	_aim_at(player, book.node.global_position)
	await _frames(2)
	world.use_aimed()
	await _frames(1)
	check(hud.catalogue_open and hud._list_box.get_child_count() >= 4 and not player.input_enabled, "the catalogue opens")
	root.push_input(key)
	await _frames(1)
	check(not hud.catalogue_open and player.input_enabled, "and closes again")
	# It's also a button on the HUD, anywhere.
	hud.toggle_catalogue()
	await _frames(1)
	check(hud.catalogue_open and not hud.catalogue_button.visible, "the HUD's catalogue button opens it too")
	hud.toggle_catalogue()
	await _frames(1)
	check(not hud.catalogue_open and player.input_enabled, "and closes it")
	await _ad_offers(gs, hud, player)
	# Walk back out.
	player.position = Vector3(6.5, 0.0, 11.5)
	await _frames(2)
	check(not world._in_shed and shed.marker.visible and not hud.shop_card.visible, "walked back out")
	check(world.helpers._walkers.size() == 1, "the penguin is out on the ice")

	# --- The helpers walk on top of the ice (give them a second of game time).
	var waited := 0.0
	while waited < 1.0:
		await process_frame
		waited += root.get_process_delta_time()
	var w0 = world.helpers._walkers[0]
	var wp: Vector3 = w0.pos
	check(absf(wp.y - grid.surface_y(wp.x, wp.z)) < 0.4, "the penguin stands on the ice surface (%.2f vs %.2f)" % [wp.y, grid.surface_y(wp.x, wp.z)])

	# --- Dig up a find. Its shadow shows through the ice as you get close.
	var find := 0
	var marker: Node3D = world._find_markers[find]
	var spot: Vector3 = world._find_spots[find]
	check(not marker.visible, "the %s starts frozen and hidden" % Balance.DISCOVERIES[find].name)
	check(world.find_hint_at(spot + Vector3(0.5, 1.0, 0.0)) == find and world.find_hint_at(spot + Vector3(9, 0, 0)) == -1,
		"aiming at the ice right by it hints that something's frozen in there")
	player.respawn(Vector3(spot.x, 0.0, spot.z + 6.0), 0.0)
	world._recheck_ghost(find)
	var cover0: float = world._ice_cover(spot + Vector3(0, 0.3, 0), grid)
	var target0: float = world._ghosts[find].target
	# Melt the ice off the top until there's not much left over it.
	var ceiling: float = grid.surface_y(spot.x, spot.z)
	while ceiling > spot.y + 1.2:
		grid.damage_sphere(Vector3(spot.x, ceiling, spot.z), 1.0, 1e9)
		ceiling = grid.surface_y(spot.x, spot.z)
	world._recheck_ghost(find)
	for _i in 20:
		world._update_ghosts(0.1)
	world._recheck_ghost(find)
	var gh: Dictionary = world._ghosts[find]
	check(not gs.discovered[find] and gh.target > target0 and gh.alpha > 0.05 and (gh.node as Node3D).visible,
		"its shadow shows through the thinner ice (%.1f m of ice, was %.1f: %.2f -> %.2f)" % [world._ice_cover(spot + Vector3(0, 0.3, 0), grid), cover0, target0, gh.alpha])
	grid.damage_sphere(marker.position, 1.2, 1e9)
	check(gs.discovered[find], "melting around it discovers %s" % Balance.DISCOVERIES[find].name)
	check(marker.visible, "the find shows up in the world")
	check(not world._ghosts.has(find), "and its shadow is gone")
	var card = world.hud._find_card
	check(card != null and is_instance_valid(card) and card.is_inside_tree(), "a card says what you found and what's still out there")

	# --- Helpers melt a thin layer as they walk instead of digging pits.
	gs.buy_helper(1)
	for _i in 6:
		gs.buy_helper(0)
	world.helpers.set_process(false)
	var tops0: PackedFloat32Array = grid.col_top.duplicate()
	var vol0: float = grid.volume_left()
	for _i in 400:   # 20 s of helper time
		world.helpers._process(0.05)
	world.helpers.set_process(true)
	var touched := 0
	var deep := 0
	for c in tops0.size():
		if tops0[c] > 0.0:
			var dent: float = tops0[c] - maxf(grid.col_top[c], 0.0)
			if dent > 0.05:
				touched += 1
			if dent > 1.2:
				deep += 1
	# (Digging pits instead touches ~170 spots, most of them more than 1.2 m deep.
	# Wandering, a few spots get crossed twice: usually under 1%, now and then 4%.)
	check(vol0 - grid.volume_left() > 20.0 and touched > 400 and deep < touched / 10,
		"helpers wear the ice down evenly (%.0f m³ in 20 s over %d spots, %d deeper than 1.2 m)" % [vol0 - grid.volume_left(), touched, deep])

	# --- Kevin: there's one volcano. You adopt him, then buying him again levels him up.
	# (No frames go by in here, so he doesn't throw any bombs at the tests below.)
	gs.grant_water(1e9)
	var kevin: Dictionary = shed.item("helper", 2)
	check(shed.describe(kevin).action == "ADOPT", "Kevin the volcano is up for adoption")
	for _i in 3:
		shed.use(kevin)
	world.helpers._update_volcano(0.0)
	var kd: Dictionary = shed.describe(kevin)
	var sign_text: String = world.helpers._kevin_sign.text
	check(gs.helper_counts[2] == 3 and kd.action == "UPGRADE" and str(kd.title).contains("Lv 3")
		and sign_text.contains("Lv 3") and (kevin.price as Label3D).text.begins_with("Lv 3"),
		"buying him again levels him up (%s; his sign says %s)" % [kd.title, sign_text])
	var swarm = world.helpers
	check(swarm.bomb_interval(3) < swarm.bomb_interval(1) and swarm.bomb_scale(3) > swarm.bomb_scale(1),
		"each level throws bigger bombs, more often")
	gs.helper_counts[2] = gs.helper_max_level(2)
	check(shed.describe(kevin).action == "MAXED" and not gs.buy_helper(2), "and he tops out at level %d" % gs.helper_max_level(2))
	gs.helper_counts[2] = 0
	world.helpers._update_volcano(0.0)   # (back to no Kevin for the rest of the test)

	# --- Ice left floating in the air melts away by itself, slowly.
	grid.find_floating_now()   # (first let any crumbs the helpers left melt)
	for _i in 60:
		grid._melt_floating(0.2)
	var cave := Vector3(11.5, 2.5, -17.0)
	var ff: PackedFloat32Array = grid.f
	for s in ff.size():
		var d: Vector3 = (grid.point_pos(s) - cave).abs()
		if d.x <= 2.01 and d.y <= 2.01 and d.z <= 2.01 and not (d.x <= 1.01 and d.y <= 1.01 and d.z <= 1.01):
			ff[s] = 0.0
	grid.f = ff
	grid._count()
	grid._touch(0, grid.nx - 1, 0, grid.nz - 1)
	grid.find_floating_now()
	var floating: int = grid.floating_count()
	var fade := 0.0
	while grid.floating_count() > 0 and fade < 15.0:
		grid._melt_floating(0.2)
		fade += 0.2
	check(floating == 125 and grid.floating_count() == 0 and fade > 3.0,
		"a block of ice left floating drips away (%d bits, gone after %.1f s)" % [floating, fade])

	# --- Small loose chunks on the ground melt away too; bigger ones stay.
	# Hollow out a room at the foot of thick ice and leave two blocks standing
	# in it: 3x3x2 points (18, about 2 m³) and 4x4x3 (48, 6 m³).
	var room := Vector3.INF
	for k in range(8, grid.nz - 8):
		for i in range(8, grid.nx - 8):
			var rp: Vector3 = grid.origin + Vector3(i, 0, k) * 0.5
			if rp.distance_to(Vector3(11.5, 0.0, -17.0)) < 8.0:
				continue
			var thick := true
			for corner in [Vector3(-3.5, 0, -2.5), Vector3(3.5, 0, -2.5), Vector3(-3.5, 0, 2.5), Vector3(3.5, 0, 2.5), Vector3.ZERO]:
				if grid.surface_y(rp.x + corner.x, rp.z + corner.z) < 3.5:
					thick = false
			if thick:
				room = rp
				break
		if room != Vector3.INF:
			break
	var small := []
	var big := []
	var ff2: PackedFloat32Array = grid.f
	for s in ff2.size():
		var d: Vector3 = grid.point_pos(s) - room
		if absf(d.x) > 3.01 or absf(d.z) > 2.01 or d.y > 2.01:
			continue
		if d.x >= -2.51 and d.x <= -1.49 and absf(d.z) <= 0.51 and d.y <= 0.51:
			small.append(s)
			ff2[s] = 1.0
		elif d.x >= 0.49 and d.x <= 2.01 and d.z >= -0.51 and d.z <= 1.01 and d.y <= 1.01:
			big.append(s)
			ff2[s] = 1.0
		elif not grid.find_points.has(s):
			ff2[s] = 0.0
	grid.f = ff2
	grid._count()
	grid._touch(0, grid.nx - 1, 0, grid.nz - 1)
	grid.find_floating_now()
	var small_marked := 0
	for s in small:
		if grid._floating.has(s):
			small_marked += 1
	var big_marked := 0
	for s in big:
		if grid._floating.has(s):
			big_marked += 1
	var t_small := 0.0
	var shrank := false
	while t_small < 15.0:
		var left := 0
		for s in small:
			if grid.f[s] > 0.5:
				left += 1
		if left == 0:
			break
		if left < small.size() and left > 0:
			shrank = true   # part of it is gone, part still there: it melts from the outside in
		grid._melt_floating(0.2)
		t_small += 0.2
	var big_left := 0
	for s in big:
		if grid.f[s] > 0.5:
			big_left += 1
	check(room != Vector3.INF and small.size() == 18 and big.size() == 48, "set up two loose chunks on the ground")
	check(small_marked == 18 and t_small > 2.0 and t_small < 15.0 and shrank,
		"a small loose chunk on the ground melts away by itself, outside first (gone after %.1f s)" % t_small)
	check(big_marked == 0 and big_left == 48, "a bigger chunk stays for you to melt (%d/48 left)" % big_left)

	# --- Glacier save string round trip (into a second, fresh glacier).
	var saved: String = grid.to_save_string()
	var copy = IceField.new()
	world.add_child(copy)
	copy.generate(world.level.glaciers[0], int(world.level.seed), [])
	check(copy.load_save_string(saved) and copy.remaining <= grid.remaining + 5 and copy.remaining >= grid.remaining - 5,
		"glacier save/load round trip (%d vs %d)" % [copy.remaining, grid.remaining])
	copy.queue_free()

	# --- Melt the village glacier: the village is free, the gate opens.
	var won := [false]
	gs.won.connect(func(): won[0] = true)
	var helpers_before: int = world.helpers._walkers.size()
	var tool_before: int = gs.tool_index
	var upgrades_before: Dictionary = gs.upgrade_levels.duplicate()
	grid.melt_everything()
	await _frames(2)
	var lake = world.glaciers[1]
	check(not won[0] and gs.stage == 1 and gs.grid == lake, "melting the village glacier opens the next stage, not the ending")
	check(world._villagers[0].visible, "the villagers came out")
	check(gs.helper_counts[0] == 0 and world.helpers._walkers.is_empty() and world.helpers._retired.size() == mini(helpers_before, 14),
		"the helpers retired (%d partying) and you hire a new crew" % world.helpers._retired.size())
	check(gs.helper_cost(0) == float(Balance.HELPERS[0].base) and gs.helper_cost(2) == float(Balance.HELPERS[2].base),
		"the new crew costs what the first one did (a penguin is 💧 %s again)" % Fmt.num(gs.helper_cost(0)))
	check(gs.tool_index == tool_before and tool_before > 0 and gs.upgrade_levels == upgrades_before and int(gs.upgrade_levels.heat) >= 1,
		"your tools and upgrades come with you (%s, heat Lv %d)" % [Balance.TOOLS[gs.tool_index].name, int(gs.upgrade_levels.heat)])
	check(world.hud.popups.get_child_count() > 0, "a popup says the village is free")
	for c in world.hud.popups.get_children():
		c.queue_free()
	player.input_enabled = true
	var valley_finds := true
	for d in Balance.finds_in(0):
		valley_finds = valley_finds and gs.discovered[d]
	check(valley_finds and not gs.discovered[Balance.finds_in(1)[0]], "every village find was dug up, the lake's are still frozen")
	await _frames(5)
	lake.flush()
	check(lake.collide and world._gate_shape.disabled, "the gate is open and the lake ice is solid")
	player.respawn(Vector3(0.0, 0.0, gate_z - 4.0), PI)
	player.move_input = Vector2(0, 1)
	for _i in 300:
		player._move(1.0 / 60.0)
	player.move_input = Vector2.ZERO
	check(player.position.z > gate_z + 4.0, "walked through the gate toward the lake (z=%.1f)" % player.position.z)
	# The lake shore is much wider than the valley, but the mountains still stop you.
	player.respawn(Vector3(0.0, 0.0, 30.0), -PI / 2.0)   # facing +x
	player.move_input = Vector2(0, 1)
	for _i in 900:
		player._move(1.0 / 60.0)
	player.move_input = Vector2.ZERO
	var edge: float = player.position.x
	check(edge > 30.0 and world.walkable(player.position.x, player.position.z), "walked along the lake shore past the old valley walls (x=%.1f)" % edge)
	check(not world.walkable(edge + 6.0, player.position.z), "and stopped at the mountains")
	# Melt the lake from the shore with the tool.
	var lake_left: int = lake.remaining
	var near := Vector3(0.0, 0.0, 30.0)
	while near.z < 60.0 and lake.surface_y(near.x, near.z + 3.0) < 1.5:
		near.z += 0.5
	player.respawn(near, PI)
	player._move(1.0 / 60.0)
	_aim_at(player, Vector3(near.x, 1.0, near.z + 3.5))
	player.melting = true
	for _i in 90:   # 3 s: Kevin's bombs may have bared harder ice here already
		player._update_tool(1.0 / 30.0)
	player.melting = false
	player._update_tool(0.0)
	check(lake.remaining < lake_left, "the tool melts the lake ice (%.1f m3)" % ((lake_left - lake.remaining) * lake.point_volume))

	# --- Melt the lake: the ending.
	lake.melt_everything()
	await _frames(2)
	check(won[0] and gs.has_won, "melting the frozen lake wins")
	check(not gs.discovered.has(false), "every find was discovered")

	# --- After the ending: the level menu shows what's coming next.
	var melt_new: Button = null
	for b in world.hud.popups.find_children("*", "Button", true, false):
		if (b as Button).text == "Melt a new glacier":
			melt_new = b
	check(melt_new != null, "the ending offers a new glacier")
	if melt_new != null:
		melt_new.pressed.emit()
		await _frames(2)
		var menu = world.hud.popups.get_child(world.hud.popups.get_child_count() - 1)
		var soon := 0
		for c in menu.cards:
			if c.find_child("Stamp", true, false) != null:
				soon += 1
		check(menu.has_signal("closed") and menu.cards.size() == Levels.MAPS.size()
			and menu.cards[0].find_child("Play", true, false) != null and soon == Levels.MAPS.size() - 1,
			"a new glacier opens the level menu: the valley again, and %d coming soon" % soon)
		menu.close()
		await _frames(2)
		check(world.hud.popups.get_child_count() == 0 and player.input_enabled, "closing the level menu goes back to the valley")

	# --- Game state save round trip.
	gs.save_game()
	var water_saved: float = gs.water
	gs.reset_state()
	gs.load_game()
	check(gs.has_won and gs.tool_index == 1 and absf(gs.water - water_saved) < 0.01, "save/load round trip")
	await process_frame
	check(root.get_node("Sound")._music_list == "summer", "summer's tune plays after the ending")
	check(gs.stage == 1 and gs.glacier_saves.size() == 2 and gs.glacier_saves[0] == "gone" and str(gs.glacier_saves[1]).begins_with("v3:"),
		"glaciers stored in the save (%d KB)" % (str(gs.glacier_saves[1]).length() / 1024))

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


func _sound(world, player) -> void:
	## Every sound the game asks for exists, and the tool, steam and music run.
	var sound = root.get_node("Sound")
	var names := {}
	var re := RegEx.create_from_string("Sound\\.(?:play|play_at|jingle)\\(\"([a-z0-9_]+)\"")
	for f in DirAccess.get_files_at("res://scripts"):
		if f.ends_with(".gd"):
			for m in re.search_all(FileAccess.get_file_as_string("res://scripts/" + f)):
				names[m.get_string(1)] = true
	for i in 6:
		names["tool_on_%d" % i] = true
		names["tool_loop_%d" % i] = true
	for i in 3:
		names["hire_%d" % i] = true
	for i in range(1, 6):
		names["find_jingle_%d" % i] = true
	for n in ["step_snow", "step_ground", "step_wood", "crack", "lake_crack", "drip", "jump", "land", "jet_start",
			"jet_sputter", "jet_loop", "sizzle_loop", "wind", "birds", "stage_done", "click", "shed_bell",
			"valley_1", "valley_2", "lake_1", "lake_2", "summer"]:
		names[n] = true
	var missing: Array = []
	for n in names:
		if sound.streams(n).is_empty():
			missing.append(n)
	check(missing.is_empty() and names.size() > 50, "all %d sounds exist %s" % [names.size(), missing])
	check(sound.streams("crack").size() >= 3, "cracks come in %d variations" % sound.streams("crack").size())
	check(sound._music_list == "valley", "the valley's music is lined up (%s)" % sound._music_list)
	var steps0: int = player.steps
	world.force_melt = true
	for _i in 20:
		await process_frame
	check(sound.loop_volume("tool") > 0.0 and sound._loops.tool.player.playing, "the hair dryer whirs while melting")
	check(sound.loop_volume("sizzle") > 0.0, "the ice hisses where the heat lands")
	world.force_melt = false
	for _i in 40:
		await process_frame
	check(sound.loop_volume("tool") == 0.0, "and goes quiet when you let go")
	var was_at: Vector3 = player.position
	player.move_input = Vector2(0, -1)   # back off the ice face, away from the glacier
	for _i in 120:
		player._move(1.0 / 60.0)
	player.move_input = Vector2.ZERO
	check(player.steps >= steps0 + 4, "walking takes footsteps (%d in 2 s)" % (player.steps - steps0))
	player.respawn(was_at, player.yaw)
	var mv: float = sound.music_volume
	sound.set_music_volume(0.3)
	check(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music")) < -8.0, "the music volume setting turns the Music bus down")
	sound.set_music_volume(mv)


func _ad_offers(gs, hud, player) -> void:
	## A timed offer tag drops in, is worth having, can be watched, and goes away.
	var mon = root.get_node("Monetization")
	var offers = hud.offers
	check(offers.current == "" and not hud.offer_tag.visible, "no ad offer in the first minutes")
	gs.water = 500.0
	offers._wait = 0.0
	await _frames(2)
	check(offers.current != "" and hud.offer_tag.visible, "an ad offer tag drops in (%s)" % offers.current)
	# Let it run out: the next one waits longer.
	offers.time_left = 0.0
	var gone: int = offers.update(0.1, true)
	check(gone == -1 and offers.current == "" and offers._wait > 200.0, "ignored, it goes away and the next one waits longer (%ds)" % int(offers._wait))
	# Double water: pays your water again, capped by recent income.
	gs.water = 1000.0
	var amount: float = gs.double_water_amount()
	check(amount > 0.0 and amount <= 1000.0, "double water pays at most your water (%s)" % amount)
	offers.current = "double_water"
	offers.time_left = 30.0
	hud.offer_tag.visible = true
	hud.take_offer()
	await _frames(1)
	check(offers.watching and mon.is_watching(), "tapping the tag plays the rewarded ad")
	mon.provider._close()
	mon.provider.rewarded_completed.emit("double_water")
	await _frames(1)
	check(absf(gs.water - (1000.0 + amount)) < 5.0 and offers.current == "" and player.input_enabled,
		"watching it to the end doubles the water and the tag goes (%s)" % gs.water)
	# Helpers 3x needs helpers; it speeds them up for a while.
	var before: float = gs.total_helper_power()
	hud.watch_ad("helper_rush")
	mon.provider._close()
	mon.provider.rewarded_completed.emit("boost_2x_heat")   # wrong placement: nothing
	mon.provider.rewarded_completed.emit("helper_rush")
	await _frames(1)
	check(gs.is_helper_rush_active() and absf(gs.total_helper_power() - before * 3.0) < 0.01, "helpers work 3x after the helper ad")
	gs.helper_rush_until = 0.0
	# Closing an ad early gives nothing.
	var w: float = gs.water
	hud.watch_ad("heat_rush")
	mon.provider._close()
	mon.provider.rewarded_failed.emit("boost_2x_heat", "closed early")
	await _frames(1)
	check(not gs.is_boost_active() and gs.water == w and player.input_enabled, "closing the ad early gives no reward")
	# The catalogue lists the free bonuses.
	hud.open_catalogue()
	await _frames(1)
	check(hud._list_box.get_child_count() >= 8, "the catalogue lists the free bonuses and the shop")
	hud.close_catalogue()
	offers._wait = 9999.0
