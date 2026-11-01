extends Node
## Autoload "GameState": the whole economy, progression and save/load.
## UI and visuals only read from here and call the buy_* / melt functions.

signal changed                                   # anything changed; UI should refresh
signal layer_cleared(index: int)
signal discovery(index: int, value: float)
signal won
signal offline_earned(result: Dictionary)        # {seconds, ice, water}

const SAVE_PATH := "user://save.json"
const SAVE_VERSION := 1
const AUTOSAVE_INTERVAL := 10.0

# --- Saved state --------------------------------------------------------------
var water: float = 0.0                 # currency (meltwater)
var lifetime_water: float = 0.0
var layer_index: int = 0               # current top layer
var layer_hp: float = 0.0              # ice left in the current layer
var tool_index: int = 0
var stat_levels: Dictionary = {}       # key -> level
var helper_counts: Array = []          # index -> owned
var discovered: Array = []             # index -> bool
var boost_until: float = 0.0           # unix time the 2x ad boost ends
var owns_remove_ads_2x: bool = false   # IAP
var owns_golden_dryer: bool = false    # IAP (cosmetic)
var golden_equipped: bool = false
var play_time: float = 0.0
var taps: int = 0
var has_won: bool = false
var last_active_time: float = 0.0

# --- Runtime only ----------------------------------------------------------------
var debug_speed: float = 1.0           # dev menu multiplier
var _autosave_timer: float = 0.0
var _last_tick_time: float = 0.0       # unix time of the last frame, to spot freezes


func _ready() -> void:
	reset_state()
	load_game()


func reset_state(keep_purchases: bool = false) -> void:
	var keep_ads := owns_remove_ads_2x
	var keep_gold := owns_golden_dryer
	water = 0.0
	lifetime_water = 0.0
	layer_index = 0
	layer_hp = Balance.LAYER_HP[0]
	tool_index = 0
	stat_levels = {}
	for s in Balance.STATS:
		stat_levels[s.key] = 0
	helper_counts = []
	for _h in Balance.HELPERS:
		helper_counts.append(0)
	discovered = []
	for _d in Balance.DISCOVERIES:
		discovered.append(false)
	boost_until = 0.0
	play_time = 0.0
	taps = 0
	has_won = false
	owns_remove_ads_2x = keep_ads if keep_purchases else false
	owns_golden_dryer = keep_gold if keep_purchases else false
	golden_equipped = golden_equipped and owns_golden_dryer
	last_active_time = now()


func now() -> float:
	return Time.get_unix_time_from_system()


func _process(delta: float) -> void:
	# If the main loop was frozen (phone locked, app in background, browser tab
	# hidden), count the gap as time away instead of one giant frame.
	var t := now()
	if _last_tick_time > 0.0 and t - _last_tick_time >= Balance.OFFLINE_MIN_SECONDS:
		_grant_offline(t - _last_tick_time)
		delta = 0.0
	_last_tick_time = t
	delta = minf(delta, 1.0)
	if not has_won:
		play_time += delta
		var auto := auto_rate()
		if auto > 0.0:
			melt_raw(auto * delta * debug_speed)
	_autosave_timer += delta
	if _autosave_timer >= AUTOSAVE_INTERVAL:
		_autosave_timer = 0.0
		save_game()


# --- Derived numbers -------------------------------------------------------------
func stat_mult(key: String) -> float:
	for s in Balance.STATS:
		if s.key == key:
			return 1.0 + s.per_level * float(stat_levels.get(key, 0))
	return 1.0


func global_mult() -> float:
	var m := 1.0
	if is_boost_active():
		m *= Balance.BOOST_MULT
	if owns_remove_ads_2x:
		m *= Balance.PERMANENT_MULT
	return m


func tap_heat() -> float:
	return Balance.TOOLS[tool_index].heat * stat_mult("heat") * stat_mult("size") * global_mult()


func hold_rate() -> float:
	return tap_heat() * Balance.HOLD_TAPS_PER_SEC


