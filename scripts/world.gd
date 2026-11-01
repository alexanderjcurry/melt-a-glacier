class_name World
extends Node3D
## The valley. Builds the 3D scene in code (sky, mountains, the glaciers, the
## village frozen inside the first one, the shed, the fence in front of the
## frozen lake), then wires up the player, the helpers, the HUD and the controls.
## You melt the level's glaciers in order (GameState.stage): the village
## glacier, then the frozen lake behind the gate.

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
const TOWER_TOP := 9.0                     # the spire on top pokes out of the ice
const SPIRE := 3.8
const VILLAGERS = ["Grandma", "Grandpa", "Kid", "Woman", "Man", "Dog", "Cat", "Rooster"]   # meshes in characters.glb
const FLOWERS = ["Daisy", "Tulip", "Cosmos", "Sunflower"]   # meshes in nature.glb

var level: Dictionary = Levels.current()
var grid: IceField             # the village glacier (the first glacier)
var glaciers: Array = []       # every glacier in the level, in the order you melt them
var player: Player
var helpers: HelperSwarm
var hud: Hud
var shed: Shed
var solids: Array[AABB] = []

var _ground_mat: StandardMaterial3D
var _mountains: MeshInstance3D
var _grass := Color(0.42, 0.57, 0.3)
var _moraine := Color(0.55, 0.46, 0.34)
var _mats := {}
var _find_markers := {}        # discovery index -> Node3D (see _make_find_marker)
var _find_spots := {}          # discovery index -> where it's frozen (worked out on the fresh ice)
var _ghosts := {}              # discovery index -> {node, mat, alpha, target}: its shadow in the ice
var _ghost_i := 0              # the one whose ice gets checked this frame
var _cover_dirs: Array = []    # directions _ice_cover looks along
var _gate: Node3D              # swings open when the village is free
var _gate_shape: CollisionShape3D
var _gate_sign: Label3D
var _lake_water: MeshInstance3D
var _water_mat: Material
var _flowers: Array = []       # {node, x, z, threshold}
var _villagers: Array = []     # Node3D
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

	_build_fence()

	# The glaciers. Each find's spot is worked out on the fresh ice (so it's the
	# same every game), then the save is loaded on top.
	var stage := clampi(GameState.stage, 0, level.glaciers.size() - 1)
	GameState.stage = stage
	for g in level.glaciers.size():
		var field := IceField.new()
		field.name = "Glacier%d" % g
		field.collide = g == stage   # the ones you can't reach yet can't be hit or stood on
		add_child(field)
		field.generate(level.glaciers[g], int(level.seed) + 1000 * g, carve if g == 0 else [], g >= stage)
		glaciers.append(field)
	grid = glaciers[0]
	GameState.grids = glaciers
	_place_finds()
	for g in glaciers.size():
		var field: IceField = glaciers[g]
		var saved := str(GameState.glacier_saves[g]) if g < GameState.glacier_saves.size() else ""
		if g < stage or saved == "gone":
			field.clear_all()
		elif saved != "":
			field.load_save_string(saved)
		field.ice_melted.connect(_on_ice_melted.bind(field))
		field.find_exposed.connect(_on_find_exposed)
	GameState.grid = glaciers[stage]
	GameState.stage_changed.connect(_on_stage_changed)
	for box in solids:
		_add_solid_shape(box)
	_arm_finds()
	_build_flowers()
	_build_villagers()
	_build_float_pool()

	player = Player.new()
	player.grids = glaciers
	player.grid = GameState.grid
	_set_bounds()
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
	helpers.grid = GameState.grid
	helpers.player = player
	add_child(helpers)

	hud = Hud.new()
	hud.player = player
	hud.grid = GameState.grid
	hud.find_hint = find_hint_at
	add_child(hud)
	hud.respawn_requested.connect(respawn)

	get_window().size_changed.connect(_fit_render_scale)
	_fit_render_scale()

	GameState.won.connect(_on_won)
	if stage > 0:
		_open_gate(false)
		for v in _villagers:
			(v as Node3D).visible = true
	_set_lake_frozen(not GameState.has_won)
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
	if glaciers.has(GameState.grid):
		GameState.save_game()
		GameState.grid = null
		GameState.grids = []
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
	_update_ghosts(delta)
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
					get_viewport().gui_release_focus()   # keys belong to the game now
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
func _on_ice_melted(at: Vector3, volume: float, value: float, field: IceField) -> void:
	var v := GameState.on_ice_melted(volume, value)
	if at.is_finite() and not _in_shed:   # (the numbers show through walls)
		_pending_water += v
		_pending_at = at + Vector3(0, 0.4, 0)
	if GameState.has_won or field != GameState.grid:
		return
	if field.remaining <= 0:
		GameState.check_win()
	elif field.fraction_left() < FINALE_FRACTION:
		# The last crumbs of the glacier collapse into slush on their own.
		hud.toast("💦 The last of %s collapses into slush!" % field.spec.name)
		field.melt_everything.call_deferred()


