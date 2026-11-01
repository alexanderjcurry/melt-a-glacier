class_name Player
extends CharacterBody3D
## First-person walker: a capsule on Godot's physics, so it slides smoothly
## over the carved ice. Hold JUMP to fly with the jetpack. Carries the heat
## tool: aim with the crosshair, hold to melt what you're looking at.

const RADIUS := 0.3
const HEIGHT := 1.7
const EYE := 1.55
const GRAVITY := 18.0
const STEP_HEIGHT := 0.5      # walks up ledges this high without jumping
const WORLD_LAYER := 1        # ground, houses, the shed, rocks, trees
const ICE_LAYER := 2

var grid: IceField
var bounds_min := Vector3(-21.0, -1.0, -27.0)
var bounds_max := Vector3(21.0, 80.0, 20.0)

# Set by the controls every frame.
var move_input := Vector2.ZERO      # x = strafe right, y = forward
var melting := false
var jet_held := false               # JUMP held down: the jetpack fires in the air
var input_enabled := true

var on_floor := false
var fuel := 1.0                     # jetpack tank, 0..1
var jetting := false
var yaw := 0.0
var pitch := -0.15
var camera: Camera3D
var target: Dictionary = {"hit": false}   # what the crosshair points at: {hit, pos, normal, dist}
var heat := 0.0                     # 0..1, how hard the tool is working (the ice glows)

var _shape: CollisionShape3D
var _head: Node3D
var _cam_offset_y := 0.0            # eases the camera after stepping up a ledge
var _bob_t := 0.0
var _tool_holder: Node3D
var _tool_model: Node3D
var _shown_tool := -1
var _shown_gold := false
var _flame: CPUParticles3D
var _steam: CPUParticles3D
var _drips: CPUParticles3D
var _jet: CPUParticles3D
var _kick := 0.0
var _hold_t := 0.0
var _heat_pos := Vector3(0, -100, 0)


func _ready() -> void:
	collision_layer = 4
	collision_mask = WORLD_LAYER | ICE_LAYER
	floor_max_angle = deg_to_rad(50.0)
	floor_snap_length = 0.35
	floor_constant_speed = true
	safe_margin = 0.02
	var capsule := CapsuleShape3D.new()
	capsule.radius = RADIUS
	capsule.height = HEIGHT
	_shape = CollisionShape3D.new()
	_shape.shape = capsule
	_shape.position = Vector3(0, HEIGHT * 0.5, 0)
	add_child(_shape)

	_head = Node3D.new()
	_head.position = Vector3(0, EYE, 0)
	add_child(_head)
	camera = Camera3D.new()
	camera.fov = 72.0
	camera.near = 0.08
	camera.far = 500.0
	camera.current = true
	_head.add_child(camera)

	_tool_holder = Node3D.new()
	_tool_holder.position = Vector3(0.24, -0.2, -0.45)
	camera.add_child(_tool_holder)

	_flame = _make_particles(Color(1.0, 0.7, 0.25, 1.0), Color(1.0, 0.3, 0.05, 0.0), 0.22, 70)
	_flame.direction = Vector3(0, 0, -1)
	_flame.spread = 7.0
	_flame.gravity = Vector3(0, 1.0, 0)
	_flame.initial_velocity_min = 9.0
	_flame.initial_velocity_max = 12.0
	_flame.lifetime = 0.35
	_flame.position = Vector3(0.24, -0.185, -0.64)
	_flame.local_coords = false
	camera.add_child(_flame)

	_steam = _make_particles(Color(1, 1, 1, 0.75), Color(1, 1, 1, 0.0), 0.35, 40)
	_steam.direction = Vector3(0, 1, 0)
	_steam.spread = 35.0
	_steam.gravity = Vector3(0, 2.5, 0)
	_steam.initial_velocity_min = 0.8
	_steam.initial_velocity_max = 2.0
	_steam.lifetime = 1.1
	_steam.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_steam.emission_sphere_radius = 0.35
	_steam.local_coords = false
	add_child(_steam)
	_steam.top_level = true

	# Meltwater dripping off where the heat lands.
	_drips = _make_particles(Color(0.75, 0.9, 1.0, 0.9), Color(0.6, 0.85, 1.0, 0.0), 0.07, 24)
	_drips.direction = Vector3(0, -1, 0)
	_drips.spread = 25.0
	_drips.gravity = Vector3(0, -9.0, 0)
	_drips.initial_velocity_min = 0.2
	_drips.initial_velocity_max = 1.0
	_drips.lifetime = 0.7
	_drips.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_drips.emission_sphere_radius = 0.4
	_drips.local_coords = false
	add_child(_drips)
	_drips.top_level = true

	_jet = _make_particles(Color(1.0, 0.75, 0.35, 0.9), Color(0.7, 0.7, 0.75, 0.0), 0.3, 40)
	_jet.direction = Vector3(0, -1, 0)
	_jet.spread = 12.0
	_jet.gravity = Vector3.ZERO
	_jet.initial_velocity_min = 4.0
	_jet.initial_velocity_max = 6.0
	_jet.lifetime = 0.35
	_jet.position = Vector3(0, 0.55, 0.28)   # a backpack nozzle: visible when you look down
	_jet.local_coords = false
	add_child(_jet)

	rotation.y = yaw
	_head.rotation.x = pitch


