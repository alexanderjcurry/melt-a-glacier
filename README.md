# A Game About Melting A Glacier (prototype)

A first-person, landscape incremental game made in **Godot 4.4**. You walk around
a valley that's buried under a glacier, aim a hair dryer at the ice and melt it
block by block. Meltwater is money: spend it at the shed on hotter tools,
upgrades and helpers (penguins with tiny torches, a sauna crew, an adopted
volcano called Kevin). Frozen junk melts out as you dig, and at the very bottom
there's a whole village. Melt the last block and summer comes back.

## Play it on your phone (iPhone or Android)

**https://alexanderjcurry.github.io/melt-a-glacier/**

Open the link in Safari (or Chrome on Android) and turn the phone sideways.
For a full-screen, app-like version on iPhone, tap **Share > Add to Home Screen**
and launch it from the new icon. Progress is saved in the browser.

| Phone | Computer |
|---|---|
| Left thumb: drag anywhere on the left side to walk | WASD or arrow keys |
| Right thumb: drag to look around | Click once, then move the mouse |
| Hold the 🔥 button to melt (you can drag from it to aim) | Hold the left mouse button |
| JUMP button (also climbs 2-block ledges) | Space |
| "Enter the shed" button appears at the shed door | E at the shed door, Esc to leave |

Every push to `main` rebuilds and republishes this link automatically
(`.github/workflows/web.yml`: it imports the project, runs the smoke test,
exports the web build, and deploys it to GitHub Pages). Watch runs in the
repo's **Actions** tab; a new version is live a minute or two after it goes green.
It needs **Settings > Pages > Source: GitHub Actions** (one-time) and a public
repo (or GitHub Pro for a private one).

