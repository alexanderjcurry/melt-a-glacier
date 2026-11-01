class_name World
extends Node3D
## The valley. Builds the 3D scene in code (sky, mountains, the glacier, the
## village frozen inside it, the shed), then wires up the player, the helpers,
## the HUD and the controls.

const SPAWN := Vector3(0.0, 0.0, 17.0)
const SPAWN_YAW := -0.3                        # facing the glacier, shed in view on the right
const FLOAT_POOL := 24
const FINALE_FRACTION := 0.012     # when this little ice is left, the rest melts by itself
const MAX_FLOATS_PER_FRAME := 3

# The village frozen in the ice. Footprints sit on whole metres so the ice can
# be carved out around each house exactly: [x, z, width, depth, walls, roof].
const HOUSES = [
	[-9, -21, 3, 3, Color(0.94, 0.88, 0.76), Color(0.72, 0.24, 0.2)],
	[-4, -22, 3, 3, Color(0.86, 0.9, 0.95), Color(0.25, 0.4, 0.7)],
	[5, -21, 4, 3, Color(0.95, 0.85, 0.6), Color(0.3, 0.55, 0.3)],
	[-9, -15, 3, 4, Color(0.98, 0.8, 0.55), Color(0.55, 0.3, 0.2)],
	[6, -15, 3, 3, Color(0.9, 0.75, 0.75), Color(0.4, 0.25, 0.45)],
]
const HOUSE_WALL := 3.0
const HOUSE_ROOF := 1.3
const CHURCH := [-1, -17, 4, 5]            # nave: x, z, width, depth
const CHURCH_WALL := 3.5
const CHURCH_ROOF := 1.6
const TOWER := [0, -12, 2, 2]              # in front of the nave
const TOWER_TOP := 6.0                     # the spire on top pokes out of the ice
const SPIRE := 3.8
const VILLAGERS = ["👵", "👴", "🧒", "👩", "👨", "🐕", "🐈", "🐓"]
const FLOWERS = ["🌼", "🌷", "🌸", "🌻"]

var level: Dictionary = Levels.current()
var grid: IceField
var player: Player
var helpers: HelperSwarm
var hud: Hud
var shed: Shed
var solids: Array[AABB] = []

var _ground_mat: StandardMaterial3D
var _mountains: MeshInstance3D
var _grass := Color(0.4, 0.62, 0.28)
var _moraine := Color(0.55, 0.46, 0.34)
var _mats := {}
var _find_markers := {}        # discovery index -> Label3D
var _flowers: Array = []       # {node, x, z, threshold}
var _villagers: Array = []     # Label3D
var _floats: Array = []        # {node, t}
var _float_i := 0
var _floats_this_frame := 0
var _mouse_melt := false
var _world_body: StaticBody3D  # ground, houses, the shed, rocks, tree trunks
var _pending_water := 0.0      # meltwater to show as a floating number soon
var _pending_at := Vector3.ZERO
var _pending_timer := 0.0
var force_melt := false        # tests and screenshots
var _quality := 1.0            # extra render-scale factor for slow devices
var _fps_timer := 0.0
var _slow_timer := 0.0
var _coach_timer := 0.0
var _in_shed := false
var _aimed: Dictionary = {}      # the thing for sale under the crosshair in the shed
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	UiTheme.install_emoji_font()
	_rng.seed = Balance.WORLD_SEED + 11
	_world_body = StaticBody3D.new()
	_world_body.collision_layer = Player.WORLD_LAYER
	_world_body.collision_mask = 0
	add_child(_world_body)
	var floor_shape := CollisionShape3D.new()
	floor_shape.shape = WorldBoundaryShape3D.new()
	_world_body.add_child(floor_shape)
	_build_environment()
	_build_shed()
	_build_ground()
	_build_mountains()
	var carve := _build_village()
	_build_trees()

	grid = IceField.new()
	add_child(grid)
	grid.generate(level, carve)
	if GameState.glacier_data != "":
		grid.load_save_string(GameState.glacier_data)
	GameState.grid = grid
	grid.ice_melted.connect(_on_ice_melted)
	grid.find_exposed.connect(_on_find_exposed)
	for box in solids:
		_add_solid_shape(box)
	_place_finds()
	_build_flowers()
	_build_villagers()
	_build_float_pool()

	player = Player.new()
	player.grid = grid
	add_child(player)
	var pos := GameState.player_pos if GameState.player_pos.is_finite() else SPAWN
	pos.x = clampf(pos.x, player.bounds_min.x + 0.5, player.bounds_max.x - 0.5)
	pos.z = clampf(pos.z, player.bounds_min.z + 0.5, player.bounds_max.z - 0.5)
	pos.y = maxf(pos.y, 0.0)
	player.position = pos
	if GameState.player_pos.is_finite():
		player.set_view(GameState.player_yaw, GameState.player_pitch)
	else:
		player.set_view(SPAWN_YAW, -0.12)
	player.unstick()
	GameState.player = player

	shed.player = player

	helpers = HelperSwarm.new()
	helpers.grid = grid
	helpers.player = player
	add_child(helpers)

	hud = Hud.new()
	hud.player = player
	hud.grid = grid
	add_child(hud)
	hud.respawn_requested.connect(respawn)

	get_window().size_changed.connect(_fit_render_scale)
	_fit_render_scale()

	GameState.won.connect(_on_won)
	if GameState.has_won:
		_on_won.call_deferred()
	_update_slow()


