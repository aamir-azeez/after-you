extends RefCounted
## The Falls' water (presentation/kit/water_bodies.gd): the stream steps down
## the strip from east to west: the still pool at the top, the stream wheel's
## reach at the last stones, the still gorge under the falls, and the mill
## pool the pool wheel raises and lowers. Where two reaches meet, the locks kit lets the higher fall into the
## lower (the dressing picks the "falls" spillway). Every level stays under the
## floors beside it. Visual only. Plan positions in cm, heights in metres.

const DATA := {
	"seabed": -1.20,
	"rate": 0.9,
	"wall_top": 0.86,
	# 4 cm, so no water face ends on a sea wall's water mark where two reaches meet.
	"inset": 4,
	# One body per tier of the climb, each with its own pebbled bed ("bed",
	# metres) about 0.6 to 0.7 m under its lowest level, so the water steps down
	# the gorge through a pour at every tier's lip and a high pool is not water
	# down to the mill pool's floor. The window is the water's own outline, so
	# no wall closes it off from the camera.
	"bounds": [-1300, -800, 14790, 800],
	"bodies": [
		{"id": "pool", "node": "MillPool", "selector": "pool", "rest": "HIGH",
			"rects": [[-1300, -800, 2820, 800]], "bed": -1.20,
			"levels": {"LOW": -0.36, "HIGH": -0.06}, "color": Color(0.27, 0.47, 0.50, 0.84)},
		{"id": "race", "node": "MillRace", "selector": "", "rest": "still",
			"rects": [[2820, -800, 5970, 800]], "bed": 0.85,
			"levels": {"still": 1.45}, "color": Color(0.27, 0.47, 0.50, 0.84)},
		{"id": "gorge", "node": "GorgeWater", "selector": "", "rest": "still",
			"rects": [[5970, -800, 10080, 800]], "bed": 4.25,
			"levels": {"still": 4.85}, "color": Color(0.25, 0.45, 0.49, 0.86)},
		{"id": "stream", "node": "UpperStream", "selector": "stream", "rest": "HIGH",
			"rects": [[10080, -800, 12550, 800]], "bed": 7.10,
			"levels": {"LOW": 7.75, "MID": 8.25, "HIGH": 8.65}, "color": Color(0.28, 0.50, 0.52, 0.84)},
		{"id": "top", "node": "TopPool", "selector": "", "rest": "still",
			"rects": [[12550, -800, 14790, 800]], "bed": 8.35,
			"levels": {"still": 9.00}, "color": Color(0.30, 0.52, 0.55, 0.84)},
	],
	"marks": {"LOW": Color("4d5b40"), "HIGH": Color("5f6a4c")},
	# The floors stand on the gorge's rock: plain rock faces, no block courses.
	"stone": Color("7f8371"),
	"courses": 0,
	"coping": Color("c9c6b0"),
	"pit_floor": Color("6f6f60"),
	"plinth": Color("8a8a78"),
	"fender": Color("6b4f37"),
	"piers": [],
}
