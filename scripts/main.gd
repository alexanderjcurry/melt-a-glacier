extends Control
## Builds the whole portrait UI in code: top bar, glacier, boost bar, shop tabs,
## popups and the ending screen. Layout targets 720x1280 and stretches.

const TABS = ["Tools", "Stats", "Helpers", "Finds", "Shop"]

var glacier: GlacierView
var water_label: Label
var rate_label: Label
var layer_label: Label
var layer_bar: ProgressBar
var total_bar: ProgressBar
var boost_button: Button
var boost_label: Label
var list_box: VBoxContainer
var scroll: ScrollContainer
var toast_box: VBoxContainer
var popup_layer: CanvasLayer
var _tab := 0
var _tab_buttons: Array = []
var _row_refreshers: Array = []   # Callables that update rows in place
var _refresh_timer := 0.0
var _win_shown := false


func _ready() -> void:
	_install_emoji_font()
	theme = _make_theme()
	_build()
	GameState.changed.connect(_mark_dirty)
	GameState.discovery.connect(_on_discovery)
	GameState.layer_cleared.connect(_on_layer_cleared)
	GameState.won.connect(_show_win)
	GameState.offline_earned.connect(_show_offline)
	Monetization.purchase_error.connect(func(id, reason): toast("Purchase failed: %s" % reason))
	Monetization.purchases_changed.connect(func(): _rebuild_list())
	_select_tab(0)
	_refresh_all()
	GameState.check_offline()
	if GameState.has_won:
		_show_win.call_deferred()


func _process(delta: float) -> void:
	_refresh_timer += delta
	if _refresh_timer >= 0.15:
		_refresh_timer = 0.0
		_refresh_all()


func _mark_dirty() -> void:
	pass  # refresh runs on a short timer; cheap enough and avoids per-frame churn


# =====================================================================================
# Layout
# =====================================================================================
func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.11, 0.2)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 0)
	add_child(root)

	root.add_child(_build_top_bar())

	glacier = GlacierView.new()
	glacier.size_flags_vertical = Control.SIZE_EXPAND_FILL
	glacier.size_flags_stretch_ratio = 1.0
	root.add_child(glacier)

	root.add_child(_build_boost_bar())
	root.add_child(_build_tabs())

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(0, 420)
	panel.add_theme_stylebox_override("panel", _flat(Color(0.1, 0.15, 0.26), 0))
	root.add_child(panel)
	scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	list_box = VBoxContainer.new()
	list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_box.add_theme_constant_override("separation", 8)
	scroll.add_child(list_box)

	toast_box = VBoxContainer.new()
	toast_box.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	toast_box.offset_top = 150
	toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast_box.alignment = BoxContainer.ALIGNMENT_BEGIN
	add_child(toast_box)

	popup_layer = CanvasLayer.new()
	popup_layer.layer = 50
	add_child(popup_layer)


func _build_top_bar() -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _flat(Color(0.06, 0.09, 0.17), 0, 16))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	panel.add_child(v)

	var row := HBoxContainer.new()
	v.add_child(row)
	water_label = Label.new()
	water_label.add_theme_font_size_override("font_size", 44)
	water_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(water_label)
	rate_label = Label.new()
	rate_label.add_theme_color_override("font_color", Color(0.6, 0.85, 1.0))
	rate_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(rate_label)

	layer_label = Label.new()
	layer_label.add_theme_font_size_override("font_size", 22)
	layer_label.add_theme_color_override("font_color", Color(0.8, 0.88, 1.0))
	v.add_child(layer_label)

	layer_bar = ProgressBar.new()
	layer_bar.show_percentage = false
	layer_bar.custom_minimum_size = Vector2(0, 14)
	layer_bar.max_value = 1.0
	layer_bar.add_theme_stylebox_override("fill", _flat(Color(0.45, 0.78, 1.0), 6))
	layer_bar.add_theme_stylebox_override("background", _flat(Color(0.15, 0.2, 0.32), 6))
	v.add_child(layer_bar)

	total_bar = ProgressBar.new()
	total_bar.show_percentage = false
	total_bar.custom_minimum_size = Vector2(0, 8)
	total_bar.max_value = 1.0
	total_bar.add_theme_stylebox_override("fill", _flat(Color(1.0, 0.75, 0.3), 4))
	total_bar.add_theme_stylebox_override("background", _flat(Color(0.15, 0.2, 0.32), 4))
	v.add_child(total_bar)
	return panel