func respawn() -> void:
	## The "I'm stuck" button: back to the start, next to the shed.
	player.respawn(SPAWN, SPAWN_YAW)
	hud.toast("🏠 Back at the start")


func _fit_render_scale() -> void:
	## Phones have tiny, very dense screens: draw the 3D view at a lower
	## resolution (the HUD stays sharp) so it runs smoothly. Slow devices get
	## turned down further by _watch_frame_rate().
	var px := Vector2(get_window().size)
	var budget := 1.3e6 if DisplayServer.is_touchscreen_available() else 2.4e6
	var s := clampf(sqrt(budget / maxf(px.x * px.y, 1.0)) * _quality, 0.4, 1.0)
	var vp := get_viewport()
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	vp.scaling_3d_scale = s


func _watch_frame_rate(delta: float) -> void:
	## Every few seconds: if the game is struggling, draw the 3D view at a
	## lower resolution; if it's flying, creep back up.
	_fps_timer += delta
	if _fps_timer < 4.0:
		return
	_fps_timer = 0.0
	if Time.get_ticks_msec() < 8000:
		return   # still settling in after loading
	var fps := Engine.get_frames_per_second()
	var was := _quality
	if fps < 40.0:
		_quality = maxf(0.55, _quality - 0.12)
	elif fps > 57.0:
		_quality = minf(1.0, _quality + 0.05)
	if _quality != was:
		_fit_render_scale()


func _exit_tree() -> void:
	if GameState.grid == grid:
		GameState.save_game()
		GameState.grid = null
		GameState.player = null


# =====================================================================================
# Per frame: controls
# =====================================================================================
func _process(delta: float) -> void:
	_floats_this_frame = 0
	_watch_frame_rate(delta)
	_pending_timer += delta
	if _pending_timer >= 0.3 and _pending_water > 0.0:
		_float_text(_pending_at, "+" + Fmt.num(_pending_water))
		_pending_water = 0.0
		_pending_timer = 0.0
	var mv := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		mv.y += 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		mv.y -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		mv.x += 1.0
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		mv.x -= 1.0
	var touch := hud.touch
	var jet := Input.is_physical_key_pressed(KEY_SPACE)
	if touch.visible:
		mv += touch.move_vector
		player.add_look(touch.take_look_delta() * Balance.LOOK_SENSITIVITY_TOUCH)
		if touch.take_jump():
			player.jump()
		jet = jet or touch.jump_held
		touch.fuel = player.fuel
	player.move_input = mv
	player.jet_held = jet
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		_mouse_melt = false
	player.melting = _mouse_melt or force_melt or (touch.visible and touch.melting)
	_update_shed(delta)
	_update_floats(delta)
	_settle_finds(delta)
	_slow_timer += delta
	if _slow_timer >= 0.4:
		_slow_timer = 0.0
		_update_slow()
	_coach_timer += delta
	_update_coach()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		if not hud.touch_mode:
			hud.set_touch_mode(true)
		return
	if event is InputEventMouseButton:
		if event.device == InputEvent.DEVICE_ID_EMULATION:
			return   # a finger, already handled by the touch controls
		if hud.touch_mode:
			hud.set_touch_mode(false)
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
				if not hud.is_blocking():
					Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
				return
			if event.pressed and not _aimed.is_empty() and str(shed.describe(_aimed).action) != "":
				_mouse_melt = false
				use_aimed()   # in the shed, a click buys what you're looking at
				return
			_mouse_melt = event.pressed
	elif event is InputEventMouseMotion:
		if event.device != InputEvent.DEVICE_ID_EMULATION and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			player.add_look(event.relative * Balance.LOOK_SENSITIVITY_MOUSE)
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_SPACE:
				player.jump()
			KEY_R:
				if not hud.is_blocking():
					respawn()
			KEY_E, KEY_ENTER:
				if hud.catalogue_open:
					hud.close_catalogue()
				elif not hud.is_blocking():
					use_aimed()
			KEY_ESCAPE:
				if hud.catalogue_open:
					hud.close_catalogue()
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


