class_name Levels
extends RefCounted
## Level descriptions: the shape of each glacier and what's frozen inside it.
## There's one valley for now. A new level is a new dictionary like VALLEY.

const VALLEY := {
	"name": "The Valley",
	"seed": 20261101,
	# The box the ice can fill (world metres). Points on its edges are always air.
	"field_min": Vector3(-18.0, 0.0, -30.0),
	"field_max": Vector3(18.0, 9.5, 5.0),
	"glacier": {
		"height": 8.3,              # thickness in the middle, behind full_z
		"half_width_back": 15.6,
		"half_width_snout": 12.5,
		"back_z": -28.5,            # its back end (the valley floor goes on behind it)
		"full_z": -12.0,            # full thickness behind this line
		"snout_z": 4.6,             # the toe of the glacier
		"bumps": 0.55,              # metres of lumpiness
	},
	# The valley around the glacier: a flat floor where you can walk, mountains
	# everywhere else (see Scenery). Distances in metres.
	"valley": {
		"half_width": 22.5,       # the side walls start just past where you can walk (x = ±21)
		"back_z": -37.5,          # the back wall: the glacier ends at -29.5, so you can walk round it
		"front_z": 64.0,          # the valley floor ends here (the lake reaches further)
		"flare_z": 21.0,          # past here the valley opens out toward the lake
		"flare": 1.0,             # metres wider per metre further out
		"lake": [0.0, 66.0, 70.0, 38.0],   # middle x, middle z, radius across, radius along
		"peaks": 1.0,             # mountain height scale
		"snow_line": 17.0,
		# Meltwater runs from under the snout down to the lake.
		"stream": [Vector2(-2.5, 2.0), Vector2(-4.0, 8.0), Vector2(-8.0, 13.5), Vector2(-10.0, 19.0),
				Vector2(-11.5, 25.0), Vector2(-13.5, 33.0)],
	},
	# Cracks across the glacier: z of the middle, how far the middle bows
	# downstream, depth, half-width at the top, and how far across they run.
	"crevasses": [
		{"z": -25.5, "bow": 1.2, "depth": 3.2, "width": 0.55, "x0": -11.0, "x1": 9.0},
		{"z": -7.5, "bow": 1.6, "depth": 2.6, "width": 0.5, "x0": -13.0, "x1": -2.5},
		{"z": -6.0, "bow": 1.2, "depth": 2.4, "width": 0.5, "x0": 4.5, "x1": 13.0},
		{"z": -1.8, "bow": 1.0, "depth": 1.8, "width": 0.45, "x0": -9.5, "x1": 7.5},
	],
}


static func current() -> Dictionary:
	return VALLEY
