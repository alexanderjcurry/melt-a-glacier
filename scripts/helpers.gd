class_name HelperSwarm
extends Node3D
## Helpers you buy at the shed. Penguins and the sauna crew walk around on the
## ice melting whatever is under them. The adopted volcano lobs lava bombs.

const WALKER_TYPES := [0, 1]           # indices into Balance.HELPERS that walk
const VOLCANO_TYPE := 2
const VOLCANO_POS := Vector3(-27.0, 13.0, -38.0)
const WALK_SPEED := 1.6

var grid: IceGrid
var _walkers: Array = []               # {type, node, pos, target (Vector3i), wobble}
var _bombs: Array = []                 # {node, from, to, t, dur, damage}
var _bomb_timer := 0.0
var _rng := RandomNumberGenerator.new()
var _volcano: Node3D
var _smoke: CPUParticles3D


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
	var label := Label3D.new()
	label.text = Balance.HELPERS[t].icon
	label.font_size = 96
	label.pixel_size = 0.009
	label.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	label.alpha_cut = Label3D.ALPHA_CUT_DISCARD
	label.outline_size = 0
	add_child(label)
	var c := grid.random_surface_cell(_rng)
	var pos := grid.cell_center(c) + Vector3(0, 0.5, 0) if c.y >= 0 else Vector3(0, 0, 8)
	_walkers.append({"type": t, "node": label, "pos": pos, "target": c, "wobble": _rng.randf() * TAU,
		"torch": _make_torch(label)})


func _make_torch(parent: Node3D) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = 10
	p.lifetime = 0.5
	p.emitting = false
	p.direction = Vector3(0, -1, 0)
	p.spread = 25.0
	p.gravity = Vector3(0, 1.5, 0)
	p.initial_velocity_min = 0.6
	p.initial_velocity_max = 1.2
	var quad := QuadMesh.new()
	quad.size = Vector2(0.12, 0.12)
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
	ramp.set_color(0, Color(1.0, 0.7, 0.2, 0.9))
	ramp.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	p.color_ramp = ramp
	p.position = Vector3(0.0, -0.3, 0.0)
	parent.add_child(p)
	return p


func _update_walker(w: Dictionary, delta: float) -> void:
	var t: int = w.type
	var count := int(GameState.helper_counts[t])
	var shown := maxi(mini(count, Balance.MAX_VISIBLE_WALKERS), 1)
	var power := GameState.helper_power(t) / float(shown)   # each visible walker carries a share
	var node: Label3D = w.node
	var torch: CPUParticles3D = w.torch
	if GameState.has_won or grid.remaining <= 0:
		torch.emitting = false
		w.wobble += delta * 6.0
		var p: Vector3 = w.pos
		p.y = lerpf(p.y, grid.surface_height_at(p), minf(1.0, delta * 8.0))
		w.pos = p
		node.position = p + Vector3(0, 0.6 + absf(sin(w.wobble)) * 0.5, 0)   # celebrate
		return
	var tgt: Vector3i = w.target
	if tgt.y < 0 or grid.column_top_y(tgt.x, tgt.z) < 0:
		tgt = grid.nearby_surface_cell(grid.world_to_cell(w.pos), _rng)
		w.target = tgt
		if tgt.y < 0:
			return
	var top := grid.column_top_y(tgt.x, tgt.z)
	var dest := grid.cell_center(Vector3i(tgt.x, top, tgt.z)) + Vector3(0, 0.5, 0)
	var pos: Vector3 = w.pos
	var flat := Vector3(dest.x - pos.x, 0.0, dest.z - pos.z)
	if flat.length() > 0.2:
		var step := flat.normalized() * minf(WALK_SPEED * delta, flat.length())
		pos += step
		torch.emitting = false
		w.wobble += delta * 10.0
	else:
		torch.emitting = true
		if grid.damage_cell(Vector3i(tgt.x, top, tgt.z), power * delta):
			w.target = grid.nearby_surface_cell(Vector3i(tgt.x, top, tgt.z), _rng, 3)
	var ground := grid.surface_height_at(pos)
	pos.y = lerpf(pos.y, ground, minf(1.0, delta * 8.0))
	w.pos = pos
	node.position = pos + Vector3(0, 0.6 + absf(sin(w.wobble)) * 0.06, 0)


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
	if GameState.has_won or grid.remaining <= 0:
		return
	# More volcanoes = more frequent bombs, same damage per second each.
	var interval := clampf(2.4 / sqrt(float(count)), 0.35, 2.4)
	_bomb_timer += delta
	if _bomb_timer >= interval:
		_bomb_timer = 0.0
		var c := grid.random_surface_cell(_rng)
		if c.y >= 0:
			var to := grid.cell_center(c) + Vector3(0, 0.5, 0)
			_launch_bomb(to, GameState.helper_power(VOLCANO_TYPE) * interval)


func _build_volcano() -> void:
	_volcano = Node3D.new()
	_volcano.position = VOLCANO_POS + Vector3(0, -13, 0)
	add_child(_volcano)
	var cone := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 2.5
	cm.bottom_radius = 9.0
	cm.height = 13.0
	cm.radial_segments = 10
	cone.mesh = cm
	cone.position = Vector3(0, 6.5, 0)
	var rock := StandardMaterial3D.new()
	rock.albedo_color = Color(0.3, 0.22, 0.2)
	cone.material_override = rock
	_volcano.add_child(cone)
	var lava := MeshInstance3D.new()
	var lm := CylinderMesh.new()
	lm.top_radius = 2.3
	lm.bottom_radius = 2.3
	lm.height = 0.3
	lava.mesh = lm
	lava.position = Vector3(0, 13.05, 0)
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.albedo_color = Color(1.0, 0.45, 0.1)
	lava.material_override = glow
	_volcano.add_child(lava)
	var label := Label3D.new()
	label.text = "🌋 Kevin"
	label.font_size = 96
	label.pixel_size = 0.03
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = Vector3(0, 17, 0)
	_volcano.add_child(label)


func _launch_bomb(to: Vector3, damage: float) -> void:
	var node := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.45
	sm.height = 0.9
	node.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.5, 0.1)
	node.material_override = mat
	add_child(node)
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
			grid.damage_sphere(to + Vector3(0, -0.5, 0), 1.7, b.damage)
			_puff(to)
			node.queue_free()
			_bombs.erase(b)


func _puff(at: Vector3) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = 24
	p.lifetime = 1.2
	p.explosiveness = 0.9
	p.direction = Vector3(0, 1, 0)
	p.spread = 60.0
	p.gravity = Vector3(0, 2.0, 0)
	p.initial_velocity_min = 1.0
	p.initial_velocity_max = 3.0
	var quad := QuadMesh.new()
	quad.size = Vector2(0.5, 0.5)
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
	ramp.set_color(0, Color(1, 1, 1, 0.8))
	ramp.set_color(1, Color(1, 1, 1, 0.0))
	p.color_ramp = ramp
	p.position = at
	add_child(p)
	p.emitting = true
	get_tree().create_timer(1.6).timeout.connect(p.queue_free)
