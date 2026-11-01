class_name Hud
extends CanvasLayer
## Everything drawn over the 3D view: meltwater, glacier progress, crosshair,
## phone controls, toasts, the shed menu, and popups. Built in code.

const TABS = ["Tools", "Upgrades", "Helpers", "Finds", "Shop"]

signal respawn_requested

var player: Player
var grid: IceGrid
var touch: TouchControls
var touch_mode := false
var near_shed := false
var shed_open := false

var root: Control
var water_label: Label
var rate_label: Label
var ice_label: Label
var ice_bar: ProgressBar
var target_label: Label
var tool_label: Label
var boost_button: Button
var boost_label: Label
var shed_button: Button
var respawn_button: Button
var fuel_bar: ProgressBar
var hint_label: Label
var coach_label: Label
var crosshair: Crosshair
var toast_box: VBoxContainer
var popups: Control
var rotate_overlay: Control

var _shed: Control
var _list_box: VBoxContainer
var _scroll: ScrollContainer
var _shed_water: Label
var _tab := 0
var _tab_buttons: Array = []
var _row_refreshers: Array = []
var _refresh_timer := 0.0
var _far_check_timer := 0.0
var _too_far := false
var _ending_shown := false


class Crosshair:
	extends Control
	var hit := false
	var frac := 1.0
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
		if hit and frac < 0.999:
			var ring := Color(1.0, 0.55, 0.15) if hot else Color(1.0, 0.8, 0.4)
			draw_arc(c, 19.0, -PI / 2.0, -PI / 2.0 + TAU * frac, 40, ring, 4.0)


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
	touch = TouchControls.new()
	root.add_child(touch)
	# Tappable with any finger, even while the other thumb is on the stick.
	touch.buttons = [
		{"control": shed_button, "action": open_shed},
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


func _on_purchase_error(_id: String, reason: String) -> void:
	toast("Purchase failed: %s" % reason)


func _on_purchases_changed() -> void:
	if shed_open:
		_rebuild_list()


func set_coach(text: String) -> void:
	## Onboarding hint above the crosshair ("" hides it).
	var show := text != "" and not shed_open and popups.get_child_count() == 0
	coach_label.visible = show
	if coach_label.text != text:
		coach_label.text = text


func set_touch_mode(on: bool) -> void:
	touch_mode = on
	touch.visible = on and not shed_open
	hint_label.visible = not on
	# On phones the touch controls tap these (any finger works); the mouse
	# version would also fire from the first finger, so it's switched off.
	for b in touch.buttons:
		(b.control as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE if on else Control.MOUSE_FILTER_STOP


func _on_respawn_pressed() -> void:
	if not is_blocking():
		respawn_requested.emit()


func is_blocking() -> bool:
	## True while a menu or popup needs the mouse.
	return shed_open or popups.get_child_count() > 0


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
	var left := _panel()
	left.position = Vector2(16, 14)
	root.add_child(left)
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 0)
	left.add_child(lv)
	water_label = _label(36)
	lv.add_child(water_label)
	rate_label = _label(18, Color(0.7, 0.88, 1.0))
	lv.add_child(rate_label)

	respawn_button = Button.new()
	respawn_button.text = "🏠 Stuck? Respawn"
	respawn_button.position = Vector2(16, 128)
	respawn_button.custom_minimum_size = Vector2(220, 50)
	respawn_button.add_theme_font_size_override("font_size", 20)
	UiTheme.colored_button(respawn_button, Color(0.22, 0.3, 0.45, 0.85), 12)
	respawn_button.pressed.connect(_on_respawn_pressed)
	root.add_child(respawn_button)

	var mid := VBoxContainer.new()
	mid.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	mid.offset_left = -220
	mid.offset_right = 220
	mid.offset_top = 16
	mid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(mid)
	ice_label = _label(20)
	ice_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mid.add_child(ice_label)
	ice_bar = ProgressBar.new()
	ice_bar.show_percentage = false
	ice_bar.max_value = 1.0
	ice_bar.custom_minimum_size = Vector2(440, 14)
	ice_bar.add_theme_stylebox_override("fill", UiTheme.flat(Color(0.55, 0.82, 1.0), 7))
	ice_bar.add_theme_stylebox_override("background", UiTheme.flat(Color(0.05, 0.1, 0.2, 0.7), 7))
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
	right.add_child(boost_label)
	boost_button = Button.new()
	boost_button.text = "📺 2x heat"
	boost_button.custom_minimum_size = Vector2(150, 56)
	UiTheme.colored_button(boost_button, Color(0.85, 0.45, 0.15))
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
	target_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	target_label.offset_left = -250
	target_label.offset_right = 250
	target_label.offset_top = 34
	target_label.offset_bottom = 64
	target_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(target_label)
	coach_label = _label(26, Color(1.0, 0.93, 0.6), 10)
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
	tool_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	tool_label.offset_left = -300
	tool_label.offset_right = 300
	tool_label.offset_top = -46
	tool_label.offset_bottom = -14
	tool_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(tool_label)

	shed_button = Button.new()
	shed_button.text = "🏠  Enter the shed"
	shed_button.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	shed_button.offset_left = -170
	shed_button.offset_right = 170
	shed_button.offset_top = -140
	shed_button.offset_bottom = -64
	shed_button.add_theme_font_size_override("font_size", 28)
	UiTheme.colored_button(shed_button, Color(0.55, 0.36, 0.2), 18)
	shed_button.visible = false
	shed_button.pressed.connect(open_shed)
	root.add_child(shed_button)

	fuel_bar = ProgressBar.new()
	fuel_bar.show_percentage = false
	fuel_bar.max_value = 1.0
	fuel_bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	fuel_bar.offset_left = -60
	fuel_bar.offset_right = 60
	fuel_bar.offset_top = 70
	fuel_bar.offset_bottom = 78
	fuel_bar.add_theme_stylebox_override("fill", UiTheme.flat(Color(0.45, 0.9, 1.0), 4))
	fuel_bar.add_theme_stylebox_override("background", UiTheme.flat(Color(0.05, 0.1, 0.2, 0.6), 4))
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
	hint_label.text = "Click to play\nWASD move · mouse look · hold left click to melt · Space jump (hold to fly)\nE shed · R respawn · Esc frees the mouse"
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
	crosshair.hit = t.hit
	crosshair.hot = player.melting
	if t.hit:
		crosshair.frac = grid.hp_fraction(t.cell)
	crosshair.far = _too_far and not t.hit
	crosshair.queue_redraw()
	fuel_bar.visible = not touch_mode and player.fuel < 0.999 and not shed_open
	fuel_bar.value = player.fuel
	_far_check_timer += delta
	if _far_check_timer >= 0.2:
		_far_check_timer = 0.0
		_too_far = false
		if not t.hit and grid != null:
			_too_far = grid.raycast(player.camera.global_position, player.aim_dir(), 80.0).hit
	_refresh_timer += delta
	if _refresh_timer >= 0.15:
		_refresh_timer = 0.0
		_refresh()


func _refresh() -> void:
	water_label.text = "💧 " + Fmt.num(GameState.water)
	var rate := GameState.total_helper_power()
	rate_label.text = "Helpers: %s hp/s" % Fmt.num(rate) if rate > 0.0 else "Melt ice, sell the water"
	var left := grid.fraction_left() if grid != null else 1.0
	ice_bar.value = 1.0 - left
	if GameState.has_won:
		ice_label.text = "The glacier is gone. Summer is back! ☀️"
	else:
		ice_label.text = "Glacier melted: %d%%  ·  %s blocks left" % [int(floor((1.0 - left) * 100.0)), Fmt.num(float(grid.remaining))]
	var t: Dictionary = player.target
	if t.hit:
		var l := grid.layer_at(t.cell)
		target_label.text = "%s  ·  +%s 💧" % [Balance.LAYERS[l].name, Fmt.num(GameState.block_value(l))]
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
	shed_button.visible = near_shed and not shed_open and popups.get_child_count() == 0
	respawn_button.visible = not shed_open and popups.get_child_count() == 0
	hint_label.visible = not touch_mode and not shed_open and popups.get_child_count() == 0 \
		and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED
	if shed_open:
		_shed_water.text = "💧 " + Fmt.num(GameState.water)
		for r in _row_refreshers:
			r.call()


# =====================================================================================
# Toasts
# =====================================================================================
func toast(text: String) -> void:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UiTheme.flat(Color(0.03, 0.06, 0.14, 0.85), 14, 12))
	p.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 22)
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
	var d: Dictionary = Balance.DISCOVERIES[i]
	toast("%s %s melted out! Sold for 💧%s" % [d.icon, d.name, Fmt.num(value)])
	if shed_open and _tab == 3:
		_rebuild_list()


