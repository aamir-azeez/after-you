extends RefCounted
## The Sleeping Lighthouse at golden hour: warm harbour stone with mossy lips,
## lit lanterns, fireflies, moored boats at the harbour, and a real striped
## lighthouse behind the tower island whose lamp wakes with the beacon.

const NORTH := [
	{"kind": "bank", "rect": [-260, -590, 160, -500], "surface": "north", "height": 12, "top": "8fa56c"},
	{"kind": "pine", "at": [-190, -555], "surface": "north", "y": 12, "size": 0.85},
	{"kind": "lantern", "at": [-60, -540], "surface": "north", "y": 12},
	{"kind": "pine", "at": [90, -548], "surface": "north", "y": 12, "size": 0.75},
]
const SOUTH := [
	{"kind": "bank", "rect": [-320, 240, -250, 500], "surface": "south", "height": 12, "top": "8fa56c"},
	{"kind": "bank", "rect": [-250, 500, -40, 530], "surface": "south", "height": 6, "top": "8fa56c"},
	{"kind": "bench", "at": [-288, 380], "surface": "south", "y": 12, "rot": 90},
	{"kind": "row", "of": {"kind": "flowers", "size": 0.45}, "from": [-215, 520], "to": [-75, 520], "count": 2, "surface": "south", "y": 6},
]
const TOWER := [
	{"kind": "bank", "rect": [440, -340, 860, -180], "surface": "tower", "height": 12, "top": "8fa56c"},
	{"kind": "bank", "rect": [850, -180, 930, 180], "surface": "tower", "height": 12, "top": "8fa56c"},
	{"kind": "tower", "at": [760, -275], "surface": "tower", "y": 12, "size": 0.85},
	{"kind": "lantern", "at": [520, -222], "surface": "tower", "y": 12},
	{"kind": "rock", "at": [620, -225], "surface": "tower", "y": 12},
	{"kind": "crate", "at": [905, 40], "surface": "tower", "y": 12, "stack": true},
]

const COURT_BACK := [
	{"kind": "bank", "rect": [-260, -200, -112, -130], "surface": "court", "height": 10, "top": "8fa56c"},
	{"kind": "bank", "rect": [12, -200, 160, -130], "surface": "court", "height": 10, "top": "8fa56c"},
	{"kind": "bush", "at": [-205, -172], "surface": "court", "y": 10, "size": 0.8},
	{"kind": "lantern", "at": [-142, -168], "surface": "court", "y": 10},
	{"kind": "pot", "at": [50, -166], "surface": "court", "y": 10},
	{"kind": "bush", "at": [115, -172], "surface": "court", "y": 10, "size": 0.75},
]

const DATA := {
	"look": "golden",
	"ground": {"*": "harbour"},
	"bridges": "timber",
	"fireflies": 12,
	"props": {
		"*": [
			# The harbour: a quay bank behind, boats and jetty posts to the west.
			{"kind": "bank", "rect": [-860, -270, -615, -180], "surface": "harbour", "height": 12, "top": "8fa56c"},
			{"kind": "bank", "rect": [-505, -270, -440, -180], "surface": "harbour", "height": 12, "top": "8fa56c"},
			{"kind": "lantern", "at": [-800, -228], "surface": "harbour", "y": 12},
			{"kind": "crate", "at": [-720, -232], "surface": "harbour", "y": 12, "stack": true},
			{"kind": "pot", "at": [-655, -226], "surface": "harbour", "y": 12},
			{"kind": "lantern", "at": [-478, -228], "surface": "harbour", "y": 12},
			{"kind": "rug", "at": [-950, 0], "y": -24, "width": 150, "depth": 420, "color": "3f6a77"},
			{"kind": "boat", "at": [-935, 70], "rot": 90, "y": -18},
			{"kind": "boat", "at": [-935, -90], "rot": 80, "y": -18, "size": 0.8},
			{"kind": "post", "at": [-878, -150], "y": -40, "height": 70},
			{"kind": "post", "at": [-878, 150], "y": -40, "height": 70},
			# The court: flowers in front, clear of both bridges.
			{"kind": "bank", "rect": [-250, 130, -112, 158], "surface": "court", "height": 6, "top": "8fa56c"},
			{"kind": "bank", "rect": [12, 130, 150, 158], "surface": "court", "height": 6, "top": "8fa56c"},
			{"kind": "row", "of": {"kind": "flowers", "size": 0.45}, "from": [-225, 145], "to": [-140, 145], "count": 2, "surface": "court", "y": 6},
			{"kind": "row", "of": {"kind": "flowers", "size": 0.45}, "from": [40, 145], "to": [125, 145], "count": 2, "surface": "court", "y": 6},
		],
		# Until the north island appears, the court has planting along its back.
		"borrowed-light": COURT_BACK,
		"missing-piece": NORTH,
		"two-promises": NORTH + SOUTH,
		"what-carried-you": NORTH + SOUTH + TOWER,
		"after-the-first-bell": NORTH + SOUTH + TOWER,
		"a-welcome-left-on": NORTH + SOUTH + TOWER,
	},
}
