# A Game About Melting A Glacier (prototype)

A first-person, landscape incremental game made in **Godot 4.7**. You walk around
a valley that's buried under a glacier, aim a hair dryer at the ice and slowly
dig into it. Meltwater is money: spend it at the shed on hotter tools,
upgrades and helpers (penguins with tiny torches, a sauna crew, an adopted
volcano called Kevin). Frozen junk melts out as you dig, and at the very bottom
there's a whole village. Free the village and the gate in the fence opens: the
whole lake beyond it froze solid, and it's a far bigger, harder glacier (its ice
sells for twice as much). You keep your tools and upgrades; your helpers retire
to the village and you hire a new crew at the same prices. When the last of the
lake ice is gone summer comes back. A run takes roughly 35 to 70 minutes.

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

1. Download **Godot 4.7.2 (Standard, not .NET)** from https://godotengine.org/download/windows/ and unzip it. There's no installer.
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
4. In Godot, run **Project > Install Android Build Template** once (the ads and store plugins need the Gradle build).
5. Plug the phone in. An Android icon appears at the top right of Godot. Click it to install and run the game on the phone.

Store builds (Android App Bundle, and the iPhone build on Codemagic) are made by CI: see [docs/LAUNCH.md](docs/LAUNCH.md).

## What's in the prototype

