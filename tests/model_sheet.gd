extends SceneTree
## A contact sheet of every mesh in one models/*.glb, for checking the art:
##   xvfb-run godot --rendering-driver opengl3 -s res://tests/model_sheet.gd -- finds /tmp/finds.png [yaw°] [only this mesh]
## (yaw turns every model round, e.g. 90 to see ships side on)
## Each mesh is baked (Models.baked), scaled to about the same size and shown
## from the front, a little above, in the game's sunlight.

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var file: String = args[0]
	var out: String = args[1] if args.size() > 1 else "/tmp/%s.png" % file
	var yaw := deg_to_rad(float(args[2])) if args.size() > 2 else 0.0
	var world := Node3D.new()
	root.add_child(world)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.55, 0.7, 0.85)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.8, 0.9)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.72
	env.tonemap_white = 2.2
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.transform.basis = Basis.looking_at(Vector3(-0.58, -0.6, -0.55).normalized(), Vector3.UP)
	sun.light_energy = 0.85
	sun.shadow_enabled = true
	world.add_child(sun)
	var scn: Node = Models.scene(file).instantiate()
	var names: Array = []
	for c in scn.get_children():
		if c is MeshInstance3D and (args.size() < 4 or c.name == args[3]):
			names.append(c.name)
	scn.free()
	var cols := ceili(sqrt(float(names.size()) * 1.6))
	for i in names.size():
		var mesh := Models.baked(file, names[i])
		var mi := Models.baked_instance(mesh)
		var box := mesh.get_aabb()
		var s := 1.0 / maxf(box.size.x, maxf(box.size.y, box.size.z))
		mi.scale = Vector3.ONE * s
		mi.rotation.y = yaw
		var cell := Vector3((i % cols) * 1.3, -(i / cols) * 1.3, 0)
		mi.position = cell - Basis(Vector3.UP, yaw) * (box.get_center() * s)
		world.add_child(mi)
		var l := Label3D.new()
		l.text = names[i]
		l.pixel_size = 0.002
		l.position = cell + Vector3(0, -0.6, 0)
		l.rotation.y = PI   # the camera looks from -Z
		world.add_child(l)
	var rows := ceili(float(names.size()) / cols)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = rows * 1.3 + 0.4
	var centre := Vector3((cols - 1) * 0.65, -(rows - 1) * 0.65, 0)
	cam.position = centre + Vector3(0, 2.0, -8.0)
	world.add_child(cam)
	cam.look_at(centre, Vector3.UP)
	cam.current = true
	for _i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out)
	print("saved ", out)
	quit(0)