func _on_find_exposed(d: int) -> void:
	_reveal_find(d, true)
	GameState.discover(d)


func _place_finds() -> void:
	## Each find is frozen at a fixed spot at its layer's depth in its glacier,
	## the same every game: worked out on the fresh ice, before loading a save.
	for g in glaciers.size():
		var field: IceField = glaciers[g]
		var box: Array = field.spec.get("finds_box", [Vector2(field.origin.x, field.origin.z), Vector2(-field.origin.x, -field.origin.z)])
		var lo: Vector2 = box[0]
		var hi: Vector2 = box[1]
		var rng := RandomNumberGenerator.new()
		rng.seed = Balance.WORLD_SEED + 7 + 100 * g
		var spots: Array = []
		for d in Balance.finds_in(g):
			var want: int = Balance.DISCOVERIES[d].layer
			var spot := Vector3.INF
			for _t in 4000:
				var x := rng.randf_range(lo.x, hi.x)
				var z := rng.randf_range(lo.y, hi.y)
				var y := field.original_top(x, z) - (float(want) + 0.5) * field.layer_depth
				if y < 0.5:
					continue
				var p := Vector3(x, y, z)
				if field.density_at(p) < 0.95:
					continue   # in a crevasse or a house
				var crowded := false
				for o in spots:
					if (o as Vector3).distance_to(p) < 3.0:
						crowded = true
				for b in solids:
					if (b as AABB).grow(0.8).has_point(p):
						crowded = true
				if crowded:
					continue
				spot = p
				break
			if spot == Vector3.INF:
				push_warning("No spot for find %d" % d)
				continue
			spots.append(spot)
			_find_spots[d] = spot
			var marker := _make_find_marker(d)
			marker.position = spot
			marker.set_meta("glacier", g)
			add_child(marker)
			_find_markers[d] = marker
			_make_ghost(d, marker)


func _arm_finds() -> void:
	## After loading: finds already dug up lie where they were found; the rest
	## wait in the ice for it to melt around them.
	for d in _find_markers:
		var g := int(Balance.DISCOVERIES[d].glacier)
		var field: IceField = glaciers[g]
		if GameState.discovered[d] or g < GameState.stage or not field.watch_find(_find_spots[d], d):
			_reveal_find(d, false)
			if not GameState.discovered[d]:
				GameState.discover(d)


# A find still in the ice shows through as a dark shape once the ice around it
# gets thin, so you can see something's in there and go after it.
const GHOST_SHOW := 2.6        # starts to show through this much ice (metres)
const GHOST_FULL := 0.7        # darkest through this little
const GHOST_RANGE := 18.0      # only this close to you
const HINT_RADIUS := 2.8       # aiming at ice this close to a find gets you a hint

# How big each find model is (its longest side, in metres), in models/finds.glb
# order (Find0, Find1...; see find_model).
const FIND_SIZES := [0.6, 0.8, 0.7, 1.6, 2.6, 0.7, 1.3, 1.1, 0.8, 0.9, 0.8,
	1.3, 2.6, 1.0, 5.0, 3.0, 2.6, 1.6]   # the lake glacier's finds: skater .. the sun's lost ray


static var _lake_model: ArrayMesh


