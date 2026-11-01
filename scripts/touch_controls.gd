class_name TouchControls
extends Control
## Multi-touch phone controls, drawn on top of the game:
## left thumb = floating joystick, right thumb = drag to look,
## MELT button = hold to melt (dragging from it also turns the view), JUMP button.
## Godot's Buttons only see the first finger, so all of this reads raw touches.

const STICK_RADIUS := 85.0
const MELT_RADIUS := 98.0
const JUMP_RADIUS := 60.0

var move_vector := Vector2.ZERO
var melting := false
var look_delta := Vector2.ZERO        # pixels dragged since the last read
var exclusions: Array[Control] = []   # on-screen buttons the controls must not steal

var _stick_finger := -1
var _stick_origin := Vector2.ZERO
var _stick_pos := Vector2.ZERO
var _look_finger := -1
var _melt_finger := -1
var _jump_finger := -1
var _jump_queued := false


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
	move_vector = Vector2.ZERO
	melting = false
	look_delta = Vector2.ZERO
	queue_redraw()


func _excluded(pos: Vector2) -> bool:
	for c in exclusions:
		if is_instance_valid(c) and c.is_visible_in_tree() and c.get_global_rect().has_point(pos):
			return true
	return false


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event is InputEventScreenTouch:
		var pos: Vector2 = event.position
		if event.pressed:
			if _excluded(pos):
				return
			if pos.distance_to(melt_center()) <= MELT_RADIUS + 25.0 and _melt_finger == -1:
				_melt_finger = event.index
				melting = true
			elif pos.distance_to(jump_center()) <= JUMP_RADIUS + 20.0 and _jump_finger == -1:
				_jump_finger = event.index
				_jump_queued = true
			elif pos.x < size.x * 0.42 and _stick_finger == -1:
				_stick_finger = event.index
				_stick_origin = pos
				_stick_pos = pos
			elif _look_finger == -1:
				_look_finger = event.index
			else:
				return
			get_viewport().set_input_as_handled()
		else:
			if event.index == _melt_finger:
				_melt_finger = -1
				melting = false
			elif event.index == _jump_finger:
				_jump_finger = -1
			elif event.index == _stick_finger:
				_stick_finger = -1
				move_vector = Vector2.ZERO
			elif event.index == _look_finger:
				_look_finger = -1
		queue_redraw()
	elif event is InputEventScreenDrag:
		if event.index == _stick_finger:
			_stick_pos = event.position
			var d := _stick_pos - _stick_origin
			if d.length() > STICK_RADIUS:
				_stick_origin += d - d.normalized() * STICK_RADIUS   # the base follows your thumb
				d = _stick_pos - _stick_origin
			move_vector = Vector2(d.x, -d.y) / STICK_RADIUS
			queue_redraw()
		elif event.index == _look_finger or event.index == _melt_finger:
			look_delta += event.relative


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
	# Jump button
	var jc := jump_center()
	draw_circle(jc, JUMP_RADIUS, Color(0.3, 0.55, 0.9, 0.75 if _jump_finger != -1 else 0.5))
	draw_arc(jc, JUMP_RADIUS, 0, TAU, 40, Color(1, 1, 1, 0.8), 3.0)
	_label(font, "JUMP", jc + Vector2(0, 2), 22, Color.WHITE)


func _label(font: Font, s: String, center: Vector2, font_size: int, color: Color) -> void:
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_string(font, Vector2(center.x - w * 0.5, center.y + font_size * 0.35), s, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