func _make_particles(c0: Color, c1: Color, size: float, amount: int) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.emitting = false
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.billboard_keep_scale = true   # particle scale (and hidden, zero-size particles) need this
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = UiTheme.soft_dot()
	quad.material = mat
	p.mesh = quad
	var ramp := Gradient.new()
	ramp.set_color(0, c0)
	ramp.set_color(1, c1)
	p.color_ramp = ramp
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.4
	return p


# --- Looking ---------------------------------------------------------------------------
func add_look(d: Vector2) -> void:
	## d in radians: x turns left/right, y tilts up/down.
	yaw -= d.x
	pitch = clampf(pitch - d.y, -1.45, 1.45)
	rotation.y = yaw
	_head.rotation.x = pitch


func set_view(p_yaw: float, p_pitch: float) -> void:
	yaw = p_yaw
	pitch = clampf(p_pitch, -1.45, 1.45)
	rotation.y = yaw
	if _head != null:
		_head.rotation.x = pitch


func aim_dir() -> Vector3:
	return -camera.global_transform.basis.z


# --- Moving -----------------------------------------------------------------------------
func jump() -> void:
	if on_floor and input_enabled:
		velocity.y = Balance.JUMP_VELOCITY
		on_floor = false


func respawn(at: Vector3, p_yaw: float) -> void:
	position = at
	velocity = Vector3.ZERO
	fuel = 1.0
	set_view(p_yaw, -0.12)
	unstick()


func _physics_process(delta: float) -> void:
	_move(delta)
	_update_tool(delta)


func _process(delta: float) -> void:
	_animate_camera(minf(delta, 0.05))


func _move(delta: float) -> void:
	var speed := Balance.WALK_SPEED * GameState.move_speed_mult()
	var turn := Basis(Vector3.UP, yaw)
	var mv := move_input.limit_length(1.0) if input_enabled else Vector2.ZERO
	var wish := turn * Vector3(mv.x, 0.0, -mv.y) * speed
	velocity.x = wish.x
	velocity.z = wish.z
	if not on_floor:
		velocity.y -= GRAVITY * delta
	_update_jetpack(delta)
	if on_floor and mv.length() > 0.1 and _step_up(Vector3(wish.x, 0.0, wish.z) * delta):
		velocity.x = 0.0
		velocity.z = 0.0
	_slide(delta)
	velocity.x = wish.x
	velocity.z = wish.z
	on_floor = is_on_floor()
	if on_floor and velocity.y < 0.0:
		velocity.y = 0.0
	# Stay in the valley.
	var p := position
	p.x = clampf(p.x, bounds_min.x + RADIUS, bounds_max.x - RADIUS)
	p.z = clampf(p.z, bounds_min.z + RADIUS, bounds_max.z - RADIUS)
	if p.y < -1.0:
		p.y = 0.05   # fell through something somehow: back onto the ground
		velocity = Vector3.ZERO
	position = p
	if on_floor and mv.length() > 0.1:
		_bob_t += delta * speed * 2.2


