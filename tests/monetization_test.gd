extends SceneTree
## Headless test of the real ad / store wiring, without a phone:
##   godot --headless -s res://tests/monetization_test.gd
## - RevenueCatStore against a fake "GodotxRevenueCat" singleton that answers
##   the way the plugin does (payload shapes copied from its Android/iOS source).
## - AdMobAds against fake AdMob + consent (UMP) natives: the consent form,
##   loading, retrying, reward timing, interstitials and Remove Ads.
## - The Monetization autoload's grant rules (restores don't flip settings).
## Exits with code 1 if anything fails. Variables stay untyped (see smoke_test.gd).

var ok := true


class FakeRevenueCat:
	extends Object
	signal customer_info_changed(data: Dictionary)
	signal customer_info(data: Dictionary)
	signal purchase_result(data: Dictionary)
	signal products(data: Dictionary)
	signal restore_finished(data: Dictionary)
	var key := ""
	var owned: Array = []          # active entitlement ids
	var next_purchase := "ok"      # ok | cancel | error
	var calls: Array = []

	func initialize(api_key: String, _user: String, _debug: bool) -> void:
		key = api_key
		calls.append("initialize")
		get_customer_info()

	func get_customer_info() -> void:
		calls.append("get_customer_info")
		customer_info.emit.call_deferred({"active_entitlements": owned.size(), "active_ids": PackedStringArray(owned)})

	func fetch_products(ids) -> void:
		calls.append("fetch_products")
		var arr := []
		for id in ids:
			arr.append({"id": id, "title": id, "description": "", "price": "€1,99", "amount": 1.99})
		products.emit.call_deferred({"products": arr, "error": ""})

	func purchase(pid: String) -> void:
		calls.append("purchase:" + pid)
		var d := {"cancelled": next_purchase == "cancel", "active_entitlements": 0,
			"error": "Network error" if next_purchase == "error" else "", "product_id": pid, "transaction_id": "t1"}
		if next_purchase == "ok":
			owned.append("remove_ads" if pid == "remove_ads_2x" else "golden_dryer")
		purchase_result.emit.call_deferred(d)

	func restore_purchases() -> void:
		calls.append("restore")
		restore_finished.emit.call_deferred({"success": true, "restored": owned.size() > 0,
			"active_entitlements": owned.size(), "error": ""})


class FakeConsent:
	## Stands in for the UMP halves of the AdMob plugin (it has no editor mock):
	## an EEA player who must answer the consent form, and then does.
	extends Object
	signal on_consent_info_updated_success
	signal on_consent_info_updated_failure(err: Dictionary)
	signal on_consent_form_load_success_listener(uid: int)
	signal on_consent_form_load_failure_listener(err: Dictionary)
	signal on_consent_form_dismissed(uid: int, err: Dictionary)
	signal on_privacy_options_form_dismissed_listener(err: Dictionary)
	var status := 2              # REQUIRED
	var form_shown := false

	func update(_request: Dictionary) -> void:
		on_consent_info_updated_success.emit.call_deferred()

	func get_consent_status() -> int:
		return status

	func get_is_consent_form_available() -> bool:
		return true

	func get_privacy_options_requirement_status() -> int:
		return 2                 # REQUIRED

	func load_consent_form() -> void:
		on_consent_form_load_success_listener.emit.call_deferred(7)

	func show(uid: int) -> void:
		form_shown = true
		status = 3               # OBTAINED
		on_consent_form_dismissed.emit.call_deferred(uid, {})


