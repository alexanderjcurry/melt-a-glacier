class_name TouchControls
extends Control
## Multi-touch phone controls, drawn on top of the game:
## left side = floating joystick, right side = drag to look,
## MELT button = hold to melt (dragging from it also turns the view),
## JUMP button = tap to jump, keep holding to fly with the jetpack.
## In the shed, while you look at something for sale, the MELT button turns
## into a BUY (or HIRE, OPEN...) button: see set_action().
## Godot's Buttons only see the first finger, so all of this reads raw touches,
## and on-screen buttons registered in `buttons` are tapped from here too.
##
## Each finger is tracked by its own index and its motion is worked out from its
## own last position. (On the web, a drag event's `relative` can be measured
## against another finger when several are down, which spun the camera.)
##
## Finger indexes are whatever the browser or OS hands out. iPhone Safari gives
## big numbers that can be negative (-1525662976), so "no finger" is NONE, a
## value no real index can have, never -1.

const STICK_RADIUS := 85.0
const STICK_DEAD := 0.12            # inner part of the stick that does nothing
const STICK_ZONE := 0.45            # the left 45% of the screen belongs to the stick
const MELT_RADIUS := 98.0
const JUMP_RADIUS := 60.0
const LOOK_DEAD_PX := 8.0           # a look finger has to move this far before the view turns
const MELT_LOOK_DEAD_PX := 24.0     # more slack while a thumb rests on the melt button
const GLITCH_PX := 220.0            # a jump this big between two events is not a real swipe
const NONE := -281474976710656      # "no finger": outside the 32-bit range touch ids come from

var move_vector := Vector2.ZERO
var melting := false
var jump_held := false
var look_delta := Vector2.ZERO        # pixels dragged since the last read
var fuel := 1.0                       # jetpack fuel 0..1, drawn around the JUMP button
var buttons: Array = []               # [{control, action}] on-screen buttons any finger can tap
var exclusions: Array[Control] = []   # other controls the touch controls must leave alone
var action_text := ""                 # set: the melt button is a shop button with this word on it
var action_sub := ""                  # a smaller line under it (the price)
var action_ok := false                # green when pressing it does something

var _stick_finger := NONE
var _stick_origin := Vector2.ZERO
var _stick_pos := Vector2.ZERO
var _look_finger := NONE
var _melt_finger := NONE
var _jump_finger := NONE
var _jump_queued := false
var _action_queued := false
var _last := {}                       # finger index -> last position
var _travel := {}                     # finger index -> distance moved since it touched down


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_watch_browser_touches()


func _notification(what: int) -> void:
	# Fingers lifted while the game is in the background never send a lift-off.
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED \
			or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		release_all()


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


func set_action(text: String, sub: String, ok: bool) -> void:
	if text != action_text or sub != action_sub or ok != action_ok:
		action_text = text
		action_sub = sub
		action_ok = ok
		queue_redraw()


func take_action() -> bool:
	## True once after the shop button was tapped.
	var a := _action_queued
	_action_queued = false
	return a


func release_all() -> void:
	_stick_finger = NONE
	_look_finger = NONE
	_melt_finger = NONE
	_jump_finger = NONE
	_last.clear()
	_travel.clear()
	move_vector = Vector2.ZERO
	melting = false
	jump_held = false
	look_delta = Vector2.ZERO
	_action_queued = false
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
	_drop_lost_fingers(i)
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
		if action_text != "":
			_action_queued = true   # a tap on BUY; the finger can still drag to look
		else:
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
	if i == NONE:
		return
	_last.erase(i)
	_travel.erase(i)
	if i == _melt_finger:
		_melt_finger = NONE
		melting = false
	if i == _jump_finger:
		_jump_finger = NONE
		jump_held = false
	if i == _stick_finger:
		_stick_finger = NONE
		move_vector = Vector2.ZERO
	if i == _look_finger:
		_look_finger = NONE


# --- In the browser: ask the page which fingers are really still down -------------
# Godot only hears about the fingers that changed. If a lift-off gets lost, the
# page's own list of touches (kept up to date by a little listener) still knows,
# so every new touch lets go of fingers that aren't on the glass any more.
const _JS_WATCH := """(function () {
	if (window.__meltTouchWatch) return;
	window.__meltTouchWatch = true;
	window.__meltTouchIds = '';
	var update = function (e) {
		var ids = [];
		for (var k = 0; k < e.touches.length; k++) ids.push(e.touches[k].identifier | 0);
		window.__meltTouchIds = ids.join(',');
	};
	['touchstart', 'touchmove', 'touchend', 'touchcancel'].forEach(function (t) {
		window.addEventListener(t, update, { capture: true, passive: true });
	});
})();"""
var _browser_watch := false


func _watch_browser_touches() -> void:
	if OS.has_feature("web") and ClassDB.class_exists("JavaScriptBridge"):
		JavaScriptBridge.eval(_JS_WATCH, true)
		_browser_watch = true


func _drop_lost_fingers(new_finger: int) -> void:
	if not _browser_watch:
		return
	var ids = JavaScriptBridge.eval("window.__meltTouchIds", true)
	if typeof(ids) != TYPE_STRING:
		return
	var down := {}
	for part in (ids as String).split(",", false):
		down[int(part)] = true
	for f in [_melt_finger, _jump_finger, _stick_finger, _look_finger]:
		if f != NONE and f != new_finger and not down.has(f):
			_release(f)


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
	var base := _stick_origin if _stick_finger != NONE else stick_home()
	var knob := _stick_pos if _stick_finger != NONE else base
	var a := 0.55 if _stick_finger != NONE else 0.28
	draw_circle(base, STICK_RADIUS, Color(1, 1, 1, a * 0.35))
	draw_arc(base, STICK_RADIUS, 0, TAU, 48, Color(1, 1, 1, a), 3.0)
	draw_circle(knob, 34.0, Color(1, 1, 1, a + 0.15))
	if _stick_finger == NONE:
		_label(font, "MOVE", base + Vector2(0, STICK_RADIUS + 26), 20, Color(1, 1, 1, 0.55))
	# Melt button (or the shop button in the shed)
	var mc := melt_center()
	if action_text != "":
		var col := Color(0.2, 0.6, 0.3, 0.92) if action_ok else Color(0.42, 0.39, 0.36, 0.82)
		draw_circle(mc, MELT_RADIUS, col)
		draw_arc(mc, MELT_RADIUS, 0, TAU, 48, Color(1, 1, 1, 0.9), 4.0)
		var big := 40 if action_text.length() <= 4 else 30
		_label(font, action_text, mc + Vector2(0, -12 if action_sub != "" else 0), big, Color.WHITE)
		if action_sub != "":
			_label(font, action_sub, mc + Vector2(0, 34), 24, Color.WHITE)
	else:
		var hot := Color(1.0, 0.45, 0.12, 0.9 if melting else 0.6)
		draw_circle(mc, MELT_RADIUS, hot)
		draw_arc(mc, MELT_RADIUS, 0, TAU, 48, Color(1, 0.9, 0.7, 0.9), 4.0)
		_label(font, "🔥", mc + Vector2(0, -14), 52, Color.WHITE)
		_label(font, "HOLD TO MELT", mc + Vector2(0, 46), 19, Color.WHITE)
	# Jump / jetpack button, with the fuel gauge around it
	var jc := jump_center()
	draw_circle(jc, JUMP_RADIUS, Color(0.3, 0.55, 0.9, 0.75 if _jump_finger != NONE else 0.5))
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