func _on_boost_pressed() -> void:
	Monetization.show_rewarded(Monetization.PLACEMENT_BOOST, func(ok: bool):
		if ok:
			GameState.start_boost()
			toast("🔥 2x heat for 5 minutes!")
		else:
			toast("No reward this time"))


# =====================================================================================
# The shed
# =====================================================================================
func open_shed() -> void:
	if shed_open:
		return
	shed_open = true
	GameState.tutorial_step = maxi(GameState.tutorial_step, 3)
	coach_label.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	player.input_enabled = false
	touch.release_all()
	touch.visible = false
	_shed = ColorRect.new()
	(_shed as ColorRect).color = Color(0.02, 0.04, 0.1, 0.7)
	_shed.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_shed.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(_shed)
	root.move_child(_shed, popups.get_index())   # popups stay on top

	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 40
	panel.offset_right = -40
	panel.offset_top = 24
	panel.offset_bottom = -24
	panel.add_theme_stylebox_override("panel", UiTheme.flat(Color(0.1, 0.13, 0.22), 22, 20))
	_shed.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 16)
	v.add_child(head)
	var title := Label.new()
	title.text = "🏠 The Shed"
	title.add_theme_font_size_override("font_size", 34)
	head.add_child(title)
	_shed_water = Label.new()
	_shed_water.add_theme_font_size_override("font_size", 30)
	_shed_water.add_theme_color_override("font_color", Color(0.7, 0.9, 1.0))
	_shed_water.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_shed_water.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_child(_shed_water)
	var close := Button.new()
	close.text = "Back to the glacier"
	close.custom_minimum_size = Vector2(260, 58)
	UiTheme.colored_button(close, Color(0.3, 0.36, 0.5))
	close.pressed.connect(close_shed)
	head.add_child(close)

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 4)
	v.add_child(tabs)
	var group := ButtonGroup.new()
	_tab_buttons = []
	for i in TABS.size():
		var b := Button.new()
		b.text = TABS[i]
		b.toggle_mode = true
		b.button_group = group
		b.custom_minimum_size = Vector2(0, 56)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_stylebox_override("normal", UiTheme.flat(Color(0.16, 0.22, 0.36), 12))
		b.add_theme_stylebox_override("hover", UiTheme.flat(Color(0.2, 0.28, 0.44), 12))
		b.add_theme_stylebox_override("pressed", UiTheme.flat(Color(0.28, 0.45, 0.75), 12))
		b.pressed.connect(_select_tab.bind(i))
		tabs.add_child(b)
		_tab_buttons.append(b)

	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(_scroll)
	_list_box = VBoxContainer.new()
	_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_box.add_theme_constant_override("separation", 8)
	_scroll.add_child(_list_box)
	_select_tab(_tab)
	_refresh()