# =====================================================================================
# The shed: walk in, look at something, buy it
# =====================================================================================
func _update_shed(delta: float) -> void:
	var inside := shed.contains(player.position)
	if inside != _in_shed:
		_in_shed = inside
		shed.marker.visible = not inside
		if not inside:
			# Walking out: done shopping (for the hints), save, and maybe an ad.
			if GameState.tutorial_step >= 2:
				GameState.tutorial_step = maxi(GameState.tutorial_step, 4)
			GameState.save_game()
			Monetization.maybe_show_interstitial("shed_exit")
	_aimed = {}
	if inside and not hud.is_blocking():
		_aimed = shed.aim(player.camera.global_position, player.aim_dir())
	shed.update(delta, _aimed)
	hud.set_shop_info(shed.describe(_aimed) if not _aimed.is_empty() else {})
	if hud.touch.take_action():
		use_aimed()


func use_aimed() -> void:
	## Buy (or hire, or open) whatever the crosshair is on in the shed.
	if _aimed.is_empty():
		return
	var r := shed.use(_aimed)
	if r.open_catalogue:
		hud.open_catalogue()
	elif r.text != "":
		hud.toast(r.text)
	if r.ok and _aimed.kind != "catalogue":
		GameState.tutorial_step = maxi(GameState.tutorial_step, 4)


# =====================================================================================
# Melting, finds, floating numbers
# =====================================================================================
func _on_ice_melted(at: Vector3, points: int, hp: float) -> void:
	var v := GameState.on_ice_melted(points, hp)
	if at.is_finite() and not _in_shed:   # (the numbers show through walls)
		_pending_water += v
		_pending_at = at + Vector3(0, 0.4, 0)
	if GameState.has_won:
		return
	if grid.remaining <= 0:
		GameState.check_win()
	elif grid.fraction_left() < FINALE_FRACTION:
		# The last crumbs of the glacier collapse into slush on their own.
		hud.toast("💦 The last of the glacier collapses into slush!")
		grid.melt_everything.call_deferred()


func _on_find_exposed(d: int) -> void:
	_reveal_find(d, true)
	GameState.discover(d)


func _place_finds() -> void:
	## Each find is frozen at a fixed spot at its layer's depth, the same every game.
	var rng := RandomNumberGenerator.new()
	rng.seed = Balance.WORLD_SEED + 7
	var spots: Array = []
	for d in Balance.DISCOVERIES.size():
		var want: int = Balance.DISCOVERIES[d].layer
		var spot := Vector3.INF
		for _t in 4000:
			var x := rng.randf_range(-12.5, 12.5)
			var z := rng.randf_range(-26.0, 1.0)
			var y := grid.original_top(x, z) - (float(want) + 0.5) * IceField.LAYER_DEPTH
			if y < 0.5:
				continue
			var p := Vector3(x, y, z)
			if grid.density_at(p) < 0.95 and not GameState.discovered[d] and grid.remaining == grid.total:
				continue   # in a crevasse or a house (only checkable on a fresh glacier)
			var crowded := false
			for o in spots:
				if (o as Vector3).distance_to(p) < 3.0:
					crowded = true
			for box in solids:
				if (box as AABB).grow(0.8).has_point(p):
					crowded = true
			if crowded:
				continue
			spot = p
			break
		if spot == Vector3.INF:
			push_warning("No spot for find %d" % d)
			continue
		spots.append(spot)
		var marker := _make_find_marker(d)
		marker.position = spot
		add_child(marker)
		_find_markers[d] = marker
		if GameState.discovered[d] or not grid.watch_find(spot, d):
			# Found in an earlier session (or its ice melted while we were away).
			_reveal_find(d, false)
			if not GameState.discovered[d]:
				GameState.discover(d)