func _build_boost_bar() -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _flat(Color(0.08, 0.12, 0.22), 0, 10))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	panel.add_child(row)
	boost_button = Button.new()
	boost_button.text = "📺  2x Heat for 5 min"
	boost_button.custom_minimum_size = Vector2(0, 64)
	boost_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	boost_button.add_theme_stylebox_override("normal", _flat(Color(0.85, 0.45, 0.15), 14))
	boost_button.add_theme_stylebox_override("hover", _flat(Color(0.92, 0.52, 0.2), 14))
	boost_button.add_theme_stylebox_override("pressed", _flat(Color(0.7, 0.35, 0.1), 14))
	boost_button.pressed.connect(_on_boost_pressed)
	row.add_child(boost_button)
	boost_label = Label.new()
	boost_label.custom_minimum_size = Vector2(190, 0)
	boost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(boost_label)
	return panel


func _build_tabs() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	var group := ButtonGroup.new()
	for i in TABS.size():
		var b := Button.new()
		b.text = TABS[i]
		b.toggle_mode = true
		b.button_group = group
		b.custom_minimum_size = Vector2(0, 66)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_stylebox_override("normal", _flat(Color(0.12, 0.18, 0.3), 0))
		b.add_theme_stylebox_override("hover", _flat(Color(0.16, 0.23, 0.38), 0))
		b.add_theme_stylebox_override("pressed", _flat(Color(0.1, 0.15, 0.26), 0))
		b.pressed.connect(_select_tab.bind(i))
		row.add_child(b)
		_tab_buttons.append(b)
	return row


func _select_tab(i: int) -> void:
	_tab = i
	_tab_buttons[i].button_pressed = true
	_rebuild_list()
	scroll.scroll_vertical = 0


# =====================================================================================
# Shop lists
# =====================================================================================
func _rebuild_list() -> void:
	for c in list_box.get_children():
		c.queue_free()
	_row_refreshers.clear()
	var pad := Control.new()
	pad.custom_minimum_size = Vector2(0, 2)
	list_box.add_child(pad)
	match _tab:
		0: _build_tools()
		1: _build_stats()
		2: _build_helpers()
		3: _build_finds()
		4: _build_shop()
	_refresh_rows()


func _build_tools() -> void:
	for i in Balance.TOOLS.size():
		var t: Dictionary = Balance.TOOLS[i]
		var row := _row(t.icon, t.name, "")
		_row_refreshers.append(func():
			var desc := "%s  •  %s heat/tap" % [t.desc, Fmt.num(t.heat)]
			if i <= GameState.tool_index:
				row.set_desc(desc)
				row.set_button("Owned ✓" if i < GameState.tool_index else "Equipped", false)
			elif not GameState.tool_unlocked(i):
				row.set_desc("Reach layer %d to unlock" % (int(t.unlock_layer) + 1))
				row.set_button("🔒 " + Fmt.num(t.cost), false)
			elif i == GameState.next_tool_index():
				row.set_desc(desc)
				row.set_button("💧 " + Fmt.num(t.cost), GameState.water >= t.cost)
			else:
				row.set_desc("Buy the previous tool first")
				row.set_button("💧 " + Fmt.num(t.cost), false))
		row.button.pressed.connect(func():
			if GameState.buy_tool(i):
				toast("%s %s equipped!" % [t.icon, t.name]))


