class_name Hud
extends CanvasLayer
## Everything drawn over the 3D view: meltwater, glacier progress, crosshair,
## phone controls, toasts, the card for whatever you're looking at in the shed,
## the catalogue, and popups. Built in code.

const PAPER := Color(0.97, 0.93, 0.83)
const INK := Color(0.27, 0.16, 0.09)
const INK_SOFT := Color(0.45, 0.34, 0.25)
const BROWN := Color(0.45, 0.29, 0.17)

signal respawn_requested

var player: Player
var grid: IceField
var touch: TouchControls
var touch_mode := false
var catalogue_open := false

var root: Control
var water_label: Label
var rate_label: Label
var ice_label: Label
var ice_bar: ProgressBar
var target_label: Label
var tool_label: Label
var boost_button: Button
var boost_label: Label
var respawn_button: Button
var fuel_bar: ProgressBar
var hint_label: Label
var coach_label: Label
var crosshair: Crosshair
var toast_box: VBoxContainer
var popups: Control
var rotate_overlay: Control
var shop_card: PanelContainer      # what you're looking at in the shed, and its price

var _card_title: Label
var _card_body: Label
var _card_price: Label
var _card_stamp: PanelContainer
var _card_footer: Label
var _catalogue: Control
var _list_box: VBoxContainer
var _cat_water: Label
var _row_refreshers: Array = []
var _refresh_timer := 0.0
var _far_check_timer := 0.0
var _too_far := false
var _ending_shown := false
var find_hint: Callable                # World.find_hint_at: a find frozen near this spot, or -1
var _find_card: Control


class Crosshair:
	extends Control
	var hit := false
	var spin := 0.0
	var hot := false
	var far := false

	func _draw() -> void:
		var c := size * 0.5
		var col := Color(1, 1, 1, 0.9) if hit else Color(1, 1, 1, 0.45)
		if far:
			col = Color(1.0, 0.6, 0.6, 0.7)
		draw_arc(c, 11.0, 0, TAU, 32, Color(0, 0, 0, 0.5), 5.0)
		draw_arc(c, 11.0, 0, TAU, 32, col, 2.5)
		draw_circle(c, 2.5, col)
		if hit and hot:
			var ring := Color(1.0, 0.55, 0.15)
			draw_arc(c, 19.0, spin, spin + PI * 0.75, 20, ring, 4.0)
			draw_arc(c, 19.0, spin + PI, spin + PI * 1.75, 20, ring, 4.0)


func _ready() -> void:
	layer = 10
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UiTheme.make_theme()
	add_child(root)
	_build_top()
	_build_center()
	_build_bottom()
	_build_shop_card()
	touch = TouchControls.new()
	root.add_child(touch)
	# Tappable with any finger, even while the other thumb is on the stick.
	touch.buttons = [
		{"control": respawn_button, "action": _on_respawn_pressed},
		{"control": boost_button, "action": _on_boost_pressed},
	]
	toast_box = VBoxContainer.new()
	toast_box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	toast_box.offset_top = 80
	toast_box.offset_left = -400
	toast_box.offset_right = 400
	toast_box.alignment = BoxContainer.ALIGNMENT_BEGIN
	toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(toast_box)
	popups = Control.new()
	popups.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	popups.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(popups)
	_build_rotate_overlay()
	set_touch_mode(DisplayServer.is_touchscreen_available())
	GameState.discovered_item.connect(_on_discovered)
	Monetization.purchase_error.connect(_on_purchase_error)
	Monetization.purchases_changed.connect(_on_purchases_changed)
	Monetization.restore_done.connect(_on_restore_done)


func _on_purchase_error(_id: String, reason: String) -> void:
	toast("Purchase failed: %s" % reason)


func _on_restore_done(found: int, error: String) -> void:
	if error != "":
		toast("Couldn't restore: %s" % error)
	elif found == 0:
		toast("Nothing to restore on this account")
	else:
		toast("Purchases restored ✔️")