func _make_find_marker(d: int) -> Label3D:
	var info: Dictionary = Balance.DISCOVERIES[d]
	var l := Label3D.new()
	l.text = info.icon
	l.font_size = 128
	l.pixel_size = 0.0055
	l.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	l.alpha_cut = Label3D.ALPHA_CUT_DISCARD
	l.visible = false
	var name_tag := Label3D.new()
	name_tag.text = info.name
	name_tag.font_size = 40
	name_tag.pixel_size = 0.0007
	name_tag.fixed_size = true
	name_tag.outline_size = 10
	name_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	name_tag.position = Vector3(0, 0.55, 0)
	l.add_child(name_tag)
	return l


func _reveal_find(d: int, animate: bool) -> void:
	var m: Label3D = _find_markers.get(d)
	if m == null:
		return
	m.visible = true
	if animate:
		m.scale = Vector3.ONE * 0.2
		var tw := m.create_tween()
		tw.tween_property(m, "scale", Vector3.ONE * 1.5, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(m, "scale", Vector3.ONE, 0.3)


func _settle_finds(delta: float) -> void:
	## Found things drop to whatever is under them as the ice melts away.
	## Their name tags only show up close.
	for d in _find_markers:
		var m: Label3D = _find_markers[d]
		if not m.visible:
			continue
		(m.get_child(0) as Label3D).visible = m.position.distance_squared_to(player.position) < 49.0
		var rest := _floor_under(m.position) + 0.36
		if m.position.y > rest + 0.001:
			m.position.y = maxf(rest, m.position.y - delta * 5.0)


func _floor_under(p: Vector3) -> float:
	var floor_y := grid.floor_below(p)
	for box in solids:
		var b := box as AABB
		if p.x >= b.position.x and p.x <= b.end.x and p.z >= b.position.z and p.z <= b.end.z and b.end.y <= p.y + 0.4:
			floor_y = maxf(floor_y, b.end.y)
	return floor_y


func _add_solid_shape(box: AABB) -> void:
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = box.size
	cs.shape = bs
	cs.position = box.get_center()
	_world_body.add_child(cs)


func _build_float_pool() -> void:
	for _i in FLOAT_POOL:
		var l := Label3D.new()
		l.font_size = 56
		l.pixel_size = 0.005
		l.outline_size = 12
		l.modulate = Color(0.75, 0.92, 1.0)
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.no_depth_test = true
		l.render_priority = 10
		l.outline_render_priority = 9
		l.visible = false
		add_child(l)
		_floats.append({"node": l, "t": 0.0})


func _float_text(at: Vector3, text: String) -> void:
	if _floats_this_frame >= MAX_FLOATS_PER_FRAME or player == null:
		return
	if at.distance_squared_to(player.position) > 900.0:
		return
	_floats_this_frame += 1
	var f: Dictionary = _floats[_float_i]
	_float_i = (_float_i + 1) % _floats.size()
	var l: Label3D = f.node
	l.text = text
	l.position = at + Vector3(_rng.randf_range(-0.25, 0.25), 0.2, _rng.randf_range(-0.25, 0.25))
	l.visible = true
	f.t = 0.0


func _update_floats(delta: float) -> void:
	for f in _floats:
		var l: Label3D = f.node
		if not l.visible:
			continue
		f.t += delta
		l.position.y += delta * 1.1
		var a := clampf(1.4 - f.t * 1.4, 0.0, 1.0)
		l.modulate.a = a
		l.outline_modulate.a = a
		if f.t >= 1.0:
			l.visible = false


# =====================================================================================
# Slow updates: the valley greens up, flowers bloom, onboarding hints
# =====================================================================================
func _update_slow() -> void:
	var melted := 1.0 - grid.fraction_left()
	_ground_mat.albedo_color = _moraine.lerp(_grass, clampf(pow(melted, 0.6), 0.0, 1.0))
	if _mountains != null:
		(_mountains.material_override as ShaderMaterial).set_shader_parameter("foot_color", _ground_mat.albedo_color)
	for f in _flowers:
		var node: Label3D = f.node
		if node.visible:
			continue
		var bloom := false
		if f.inside:
			bloom = melted > 0.02 and not grid.has_ice_at(f.x, f.z)
		else:
			bloom = melted >= f.threshold
		if bloom:
			node.visible = true
			node.scale = Vector3.ONE * 0.1
			node.create_tween().tween_property(node, "scale", Vector3.ONE, 0.6) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _update_coach() -> void:
	var text := ""
	if _in_shed and GameState.tutorial_step < 4:
		if hud.touch_mode:
			text = "Everything in here is for sale.\nLook at something, then tap BUY"
		else:
			text = "Everything in here is for sale.\nAim at something and click to buy it"
		hud.set_coach(text)
		return
	match GameState.tutorial_step:
		0:
			if GameState.blocks_melted > 0:
				GameState.tutorial_step = 1
				_coach_timer = 0.0
			elif hud.touch_mode:
				text = "Walk up to the ice with the left stick,\naim at it and hold 🔥 to melt it"
			else:
				text = "Walk up to the ice (WASD), aim at it\nand hold the left mouse button to melt it"
		1:
			text = "Melted ice turns into 💧 meltwater.\nDeeper ice is harder, but worth more"
			if _coach_timer > 7.0:
				GameState.tutorial_step = 2
		2:
			if GameState.water >= 20.0:
				text = "Spend your 💧 at the 🏠 shed:\nwalk in, hotter tools melt way faster"
	hud.set_coach(text)


func _on_won() -> void:
	for v in _villagers:
		(v as Node3D).visible = true
	_update_slow()
	hud.show_ending()


# =====================================================================================
# Building the valley
# =====================================================================================
func _mat(c: Color, roughness: float = 0.9) -> StandardMaterial3D:
	var key := "%s/%s" % [c.to_html(), roughness]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = roughness
	_mats[key] = m
	return m


func _mesh(mesh: Mesh, pos: Vector3, c: Color, parent: Node = self) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.material_override = _mat(c)
	# Only things near the playing area cast shadows (the shadow map covers ~70 m).
	var near := Vector2(pos.x, pos.z - 0.0).length() < 45.0
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if near else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


func _box(size: Vector3, center: Vector3, c: Color) -> MeshInstance3D:
	var bm := BoxMesh.new()
	bm.size = size
	return _mesh(bm, center, c)


func _cone(base: Vector3, radius: float, height: float, c: Color, segments: int = 8) -> MeshInstance3D:
	var cm := CylinderMesh.new()
	cm.top_radius = 0.0
	cm.bottom_radius = radius
	cm.height = height
	cm.radial_segments = segments
	cm.rings = 1
	return _mesh(cm, base + Vector3(0, height * 0.5, 0), c)


func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = Scenery.sky(int(level.seed))
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.72
	env.tonemap_white = 2.2   # a gentle shoulder, so sunlit snow keeps its texture
	env.ambient_light_energy = 0.65   # with a slightly softer sun: gentler shade on a phone screen
	# A quarter of the fill light is neutral, so shade isn't deep blue.
	env.ambient_light_sky_contribution = 0.75
	env.ambient_light_color = Color(0.62, 0.64, 0.68)
	env.fog_enabled = true
	env.fog_light_color = Color(0.74, 0.84, 0.95)
	env.fog_density = 0.0035
	env.fog_sky_affect = 0.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	# Low afternoon sun from the right, so the glacier's shape reads in light
	# and shadow (from straight behind the camera everything looks flat).
	var sun := DirectionalLight3D.new()
	sun.transform.basis = Basis.looking_at(Vector3(-0.58, -0.6, -0.55).normalized(), Vector3.UP)
	sun.light_energy = 0.85
	sun.light_color = Color(1.0, 0.95, 0.88)
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 70.0
	sun.directional_shadow_split_1 = 0.25
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.2
	sun.shadow_blur = 1.5
	add_child(sun)


func _build_ground() -> void:
	# A soft noise texture so the ground isn't one flat colour.
	var noise := FastNoiseLite.new()
	noise.seed = Balance.WORLD_SEED + 5
	noise.frequency = 0.05
	var img := noise.get_seamless_image(128, 128)
	img.convert(Image.FORMAT_RGB8)
	for y in img.get_height():
		for x in img.get_width():
			var v := 0.7 + 0.3 * img.get_pixel(x, y).r
			img.set_pixel(x, y, Color(v, v, v))
	img.generate_mipmaps()
	_ground_mat = StandardMaterial3D.new()
	_ground_mat.albedo_texture = ImageTexture.create_from_image(img)
	_ground_mat.uv1_scale = Vector3(50, 50, 1)
	_ground_mat.roughness = 1.0
	_ground_mat.albedo_color = _moraine
	var pm := PlaneMesh.new()
	pm.size = Vector2(500, 500)
	var ground := MeshInstance3D.new()
	ground.mesh = pm
	ground.material_override = _ground_mat
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ground)

	# The meltwater lake past the glacier's tongue, and the stream that feeds it.
	add_child(Scenery.lake(level))
	var stream := Scenery.stream(level)
	if stream != null:
		add_child(stream)

	# A few boulders for scale.
	var spots := [Vector3(-14, 0, 13), Vector3(-5, 0, 19), Vector3(19.2, 0, 5.0), Vector3(-19, 0, 2),
			Vector3(18, 0, -6), Vector3(4, 0, 19.5), Vector3(-20, 0, 9), Vector3(19.5, 0, 15)]
	for i in spots.size():
		var p: Vector3 = spots[i]
		if shed.blocks(p.x, p.z, 1.0):
			continue
		var r := MeshInstance3D.new()
		r.mesh = Scenery.boulder_mesh(i % 4)
		r.material_override = Scenery.rock_material(0.25)
		r.position = p
		var sc := _rng.randf_range(1.0, 1.9)
		r.scale = Vector3.ONE * sc
		r.rotation.y = _rng.randf() * TAU
		add_child(r)
		solids.append(AABB(p - Vector3(0.45, 0.0, 0.45) * sc, Vector3(0.9, 0.42, 0.9) * sc))


