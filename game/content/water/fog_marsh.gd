extends RefCounted
## Fog Marsh's water (presentation/kit/water_bodies.gd): one still, shallow
## marsh under every boardwalk, just below the low floors. No wheel moves it
## (the current wheel only steers what floats). Visual only. Plan positions in
## cm, heights in metres.

const DATA := {
	"seabed": -0.60,
	"rate": 0.9,
	"wall_top": 0.0,
	"inset": 3,
	"bounds": [-1300, -760, 12200, 760],
	"bodies": [
		{"id": "marsh", "node": "MarshWater", "selector": "", "rest": "still",
			"rects": [[-1300, -760, 12200, 760]],
			"levels": {"still": -0.10}, "color": Color(0.33, 0.47, 0.44, 0.86)},
	],
	"marks": {"still": Color("5b6248")},
	"stone": Color("7d6a50"),
	"coping": Color("b9b39a"),
	"pit_floor": Color("6a6656"),
	"plinth": Color("7d7864"),
	"fender": Color("5f4a36"),
	"piers": [],
}