class FakeAds:
	## Stands in for the native MobileAds / RewardedAd / InterstitialAd halves.
	extends Object
	signal on_initialization_complete(status: Dictionary)
	signal on_rewarded_ad_loaded(uid: int)
	signal on_rewarded_ad_failed_to_load(uid: int, err: Dictionary)
	signal on_rewarded_ad_user_earned_reward(uid: int, item: Dictionary)
	signal on_rewarded_ad_dismissed_full_screen_content(uid: int)
	signal on_rewarded_ad_failed_to_show_full_screen_content(uid: int, err: Dictionary)
	signal on_rewarded_ad_clicked(uid: int)
	signal on_rewarded_ad_impression(uid: int)
	signal on_rewarded_ad_showed_full_screen_content(uid: int)
	signal on_rewarded_ad_paid(uid: int, value: Dictionary)
	signal on_interstitial_ad_loaded(uid: int)
	signal on_interstitial_ad_failed_to_load(uid: int, err: Dictionary)
	signal on_interstitial_ad_dismissed_full_screen_content(uid: int)
	signal on_interstitial_ad_failed_to_show_full_screen_content(uid: int, err: Dictionary)
	signal on_interstitial_ad_clicked(uid: int)
	signal on_interstitial_ad_impression(uid: int)
	signal on_interstitial_ad_showed_full_screen_content(uid: int)
	signal on_interstitial_ad_paid(uid: int, value: Dictionary)
	var next_uid := 1
	var loads: Array = []            # ad unit ids requested
	var interstitial_uids := {}
	var shown := 0
	var fail_loads := 0              # fail this many loads first
	var watch_to_end := true         # the player sits through the rewarded ad
	var reward_after_close := false  # some SDKs report the reward after the close

	func initialize() -> void:
		on_initialization_complete.emit.call_deferred({})

	func set_request_configuration(_c: Dictionary, _ids: Array) -> void:
		pass

	func set_ios_app_pause_on_background(_p: bool) -> void:
		pass

	func create() -> int:
		next_uid += 1
		return next_uid

	func load(unit: String, _req: Dictionary, _kw: Array, uid: int) -> void:
		loads.append(unit)
		var rewarded: bool = unit == StoreConfig.TEST_REWARDED[StoreConfig.platform()]
		if not rewarded:
			interstitial_uids[uid] = true
		if fail_loads > 0:
			fail_loads -= 1
			var err := {"code": 3, "domain": "x", "message": "no fill", "cause": {}, "response_info": {}}
			if rewarded:
				on_rewarded_ad_failed_to_load.emit.call_deferred(uid, err)
			else:
				on_interstitial_ad_failed_to_load.emit.call_deferred(uid, err)
		elif rewarded:
			on_rewarded_ad_loaded.emit.call_deferred(uid)
		else:
			on_interstitial_ad_loaded.emit.call_deferred(uid)

	func show(uid: int) -> void:
		shown += 1
		_play(uid)

	func _play(uid: int) -> void:
		await Engine.get_main_loop().process_frame
		if interstitial_uids.has(uid):
			on_interstitial_ad_dismissed_full_screen_content.emit(uid)
			return
		var item := {"amount": 1, "type": "boost"}
		if watch_to_end and not reward_after_close:
			on_rewarded_ad_user_earned_reward.emit(uid, item)
		on_rewarded_ad_dismissed_full_screen_content.emit(uid)
		if watch_to_end and reward_after_close:
			await Engine.get_main_loop().process_frame
			on_rewarded_ad_user_earned_reward.emit(uid, item)

	func destroy(_uid: int) -> void:
		pass


func check(cond: bool, what: String) -> void:
	print(("  ok    " if cond else "  FAIL  ") + what)
	if not cond:
		ok = false


func _initialize() -> void:
	create_timer(60.0).timeout.connect(func():
		print("MONETIZATION TEST TIMED OUT")
		quit(2))
	_run.call_deferred()


func _frames(n: int) -> void:
	for _i in n:
		await process_frame


func _set_ad_plugin(plugin) -> void:
	var api := "res://addons/admob/gdscript/src/api/"
	for path in ["MobileAds", "RewardedAd", "RewardedAdLoader", "InterstitialAd", "InterstitialAdLoader"]:
		load(api + path + ".gd")._plugin = plugin