func _build_stats() -> void:
	for s in Balance.STATS:
		var key: String = s.key
		var row := _row(s.icon, s.name, "")
		_row_refreshers.append(func():
			var lvl := int(GameState.stat_levels[key])
			row.set_title("%s  (Lv %d)" % [s.name, lvl])
			row.set_desc("%s  •  now x%.2f" % [s.desc, GameState.stat_mult(key)])
			var cost := GameState.stat_cost(key)
			row.set_button("💧 " + Fmt.num(cost), GameState.water >= cost))
		row.button.pressed.connect(func(): GameState.buy_stat(key))


func _build_helpers() -> void:
	for i in Balance.HELPERS.size():
		var hdef: Dictionary = Balance.HELPERS[i]
		var row := _row(hdef.icon, hdef.name, "")
		_row_refreshers.append(func():
			var n := int(GameState.helper_counts[i])
			row.set_title("%s  x%d" % [hdef.name, n])
			var each: float = hdef.rate * GameState.stat_mult("auto") * GameState.global_mult()
			row.set_desc("%s  •  %s t/s each" % [hdef.desc, Fmt.num(each)])
			var cost := GameState.helper_cost(i)
			row.set_button("💧 " + Fmt.num(cost), GameState.water >= cost))
		row.button.pressed.connect(func(): GameState.buy_helper(i))


func _build_finds() -> void:
	var found := 0
	for d in GameState.discovered:
		if d:
			found += 1
	var header := Label.new()
	header.text = "Collection: %d / %d found" % [found, Balance.DISCOVERIES.size()]
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	list_box.add_child(header)
	for i in Balance.DISCOVERIES.size():
		var d: Dictionary = Balance.DISCOVERIES[i]
		var row: ShopRow
		if GameState.discovered[i]:
			row = _row(d.icon, d.name, d.flavor)
			row.set_button("Found ✓", false)
		else:
			row = _row("❓", "???", "Buried in layer %d (%s)" % [i + 1, Balance.LAYERS[i].name])
			row.set_button("Frozen", false)


func _build_shop() -> void:
	var boost_row := _row("📺", "2x Heat Boost", "Watch an ad: everything melts 2x faster for 5 min. Stacks to 15 min.")
	boost_row.set_button("Watch", true)
	boost_row.button.pressed.connect(_on_boost_pressed)

	for id in Monetization.PRODUCTS:
		var p: Dictionary = Monetization.PRODUCTS[id]
		var icon := "🚫" if id == Monetization.PRODUCT_REMOVE_ADS_2X else "✨"
		var desc := "No interstitial ads, and everything melts 2x forever." if id == Monetization.PRODUCT_REMOVE_ADS_2X else "A shiny gold heat glow. Purely cosmetic, purely fabulous."
		var row := _row(icon, p.title, desc)
		var pid: String = id
		_row_refreshers.append(func():
			if Monetization.owns(pid):
				row.set_button("Owned ✓", false)
			else:
				row.set_button(Monetization.price(pid), true))
		row.button.pressed.connect(func(): Monetization.buy(pid))

	if GameState.owns_golden_dryer:
		var g := _row("🎨", "Golden glow", "Toggle the golden hair dryer look.")
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
		title.text = "— Developer tools (playtest builds only) —"
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title.add_theme_color_override("font_color", Color(1, 0.6, 0.6))
		list_box.add_child(title)
		var cash := _row("💰", "Free meltwater", "Adds 10x your current water (min 1K).")
		cash.set_button("Add", true)
		cash.button.pressed.connect(func(): GameState.grant_water(maxf(1000.0, GameState.water * 10.0)))
		var speed := _row("⏩", "Game speed", "Multiplies all melting. For testing pacing.")
		_row_refreshers.append(func(): speed.set_button("x%d" % int(GameState.debug_speed), true))
		speed.button.pressed.connect(func():
			GameState.debug_speed = 1.0 if GameState.debug_speed >= 100.0 else GameState.debug_speed * 10.0)
		var off := _row("🕑", "Simulate 2h away", "Tests the offline earnings popup.")
		off.set_button("Go", true)
		off.button.pressed.connect(func():
			GameState.last_active_time -= 7200.0
			GameState.check_offline())
		var wipe := _row("🗑️", "Wipe save", "Start over (keeps purchases).")
		wipe.set_button("Wipe", true)
		wipe.button.pressed.connect(func():
			GameState.wipe_save()
			_win_shown = false
			_clear_popups()
			_rebuild_list())


