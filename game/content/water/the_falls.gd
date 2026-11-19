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
	# 4 cm, so no water face ends on a sea wall's water mark where two reaches meet.
	"inset": 4,
	# PROTOTYPE (train/falls-rethink-proto): one body per tier of the climb,
	# on the stretched map (core/journey/proto_spread.gd: x times 2, z times
	# 1.4, heights 2.5 times plus each tier's base), so the water steps down
	# the gorge through a pour at every tier's lip. The window is the water's
	# own outline, so no wall closes it off from the camera.
	"bounds": [-1300, -760, 14600, 760],
	"bodies": [
		{"id": "pool", "node": "MillPool", "selector": "pool", "rest": "HIGH",
			"rects": [[-1300, -760, 2175, 760]],
			"levels": {"LOW": -0.36, "HIGH": -0.06}, "color": Color(0.27, 0.47, 0.50, 0.84)},
		{"id": "race", "node": "MillRace", "selector": "", "rest": "still",
			"rects": [[2175, -760, 5190, 760]],
			"levels": {"still": 1.85}, "color": Color(0.27, 0.47, 0.50, 0.84)},
		{"id": "gorge", "node": "GorgeWater", "selector": "", "rest": "still",
			"rects": [[5190, -760, 9230, 760]],
			"levels": {"still": 5.05}, "color": Color(0.25, 0.45, 0.49, 0.86)},
		{"id": "stream", "node": "UpperStream", "selector": "stream", "rest": "HIGH",
			"rects": [[9230, -760, 12076, 760]],
			"levels": {"LOW": 7.75, "MID": 8.25, "HIGH": 8.80}, "color": Color(0.28, 0.50, 0.52, 0.84)},
		{"id": "top", "node": "TopPool", "selector": "", "rest": "still",
			"rects": [[12076, -760, 14600, 760]],
			"levels": {"still": 9.00}, "color": Color(0.30, 0.52, 0.55, 0.84)},
	],
	"marks": {"LOW": Color("4d5b40"), "HIGH": Color("5f6a4c")},
	"stone": Color("9a9a88"),
	"coping": Color("c9c6b0"),
	"pit_floor": Color("6f6f60"),
	"plinth": Color("8a8a78"),
	"fender": Color("6b4f37"),
	"piers": [],
}
