extends Node
## Autoload "Monetization": the only place the game asks for ads or purchases.
##
## Usage from game code:
##   Monetization.show_rewarded(Monetization.PLACEMENT_BOOST, func(ok): if ok: GameState.start_boost())
##   Monetization.buy(Monetization.PRODUCT_REMOVE_ADS_2X)
##   Monetization.maybe_show_interstitial("shed_exit")
##
## Swapping in real SDKs: implement a MonetizationProvider subclass (see
## README "Adding real ads & purchases") and return it from _create_provider().

signal purchases_changed
signal purchase_error(product_id: String, reason: String)

# Rewarded ad placements (use these as AdMob ad unit keys too).
const PLACEMENT_BOOST := "boost_2x_heat"

# Store product ids (create the same ids in Play Console / App Store Connect).
const PRODUCT_REMOVE_ADS_2X := "remove_ads_2x"      # non-consumable, $2.99
const PRODUCT_GOLDEN_DRYER := "golden_hair_dryer"   # non-consumable cosmetic, $0.99

const PRODUCTS = {
	PRODUCT_REMOVE_ADS_2X: {"title": "Remove Ads + Permanent 2x", "fallback_price": "$2.99"},
	PRODUCT_GOLDEN_DRYER: {"title": "Golden Hair Dryer", "fallback_price": "$0.99"},
}

var provider: MonetizationProvider
var _reward_callbacks: Dictionary = {}   # placement -> Callable(bool)
var _last_interstitial: float = 0.0


func _ready() -> void:
	provider = _create_provider()
	add_child(provider)
	provider.rewarded_completed.connect(_on_rewarded_completed)
	provider.rewarded_failed.connect(_on_rewarded_failed)
	provider.purchase_succeeded.connect(_grant)
	provider.purchase_restored.connect(_grant)
	provider.purchase_failed.connect(func(id, reason): purchase_error.emit(id, reason))
	provider.initialize()
	_last_interstitial = Time.get_unix_time_from_system()


func _create_provider() -> MonetizationProvider:
	# TODO when shipping: detect the plugin and return the real provider, e.g.
	#   if Engine.has_singleton("PoingGodotAdMob"):
	#       return preload("res://scripts/monetization/admob_provider.gd").new()
	return StubMonetizationProvider.new()


# --- Rewarded ------------------------------------------------------------------------
func is_rewarded_ready(placement: String) -> bool:
	return provider.is_rewarded_ready(placement)


func show_rewarded(placement: String, on_done: Callable) -> void:
	## on_done(ok: bool) is called exactly once.
	if _reward_callbacks.has(placement):
		return
	_reward_callbacks[placement] = on_done
	provider.show_rewarded(placement)


func _on_rewarded_completed(placement: String) -> void:
	var cb: Callable = _reward_callbacks.get(placement, Callable())
	_reward_callbacks.erase(placement)
	if cb.is_valid():
		cb.call(true)


func _on_rewarded_failed(placement: String, reason: String) -> void:
	print("[Monetization] rewarded '%s' failed: %s" % [placement, reason])
	var cb: Callable = _reward_callbacks.get(placement, Callable())
	_reward_callbacks.erase(placement)
	if cb.is_valid():
		cb.call(false)


# --- Interstitial (used lightly) ---------------------------------------------------------
func maybe_show_interstitial(placement: String) -> void:
	if GameState.owns_remove_ads_2x:
		return
	var grid: IceField = GameState.grid
	if grid == null or 1.0 - grid.fraction_left() < Balance.INTERSTITIAL_MIN_PROGRESS:
		return
	var t := Time.get_unix_time_from_system()
	if t - _last_interstitial < Balance.INTERSTITIAL_COOLDOWN:
		return
	_last_interstitial = t
	provider.show_interstitial(placement)


# --- Purchases --------------------------------------------------------------------------
func owns(product_id: String) -> bool:
	match product_id:
		PRODUCT_REMOVE_ADS_2X:
			return GameState.owns_remove_ads_2x
		PRODUCT_GOLDEN_DRYER:
			return GameState.owns_golden_dryer
	return false


func price(product_id: String) -> String:
	return provider.price_string(product_id, PRODUCTS[product_id].fallback_price)


func buy(product_id: String) -> void:
	if owns(product_id):
		return
	provider.purchase(product_id)


func restore() -> void:
	provider.restore_purchases()


func _grant(product_id: String) -> void:
	match product_id:
		PRODUCT_REMOVE_ADS_2X:
			GameState.owns_remove_ads_2x = true
		PRODUCT_GOLDEN_DRYER:
			GameState.owns_golden_dryer = true
			GameState.golden_equipped = true
		_:
			push_warning("Unknown product: %s" % product_id)
			return
	GameState.save_game()
	GameState.changed.emit()
	purchases_changed.emit()