func _on_purchases_changed() -> void:
	if catalogue_open:
		_rebuild_catalogue()


func set_coach(text: String) -> void:
	## Onboarding hint above the crosshair ("" hides it).
	var show := text != "" and not catalogue_open and popups.get_child_count() == 0
	coach_label.visible = show
	if coach_label.text != text:
		coach_label.text = text


func set_touch_mode(on: bool) -> void:
	touch_mode = on
	touch.visible = on and not catalogue_open
	hint_label.visible = not on
	# On phones the touch controls tap these (any finger works); the mouse
	# version would also fire from the first finger, so it's switched off.
	for b in touch.buttons:
		(b.control as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE if on else Control.MOUSE_FILTER_STOP


func _on_respawn_pressed() -> void:
	if not is_blocking():
		respawn_requested.emit()


func is_blocking() -> bool:
	## True while the catalogue or a popup needs the mouse.
	return catalogue_open or popups.get_child_count() > 0


# =====================================================================================
# Layout
# =====================================================================================
func _panel(color: Color = Color(0.03, 0.07, 0.16, 0.6)) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UiTheme.flat(color, 16, 14))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


func _label(size: int, color: Color = Color.WHITE, outline: int = 6) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_constant_override("outline_size", outline)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _build_top() -> void:
	var left := PanelContainer.new()
	left.add_theme_stylebox_override("panel", UiTheme.wood_sign())
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.position = Vector2(10, 8)
	root.add_child(left)
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 0)
	left.add_child(lv)
	water_label = _label(38)
	UiTheme.outlined(water_label, 38)
	lv.add_child(water_label)
	rate_label = _label(17, Color(1.0, 0.88, 0.68), 6)
	lv.add_child(rate_label)

	respawn_button = Button.new()
	respawn_button.text = "🏠 Stuck? Respawn"
	respawn_button.position = Vector2(14, 132)
	respawn_button.custom_minimum_size = Vector2(0, 52)
	respawn_button.add_theme_font_size_override("font_size", 21)
	UiTheme.colored_button(respawn_button, Color(0.5, 0.62, 0.72))
	respawn_button.pressed.connect(_on_respawn_pressed)
	root.add_child(respawn_button)

	var mid := VBoxContainer.new()
	mid.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	mid.offset_left = -220
	mid.offset_right = 220
	mid.offset_top = 16
	mid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(mid)
	ice_label = _label(21)
	UiTheme.outlined(ice_label, 21, UiTheme.CREAM, 7)
	ice_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mid.add_child(ice_label)
	ice_bar = ProgressBar.new()
	ice_bar.show_percentage = false
	ice_bar.max_value = 1.0
	ice_bar.custom_minimum_size = Vector2(440, 24)
	UiTheme.bar_styles(ice_bar, Color(0.62, 0.88, 1.0))
	ice_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mid.add_child(ice_bar)

	var right := HBoxContainer.new()
	right.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	right.offset_left = -360
	right.offset_right = -16
	right.offset_top = 14
	right.alignment = BoxContainer.ALIGNMENT_END
	right.add_theme_constant_override("separation", 10)
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(right)
	boost_label = _label(20, Color(1.0, 0.8, 0.4))
	UiTheme.outlined(boost_label, 21, Color(1.0, 0.8, 0.4), 7)
	right.add_child(boost_label)
	boost_button = Button.new()
	boost_button.text = "📺 2x heat"
	boost_button.custom_minimum_size = Vector2(150, 60)
	UiTheme.colored_button(boost_button, Color(0.95, 0.55, 0.2))
	boost_button.pressed.connect(_on_boost_pressed)
	right.add_child(boost_button)


