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
	"bounds": [-700, -700, 5100, 700],
	"bodies": [
		{"id": "marsh", "node": "MarshWater", "selector": "", "rest": "still",
			"rects": [[-500, -520, 4900, 520]],
			"levels": {"still": -0.10}, "color": Color(0.33, 0.47, 0.44, 0.86)},
	],
	"marks": {"still": Color("5b6248")},
	"stone": Color("8f8a74"),
	"coping": Color("b9b39a"),
	"pit_floor": Color("6a6656"),
	"plinth": Color("7d7864"),
	"fender": Color("5f4a36"),
	"piers": [],
}
