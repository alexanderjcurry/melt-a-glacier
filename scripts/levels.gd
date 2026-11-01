class_name Levels
extends RefCounted
## Level descriptions: the shape of each glacier and what's frozen inside it.
## There's one valley for now. A new level is a new dictionary like VALLEY.
##
## A level has one or more glaciers, melted in order: when one is gone, the
## next one opens up (the valley's village glacier, then the frozen lake).
## Each glacier is its own block of ice (IceField) with its own grid, shape
## and ice layers (Balance.LAYER_SETS). Its finds are Balance.DISCOVERIES
## entries with that glacier's index.

const VALLEY := {
	"name": "The Valley",
	"seed": 20261101,
	"glaciers": [
		{
			"name": "the village glacier",
			"title": "Village glacier",
			"kind": "tongue",           # a tongue of ice down the valley (IceField._height)
			# The box the ice can fill (world metres). Points on its edges are always air.
			"field_min": Vector3(-19.5, 0.0, -30.0),
			"field_max": Vector3(19.5, 13.5, 5.0),
			"res": 0.5,                 # metres between grid points
			"height": 12.0,             # thickness in the middle, behind full_z
			"half_width_back": 16.6,
			"half_width_snout": 13.4,
			"back_z": -28.5,            # its back end (the valley floor goes on behind it)
			"full_z": -14.0,            # full thickness behind this line
			"snout_z": 4.6,             # the toe of the glacier
			"bumps": 0.6,               # metres of lumpiness
			"layers": "valley",         # Balance.LAYER_SETS
			"layer_depth": 1.2,         # metres of ice per layer, from the top down
			"finds_box": [Vector2(-14.0, -26.0), Vector2(14.0, 1.0)],   # where finds may be frozen (x, z)
			# Cracks across the glacier: z of the middle, how far the middle bows
			# downstream, depth, half-width at the top, and how far across they run.
			"crevasses": [
				{"z": -25.5, "bow": 1.2, "depth": 3.2, "width": 0.55, "x0": -11.0, "x1": 9.0},
				{"z": -7.5, "bow": 1.6, "depth": 2.6, "width": 0.5, "x0": -13.0, "x1": -2.5},
				{"z": -6.0, "bow": 1.2, "depth": 2.4, "width": 0.5, "x0": 4.5, "x1": 13.0},
				{"z": -1.8, "bow": 1.0, "depth": 1.8, "width": 0.45, "x0": -9.5, "x1": 7.5},
			],
		},
		{
			# The lake froze solid and disappeared under an ice cap. You can see
			# it from the start, but the gate stays locked until the village is free.
			"name": "the frozen lake",
			"title": "Frozen lake",
			"kind": "dome",             # a round ice cap (IceField._dome_height)
			"field_min": Vector3(-66.0, 0.0, 29.0),
			"field_max": Vector3(66.0, 18.0, 103.0),
			"res": 1.0,                 # it's huge: a coarser grid keeps it quick
			"center": Vector2(0.0, 66.0),
			"radius": Vector2(61.0, 33.0),
			"height": 14.0,
			"edge": 0.5,                # how steep the edge is (smaller = steeper cliffs)
			"wobble": 0.08,             # how far the edge wanders from a perfect oval
			"hills": 2.2,               # big rolls on top
			"bumps": 0.7,
			"layers": "lake",
			"layer_depth": 1.4,
			"worth": 2.0,               # its ice sells for twice as much per hp (see IceField.worth)
			"finds_box": [Vector2(-50.0, 40.0), Vector2(50.0, 92.0)],
			"crevasses": [
				{"z": 52.0, "bow": 3.0, "depth": 4.0, "width": 1.2, "x0": -34.0, "x1": -6.0},
				{"z": 60.0, "bow": -2.5, "depth": 3.5, "width": 1.1, "x0": 10.0, "x1": 38.0},
				{"z": 80.0, "bow": 2.0, "depth": 3.0, "width": 1.0, "x0": -18.0, "x1": 16.0},
			],
			# A goblin pirate fleet froze in with the lake (PirateFleet). Each ship's
			# hull is hollowed out of the ice; its masts poke out of the top. "yaw"
			# turns the bow (which points to -Z) round; keep it to quarter turns so
			# the hollow fits the hull. "bounty" is what the crew pays you for
			# thawing them out.
			"ships": [
				{"name": "The Rusty Gob", "mesh": "Galleon", "pos": Vector3(4.0, 0.0, 50.0), "yaw": 0.0,
					"bounty": 600000.0},
				{"name": "The Soggy Sock", "mesh": "Sloop", "pos": Vector3(-25.0, 0.0, 61.0), "yaw": 0.0,
					"bounty": 150000.0},
				{"name": "The Wet Biscuit", "mesh": "Sloop", "pos": Vector3(27.0, 0.0, 73.0), "yaw": PI,
					"bounty": 300000.0},
			],
		},
	],
	# The valley around the glaciers: a flat floor where you can walk, mountains
	# everywhere else (see Scenery). Distances in metres.
	"valley": {
		"half_width": 24.5,       # the side walls start just past where you can walk (x = ±23)
		"back_z": -37.5,          # the back wall: the glacier ends at -29.5, so you can walk round it
		"front_z": 64.0,          # the valley floor ends here (the lake reaches further)
		"flare_z": 21.0,          # past here the valley opens out toward the lake
		"flare": 1.0,             # metres wider per metre further out
		"lake": [0.0, 66.0, 70.0, 38.0],   # middle x, middle z, radius across, radius along
		"peaks": 1.0,             # mountain height scale
		"snow_line": 17.0,
		# The fence across the valley that keeps you off the lake until the village is free.
		"gate_z": 21.0,
		# Meltwater runs from under the snout down to the lake.
		"stream": [Vector2(-2.5, 2.0), Vector2(-4.0, 8.0), Vector2(-8.0, 13.5), Vector2(-10.0, 19.0),
				Vector2(-11.5, 25.0), Vector2(-13.5, 33.0)],
	},
}


static func current() -> Dictionary:
	return VALLEY
