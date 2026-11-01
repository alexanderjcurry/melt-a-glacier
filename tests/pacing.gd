extends SceneTree
## Pacing bot: plays a whole run the way a keen player would and prints how long
## each part took, in game minutes. Use it after changing Balance or a glacier.
##   godot --headless --fixed-fps 20 -s res://tests/pacing.gd
##   godot --headless --fixed-fps 20 -s res://tests/pacing.gd -- casual
## The default player keeps the beam on the ice most of the time and goes to the
## shed about once a minute. "casual" is slower: more looking around, more shed
## browsing. Real first runs land somewhere between the two.
## Add "seed=N" for a different roll of the dice.
## Variables stay untyped: this compiles before the GameState autoload exists.

const DT := 0.05                 # must match --fixed-fps 20
const LIMIT := 3.0 * 3600.0      # give up after three game hours
const SHED := Vector3(13.0, 0.0, 11.5)
const REPORT_EVERY := 300.0

var duty := 0.8                  # share of melting time the beam is actually on ice
var shop_every := 60.0           # seconds of play between shed visits
var browse := 10.0               # seconds spent looking around inside the shed
var dwell_max := 2.5             # most time on one spot before sweeping on
var walk_speed := 4.5

var gs
var grid
var rng := RandomNumberGenerator.new()
var t := 0.0
var marks: Array = []
var stage_start := 0.0
# Where the water came from: your tool, finds, and everything else (helpers, drips).
var from_tool := 0.0
var from_finds := 0.0
var last_report := {"t": 0.0, "tool": 0.0, "finds": 0.0, "all": 0.0}


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a == "casual":
			duty = 0.6
			shop_every = 50.0
			browse = 25.0
			dwell_max = 1.5
		elif a.begins_with("seed="):
			rng.seed = int(a.substr(5))
	if rng.seed == 0:
		rng.seed = 7
	_run.call_deferred()


func _note(text: String) -> void:
	print("%6.1f min  %s" % [t / 60.0, text])


static func _n(x: float) -> String:
	## 1234567 -> "1.23M"
	var a := absf(x)
	if a >= 1e9:
		return "%.2fB" % (x / 1e9)
	if a >= 1e6:
		return "%.2fM" % (x / 1e6)
	if a >= 1e3:
		return "%.2fK" % (x / 1e3)
	return "%.1f" % x


static func _work(field) -> float:
	## hp x m³ it takes to melt all of this glacier (= water at x1 sell).
	var w := 0.0
	for s in field.f.size():
		if field.f[s] > 0.5:
			w += field.layer_hp(field.lay[s])
	return w * field.point_volume