| Feature | Where |
|---|---|
| Two glaciers, melted in order. The village glacier (about 7,300 m³, a 0.5 m grid) and then the frozen lake (about 62,000 m³, a 1 m grid). Each is smooth, diggable ice stored as a density field and re-meshed in 8x8 chunks as you melt it (surface nets). 10 layers by depth each, from Fresh Snow to The Last Chunk in the village and from Lake Snow to The Lake's Heart (turquoise, jade, black, violet) in the lake: deeper ice is harder and worth more. Crevasses, snow cover, carved ice and a wet glow where the heat lands are drawn by `shaders/ice.gdshader` | `scripts/ice_field.gd`, `Balance.LAYER_SETS` |
| The level: each glacier's shape, its crevasses and the valley around them are one dictionary, so more levels (or more glaciers in one level) are more dictionaries | `scripts/levels.gd` |
| A fence across the valley keeps you off the lake. Its gate is locked until the village is free, then swings open. Your helpers retire and party in the village, and you hire a new crew for the lake at the same prices. Tools and upgrades carry over | `World._build_fence()`, `GameState.check_win()` |
| First-person walking (CharacterBody3D on the ice's collision mesh), step-up, a jetpack (hold JUMP, fuel refills on landing) and a respawn button | `scripts/player.gd` |
| The valley: generated mountains with rock and snow, a cloudy sky, the lake and a meltwater stream, pine forest, boulders | `scripts/scenery.gd`, `shaders/` |
| The heat tool: aim with the crosshair, hold to melt a ball of ice. Each tool has its own 3D effect: rings of hot air in a warm haze, a cone of lamp light with dust glinting in it, a blue torch flame and jet, billowing fire with embers, a molten lava stream that drips and splashes, and a column of sunlight from space with shockwaves. Where it lands the ice steams, sparks or flurries. Upgrades show in it: Wider Nozzle makes it wider where it lands, Longer Reach makes it go further, Heat Output makes it brighter and denser | `Player._update_tool()`, `scripts/tool_fx.gd`, `shaders/tool_cone.gdshader`, `shaders/spark.gdshader` |
| The shed is a walk-in store: tools hang on the pegboard, upgrades sit on the workbench, helpers wait in the hiring corner, finds go on the shelf by the door, and the catalogue on the table has the boost and purchases. Look at anything for a paper price card, then buy it where it stands | `scripts/shed.gd`, `Hud.set_shop_info()` |
| 6 tools bought in order at the shed: Hair Dryer, Heat Lamp, Blowtorch, Flamethrower, Lava Hose, Orbital Mirror (the same models you hold) | `Balance.TOOLS`, `scripts/props.gd` |
| 5 upgrades: Heat Output, Wider Nozzle, Longer Reach, Steam Sell, Crampon Boots | `Balance.UPGRADES` |
| Helpers (3D models built in code): penguins with tiny torches and the sauna crew walk on the ice melting it, Kevin the volcano lobs lava bombs and watches you. There's one Kevin: you adopt him, then level him up (to 15) for bigger bombs, more often | `scripts/helpers.gd`, `scripts/creatures.gd`, `Balance.HELPERS` |
| 18 buried finds frozen at fixed depths: 11 in the village glacier (mitten, snowmobile, mammoth, 1970s caveman, dinosaur egg...) and 7 in the lake (ice skater, pirate treasure, a whale, a lake monster, a UFO, the sun's lost ray). They melt out, sell for a burst of water, and stay in the world | `World._place_finds()`, `Balance.DISCOVERIES` |
| A village frozen inside the glacier. The church spire pokes out of the top as a hint | `World._build_village()` |
| The valley greens up and flowers bloom where the ice is gone; villagers come out at the end | `World._update_slow()` |
| Loose ice melts by itself: bits left floating, and small chunks on the ground (under about 4 m³), shrink away over a few seconds, corners first, and still pay out | `IceField._melt_floating()` |
| No "while you were away" earnings: it's a game you play in a sitting, so nothing melts while it's closed | |
| The catalogue: a button at the top right of the HUD (C or Tab on a computer), or the book in the shed. Free bonuses for a rewarded ad: 2x heat for 5 min (stacks to 15), helpers work 3x for 3 min, and double your water (capped at about 4 minutes of your recent income). IAP: Remove Ads + permanent 2x, Golden Hair Dryer, Restore | `Hud.open_catalogue()`, `Balance.AD_REWARDS`, `GameState.grant_ad_reward()` |
| Timed ad offers: now and then a paper tag swings down under the catalogue button ("FREE BONUS: Double your water, +💧 70K, enough for the Flamethrower!"). Tap it (or press B) to watch. Kept gentle on purpose: none in the first 2.5 minutes, one at a time, gone after 40 s, the next one waits longer each time you let one pass (200 s up to 8 min), only offers that are worth having right now, and never one whose ad hasn't loaded. After you choose a rewarded ad, no interstitial for a while | `scripts/ad_offers.gd`, `Balance.OFFER_*`, `Hud._update_offer()` |
| Light interstitials: only when leaving the shed, after 15% of the ice is gone, at most every 4 min, never with Remove Ads | `Monetization.maybe_show_interstitial()` |
| A popup when the village is free, an ending with a stats screen when the lake is, then walk around or open "Where to next?": the valley to melt again, and the maps still to come (Frozen Harbor, Arctic Research Base, Ice Cave City, Mammoth Graveyard, Frozen Volcano, The Polar Cap) stamped COMING SOON. It's in the catalogue too once you've won | `Hud.show_stage_done()`, `Hud.show_ending()`, `scripts/level_menu.gd`, `Levels.MAPS` |
| Short onboarding hints the first time | `World._update_coach()` |
| Sound and music, all made by script for this game (no stock audio). Each tool has its own spray sound that rises in pitch with Heat Output and gets bigger with Wider Nozzle and Longer Reach; the ice hisses, cracks (lower and louder the deeper you go, and the lake's thick ice "sings") and drips; loose chunks crack off; finds break free with a jingle that gets grander with rarity; footsteps crunch on snow, thud on earth and knock on the shed's boards; a bell over the shed door; penguins squawk, the sauna crew splash their stones, Kevin's bombs boom, whistle and hiss; the gate creaks open; wind, then birdsong as the valley greens. Five cozy tunes (two for the valley, two for the lake, one for summer) take turns with quiet stretches between. Music and effects volume and Mute are in the catalogue (M on a computer). The game goes quiet during ads and when the browser tab is hidden | `scripts/audio/sound.gd`, `audio/`, `art/audio/` |
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
scripts/tool_fx.gd       what comes out of each tool (flames, beams, sparks, steam), sized by your upgrades
scripts/creatures.gd     3D models of the helpers (penguin, sauna crew, Kevin)
scripts/mesh_kit.gd      tiny modelling kit (ellipsoids, cylinders, boxes) for the models
scripts/touch_controls.gd  phone controls (multi-touch stick, look, melt, jump)
scripts/helpers.gd       penguins, sauna crew, Kevin the volcano
scripts/hud.gd           HUD, shed price card, catalogue, toasts, popups, ending
scripts/level_menu.gd    "Where to next?": every map after the ending, the unbuilt ones stamped COMING SOON
scripts/ui_theme.gd      shared UI look, emoji font, particle texture
scripts/shop_row.gd      one catalogue row
scripts/ad_offers.gd     when the HUD's timed ad-offer tag shows up, and which reward it offers
scripts/fmt.gd           1.23K / 4.5M number formatting
scripts/audio/sound.gd   autoload "Sound": every sound effect, the music and the ambience, plus the volume settings
audio/                   the sounds (sfx/), wind and birds (amb/) and the music (music/), built by art/audio/
default_bus_layout.tres  audio buses: Music, Ambience, SFX
scripts/monetization/    ad + IAP interface, stub provider, autoload facade
shaders/                 ice, mountain rock and snow, sky, water, shed wood, the tools' flames and sparks
fonts/                   subset Noto Color Emoji (the placeholder art) + license
tests/smoke_test.gd      headless test: godot --headless -s res://tests/smoke_test.gd
tests/screenshots.gd     renders screenshots of key moments (see the top of the file)
tests/field_bench.gd     timing benchmark for the ice (build, re-mesh, melt rate)
tests/pacing.gd          a bot plays a whole run and prints how long each part took
tools/subset_emoji.sh    rebuild the emoji font if you add new emoji
```

## Tuning the pacing

Every number lives in `scripts/balance.gd`. Each ice layer has an hp per cubic
metre, and melting a cubic metre pays out that hp in meltwater (times the Steam
Sell upgrade). Helpers' power is in the same units: a penguin with power 0.5
melts about 0.5 hp of ice per second.

`tests/pacing.gd` plays a whole run in about five minutes of real time and
prints when it bought each tool and finished each glacier:

```
godot --headless --fixed-fps 20 -s res://tests/pacing.gd             # a keen player
godot --headless --fixed-fps 20 -s res://tests/pacing.gd -- casual   # a slower one
```

Aim for the village in about 15 to 20 minutes and the lake in about 20 to 30
for a keen player. A casual player takes longer, and real first runs land in
between. Each tool costs roughly what the glacier pays out while you use the
tool before it, so to slow a part down, raise the next tool's cost or the hp of
the layers it has to get through.

## Ads, purchases and publishing

Real ads (AdMob, with the EU consent form and the iPhone tracking prompt) and real purchases (RevenueCat) are wired in. On a phone the game uses them; in the editor and the web playtest it uses the stub with pretend ads and free purchases. Every id lives in `scripts/monetization/store_config.gd`.

How to publish, step by step, including what only the account owner can do: **[docs/LAUNCH.md](docs/LAUNCH.md)**.

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