func close_shed() -> void:
	if not shed_open:
		return
	shed_open = false
	_row_refreshers.clear()
	if _shed != null:
		_shed.queue_free()
		_shed = null
	player.input_enabled = true
	touch.visible = touch_mode
	GameState.save_game()
	Monetization.maybe_show_interstitial("shed_exit")


func _select_tab(i: int) -> void:
	_tab = i
	_tab_buttons[i].button_pressed = true
	_rebuild_list()
	_scroll.scroll_vertical = 0


func _rebuild_list() -> void:
	if _list_box == null or not shed_open:
		return
	for c in _list_box.get_children():
		c.queue_free()
	_row_refreshers.clear()
	match _tab:
		0: _build_tools()
		1: _build_upgrades()
		2: _build_helpers()
		3: _build_finds()
		4: _build_shop()
	for r in _row_refreshers:
		r.call()


func _row(icon: String, title: String, desc: String) -> ShopRow:
	var row := ShopRow.new()
	row.setup(icon, title, desc)
	_list_box.add_child(row)
	return row


func _build_tools() -> void:
	for i in Balance.TOOLS.size():
		var t: Dictionary = Balance.TOOLS[i]
		var row := _row(t.icon, t.name, "")
		var stats := "%s  ·  power %s, zone %.1f m, reach %.1f m" % [t.desc, Fmt.num(t.power), t.radius, t.range]
		_row_refreshers.append(func():
			row.set_desc(stats)
			if i < GameState.tool_index:
				row.set_button("Owned ✔️", false)
			elif i == GameState.tool_index:
				row.set_button("Equipped", false)
			elif i == GameState.next_tool_index():
				row.set_button("💧 " + Fmt.num(t.cost), GameState.water >= t.cost)
			else:
				row.set_desc("Buy the previous tool first")
				row.set_button("🔒 " + Fmt.num(t.cost), false))
		row.button.pressed.connect(func():
			if GameState.buy_tool(i):
				toast("%s %s equipped!" % [t.icon, t.name]))