func _run() -> void:
	gs = root.get_node("GameState")
	gs.wipe_save()
	var world = load("res://scenes/world.tscn").instantiate()
	root.add_child(world)
	await process_frame
	for g in gs.grids.size():
		var field = gs.grids[g]
		var finds := 0.0
		for d in Balance.finds_in(g):
			finds += float(Balance.DISCOVERIES[d].value)
		_note("%s: %d m3 of ice, %s to melt (water at x1 sell), finds worth %s" % [
			field.spec.title, field.volume_left(), _n(_work(field)), _n(finds)])
	gs.discovered_item.connect(func(i, value):
		from_finds += value
		_note("found %s (+%s)" % [Balance.DISCOVERIES[i].name, _n(value)]))
	gs.stage_changed.connect(func(s):
		_note("=== %s done in %.1f min. On to %s ===" % [grid.spec.title, (t - stage_start) / 60.0, gs.grids[s].spec.title])
		stage_start = t)

	var pos := Vector3(0.0, 0.0, 4.0)   # where we stand
	var spot := Vector3.INF
	var dwell := 0.0
	var busy := 0.0
	var next_shop := shop_every
	var next_report := REPORT_EVERY
	var stage := -1
	while not gs.has_won and t < LIMIT:
		await process_frame
		for field in gs.grids:
			field._dirty.clear()   # nobody's looking: skip re-meshing, it doesn't change the numbers
		t += DT
		if gs.stage != stage:
			stage = gs.stage
			grid = gs.grid
			marks = [0.1, 0.25, 0.5, 0.75, 0.9]
			spot = Vector3.INF
		if t >= next_report:
			next_report += REPORT_EVERY
			_report()
		while not marks.is_empty() and 1.0 - grid.fraction_left() >= marks[0]:
			_note("%.0f%% of %s melted" % [marks[0] * 100.0, grid.spec.name])
			marks.pop_front()
		if busy > 0.0:
			busy -= DT
			continue
		# Off to the shed every so often (less often when it's a long walk away),
		# or as soon as the next tool is affordable.
		var nt: int = gs.next_tool_index()
		var tool_ready: bool = nt >= 0 and gs.water >= float(Balance.TOOLS[nt].cost)
		if t >= next_shop or (tool_ready and t >= next_shop - shop_every * 0.75):
			var trip: float = 2.0 * Vector2(pos.x - SHED.x, pos.z - SHED.z).length() / (walk_speed * gs.move_speed_mult())
			_shop()
			busy = trip + browse
			next_shop = t + busy + maxf(shop_every, trip * 2.0)
			continue
		# Pick where to aim: stay near the last spot (sweeping), walk if it's out of reach.
		if not spot.is_finite() or dwell > dwell_max or not grid.has_ice_at(spot.x, spot.z) \
				or grid.surface_y(spot.x, spot.z) < 0.05:
			var near: Vector3 = spot if spot.is_finite() else pos
			spot = grid.nearby_surface_point(near, rng, maxf(gs.tool_radius(), 1.0))
			dwell = 0.0
			if not spot.is_finite():
				continue
			var reach: float = gs.tool_range() * 0.7
			var d := Vector2(spot.x - pos.x, spot.z - pos.z).length()
			if d > reach:
				busy = (d - reach) / (walk_speed * gs.move_speed_mult()) + 0.5
				pos = spot + (pos - spot).normalized() * reach
				continue
		dwell += DT
		if rng.randf() < duty:
			var y: float = grid.surface_y(spot.x, spot.z)
			var before: float = gs.lifetime_water - from_finds   # (a find dug up by the tool counts as a find)
			grid.damage_sphere(Vector3(spot.x, y - 0.2, spot.z), gs.tool_radius(), gs.tool_power() * DT)
			from_tool += gs.lifetime_water - from_finds - before

	_report()
	if gs.has_won:
		_note("WON. water left %s, lifetime %s" % [_n(gs.water), _n(gs.lifetime_water)])
	else:
		_note("gave up: %.0f%% of %s melted" % [100.0 * (1.0 - grid.fraction_left()), grid.spec.name])
	quit(0)


func _report() -> void:
	## Progress, and where the water came from since the last report (per second).
	var span: float = maxf(t - float(last_report.t), DT)
	var all: float = gs.lifetime_water - float(last_report.all)
	var tool: float = from_tool - float(last_report.tool)
	var finds: float = from_finds - float(last_report.finds)
	_note("%s %2.0f%% melted | %s, heat %d nozzle %d sell %d | helpers %s | water %s | per s: tool %s, helpers %s, finds %s" % [
		grid.spec.title, 100.0 * (1.0 - grid.fraction_left()), Balance.TOOLS[gs.tool_index].name,
		gs.upgrade_levels.heat, gs.upgrade_levels.nozzle, gs.upgrade_levels.sell, str(gs.helper_counts),
		_n(gs.water), _n(tool / span), _n((all - tool - finds) / span), _n(finds / span)])
	last_report = {"t": t, "tool": from_tool, "finds": from_finds, "all": gs.lifetime_water}


func _shop() -> void:
	var bought := true
	while bought:
		bought = false
		var nt: int = gs.next_tool_index()
		if nt >= 0 and gs.water >= float(Balance.TOOLS[nt].cost):
			gs.buy_tool(nt)
			_note("bought %s (%s)" % [Balance.TOOLS[nt].name, _n(Balance.TOOLS[nt].cost)])
			bought = true
			continue
		# Then the cheapest upgrade or helper, keeping most of the money for the next tool.
		var cap: float = float(Balance.TOOLS[nt].cost) * 0.3 if nt >= 0 else INF
		var best := ""
		var best_cost := INF
		for key in ["heat", "nozzle", "sell"]:
			if not gs.upgrade_maxed(key) and gs.upgrade_cost(key) < best_cost:
				best = key
				best_cost = gs.upgrade_cost(key)
		for i in Balance.HELPERS.size():
			if gs.helper_cost(i) < best_cost:
				best = str(i)
				best_cost = gs.helper_cost(i)
		if best == "" or best_cost > gs.water or best_cost > cap:
			break
		if best.is_valid_int():
			gs.buy_helper(int(best))
		else:
			gs.buy_upgrade(best)
		bought = true
