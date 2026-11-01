extends Node
## Autoload "GameState": meltwater, tools, upgrades, helpers, finds, and saving.
## The glacier itself lives in IceGrid; its state is saved through here.

signal changed                                   # anything changed; UI should refresh
signal discovered_item(index: int, value: float)
signal won
signal offline_earned(result: Dictionary)        # {seconds, blocks, water, capped}

const SAVE_PATH := "user://save3d.json"
const SAVE_VERSION := 2
const AUTOSAVE_INTERVAL := 10.0

# --- Saved state ----------------------------------------------------------------
var water: float = 0.0
var lifetime_water: float = 0.0
var tool_index: int = 0
var upgrade_levels: Dictionary = {}    # key -> level
var helper_counts: Array = []          # index -> owned
var discovered: Array = []             # index -> bool
var blocks_melted: int = 0
var boost_until: float = 0.0
var owns_remove_ads_2x: bool = false   # IAP
var owns_golden_dryer: bool = false    # IAP (cosmetic)
var golden_equipped: bool = false
var play_time: float = 0.0
var has_won: bool = false
var last_active_time: float = 0.0
var player_pos: Vector3 = Vector3.INF  # INF = use the spawn point
var player_yaw: float = 0.0
var player_pitch: float = -0.15
var glacier_data: String = ""          # IceGrid.to_save_string()
var tutorial_step: int = 0             # onboarding hints (World._update_coach)

# --- Runtime only -------------------------------------------------------------------
var grid: IceGrid                      # set by the world when it's built
var player: Node3D
var debug_speed: float = 1.0           # dev menu multiplier
var _autosave_timer: float = 0.0
var _last_tick_time: float = 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	reset_state()
	load_game()


func reset_state(keep_purchases: bool = false) -> void:
	var keep_ads := owns_remove_ads_2x
	var keep_gold := owns_golden_dryer
	water = 0.0
	lifetime_water = 0.0
	tool_index = 0
	upgrade_levels = {}
	for u in Balance.UPGRADES:
		upgrade_levels[u.key] = 0
	helper_counts = []
	for _h in Balance.HELPERS:
		helper_counts.append(0)
	discovered = []
	for _d in Balance.DISCOVERIES:
		discovered.append(false)
	blocks_melted = 0
	boost_until = 0.0
	play_time = 0.0
	has_won = false
	owns_remove_ads_2x = keep_ads if keep_purchases else false
	owns_golden_dryer = keep_gold if keep_purchases else false
	golden_equipped = golden_equipped and owns_golden_dryer
	last_active_time = now()
	player_pos = Vector3.INF
	player_yaw = 0.0
	player_pitch = -0.15
	glacier_data = ""
	tutorial_step = 0


func now() -> float:
	return Time.get_unix_time_from_system()


func _process(delta: float) -> void:
	# A frozen main loop (phone locked, app in background, browser tab hidden)
	# counts as time away instead of one giant frame.
	var t := now()
	if _last_tick_time > 0.0 and t - _last_tick_time >= Balance.OFFLINE_MIN_SECONDS:
		_grant_offline(t - _last_tick_time)
	_last_tick_time = t
	if not has_won:
		play_time += minf(delta, 1.0)
	_autosave_timer += delta
	if _autosave_timer >= AUTOSAVE_INTERVAL:
		_autosave_timer = 0.0
		save_game()


# --- Derived numbers -------------------------------------------------------------
func upgrade_mult(key: String) -> float:
	for u in Balance.UPGRADES:
		if u.key == key:
			return 1.0 + float(u.per_level) * float(upgrade_levels.get(key, 0))
	return 1.0


func global_mult() -> float:
	var m := 1.0
	if is_boost_active():
		m *= Balance.BOOST_MULT
	if owns_remove_ads_2x:
		m *= Balance.PERMANENT_MULT
	return m


func tool_def() -> Dictionary:
	return Balance.TOOLS[tool_index]


func tool_power() -> float:
	return float(tool_def().power) * upgrade_mult("heat") * global_mult() * debug_speed


func tool_radius() -> float:
	return float(tool_def().radius) * upgrade_mult("nozzle")


func tool_range() -> float:
	return float(tool_def().range) * upgrade_mult("reach")


func move_speed_mult() -> float:
	return upgrade_mult("boots")


func sell_mult() -> float:
	return upgrade_mult("sell")


func helper_power(i: int) -> float:
	## Total hp per second from all helpers of type i.
	return float(Balance.HELPERS[i].power) * float(helper_counts[i]) * global_mult() * debug_speed


func total_helper_power() -> float:
	var p := 0.0
	for i in Balance.HELPERS.size():
		p += helper_power(i)
	return p


func block_value(layer: int) -> float:
	return Balance.layer_hp(layer) * sell_mult()


func is_boost_active() -> bool:
	return now() < boost_until


func boost_seconds_left() -> float:
	return maxf(0.0, boost_until - now())


# --- Earning ------------------------------------------------------------------------------
func on_block_melted(layer: int) -> float:
	var v := block_value(layer)
	blocks_melted += 1
	water += v
	lifetime_water += v
	changed.emit()
	return v


func grant_water(amount: float) -> void:
	water += amount
	lifetime_water += amount
	changed.emit()


func discover(i: int) -> void:
	if discovered[i]:
		return
	discovered[i] = true
	var value: float = float(Balance.DISCOVERIES[i].value) * sell_mult()
	grant_water(value)
	discovered_item.emit(i, value)


func check_win() -> void:
	if has_won or grid == null or grid.remaining > 0:
		return
	has_won = true
	save_game()
	won.emit()
	changed.emit()


