class_name AdOffers
extends RefCounted
## When a timed rewarded-ad offer shows up on the HUD, and which one.
##
## Rules (numbers in Balance.OFFER_*): nothing in the first few minutes; one
## offer at a time; it goes away by itself after OFFER_LIFETIME; the clock only
## runs while you're actually playing (not in the catalogue or a popup); and
## every offer you let pass makes the next one wait longer. Taking one resets
## the wait. Offers only show when they'd be worth having (no "helpers 3x"
## without helpers, no 2x heat while it's already on).

var current := ""            # the reward on offer (a Balance.AD_REWARDS key), "" = none
var time_left := 0.0
var watching := false        # its ad is playing: don't let it run out meanwhile
var _wait := Balance.OFFER_FIRST_AFTER
var _gap := Balance.OFFER_GAP
var _last := ""
var rng := RandomNumberGenerator.new()


func _init() -> void:
	rng.randomize()


func update(delta: float, playing: bool) -> int:
	## Call every frame. Returns 1 when an offer appears, -1 when one goes away
	## unused, 0 otherwise.
	if current != "":
		if watching:
			return 0
		if playing:
			time_left -= delta
		if time_left <= 0.0 or not eligible(current):
			_pass()
			return -1
		return 0
	if not playing:
		return 0
	_wait -= delta
	if _wait > 0.0:
		return 0
	var k := pick()
	if k == "":
		_wait = 20.0   # nothing worth offering yet; look again soon
		return 0
	current = k
	time_left = Balance.OFFER_LIFETIME
	_last = k
	return 1


func taken() -> void:
	## The player watched the ad for the current offer.
	current = ""
	watching = false
	_gap = Balance.OFFER_GAP
	_wait = _gap


func _pass() -> void:
	current = ""
	watching = false
	_gap = minf(_gap * Balance.OFFER_GAP_GROWTH, Balance.OFFER_GAP_MAX)
	_wait = _gap


static func eligible(kind: String) -> bool:
	if GameState.has_won:
		return false
	if not Monetization.is_rewarded_ready(str(Balance.AD_REWARDS[kind].placement)):
		return false   # no ad loaded (offline, no fill): don't offer what we can't show
	match kind:
		"double_water":
			var amount := GameState.double_water_amount()
			return amount >= maxf(Balance.DOUBLE_WATER_MIN, GameState.income_per_minute())
		"heat_rush":
			return not GameState.is_boost_active()
		"helper_rush":
			return GameState.has_helpers() and not GameState.is_helper_rush_active()
	return false


func pick() -> String:
	## Double water when it would get you the next tool right now (that's the
	## offer worth taking); otherwise any worthwhile one, not the same as last time.
	if eligible("double_water") and unlocks_tool() != "":
		return "double_water"
	var options: Array = []
	for k in Balance.AD_REWARDS:
		if eligible(k) and k != _last:
			options.append(k)
	if options.is_empty() and eligible(_last):
		options.append(_last)
	if options.is_empty():
		return ""
	return options[rng.randi() % options.size()]


static func unlocks_tool() -> String:
	## The next tool's name if doubling your water would buy it, else "".
	var i := GameState.next_tool_index()
	if i < 0:
		return ""
	var cost: float = Balance.TOOLS[i].cost
	if GameState.water < cost and GameState.water + GameState.double_water_amount() >= cost:
		return str(Balance.TOOLS[i].name)
	return ""


static func pitch(kind: String) -> String:
	## The small line under an offer's title: what exactly you'd get.
	match kind:
		"double_water":
			var line := "+💧 %s" % Fmt.num(GameState.double_water_amount())
			var tool := unlocks_tool()
			if tool != "":
				line += "  ·  enough for the %s!" % tool
			return line
		"heat_rush":
			return "Everything you melt goes twice as fast"
		"helper_rush":
			return "Your crew melts three times as much"
	return ""