func _build_center() -> void:
	crosshair = Crosshair.new()
	crosshair.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	crosshair.offset_left = -30
	crosshair.offset_right = 30
	crosshair.offset_top = -30
	crosshair.offset_bottom = 30
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(crosshair)
	target_label = _label(20)
	UiTheme.outlined(target_label, 21, UiTheme.CREAM, 7)
	target_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	target_label.offset_left = -250
	target_label.offset_right = 250
	target_label.offset_top = 34
	target_label.offset_bottom = 64
	target_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(target_label)
	coach_label = _label(26, Color(1.0, 0.93, 0.6), 10)
	UiTheme.outlined(coach_label, 28, Color(1.0, 0.92, 0.6), 10)
	coach_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	coach_label.offset_left = -420
	coach_label.offset_right = 420
	coach_label.offset_top = -160
	coach_label.offset_bottom = -60
	coach_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	coach_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	coach_label.visible = false
	root.add_child(coach_label)


func _build_bottom() -> void:
	tool_label = _label(22)
	UiTheme.outlined(tool_label, 24, UiTheme.CREAM, 8)
	tool_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	tool_label.offset_left = -300
	tool_label.offset_right = 300
	tool_label.offset_top = -46
	tool_label.offset_bottom = -14
	tool_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(tool_label)

	fuel_bar = ProgressBar.new()
	fuel_bar.show_percentage = false
	fuel_bar.max_value = 1.0
	fuel_bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	fuel_bar.offset_left = -60
	fuel_bar.offset_right = 60
	fuel_bar.offset_top = 66
	fuel_bar.offset_bottom = 82
	UiTheme.bar_styles(fuel_bar, Color(0.5, 0.92, 1.0))
	fuel_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fuel_bar.visible = false
	root.add_child(fuel_bar)

	hint_label = _label(18, Color(1, 1, 1, 0.85))
	hint_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	hint_label.offset_left = -400
	hint_label.offset_right = 400
	hint_label.offset_top = 80
	hint_label.offset_bottom = 140
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.text = "Click to play\nWASD move · mouse look · hold left click to melt · Space jump (hold to fly)\nWalk into the 🏠 shed to shop · R respawn · Esc frees the mouse"
	root.add_child(hint_label)


func _build_rotate_overlay() -> void:
	rotate_overlay = ColorRect.new()
	(rotate_overlay as ColorRect).color = Color(0.04, 0.07, 0.15, 0.97)
	rotate_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rotate_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	rotate_overlay.visible = false
	root.add_child(rotate_overlay)
	var l := _label(84)
	l.text = "📱🔄\n\nTurn your phone sideways\nto play"
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rotate_overlay.add_child(l)


# =====================================================================================
# Per-frame
# =====================================================================================
func _process(delta: float) -> void:
	var vp := root.get_viewport_rect().size
	rotate_overlay.visible = touch_mode and vp.x < vp.y
	if player == null:
		return
	var t: Dictionary = player.target
	crosshair.hit = t.hit or shop_card.visible
	crosshair.hot = player.melting and not shop_card.visible
	crosshair.spin = fmod(crosshair.spin + delta * 7.0, TAU)
	crosshair.far = _too_far and not t.hit
	crosshair.queue_redraw()
	fuel_bar.visible = not touch_mode and player.fuel < 0.999 and not catalogue_open
	fuel_bar.value = player.fuel
	_far_check_timer += delta
	if _far_check_timer >= 0.2:
		_far_check_timer = 0.0
		_too_far = false
		if not t.hit and grid != null:
			_too_far = player.ray(80.0).hit
	_refresh_timer += delta
	if _refresh_timer >= 0.15:
		_refresh_timer = 0.0
		_refresh()