static func find_model(d: int) -> int:
	## Which FindN model in models/finds.glb is find d (the village's finds
	## were put in a new order when the glacier got deeper).
	return int(Balance.DISCOVERIES[d].get("model", d))


static func find_size(d: int) -> float:
	var m := find_model(d)
	return FIND_SIZES[m] if m < FIND_SIZES.size() else 0.8


static func find_mesh(d: int) -> Mesh:
	## The model of find d (art/blender/build_finds.py); past the end, the
	## glaciers themselves for the shed's last shelf slots: the village as a
	## tiny house, then the frozen lake.
	if d == Balance.DISCOVERIES.size() + 1:
		return _frozen_lake_model()
	if d >= Balance.DISCOVERIES.size():
		return Models.baked("house_0")
	return Models.baked("finds", "Find%d" % find_model(d))


static func _frozen_lake_model() -> ArrayMesh:
	## A little round of lake with a floe of ice on it.
	if _lake_model == null:
		var st := MeshKit.begin()
		MeshKit.cylinder(st, Vector3(0, 0.0, 0), Vector3(0, 0.05, 0), 0.5, 0.5, Color(0.55, 0.42, 0.3), 24)
		MeshKit.cylinder(st, Vector3(0, 0.05, 0), Vector3(0, 0.07, 0), 0.46, 0.46, Color(0.3, 0.72, 0.8), 24)
		MeshKit.ellipsoid(st, Vector3(-0.05, 0.08, 0.02), Vector3(0.3, 0.1, 0.24), Color(0.9, 0.96, 1.0))
		MeshKit.ellipsoid(st, Vector3(0.24, 0.07, -0.18), Vector3(0.1, 0.04, 0.08), Color(0.82, 0.93, 0.98))
		_lake_model = MeshKit.finish(st)
	return _lake_model


func _make_find_marker(d: int) -> Node3D:
	## A find in the ice: its model (resting 0.36 m below the marker's origin,
	## see _settle_finds), turning slowly once found, with its name above.
	var info: Dictionary = Balance.DISCOVERIES[d]
	var size := find_size(d)
	var m := Models.fitted(find_mesh(d), size, -0.36)
	m.rotation.y = PI + float(d) * 0.7
	m.visible = false
	var name_tag := Label3D.new()
	name_tag.text = "%s %s" % [info.icon, info.name]
	name_tag.font_size = 40
	name_tag.pixel_size = 0.0007
	name_tag.fixed_size = true
	name_tag.outline_size = 10
	var rarity := int(info.get("rarity", 0))
	UiTheme.sign_label(name_tag, UiTheme.CREAM if rarity == 0 else Balance.rarity(d).color.lightened(0.25))
	name_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	name_tag.position = Vector3(0, -0.36 + (find_mesh(d).get_aabb().size.y / _longest(find_mesh(d))) * size + 0.25, 0)
	m.add_child(name_tag)
	m.move_child(name_tag, 0)
	return m


static func _longest(mesh: Mesh) -> float:
	var s := mesh.get_aabb().size
	return maxf(s.x, maxf(s.y, s.z))


