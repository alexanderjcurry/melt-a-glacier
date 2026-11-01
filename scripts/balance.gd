class_name Balance
extends RefCounted
## All tunable game numbers for the first-person glacier game live here.

# --- Glacier grid ----------------------------------------------------------------
# The glacier is a grid of 1 m ice blocks. Cell (0,0,0)'s corner sits at GRID_ORIGIN.
const BLOCK := 1.0
const GRID_X := 34
const GRID_Z := 30
const GRID_Y := 8
const GRID_ORIGIN := Vector3(-17.0, 0.0, -25.0)
const WORLD_SEED := 20261101

# Ice layers by depth below the glacier's original surface (0 = surface).
# Deeper ice is older, harder (hp) and worth more meltwater (hp x sell bonus).
const LAYERS = [
	{"name": "Fresh Snow", "hp": 1.0, "color": Color(0.88, 0.94, 1.0)},
	{"name": "Crunchy Firn", "hp": 2.0, "color": Color(0.78, 0.89, 0.99)},
	{"name": "Slushy Ice", "hp": 4.0, "color": Color(0.66, 0.84, 0.98)},
	{"name": "Blue Ice", "hp": 8.0, "color": Color(0.5, 0.76, 0.96)},
	{"name": "Old Blue Ice", "hp": 16.0, "color": Color(0.38, 0.67, 0.93)},
	{"name": "Glacial Ice", "hp": 32.0, "color": Color(0.28, 0.57, 0.88)},
	{"name": "Ancient Ice", "hp": 64.0, "color": Color(0.2, 0.46, 0.8)},
	{"name": "The Last Chunk", "hp": 128.0, "color": Color(0.14, 0.34, 0.68)},
]

# --- Player -------------------------------------------------------------------------
const WALK_SPEED := 4.5         # m/s
const JUMP_VELOCITY := 6.6      # enough to hop up about 1.2 m
const LOOK_SENSITIVITY_TOUCH := 0.0031   # radians per pixel of finger drag
const LOOK_SENSITIVITY_MOUSE := 0.0025   # radians per pixel of mouse motion

# Jetpack: tap JUMP to hop, keep holding it to fly. Fuel refills on the ground.
const JET_ACCEL := 34.0          # m/s^2 of thrust (gravity pulls 18)
const JET_MAX_RISE := 5.5        # fastest climb, m/s
const JET_FUEL := 2.2            # seconds of thrust on a full tank (upgradable)
const JET_REFILL := 0.8          # tanks per second while standing on something
const JET_HOLD_DELAY := 0.16     # hold JUMP this long before the jetpack fires
const JET_CEILING := 24.0        # can't fly higher than this

# --- Tools (bought in order at the shed) ------------------------------------------------
# power: hp per second at the centre of the heat zone; radius / range in metres.
const TOOLS = [
	{"name": "Hair Dryer", "icon": "💨", "power": 2.0, "radius": 0.9, "range": 4.5, "cost": 0.0,
		"color": Color(0.95, 0.5, 0.7), "desc": "Borrowed from your aunt."},
	{"name": "Heat Lamp", "icon": "💡", "power": 6.0, "radius": 1.15, "range": 5.5, "cost": 100.0,
		"color": Color(1.0, 0.82, 0.3), "desc": "Keeps fries and glaciers warm."},
	{"name": "Blowtorch", "icon": "🔥", "power": 18.0, "radius": 1.4, "range": 6.5, "cost": 1200.0,
		"color": Color(0.35, 0.55, 0.95), "desc": "Crème brûlée, but it's a glacier."},
	{"name": "Flamethrower", "icon": "🐉", "power": 55.0, "radius": 1.8, "range": 9.0, "cost": 12000.0,
		"color": Color(0.9, 0.35, 0.15), "desc": "Probably needs a permit."},
	{"name": "Lava Hose", "icon": "🌋", "power": 160.0, "radius": 2.3, "range": 11.0, "cost": 90000.0,
		"color": Color(0.85, 0.2, 0.1), "desc": "Garden hose, but lava."},
	{"name": "Orbital Mirror", "icon": "🛰️", "power": 450.0, "radius": 3.2, "range": 45.0, "cost": 450000.0,
		"color": Color(0.85, 0.9, 1.0), "desc": "A magnifying glass in space."},
]

