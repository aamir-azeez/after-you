extends RefCounted
## First Steps: a cottage garden on a spring morning. A meadow shore with a
## stone path to a timber rope lift (its hand winch stands beside the power
## spot) and a plank loft with a little cottage behind it. The garden theme
## grows the banks, the hedge and the front flowers around both floors
## (content/dressing/placement.gd); only the special props are placed here.

const DATA := {
	"theme": "garden",
	"ground": {"shore": "grass", "loft": "timber"},
	"lift": "rope_tower",
	"edged": {"shore": ["back", "left", "front"], "loft": ["front", "right"]},
	"props": {"*": [
		# Shore: a bench, a lamp, a tree and a shrub on the back bank, tufts
		# along the back of the grass.
		{"slot": "tree", "floor": "shore", "edge": "back", "along": 0.0, "size": 0.9},
		{"slot": "bench", "floor": "shore", "edge": "back", "along": 0.17},
		{"slot": "lamp", "floor": "shore", "edge": "back", "along": 0.33},
		{"slot": "shrub", "floor": "shore", "edge": "back", "along": 0.8, "size": 0.85},
		{"slot": "scatter", "floor": "shore", "edge": "back", "out": -20, "span": [0.0, 0.5], "spacing": 60, "vary": true},
		# A stone path up to the lift's open side.
		{"slot": "path", "at": [-152, 0], "surface": "shore", "width": 56, "depth": 64},
		# Loft: a cottage and a lamp on a deep bank behind its far half, a
		# railing along the rest of its back, a shrub at its far side.
		{"slot": "bank", "floor": "loft", "edge": "back", "span": [0.52, 1.0], "depth": 140, "height": 12},
		{"slot": "landmark", "floor": "loft", "edge": "back", "along": 0.81, "width": 120, "depth": 80, "size": 0.75},
		{"slot": "lamp", "floor": "loft", "edge": "back", "along": 0.55, "out": 32},
		{"slot": "railing", "floor": "loft", "edge": "back", "span": [0.0, 0.5], "out": 24, "inset": 10},
		{"slot": "shrub", "floor": "loft", "edge": "right", "along": 0.62, "size": 0.5},
	]},
}