func _reveal_find(d: int, animate: bool) -> void:
	var m: Node3D = _find_markers.get(d)
	if m == null:
		return
	_drop_ghost(d)
	m.visible = true
	var rarity := int(Balance.DISCOVERIES[d].get("rarity", 0))
	var color: Color = Balance.rarity(d).color
	if rarity >= 4 and m.get_node_or_null("Glow") == null:
		# Legendary finds shine, even after you've found them.
		var glow := OmniLight3D.new()
		glow.name = "Glow"
		glow.light_color = color.lightened(0.3)
		glow.light_energy = 1.4
		glow.omni_range = 4.0
		glow.position = Vector3(0, 0.6, 0)
		m.add_child(glow)
	if animate:
		m.scale = Vector3.ONE * 0.2
		var tw := m.create_tween()
		tw.tween_property(m, "scale", Vector3.ONE * (1.45 + 0.1 * rarity), 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(m, "scale", Vector3.ONE, 0.35)
		var at: Vector3 = _find_spots.get(d, m.position)
		_shatter(at + Vector3(0, 0.3, 0), rarity, color)
		_flash(at + Vector3(0, 0.9, 0), rarity, color)


func _shatter(at: Vector3, rarity: int, color: Color) -> void:
	## Shards of ice burst out where a find breaks free (more for rarer finds).
	var p := CPUParticles3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.1, 0.1, 0.1)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.2
	bm.material = mat
	p.mesh = bm
	p.amount = 26 + 14 * rarity
	p.one_shot = true
	p.explosiveness = 1.0
	p.lifetime = 1.4
	p.direction = Vector3.UP
	p.spread = 75.0
	p.initial_velocity_min = 2.5
	p.initial_velocity_max = 6.0 + rarity
	p.gravity = Vector3(0, -12.0, 0)
	p.particle_flag_rotate_y = true
	p.angular_velocity_min = -300.0
	p.angular_velocity_max = 300.0
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.9
	var shrink := Curve.new()
	shrink.add_point(Vector2(0.0, 1.0))
	shrink.add_point(Vector2(0.7, 0.85))
	shrink.add_point(Vector2(1.0, 0.0))
	p.scale_amount_curve = shrink
	var tint := Gradient.new()   # mostly ice, some sparkle in the find's colour
	tint.set_color(0, Color(0.88, 0.96, 1.0))
	tint.set_color(1, Color(0.75, 0.9, 1.0) if rarity == 0 else color.lightened(0.2))
	tint.add_point(0.6, Color(0.7, 0.86, 0.98))
	p.color_initial_ramp = tint
	p.position = at
	add_child(p)
	p.emitting = true
	get_tree().create_timer(2.0).timeout.connect(p.queue_free)


func _flash(at: Vector3, rarity: int, color: Color) -> void:
	## A burst of light in the find's colour.
	var l := OmniLight3D.new()
	l.light_color = color.lerp(Color.WHITE, 0.3)
	l.omni_range = 5.0 + 1.5 * rarity
	l.light_energy = 0.0
	l.position = at
	add_child(l)
	var tw := l.create_tween()
	tw.tween_property(l, "light_energy", 3.0 + rarity, 0.08)
	tw.tween_property(l, "light_energy", 0.0, 0.9 + 0.25 * rarity).set_ease(Tween.EASE_IN)
	tw.tween_callback(l.queue_free)


