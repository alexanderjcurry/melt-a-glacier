class_name TouchControls
extends Control
## Multi-touch phone controls, drawn on top of the game:
## left side = floating joystick, right side = drag to look,
## MELT button = hold to melt (dragging from it also turns the view),
## JUMP button = tap to jump, keep holding to fly with the jetpack.
## Godot's Buttons only see the first finger, so all of this reads raw touches,
## and on-screen buttons registered in `buttons` are tapped from here too.
##
## Each finger is tracked by its own index and its motion is worked out from its
## own last position. (On the web, a drag event's `relative` can be measured
## against another finger when several are down, which spun the camera.)

const STICK_RADIUS := 85.0
const STICK_DEAD := 0.12            # inner part of the stick that does nothing
const STICK_ZONE := 0.45            # the left 45% of the screen belongs to the stick
const MELT_RADIUS := 98.0
const JUMP_RADIUS := 60.0
const LOOK_DEAD_PX := 8.0           # a look finger has to move this far before the view turns
const MELT_LOOK_DEAD_PX := 24.0     # more slack while a thumb rests on the melt button
const GLITCH_PX := 220.0            # a jump this big between two events is not a real swipe

var move_vector := Vector2.ZERO
var melting := false
var jump_held := false
var look_delta := Vector2.ZERO        # pixels dragged since the last read
var fuel := 1.0                       # jetpack fuel 0..1, drawn around the JUMP button
var buttons: Array = []               # [{control, action}] on-screen buttons any finger can tap
var exclusions: Array[Control] = []   # other controls the touch controls must leave alone

var _stick_finger := -1
var _stick_origin := Vector2.ZERO
var _stick_pos := Vector2.ZERO
var _look_finger := -1
var _melt_finger := -1
var _jump_finger := -1
var _jump_queued := false
var _last := {}                       # finger index -> last position
var _travel := {}                     # finger index -> distance moved since it touched down


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func melt_center() -> Vector2:
	return Vector2(size.x - 150.0, size.y - 150.0)


func jump_center() -> Vector2:
	return Vector2(size.x - 315.0, size.y - 80.0)


func stick_home() -> Vector2:
	return Vector2(170.0, size.y - 160.0)


func take_look_delta() -> Vector2:
	var d := look_delta
	look_delta = Vector2.ZERO
	return d


func take_jump() -> bool:
	var j := _jump_queued
	_jump_queued = false
	return j


func release_all() -> void:
	_stick_finger = -1
	_look_finger = -1
	_melt_finger = -1
	_jump_finger = -1
	_last.clear()
	_travel.clear()
	move_vector = Vector2.ZERO
	melting = false
	jump_held = false
	look_delta = Vector2.ZERO
	queue_redraw()


func _excluded(pos: Vector2) -> bool:
	for c in exclusions:
		if is_instance_valid(c) and c.is_visible_in_tree() and c.get_global_rect().has_point(pos):
			return true
	return false


func _button_at(pos: Vector2) -> Dictionary:
	for b in buttons:
		var c: Control = b.control
		if is_instance_valid(c) and c.is_visible_in_tree() and c.get_global_rect().grow(6.0).has_point(pos):
			return b
	return {}


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event is InputEventScreenTouch:
		_on_touch(event)
	elif event is InputEventScreenDrag:
		_on_drag(event)


func _on_touch(event: InputEventScreenTouch) -> void:
	var i := event.index
	var pos := event.position
	# A new touch with an index we still hold means its lift-off got lost
	# (browsers can drop touchend): let go of it first.
	_release(i)
	if not event.pressed or event.canceled:
		queue_redraw()
		return
	var b := _button_at(pos)
	if not b.is_empty():
		_flash(b.control)
		b.action.call()
		get_viewport().set_input_as_handled()
		return
	if _excluded(pos):
		return
	if pos.distance_to(melt_center()) <= MELT_RADIUS + 25.0:
		_release(_melt_finger)
		_melt_finger = i
		melting = true
	elif pos.distance_to(jump_center()) <= JUMP_RADIUS + 25.0:
		_release(_jump_finger)
		_jump_finger = i
		jump_held = true
		_jump_queued = true
	elif pos.x < size.x * STICK_ZONE:
		# The left side is always the stick. A second finger there takes it
		# over instead of turning the camera.
		_release(_stick_finger)
		_stick_finger = i
		_stick_origin = pos
		_stick_pos = pos
		move_vector = Vector2.ZERO
	else:
		_release(_look_finger)
		_look_finger = i
	_last[i] = pos
	_travel[i] = 0.0
	get_viewport().set_input_as_handled()
	queue_redraw()


