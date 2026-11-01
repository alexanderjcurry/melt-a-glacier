class_name HelperSwarm
extends Node3D
## Helpers you buy at the shed. Penguins and the sauna crew waddle around on
## top of the ice melting the spot in front of them. Kevin the adopted
## volcano lobs lava bombs (and keeps an eye on you).

const WALKER_TYPES := [0, 1]           # indices into Balance.HELPERS that walk
const VOLCANO_TYPE := 2
const VOLCANO_POS := Vector3(-27.0, 13.0, -38.0)
const WALK_SPEED := [1.4, 1.1]         # per walker type
const MELT_RADIUS := [0.7, 1.0]
const MELT_TIME := 4.5                 # seconds at one spot before moving on

var grid: IceField
var player: Node3D                     # Kevin watches you
var _walkers: Array = []               # {type, node, body, pos, target, t, timer, melting, fx}
var _bombs: Array = []                 # {node, from, to, t, dur, damage}
var _bomb_timer := 0.0
var _rng := RandomNumberGenerator.new()
var _volcano: Node3D
var _smoke: CPUParticles3D
var _spawned := 0


func _ready() -> void:
	_rng.randomize()


func _process(delta: float) -> void:
	delta = minf(delta, 0.05)
	if grid == null:
		return
	_sync_walkers()
	for w in _walkers:
		_update_walker(w, delta)
	_update_volcano(delta)
	_update_bombs(delta)


# --- Walkers --------------------------------------------------------------------------------
func _sync_walkers() -> void:
	for t in WALKER_TYPES:
		var want := mini(int(GameState.helper_counts[t]), Balance.MAX_VISIBLE_WALKERS)
		var have := 0
		for w in _walkers:
			if w.type == t:
				have += 1
		while have < want:
			_spawn_walker(t)
			have += 1
		if have > want:   # after a reset
			for w in _walkers.duplicate():
				if w.type == t and have > want:
					w.node.queue_free()
					_walkers.erase(w)
					have -= 1


func _spawn_walker(t: int) -> void:
	_spawned += 1
	var node: Node3D = Creatures.penguin(_spawned) if t == 0 else Creatures.sauna(_spawned)
	var s := _rng.randf_range(0.92, 1.08)
	node.scale = Vector3(s, s, s)
	add_child(node)
	var body: Node3D = node.get_node("Body")
	var fx: CPUParticles3D
	if t == 0:
		fx = _make_fx(Color(1.0, 0.7, 0.2, 0.95), Color(1.0, 0.95, 0.9, 0.0), 0.1, 14, 0.35)
		fx.direction = Vector3(0, -0.6, -1)
		fx.initial_velocity_min = 1.2
		fx.initial_velocity_max = 2.0
		fx.gravity = Vector3(0, 1.5, 0)
		body.get_node("Nozzle").add_child(fx)
	else:
		fx = _make_fx(Color(1, 1, 1, 0.65), Color(1, 1, 1, 0.0), 0.32, 18, 1.4)
		fx.direction = Vector3(0, 1, 0)
		fx.spread = 25.0
		fx.initial_velocity_min = 0.5
		fx.initial_velocity_max = 1.1
		fx.gravity = Vector3(0, 0.8, 0)
		body.get_node("Bucket").add_child(fx)
	var p := grid.random_surface_point(_rng)
	if p == Vector3.INF:
		p = Vector3(_rng.randf_range(-8.0, 8.0), 0.0, 8.0)
	p.y = grid.surface_y(p.x, p.z)   # the same smoothed surface they walk on
	node.position = p
	node.rotation.y = _rng.randf() * TAU
	_walkers.append({"type": t, "node": node, "body": body, "pos": p, "target": Vector3.INF,
		"t": _rng.randf() * TAU, "timer": 0.0, "melting": false, "fx": fx})


