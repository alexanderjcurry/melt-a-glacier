extends SceneTree
## Screenshots of the HUD's catalogue button, an ad offer tag and the catalogue:
##   xvfb-run -s "-screen 0 1600x900x24" godot --rendering-driver opengl3 -s res://tests/offer_shots.gd -- /tmp/shots [touch]
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
	root.get_texture().get_image().save_png("%s/%s.png" % [out_dir, name])
	print("saved ", name)


func _frames(n: int) -> void:
	for _i in n:
		await process_frame


func _run() -> void:
	var gs = root.get_node("GameState")
	gs.wipe_save()
	var world = load("res://scenes/world.tscn").instantiate()
	root.add_child(world)
	var hud = world.hud
	var touch: bool = OS.get_cmdline_user_args().has("touch")
	hud.set_touch_mode(touch)
	var sfx := "_touch" if touch else ""
	gs.tool_index = 2
	gs.helper_counts[0] = 3
	gs.water = 2600.0
	gs.tutorial_step = 9
	await _frames(10)
	# Double water that would buy the next tool (the Flamethrower costs 100K: make it close).
	gs.water = 70000.0
	gs._income = [7000.0]
	gs._income_t = 14.0
	hud.offers._wait = 0.0
	hud.offers._last = "heat_rush"
	await _frames(4)
	await _frames(30)
	await _shot("offer_tag%s" % sfx)
	hud.open_catalogue()
	await _frames(6)
	await _shot("catalogue_with_offer%s" % sfx)
	hud.close_catalogue()
	gs.boost_until = gs.now() + 200.0
	gs.helper_rush_until = gs.now() + 95.0
	hud.offers._pass()
	await _frames(40)
	await _shot("rewards_running%s" % sfx)
	quit()