func _row(icon: String, title: String, desc: String) -> ShopRow:
	var row := ShopRow.new()
	row.setup(icon, title, desc)
	list_box.add_child(row)
	return row


func _refresh_rows() -> void:
	for r in _row_refreshers:
		r.call()


func _refresh_all() -> void:
	water_label.text = "💧 " + Fmt.num(GameState.water)
	var rate := GameState.water_per_second()
	rate_label.text = "+%s/s\n%s/tap" % [Fmt.num(rate), Fmt.num(GameState.tap_heat() * GameState.sell_mult())]
	if GameState.has_won:
		layer_label.text = "The glacier is gone. Summer is back!"
	else:
		var li := GameState.layer_index
		layer_label.text = "Layer %d/%d · %s · %s t left" % [li + 1, Balance.layer_count(), Balance.LAYERS[li].name, Fmt.num(GameState.layer_hp)]
	layer_bar.value = 1.0 - GameState.layer_fraction_left()
	total_bar.value = GameState.total_progress()
	if GameState.is_boost_active():
		boost_label.text = "🔥 2x  " + Fmt.duration(GameState.boost_seconds_left())
		boost_label.add_theme_color_override("font_color", Color(1.0, 0.75, 0.3))
	else:
		boost_label.text = "No boost"
		boost_label.add_theme_color_override("font_color", Color(0.6, 0.65, 0.75))
	_refresh_rows()


# =====================================================================================
# Events
# =====================================================================================
func _on_boost_pressed() -> void:
	Monetization.show_rewarded(Monetization.PLACEMENT_BOOST, func(ok: bool):
		if ok:
			GameState.start_boost()
			toast("🔥 2x heat for 5 minutes!")
		else:
			toast("No reward this time"))


func _on_discovery(index: int, value: float) -> void:
	var d: Dictionary = Balance.DISCOVERIES[index]
	toast("%s %s melted out! Sold for 💧%s" % [d.icon, d.name, Fmt.num(value)])
	if _tab == 3:
		_rebuild_list()


func _on_layer_cleared(index: int) -> void:
	if index + 1 < Balance.layer_count():
		toast("Layer %d melted! Next: %s" % [index + 1, Balance.LAYERS[index + 1].name])
	if _tab == 0:
		_rebuild_list()
	Monetization.maybe_show_interstitial("layer_clear")


func toast(text: String) -> void:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _flat(Color(0.05, 0.08, 0.15, 0.88), 14, 12))
	p.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 24)
	p.add_child(l)
	toast_box.add_child(p)
	while toast_box.get_child_count() > 3:
		var old := toast_box.get_child(0)
		toast_box.remove_child(old)
		old.queue_free()
	var tw := p.create_tween()  # bound to the toast, so it dies with it
	tw.tween_interval(2.4)
	tw.tween_property(p, "modulate:a", 0.0, 0.5)
	tw.tween_callback(p.queue_free)


# =====================================================================================
# Popups
# =====================================================================================
func _popup(title: String, body: String) -> Dictionary:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.theme = theme  # CanvasLayer children don't inherit the main theme
	popup_layer.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(600, 0)
	panel.add_theme_stylebox_override("panel", _flat(Color(0.12, 0.18, 0.32), 24, 32))
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 18)
	panel.add_child(v)
	var t := Label.new()
	t.text = title
	t.add_theme_font_size_override("font_size", 40)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var b := Label.new()
	b.text = body
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.custom_minimum_size = Vector2(536, 0)
	v.add_child(b)
	return {"root": dim, "box": v}


func _popup_button(p: Dictionary, text: String, color: Color, cb: Callable) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(0, 76)
	btn.add_theme_stylebox_override("normal", _flat(color, 16))
	btn.add_theme_stylebox_override("hover", _flat(color.lightened(0.1), 16))
	btn.add_theme_stylebox_override("pressed", _flat(color.darkened(0.15), 16))
	btn.pressed.connect(cb)
	p.box.add_child(btn)
	return btn


