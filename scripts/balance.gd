class_name Balance
extends RefCounted
## All tunable game numbers live here. Pacing was tuned with a greedy-player
## simulation: an optimal player who holds ~50% of the time finishes in ~1 h,
## a lazier one in ~1.7 h, so real players should land around 2-4 h.

# --- Glacier -----------------------------------------------------------------
# Ice (tons) per layer, top to bottom. The last layer hides the village.
const LAYER_HP = [500.0, 3.0e3, 1.8e4, 1.08e5, 6.48e5, 3.89e6, 2.33e7, 1.17e8, 5.25e8, 2.1e9, 6.3e9, 1.57e10]

const LAYERS = [
	{"name": "Fresh Snow", "color": Color(0.97, 0.98, 1.0)},
	{"name": "Crunchy Firn", "color": Color(0.9, 0.95, 1.0)},
	{"name": "Slushy Ice", "color": Color(0.82, 0.92, 0.99)},
	{"name": "Blue Ice", "color": Color(0.7, 0.87, 0.98)},
	{"name": "Old Blue Ice", "color": Color(0.6, 0.81, 0.96)},
	{"name": "Glacial Ice", "color": Color(0.5, 0.74, 0.94)},
	{"name": "Disco-Era Ice", "color": Color(0.45, 0.67, 0.92)},
	{"name": "Ice Age Ice", "color": Color(0.38, 0.6, 0.88)},
	{"name": "Ancient Ice", "color": Color(0.32, 0.52, 0.84)},
	{"name": "Primordial Ice", "color": Color(0.27, 0.44, 0.78)},
	{"name": "Bedrock Ice", "color": Color(0.22, 0.37, 0.7)},
	{"name": "The Last Chunk", "color": Color(0.18, 0.3, 0.62)},
]

# One buried thing per layer. It melts out when its layer is half gone and
# sells for a one-off burst of meltwater (value_mult x that layer's ice).
const DISCOVERIES = [
	{"name": "Lost Mitten", "icon": "🧤", "value_mult": 0.6, "flavor": "Still damp. Somehow."},
	{"name": "Frozen Pizza", "icon": "🍕", "value_mult": 0.6, "flavor": "Best before 1987."},
	{"name": "Mixtape", "icon": "📼", "value_mult": 0.6, "flavor": "Side B is all whale songs."},
	{"name": "Lost Snowmobile", "icon": "🛷", "value_mult": 0.7, "flavor": "Keys still in it."},
	{"name": "Frozen Mammoth", "icon": "🦣", "value_mult": 0.8, "flavor": "He looks annoyed."},
	{"name": "Viking Helmet", "icon": "🪖", "value_mult": 0.8, "flavor": "No horns. Historians were right."},
	{"name": "1970s Caveman", "icon": "🕺", "value_mult": 0.9, "flavor": "Thawed out mid-dance move."},
	{"name": "Prehistoric Fish", "icon": "🐟", "value_mult": 0.9, "flavor": "Do not microwave."},
	{"name": "Yeti's Phone", "icon": "📱", "value_mult": 1.0, "flavor": "4,812 unread messages."},
	{"name": "Message in a Bottle", "icon": "🍾", "value_mult": 1.0, "flavor": "It says 'help, cold'."},
	{"name": "Dinosaur Egg", "icon": "🥚", "value_mult": 1.2, "flavor": "It's warm now. Uh oh."},
	{"name": "The Village", "icon": "🏘️", "value_mult": 0.0, "flavor": "Summer is back!"},
]

# --- Tapping -------------------------------------------------------------------
const HOLD_TAPS_PER_SEC := 5.0  # holding a finger down = this many taps per second

# Tools are bought in order. unlock_layer = layer the player must reach first.
const TOOLS = [
	{"name": "Hair Dryer", "icon": "💨", "heat": 1.0, "cost": 0.0, "unlock_layer": 0, "desc": "Borrowed from your aunt."},
	{"name": "Heat Lamp", "icon": "💡", "heat": 8.0, "cost": 200.0, "unlock_layer": 1, "desc": "Keeps fries and glaciers warm."},
	{"name": "Blowtorch", "icon": "🔥", "heat": 60.0, "cost": 8.0e3, "unlock_layer": 3, "desc": "Creme brulee, but it's a glacier."},
	{"name": "Flamethrower", "icon": "🐉", "heat": 500.0, "cost": 4.0e5, "unlock_layer": 5, "desc": "Probably needs a permit."},
	{"name": "Lava Hose", "icon": "🌋", "heat": 5000.0, "cost": 2.5e7, "unlock_layer": 7, "desc": "Garden hose, but lava."},
	{"name": "Orbital Mirror", "icon": "🛰️", "heat": 60000.0, "cost": 2.0e9, "unlock_layer": 9, "desc": "A giant magnifying glass. In space."},
]

# Stats: per-level bonus is additive (1 + per_level * level). Cost = base * growth^level.
const STATS = [
	{"key": "heat", "name": "Heat Output", "icon": "🌡️", "base": 15.0, "growth": 1.45, "per_level": 0.25, "desc": "+25% tap heat per level"},
	{"key": "size", "name": "Tool Size", "icon": "📏", "base": 80.0, "growth": 1.55, "per_level": 0.15, "desc": "+15% tap heat and a bigger heat zone"},
	{"key": "auto", "name": "Auto-Melt Rate", "icon": "⚙️", "base": 500.0, "growth": 1.6, "per_level": 0.25, "desc": "+25% helper output per level"},
	{"key": "sell", "name": "Steam Sell Multiplier", "icon": "💧", "base": 300.0, "growth": 1.7, "per_level": 0.1, "desc": "+10% meltwater per ton melted"},
]

# Helpers melt automatically (tons/sec each). Cost = base * HELPER_GROWTH^owned.
const HELPER_GROWTH := 1.17
const HELPERS = [
	{"name": "Penguin with Tiny Torch", "icon": "🐧", "rate": 0.4, "base": 25.0, "desc": "Small torch. Big heart."},
	{"name": "Sauna Crew", "icon": "🧖", "rate": 4.0, "base": 800.0, "desc": "Very relaxed. Very hot."},
	{"name": "Adopted Volcano", "icon": "🌋", "rate": 45.0, "base": 4.0e4, "desc": "You named it Kevin."},
	{"name": "Hot Spring Resort", "icon": "♨️", "rate": 600.0, "base": 2.5e6, "desc": "Five stars on TripAdvisor."},
	{"name": "Sun-Lens Satellite", "icon": "☀️", "rate": 9000.0, "base": 2.0e8, "desc": "Points the sun where you want it."},
]

# --- Offline, boosts, ads -----------------------------------------------------------
const OFFLINE_EFFICIENCY := 0.5        # helpers work at half speed while you're away
const OFFLINE_CAP_SECONDS := 8.0 * 3600.0
const OFFLINE_MIN_SECONDS := 60.0
const BOOST_DURATION := 300.0          # "watch an ad for 2x heat for 5 min"
const BOOST_MULT := 2.0
const PERMANENT_MULT := 2.0            # from the "Remove ads + permanent 2x" IAP
const INTERSTITIAL_COOLDOWN := 240.0   # never more than one every 4 minutes
const INTERSTITIAL_MIN_LAYER := 3      # no interstitials during the first layers


static func layer_count() -> int:
	return LAYER_HP.size()


static func total_ice() -> float:
	var t := 0.0
	for hp in LAYER_HP:
		t += hp
	return t