func _release(i: int) -> void:
	if i < 0:
		return
	_last.erase(i)
	_travel.erase(i)
	if i == _melt_finger:
		_melt_finger = -1
		melting = false
	if i == _jump_finger:
		_jump_finger = -1
		jump_held = false
	if i == _stick_finger:
		_stick_finger = -1
		move_vector = Vector2.ZERO
	if i == _look_finger:
		_look_finger = -1


func _on_drag(event: InputEventScreenDrag) -> void:
	var i := event.index
	if not _last.has(i):
		return
	var pos := event.position
	var step: Vector2 = pos - _last[i]
	_last[i] = pos
	if i == _stick_finger:
		_stick_pos = pos
		var d := _stick_pos - _stick_origin
		if d.length() > STICK_RADIUS:
			_stick_origin += d - d.normalized() * STICK_RADIUS   # the base follows your thumb
			d = _stick_pos - _stick_origin
		var v := Vector2(d.x, -d.y) / STICK_RADIUS
		var m := v.length()
		if m < STICK_DEAD:
			move_vector = Vector2.ZERO
		else:
			move_vector = v / m * minf(1.0, (m - STICK_DEAD) / (1.0 - STICK_DEAD))
		queue_redraw()
	elif i == _look_finger or i == _melt_finger:
		var len := step.length()
		if len > GLITCH_PX or len == 0.0:
			return
		var dead := MELT_LOOK_DEAD_PX if i == _melt_finger else LOOK_DEAD_PX
		var before: float = _travel.get(i, 0.0)
		_travel[i] = before + len
		if before + len <= dead:
			return
		if before < dead:
			step *= (before + len - dead) / len   # only the part past the dead zone counts
		look_delta += step
	get_viewport().set_input_as_handled()


func _flash(c: Control) -> void:
	c.modulate = Color(1.4, 1.4, 1.4)
	c.create_tween().tween_property(c, "modulate", Color.WHITE, 0.25)


func _draw() -> void:
	var font := get_theme_default_font()
	# Joystick
	var base := _stick_origin if _stick_finger != -1 else stick_home()
	var knob := _stick_pos if _stick_finger != -1 else base
	var a := 0.55 if _stick_finger != -1 else 0.28
	draw_circle(base, STICK_RADIUS, Color(1, 1, 1, a * 0.35))
	draw_arc(base, STICK_RADIUS, 0, TAU, 48, Color(1, 1, 1, a), 3.0)
	draw_circle(knob, 34.0, Color(1, 1, 1, a + 0.15))
	if _stick_finger == -1:
		_label(font, "MOVE", base + Vector2(0, STICK_RADIUS + 26), 20, Color(1, 1, 1, 0.55))
	# Melt button
	var mc := melt_center()
	var hot := Color(1.0, 0.45, 0.12, 0.9 if melting else 0.6)
	draw_circle(mc, MELT_RADIUS, hot)
	draw_arc(mc, MELT_RADIUS, 0, TAU, 48, Color(1, 0.9, 0.7, 0.9), 4.0)
	_label(font, "🔥", mc + Vector2(0, -14), 52, Color.WHITE)
	_label(font, "HOLD TO MELT", mc + Vector2(0, 46), 19, Color.WHITE)
	# Jump / jetpack button, with the fuel gauge around it
	var jc := jump_center()
	draw_circle(jc, JUMP_RADIUS, Color(0.3, 0.55, 0.9, 0.75 if _jump_finger != -1 else 0.5))
	draw_arc(jc, JUMP_RADIUS, 0, TAU, 40, Color(1, 1, 1, 0.8), 3.0)
	if fuel < 0.999:
		draw_arc(jc, JUMP_RADIUS + 9.0, 0, TAU, 48, Color(0, 0, 0, 0.35), 7.0)
		var fc := Color(0.45, 0.9, 1.0) if fuel > 0.25 else Color(1.0, 0.5, 0.3)
		draw_arc(jc, JUMP_RADIUS + 9.0, -PI / 2.0, -PI / 2.0 + TAU * fuel, 48, fc, 7.0)
	_label(font, "JUMP", jc + Vector2(0, -8), 22, Color.WHITE)
	_label(font, "hold = fly", jc + Vector2(0, 18), 15, Color(1, 1, 1, 0.85))


func _label(font: Font, s: String, center: Vector2, font_size: int, color: Color) -> void:
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_string(font, Vector2(center.x - w * 0.5, center.y + font_size * 0.35), s, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
