extends Node
## Autoload "GameState": meltwater, tools, upgrades, helpers, finds, and saving.
## The glaciers themselves live in IceFields; their state is saved through here.
## A level's glaciers are melted one after another (`stage`): the village
## glacier, then the frozen lake. You win when the last one is gone.

signal changed                                   # anything changed; UI should refresh
signal discovered_item(index: int, value: float)
signal stage_changed(stage: int)                 # a glacier is gone and the next one opens up
signal won

const SAVE_PATH := "user://save3d.json"
const SAVE_VERSION := 4            # 4 = the bigger valley + the frozen lake. Older saves start fresh.
const AUTOSAVE_INTERVAL := 10.0

# --- Saved state ----------------------------------------------------------------
var water: float = 0.0
var lifetime_water: float = 0.0
var tool_index: int = 0
var upgrade_levels: Dictionary = {}    # key -> level
var helper_counts: Array = []          # index -> owned
var discovered: Array = []             # index -> bool
var melted_volume: float = 0.0         # m³ of ice melted, all glaciers
var stage: int = 0                     # which glacier you're melting (index into the level's glaciers)
var boost_until: float = 0.0
var helper_rush_until: float = 0.0     # rewarded ad: helpers work 3x until then
var owns_remove_ads_2x: bool = false   # IAP
var owns_golden_dryer: bool = false    # IAP (cosmetic)
var golden_equipped: bool = false
var play_time: float = 0.0
var has_won: bool = false
var player_pos: Vector3 = Vector3.INF  # INF = use the spawn point
var player_yaw: float = 0.0
var player_pitch: float = -0.15
var glacier_saves: Array = []          # IceField.to_save_string() per glacier ("" = untouched)
var tutorial_step: int = 0             # onboarding hints (World._update_coach)

# --- Runtime only -------------------------------------------------------------------
var grid: IceField                     # the glacier you're melting now (set by the world)
var grids: Array = []                  # every glacier in the level, in order
var player: Node3D
var debug_speed: float = 1.0           # dev menu multiplier
var _autosave_timer: float = 0.0
var _income: Array = []                # meltwater earned per INCOME_BUCKET seconds, newest last
var _income_t: float = 0.0
const INCOME_BUCKET := 15.0
const INCOME_BUCKETS := 16             # 4 minutes


func _ready() -> void:
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
	melted_volume = 0.0
	stage = 0
	boost_until = 0.0
	helper_rush_until = 0.0
	_income = []
	play_time = 0.0
	has_won = false
	owns_remove_ads_2x = keep_ads if keep_purchases else false
	owns_golden_dryer = keep_gold if keep_purchases else false
	golden_equipped = golden_equipped and owns_golden_dryer
	player_pos = Vector3.INF
	player_yaw = 0.0
	player_pitch = -0.15
	glacier_saves = []
	tutorial_step = 0


func now() -> float:
	return Time.get_unix_time_from_system()


func _process(delta: float) -> void:
	if not has_won:
		play_time += minf(delta, 1.0)
	_income_t += minf(delta, 1.0)
	if _income.is_empty() or _income_t >= INCOME_BUCKET:
		_income_t = 0.0
		_income.append(0.0)
		if _income.size() > INCOME_BUCKETS:
			_income.pop_front()
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


func jet_fuel_seconds() -> float:
	return Balance.JET_FUEL * upgrade_mult("jet")


func sell_mult() -> float:
	return upgrade_mult("sell")


func helper_each(i: int) -> float:
	## hp per second from one helper of type i (or one of Kevin's levels).
	var m := Balance.HELPER_RUSH_MULT if is_helper_rush_active() else 1.0
	return float(Balance.HELPERS[i].power) * global_mult() * m * debug_speed


func helper_power(i: int) -> float:
	## Total hp per second from all helpers of type i.
	return helper_each(i) * float(helper_counts[i])


func total_helper_power() -> float:
	var p := 0.0
	for i in Balance.HELPERS.size():
		p += helper_power(i)
	return p


func layer_value(g: IceField, layer: int) -> float:
	## Meltwater for a cubic metre of this layer of that glacier.
	return g.layer_hp(layer) * g.worth * sell_mult()


func melted_cubic_metres() -> float:
	return melted_volume


func is_boost_active() -> bool:
	return now() < boost_until


func boost_seconds_left() -> float:
	return maxf(0.0, boost_until - now())


func is_helper_rush_active() -> bool:
	return now() < helper_rush_until


func helper_rush_seconds_left() -> float:
	return maxf(0.0, helper_rush_until - now())


func has_helpers() -> bool:
	for c in helper_counts:
		if int(c) > 0:
			return true
	return false


func income_per_minute() -> float:
	## Meltwater per minute over the last few minutes (melting, helpers, finds).
	if _income.is_empty():
		return 0.0
	var total := 0.0
	for v in _income:
		total += float(v)
	var span := INCOME_BUCKET * float(_income.size() - 1) + maxf(_income_t, 1.0)
	return total / span * 60.0


func double_water_amount() -> float:
	## What "double your water" pays: your water again, capped at a few minutes of income.
	return minf(water, maxf(Balance.DOUBLE_WATER_MIN * 3.0, income_per_minute() * Balance.DOUBLE_WATER_MINUTES))


