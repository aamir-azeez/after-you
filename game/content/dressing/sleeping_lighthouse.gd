extends RefCounted
## The Sleeping Lighthouse at golden hour: warm harbour stone with mossy lips,
## lit lanterns, fireflies, moored boats at the harbour, and a real striped
## lighthouse behind the tower island whose lamp wakes with the beacon. Props
## given no height stand on the top of the bank under them.

const NORTH := [
	{"kind": "bank", "rect": [-260, -590, 160, -500], "surface": "north", "height": 12, "top": "8fa56c"},
	{"kind": "pine", "at": [-190, -555], "surface": "north", "size": 0.85},
	{"kind": "lantern", "at": [-60, -540], "surface": "north"},
	{"kind": "pine", "at": [90, -548], "surface": "north", "size": 0.75},
]
const SOUTH := [
	{"kind": "bank", "rect": [-320, 240, -250, 500], "surface": "south", "height": 12, "top": "8fa56c"},
	{"kind": "bank", "rect": [-250, 500, -40, 530], "surface": "south", "height": 6, "top": "8fa56c"},
	{"kind": "bench", "at": [-288, 380], "surface": "south", "rot": 90},
	{"kind": "row", "of": {"kind": "flowers", "size": 0.45}, "from": [-215, 520], "to": [-75, 520], "count": 2, "surface": "south", "y": 6},
]
const TOWER := [
	{"kind": "bank", "rect": [440, -340, 860, -180], "surface": "tower", "height": 12, "top": "8fa56c"},
	{"kind": "bank", "rect": [850, -180, 930, 180], "surface": "tower", "height": 12, "top": "8fa56c"},
	{"kind": "tower", "at": [760, -275], "surface": "tower", "size": 0.85},
	{"kind": "lantern", "at": [520, -222], "surface": "tower"},
	{"kind": "rock", "at": [620, -225], "surface": "tower"},
	{"kind": "crate", "at": [905, 40], "surface": "tower", "stack": true},
]

const COURT_BACK := [
	{"kind": "bank", "rect": [-260, -200, -112, -130], "surface": "court", "height": 10, "top": "8fa56c"},
	{"kind": "bank", "rect": [12, -200, 160, -130], "surface": "court", "height": 10, "top": "8fa56c"},
	{"kind": "bush", "at": [-205, -172], "surface": "court", "size": 0.8},
	{"kind": "lantern", "at": [-142, -168], "surface": "court"},
	{"kind": "pot", "at": [50, -166], "surface": "court"},
	{"kind": "bush", "at": [115, -172], "surface": "court", "size": 0.75},
]

const DATA := {
	"look": "golden",
	"ground": {"*": "harbour"},
	"bridges": "timber",
	"fireflies": 12,
	# Mossy banks, and the court's front lip grown along its edge
	# (content/dressing/placement.gd).
	"picks": {"bank": "moss"},
	"edging": {"front": [{"slot": "bank", "depth": 28, "height": 6}, {"slot": "trim", "spacing": 65, "size": 0.45}]},
	"edged": {"court": ["front"]},
	"props": {
		"*": [
			# The harbour: a quay bank behind, boats and jetty posts to the west.
			{"kind": "bank", "rect": [-860, -270, -615, -180], "surface": "harbour", "height": 12, "top": "8fa56c"},
			{"kind": "bank", "rect": [-505, -270, -440, -180], "surface": "harbour", "height": 12, "top": "8fa56c"},
			{"kind": "lantern", "at": [-800, -228], "surface": "harbour"},
			{"kind": "crate", "at": [-720, -232], "surface": "harbour", "stack": true},
			{"kind": "pot", "at": [-655, -226], "surface": "harbour"},
			{"kind": "lamp_post", "at": [-478, -228], "surface": "harbour", "size": 0.8},
			{"kind": "rug", "at": [-950, 0], "y": -24, "width": 150, "depth": 420, "color": "3f6a77"},
			{"kind": "boat", "at": [-935, 70], "rot": 90, "y": -18},
			{"kind": "boat", "at": [-935, -90], "rot": 80, "y": -18, "size": 0.8},
			{"kind": "post", "at": [-878, -150], "y": -40, "height": 70},
			{"kind": "post", "at": [-878, 150], "y": -40, "height": 70},
			# A working quay: bollards along the harbour's front lip, lobster
			# pots and a crate on a quay edge by the boats, on its top.
			{"slot": "bank", "floor": "harbour", "edge": "front", "span": [0.0, 0.975], "depth": 46, "height": 6},
			{"slot": "trim", "style": "bollards", "floor": "harbour", "edge": "front", "span": [0.0, 0.975], "spacing": 78, "size": 0.55},
			{"slot": "bank", "floor": "harbour", "edge": "left", "span": [0.083, 0.917], "gap": 28, "depth": 28, "height": 12},
			{"kind": "lobster_pot", "floor": "harbour", "edge": "left", "along": 0.306, "size": 0.55, "rot": 70},
			{"kind": "lobster_pot", "floor": "harbour", "edge": "left", "along": 0.528, "size": 0.5, "rot": 105},
			{"kind": "crate", "floor": "harbour", "edge": "left", "along": 0.764, "size": 0.6, "rot": 12},
			# The court: a flower lip in front, cut around the south crossing on
			# the stages that have it.
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