func _build_mountains() -> void:
	# One heightfield all the way round, with a hollow for Kevin the volcano.
	var kevin := Vector2(HelperSwarm.VOLCANO_POS.x, HelperSwarm.VOLCANO_POS.z)
	_mountains = Scenery.mountains(level, kevin, IceField.detail_texture(int(level.seed)))
	add_child(_mountains)


func _build_village() -> Array:
	## Builds the frozen village and returns the boxes to carve out of the ice.
	var carve: Array = []
	for hdef in HOUSES:
		var x := float(hdef[0])
		var z := float(hdef[1])
		var w := float(hdef[2])
		var d := float(hdef[3])
		_house(x, z, w, d, HOUSE_WALL, HOUSE_ROOF, hdef[4], hdef[5])
		var box := AABB(Vector3(x, 0, z), Vector3(w, HOUSE_WALL + HOUSE_ROOF, d))
		carve.append(box)
		solids.append(box)
	# The church, with a steeple tall enough to poke out of the top of the glacier.
	var cx := float(CHURCH[0])
	var cz := float(CHURCH[1])
	var cw := float(CHURCH[2])
	var cd := float(CHURCH[3])
	_house(cx, cz, cw, cd, CHURCH_WALL, CHURCH_ROOF, Color(0.93, 0.93, 0.9), Color(0.45, 0.47, 0.55))
	var nave := AABB(Vector3(cx, 0, cz), Vector3(cw, CHURCH_WALL + CHURCH_ROOF, cd))
	carve.append(nave)
	solids.append(nave)
	var tx := float(TOWER[0])
	var tz := float(TOWER[1])
	var tw := float(TOWER[2])
	var td := float(TOWER[3])
	var stone := Color(0.86, 0.83, 0.76)
	_box(Vector3(tw, TOWER_TOP, td), Vector3(tx + tw * 0.5, TOWER_TOP * 0.5, tz + td * 0.5), stone)
	_box(Vector3(tw + 0.16, 0.25, td + 0.16), Vector3(tx + tw * 0.5, TOWER_TOP - 1.9, tz + td * 0.5), stone.darkened(0.2))
	_box(Vector3(tw + 0.16, 0.2, td + 0.16), Vector3(tx + tw * 0.5, TOWER_TOP - 0.1, tz + td * 0.5), stone.darkened(0.2))
	_box(Vector3(0.9, 1.6, 0.06), Vector3(tx + tw * 0.5, 0.8, tz + td + 0.03), Color(0.4, 0.25, 0.15))
	# Belfry openings on all four sides, and a clock.
	var dark := Color(0.12, 0.12, 0.16)
	_box(Vector3(0.7, 1.0, 0.06), Vector3(tx + tw * 0.5, TOWER_TOP - 0.9, tz + td + 0.03), dark)
	_box(Vector3(0.7, 1.0, 0.06), Vector3(tx + tw * 0.5, TOWER_TOP - 0.9, tz - 0.03), dark)
	_box(Vector3(0.06, 1.0, 0.7), Vector3(tx - 0.03, TOWER_TOP - 0.9, tz + td * 0.5), dark)
	_box(Vector3(0.06, 1.0, 0.7), Vector3(tx + tw + 0.03, TOWER_TOP - 0.9, tz + td * 0.5), dark)
	var clock := CylinderMesh.new()
	clock.top_radius = 0.42
	clock.bottom_radius = 0.42
	clock.height = 0.05
	var face := _mesh(clock, Vector3(tx + tw * 0.5, TOWER_TOP - 2.8, tz + td + 0.03), Color(0.97, 0.95, 0.85))
	face.rotation.x = PI / 2.0
	_box(Vector3(0.05, 0.3, 0.04), Vector3(tx + tw * 0.5, TOWER_TOP - 2.68, tz + td + 0.07), dark)
	_box(Vector3(0.22, 0.05, 0.04), Vector3(tx + tw * 0.5 + 0.1, TOWER_TOP - 2.8, tz + td + 0.07), dark)
	var spire := _cone(Vector3(tx + tw * 0.5, TOWER_TOP, tz + td * 0.5), tw * 0.72, SPIRE, Color(0.35, 0.38, 0.5), 4)
	spire.rotation.y = PI / 4.0
	_box(Vector3(0.1, 0.7, 0.1), Vector3(tx + tw * 0.5, TOWER_TOP + SPIRE + 0.3, tz + td * 0.5), Color(0.95, 0.8, 0.3))
	_box(Vector3(0.45, 0.1, 0.1), Vector3(tx + tw * 0.5, TOWER_TOP + SPIRE + 0.4, tz + td * 0.5), Color(0.95, 0.8, 0.3))
	var tower := AABB(Vector3(tx, 0, tz), Vector3(tw, TOWER_TOP, td))
	carve.append(tower)
	solids.append(tower)
	solids.append(AABB(Vector3(tx + tw * 0.5 - 0.5, TOWER_TOP, tz + td * 0.5 - 0.5), Vector3(1.0, SPIRE * 0.6, 1.0)))
	# A well in the square.
	var well := CylinderMesh.new()
	well.top_radius = 0.7
	well.bottom_radius = 0.7
	well.height = 0.9
	_mesh(well, Vector3(1.5, 0.45, -19.5), Color(0.55, 0.55, 0.58))
	solids.append(AABB(Vector3(0.8, 0, -20.2), Vector3(1.4, 0.9, 1.4)))
	return carve