func _build_upgrades() -> void:
	for u in Balance.UPGRADES:
		var key: String = u.key
		var row := _row(u.icon, u.name, "")
		_row_refreshers.append(func():
			var lvl := int(GameState.upgrade_levels[key])
			row.set_title("%s  (Lv %d/%d)" % [u.name, lvl, int(u.max)])
			row.set_desc("%s  ·  now x%.2f" % [u.desc, GameState.upgrade_mult(key)])
			if GameState.upgrade_maxed(key):
				row.set_button("Maxed ✔️", false)
			else:
				var cost := GameState.upgrade_cost(key)
				row.set_button("💧 " + Fmt.num(cost), GameState.water >= cost))
		row.button.pressed.connect(func(): GameState.buy_upgrade(key))


func _build_helpers() -> void:
	for i in Balance.HELPERS.size():
		var h: Dictionary = Balance.HELPERS[i]
		var row := _row(h.icon, h.name, "")
		_row_refreshers.append(func():
			row.set_title("%s  x%d" % [h.name, int(GameState.helper_counts[i])])
			row.set_desc("%s  ·  %s hp/s each" % [h.desc, Fmt.num(float(h.power) * GameState.global_mult())])
			var cost := GameState.helper_cost(i)
			row.set_button("💧 " + Fmt.num(cost), GameState.water >= cost))
		row.button.pressed.connect(func():
			if GameState.buy_helper(i):
				toast("%s %s hired!" % [h.icon, h.name]))


func _build_finds() -> void:
	var found := 0
	for d in GameState.discovered:
		if d:
			found += 1
	var header := Label.new()
	header.text = "Collection: %d / %d found  (+ the village at the very bottom)" % [found, Balance.DISCOVERIES.size()]
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_list_box.add_child(header)
	for i in Balance.DISCOVERIES.size():
		var d: Dictionary = Balance.DISCOVERIES[i]
		var row: ShopRow
		if GameState.discovered[i]:
			row = _row(d.icon, d.name, d.flavor)
			row.set_button("Found ✔️", false)
		else:
			row = _row("❓", "???", "Frozen somewhere in the %s" % Balance.LAYERS[int(d.layer)].name)
			row.set_button("Frozen", false)
	var village := _row("🏘️", "The Village" if GameState.has_won else "???",
		"Free at last! Summer is back." if GameState.has_won else "Something big is under all that ice")
	village.set_button("Found ✔️" if GameState.has_won else "Frozen", false)


