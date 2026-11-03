#!/bin/bash
# Downloads the native halves of the ad and store plugins (they are big and
# versioned, so they're not in git). The GDScript halves are in addons/.
#
#   bash tools/fetch_plugins.sh android    # before an Android export
#   bash tools/fetch_plugins.sh ios        # before an iOS export (on the Mac / Codemagic)
#   bash tools/fetch_plugins.sh all
#
# Works in Git Bash on Windows too. Re-running is safe.
set -euo pipefail
cd "$(dirname "$0")/.."
source tools/plugin_versions.env
WHAT="${1:-all}"
CACHE="${PLUGIN_CACHE:-$HOME/.cache/melt-a-glacier-plugins}"
mkdir -p "$CACHE"
GH=https://github.com

fetch() {  # url file
	if [ ! -s "$CACHE/$2" ]; then
		echo "Downloading $2"
		curl -fSL --retry 3 -o "$CACHE/$2.part" "$1"
		mv "$CACHE/$2.part" "$CACHE/$2"
	fi
}

admob() {  # android|ios
	local f="admob-$1-template-v$GODOT_VERSION-$ADMOB_PLUGIN_VERSION.zip"
	fetch "$GH/poingstudios/godot-admob-plugin/releases/download/$ADMOB_PLUGIN_VERSION/$1-template-v$GODOT_VERSION.zip" "$f"
	rm -rf "addons/admob/$1/bin"
	mkdir -p "addons/admob/$1/bin"
	unzip -q -o "$CACHE/$f" -d "addons/admob/$1/bin"
	echo "AdMob $1 libraries -> addons/admob/$1/bin"
}

revenuecat() {  # android|ios
	local f="godotx_revenue_cat-$REVENUECAT_PLUGIN_VERSION.zip"
	fetch "$GH/godot-x/revenuecat/releases/download/$REVENUECAT_PLUGIN_VERSION/godotx_revenue_cat.zip" "$f"
	local tmp
	tmp="$(mktemp -d)"
	if [ "$1" = android ]; then
		unzip -q -o "$CACHE/$f" 'godotx_revenue_cat/android/*' -d "$tmp"
		rm -rf android/revenue_cat
		mkdir -p android
		cp -R "$tmp/godotx_revenue_cat/android/revenue_cat" android/
		echo "RevenueCat Android library -> android/revenue_cat"
	else
		# Skip the debug symbols and the mac/tv/watch/vision slices (~900 MB unzipped).
		unzip -q -o "$CACHE/$f" 'godotx_revenue_cat/ios/*' -x '*/dSYMs/*' -d "$tmp"
		rm -rf ios/plugins/revenue_cat
		mkdir -p ios/plugins
		cp -R "$tmp/godotx_revenue_cat/ios/plugins/revenue_cat" ios/plugins/
		echo "RevenueCat iOS plugin -> ios/plugins/revenue_cat"
	fi
	rm -rf "$tmp"
}

case "$WHAT" in
	android) admob android; revenuecat android ;;
	ios) admob ios; revenuecat ios ;;
	all) admob android; revenuecat android; admob ios; revenuecat ios ;;
	*) echo "usage: $0 android|ios|all"; exit 1 ;;
esac