func _make_ghost(d: int, marker: Node3D) -> void:
	## The find's shape, drawn through the ice (no depth test) and faded in
	## by _update_ghosts once the ice around it gets thin. Dark for most
	## finds; legendary ones glow.
	var g := Models.fitted(find_mesh(d), find_size(d), -0.36)
	g.position = marker.position
	g.rotation.y = marker.rotation.y
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = true
	mat.render_priority = -1
	var rarity := int(Balance.DISCOVERIES[d].get("rarity", 0))
	if rarity >= 4:
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mat.albedo_color = Color(Balance.rarity(d).color, 0.0)
	else:
		mat.albedo_color = Color(0.02, 0.08, 0.18, 0.0).lerp(Color(Balance.rarity(d).color.darkened(0.6), 0.0), 0.35 * rarity / 3.0)
	for c in g.get_children():
		if c is GeometryInstance3D:
			(c as GeometryInstance3D).material_override = mat
			(c as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	g.visible = false
	add_child(g)
	_ghosts[d] = {"node": g, "mat": mat, "alpha": 0.0, "target": 0.0}


func _drop_ghost(d: int) -> void:
	if _ghosts.has(d):
		(_ghosts[d].node as Node3D).queue_free()
		_ghosts.erase(d)


func _update_ghosts(delta: float) -> void:
	## Fade each find's shadow in or out with how much ice is left around it.
	## One find's ice gets checked per frame, so it never costs much.
	if _ghosts.is_empty():
		return
	var keys := _ghosts.keys()
	_ghost_i = (_ghost_i + 1) % keys.size()
	_recheck_ghost(keys[_ghost_i])
	var t := Time.get_ticks_msec() * 0.001
	for d in _ghosts:
		var gh: Dictionary = _ghosts[d]
		var node: Node3D = gh.node
		gh.alpha = move_toward(float(gh.alpha), float(gh.target), delta * 0.8)
		node.visible = gh.alpha > 0.01
		if node.visible:
			var mat: StandardMaterial3D = gh.mat
			var c := mat.albedo_color
			c.a = gh.alpha * 0.55 * (0.82 + 0.18 * sin(t * 2.6 + float(d)))
			mat.albedo_color = c


func _recheck_ghost(d: int) -> void:
	var gh: Dictionary = _ghosts[d]
	var target := 0.0
	var dist := (gh.node as Node3D).position.distance_to(player.global_position + Vector3(0, 1.5, 0))
	var g := int(Balance.DISCOVERIES[d].glacier)
	if dist < GHOST_RANGE and g <= GameState.stage and _find_spots.has(d):
		var cover := _ice_cover(_find_spots[d] + Vector3(0, 0.3, 0), glaciers[g])
		target = clampf((GHOST_SHOW - cover) / (GHOST_SHOW - GHOST_FULL), 0.0, 1.0)
		target *= clampf((GHOST_RANGE - dist) / 5.0, 0.0, 1.0)
	gh.target = target


func _ice_cover(p: Vector3, field: IceField) -> float:
	## Roughly how much ice there is between p and open air (metres, up to 3),
	## looking up and sideways (down is the valley floor).
	if _cover_dirs.is_empty():
		for x in [-1, 0, 1]:
			for y in [0, 1]:
				for z in [-1, 0, 1]:
					if x != 0 or y != 0 or z != 0:
						_cover_dirs.append(Vector3(x, y, z).normalized())
	var best := 3.0
	for dir in _cover_dirs:
		var step := 0.25
		while step < best:
			if field.density_at(p + dir * step) < 0.5:
				best = step
				break
			step += 0.25
	return best


func find_hint_at(at: Vector3) -> int:
	## A find still frozen near this spot on the ice (for the HUD), or -1.
	var best := -1
	var best_d := HINT_RADIUS
	for d in _ghosts:
		if not _find_spots.has(d) or int(Balance.DISCOVERIES[d].glacier) > GameState.stage:
			continue
		var dist: float = (_find_spots[d] as Vector3).distance_to(at)
		if dist < best_d:
			best_d = dist
			best = d
	return best


func _settle_finds(delta: float) -> void:
	## Found things drop to whatever is under them as the ice melts away.
	## Their name tags only show up close.
	for d in _find_markers:
		var m: Node3D = _find_markers[d]
		if not m.visible:
			continue
		m.rotation.y += delta * 0.5   # turning slowly, to show it off
		(m.get_child(0) as Label3D).visible = m.position.distance_squared_to(player.position) < 49.0
		var rest := _floor_under(m.position, glaciers[int(m.get_meta("glacier", 0))]) + 0.36
		if m.position.y > rest + 0.001:
			m.position.y = maxf(rest, m.position.y - delta * 5.0)


func _floor_under(p: Vector3, field: IceField) -> float:
	var floor_y := field.floor_below(p)
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
		UiTheme.sign_label(l, Color(0.75, 0.92, 1.0))
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
		var node: Node3D = f.node
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
			if GameState.melted_volume > 0.0:
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


func _on_stage_changed(stage: int) -> void:
	## A glacier is gone. The first time: the village is free, the gate to the
	## frozen lake opens, and your helpers retire to the village.
	var field: IceField = glaciers[stage]
	field.set_collide(true)
	player.grid = field
	helpers.retire()
	helpers.grid = field
	hud.grid = field
	_set_bounds()
	_open_gate(true)
	for v in _villagers:
		(v as Node3D).visible = true
	_update_slow()
	hud.show_stage_done(stage)


func _on_won() -> void:
	for v in _villagers:
		(v as Node3D).visible = true
	_set_lake_frozen(false)
	_update_slow()
	hud.show_ending()


# =====================================================================================
# Where you can walk, the fence in front of the lake
# =====================================================================================
func _set_bounds() -> void:
	## Before the village is free: the valley floor, up to the fence. After:
	## the whole valley floor and the lake.
	var v: Dictionary = level.valley
	if GameState.stage == 0:
		player.bounds_min = Vector3(-(float(v.half_width) - 1.5), -1.0, float(v.back_z) + 1.5)
		player.bounds_max = Vector3(float(v.half_width) - 1.5, 80.0, float(v.gate_z) - 0.45)
		player.walkable = Callable()
	else:
		var lk: Array = v.lake
		player.bounds_min = Vector3(-200.0, -1.0, float(v.back_z) + 1.5)
		player.bounds_max = Vector3(200.0, 80.0, float(lk[1]) + float(lk[3]) - 1.5)
		player.walkable = walkable


func walkable(x: float, z: float) -> bool:
	## On the valley floor or the lake, not up in the mountains (or Kevin's hollow).
	return Scenery.floor_distance(level.valley, x, z, Vector2.INF, Vector2.ZERO) < -1.5


func _build_fence() -> void:
	## A wooden fence right across the valley in front of the lake, with a gate
	## in the middle that stays locked until the village is free.
	var v: Dictionary = level.valley
	var z: float = v.gate_z
	var half := float(v.half_width) + 2.0   # into the foot of the mountains on both sides
	var gap := 1.7                          # half the gate's width
	var wood := Color(0.52, 0.37, 0.24)
	var dark := wood.darkened(0.25)
	var x := -half
	while x <= half + 0.01:
		if absf(x) > gap + 0.3:
			_box(Vector3(0.16, 1.35, 0.16), Vector3(x, 0.675, z), dark)
		x += 2.5
	for side in [-1.0, 1.0]:
		var x0: float = side * (gap + 0.15)
		var x1: float = side * half
		var mid := (x0 + x1) * 0.5
		var len := absf(x1 - x0)
		for y in [0.5, 1.0]:
			_box(Vector3(len, 0.11, 0.06), Vector3(mid, y, z + 0.09), wood)
		# Gate posts, taller, with a cap.
		_box(Vector3(0.26, 1.8, 0.26), Vector3(side * (gap + 0.13), 0.9, z), dark)
		_box(Vector3(0.34, 0.08, 0.34), Vector3(side * (gap + 0.13), 1.84, z), wood)
		var lo := minf(x0, x1)
		var fence := AABB(Vector3(lo, 0.0, z - 0.2), Vector3(len, 1.4, 0.4))
		solids.append(fence)
	# The gate: one leaf hinged on the left post.
	_gate = Node3D.new()
	_gate.position = Vector3(-gap, 0.0, z)
	add_child(_gate)
	var w := gap * 2.0
	for y in [0.35, 0.8, 1.25]:
		_box(Vector3(w, 0.12, 0.07), Vector3(w * 0.5, y, 0.0), wood, _gate)
	for gx in [0.08, w * 0.5, w - 0.08]:
		_box(Vector3(0.1, 1.2, 0.08), Vector3(gx, 0.8, 0.02), wood, _gate)
	var brace := _box(Vector3(sqrt(w * w + 0.81), 0.1, 0.06), Vector3(w * 0.5, 0.8, -0.03), dark, _gate)
	brace.rotation.z = atan2(0.9, w)
	var lock := _box(Vector3(0.16, 0.2, 0.1), Vector3(w - 0.25, 0.8, 0.09), Color(0.75, 0.62, 0.25), _gate)
	lock.name = "Lock"
	var body := StaticBody3D.new()
	body.collision_layer = Player.WORLD_LAYER
	body.collision_mask = 0
	_gate_shape = CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(w, 1.5, 0.3)
	_gate_shape.shape = bs
	_gate_shape.position = Vector3(0.0, 0.75, z)
	body.add_child(_gate_shape)
	add_child(body)
	# A sign on the valley side, by the gate.
	var sign_x := gap + 1.9
	_box(Vector3(0.1, 1.75, 0.1), Vector3(sign_x - 0.8, 0.875, z - 0.25), dark)
	_box(Vector3(0.1, 1.75, 0.1), Vector3(sign_x + 0.8, 0.875, z - 0.25), dark)
	_box(Vector3(1.95, 0.86, 0.06), Vector3(sign_x, 1.35, z - 0.3), Color(0.93, 0.88, 0.76))
	_gate_sign = Label3D.new()
	_gate_sign.font = UiTheme.display_font()
	_gate_sign.font_size = 44
	_gate_sign.pixel_size = 0.0037
	_gate_sign.modulate = Color(0.3, 0.19, 0.11)
	_gate_sign.outline_size = 0
	_gate_sign.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_gate_sign.position = Vector3(sign_x, 1.35, z - 0.34)
	_gate_sign.rotation.y = PI
	add_child(_gate_sign)
	_set_gate_sign(false)


func _set_gate_sign(open: bool) -> void:
	if open:
		_gate_sign.text = "THE FROZEN LAKE\nThe gate's open.\nGo melt it!"
	else:
		_gate_sign.text = "🔒 THE FROZEN LAKE\nClosed until the\nvillage is free"


func _open_gate(animate: bool) -> void:
	_gate_shape.disabled = true
	_set_gate_sign(true)
	var lock := _gate.get_node_or_null("Lock")
	if lock != null:
		lock.visible = false
	var open_angle := deg_to_rad(-105.0)   # swung in toward the lake
	if animate:
		var tw := _gate.create_tween()
		tw.tween_interval(1.2)
		tw.tween_property(_gate, "rotation:y", open_angle, 2.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		_gate.rotation.y = open_angle


func _set_lake_frozen(frozen: bool) -> void:
	## Until the very end the lake is frozen over: it only thaws when the last
	## glacier is gone.
	if _lake_water == null:
		return
	if frozen:
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.82, 0.9, 0.96)
		m.albedo_texture = _frozen_lake_texture()
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		m.uv1_scale = Vector3(0.05, 0.05, 1.0)
		m.uv1_triplanar = true
		m.roughness = 0.35
		_lake_water.material_override = m
	else:
		_lake_water.material_override = _water_mat


func _frozen_lake_texture() -> ImageTexture:
	## Soft grey blotches for the frozen lake (the ice's detail texture has a
	## different noise in each colour channel, which shows as rainbows).
	var src := IceField.detail_texture(int(level.seed)).get_image()
	src.clear_mipmaps()
	var n := src.get_width()
	var data := src.get_data()   # RGB8
	var grey := PackedByteArray()
	grey.resize(n * n)
	for i in n * n:
		grey[i] = int(200.0 + (float(data[i * 3]) * 0.35 + float(data[i * 3 + 1]) * 0.65 - 128.0) * 0.4)
	var img := Image.create_from_data(n, n, false, Image.FORMAT_L8, grey)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


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


func _box(size: Vector3, center: Vector3, c: Color, parent: Node = self) -> MeshInstance3D:
	var bm := BoxMesh.new()
	bm.size = size
	return _mesh(bm, center, c, parent)


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
	_lake_water = Scenery.lake(level)
	_water_mat = _lake_water.material_override
	add_child(_lake_water)
	var stream := Scenery.stream(level)
	if stream != null:
		add_child(stream)

	# A few boulders for scale.
	var spots := [Vector3(-14, 0, 13), Vector3(-5, 0, 19), Vector3(19.2, 0, 5.0), Vector3(-19, 0, 2),
			Vector3(21, 0, -6), Vector3(4, 0, 19.5), Vector3(-20, 0, 9), Vector3(19.5, 0, 15)]
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
	## The buildings are Blender models (art/blender/build_village.py); house i
	## is models/house_i.glb, made to fit HOUSES[i]'s footprint.
	var carve: Array = []
	for i in HOUSES.size():
		var hdef: Array = HOUSES[i]
		var x := float(hdef[0])
		var z := float(hdef[1])
		var w := float(hdef[2])
		var d := float(hdef[3])
		_model("house_%d" % i, Vector3(x + w * 0.5, 0.0, z + d * 0.5))
		var box := AABB(Vector3(x, 0, z), Vector3(w, HOUSE_WALL + HOUSE_ROOF, d))
		carve.append(box)
		solids.append(box)
	# The church, with an onion-dome steeple tall enough to poke out of the top
	# of the glacier. The model's origin is the nave's footprint corner.
	var cx := float(CHURCH[0])
	var cz := float(CHURCH[1])
	var cw := float(CHURCH[2])
	var cd := float(CHURCH[3])
	_model("church", Vector3(cx, 0.0, cz))
	var nave := AABB(Vector3(cx, 0, cz), Vector3(cw, CHURCH_WALL + CHURCH_ROOF, cd))
	carve.append(nave)
	solids.append(nave)
	var tx := float(TOWER[0])
	var tz := float(TOWER[1])
	var tw := float(TOWER[2])
	var td := float(TOWER[3])
	var tower := AABB(Vector3(tx, 0, tz), Vector3(tw, TOWER_TOP, td))
	carve.append(tower)
	solids.append(tower)
	solids.append(AABB(Vector3(tx + tw * 0.5 - 0.5, TOWER_TOP, tz + td * 0.5 - 0.5), Vector3(1.0, SPIRE * 0.6, 1.0)))
	# A well in the square.
	_model("well", Vector3(1.5, 0.0, -19.5))
	solids.append(AABB(Vector3(0.8, 0, -20.2), Vector3(1.4, 0.9, 1.4)))
	return carve


func _model(file: String, pos: Vector3) -> Node3D:
	var n := Models.instance(file)
	n.position = pos
	add_child(n)
	return n


func _build_shed() -> void:
	## The tool shed by the path: a red cabin you walk into to shop (see Shed).
	shed = Shed.new()
	add_child(shed)
	shed.build(IceField.detail_texture(int(level.seed)))
	# Woodpile, rain barrel, crates, lantern and stovepipe round the outside
	# (art/blender/build_shed_props.py, in world coordinates).
	_model("shed_props", Vector3.ZERO)
	solids.append(AABB(Vector3(12.4, 0, 15.2), Vector3(2.6, 1.3, 0.75)))   # woodpile
	solids.append(AABB(Vector3(8.9, 0, 15.4), Vector3(0.7, 0.85, 0.7)))    # barrel
	solids.append(AABB(Vector3(7.8, 0, 8.5), Vector3(0.75, 1.1, 1.5)))     # crates


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
				or Scenery.near_stream(level, x, z, 2.0) or Vector2(x - SPAWN.x, z - SPAWN.z).length() < 4.0 \
				or absf(z - float(v.gate_z)) < 1.6:
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
			x = rng.randf_range(-16.5, 16.5)
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
		var l := Models.baked_instance(Models.baked("nature", FLOWERS[rng.randi() % FLOWERS.size()]))
		l.position = Vector3(x, 0.0, z)
		l.rotation.y = rng.randf() * TAU
		l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		l.visible = false
		add_child(l)
		_flowers.append({"node": l, "x": x, "z": z, "inside": inside, "threshold": rng.randf_range(0.05, 0.95)})


func _build_villagers() -> void:
	## The villagers who come out to celebrate when the ice is gone
	## (art/blender/build_characters.py). They hop on the spot, facing the valley.
	var spots := [Vector3(-7.5, 0.0, -16.6), Vector3(-2.5, 0.0, -18.3), Vector3(7.0, 0.0, -17.4),
		Vector3(1.0, 0.0, -9.2), Vector3(-6.5, 0.0, -10.5), Vector3(4.5, 0.0, -10.8),
		Vector3(3.2, 0.0, -19.0), Vector3(-0.8, 0.0, -20.5)]
	for i in VILLAGERS.size():
		var v := Node3D.new()
		var mi := Models.baked_instance(Models.baked("characters", VILLAGERS[i]))
		v.add_child(mi)
		v.position = spots[i]
		v.rotation.y = PI + (float(i % 3) - 1.0) * 0.35   # face +Z, toward you, give or take
		v.visible = false
		add_child(v)
		_villagers.append(v)
		var tw := mi.create_tween().set_loops()
		tw.tween_property(mi, "position:y", 0.22, 0.35 + 0.05 * i).set_trans(Tween.TRANS_SINE)
		tw.tween_property(mi, "position:y", 0.0, 0.35 + 0.05 * i).set_trans(Tween.TRANS_SINE)