func _house(x: float, z: float, w: float, d: float, wall: float, roof: float, wall_col: Color, roof_col: Color) -> void:
	var cx := x + w * 0.5
	var cz := z + d * 0.5
	_box(Vector3(w, wall, d), Vector3(cx, wall * 0.5, cz), wall_col)
	var pm := PrismMesh.new()
	pm.size = Vector3(w + 0.3, roof, d + 0.3)
	_mesh(pm, Vector3(cx, wall + roof * 0.5, cz), roof_col)
	# Door and windows on the side facing the valley mouth.
	var front := z + d + 0.03
	_box(Vector3(0.8, 1.7, 0.06), Vector3(cx, 0.85, front), Color(0.4, 0.25, 0.15))
	if w >= 3.0:
		_box(Vector3(0.6, 0.6, 0.06), Vector3(x + 0.6, 1.9, front), Color(0.95, 0.85, 0.45))
		_box(Vector3(0.6, 0.6, 0.06), Vector3(x + w - 0.6, 1.9, front), Color(0.95, 0.85, 0.45))
	_box(Vector3(0.06, 0.6, 0.6), Vector3(x - 0.03, 1.9, cz), Color(0.95, 0.85, 0.45))
	_box(Vector3(0.06, 0.6, 0.6), Vector3(x + w + 0.03, 1.9, cz), Color(0.95, 0.85, 0.45))