func base_helper_rate() -> float:
	var r := 0.0
	for i in Balance.HELPERS.size():
		r += Balance.HELPERS[i].rate * float(helper_counts[i])
	return r * stat_mult("auto")


func auto_rate() -> float:
	return base_helper_rate() * global_mult()


func sell_mult() -> float:
	return stat_mult("sell")


func water_per_second() -> float:
	return auto_rate() * sell_mult()


func is_boost_active() -> bool:
	return now() < boost_until


func boost_seconds_left() -> float:
	return maxf(0.0, boost_until - now())


func tool_size_level() -> int:
	return int(stat_levels.get("size", 0))


func total_progress() -> float:
	## 0..1 of the glacier melted, by layer (each layer counts equally, which
	## matches what the player sees).
	if has_won:
		return 1.0
	var n := float(Balance.layer_count())
	var f: float = 1.0 - layer_hp / Balance.LAYER_HP[layer_index]
	return (float(layer_index) + f) / n


func layer_fraction_left() -> float:
	if has_won:
		return 0.0
	return layer_hp / Balance.LAYER_HP[layer_index]


# --- Melting -------------------------------------------------------------------------
func tap() -> float:
	taps += 1
	return melt_raw(tap_heat() * debug_speed)


func melt_raw(ice: float) -> float:
	## Melts `ice` tons (multipliers already applied). Returns meltwater earned.
	if has_won or ice <= 0.0:
		return 0.0
	var earned := 0.0
	var remaining := ice
	while remaining > 0.0 and not has_won:
		var take := minf(remaining, layer_hp)
		layer_hp -= take
		remaining -= take
		earned += take * sell_mult()
		_check_discovery()
		if layer_hp <= 0.0:
			_clear_layer()
	_add_water(earned)
	return earned


func _add_water(amount: float) -> void:
	water += amount
	lifetime_water += amount
	changed.emit()


func _check_discovery() -> void:
	var i := layer_index
	if i >= Balance.DISCOVERIES.size() - 1:
		return  # the village is revealed by winning, not mid-layer
	if not discovered[i] and layer_hp <= Balance.LAYER_HP[i] * 0.5:
		discovered[i] = true
		var value: float = Balance.LAYER_HP[i] * Balance.DISCOVERIES[i].value_mult * sell_mult()
		_add_water(value)
		discovery.emit(i, value)


func _clear_layer() -> void:
	var cleared := layer_index
	layer_index += 1
	layer_cleared.emit(cleared)
	if layer_index >= Balance.layer_count():
		layer_index = Balance.layer_count() - 1
		layer_hp = 0.0
		has_won = true
		discovered[Balance.DISCOVERIES.size() - 1] = true
		save_game()
		won.emit()
	else:
		layer_hp = Balance.LAYER_HP[layer_index]
	changed.emit()


# --- Shop --------------------------------------------------------------------------
func next_tool_index() -> int:
	return tool_index + 1 if tool_index + 1 < Balance.TOOLS.size() else -1


func tool_unlocked(i: int) -> bool:
	return layer_index >= int(Balance.TOOLS[i].unlock_layer) or has_won


func buy_tool(i: int) -> bool:
	if i != next_tool_index() or not tool_unlocked(i):
		return false
	var cost: float = Balance.TOOLS[i].cost
	if water < cost:
		return false
	water -= cost
	tool_index = i
	changed.emit()
	return true


func stat_cost(key: String) -> float:
	for s in Balance.STATS:
		if s.key == key:
			return s.base * pow(s.growth, float(stat_levels[key]))
	return INF


func buy_stat(key: String) -> bool:
	var cost := stat_cost(key)
	if water < cost:
		return false
	water -= cost
	stat_levels[key] = int(stat_levels[key]) + 1
	changed.emit()
	return true


func helper_cost(i: int) -> float:
	return Balance.HELPERS[i].base * pow(Balance.HELPER_GROWTH, float(helper_counts[i]))


func buy_helper(i: int) -> bool:
	var cost := helper_cost(i)
	if water < cost:
		return false
	water -= cost
	helper_counts[i] = int(helper_counts[i]) + 1
	changed.emit()
	return true


