class_name UiTheme
extends RefCounted
## Shared look for every menu: fonts (with emoji), colours, rounded buttons.

const EMOJI_FONT_PATH := "res://fonts/NotoColorEmoji-subset.ttf"

static var _soft_dot: Texture2D


static func install_emoji_font() -> void:
	## Emoji are the placeholder art. Make a bundled colour-emoji font a fallback
	## of the default font so every Label, Label3D and draw_string can show them.
	if ThemeDB.fallback_font.fallbacks.size() > 0:
		return   # already installed
	var emoji := load(EMOJI_FONT_PATH) as FontFile
	if emoji == null:
		return
	emoji.fixed_size_scale_mode = TextServer.FIXED_SIZE_SCALE_ENABLED
	var base := ThemeDB.fallback_font.duplicate() as Font
	base.fallbacks = [emoji]
	ThemeDB.fallback_font = base
	ThemeDB.get_default_theme().default_font = base


static func soft_dot() -> Texture2D:
	## A soft round blob for particles (steam, flames, sparks). Built from an
	## Image with mipmaps: a GradientTexture2D rendered some particles black on WebGL.
	if _soft_dot == null:
		var n := 64
		var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
		for y in n:
			for x in n:
				var d := Vector2(x + 0.5 - n * 0.5, y + 0.5 - n * 0.5).length() / (n * 0.5)
				var a := clampf(1.0 - d, 0.0, 1.0)
				img.set_pixel(x, y, Color(1, 1, 1, a * a * (3.0 - 2.0 * a)))
		img.generate_mipmaps()
		_soft_dot = ImageTexture.create_from_image(img)
	return _soft_dot


static func flat(color: Color, radius: int = 12, margin: int = 12) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(radius)
	s.content_margin_left = margin
	s.content_margin_right = margin
	s.content_margin_top = margin * 0.6
	s.content_margin_bottom = margin * 0.6
	return s


static func make_theme() -> Theme:
	var t := Theme.new()
	t.default_font = ThemeDB.fallback_font
	t.default_font_size = 24
	t.set_color("font_color", "Label", Color(0.95, 0.97, 1.0))
	t.set_color("font_outline_color", "Label", Color(0.03, 0.06, 0.14, 0.85))
	t.set_color("font_color", "Button", Color(1, 1, 1))
	t.set_color("font_disabled_color", "Button", Color(0.62, 0.67, 0.75))
	t.set_stylebox("normal", "Button", flat(Color(0.2, 0.45, 0.8), 14))
	t.set_stylebox("hover", "Button", flat(Color(0.25, 0.52, 0.88), 14))
	t.set_stylebox("pressed", "Button", flat(Color(0.15, 0.36, 0.68), 14))
	t.set_stylebox("disabled", "Button", flat(Color(0.2, 0.25, 0.35), 14))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	return t


static func no_keyboard(b: BaseButton) -> void:
	## Buttons are for clicks and taps only. A button the mouse clicked keeps
	## keyboard focus, and Space (jump) or Enter would press it again: letting
	## go of Space after flying hit "Respawn" and sent you back to the start.
	b.focus_mode = Control.FOCUS_NONE


static func colored_button(b: Button, color: Color, radius: int = 14) -> void:
	no_keyboard(b)
	b.add_theme_stylebox_override("normal", flat(color, radius))
	b.add_theme_stylebox_override("hover", flat(color.lightened(0.1), radius))
	b.add_theme_stylebox_override("pressed", flat(color.darkened(0.15), radius))