func _slide(delta: float) -> void:
	## move_and_slide() for exactly `delta` seconds. Godot uses the frame's own
	## delta, which only matches when we're called from _physics_process.
	var engine_dt := get_physics_process_delta_time() if Engine.is_in_physics_frame() else get_process_delta_time()
	if engine_dt <= 0.0 or absf(engine_dt - delta) < 0.00001:
		move_and_slide()
		return
	var k := delta / engine_dt
	velocity *= k
	move_and_slide()
	velocity /= k


func _step_up(motion: Vector3) -> bool:
	## Walking into a low ledge: hop up onto it instead of stopping.
	var col := KinematicCollision3D.new()
	if not test_move(global_transform, motion, col):
		return false
	if col.get_normal().y > 0.65:
		return false   # just a slope; move_and_slide walks up those
	var up := Vector3(0, STEP_HEIGHT, 0)
	if test_move(global_transform, up):
		return false   # no headroom
	var raised := global_transform.translated(up)
	if test_move(raised, motion):
		return false   # too tall to step onto
	var down := KinematicCollision3D.new()
	if not test_move(raised.translated(motion), -up, down):
		return false   # nothing to stand on
	var rise := STEP_HEIGHT - down.get_travel().length()
	if rise <= 0.03:
		return false
	global_position += motion + Vector3(0, rise + 0.01, 0)
	_cam_offset_y -= rise
	return true


func _update_jetpack(delta: float) -> void:
	## Hold JUMP: after a short delay the jetpack pushes you up, as long as
	## there's fuel. Landing on anything refills the tank.
	var held := jet_held and input_enabled
	_hold_t = _hold_t + delta if held else 0.0
	jetting = false
	if on_floor:
		fuel = minf(1.0, fuel + delta * Balance.JET_REFILL)
	elif held and fuel > 0.0 and _hold_t >= Balance.JET_HOLD_DELAY and position.y < Balance.JET_CEILING:
		jetting = true
		var v := velocity.y + Balance.JET_ACCEL * delta
		velocity.y = minf(v, maxf(Balance.JET_MAX_RISE, velocity.y))
		fuel = maxf(0.0, fuel - delta / GameState.jet_fuel_seconds())
	_jet.emitting = jetting


func collides(p: Vector3) -> bool:
	## Would the player's body overlap anything standing at p?
	if p.x - RADIUS < bounds_min.x or p.x + RADIUS > bounds_max.x \
			or p.z - RADIUS < bounds_min.z or p.z + RADIUS > bounds_max.z:
		return true
	if grid != null:
		for h in [0.3, 0.85, 1.4]:
			if grid.solid_at(p + Vector3(0, h, 0)):
				return true
	if not is_inside_tree():
		return false
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = _shape.shape
	q.transform = Transform3D(Basis(), p + Vector3(0, HEIGHT * 0.5 + 0.06, 0))
	q.collision_mask = WORLD_LAYER | ICE_LAYER
	q.exclude = [get_rid()]
	return not get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty()


func unstick() -> void:
	## If melting or loading ever leaves us inside something, pop up on top.
	var guard := 0
	while collides(position) and guard < 120:
		position.y += 0.25
		guard += 1
	on_floor = false


func _animate_camera(delta: float) -> void:
	_cam_offset_y = lerpf(_cam_offset_y, 0.0, minf(1.0, delta * 12.0))
	var bob := sin(_bob_t) * 0.04
	_head.position.y = EYE + _cam_offset_y + bob
	_kick = lerpf(_kick, 0.0, minf(1.0, delta * 10.0))
	_tool_holder.position = Vector3(0.24 + sin(_bob_t * 0.5) * 0.01, -0.2 + absf(cos(_bob_t * 0.5)) * 0.008, -0.45 + _kick)


