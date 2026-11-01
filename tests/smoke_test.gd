extends SceneTree
## Headless smoke test: godot --headless -s res://tests/smoke_test.gd
## Loads the main scene, taps, buys things, fakes offline time, and melts to the end.

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var gs = root.get_node("GameState")
	gs.wipe_save()
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	var ok := true

	for i in 20:
		gs.tap()
	print("after 20 taps: water=", gs.water, " layer_hp=", gs.layer_hp)
	ok = ok and gs.water > 0.0

	gs.grant_water(1000.0)
	ok = ok and gs.buy_helper(0)
	ok = ok and gs.buy_stat("heat")
	print("bought helper+stat: helpers=", gs.helper_counts, " stats=", gs.stat_levels)

	# Cycle every tab to exercise list builders.
	for t in 5:
		main._select_tab(t)
		await process_frame

	# Offline earnings
	var got := []
	gs.offline_earned.connect(func(r): got.append(r))
	gs.last_active_time -= 3600.0
	gs.check_offline()
	print("offline: ", got)
	ok = ok and got.size() == 1

	# A frozen main loop (phone locked / browser tab hidden) also pays out.
	gs._last_tick_time -= 600.0
	await process_frame
	await process_frame
	print("after freeze: ", got.size(), " payouts")
	ok = ok and got.size() == 2 and absf(got[1].seconds - 600.0) < 5.0

	# Melt everything and check discoveries + win.
	var won := [false]
	gs.won.connect(func(): won[0] = true)
	gs.melt_raw(Balance.total_ice() * 2.0)
	await process_frame
	print("won=", won[0], " has_won=", gs.has_won, " discovered=", gs.discovered)
	ok = ok and won[0] and not gs.discovered.has(false)

	# Save round trip
	gs.save_game()
	gs.reset_state()
	gs.load_game()
	ok = ok and gs.has_won
	print("save roundtrip has_won=", gs.has_won)

	for i in 30:
		await process_frame
	gs.wipe_save()
	print("SMOKE TEST ", "PASSED" if ok else "FAILED")
	quit(0 if ok else 1)