func _refresh() -> void:
	# Toasts go under the find card while it's up.
	var top := 80.0
	if _find_card != null and is_instance_valid(_find_card) and _find_card.is_inside_tree():
		top = _find_card.offset_top + _find_card.size.y + 8.0
	toast_box.offset_top = top
	water_label.text = "💧 " + Fmt.num(GameState.water)
	var rate := GameState.total_helper_power()
	rate_label.text = "Helpers: %s hp/s" % Fmt.num(rate) if rate > 0.0 else "Melt ice, sell the water"
	var left := grid.fraction_left() if grid != null else 1.0
	ice_bar.value = 1.0 - left
	if GameState.has_won:
		ice_label.text = "The lake is free. Summer is back! ☀️"
	else:
		var what: String = str(grid.spec.get("title", "Glacier")) if grid != null else "Glacier"
		ice_label.text = "%s: %d%% melted  ·  %s m³ of ice left" % [what, int(floor((1.0 - left) * 100.0)), Fmt.num(grid.volume_left())]
	var t: Dictionary = player.target
	if shop_card.visible:
		target_label.text = ""
	elif t.hit:
		var g: IceField = t.grid
		var l := g.layer_at(t.pos - t.normal * 0.3)
		target_label.text = "%s  ·  💧%s per m³" % [g.layer_name(l), Fmt.num(GameState.layer_value(g, l))]
		var near: int = find_hint.call(t.pos) if find_hint.is_valid() else -1
		if near >= 0:
			target_label.text += "\n" + _tease(near)
	elif _too_far:
		target_label.text = "Too far away. Walk closer"
	else:
		target_label.text = ""
	var td: Dictionary = GameState.tool_def()
	tool_label.text = "%s %s" % [td.icon, td.name]
	if GameState.is_boost_active():
		boost_label.text = "🔥 2x " + Fmt.duration(GameState.boost_seconds_left())
	else:
		boost_label.text = ""
	respawn_button.visible = not catalogue_open and popups.get_child_count() == 0
	hint_label.visible = not touch_mode and not catalogue_open and popups.get_child_count() == 0 \
		and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED
	if catalogue_open:
		_cat_water.text = "You have 💧 " + Fmt.num(GameState.water)
		for r in _row_refreshers:
			r.call()


# =====================================================================================
# Toasts
# =====================================================================================
func toast(text: String) -> void:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UiTheme.paper(18.0))
	p.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 22)
	l.add_theme_color_override("font_color", INK)
	p.add_child(l)
	toast_box.add_child(p)
	while toast_box.get_child_count() > 2:
		var old := toast_box.get_child(0)
		toast_box.remove_child(old)
		old.queue_free()
	var tw := p.create_tween()
	tw.tween_interval(2.6)
	tw.tween_property(p, "modulate:a", 0.0, 0.5)
	tw.tween_callback(p.queue_free)


func _on_discovered(i: int, value: float) -> void:
	show_find(i, value)


static func _tease(d: int) -> String:
	## What the hint says about a find you haven't dug up yet (it gives away
	## how special it is, not what it is).
	match int(Balance.DISCOVERIES[d].get("rarity", 0)):
		0, 1:
			return "❓ Something's frozen in here!"
		2:
			return "❓ Something rare is frozen in here!"
		3:
			return "✨ Something BIG is frozen in here!"
		_:
			return "🌟 Something amazing is frozen in here!"


