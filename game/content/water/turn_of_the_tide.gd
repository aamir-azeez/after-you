extends RefCounted
## Turn of the Tide's water (presentation/kit/water_bodies.gd): the harbour
## channels follow the tide wheel, an outer sea past the mole follows the basin
## wheel, and a sea chamber between them follows the chamber wheel. Visual
## only: nothing here reaches a simulation, a recording or a checkpoint.
## Low sits below the beaches, half between beach and terrace, high between
## terrace and quay; the outer sea rests a little below the beaches while its
## gate is shut. Plan positions in cm, heights in metres.

const DATA := {
	"seabed": -0.70,
	# Water moves this many metres a second: one tide step in about half a second.
	"rate": 1.1,
	# Water never stands higher than high; walls that hold it back stand to here.
	"wall_top": 0.77,
	# Water stops this many cm short of what holds it on the sides the camera sees.
	"inset": 3,
	# Sea walls and lock pieces stand only inside this window.
	"bounds": [-1116, -700, 1884, 700],
	"bodies": [
		{"id": "harbour", "node": "HarbourWater", "selector": "tide", "rest": "low",
			"rects": [[-512, -480, 1728, 480]],
			"levels": {"low": -0.22, "half": 0.24, "high": 0.70}, "color": Color(0.25, 0.42, 0.47, 0.84)},
		# Wide past the mole, through the harbour mouth, and a short reach past
		# each end of the mouth where the sea gates stand.
		{"id": "sea", "node": "OuterSea", "selector": "basin", "rest": "shut",
			"rects": [[-2400, -640, -960, 640], [-960, -480, -704, 480], [-704, -560, -512, 560]],
			"levels": {"shut": -0.06, "low": -0.22, "half": 0.24, "high": 0.70}, "color": Color(0.21, 0.37, 0.44, 0.88)},
		{"id": "chamber", "node": "ChamberWater", "selector": "chamber", "rest": "half", "basin": true,
			"rects": [[-640, -128, -576, 128]],
			"levels": {"low": -0.22, "half": 0.24, "high": 0.70}, "color": Color(0.28, 0.46, 0.50, 0.84)},
	],
	# Weed and wet bands on every wall at the first body's levels.
	"marks": {"low": Color("4d5b40"), "half": Color("655e4c"), "high": Color("7a6f5d")},
	# One masonry for every wall that holds water back, so walls that meet at a
	# corner read as one wall; its coping; a sealed pit's floor; a stair's plinth.
	"stone": Color("b8a283"),
	"coping": Color("dccaa4"),
	"pit_floor": Color("7d6d58"),
	"plinth": Color("a3705a"),
	# Floors above every water get a timber fender instead of a parapet.
	"fender": Color("6b4f37"),
	# The aqueduct stands on piers: water runs under it, so it gets no walls.
	"piers": ["aq-feeder", "aq-span"],
}
