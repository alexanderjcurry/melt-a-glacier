class_name Player
extends Node3D
## First-person walker with simple voxel collision (no physics engine), plus the
## heat tool: aim with the crosshair, hold to melt what you're looking at.

const RADIUS := 0.3
const HEIGHT := 1.7
const EYE := 1.55
const STEP_UP := 1.05
const AIR_STEP_UP := 0.8      # at the top of a jump you can pull yourself up a 2-block wall
const GRAVITY := 18.0

var grid: IceGrid
var solids: Array[AABB] = []        # houses, the shed: things you can't walk through
var bounds_min := Vector3(-21.0, -1.0, -27.0)
var bounds_max := Vector3(21.0, 80.0, 20.0)

# Set by the controls every frame.
var move_input := Vector2.ZERO      # x = strafe right, y = forward
var melting := false
var input_enabled := true

var velocity := Vector3.ZERO
var on_floor := false
var yaw := 0.0
var pitch := -0.15
var camera: Camera3D
var target: Dictionary = {"hit": false}   # what the crosshair points at

var _head: Node3D
var _cam_offset_y := 0.0            # eases the camera after stepping up a block
var _bob_t := 0.0
var _tool_holder: Node3D
var _tool_model: Node3D
var _shown_tool := -1
var _shown_gold := false
var _flame: CPUParticles3D
var _steam: CPUParticles3D
var _kick := 0.0


func _ready() -> void:
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


func jump() -> void:
	if on_floor and input_enabled:
		velocity.y = Balance.JUMP_VELOCITY
		on_floor = false


func aim_dir() -> Vector3:
	return -camera.global_transform.basis.z


# --- Frame update ------------------------------------------------------------------------
func _process(delta: float) -> void:
	delta = minf(delta, 0.05)
	_move(delta)
	_animate_camera(delta)
	_update_tool(delta)


func _move(delta: float) -> void:
	var speed := Balance.WALK_SPEED * GameState.move_speed_mult()
	var turn := Basis(Vector3.UP, yaw)
	var fwd := turn * Vector3(0, 0, -1)
	var right := turn * Vector3(1, 0, 0)
	var mv := move_input.limit_length(1.0) if input_enabled else Vector2.ZERO
	var wish := (fwd * mv.y + right * mv.x) * speed
	velocity.x = wish.x
	velocity.z = wish.z
	velocity.y -= GRAVITY * delta
	_move_horizontal(Vector3(velocity.x * delta, 0.0, 0.0))
	_move_horizontal(Vector3(0.0, 0.0, velocity.z * delta))
	_move_vertical(velocity.y * delta)
	if on_floor and mv.length() > 0.1:
		_bob_t += delta * speed * 2.2


func _move_horizontal(d: Vector3) -> void:
	if d.length_squared() == 0.0:
		return
	var np := position + d
	if not collides(np):
		position = np
		return
	# Auto-climb up to one block, like walking up stairs (a bit less mid-jump).
	var lifts := [0.35, 0.7, STEP_UP] if on_floor else [0.3, 0.55, AIR_STEP_UP]
	for h in lifts:
		var lift := Vector3(0.0, h, 0.0)
		if not collides(np + lift) and not collides(position + lift):
			position = np + lift
			_cam_offset_y -= h
			return


func _move_vertical(dy: float) -> void:
	var np := position + Vector3(0.0, dy, 0.0)
	if np.y <= 0.0:
		np.y = 0.0
		position = np
		velocity.y = 0.0
		on_floor = true
		return
	if collides(np):
		if dy < 0.0:
			var y := np.y
			for _k in 30:
				y += 0.05
				if not collides(Vector3(np.x, y, np.z)):
					break
			position.y = y
			on_floor = true
		velocity.y = 0.0
		return
	position = np
	on_floor = false


func collides(p: Vector3) -> bool:
	if p.x - RADIUS < bounds_min.x or p.x + RADIUS > bounds_max.x \
			or p.z - RADIUS < bounds_min.z or p.z + RADIUS > bounds_max.z:
		return true
	var mn := Vector3(p.x - RADIUS, p.y + 0.001, p.z - RADIUS)
	var mx := Vector3(p.x + RADIUS, p.y + HEIGHT, p.z + RADIUS)
	if grid != null and grid.box_hits_ice(mn, mx):
		return true
	var box := AABB(mn, mx - mn)
	for s in solids:
		if s.intersects(box):
			return true
	return false


func unstick() -> void:
	## If melting physics ever leaves us inside something, pop up on top.
	var guard := 0
	while collides(position) and guard < 200:
		position.y += 0.25
		guard += 1


func _animate_camera(delta: float) -> void:
	_cam_offset_y = lerpf(_cam_offset_y, 0.0, minf(1.0, delta * 12.0))
	var bob := sin(_bob_t) * 0.04
	_head.position.y = EYE + _cam_offset_y + bob
	_kick = lerpf(_kick, 0.0, minf(1.0, delta * 10.0))
	_tool_holder.position = Vector3(0.24 + sin(_bob_t * 0.5) * 0.01, -0.2 + absf(cos(_bob_t * 0.5)) * 0.008, -0.45 + _kick)


# --- The tool -------------------------------------------------------------------------------
func _update_tool(delta: float) -> void:
	if _shown_tool != GameState.tool_index or _shown_gold != GameState.golden_equipped:
		_build_tool_model()
	var reach := GameState.tool_range()
	target = grid.raycast(camera.global_position, aim_dir(), reach) if grid != null else {"hit": false}
	if target.hit and _blocked_by_solid(camera.global_position, target.pos):
		target = {"hit": false}   # a house (or the shed) is in the way
	var active := melting and input_enabled and not GameState.has_won
	_flame.emitting = active
	if active:
		var dist: float = target.dist if target.hit else reach
		_flame.lifetime = clampf(dist / 10.5, 0.06, 0.6)
		var aim_point: Vector3 = target.pos if target.hit else camera.global_position + aim_dir() * reach
		if _flame.global_position.distance_to(aim_point) > 0.3:
			_flame.look_at(aim_point)
		_kick = 0.02 + randf() * 0.015
	if active and target.hit:
		var normal: Vector3 = target.normal
		var center: Vector3 = target.pos - normal * 0.3
		grid.damage_sphere(center, GameState.tool_radius(), GameState.tool_power() * delta, target.index)
		_steam.global_position = target.pos + normal * 0.2
		_steam.emitting = true
	else:
		_steam.emitting = false


func _blocked_by_solid(from: Vector3, to: Vector3) -> bool:
	for s in solids:
		if s.intersects_segment(from, to) != null:
			return true
	return false


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
