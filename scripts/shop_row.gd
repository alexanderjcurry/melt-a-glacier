class_name ShopRow
extends PanelContainer
## One row in a shop list: icon, title, description, and a buy button.
## `paper` draws it like a line in a printed catalogue instead.

var icon_label: Label
var title_label: Label
var desc_label: Label
var button: Button
var _normal: StyleBox
var _special: StyleBoxFlat
var _lit := false


func setup(icon: String, title: String, desc: String, paper: bool = false) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.14, 0.2, 0.34)
	sb.set_corner_radius_all(14)
	if paper:
		sb.bg_color = Color(0.93, 0.87, 0.74)
		sb.set_corner_radius_all(8)
		sb.border_color = Color(0.72, 0.6, 0.45)
		sb.border_width_bottom = 2
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	add_theme_stylebox_override("panel", sb)
	_normal = sb
	_special = sb.duplicate()
	_special.bg_color = Color(1.0, 0.9, 0.6)
	_special.border_color = Color(0.75, 0.24, 0.16)
	_special.set_border_width_all(3)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	add_child(h)

	icon_label = Label.new()
	icon_label.text = icon
	icon_label.add_theme_font_size_override("font_size", 44)
	icon_label.custom_minimum_size = Vector2(64, 0)
	icon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(icon_label)

	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 2)
	h.add_child(v)
	title_label = Label.new()
	title_label.text = title
	title_label.add_theme_font_size_override("font_size", 27)
	if paper:
		title_label.add_theme_color_override("font_color", Color(0.27, 0.16, 0.09))
	v.add_child(title_label)
	desc_label = Label.new()
	desc_label.text = desc
	desc_label.add_theme_font_size_override("font_size", 20)
	desc_label.add_theme_color_override("font_color", Color(0.45, 0.34, 0.25) if paper else Color(0.7, 0.78, 0.9))
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_label.custom_minimum_size = Vector2(300, 0)
	v.add_child(desc_label)

	button = Button.new()
	UiTheme.no_keyboard(button)
	button.custom_minimum_size = Vector2(190, 76)
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.text = ""
	if paper:
		UiTheme.colored_button(button, Color(0.38, 0.7, 0.4))
		button.add_theme_stylebox_override("disabled", UiTheme.enamel(Color(0.7, 0.64, 0.56)))
		button.add_theme_color_override("font_disabled_color", Color(0.97, 0.94, 0.88))
	h.add_child(button)


func set_title(t: String) -> void:
	if title_label.text != t:
		title_label.text = t


func set_desc(t: String) -> void:
	if desc_label.text != t:
		desc_label.text = t


func set_button(text: String, enabled: bool) -> void:
	if button.text != text:
		button.text = text
	button.disabled = not enabled


func set_highlight(on: bool) -> void:
	## Marks the row as today's special offer (a warm, gently pulsing card).
	if on != _lit:
		_lit = on
		add_theme_stylebox_override("panel", _special if on else _normal)
	if on:
		var t := Time.get_ticks_msec() / 1000.0
		_special.bg_color = Color(1.0, 0.9, 0.6).lerp(Color(1.0, 0.82, 0.5), 0.5 + 0.5 * sin(t * 3.4))
