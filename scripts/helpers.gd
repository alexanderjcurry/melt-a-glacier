class_name HelperSwarm
extends Node3D
## Helpers you buy at the shed. Penguins and the sauna crew wander around on
## top of the ice, melting a thin layer as they walk (so the glacier wears
## down evenly instead of getting dug full of holes). Kevin the adopted
## volcano lobs lava bombs (and keeps an eye on you). When a glacier is gone
## the crew retires and parties where they stand; you hire a new crew for the
## next glacier.

const WALKER_TYPES := [0, 1]           # indices into Balance.HELPERS that walk
const VOLCANO_TYPE := 2
const VOLCANO_POS := Vector3(-30.0, 13.0, -47.0)   # in his hollow, clear of the path behind the glacier
const WALK_SPEED := [1.2, 1.1]         # m/s, per walker type
# Their heat lands in a few small, shallow spots scattered around them (the
# sauna crew's hot stones warm a wide circle), so the ice wears down a little
# everywhere they go instead of in one deep hole.
const SPREAD := [0.9, 3.2]             # radius of the circle the heat lands in
const SPOT_RADIUS := [0.6, 0.75]
const SPOTS := [2, 8]                  # spots per pulse
const MELT_PULSE := 0.25               # heat is saved up and put down this often (seconds)
# A helper's power is the hp x m³ of ice it melts per second (= water per second
# at x1 sell), as long as the ice isn't so soft that the heat is wasted. A ball
# of heat `a` with radius r melts about WORK x a x r³ of that (IceField.damage_sphere):
const WALK_WORK := 2.76                # ball centred just above the surface
const BOMB_WORK := 4.3                 # ball centred 0.4 m into the ice
const BOMB_RADIUS := 1.7
const DROP := 0.6                      # won't step down more than this per 0.6 m (into a hole)
const CLIMB := 1.1                     # or climb more than this

var grid: IceField
var player: Node3D                     # Kevin watches you
var _walkers: Array = []               # {type, node, body, pos, target, t, heat, pulse, fx}
var _retired: Array = []               # the old crew, partying in the village
const MAX_RETIRED := 14
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
	for w in _retired:
		w.t += delta * 7.0
		var pos: Vector3 = w.pos
		(w.node as Node3D).position = Vector3(pos.x, absf(sin(w.t)) * 0.35, pos.z)
		_pose(w, 1.0, 0.0, true)
	_update_volcano(delta)
	_update_bombs(delta)


# --- Walkers --------------------------------------------------------------------------------
func retire() -> void:
	## The glacier's gone: this crew stops working and parties where they are
	## (a few of them, anyway). Kevin dozes off until you adopt him again.
	for w in _walkers:
		(w.fx as CPUParticles3D).emitting = false
		if _retired.size() < MAX_RETIRED:
			var pos: Vector3 = w.pos
			w.pos = Vector3(pos.x, 0.0, pos.z)
			_retired.append(w)
		else:
			(w.node as Node3D).queue_free()
	_walkers.clear()
	if _smoke != null:
		_smoke.emitting = false


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
		"t": _rng.randf() * TAU, "heat": 0.0, "pulse": _rng.randf() * MELT_PULSE, "scramble": false, "fx": fx})


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
	# Keep wandering: a new spot every few metres, never over a cliff or into a deep hole.
	var tgt: Vector3 = w.target
	var flat := Vector3.ZERO
	if tgt != Vector3.INF:
		flat = Vector3(tgt.x - pos.x, 0.0, tgt.z - pos.z)
	if tgt == Vector3.INF or flat.length() < 0.4 or not grid.has_ice_at(tgt.x, tgt.z):
		var pick := _pick_target(pos)
		tgt = pick[0]
		w.target = tgt
		w.scramble = not pick[1]   # no easy way anywhere: climb out however it takes
		if tgt == Vector3.INF:
			fx.emitting = false
			_pose(w, 0.0, 0.0, false)
			return
		flat = Vector3(tgt.x - pos.x, 0.0, tgt.z - pos.z)
	var dir := flat.normalized()
	var ahead := pos + dir * 0.6
	var step := grid.surface_y(ahead.x, ahead.z) - grid.surface_y(pos.x, pos.z)
	if not w.scramble and (step < -DROP or step > CLIMB):
		w.target = Vector3.INF   # too steep that way (someone dug a hole): go somewhere else
		return
	pos += dir * minf(float(WALK_SPEED[t]) * delta, flat.length())
	node.rotation.y = lerp_angle(node.rotation.y, atan2(-dir.x, -dir.z), minf(1.0, delta * 6.0))
	w.t += delta * (11.0 if t == 0 else 8.0)
	# Melt a thin layer just ahead of their feet as they go.
	var on_ice := grid.has_ice_at(pos.x, pos.z)
	if on_ice:
		w.heat += power * delta
		w.pulse += delta
		if w.pulse >= MELT_PULSE:
			var r: float = maxf(SPOT_RADIUS[t], grid.res * 1.15)   # (a coarse grid needs a bigger spot to hit anything)
			var n: int = SPOTS[t]
			var spread: float = SPREAD[t]
			var amount: float = w.heat / (WALK_WORK * r * r * r * float(n))
			var ahead_c := Vector3(pos.x, 0.0, pos.z) - node.global_transform.basis.z * spread * 0.4
			for _k in n:
				var a := _rng.randf() * TAU
				var spot := ahead_c + Vector3(cos(a), 0.0, sin(a)) * spread * sqrt(_rng.randf())
				if grid.has_ice_at(spot.x, spot.z):
					spot.y = grid.surface_y(spot.x, spot.z) + 0.12
					grid.damage_sphere(spot, r, amount)
			w.heat = 0.0
			w.pulse = 0.0
	fx.emitting = on_ice
	pos.y = lerpf(pos.y, grid.surface_y(pos.x, pos.z), minf(1.0, delta * 10.0))
	w.pos = pos
	node.position = pos
	_pose(w, 1.0, 0.35 if on_ice else 0.0, false)