# Shed upgrades. Effect = 1 + per_level * level. Cost = base * growth^level.
const UPGRADES = [
	{"key": "heat", "name": "Heat Output", "icon": "🌡️", "base": 20.0, "growth": 1.55, "per_level": 0.25, "max": 30,
		"desc": "+25% melting power"},
	{"key": "nozzle", "name": "Wider Nozzle", "icon": "📏", "base": 60.0, "growth": 1.8, "per_level": 0.1, "max": 12,
		"desc": "+10% heat zone size"},
	{"key": "reach", "name": "Longer Reach", "icon": "🎯", "base": 40.0, "growth": 1.7, "per_level": 0.12, "max": 12,
		"desc": "+12% melting range"},
	{"key": "sell", "name": "Steam Sell", "icon": "💧", "base": 90.0, "growth": 1.75, "per_level": 0.15, "max": 25,
		"desc": "+15% meltwater per block"},
	{"key": "boots", "name": "Crampon Boots", "icon": "🥾", "base": 50.0, "growth": 2.2, "per_level": 0.1, "max": 8,
		"desc": "+10% walking speed"},
	{"key": "jet", "name": "Bigger Fuel Tank", "icon": "🚀", "base": 60.0, "growth": 2.1, "per_level": 0.35, "max": 8,
		"desc": "+35% jetpack flying time"},
]

# Helpers melt on their own. Penguins and the sauna crew waddle around on the
# ice; the volcano lobs lava bombs. power = hp per second each.
const HELPER_GROWTH := 1.2
const HELPERS = [
	{"key": "penguin", "name": "Penguin with Tiny Torch", "icon": "🐧", "power": 0.8, "base": 40.0,
		"desc": "Waddles around melting the surface."},
	{"key": "sauna", "name": "Sauna Crew", "icon": "🧖", "power": 6.0, "base": 900.0,
		"desc": "Very relaxed. Very hot."},
	{"key": "volcano", "name": "Adopted Volcano", "icon": "🌋", "power": 45.0, "base": 15000.0,
		"desc": "Lobs lava bombs at the ice. You named it Kevin."},
]
const MAX_VISIBLE_WALKERS := 18   # per helper type; more helpers just work harder

# Buried things, placed at a depth (layer). Each sells for a burst of meltwater.
const DISCOVERIES = [
	{"name": "Lost Mitten", "icon": "🧤", "layer": 1, "value": 25.0, "flavor": "Still damp. Somehow."},
	{"name": "Frozen Pizza", "icon": "🍕", "layer": 2, "value": 80.0, "flavor": "Best before 1987."},
	{"name": "Mixtape", "icon": "📼", "layer": 2, "value": 120.0, "flavor": "Side B is all whale songs."},
	{"name": "Lost Snowmobile", "icon": "🛷", "layer": 3, "value": 400.0, "flavor": "Keys still in it."},
	{"name": "Frozen Mammoth", "icon": "🦣", "layer": 4, "value": 1500.0, "flavor": "He looks annoyed."},
	{"name": "Viking Helmet", "icon": "🪖", "layer": 4, "value": 1800.0, "flavor": "No horns. Historians were right."},
	{"name": "1970s Caveman", "icon": "🕺", "layer": 5, "value": 6000.0, "flavor": "Thawed out mid-dance move."},
	{"name": "Prehistoric Fish", "icon": "🐟", "layer": 5, "value": 7000.0, "flavor": "Do not microwave."},
	{"name": "Yeti's Phone", "icon": "📱", "layer": 6, "value": 25000.0, "flavor": "4,812 unread messages."},
	{"name": "Message in a Bottle", "icon": "🍾", "layer": 6, "value": 30000.0, "flavor": "It says 'help, cold'."},
	{"name": "Dinosaur Egg", "icon": "🥚", "layer": 7, "value": 90000.0, "flavor": "It's warm now. Uh oh."},
]

# --- Offline, boosts, ads ------------------------------------------------------------
# Kept modest on purpose: melting it yourself is the fun part, and the glacier
# has an ending, so time away shouldn't finish it for you.
const OFFLINE_EFFICIENCY := 0.25       # helpers work at quarter speed while you're away
const OFFLINE_CAP_SECONDS := 4.0 * 3600.0
const OFFLINE_MIN_SECONDS := 60.0
const BOOST_DURATION := 300.0          # "watch an ad for 2x heat for 5 min"
const BOOST_MULT := 2.0
const PERMANENT_MULT := 2.0            # from the "Remove ads + permanent 2x" IAP
const INTERSTITIAL_COOLDOWN := 240.0
const INTERSTITIAL_MIN_PROGRESS := 0.15  # no interstitials before 15% of the ice is gone


static func layer_hp(layer: int) -> float:
	return float(LAYERS[clampi(layer, 0, LAYERS.size() - 1)].hp)