func _build_shed() -> void:
	## The tool shed by the path: a red cabin you walk into to shop (see Shed).
	shed = Shed.new()
	add_child(shed)
	shed.build(IceField.detail_texture(int(level.seed)))


func _build_trees() -> void:
	# Pines along both sides of the valley near the shed, and a forest further
	# out toward the lake.
	var near := []
	var far := []
	var v: Dictionary = level.valley
	for i in 120:
		var side := -1.0 if i % 2 == 0 else 1.0
		var x: float
		var z: float
		if i < 30:
			x = side * _rng.randf_range(13.0, 21.5)
			z = _rng.randf_range(6.0, 30.0)
		else:
			z = _rng.randf_range(20.0, 62.0)
			var hw: float = v.half_width + maxf(0.0, z - v.flare_z) * v.flare
			x = side * _rng.randf_range(12.0, hw - 1.0)
		if shed.blocks(x, z, 1.2) or Scenery.on_lake(level, x, z, 2.0) \
				or Scenery.near_stream(level, x, z, 2.0) or Vector2(x - SPAWN.x, z - SPAWN.z).length() < 4.0:
			continue
		var s := _rng.randf_range(0.8, 1.4) if i < 30 else _rng.randf_range(0.9, 1.7)
		var spot := [Vector3(x, 0, z), s, _rng.randf() * TAU]
		if z < 26.0:
			near.append(spot)
			if z < 20.0:
				solids.append(AABB(Vector3(x - 0.3, 0, z - 0.3), Vector3(0.6, 4.0 * s, 0.6)))
		else:
			far.append(spot)
	add_child(Scenery.forest(near, true))
	add_child(Scenery.forest(far, false))