func _pick_target(from: Vector3) -> Array:
	## [spot, easy]: somewhere on the ice a few metres away, preferring snow
	## that hasn't been melted down yet (so the glacier wears down evenly
	## instead of getting trenches), reachable without dropping into a hole or
	## climbing a wall (easy = true). Otherwise any spot on the ice nearby.
	var h0 := grid.surface_y(from.x, from.z)
	var best := Vector3.INF
	var best_score := -INF
	for _try in 10:
		var ang := _rng.randf() * TAU
		var dist := _rng.randf_range(2.0, 6.0)
		var to := from + Vector3(sin(ang), 0.0, cos(ang)) * dist
		if not grid.has_ice_at(to.x, to.z):
			continue
		var h := grid.surface_y(to.x, to.z)
		if h < 0.25:
			continue
		var ok := true
		var prev := h0
		var steps := int(ceil(dist / 0.6))
		for k in range(1, steps + 1):
			var p := from.lerp(to, float(k) / steps)
			var hp := grid.surface_y(p.x, p.z)
			if hp - prev < -DROP or hp - prev > CLIMB:
				ok = false
				break
			prev = hp
		if not ok:
			continue
		var worn := grid.original_top(to.x, to.z) - h   # how much has melted off here already
		var score := -worn + _rng.randf() * 0.5
		if score > best_score:
			best_score = score
			best = Vector3(to.x, h, to.z)
	if best != Vector3.INF:
		return [best, true]
	return [grid.nearby_surface_point(from, _rng, 4.0), false]


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
		if _volcano != null and GameState.stage == 0:   # (after a fresh start)
			_volcano.queue_free()
			_volcano = null
		elif _volcano != null:
			_look_at_player()   # retired, but still watching you
		return
	if _volcano == null:
		_build_volcano()
	if not _smoke.emitting:
		_smoke.emitting = true
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
			_launch_bomb(p, GameState.helper_power(VOLCANO_TYPE) * interval / (BOMB_WORK * pow(BOMB_RADIUS, 3.0)))


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
	UiTheme.sign_label(label)
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
	var far := from.distance_to(to)   # the lake is a long way off: higher, slower lobs
	_bombs.append({"node": node, "from": from, "to": to, "t": 0.0, "dur": clampf(far / 28.0, 1.8, 5.0),
		"arc": clampf(far * 0.3, 14.0, 40.0), "damage": damage})


func _update_bombs(delta: float) -> void:
	for b in _bombs.duplicate():
		b.t += delta
		var k := clampf(b.t / b.dur, 0.0, 1.0)
		var from: Vector3 = b.from
		var to: Vector3 = b.to
		var p := from.lerp(to, k)
		p.y += sin(k * PI) * float(b.arc)
		var node: MeshInstance3D = b.node
		node.position = p
		if k >= 1.0:
			grid.damage_sphere(to + Vector3(0, -0.4, 0), BOMB_RADIUS, b.damage)
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
