class_name GlacierView
extends Control
## Draws the valley, the layered glacier, buried objects and helpers, and turns
## taps / holds into melting. All art is procedural placeholder (shapes + emoji)
## so the prototype runs with zero imported assets.

signal tapped(world_pos: Vector2, water: float)

const TOP_MARGIN := 30.0
const FLOOR_HEIGHT := 70.0
const WALL_TOP := 26.0       # valley wall inset at glacier top
const WALL_BOTTOM := 120.0   # valley wall inset at valley floor

var _holding := false
var _pointer := Vector2.ZERO
var _float_texts: Array = []       # {pos, text, t, color}
var _float_accum := 0.0
var _float_timer := 0.0
var _shake := 0.0
var _time := 0.0
var _reveals: Array = []           # {index, t}
var _steam: CPUParticles2D
var _drips: CPUParticles2D
var _font: Font


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	_font = ThemeDB.fallback_font
	_steam = _make_steam()
	add_child(_steam)
	_drips = _make_drips()
	add_child(_drips)
	GameState.layer_cleared.connect(_on_layer_cleared)
	GameState.discovery.connect(_on_discovery)


# --- Geometry -----------------------------------------------------------------------
func floor_y() -> float:
	return size.y - FLOOR_HEIGHT


func band_height() -> float:
	return (floor_y() - TOP_MARGIN) / float(Balance.layer_count())


func band_top(i: int) -> float:
	return TOP_MARGIN + band_height() * float(i)


func surface_y() -> float:
	if GameState.has_won:
		return floor_y()
	var i := GameState.layer_index
	return band_top(i) + band_height() * (1.0 - GameState.layer_fraction_left())


func wall_left(y: float) -> float:
	var t := clampf((y - TOP_MARGIN) / (floor_y() - TOP_MARGIN), 0.0, 1.0)
	return lerpf(WALL_TOP, WALL_BOTTOM, t * t)


func wall_right(y: float) -> float:
	return size.x - wall_left(y)


func discovery_pos(i: int) -> Vector2:
	var x_frac := 0.3 + 0.4 * fposmod(float(i) * 0.618, 1.0)
	return Vector2(size.x * x_frac, band_top(i) + band_height() * 0.5)


# --- Input ----------------------------------------------------------------------------
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_holding = true
			_pointer = event.position
			var w := GameState.tap()
			_float_accum += w
			_float_timer = 1.0  # show the first tap's number right away
			tapped.emit(_pointer, w)
		else:
			_holding = false
		accept_event()
	elif event is InputEventMouseMotion and _holding:
		_pointer = event.position
		accept_event()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT and not DisplayServer.is_touchscreen_available():
		_holding = false


# --- Update -----------------------------------------------------------------------------
func _process(delta: float) -> void:
	_time += delta
	if _holding and not GameState.has_won:
		var w := GameState.melt_raw(GameState.hold_rate() * delta * GameState.debug_speed)
		_float_accum += w
	_float_timer += delta
	if _float_timer >= 0.18 and _float_accum > 0.0:
		var p := Vector2(_pointer.x, minf(_pointer.y, surface_y()))
		_spawn_float("+" + Fmt.num(_float_accum), p + Vector2(randf_range(-30, 30), -20), Color(0.75, 0.93, 1.0))
		_float_accum = 0.0
		_float_timer = 0.0

	# Steam at the melt point, clamped to the ice surface.
	_steam.emitting = _holding and not GameState.has_won
	_steam.position = Vector2(_pointer.x, maxf(_pointer.y, surface_y()))
	_steam.amount = 24 + mini(GameState.tool_size_level(), 40)

	# Drips at the glacier's foot whenever helpers are working.
	_drips.emitting = GameState.auto_rate() > 0.0 and not GameState.has_won
	_drips.position = Vector2(size.x * 0.5, floor_y() - 4)
	_drips.emission_rect_extents = Vector2((wall_right(floor_y()) - wall_left(floor_y())) * 0.5, 2)

	for ft in _float_texts:
		ft.t += delta
		ft.pos.y -= 70.0 * delta
	_float_texts = _float_texts.filter(func(ft): return ft.t < 1.1)
	for r in _reveals:
		r.t += delta
	_reveals = _reveals.filter(func(r): return r.t < 2.2)
	_shake = maxf(0.0, _shake - delta * 30.0)
	queue_redraw()


func _spawn_float(text: String, pos: Vector2, color: Color) -> void:
	if _float_texts.size() > 30:
		_float_texts.pop_front()
	_float_texts.append({"pos": pos, "text": text, "t": 0.0, "color": color})


func _on_layer_cleared(index: int) -> void:
	_shake = 14.0
	var y := band_top(index) + band_height()
	_spawn_float("CRACK!", Vector2(size.x * 0.5, y), Color(1, 1, 1))


func _on_discovery(index: int, value: float) -> void:
	_reveals.append({"index": index, "t": 0.0})
	_spawn_float("+" + Fmt.num(value), discovery_pos(index) + Vector2(0, -60), Color(1.0, 0.9, 0.4))


