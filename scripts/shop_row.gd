class_name ShopRow
extends PanelContainer
## One row in a shop list: icon, title, description, and a buy button.

var icon_label: Label
var title_label: Label
var desc_label: Label
var button: Button


func setup(icon: String, title: String, desc: String) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.14, 0.2, 0.34)
	sb.set_corner_radius_all(14)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	add_theme_stylebox_override("panel", sb)
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
	v.add_child(title_label)
	desc_label = Label.new()
	desc_label.text = desc
	desc_label.add_theme_font_size_override("font_size", 20)
	desc_label.add_theme_color_override("font_color", Color(0.7, 0.78, 0.9))
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_label.custom_minimum_size = Vector2(300, 0)
	v.add_child(desc_label)

	button = Button.new()
	button.custom_minimum_size = Vector2(190, 76)
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.text = ""
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
