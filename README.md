# A Game About Melting A Glacier (prototype)

A portrait, one-thumb incremental game made in **Godot 4.4**. Tap or hold on the
glacier to melt it, earn meltwater, buy hotter tools and helpers, dig up frozen
junk, and free the village underneath.

## Play it on your phone (iPhone or Android)

**https://alexanderjcurry.github.io/melt-a-glacier/**

Open the link in Safari (or Chrome on Android). For a full-screen, app-like
version on iPhone, tap **Share > Add to Home Screen** and launch it from the
new icon. Progress is saved in the browser.

Every push to `main` rebuilds and republishes this link automatically
(`.github/workflows/web.yml`: it imports the project, runs the smoke test,
exports the web build, and deploys it to GitHub Pages). Watch runs in the
repo's **Actions** tab; a new version is live a minute or two after it goes green.
It needs **Settings > Pages > Source: GitHub Actions** (one-time) and a public
repo (or GitHub Pro for a private one).

The web build is a playtest build. It runs at real speed, includes the
developer tools (bottom of the Shop tab), and fakes ads and purchases.
Real ads and in-app purchases only work in the native app builds.

## Run it on Windows (5 minutes)

1. Download **Godot 4.4.x (Standard, not .NET)** from https://godotengine.org/download/windows/ and unzip it. There's no installer.
2. Open Godot, click **Import**, and pick `project.godot` in this folder.
3. Press **F5** (or the ▶ button). The game opens in a phone-shaped window. Click to tap, and hold the mouse button to keep melting.

The first import shows a few font warnings (`_font_get_glyph_contours`). Those are harmless and come from the emoji font.

The project uses Godot's **Compatibility** renderer (OpenGL ES 3 / WebGL 2).
It's the recommended choice for 2D mobile games, runs on the widest range of
phones, and is the only renderer the web build supports.

## Play it on an Android phone (native app)

Fastest path, no APK needed:
1. On the phone, enable **Developer options**, then turn on **USB debugging**.
2. In Godot, open **Editor > Manage Export Templates** and click **Download and Install**.
3. Install **JDK 17** and the **Android SDK** (the easiest way is to install Android Studio once). Then set their paths in **Editor > Editor Settings > Export > Android**.
4. Plug the phone in. An Android icon appears at the top right of Godot. Click it to install and run the game on the phone.

To make an APK you can share, use **Project > Export > Android > Export Project**. A preset is already included. Change `package/unique_name` from `com.example.meltaglacier` to your own (for example `com.yourname.meltaglacier`) before you ever upload to Google Play, because you can't change it later.

iOS comes later through Codemagic (Godot workflow). Nothing in the code is Android-only.

## What's in the prototype

| Feature | Where |
|---|---|
| Tap = 1 burst, hold = 5 taps/sec, with steam, heat glow, floating numbers and screen shake on layer breaks | `scripts/glacier_view.gd` |
| 12 ice layers that shrink visibly, from Fresh Snow down to The Last Chunk | `Balance.LAYERS / LAYER_HP` |
| 6 tools: Hair Dryer, Heat Lamp, Blowtorch, Flamethrower, Lava Hose, Orbital Mirror (gated by depth) | `Balance.TOOLS` |
| 4 stats: Heat Output, Tool Size, Auto-Melt Rate, Steam Sell multiplier | `Balance.STATS` |
| 5 helpers: Penguins with tiny torches, Sauna Crew, an adopted volcano, a Hot Spring Resort, a Sun-Lens Satellite. They stand on the ice | `Balance.HELPERS` |
| 11 buried finds (mammoth, snowmobile, 1970s caveman...) that melt out and sell for a cash burst, plus a collection log (Finds tab) | `Balance.DISCOVERIES` |
| Offline earnings: helpers keep working at 50% for up to 8h, with an optional "watch ad to double" | `GameState.check_offline()` |
| Rewarded ad: 2x heat for 5 min (stacks to 15) | boost bar + Shop |
| IAP: Remove Ads + permanent 2x ($2.99), Golden Hair Dryer cosmetic ($0.99), Restore | Shop tab |
| Light interstitials: only after layer 3, at most one every 4 min, never if Remove Ads is owned | `Monetization.maybe_show_interstitial()` |
| Ending: the village appears, the valley turns green, and a stats screen you can screenshot, then "Melt a new glacier" | `main.gd _show_win()` |
| Autosave every 10s and when the app is backgrounded (`user://save.json`) | `GameState` |