# --- Earning ------------------------------------------------------------------------------
func on_ice_melted(volume: float, value: float) -> float:
	## `volume` m³ of ice just melted; `value` is their layers' hp x m³.
	var v := value * sell_mult()
	melted_volume += volume
	water += v
	lifetime_water += v
	_note_income(v)
	changed.emit()
	return v


func grant_water(amount: float, counts_as_income: bool = true) -> void:
	water += amount
	lifetime_water += amount
	if counts_as_income:
		_note_income(amount)
	changed.emit()


func _note_income(v: float) -> void:
	if _income.is_empty():
		_income.append(0.0)
	_income[_income.size() - 1] = float(_income[_income.size() - 1]) + v


func discover(i: int) -> void:
	if discovered[i]:
		return
	discovered[i] = true
	var value: float = float(Balance.DISCOVERIES[i].value) * sell_mult()
	grant_water(value)
	discovered_item.emit(i, value)


func check_win() -> void:
	## The glacier you're on is gone: on to the next one, or that's the game.
	if has_won or grid == null or grid.remaining > 0:
		return
	if stage < grids.size() - 1:
		stage += 1
		grid = grids[stage]
		# Your helpers retire; hire a new crew for the next glacier.
		for i in helper_counts.size():
			helper_counts[i] = 0
		save_game()
		stage_changed.emit(stage)
		changed.emit()
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


func helper_max_level(i: int) -> int:
	## A helper there's only one of (Kevin) levels up instead, this far. 0 = you
	## can hire as many as you like.
	return int(Balance.HELPERS[i].get("max_level", 0))


func helper_maxed(i: int) -> bool:
	return helper_max_level(i) > 0 and int(helper_counts[i]) >= helper_max_level(i)


func buy_helper(i: int) -> bool:
	var cost := helper_cost(i)
	if water < cost or helper_maxed(i):
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


func grant_ad_reward(kind: String) -> String:
	## A rewarded ad finished: hand out `kind` (see Balance.AD_REWARDS) and
	## return the toast that says what you got.
	match kind:
		"double_water":
			var amount := double_water_amount()
			grant_water(amount, false)   # not income, or the next offer would grow
			save_game()
			return "💧 +%s meltwater!" % Fmt.num(amount)
		"heat_rush":
			start_boost()
			return "🔥 2x heat for 5 minutes!"
		"helper_rush":
			helper_rush_until = maxf(now(), helper_rush_until) + Balance.HELPER_RUSH_DURATION
			changed.emit()
			return "🐧 Your helpers are working 3x as hard!"
	return ""


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_CLOSE_REQUEST:
			save_game()


# --- Save / load -------------------------------------------------------------------
func to_dict() -> Dictionary:
	if not grids.is_empty():
		glacier_saves.resize(grids.size())
		for g in grids.size():
			var field: IceField = grids[g]
			if g < stage:
				glacier_saves[g] = "gone"            # melted: nothing to store
			elif g > stage:
				glacier_saves[g] = ""                # not started yet
			else:
				glacier_saves[g] = field.to_save_string()
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
		"melted_volume": melted_volume,
		"stage": stage,
		"boost_until": boost_until,
		"helper_rush_until": helper_rush_until,
		"owns_remove_ads_2x": owns_remove_ads_2x,
		"owns_golden_dryer": owns_golden_dryer,
		"golden_equipped": golden_equipped,
		"play_time": play_time,
		"has_won": has_won,
		"player_pos": [player_pos.x, player_pos.y, player_pos.z] if player_pos.is_finite() else [],
		"player_yaw": player_yaw,
		"player_pitch": player_pitch,
		"glaciers": glacier_saves,
		"tutorial_step": tutorial_step,
	}


func save_game() -> void:
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
	owns_remove_ads_2x = bool(data.get("owns_remove_ads_2x", false))
	owns_golden_dryer = bool(data.get("owns_golden_dryer", false))
	golden_equipped = bool(data.get("golden_equipped", false)) and owns_golden_dryer
	if int(data.get("version", 0)) < 4:
		return   # an older, smaller valley: start the new one fresh, keep purchases
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
	melted_volume = float(data.get("melted_volume", 0.0))
	stage = maxi(0, int(data.get("stage", 0)))
	boost_until = float(data.get("boost_until", 0.0))
	helper_rush_until = float(data.get("helper_rush_until", 0.0))
	play_time = float(data.get("play_time", 0.0))
	has_won = bool(data.get("has_won", false))
	var pp: Array = data.get("player_pos", [])
	player_pos = Vector3(float(pp[0]), float(pp[1]), float(pp[2])) if pp.size() == 3 else Vector3.INF
	player_yaw = float(data.get("player_yaw", 0.0))
	player_pitch = float(data.get("player_pitch", -0.15))
	glacier_saves = data.get("glaciers", [])
	tutorial_step = int(data.get("tutorial_step", 0))


func wipe_save() -> void:
	## Start a fresh glacier (keeps purchases). The world rebuilds itself.
	reset_state(true)
	grid = null
	grids = []
	player = null
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(to_dict()))
	changed.emit()