func show_find(i: int, value: float) -> void:
	## A find just melted out: a big card at the top for a few seconds (play
	## goes on), saying how rare it is and what's still out there.
	var d: Dictionary = Balance.DISCOVERIES[i]
	var rarity := int(d.get("rarity", 0))
	var rar: Dictionary = Balance.rarity(i)
	if _find_card != null and is_instance_valid(_find_card):
		_find_card.queue_free()
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UiTheme.paper(14.0))
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.anchor_left = 0.5
	card.anchor_right = 0.5
	card.offset_left = -310
	card.offset_right = 310
	card.offset_top = 76   # just under the ice bar, clear of the crosshair (the find is there)
	card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(v)
	var tier_text := "%s FIND" % str(rar.name).to_upper()
	if rarity >= 4:
		tier_text = "🌟 %s! 🌟" % tier_text
	elif rarity >= 2:
		tier_text = "✨ %s ✨" % tier_text
	var tier := _card_line(tier_text, 20, rar.color)
	UiTheme.outlined(tier, 20, rar.color, 5)
	v.add_child(tier)
	var title := _card_line("%s %s" % [d.icon, d.name], 34, INK)
	title.add_theme_font_override("font", UiTheme.display_font())
	v.add_child(title)
	var line := _card_line("“%s”   +💧 %s" % [d.flavor, Fmt.num(value)], 19, INK_SOFT)
	v.add_child(line)
	var next := _card_line(_whats_next(i), 16, BROWN)
	next.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	next.custom_minimum_size = Vector2(580, 0)
	v.add_child(next)
	root.add_child(card)
	root.move_child(card, popups.get_index())   # popups stay on top
	_find_card = card
	card.modulate.a = 0.0
	card.scale = Vector2(0.85, 0.85)
	card.pivot_offset = Vector2(310, 50)
	var tw := card.create_tween()
	tw.set_parallel(true)
	tw.tween_property(card, "modulate:a", 1.0, 0.18)
	tw.tween_property(card, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.chain().tween_interval(3.2 + 0.7 * rarity)
	tw.chain().tween_property(card, "modulate:a", 0.0, 0.5)
	tw.chain().tween_callback(card.queue_free)


func _card_line(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func _whats_next(i: int) -> String:
	## "3 of 11 found in the village glacier. Something rare is still frozen
	## down in the Glacial Ice…"
	var g := int(Balance.DISCOVERIES[i].glacier)
	var finds := Balance.finds_in(g)
	var found := 0
	var next := -1
	for d in finds:
		if GameState.discovered[d]:
			found += 1
		elif next < 0 or int(Balance.DISCOVERIES[d].layer) < int(Balance.DISCOVERIES[next].layer):
			next = d
	var field: IceField = GameState.grids[g] if g < GameState.grids.size() else null
	var where: String = field.spec.name if field != null else "this glacier"
	var text := "%d of %d found in %s." % [found, finds.size(), where]
	if next >= 0:
		var what := "Something"
		match int(Balance.DISCOVERIES[next].get("rarity", 0)):
			2:
				what = "Something rare"
			3:
				what = "Something big"
			4:
				what = "Something legendary"
		var layer: String = field.layer_name(int(Balance.DISCOVERIES[next].layer)) if field != null else "ice"
		text += " %s is still frozen down in the %s…" % [what, layer]
	elif g + 1 < GameState.grids.size():
		text += " That's all of them here. Who knows what's waiting in %s…" % GameState.grids[g + 1].spec.name
	else:
		text += " You found every last one!"
	return text


func _on_boost_pressed() -> void:
	Monetization.show_rewarded(Monetization.PLACEMENT_BOOST, func(ok: bool):
		if ok:
			GameState.start_boost()
			toast("🔥 2x heat for 5 minutes!")
		else:
			toast("No reward this time"))


# =====================================================================================
# The shed: a card for whatever you're looking at, and the catalogue
# =====================================================================================
func _paper(bg: Color, border: int, radius: int, margin: int) -> StyleBoxFlat:
	var sb := UiTheme.flat(bg, radius, margin)
	sb.border_color = BROWN
	sb.set_border_width_all(border)
	sb.shadow_color = Color(0, 0, 0, 0.3)
	sb.shadow_size = 6
	sb.shadow_offset = Vector2(0, 3)
	return sb


func _ink(size: int, color: Color = INK) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _build_shop_card() -> void:
	## A paper price tag at the bottom of the screen: name, what it does, price.
	shop_card = PanelContainer.new()
	shop_card.add_theme_stylebox_override("panel", UiTheme.paper(20.0))
	shop_card.anchor_left = 0.5
	shop_card.anchor_right = 0.5
	shop_card.anchor_top = 1.0
	shop_card.anchor_bottom = 1.0
	shop_card.offset_left = -340
	shop_card.offset_right = 340
	shop_card.offset_top = -14
	shop_card.offset_bottom = -14
	shop_card.grow_vertical = Control.GROW_DIRECTION_BEGIN
	shop_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shop_card.visible = false
	root.add_child(shop_card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shop_card.add_child(v)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(head)
	_card_title = _ink(30)
	_card_title.add_theme_font_override("font", UiTheme.display_font())
	_card_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_card_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(_card_title)
	_card_stamp = PanelContainer.new()
	_card_stamp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card_stamp.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_card_stamp)
	_card_price = _ink(26, Color.WHITE)
	UiTheme.outlined(_card_price, 26, UiTheme.CREAM, 6)
	_card_stamp.add_child(_card_price)
	_card_body = _ink(21, INK_SOFT)
	_card_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_card_body.custom_minimum_size = Vector2(640, 0)
	v.add_child(_card_body)
	_card_footer = _ink(18, BROWN)
	_card_footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.add_child(_card_footer)


func set_shop_info(info: Dictionary) -> void:
	## The world calls this every frame with what the crosshair is on in the
	## shed (see Shed.describe), or {} for nothing.
	var show := not info.is_empty() and not is_blocking()
	if shop_card.visible != show:
		shop_card.visible = show
		tool_label.visible = not show
	if not show:
		touch.set_action("", "", false)
		return
	var title: String = info.title
	var body: String = info.body
	var price: String = info.price
	var action: String = info.action
	var can: bool = info.can
	if _card_title.text != title:
		_card_title.text = title
	if _card_body.text != body:
		_card_body.text = body
	_card_stamp.visible = price != ""
	if _card_price.text != price:
		_card_price.text = price
	var buying := action in ["BUY", "HIRE", "ADOPT", "UPGRADE", "WAKE UP"]
	var stamp := Color(0.5, 0.47, 0.42)
	if can:
		stamp = Color(0.2, 0.52, 0.27)
	elif buying:
		stamp = Color(0.66, 0.3, 0.2)
	elif action == "OWNED" or action == "IN USE" or action == "MAXED":
		stamp = Color(0.33, 0.5, 0.37)
	_card_stamp.add_theme_stylebox_override("panel", UiTheme.enamel(stamp))
	var foot := ""
	if buying and not can:
		foot = "Not enough 💧 yet"
	elif can and not touch_mode:
		foot = "Click (or press E) to %s" % action.to_lower()
	_card_footer.visible = foot != ""
	if _card_footer.text != foot:
		_card_footer.text = foot
	touch.set_action(action, price if buying else "", can)


func open_catalogue() -> void:
	## The mail-order catalogue on the table by the shed door: the boost, the
	## purchases, and in playtest builds the developer tools.
	if catalogue_open:
		return
	catalogue_open = true
	shop_card.visible = false
	tool_label.visible = true
	coach_label.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	player.input_enabled = false
	touch.release_all()
	touch.visible = false
	_catalogue = ColorRect.new()
	(_catalogue as ColorRect).color = Color(0.05, 0.03, 0.02, 0.55)
	_catalogue.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_catalogue.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(_catalogue)
	root.move_child(_catalogue, popups.get_index())   # popups stay on top

	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 70
	panel.offset_right = -70
	panel.offset_top = 26
	panel.offset_bottom = -26
	panel.add_theme_stylebox_override("panel", _paper(PAPER, 5, 12, 22))
	_catalogue.add_child(panel)
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
	var title := _ink(38)
	title.text = "📖 The Catalogue"
	titles.add_child(title)
	var sub := _ink(19, INK_SOFT)
	sub.text = "Mail-order goods for the serious glacier melter"
	titles.add_child(sub)
	_cat_water = _ink(26)
	_cat_water.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_cat_water)
	var close := Button.new()
	close.text = "Close"
	close.custom_minimum_size = Vector2(170, 60)
	UiTheme.colored_button(close, BROWN)
	close.pressed.connect(close_catalogue)
	head.add_child(close)
	var rule := ColorRect.new()
	rule.color = BROWN
	rule.custom_minimum_size = Vector2(0, 3)
	v.add_child(rule)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(scroll)
	_list_box = VBoxContainer.new()
	_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_box.add_theme_constant_override("separation", 8)
	scroll.add_child(_list_box)
	_rebuild_catalogue()
	_refresh()


func close_catalogue() -> void:
	if not catalogue_open:
		return
	catalogue_open = false
	_row_refreshers.clear()
	if _catalogue != null:
		_catalogue.queue_free()
		_catalogue = null
		_list_box = null
	if popups.get_child_count() == 0:
		player.input_enabled = true
		touch.visible = touch_mode
	GameState.save_game()


func _rebuild_catalogue() -> void:
	if _list_box == null or not catalogue_open:
		return
	for c in _list_box.get_children():
		c.queue_free()
	_row_refreshers.clear()
	_build_catalogue_rows()
	for r in _row_refreshers:
		r.call()


func _row(icon: String, title: String, desc: String) -> ShopRow:
	var row := ShopRow.new()
	row.setup(icon, title, desc, true)
	_list_box.add_child(row)
	return row


func _build_catalogue_rows() -> void:
	var boost := _row("📺", "2x Heat Boost", "Watch an ad: everything melts 2x faster for 5 min. Stacks to 15 min.")
	boost.set_button("Watch", true)
	boost.button.pressed.connect(_on_boost_pressed)
	for id in Monetization.PRODUCTS:
		var p: Dictionary = Monetization.PRODUCTS[id]
		var pid: String = id
		var icon := "🚫" if pid == Monetization.PRODUCT_REMOVE_ADS_2X else "✨"
		var desc := "No interstitial ads, and everything melts 2x forever." if pid == Monetization.PRODUCT_REMOVE_ADS_2X \
			else "A gold hair dryer. Purely cosmetic, purely fabulous."
		var row := _row(icon, p.title, desc)
		_row_refreshers.append(func():
			if Monetization.owns(pid):
				row.set_button("Owned ✔️", false)
			else:
				row.set_button(Monetization.price(pid), true))
		row.button.pressed.connect(func(): Monetization.buy(pid))
	if GameState.owns_golden_dryer:
		var g := _row("🎨", "Golden hair dryer", "Show the gold version of the hair dryer.")
		_row_refreshers.append(func(): g.set_button("On" if GameState.golden_equipped else "Off", true))
		g.button.pressed.connect(func(): GameState.golden_equipped = not GameState.golden_equipped)
	var restore := _row("🔄", "Restore purchases", "Re-download what you already bought.")
	restore.set_button("Restore", true)
	restore.button.pressed.connect(func():
		Monetization.restore()
		toast("Checking the store..."))
	if Monetization.privacy_options_required():
		var privacy := _row("🛡️", "Ad privacy choices", "Change what you agreed to about ads.")
		privacy.set_button("Change", true)
		privacy.button.pressed.connect(Monetization.show_privacy_options)
	var policy := _row("📄", "Privacy policy", "What the game collects (only what ads and the store need).")
	policy.set_button("Read", true)
	policy.button.pressed.connect(func(): OS.shell_open(StoreConfig.PRIVACY_POLICY_URL))

	# Dev tools: in the editor, and in exports tagged "playtest" (the web build).
	# Remove the tag from export_presets.cfg before shipping.
	if OS.is_debug_build() or OS.has_feature("playtest"):
		var title := _ink(22, Color(0.7, 0.2, 0.15))
		title.text = "Developer tools (playtest builds only)"
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_list_box.add_child(title)
		var cash := _row("💰", "Free meltwater", "Adds 10x your current water (at least 1K).")
		cash.set_button("Add", true)
		cash.button.pressed.connect(func(): GameState.grant_water(maxf(1000.0, GameState.water * 10.0)))
		var speed := _row("⏩", "Melting speed", "Multiplies all melting, for testing.")
		_row_refreshers.append(func(): speed.set_button("x%d" % int(GameState.debug_speed), true))
		speed.button.pressed.connect(func():
			GameState.debug_speed = 1.0 if GameState.debug_speed >= 100.0 else GameState.debug_speed * 10.0)
		var melt := _row("☀️", "Melt this glacier", "Skip to the next glacier (or the ending).")
		melt.set_button("Melt", true)
		melt.button.pressed.connect(func():
			close_catalogue()
			GameState.grid.melt_everything())
		var wipe := _row("🗑️", "Start over", "New glacier, keeps purchases.")
		wipe.set_button("Wipe", true)
		wipe.button.pressed.connect(func():
			GameState.wipe_save()
			get_tree().reload_current_scene())


# =====================================================================================
# Popups
# =====================================================================================
func _popup(title: String, body: String) -> Dictionary:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	player.input_enabled = false
	touch.release_all()
	touch.visible = false
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	popups.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(620, 0)
	panel.add_theme_stylebox_override("panel", UiTheme.paper(34.0))
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	panel.add_child(v)
	var t := Label.new()
	t.text = title
	t.add_theme_font_override("font", UiTheme.display_font())
	t.add_theme_font_size_override("font_size", 44)
	t.add_theme_color_override("font_color", Color(0.75, 0.24, 0.16))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var b := Label.new()
	b.text = body
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.custom_minimum_size = Vector2(560, 0)
	b.add_theme_color_override("font_color", INK)
	v.add_child(b)
	return {"root": dim, "box": v}


func _popup_button(p: Dictionary, text: String, color: Color, cb: Callable) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(0, 66)
	btn.add_theme_font_size_override("font_size", 28)
	UiTheme.colored_button(btn, color, 16)
	btn.pressed.connect(cb)
	p.box.add_child(btn)
	return btn


func _close_popup(p: Dictionary) -> void:
	var r: Control = p.root
	popups.remove_child(r)
	r.queue_free()
	if popups.get_child_count() == 0 and not catalogue_open:
		player.input_enabled = true
		touch.visible = touch_mode


func show_stage_done(stage: int) -> void:
	## A glacier is gone and the next one opens up (so far: the village is free,
	## on to the frozen lake).
	if catalogue_open:
		close_catalogue()
	var next: String = str(GameState.grids[stage].spec.get("name", "the next glacier")) if stage < GameState.grids.size() else "the next glacier"
	var body := "Everyone's home again, and your helpers have earned a holiday: they're partying in the village square.\n\nBut look past the fence. The whole lake froze solid, and the gate is open now.\nHire a new crew at the shed and go melt %s!" % next
	var p := _popup("🏘️ The village is free! 🎉", body)
	_popup_button(p, "To the lake!", Color(0.25, 0.5, 0.85), func(): _close_popup(p))


func show_ending() -> void:
	if _ending_shown:
		return
	_ending_shown = true
	if catalogue_open:
		close_catalogue()
	var found := 0
	for d in GameState.discovered:
		if d:
			found += 1
	var body := "The last chunk dripped away and the lake is free.\nSummer is back!\n\n⏱ %s played\n🧊 %s m³ of ice melted\n💧 %s meltwater earned\n🏺 %d/%d finds\n\n(Screenshot this!)" % [
		Fmt.duration(GameState.play_time), Fmt.num(GameState.melted_cubic_metres()), Fmt.num(GameState.lifetime_water),
		found, Balance.DISCOVERIES.size()]
	var p := _popup("☀️ THE END ☀️", body)
	_popup_button(p, "Walk around the village", Color(0.36, 0.6, 0.86), func(): _close_popup(p))
	_popup_button(p, "Melt a new glacier", Color(0.95, 0.55, 0.2), func():
		GameState.wipe_save()
		get_tree().reload_current_scene())