func _build_shop() -> void:
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
		toast("Restore requested"))

	# Dev tools: in the editor, and in exports tagged "playtest" (the web build).
	# Remove the tag from export_presets.cfg before shipping.
	if OS.is_debug_build() or OS.has_feature("playtest"):
		var title := Label.new()
		title.text = "Developer tools (playtest builds only)"
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title.add_theme_color_override("font_color", Color(1, 0.6, 0.6))
		_list_box.add_child(title)
		var cash := _row("💰", "Free meltwater", "Adds 10x your current water (at least 1K).")
		cash.set_button("Add", true)
		cash.button.pressed.connect(func(): GameState.grant_water(maxf(1000.0, GameState.water * 10.0)))
		var speed := _row("⏩", "Melting speed", "Multiplies all melting, for testing.")
		_row_refreshers.append(func(): speed.set_button("x%d" % int(GameState.debug_speed), true))
		speed.button.pressed.connect(func():
			GameState.debug_speed = 1.0 if GameState.debug_speed >= 100.0 else GameState.debug_speed * 10.0)
		var away := _row("🕑", "Simulate 2h away", "Tests the offline melting popup (needs helpers).")
		away.set_button("Go", true)
		away.button.pressed.connect(func():
			GameState.last_active_time -= 7200.0
			GameState.check_offline())
		var melt := _row("☀️", "Melt everything", "Skip straight to the ending.")
		melt.set_button("Melt", true)
		melt.button.pressed.connect(func():
			close_shed()
			grid.melt_everything())
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
	panel.add_theme_stylebox_override("panel", UiTheme.flat(Color(0.12, 0.18, 0.32), 24, 30))
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	panel.add_child(v)
	var t := Label.new()
	t.text = title
	t.add_theme_font_size_override("font_size", 36)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var b := Label.new()
	b.text = body
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.custom_minimum_size = Vector2(560, 0)
	v.add_child(b)
	return {"root": dim, "box": v}


func _popup_button(p: Dictionary, text: String, color: Color, cb: Callable) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(0, 64)
	UiTheme.colored_button(btn, color, 16)
	btn.pressed.connect(cb)
	p.box.add_child(btn)
	return btn


func _close_popup(p: Dictionary) -> void:
	var r: Control = p.root
	popups.remove_child(r)
	r.queue_free()
	if popups.get_child_count() == 0 and not shed_open:
		player.input_enabled = true
		touch.visible = touch_mode


func show_offline(result: Dictionary) -> void:
	var water: float = result.water
	var body := "While you were away for %s, your helpers melted %s blocks of ice.\n\nYou earned 💧%s" % [
		Fmt.duration(result.seconds), Fmt.num(float(result.blocks)), Fmt.num(water)]
	if result.get("capped", false):
		body += "\n(Away time counts for up to %d hours.)" % int(Balance.OFFLINE_CAP_SECONDS / 3600.0)
	var p := _popup("Welcome back!", body)
	_popup_button(p, "📺  Watch an ad to double it (+💧%s)" % Fmt.num(water), Color(0.85, 0.45, 0.15), func():
		Monetization.show_rewarded(Monetization.PLACEMENT_OFFLINE_DOUBLE, func(ok: bool):
			if ok:
				GameState.grant_water(water)
				toast("Doubled! +💧" + Fmt.num(water))
			_close_popup(p)))
	_popup_button(p, "Collect", Color(0.25, 0.5, 0.85), func(): _close_popup(p))


func show_ending() -> void:
	if _ending_shown:
		return
	_ending_shown = true
	if shed_open:
		close_shed()
	var found := 0
	for d in GameState.discovered:
		if d:
			found += 1
	var body := "The last chunk dripped away and the village is free.\nSummer is back!\n\n⏱ %s played\n🧊 %s blocks melted\n💧 %s meltwater earned\n🏺 %d/%d finds\n\n(Screenshot this!)" % [
		Fmt.duration(GameState.play_time), Fmt.num(float(GameState.blocks_melted)), Fmt.num(GameState.lifetime_water),
		found, Balance.DISCOVERIES.size()]
	var p := _popup("☀️ THE END ☀️", body)
	_popup_button(p, "Walk around the village", Color(0.25, 0.5, 0.85), func(): _close_popup(p))
	_popup_button(p, "Melt a new glacier", Color(0.85, 0.45, 0.15), func():
		GameState.wipe_save()
		get_tree().reload_current_scene())
