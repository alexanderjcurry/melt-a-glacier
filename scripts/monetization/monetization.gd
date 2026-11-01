extends Node
## Autoload "Monetization": the only place the game asks for ads or purchases.
##
## Usage from game code:
##   Monetization.show_rewarded(Monetization.PLACEMENT_BOOST, func(ok): if ok: GameState.start_boost())
##   Monetization.buy(Monetization.PRODUCT_REMOVE_ADS_2X)
##   Monetization.maybe_show_interstitial("shed_exit")
##
## Providers: on Android/iOS the real one (MobileMonetizationProvider: AdMob +
## RevenueCat, ids in store_config.gd). In the editor and playtest/web builds,
## the stub with pretend ads and free purchases. See docs/LAUNCH.md.

signal purchases_changed
signal purchase_error(product_id: String, reason: String)
signal restore_done(found: int, error: String)

# Rewarded ad placements (use these as AdMob ad unit keys too). Each one is a
# reward in Balance.AD_REWARDS, offered in the catalogue and on the HUD's
# timed offer tag (Hud, AdOffers).
const PLACEMENT_BOOST := "boost_2x_heat"
const PLACEMENT_DOUBLE_WATER := "double_water"
const PLACEMENT_HELPER_RUSH := "helper_rush"

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
	provider.restore_finished.connect(func(found, error): restore_done.emit(found, error))
	provider.initialize()
	_last_interstitial = Time.get_unix_time_from_system()


func _create_provider() -> MonetizationProvider:
	var os_name := OS.get_name()
	if (os_name == "Android" or os_name == "iOS") and not OS.has_feature("stub_store"):
		return MobileMonetizationProvider.new()
	if OS.is_debug_build() or OS.has_feature("playtest") or OS.has_feature("stub_store"):
		return StubMonetizationProvider.new()
	return MonetizationProvider.new()   # e.g. a release desktop build: no ads, no store


func provider_name() -> String:
	return provider.provider_name()


# --- Privacy (ad consent) ------------------------------------------------------------------
func privacy_options_required() -> bool:
	## Show a "Privacy settings" button when this is true (EEA/UK players).
	return provider.privacy_options_required()


func show_privacy_options() -> void:
	provider.show_privacy_options()


# --- Rewarded ------------------------------------------------------------------------
func is_rewarded_ready(placement: String) -> bool:
	return provider.is_rewarded_ready(placement)


func show_rewarded(placement: String, on_done: Callable) -> void:
	## on_done(ok: bool) is called exactly once.
	if _reward_callbacks.has(placement):
		return
	_reward_callbacks[placement] = on_done
	provider.show_rewarded(placement)


func watch_for_reward(kind: String, on_done: Callable) -> void:
	## Show the rewarded ad for one of Balance.AD_REWARDS; if it's watched to
	## the end, grant the reward. on_done(ok: bool, text: String) says what you got.
	var placement: String = Balance.AD_REWARDS[kind].placement
	show_rewarded(placement, func(ok: bool):
		on_done.call(ok, GameState.grant_ad_reward(kind) if ok else ""))


func is_watching() -> bool:
	return not _reward_callbacks.is_empty()


func _on_rewarded_completed(placement: String) -> void:
	# Someone who just chose to watch an ad shouldn't get an unasked one next.
	_last_interstitial = Time.get_unix_time_from_system()
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
	if not PRODUCTS.has(product_id):
		push_warning("Unknown product: %s" % product_id)
		return
	if owns(product_id):
		return   # restores and store updates repeat grants; keep the player's settings
	match product_id:
		PRODUCT_REMOVE_ADS_2X:
			GameState.owns_remove_ads_2x = true
			provider.set_ads_removed(true)
		PRODUCT_GOLDEN_DRYER:
			GameState.owns_golden_dryer = true
			GameState.golden_equipped = true
	GameState.save_game()
	GameState.changed.emit()
	purchases_changed.emit()