**Developer menu:** when you run from the editor, and in exports tagged `playtest` (the web build), the bottom of the **Shop** tab has free meltwater, a x10/x100 game-speed toggle, "simulate 2h away", and wipe save. Other release exports hide it. Remove `playtest` from the Web preset's `custom_features` before a public launch.

## Project layout

```
project.godot            720x1280 portrait, Compatibility renderer, autoloads
export_presets.cfg       Web (playtest) and Android export presets
.github/workflows/web.yml  builds + publishes the phone-playable web version
scenes/main.tscn         the only scene (UI is built in code)
scripts/balance.gd       ALL tunable numbers: layers, tools, stats, helpers, finds, ad rules
scripts/game_state.gd    autoload: economy, melting, offline, save/load
scripts/glacier_view.gd  draws the valley/glacier and handles touch
scripts/main.gd          HUD, shop tabs, toasts, popups, ending
scripts/shop_row.gd      one shop list row
scripts/fmt.gd           1.23K / 4.5M number formatting
scripts/monetization/    ad + IAP interface, stub provider, autoload facade
fonts/                   subset Noto Color Emoji (the placeholder art) + license
tests/smoke_test.gd      headless test: godot --headless -s res://tests/smoke_test.gd
tools/pacing_sim.py      greedy-player simulation used to tune balance.gd
tools/subset_emoji.sh    rebuild the emoji font if you add new emoji
```

## Tuning the pacing

Every number lives in `scripts/balance.gd`. `tools/pacing_sim.py` mirrors it. With the current numbers, a perfect player who holds the screen half the time finishes in about **1 hour**, and one who holds a quarter of the time takes about **1.7 hours**. Real players buy less efficiently and take breaks, so expect roughly 2 to 4 hours. That is an estimate until real people playtest it. To make the game longer, raise the later `LAYER_HP` entries.

## Adding real ads and purchases later

The game only ever calls the `Monetization` autoload. That autoload forwards to one `MonetizationProvider`. Right now that provider is `StubMonetizationProvider`, which shows a fake 3-second "ad" and approves every purchase, so you can test the whole flow.

To go live:
1. Install the plugins. For ads, use the **Poing Studios Godot AdMob plugin**. For purchases, use the official **GodotGooglePlayBilling** plugin (Android) and an iOS StoreKit plugin later. If you want one purchase API across both stores, RevenueCat has a Godot community plugin too.
2. Create `scripts/monetization/admob_billing_provider.gd` that `extends MonetizationProvider`. Implement `initialize`, `show_rewarded`, `show_interstitial`, `purchase`, `restore_purchases` and `price_string`, and emit the matching signals.
3. Return your new provider from `_create_provider()` in `scripts/monetization/monetization.gd`.
4. Create the same IDs in the store consoles: products `remove_ads_2x` and `golden_hair_dryer` (both non-consumable), and rewarded placements `boost_2x_heat` and `offline_double`.

No game code changes beyond that.

## Placeholder art

The visuals are drawn with shapes, and the objects are emoji from a bundled Noto Color Emoji subset (Apache 2.0 / OFL, see `fonts/`). If you add a new emoji to the code, re-run `tools/subset_emoji.sh`, or it shows as a box. Swapping in real sprites later means replacing the `_text(icon...)` calls in `glacier_view.gd` with `draw_texture`.