The web build is a playtest build. It includes the developer tools (bottom of
the shed's Shop tab) and fakes ads and purchases. Real ads and in-app purchases
only work in the native app builds.

## Run it on Windows (5 minutes)

1. Download **Godot 4.4.x (Standard, not .NET)** from https://godotengine.org/download/windows/ and unzip it. There's no installer.
2. Open Godot, click **Import**, and pick `project.godot` in this folder.
3. Press **F5** (or the ▶ button). Click in the window to grab the mouse.

The first import shows a few font warnings (`_font_get_glyph_contours`). Those are harmless and come from the emoji font.

The project uses Godot's **Compatibility** renderer (OpenGL ES 3 / WebGL 2).
It runs on the widest range of phones and is the only renderer the web build
supports. On phones the 3D view is drawn at a lower resolution than the HUD so
it stays smooth (`World._fit_render_scale()`).

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
| The glacier: ~4,600 one-metre ice blocks in 8 layers by depth (Fresh Snow 1 hp down to The Last Chunk 128 hp). Deeper ice is harder and worth more. Drawn with one MultiMesh | `scripts/ice_grid.gd`, `Balance.LAYERS` |
| First-person walking with voxel collision, auto step-up, jumping and ledge climbing (no physics engine) | `scripts/player.gd` |
| The heat tool: aim with the crosshair, hold to melt a ball of ice, flame and steam effects | `Player._update_tool()` |
| 6 tools bought in order at the shed: Hair Dryer, Heat Lamp, Blowtorch, Flamethrower, Lava Hose, Orbital Mirror | `Balance.TOOLS` |
| 5 upgrades: Heat Output, Wider Nozzle, Longer Reach, Steam Sell, Crampon Boots | `Balance.UPGRADES` |
| Helpers: penguins and the sauna crew walk on the ice melting it, Kevin the volcano lobs lava bombs | `scripts/helpers.gd`, `Balance.HELPERS` |
| 11 buried finds frozen at fixed depths (mitten, snowmobile, mammoth, 1970s caveman, dinosaur egg...). They melt out, sell for a burst of water, and stay in the world | `World._place_finds()`, `Balance.DISCOVERIES` |
| A village frozen inside the glacier. The church spire pokes out of the top as a hint | `World._build_village()` |
| The valley greens up and flowers bloom where the ice is gone; villagers come out at the end | `World._update_slow()` |
| Offline melting: helpers keep working at 25% for up to 4 h, with "watch an ad to double it" | `GameState.check_offline()` |
| Rewarded ad: 2x heat for 5 min (stacks to 15). IAP: Remove Ads + permanent 2x, Golden Hair Dryer, Restore | HUD button, shed Shop tab |
| Light interstitials: only when leaving the shed, after 15% of the ice is gone, at most every 4 min, never with Remove Ads | `Monetization.maybe_show_interstitial()` |
| Ending with a stats screen, then walk around the village or melt a new glacier | `Hud.show_ending()` |
| Short onboarding hints the first time | `World._update_coach()` |
| Autosave every 10s and when the app is backgrounded (`user://save3d.json`), glacier included | `GameState` |

**Developer menu:** when you run from the editor, and in exports tagged `playtest` (the web build), the bottom of the shed's **Shop** tab has free meltwater, a x10/x100 melting speed toggle, "simulate 2h away", "melt everything" and "start over". Other release exports hide it. Remove `playtest` from the Web preset's `custom_features` before a public launch.

## Project layout

```
project.godot            1280x720 landscape, Compatibility renderer, autoloads
export_presets.cfg       Web (playtest) and Android export presets
.github/workflows/web.yml  builds + publishes the phone-playable web version
scenes/world.tscn        the only scene; everything is built in code
scripts/balance.gd       ALL tunable numbers: layers, tools, upgrades, helpers, finds, ad rules
scripts/game_state.gd    autoload: economy, shed purchases, offline, save/load
scripts/world.gd         builds the valley (sky, mountains, village, shed) and wires everything up
scripts/ice_grid.gd      the glacier: block data, melting, raycasts, collision, save string
scripts/player.gd        first-person movement, collision, the heat tool
scripts/touch_controls.gd  phone controls (multi-touch stick, look, melt, jump)
scripts/helpers.gd       penguins, sauna crew, Kevin the volcano
scripts/hud.gd           HUD, shed menu, toasts, popups, ending
scripts/ui_theme.gd      shared UI look, emoji font, particle texture
scripts/shop_row.gd      one shop list row
scripts/fmt.gd           1.23K / 4.5M number formatting
scripts/monetization/    ad + IAP interface, stub provider, autoload facade
fonts/                   subset Noto Color Emoji (the placeholder art) + license
tests/smoke_test.gd      headless test: godot --headless -s res://tests/smoke_test.gd
tests/screenshots.gd     renders screenshots of key moments (see the top of the file)
tools/subset_emoji.sh    rebuild the emoji font if you add new emoji
```

## Tuning the pacing

Every number lives in `scripts/balance.gd`. The whole glacier is about 81,000 hp,
and a block pays out its hp in meltwater (times the Steam Sell upgrade). To make
the game longer, raise the deeper `LAYERS` hp values (and the tool costs with
them). The first playtests will tell us how long a run really takes.

## Adding real ads and purchases later

The game only ever calls the `Monetization` autoload. That autoload forwards to one `MonetizationProvider`. Right now that provider is `StubMonetizationProvider`, which shows a fake 3-second "ad" and approves every purchase, so you can test the whole flow.

To go live:
1. Install the plugins. For ads, use the **Poing Studios Godot AdMob plugin**. For purchases, use the official **GodotGooglePlayBilling** plugin (Android) and an iOS StoreKit plugin later. If you want one purchase API across both stores, RevenueCat has a Godot community plugin too.
2. Create `scripts/monetization/admob_billing_provider.gd` that `extends MonetizationProvider`. Implement `initialize`, `show_rewarded`, `show_interstitial`, `purchase`, `restore_purchases` and `price_string`, and emit the matching signals.
3. Return your new provider from `_create_provider()` in `scripts/monetization/monetization.gd`.
4. Create the same IDs in the store consoles: products `remove_ads_2x` and `golden_hair_dryer` (both non-consumable), and rewarded placements `boost_2x_heat` and `offline_double`.

No game code changes beyond that.

## Placeholder art

Everything is simple shapes built in code (boxes, cones, prisms), and the
characters and finds are emoji drawn as 3D labels, from a bundled Noto Color
Emoji subset (Apache 2.0 / OFL, see `fonts/`). If you add a new emoji to the
code, re-run `tools/subset_emoji.sh`, or it shows as a box. Real models can
replace the shapes one at a time (the shed, the houses, the helpers).