# --- Drawing ---------------------------------------------------------------------------
func _draw() -> void:
	var w := size.x
	var h := size.y
	if _shake > 0.0:
		draw_set_transform(Vector2(randf_range(-_shake, _shake), randf_range(-_shake, _shake) * 0.5))

	_draw_sky(w, h)
	_draw_mountains(w, h)
	_draw_floor(w, h)
	_draw_village(w)
	if not GameState.has_won:
		_draw_glacier(w)
	_draw_buried_objects()
	_draw_helpers()
	_draw_reveals()
	if _holding and not GameState.has_won:
		_draw_heat_glow()
	for ft in _float_texts:
		var a := 1.0 - clampf((ft.t - 0.6) / 0.5, 0.0, 1.0)
		var c: Color = ft.color
		c.a = a
		_text(ft.text, ft.pos, 30, c, true)
	draw_set_transform(Vector2.ZERO)


func _draw_sky(w: float, h: float) -> void:
	# Sky warms up as the glacier melts.
	var p := GameState.total_progress()
	var top := Color(0.35, 0.55, 0.85).lerp(Color(0.3, 0.6, 0.95), p)
	var bottom := Color(0.75, 0.86, 0.97).lerp(Color(1.0, 0.86, 0.6), p)
	var steps := 16
	for i in steps:
		var c := top.lerp(bottom, float(i) / float(steps - 1))
		draw_rect(Rect2(0, h * float(i) / steps, w, h / steps + 1), c)
	var sun_r := lerpf(26.0, 48.0, p)
	draw_circle(Vector2(w - 80, 70), sun_r + 10, Color(1, 0.9, 0.4, 0.25))
	draw_circle(Vector2(w - 80, 70), sun_r, Color(1, 0.88, 0.35))


func _draw_mountains(w: float, h: float) -> void:
	var fy := floor_y()
	var rock := Color(0.42, 0.45, 0.52)
	var snow := Color(0.95, 0.97, 1.0)
	# Left wall
	var left := PackedVector2Array([Vector2(0, fy), Vector2(0, 10), Vector2(WALL_TOP + 10, TOP_MARGIN - 20)])
	for i in 13:
		var y := lerpf(TOP_MARGIN, fy, float(i) / 12.0)
		left.append(Vector2(wall_left(y), y))
	draw_colored_polygon(left, rock)
	var right := PackedVector2Array([Vector2(w, fy), Vector2(w, 10), Vector2(w - WALL_TOP - 10, TOP_MARGIN - 20)])
	for i in 13:
		var y := lerpf(TOP_MARGIN, fy, float(i) / 12.0)
		right.append(Vector2(wall_right(y), y))
	draw_colored_polygon(right, rock)
	draw_colored_polygon(PackedVector2Array([Vector2(0, 10), Vector2(WALL_TOP + 10, TOP_MARGIN - 20), Vector2(30, 60), Vector2(0, 70)]), snow)
	draw_colored_polygon(PackedVector2Array([Vector2(w, 10), Vector2(w - WALL_TOP - 10, TOP_MARGIN - 20), Vector2(w - 30, 60), Vector2(w, 70)]), snow)


func _draw_floor(w: float, h: float) -> void:
	var grass := Color(0.36, 0.62, 0.3) if GameState.has_won else Color(0.45, 0.5, 0.45)
	draw_rect(Rect2(0, floor_y(), w, h - floor_y()), grass)
	draw_rect(Rect2(0, floor_y(), w, 6), grass.darkened(0.2))


func _draw_village(w: float) -> void:
	var fy := floor_y()
	var houses := [0.25, 0.38, 0.52, 0.66, 0.78]
	var colors := [Color(0.85, 0.35, 0.3), Color(0.95, 0.75, 0.3), Color(0.4, 0.6, 0.85), Color(0.9, 0.5, 0.6), Color(0.5, 0.75, 0.5)]
	for i in houses.size():
		var x: float = w * houses[i]
		var hw := 26.0
		var hh := 30.0 + float(i % 2) * 8.0
		draw_rect(Rect2(x - hw, fy - hh, hw * 2, hh), colors[i])
		draw_colored_polygon(PackedVector2Array([Vector2(x - hw - 6, fy - hh), Vector2(x + hw + 6, fy - hh), Vector2(x, fy - hh - 26)]), Color(0.45, 0.25, 0.2))
		draw_rect(Rect2(x - 7, fy - 18, 14, 18), Color(0.3, 0.2, 0.15))