# --- Shed -------------------------------------------------------------------------------
func next_tool_index() -> int:
	return tool_index + 1 if tool_index + 1 < Balance.TOOLS.size() else -1


func buy_tool(i: int) -> bool:
	if i != next_tool_index():
		return false
	var cost: float = Balance.TOOLS[i].cost
	if water < cost:
		return false
	water -= cost
	tool_index = i
	changed.emit()
	return true


func upgrade_def(key: String) -> Dictionary:
	for u in Balance.UPGRADES:
		if u.key == key:
			return u
	return {}


func upgrade_maxed(key: String) -> bool:
	return int(upgrade_levels[key]) >= int(upgrade_def(key).max)


func upgrade_cost(key: String) -> float:
	var u := upgrade_def(key)
	return float(u.base) * pow(float(u.growth), float(upgrade_levels[key]))


func buy_upgrade(key: String) -> bool:
	if upgrade_maxed(key):
		return false
	var cost := upgrade_cost(key)
	if water < cost:
		return false
	water -= cost
	upgrade_levels[key] = int(upgrade_levels[key]) + 1
	changed.emit()
	return true


func helper_cost(i: int) -> float:
	return float(Balance.HELPERS[i].base) * pow(Balance.HELPER_GROWTH, float(helper_counts[i]))


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


# --- Offline earnings -------------------------------------------------------------
func check_offline() -> void:
	## Called once the world is ready: pays out the time since the last save.
	var elapsed := now() - last_active_time
	last_active_time = now()
	_last_tick_time = now()
	_grant_offline(elapsed)


func _grant_offline(elapsed: float) -> void:
	if has_won or grid == null or elapsed < Balance.OFFLINE_MIN_SECONDS:
		return
	var secs := minf(elapsed, Balance.OFFLINE_CAP_SECONDS)
	# Boosts don't run while you're away; the permanent IAP multiplier does.
	var mult := Balance.PERMANENT_MULT if owns_remove_ads_2x else 1.0
	var base_power := 0.0
	for i in Balance.HELPERS.size():
		base_power += float(Balance.HELPERS[i].power) * float(helper_counts[i])
	var budget := base_power * mult * secs * Balance.OFFLINE_EFFICIENCY
	if budget <= 0.0:
		return
	var before := water
	var blocks := grid.melt_budget(budget, _rng)   # each melted block pays out via the world
	if blocks <= 0:
		return
	offline_earned.emit({"seconds": secs, "blocks": blocks, "water": water - before,
		"capped": elapsed > Balance.OFFLINE_CAP_SECONDS})
	check_win()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_CLOSE_REQUEST:
			save_game()


# --- Save / load -------------------------------------------------------------------
func to_dict() -> Dictionary:
	if grid != null:
		glacier_data = grid.to_save_string()
	if player != null:
		player_pos = player.position
		player_yaw = player.yaw
		player_pitch = player.pitch
	return {
		"version": SAVE_VERSION,
		"water": water,
		"lifetime_water": lifetime_water,
		"tool_index": tool_index,
		"upgrade_levels": upgrade_levels,
		"helper_counts": helper_counts,
		"discovered": discovered,
		"blocks_melted": blocks_melted,
		"boost_until": boost_until,
		"owns_remove_ads_2x": owns_remove_ads_2x,
		"owns_golden_dryer": owns_golden_dryer,
		"golden_equipped": golden_equipped,
		"play_time": play_time,
		"has_won": has_won,
		"last_active_time": last_active_time,
		"player_pos": [player_pos.x, player_pos.y, player_pos.z] if player_pos.is_finite() else [],
		"player_yaw": player_yaw,
		"player_pitch": player_pitch,
		"glacier": glacier_data,
		"tutorial_step": tutorial_step,
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
	var data = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if typeof(data) != TYPE_DICTIONARY:
		push_warning("Save file unreadable, starting fresh.")
		return
	water = float(data.get("water", 0.0))
	lifetime_water = float(data.get("lifetime_water", 0.0))
	tool_index = clampi(int(data.get("tool_index", 0)), 0, Balance.TOOLS.size() - 1)
	var ul: Dictionary = data.get("upgrade_levels", {})
	for u in Balance.UPGRADES:
		upgrade_levels[u.key] = clampi(int(ul.get(u.key, 0)), 0, int(u.max))
	var hc: Array = data.get("helper_counts", [])
	for i in helper_counts.size():
		helper_counts[i] = int(hc[i]) if i < hc.size() else 0
	var dc: Array = data.get("discovered", [])
	for i in discovered.size():
		discovered[i] = bool(dc[i]) if i < dc.size() else false
	blocks_melted = int(data.get("blocks_melted", 0))
	boost_until = float(data.get("boost_until", 0.0))
	owns_remove_ads_2x = bool(data.get("owns_remove_ads_2x", false))
	owns_golden_dryer = bool(data.get("owns_golden_dryer", false))
	golden_equipped = bool(data.get("golden_equipped", false)) and owns_golden_dryer
	play_time = float(data.get("play_time", 0.0))
	has_won = bool(data.get("has_won", false))
	last_active_time = float(data.get("last_active_time", now()))
	var pp: Array = data.get("player_pos", [])
	player_pos = Vector3(float(pp[0]), float(pp[1]), float(pp[2])) if pp.size() == 3 else Vector3.INF
	player_yaw = float(data.get("player_yaw", 0.0))
	player_pitch = float(data.get("player_pitch", -0.15))
	glacier_data = str(data.get("glacier", ""))
	tutorial_step = int(data.get("tutorial_step", 0))


func wipe_save() -> void:
	## Start a fresh glacier (keeps purchases). The world rebuilds itself.
	reset_state(true)
	grid = null
	player = null
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(to_dict()))
	changed.emit()