func _build_flowers() -> void:
	# Flowers bloom where the ice has gone: inside the glacier's footprint once
	# that spot is bare, and out in the valley as the whole glacier shrinks.
	var rng := RandomNumberGenerator.new()
	rng.seed = Balance.WORLD_SEED + 21
	for i in 44:
		var inside := i < 26
		var x: float
		var z: float
		if inside:
			x = rng.randf_range(-15.5, 15.5)
			z = rng.randf_range(-24.0, 4.0)
		else:
			x = rng.randf_range(-20.0, 20.0)
			z = rng.randf_range(5.0, 19.5)
		var blocked := shed.blocks(x, z, 0.3)
		for s in solids:
			if s.grow(0.3).has_point(Vector3(x, 0.2, z)):
				blocked = true
		if blocked:
			continue
		var l := Label3D.new()
		l.text = FLOWERS[rng.randi() % FLOWERS.size()]
		l.font_size = 64
		l.pixel_size = 0.0045
		l.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		l.alpha_cut = Label3D.ALPHA_CUT_DISCARD
		l.position = Vector3(x, 0.15, z)
		l.visible = false
		add_child(l)
		_flowers.append({"node": l, "x": x, "z": z, "inside": inside, "threshold": rng.randf_range(0.05, 0.95)})


func _build_villagers() -> void:
	var spots := [Vector3(-7.5, 0.4, -16.6), Vector3(-2.5, 0.4, -18.3), Vector3(7.0, 0.4, -17.4),
		Vector3(1.0, 0.4, -9.2), Vector3(-6.5, 0.4, -10.5), Vector3(4.5, 0.4, -10.8),
		Vector3(3.2, 0.4, -19.0), Vector3(-0.8, 0.4, -20.5)]
	for i in VILLAGERS.size():
		var l := Label3D.new()
		l.text = VILLAGERS[i]
		l.font_size = 128
		l.pixel_size = 0.0065
		l.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		l.alpha_cut = Label3D.ALPHA_CUT_DISCARD
		l.position = spots[i]
		l.visible = false
		add_child(l)
		_villagers.append(l)
		var tw := l.create_tween().set_loops()
		tw.tween_property(l, "position:y", 0.62, 0.35 + 0.05 * i).set_trans(Tween.TRANS_SINE)
		tw.tween_property(l, "position:y", 0.4, 0.35 + 0.05 * i).set_trans(Tween.TRANS_SINE)
