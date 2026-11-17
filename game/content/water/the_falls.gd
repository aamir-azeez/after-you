extends RefCounted
## The Falls' water (presentation/kit/water_bodies.gd): the stream steps down
## the strip from east to west: the still pool at the top, the stream wheel's
## reach at the last stones, the still gorge under the falls, and the mill
## pool the pool wheel raises and lowers. Where two reaches meet, the locks kit lets the higher fall into the
## lower (the dressing picks the "falls" spillway). Every level stays under the
## floors beside it. Visual only. Plan positions in cm, heights in metres.

const DATA := {
	"seabed": -0.70,
	"rate": 0.9,
	"wall_top": 0.86,
	"inset": 3,
	"bounds": [-700, -700, 5700, 700],
	"bodies": [
		# The mill pool and mill race, round the first two stages: LOW shows
		# the stepping stones' tops, HIGH sits just under the low floors.
		{"id": "pool", "node": "MillPool", "selector": "pool", "rest": "HIGH",
			"rects": [[-500, -520, 2050, 520]],
			"levels": {"LOW": -0.36, "HIGH": -0.06}, "color": Color(0.27, 0.47, 0.50, 0.84)},
		# The gorge under the falls, between the ledges.
		{"id": "gorge", "node": "GorgeWater", "selector": "", "rest": "still",
			"rects": [[2050, -520, 3550, 520]],
			"levels": {"still": 0.22}, "color": Color(0.25, 0.45, 0.49, 0.86)},
		# The upper stream at the last stones, set by the stream wheel.
		{"id": "stream", "node": "UpperStream", "selector": "stream", "rest": "HIGH",
			"rects": [[3550, -520, 4650, 520]],
			"levels": {"LOW": 0.30, "MID": 0.50, "HIGH": 0.72}, "color": Color(0.28, 0.50, 0.52, 0.84)},
		# The pool at the top, under the last falls past the far bank, still and
		# always above the stream, so it falls into it at the far gate.
		{"id": "top", "node": "TopPool", "selector": "", "rest": "still",
			"rects": [[4650, -520, 5500, 520]],
			"levels": {"still": 0.80}, "color": Color(0.30, 0.52, 0.55, 0.84)},
	],
	"marks": {"LOW": Color("4d5b40"), "HIGH": Color("5f6a4c")},
	"stone": Color("9a9a88"),
	"coping": Color("c9c6b0"),
	"pit_floor": Color("6f6f60"),
	"plinth": Color("8a8a78"),
	"fender": Color("6b4f37"),
	"piers": [],
}