func _clear_popups() -> void:
	for c in popup_layer.get_children():
		c.queue_free()


func _show_offline(result: Dictionary) -> void:
	var water: float = result.water
	var body := "While you were away for %s, your helpers melted %s tons of ice.\n\nYou earned 💧%s" % [
		Fmt.duration(result.seconds), Fmt.num(result.ice), Fmt.num(water)]
	if result.get("capped", false):
		body += "\n(Offline time caps at 8 hours.)"
	var p := _popup("Welcome back!", body)
	var root: Control = p.root
	_popup_button(p, "📺  Watch ad: double it (+💧%s)" % Fmt.num(water), Color(0.85, 0.45, 0.15), func():
		Monetization.show_rewarded(Monetization.PLACEMENT_OFFLINE_DOUBLE, func(ok: bool):
			if ok:
				GameState.grant_water(water)
				toast("Doubled! +💧" + Fmt.num(water))
			root.queue_free()))
	_popup_button(p, "Collect", Color(0.25, 0.5, 0.85), func(): root.queue_free())


func _show_win() -> void:
	if _win_shown:
		return
	_win_shown = true
	var found := 0
	for d in GameState.discovered:
		if d:
			found += 1
	var body := "The last chunk dripped away and the village is free.\nSummer is back!\n\n⏱ %s played\n👆 %s taps\n💧 %s meltwater earned\n🏺 %d/%d finds\n\n(Screenshot this!)" % [
		Fmt.duration(GameState.play_time), Fmt.num(float(GameState.taps)), Fmt.num(GameState.lifetime_water), found, Balance.DISCOVERIES.size()]
	var p := _popup("☀️ THE END ☀️", body)
	var root: Control = p.root
	_popup_button(p, "Admire the view", Color(0.25, 0.5, 0.85), func(): root.queue_free())
	_popup_button(p, "Melt a new glacier", Color(0.85, 0.45, 0.15), func():
		GameState.wipe_save()
		_win_shown = false
		root.queue_free()
		_rebuild_list())


# =====================================================================================
# Theme helpers
# =====================================================================================
const EMOJI_FONT_PATH := "res://fonts/NotoColorEmoji-subset.ttf"


func _install_emoji_font() -> void:
	## Emoji are the placeholder art. Bundle a (subset) color emoji font and make
	## it a fallback of the default font so every Label / draw_string can show them.
	var emoji := load(EMOJI_FONT_PATH) as FontFile
	if emoji == null:
		return
	emoji.fixed_size_scale_mode = TextServer.FIXED_SIZE_SCALE_ENABLED
	var base := ThemeDB.fallback_font.duplicate() as Font
	base.fallbacks = [emoji]
	ThemeDB.fallback_font = base
	ThemeDB.get_default_theme().default_font = base  # covers overlays like the stub ad


func _flat(color: Color, radius: int = 12, margin: int = 12) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(radius)
	s.content_margin_left = margin
	s.content_margin_right = margin
	s.content_margin_top = margin * 0.6
	s.content_margin_bottom = margin * 0.6
	return s


func _make_theme() -> Theme:
	var t := Theme.new()
	t.default_font = ThemeDB.fallback_font
	t.default_font_size = 26
	t.set_color("font_color", "Label", Color(0.93, 0.96, 1.0))
	t.set_color("font_color", "Button", Color(1, 1, 1))
	t.set_color("font_disabled_color", "Button", Color(0.6, 0.65, 0.72))
	t.set_stylebox("normal", "Button", _flat(Color(0.2, 0.45, 0.8), 14))
	t.set_stylebox("hover", "Button", _flat(Color(0.25, 0.52, 0.88), 14))
	t.set_stylebox("pressed", "Button", _flat(Color(0.15, 0.36, 0.68), 14))
	t.set_stylebox("disabled", "Button", _flat(Color(0.2, 0.25, 0.35), 14))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	return t
