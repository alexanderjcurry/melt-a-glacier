# A Game About Melting A Glacier (prototype)

A first-person, landscape incremental game made in **Godot 4.4**. You walk around
a valley that's buried under a glacier, aim a hair dryer at the ice and slowly
dig into it. Meltwater is money: spend it at the shed on hotter tools,
upgrades and helpers (penguins with tiny torches, a sauna crew, an adopted
volcano called Kevin). Frozen junk melts out as you dig, and at the very bottom
there's a whole village. Melt the last of it and summer comes back.

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
| JUMP button; hold it to fly with the jetpack | Space (hold to fly) |
| 🏠 Stuck? Respawn button (top left) | R |
| Walk into the 🏠 shed, look at something, then tap the green BUY button (it takes the 🔥 button's place) | Walk in, aim at something, click (or press E) |

Every push to `main` rebuilds and republishes this link automatically
(`.github/workflows/web.yml`: it imports the project, runs the smoke test,
exports the web build, and deploys it to GitHub Pages). Watch runs in the
repo's **Actions** tab; a new version is live a minute or two after it goes green.
It needs **Settings > Pages > Source: GitHub Actions** (one-time) and a public
repo (or GitHub Pro for a private one).

The web build is a playtest build. It includes the developer tools (at the end of
the catalogue on the table inside the shed door) and fakes ads and purchases. Real ads and in-app purchases
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
| The glacier: smooth, diggable ice (about 4,900 m³) stored as a density field on a 0.5 m grid and re-meshed in 8x8 chunks as you melt it (surface nets). 8 layers by depth, from Fresh Snow to The Last Chunk: deeper ice is harder and worth more. Crevasses, snow cover, blue carved ice and a wet glow where the heat lands are drawn by `shaders/ice.gdshader` | `scripts/ice_field.gd`, `Balance.LAYERS` |
| The level: the glacier's shape, its crevasses and the valley around it are one dictionary, so more levels are more dictionaries | `scripts/levels.gd` |
| First-person walking (CharacterBody3D on the ice's collision mesh), step-up, a jetpack (hold JUMP, fuel refills on landing) and a respawn button | `scripts/player.gd` |
| The valley: generated mountains with rock and snow, a cloudy sky, the lake and a meltwater stream, pine forest, boulders | `scripts/scenery.gd`, `shaders/` |
| The heat tool: aim with the crosshair, hold to melt a ball of ice, flame and steam effects | `Player._update_tool()` |
| The shed is a walk-in store: tools hang on the pegboard, upgrades sit on the workbench, helpers wait in the hiring corner, finds go on the shelf by the door, and the catalogue on the table has the boost and purchases. Look at anything for a paper price card, then buy it where it stands | `scripts/shed.gd`, `Hud.set_shop_info()` |
| 6 tools bought in order at the shed: Hair Dryer, Heat Lamp, Blowtorch, Flamethrower, Lava Hose, Orbital Mirror (the same models you hold) | `Balance.TOOLS`, `scripts/props.gd` |
| 5 upgrades: Heat Output, Wider Nozzle, Longer Reach, Steam Sell, Crampon Boots | `Balance.UPGRADES` |
| Helpers (3D models built in code): penguins with tiny torches and the sauna crew walk on the ice melting it, Kevin the volcano lobs lava bombs and watches you | `scripts/helpers.gd`, `scripts/creatures.gd`, `Balance.HELPERS` |
| 11 buried finds frozen at fixed depths (mitten, snowmobile, mammoth, 1970s caveman, dinosaur egg...). They melt out, sell for a burst of water, and stay in the world | `World._place_finds()`, `Balance.DISCOVERIES` |
| A village frozen inside the glacier. The church spire pokes out of the top as a hint | `World._build_village()` |
| The valley greens up and flowers bloom where the ice is gone; villagers come out at the end | `World._update_slow()` |
| Loose ice melts by itself: bits left floating, and small chunks on the ground (under about 4 m³), shrink away over a few seconds, corners first, and still pay out | `IceField._melt_floating()` |
| No "while you were away" earnings: it's a game you play in a sitting, so nothing melts while it's closed | |
| Rewarded ad: 2x heat for 5 min (stacks to 15). IAP: Remove Ads + permanent 2x, Golden Hair Dryer, Restore | HUD button, the catalogue in the shed |
| Light interstitials: only when leaving the shed, after 15% of the ice is gone, at most every 4 min, never with Remove Ads | `Monetization.maybe_show_interstitial()` |
| Ending with a stats screen, then walk around the village or melt a new glacier | `Hud.show_ending()` |
| Short onboarding hints the first time | `World._update_coach()` |
| Autosave every 10s and when the app is backgrounded (`user://save3d.json`), glacier included | `GameState` |

**Developer menu:** when you run from the editor, and in exports tagged `playtest` (the web build), the end of the **catalogue** (the book on the table inside the shed door) has free meltwater, a x10/x100 melting speed toggle, "melt everything" and "start over". Other release exports hide it. Remove `playtest` from the Web preset's `custom_features` before a public launch.

## Project layout

```
project.godot            1280x720 landscape, Compatibility renderer, autoloads
export_presets.cfg       Web (playtest) and Android export presets
.github/workflows/web.yml  builds + publishes the phone-playable web version
scenes/world.tscn        the only scene; everything is built in code
scripts/balance.gd       ALL tunable numbers: layers, tools, upgrades, helpers, finds, ad rules
scripts/game_state.gd    autoload: economy, shed purchases, save/load
scripts/levels.gd        level descriptions: glacier shape, crevasses, valley, stream
scripts/world.gd         builds the valley (village, finds) and wires everything up
scripts/shed.gd          the walk-in shed: building, sections, what you look at and buy
scripts/props.gd         models of the six tools and the upgrade items
scripts/scenery.gd       mountains, sky, lake, stream, forest, boulders
scripts/ice_field.gd     the glacier: density field, meshing, melting, collision, save string
scripts/player.gd        first-person movement, jetpack, respawn, the heat tool
scripts/creatures.gd     3D models of the helpers (penguin, sauna crew, Kevin)
scripts/mesh_kit.gd      tiny modelling kit (ellipsoids, cylinders, boxes) for the models
scripts/touch_controls.gd  phone controls (multi-touch stick, look, melt, jump)
scripts/helpers.gd       penguins, sauna crew, Kevin the volcano
scripts/hud.gd           HUD, shed price card, catalogue, toasts, popups, ending
scripts/ui_theme.gd      shared UI look, emoji font, particle texture
scripts/shop_row.gd      one catalogue row
scripts/fmt.gd           1.23K / 4.5M number formatting
scripts/monetization/    ad + IAP interface, stub provider, autoload facade
shaders/                 ice, mountain rock and snow, sky, water, shed wood
fonts/                   subset Noto Color Emoji (the placeholder art) + license
tests/smoke_test.gd      headless test: godot --headless -s res://tests/smoke_test.gd
tests/screenshots.gd     renders screenshots of key moments (see the top of the file)
tests/field_bench.gd     timing benchmark for the ice (build, re-mesh, melt rate)
tools/subset_emoji.sh    rebuild the emoji font if you add new emoji
```

## Tuning the pacing

Every number lives in `scripts/balance.gd`. The glacier holds about 4,900 m³ of
ice. Each layer has an hp per cubic metre, and melting a cubic metre pays out that
hp in meltwater (times the Steam Sell upgrade). To make the game longer, raise the
deeper `LAYERS` hp values (and the tool costs with them). The first playtests
will tell us how long a run really takes.

## Adding real ads and purchases later

The game only ever calls the `Monetization` autoload. That autoload forwards to one `MonetizationProvider`. Right now that provider is `StubMonetizationProvider`, which shows a fake 3-second "ad" and approves every purchase, so you can test the whole flow.

To go live:
1. Install the plugins. For ads, use the **Poing Studios Godot AdMob plugin**. For purchases, use the official **GodotGooglePlayBilling** plugin (Android) and an iOS StoreKit plugin later. If you want one purchase API across both stores, RevenueCat has a Godot community plugin too.
2. Create `scripts/monetization/admob_billing_provider.gd` that `extends MonetizationProvider`. Implement `initialize`, `show_rewarded`, `show_interstitial`, `purchase`, `restore_purchases` and `price_string`, and emit the matching signals.
3. Return your new provider from `_create_provider()` in `scripts/monetization/monetization.gd`.
4. Create the same IDs in the store consoles: products `remove_ads_2x` and `golden_hair_dryer` (both non-consumable), and the rewarded placement `boost_2x_heat`.

No game code changes beyond that.

## Placeholder art

Everything is built in code. The helpers, the shed and the tools are low-poly 3D
models made of simple shapes (`scripts/creatures.gd`, `scripts/shed.gd`,
`scripts/props.gd`); the mountains, lake and forest are generated
(`scripts/scenery.gd`). The finds and villagers are still emoji drawn as 3D
labels, from a bundled Noto Color Emoji subset (Apache 2.0 / OFL, see `fonts/`).
If you add a new emoji to the code, re-run `tools/subset_emoji.sh`, or it shows
as a box. Real models can replace the shapes one at a time (the shed, the houses,
the helpers).

A note for shader work: the Compatibility renderer lights colours as they are
(a custom shader's `ALBEDO = vec3(0.5)` looks the same as a StandardMaterial3D
with `albedo_color` 0.5), so don't convert colours to linear in shaders.