func _draw_glacier(w: float) -> void:
	var li := GameState.layer_index
	var sy := surface_y()
	for i in range(Balance.layer_count() - 1, li - 1, -1):
		var y1 := band_top(i) + band_height() + (2.0 if i == Balance.layer_count() - 1 else 1.0)
		var y0 := sy if i == li else band_top(i)
		var col: Color = Balance.LAYERS[i].color
		var poly := PackedVector2Array()
		if i == li:
			# Wavy, slowly shimmering top surface.
			var segs := 24
			var xl := wall_left(y0) - 4
			var xr := wall_right(y0) + 4
			for s in segs + 1:
				var x := lerpf(xl, xr, float(s) / segs)
				var wave := sin(x * 0.045 + _time * 1.5) * 3.0 + sin(x * 0.11 + float(i)) * 2.0
				poly.append(Vector2(x, minf(y0 + wave, y1 - 1)))
		else:
			poly.append(Vector2(wall_left(y0) - 4, y0))
			poly.append(Vector2(wall_right(y0) + 4, y0))
		poly.append(Vector2(wall_right(y1) + 4, y1))
		poly.append(Vector2(wall_left(y1) - 4, y1))
		draw_colored_polygon(poly, col)
		# Highlight line along the top of each band
		var hl := col.lightened(0.35)
		hl.a = 0.6
		draw_line(Vector2(wall_left(y0) + 2, y0 + 2), Vector2(wall_right(y0) - 2, y0 + 2), hl, 2.0)
	# A little sparkle on the surface
	var sx := fposmod(_time * 90.0, w)
	if sx > wall_left(sy) and sx < wall_right(sy):
		draw_circle(Vector2(sx, sy + 8), 2.5, Color(1, 1, 1, 0.8))


func _draw_buried_objects() -> void:
	var n := Balance.DISCOVERIES.size() - 1  # the village is drawn separately
	for i in n:
		if GameState.discovered[i]:
			continue
		if i < GameState.layer_index:
			continue
		var p := discovery_pos(i)
		var alpha := 0.35 if p.y > surface_y() + 20 else 0.7
		_text(Balance.DISCOVERIES[i].icon, p, 44, Color(0.75, 0.88, 1.0, alpha), true)


func _draw_reveals() -> void:
	for r in _reveals:
		var i: int = r.index
		var t: float = r.t
		var p := discovery_pos(i)
		p.y = minf(p.y, surface_y()) - 30.0 - t * 40.0
		var scale := 1.0 + 0.6 * sin(minf(t, 0.4) / 0.4 * PI * 0.5)
		var a := 1.0 - clampf((t - 1.6) / 0.6, 0.0, 1.0)
		draw_circle(p, 46.0 * scale, Color(1, 0.95, 0.6, 0.35 * a))
		_text(Balance.DISCOVERIES[i].icon, p, int(54 * scale), Color(1, 1, 1, a), true)
		_text(Balance.DISCOVERIES[i].name, p + Vector2(0, 52), 26, Color(1, 1, 0.85, a), true)


func _draw_helpers() -> void:
	if GameState.has_won:
		return
	var sy := surface_y()
	var x := wall_left(sy) + 30
	var right := wall_right(sy) - 30
	for i in Balance.HELPERS.size():
		var shown := mini(int(GameState.helper_counts[i]), 4)
		for k in shown:
			if x > right:
				return
			var bob := sin(_time * 4.0 + float(k) * 1.3 + float(i)) * 3.0
			_text(Balance.HELPERS[i].icon, Vector2(x, sy - 14 + bob), 30, Color.WHITE, true)
			x += 34


func _draw_heat_glow() -> void:
	var radius := 36.0 + minf(float(GameState.tool_size_level()) * 4.0, 110.0)
	var base := Color(1.0, 0.82, 0.2) if GameState.golden_equipped else Color(1.0, 0.5, 0.15)
	for k in 5:
		var c := base
		c.a = 0.07 + 0.05 * float(k)
		draw_circle(_pointer, radius * (1.0 - float(k) * 0.17), c)
	_text(Balance.TOOLS[GameState.tool_index].icon, _pointer + Vector2(0, -radius - 6), 40, Color.WHITE, true)


func _text(s: String, center: Vector2, font_size: int, color: Color, outline: bool = false) -> void:
	var width := _font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var pos := Vector2(center.x - width * 0.5, center.y + font_size * 0.35)
	if outline:
		draw_string_outline(_font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 6, Color(0.05, 0.1, 0.2, color.a * 0.8))
	draw_string(_font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


# --- Particles --------------------------------------------------------------------------
func _make_steam() -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.amount = 24
	p.lifetime = 1.1
	p.emitting = false
	p.local_coords = false
	p.direction = Vector2(0, -1)
	p.spread = 30.0
	p.gravity = Vector2(0, -80)
	p.initial_velocity_min = 40.0
	p.initial_velocity_max = 110.0
	p.scale_amount_min = 6.0
	p.scale_amount_max = 14.0
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 18.0
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 0.8))
	ramp.set_color(1, Color(1, 1, 1, 0.0))
	p.color_ramp = ramp
	return p


func _make_drips() -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.amount = 30
	p.lifetime = 0.9
	p.emitting = false
	p.local_coords = false
	p.direction = Vector2(0, 1)
	p.spread = 5.0
	p.gravity = Vector2(0, 500)
	p.initial_velocity_min = 10.0
	p.initial_velocity_max = 30.0
	p.scale_amount_min = 3.0
	p.scale_amount_max = 5.0
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.color = Color(0.45, 0.7, 1.0, 0.9)
	return p