# --- The tool -------------------------------------------------------------------------------
func ray(dist: float) -> Dictionary:
	## What's straight ahead of the crosshair, if it's ice: {hit, pos, normal, dist}.
	if camera == null or not is_inside_tree() or grid == null:
		return {"hit": false}
	var from := camera.global_position
	var q := PhysicsRayQueryParameters3D.create(from, from + aim_dir() * dist, WORLD_LAYER | ICE_LAYER, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty() or hit.collider != grid.body:
		return {"hit": false}
	var p: Vector3 = hit.position
	return {"hit": true, "pos": p, "normal": hit.normal, "dist": from.distance_to(p)}


func _update_tool(delta: float) -> void:
	if _shown_tool != GameState.tool_index or _shown_gold != GameState.golden_equipped:
		_build_tool_model()
	var reach := GameState.tool_range()
	target = ray(reach)
	var active := melting and input_enabled and not GameState.has_won
	_flame.emitting = active
	if active:
		var dist: float = target.dist if target.hit else reach
		_flame.lifetime = clampf(dist / 10.5, 0.06, 0.6)
		var aim_point: Vector3 = target.pos if target.hit else camera.global_position + aim_dir() * reach
		if _flame.global_position.distance_to(aim_point) > 0.3:
			_flame.look_at(aim_point)
		_kick = 0.02 + randf() * 0.015
	var working: bool = active and target.hit
	if working:
		var normal: Vector3 = target.normal
		grid.damage_sphere(target.pos - normal * 0.2, GameState.tool_radius(), GameState.tool_power() * delta)
		_steam.global_position = target.pos + normal * 0.2
		_drips.global_position = target.pos + normal * 0.1
		_heat_pos = target.pos
	_steam.emitting = working
	_drips.emitting = working
	heat = move_toward(heat, 1.0 if working else 0.0, delta * (5.0 if working else 2.0))
	if grid != null:
		grid.set_heat(_heat_pos, heat)


func _build_tool_model() -> void:
	_shown_tool = GameState.tool_index
	_shown_gold = GameState.golden_equipped
	if _tool_model != null:
		_tool_model.queue_free()
	_tool_model = Node3D.new()
	_tool_model.scale = Vector3.ONE * (0.6 + 0.04 * float(_shown_tool))   # better tools are a bit chunkier
	_tool_holder.add_child(_tool_model)
	var t: Dictionary = GameState.tool_def()
	var col: Color = Color(1.0, 0.8, 0.25) if (_shown_gold and _shown_tool == 0) else t.color
	var tier := float(_shown_tool)
	# Barrel pointing forward (a cylinder's +Y turned to -Z).
	var barrel := _part(_cyl(0.052 + 0.004 * tier, 0.066 + 0.004 * tier, 0.26), col)
	barrel.rotation.x = -PI / 2.0
	barrel.position = Vector3(0, 0, -0.03)
	var back := _part(_cyl(0.07, 0.07, 0.04), col.darkened(0.25))
	back.rotation.x = -PI / 2.0
	back.position = Vector3(0, 0, 0.11)
	var grille := _part(_cyl(0.055, 0.055, 0.01), Color(0.15, 0.15, 0.18))
	grille.rotation.x = -PI / 2.0
	grille.position = Vector3(0, 0, 0.133)
	var handle := _part(_box(Vector3(0.05, 0.18, 0.065)), col.darkened(0.35))
	handle.position = Vector3(0, -0.11, 0.05)
	handle.rotation.x = 0.28
	var nozzle := _part(_cyl(0.028 + 0.01 * tier, 0.042 + 0.008 * tier, 0.1), Color(0.22, 0.22, 0.26))
	nozzle.rotation.x = -PI / 2.0
	nozzle.position = Vector3(0, 0, -0.2)
	if _shown_tool == Balance.TOOLS.size() - 1:
		# The orbital mirror "remote": a dish on top.
		var dish := _part(_cyl(0.12, 0.02, 0.05), Color(0.9, 0.92, 1.0))
		dish.position = Vector3(0, 0.1, 0.02)


func _part(mesh: Mesh, c: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _solid(c)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_tool_model.add_child(mi)
	return mi


func _cyl(top: float, bottom: float, height: float) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = top
	m.bottom_radius = bottom
	m.height = height
	m.radial_segments = 16
	m.rings = 1
	return m


func _box(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m


func _solid(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.5
	return m