func start_boost() -> void:
	## Called after a rewarded ad. Stacks up to 3 boosts (15 min).
	var base := maxf(now(), boost_until)
	boost_until = minf(base + Balance.BOOST_DURATION, now() + Balance.BOOST_DURATION * 3.0)
	changed.emit()


func grant_water(amount: float) -> void:
	_add_water(amount)


# --- Offline earnings ------------------------------------------------------------
func check_offline() -> void:
	## Called once the main scene is ready: pays out the time since the last save.
	## (Time spent frozen while the game is open is caught in _process.)
	var elapsed := now() - last_active_time
	last_active_time = now()
	_last_tick_time = now()
	_grant_offline(elapsed)


func _grant_offline(elapsed: float) -> void:
	if has_won or elapsed < Balance.OFFLINE_MIN_SECONDS:
		return
	var secs := minf(elapsed, Balance.OFFLINE_CAP_SECONDS)
	# Boosts don't apply offline; the permanent IAP multiplier does.
	var mult := Balance.PERMANENT_MULT if owns_remove_ads_2x else 1.0
	var ice := base_helper_rate() * mult * secs * Balance.OFFLINE_EFFICIENCY
	if ice <= 0.0:
		return
	var w := melt_raw(ice)
	offline_earned.emit({"seconds": secs, "ice": ice, "water": w, "capped": elapsed > Balance.OFFLINE_CAP_SECONDS})


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_CLOSE_REQUEST:
			save_game()


# --- Save / load ------------------------------------------------------------------
func to_dict() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"water": water,
		"lifetime_water": lifetime_water,
		"layer_index": layer_index,
		"layer_hp": layer_hp,
		"tool_index": tool_index,
		"stat_levels": stat_levels,
		"helper_counts": helper_counts,
		"discovered": discovered,
		"boost_until": boost_until,
		"owns_remove_ads_2x": owns_remove_ads_2x,
		"owns_golden_dryer": owns_golden_dryer,
		"golden_equipped": golden_equipped,
		"play_time": play_time,
		"taps": taps,
		"has_won": has_won,
		"last_active_time": last_active_time,
	}


func save_game() -> void:
	if not has_won:
		last_active_time = now()
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("Could not save: %s" % FileAccess.get_open_error())
		return
	f.store_string(JSON.stringify(to_dict()))


func load_game() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var text := FileAccess.get_file_as_string(SAVE_PATH)
	var data = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY:
		push_warning("Save file unreadable, starting fresh.")
		return
	water = float(data.get("water", 0.0))
	lifetime_water = float(data.get("lifetime_water", 0.0))
	layer_index = clampi(int(data.get("layer_index", 0)), 0, Balance.layer_count() - 1)
	layer_hp = float(data.get("layer_hp", Balance.LAYER_HP[layer_index]))
	tool_index = clampi(int(data.get("tool_index", 0)), 0, Balance.TOOLS.size() - 1)
	var sl: Dictionary = data.get("stat_levels", {})
	for s in Balance.STATS:
		stat_levels[s.key] = int(sl.get(s.key, 0))
	var hc: Array = data.get("helper_counts", [])
	for i in helper_counts.size():
		helper_counts[i] = int(hc[i]) if i < hc.size() else 0
	var dc: Array = data.get("discovered", [])
	for i in discovered.size():
		discovered[i] = bool(dc[i]) if i < dc.size() else false
	boost_until = float(data.get("boost_until", 0.0))
	owns_remove_ads_2x = bool(data.get("owns_remove_ads_2x", false))
	owns_golden_dryer = bool(data.get("owns_golden_dryer", false))
	golden_equipped = bool(data.get("golden_equipped", false)) and owns_golden_dryer
	play_time = float(data.get("play_time", 0.0))
	taps = int(data.get("taps", 0))
	has_won = bool(data.get("has_won", false))
	last_active_time = float(data.get("last_active_time", now()))


func wipe_save() -> void:
	reset_state(true)
	save_game()
	changed.emit()