func _run() -> void:
	var Store = load("res://scripts/monetization/revenuecat_store.gd")
	var Ads = load("res://scripts/monetization/admob_ads.gd")
	var Mobile = load("res://scripts/monetization/mobile_provider.gd")
	var Config = load("res://scripts/monetization/store_config.gd")
	check(Store != null and Ads != null and Mobile != null and Config != null, "the real providers compile")

	print("store config")
	check(Config.rewarded_unit("boost_2x_heat") == Config.TEST_REWARDED[Config.platform()],
		"debug builds only ever use Google's test ad units")
	check(Config.missing_for_release("Android").size() > 0, "the release check notices missing ids")

	print("RevenueCat store (fake plugin)")
	var fake := FakeRevenueCat.new()
	fake.owned = ["golden_dryer"]
	var store = Store.new()
	root.add_child(store)
	var got := {"purchased": [], "failed": [], "restored": [], "restore_done": []}
	store.purchased.connect(func(id): got.purchased.append(id))
	store.failed.connect(func(id, r): got.failed.append([id, r]))
	store.restored.connect(func(id): got.restored.append(id))
	store.restore_done.connect(func(n, e): got.restore_done.append([n, e]))
	Engine.register_singleton("GodotxRevenueCat", fake)
	store.start(["remove_ads_2x", "golden_hair_dryer"])
	await _frames(3)
	check(fake.calls.has("initialize") and fake.calls.has("fetch_products"), "configures RevenueCat and asks for prices")
	check(store.price_string("remove_ads_2x", "$2.99") == "€1,99", "uses the store's local price")
	check(store.price_string("unknown", "$9") == "$9", "falls back when the store has no price")
	check(got.restored == ["golden_hair_dryer"], "grants what the account already owns at startup")
	store.purchase("remove_ads_2x")
	await _frames(3)
	check(got.purchased == ["remove_ads_2x"], "a successful purchase is reported once")
	fake.next_purchase = "cancel"
	store.purchase("golden_hair_dryer")
	await _frames(3)
	check(got.failed.size() == 1 and got.failed[0][1] == "cancelled", "a cancelled purchase says so")
	fake.next_purchase = "error"
	store.purchase("golden_hair_dryer")
	await _frames(3)
	check(got.failed.size() == 2 and got.failed[1][1] == "no connection, try again later", "store errors read nicely")
	got.restored.clear()
	store.restore()
	await _frames(4)
	check(got.restore_done == [[2, ""]], "restore reports how many things it found")
	check(got.restored.has("remove_ads_2x") and got.restored.has("golden_hair_dryer"), "restore grants both products")
	Engine.unregister_singleton("GodotxRevenueCat")
	store.queue_free()
	await _frames(2)
	fake.free()

	print("grant rules (Monetization autoload)")
	var mon = root.get_node("Monetization")
	var gs = root.get_node("GameState")
	gs.owns_golden_dryer = false
	gs.golden_equipped = false
	mon._grant("golden_hair_dryer")
	check(gs.owns_golden_dryer and gs.golden_equipped, "buying the golden dryer equips it")
	gs.golden_equipped = false
	mon._grant("golden_hair_dryer")
	check(not gs.golden_equipped, "a later restore doesn't switch it back on")
	gs.owns_golden_dryer = false

	print("mobile provider without plugins")
	var mobile = Mobile.new()
	root.add_child(mobile)
	mobile.initialize()
	var res := {"rew": [], "buy": [], "restore": []}
	mobile.rewarded_failed.connect(func(p, r): res.rew.append(r))
	mobile.purchase_failed.connect(func(p, r): res.buy.append(r))
	mobile.restore_finished.connect(func(n, e): res.restore.append(e))
	check(not mobile.is_rewarded_ready("boost_2x_heat"), "no ads are offered without the AdMob plugin")
	mobile.show_rewarded("boost_2x_heat")
	mobile.purchase("remove_ads_2x")
	mobile.restore_purchases()
	check(res.rew.size() == 1 and res.buy.size() == 1 and res.restore.size() == 1,
		"every request still ends with exactly one answer")
	mobile.queue_free()

	print("AdMob ads (fake native plugin)")
	var consent := FakeConsent.new()
	var ump = load("res://addons/admob/gdscript/src/ump/api/UserMessagingPlatform.gd")
	var info = load("res://addons/admob/gdscript/src/ump/api/ConsentInformation.gd")
	var form = load("res://addons/admob/gdscript/src/ump/api/ConsentForm.gd")
	ump._plugin = consent
	info._plugin = consent
	form._plugin = consent
	var fake_ads := FakeAds.new()
	fake_ads.fail_loads = 1
	_set_ad_plugin(fake_ads)
	var ads = Ads.new()
	root.add_child(ads)
	var done := []
	ads.rewarded_done.connect(func(p, okay, reason): done.append([p, okay, reason]))
	ads.show_rewarded("boost_2x_heat")
	check(done.size() == 1 and not done[0][1], "showing before anything loaded fails politely")
	ads.start()
	var waited := 0.0
	while not ads.is_rewarded_ready("boost_2x_heat") and waited < 12.0:
		await create_timer(0.1).timeout
		waited += 0.1
	check(consent.form_shown, "an EEA player is shown the consent form first")
	check(ads.can_request_ads(), "after answering it, ads may be requested")
	check(ads.privacy_options_required(), "the privacy-choices button is offered")
	check(ads.is_rewarded_ready("boost_2x_heat"), "then a rewarded ad loads (%.1fs, after one failed load)" % waited)
	check(fake_ads.loads.size() >= 3, "the failed load was retried")
	ads.show_rewarded("boost_2x_heat")
	await _frames(6)
	check(done.size() == 2 and done[1][1], "watching to the end gives the reward")
	await _frames(4)
	check(ads.is_rewarded_ready("helper_rush"), "the next ad is loaded right away")
	fake_ads.reward_after_close = true
	ads.show_rewarded("helper_rush")
	await create_timer(0.3).timeout
	check(done.size() == 3 and done[2][1], "a reward that lands just after the close still counts")
	await _frames(4)
	fake_ads.watch_to_end = false
	ads.show_rewarded("boost_2x_heat")
	await create_timer(1.5).timeout
	check(done.size() == 4 and not done[3][1] and done[3][2] == "closed early", "closing early gives nothing")
	var closed := []
	ads.interstitial_done.connect(func(p): closed.append(p))
	ads.show_interstitial("shed_exit")
	await _frames(4)
	check(closed == ["shed_exit"], "an interstitial shows and closes")
	ads.set_interstitials_enabled(false)
	var before: int = fake_ads.shown
	ads.show_interstitial("shed_exit")
	check(closed.size() == 2 and fake_ads.shown == before, "after Remove Ads no interstitial shows (the call still answers)")
	ads.queue_free()
	await _frames(2)
	ump._plugin = null
	info._plugin = null
	form._plugin = null
	consent.free()
	_set_ad_plugin(null)
	fake_ads.free()

	print("MONETIZATION TEST " + ("PASSED" if ok else "FAILED"))
	quit(0 if ok else 1)
