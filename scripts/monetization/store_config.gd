class_name StoreConfig
## Every ID the live ad network and stores need, in one place.
##
## None of these are secrets: AdMob ad unit IDs and RevenueCat *public* SDK keys
## ship inside every copy of the app. (Never put a RevenueCat *secret* key, a
## keystore password or an App Store Connect key in this repo.)
##
## Where each value comes from is in docs/LAUNCH.md. Empty values are safe: that
## ad format or store is simply switched off on that platform, and
## tests/release_check.gd fails the store build so nothing ships half-wired.
##
## The AdMob *app* IDs (the ones with a "~") are not here: the AdMob plugin reads
## them from project.godot, [admob] section, so it can write them into the
## Android manifest and the iOS Info.plist.

# --- RevenueCat (in-app purchases) ---------------------------------------------------
# RevenueCat dashboard > Project > API keys > the public app-specific keys.
const REVENUECAT_KEY_ANDROID := ""   # starts with "goog_"
const REVENUECAT_KEY_IOS := ""       # starts with "appl_"

# RevenueCat entitlement identifier -> the game's product id (monetization.gd).
# In RevenueCat, attach the store product of the same name to each entitlement.
const ENTITLEMENT_TO_PRODUCT := {
	"remove_ads": "remove_ads_2x",
	"golden_dryer": "golden_hair_dryer",
}

# --- AdMob (ads) -------------------------------------------------------------------------
# AdMob > Apps > (the app) > Ad units. Release builds use these. Debug builds,
# the editor and anything with an empty id use Google's test units, so you can
# never accidentally click your own live ads (that gets AdMob accounts banned).
const ADMOB_REWARDED := {"Android": "", "iOS": ""}
const ADMOB_INTERSTITIAL := {"Android": "", "iOS": ""}

# Optional: a separate rewarded unit per placement, only for nicer AdMob reports.
# Placements not listed here use ADMOB_REWARDED.
#   "boost_2x_heat": {"Android": "ca-app-pub-.../...", "iOS": "ca-app-pub-.../..."},
const ADMOB_REWARDED_BY_PLACEMENT := {}

# The cosy game shouldn't show grim ads. "G", "PG", "T" or "MA"; lower = less fill.
const MAX_AD_CONTENT_RATING := "PG"

# Google's public test units (https://developers.google.com/admob/android/test-ads).
const TEST_REWARDED := {
	"Android": "ca-app-pub-3940256099942544/5224354917",
	"iOS": "ca-app-pub-3940256099942544/1712485313",
}
const TEST_INTERSTITIAL := {
	"Android": "ca-app-pub-3940256099942544/1033173712",
	"iOS": "ca-app-pub-3940256099942544/4411468910",
}

# --- Links shown in the game ---------------------------------------------------------------
const PRIVACY_POLICY_URL := "https://alexanderjcurry.github.io/melt-a-glacier/privacy.html"


static func platform() -> String:
	## Which set of ids to use. Only Android and iOS ship with ads and purchases;
	## anything else (the editor, tests) borrows the Android ids.
	return "iOS" if OS.get_name() == "iOS" else "Android"


static func use_test_ads() -> bool:
	return OS.is_debug_build()


static func revenuecat_key() -> String:
	match OS.get_name():
		"Android":
			return REVENUECAT_KEY_ANDROID
		"iOS":
			return REVENUECAT_KEY_IOS
	return ""


static func rewarded_unit(placement: String) -> String:
	var live: String = ADMOB_REWARDED.get(platform(), "")
	var per: Dictionary = ADMOB_REWARDED_BY_PLACEMENT.get(placement, {})
	if per.get(platform(), "") != "":
		live = per[platform()]
	return TEST_REWARDED.get(platform(), "") if use_test_ads() else live


static func interstitial_unit() -> String:
	var live: String = ADMOB_INTERSTITIAL.get(platform(), "")
	return TEST_INTERSTITIAL.get(platform(), "") if use_test_ads() else live


static func missing_for_release(os_name: String) -> PackedStringArray:
	## What still has to be filled in before a store build for `os_name`.
	var out := PackedStringArray()
	var key := REVENUECAT_KEY_ANDROID if os_name == "Android" else REVENUECAT_KEY_IOS
	var prefix := "goog_" if os_name == "Android" else "appl_"
	if not key.begins_with(prefix):
		out.append("StoreConfig.REVENUECAT_KEY_%s (a public '%s...' key)" % [os_name.to_upper(), prefix])
	if not str(ADMOB_REWARDED.get(os_name, "")).begins_with("ca-app-pub-"):
		out.append("StoreConfig.ADMOB_REWARDED[\"%s\"]" % os_name)
	if not str(ADMOB_INTERSTITIAL.get(os_name, "")).begins_with("ca-app-pub-"):
		out.append("StoreConfig.ADMOB_INTERSTITIAL[\"%s\"]" % os_name)
	for unit in [ADMOB_REWARDED.get(os_name, ""), ADMOB_INTERSTITIAL.get(os_name, "")]:
		if str(unit).begins_with("ca-app-pub-3940256099942544"):
			out.append("a Google *test* ad unit is set as a live unit (%s)" % unit)
	var setting := "admob/general/%s/app_id" % os_name.to_lower()
	var app_id := str(ProjectSettings.get_setting(setting, ""))
	if not app_id.contains("~") or app_id.begins_with("ca-app-pub-3940256099942544"):
		out.append("project.godot %s (your AdMob app id, with a '~')" % setting)
	return out
