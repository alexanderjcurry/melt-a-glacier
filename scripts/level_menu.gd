class_name LevelMenu
extends ColorRect
## Where to next: every map on one sheet of paper, shown after the ending (and
## from the catalogue once you've won). The valley you just melted can be
## played again; the rest are on their way and stamped COMING SOON, to show
## what's coming (Levels.MAPS). Hud.show_levels() puts it in the HUD's popups,
## so the game waits while it's up, and takes it away again on `closed`.

signal closed

const CARD_SIZE := Vector2(252, 200)
const GAP := 14
const PER_ROW := 4
const PAPER := Color(0.97, 0.93, 0.83)
const CARD_PAPER := Color(1.0, 0.98, 0.92)
const CARD_LATER := Color(0.92, 0.89, 0.83)
const INK := Color(0.27, 0.16, 0.09)
const INK_SOFT := Color(0.45, 0.34, 0.25)
const BROWN := Color(0.45, 0.29, 0.17)
const GREEN := Color(0.2, 0.5, 0.25)
const ORANGE := Color(0.95, 0.55, 0.2)
const STAMP_RED := Color(0.78, 0.18, 0.14)

var cards: Array[Control] = []   # one per map, in Levels.MAPS order
var _note: Label                 # a line under the cards: what you tapped


func _init() -> void:
	color = Color(0.05, 0.03, 0.02, 0.55)
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()


func close() -> void:
	closed.emit()


func _build() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 50
	panel.offset_right = -50
	panel.offset_top = 16
	panel.offset_bottom = -16
	panel.add_theme_stylebox_override("panel", _paper(PAPER, 5, 12, 20))
	add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 16)
	v.add_child(head)
	var titles := VBoxContainer.new()
	titles.add_theme_constant_override("separation", 0)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(titles)
	var title := _ink(34)
	title.text = "🗺️ Where to next?"
	titles.add_child(title)
	var sub := _ink(19, INK_SOFT)
	sub.text = "More glaciers are on their way. Here's what's coming!"
	titles.add_child(sub)
	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(170, 60)
	UiTheme.colored_button(back, BROWN)
	back.pressed.connect(close)
	head.add_child(back)
	var rule := ColorRect.new()
	rule.color = BROWN
	rule.custom_minimum_size = Vector2(0, 3)
	v.add_child(rule)

	# The maps, PER_ROW to a row, each row centred.
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rows.alignment = BoxContainer.ALIGNMENT_CENTER
	rows.add_theme_constant_override("separation", GAP)
	scroll.add_child(rows)
	var row: HBoxContainer
	for i in Levels.MAPS.size():
		if i % PER_ROW == 0:
			row = HBoxContainer.new()
			row.alignment = BoxContainer.ALIGNMENT_CENTER
			row.add_theme_constant_override("separation", GAP)
			rows.add_child(row)
		var card := _card(i)
		cards.append(card)
		row.add_child(card)
	_note = _ink(18, INK_SOFT)
	_note.text = "Tap a glacier to take a look."
	_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_note)


func _card(i: int) -> Control:
	## A postcard for one map: its picture, name and a line about it. The valley
	## has a button to melt it again; the others get a COMING SOON stamp.
	var m: Dictionary = Levels.MAPS[i]
	var ready: bool = m.get("ready", false)
	var card := PanelContainer.new()
	card.custom_minimum_size = CARD_SIZE
	card.add_theme_stylebox_override("panel", _paper(CARD_PAPER if ready else CARD_LATER, 3, 10, 12))
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(v)
	var icon := _ink(40)
	icon.text = str(m.icon)
	icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if not ready:
		icon.modulate = Color(1, 1, 1, 0.6)   # still frozen over
	v.add_child(icon)
	var name := _ink(21, BROWN if ready else INK_SOFT)
	name.add_theme_font_override("font", UiTheme.display_font())
	name.text = str(m.name)
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(name)
	var blurb := _ink(15, INK_SOFT)
	blurb.text = str(m.blurb)
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blurb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	blurb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(blurb)
	if ready:
		var done := _ink(16, GREEN)
		done.text = ("✔️ Melted in %s" % Fmt.duration(GameState.play_time)) if GameState.has_won else "📍 You're here"
		done.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(done)
		var again := Button.new()
		again.name = "Play"
		again.text = "Melt it again" if GameState.has_won else "Start over"
		again.custom_minimum_size = Vector2(0, 48)
		again.add_theme_font_size_override("font_size", 20)
		UiTheme.colored_button(again, ORANGE)
		again.pressed.connect(_play)
		v.add_child(again)
		card.gui_input.connect(func(e: InputEvent):
			if _is_tap(e):
				_note.text = "%s %s: melt it all again, from a fresh glacier." % [m.icon, m.name])
	else:
		var stamp := _stamp(i)
		v.add_child(stamp)
		card.gui_input.connect(func(e: InputEvent):
			if _is_tap(e):
				_note.text = "%s %s is still freezing over. Coming soon!" % [m.icon, m.name]
				_thump(stamp.get_child(0) as Control))
	return card


func _play() -> void:
	## Melt the valley again from a fresh glacier (purchases are kept).
	GameState.wipe_save()
	get_tree().reload_current_scene()


func _stamp(i: int) -> Control:
	## A red rubber stamp, put on a bit crooked. (It sits in a plain Control, not
	## a container: containers straighten their children out.)
	var holder := Control.new()
	holder.name = "Stamp"
	holder.custom_minimum_size = Vector2(0, 46)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var stamp := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(STAMP_RED, 0.06)
	sb.border_color = Color(STAMP_RED, 0.85)
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 1
	sb.content_margin_bottom = 1
	stamp.add_theme_stylebox_override("panel", sb)
	stamp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := Label.new()
	l.text = "COMING SOON"
	l.add_theme_font_override("font", UiTheme.display_font())
	l.add_theme_font_size_override("font_size", 24)
	l.add_theme_color_override("font_color", Color(STAMP_RED, 0.9))
	stamp.add_child(l)
	stamp.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	stamp.grow_horizontal = Control.GROW_DIRECTION_BOTH
	stamp.grow_vertical = Control.GROW_DIRECTION_BOTH
	stamp.rotation_degrees = [-9.0, -6.0, -11.0, -7.0, -10.0, -5.0][i % 6]
	stamp.resized.connect(func(): stamp.pivot_offset = stamp.size * 0.5)
	holder.add_child(stamp)
	return holder


func _thump(stamp: Control) -> void:
	var tw := stamp.create_tween()
	tw.tween_property(stamp, "scale", Vector2(1.18, 1.18), 0.07)
	tw.tween_property(stamp, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


static func _is_tap(e: InputEvent) -> bool:
	## Clicks, and taps on a phone (they come as clicks too).
	return e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT


static func _paper(bg: Color, border: int, radius: int, margin: int) -> StyleBoxFlat:
	var sb := UiTheme.flat(bg, radius, margin)
	sb.border_color = BROWN
	sb.set_border_width_all(border)
	sb.shadow_color = Color(0, 0, 0, 0.3)
	sb.shadow_size = 6
	sb.shadow_offset = Vector2(0, 3)
	return sb


static func _ink(size: int, color: Color = INK) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l