func _make_fx(c0: Color, c1: Color, size: float, amount: int, life: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	p.emitting = false
	p.spread = 18.0
	p.local_coords = false
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
	p.scale_amount_min = 0.7
	p.scale_amount_max = 1.3
	return p


func _update_walker(w: Dictionary, delta: float) -> void:
	var t: int = w.type
	var node: Node3D = w.node
	var fx: CPUParticles3D = w.fx
	var pos: Vector3 = w.pos
	if GameState.has_won or grid.remaining <= 0:
		# Party time: hop up and down wherever they are.
		fx.emitting = false
		w.t += delta * 7.0
		pos.y = lerpf(pos.y, grid.surface_y(pos.x, pos.z), minf(1.0, delta * 8.0))
		w.pos = pos
		node.position = pos + Vector3(0, absf(sin(w.t)) * 0.35, 0)
		_pose(w, 1.0, 0.0, true)
		return
	var count := int(GameState.helper_counts[t])
	var shown := maxi(mini(count, Balance.MAX_VISIBLE_WALKERS), 1)
	var power := GameState.helper_power(t) / float(shown)   # each visible walker carries a share
	var tgt: Vector3 = w.target
	if tgt == Vector3.INF or not grid.has_ice_at(tgt.x, tgt.z):
		tgt = grid.nearby_surface_point(pos, _rng, 4.0)
		w.target = tgt
		w.timer = 0.0
		if tgt == Vector3.INF:
			fx.emitting = false
			return
	var flat := Vector3(tgt.x - pos.x, 0.0, tgt.z - pos.z)
	var walking := flat.length() > 0.3
	if walking:
		pos += flat.normalized() * minf(float(WALK_SPEED[t]) * delta, flat.length())
		node.rotation.y = lerp_angle(node.rotation.y, atan2(-flat.x, -flat.z), minf(1.0, delta * 8.0))
		w.t += delta * (11.0 if t == 0 else 8.0)
		w.timer = 0.0
	else:
		# Melt the spot just in front.
		var fwd := -node.global_transform.basis.z
		var spot := Vector3(pos.x, 0.0, pos.z) + fwd * 0.35
		spot.y = grid.surface_y(spot.x, spot.z) - 0.12
		grid.damage_sphere(spot, float(MELT_RADIUS[t]), power * delta)
		w.timer += delta
		w.t += delta * 3.0
		if w.timer > MELT_TIME:
			w.target = grid.nearby_surface_point(pos, _rng, 3.0)
			w.timer = 0.0
	fx.emitting = not walking
	pos.y = lerpf(pos.y, grid.surface_y(pos.x, pos.z), minf(1.0, delta * 10.0))
	w.pos = pos
	node.position = pos
	_pose(w, 1.0 if walking else 0.0, 0.0 if walking else 1.0, false)


func _pose(w: Dictionary, walk: float, work: float, party: bool) -> void:
	## Waddle while walking, lean in while melting, flap while partying.
	var body: Node3D = w.body
	var node: Node3D = w.node
	var ph: float = w.t
	if int(w.type) == 0:
		body.rotation = Vector3(-0.32 * work, 0.0, sin(ph) * 0.2 * walk)
		var flap := 0.25 + (absf(sin(ph * 2.0)) * 0.9 if party else 0.0) + sin(ph * 4.0) * 0.08 * work
		(body.get_node("FlipperL") as Node3D).rotation.z = -flap
		(body.get_node("FlipperR") as Node3D).rotation.z = flap
		(node.get_node("FootL") as Node3D).position.y = 0.03 + maxf(0.0, sin(ph)) * 0.05 * walk
		(node.get_node("FootR") as Node3D).position.y = 0.03 + maxf(0.0, -sin(ph)) * 0.05 * walk
	else:
		body.rotation = Vector3(-0.12 * work, 0.0, sin(ph) * 0.08 * walk)
		body.position.y = absf(sin(ph)) * 0.04 * walk
		(node.get_node("FootL") as Node3D).position.y = maxf(0.0, sin(ph)) * 0.06 * walk
		(node.get_node("FootR") as Node3D).position.y = maxf(0.0, -sin(ph)) * 0.06 * walk
		if party:
			body.rotation.z = sin(ph) * 0.2


# --- Volcano ------------------------------------------------------------------------------
func _update_volcano(delta: float) -> void:
	var count := int(GameState.helper_counts[VOLCANO_TYPE])
	if count <= 0:
		if _volcano != null:
			_volcano.queue_free()
			_volcano = null
		return
	if _volcano == null:
		_build_volcano()
	_look_at_player()
	if GameState.has_won or grid.remaining <= 0:
		return
	# More volcanoes = more frequent bombs, same damage per second each.
	var interval := clampf(2.4 / sqrt(float(count)), 0.35, 2.4)
	_bomb_timer += delta
	if _bomb_timer >= interval:
		_bomb_timer = 0.0
		var p := grid.random_surface_point(_rng)
		if p != Vector3.INF:
			_launch_bomb(p, GameState.helper_power(VOLCANO_TYPE) * interval)


func _build_volcano() -> void:
	_volcano = Creatures.volcano()
	_volcano.position = VOLCANO_POS + Vector3(0, -13, 0)
	# Face the glacier.
	var to := Vector3(0, 0, -12) - _volcano.position
	_volcano.rotation.y = atan2(to.x, to.z)
	add_child(_volcano)
	_smoke = _make_fx(Color(0.45, 0.42, 0.42, 0.55), Color(0.6, 0.6, 0.62, 0.0), 3.0, 26, 5.0)
	_smoke.direction = Vector3(0, 1, 0)
	_smoke.spread = 12.0
	_smoke.initial_velocity_min = 2.0
	_smoke.initial_velocity_max = 3.5
	_smoke.gravity = Vector3(0.4, 0.3, 0.2)
	_smoke.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_smoke.emission_sphere_radius = 1.2
	_smoke.position = Vector3(0, 13.4, 0)
	_volcano.add_child(_smoke)
	_smoke.emitting = true
	var label := Label3D.new()
	label.text = "🌋 Kevin"
	label.font_size = 96
	label.pixel_size = 0.03
	label.outline_size = 18
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = Vector3(0, 17.5, 0)
	_volcano.add_child(label)


func _look_at_player() -> void:
	if player == null:
		return
	for eye_name in ["EyeL", "EyeR"]:
		var eye: Node3D = _volcano.get_node(eye_name)
		var pupil: Node3D = eye.get_node("Pupil")
		var dir := eye.global_transform.basis.inverse() * (player.global_position + Vector3(0, 1.5, 0) - eye.global_position)
		pupil.position = pupil.position.lerp(dir.normalized() * 0.85, 0.15)


func _launch_bomb(to: Vector3, damage: float) -> void:
	var node := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.45
	sm.height = 0.9
	sm.radial_segments = 10
	sm.rings = 6
	node.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.5, 0.1)
	node.material_override = mat
	add_child(node)
	var trail := _make_fx(Color(1.0, 0.6, 0.2, 0.8), Color(0.5, 0.5, 0.5, 0.0), 0.7, 20, 0.8)
	trail.spread = 180.0
	trail.initial_velocity_min = 0.1
	trail.initial_velocity_max = 0.4
	trail.gravity = Vector3(0, 0.5, 0)
	node.add_child(trail)
	trail.emitting = true
	var from := VOLCANO_POS + Vector3(0, 0.5, 0)
	node.position = from
	_bombs.append({"node": node, "from": from, "to": to, "t": 0.0, "dur": 1.8, "damage": damage})


func _update_bombs(delta: float) -> void:
	for b in _bombs.duplicate():
		b.t += delta
		var k := clampf(b.t / b.dur, 0.0, 1.0)
		var from: Vector3 = b.from
		var to: Vector3 = b.to
		var p := from.lerp(to, k)
		p.y += sin(k * PI) * 14.0
		var node: MeshInstance3D = b.node
		node.position = p
		if k >= 1.0:
			grid.damage_sphere(to + Vector3(0, -0.4, 0), 1.7, b.damage)
			_puff(to)
			node.queue_free()
			_bombs.erase(b)


func _puff(at: Vector3) -> void:
	var p := _make_fx(Color(1, 1, 1, 0.8), Color(1, 1, 1, 0.0), 0.6, 24, 1.2)
	p.one_shot = true
	p.explosiveness = 0.9
	p.direction = Vector3(0, 1, 0)
	p.spread = 60.0
	p.gravity = Vector3(0, 2.0, 0)
	p.initial_velocity_min = 1.0
	p.initial_velocity_max = 3.0
	p.position = at
	add_child(p)
	p.emitting = true
	get_tree().create_timer(1.6).timeout.connect(p.queue_free)
