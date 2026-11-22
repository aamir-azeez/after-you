extends RefCounted
## The Relay Isles as a garden crossing. A meadow shore
## with a bench and a hedge, a plank landing stage in the middle where the seed
## rests, and a cottage garden at the far end. The garden theme grows the
## banks, the hedge and the front flowers around the floors, clear of the
## plates, the sockets and both crossings (content/dressing/placement.gd); only
## the special props are placed here.

const DATA := {
	"theme": "garden",
	"ground": {"west": "grass", "relay": "timber", "east": "grass"},
	"edged": {"west": ["back", "left", "front"], "relay": ["back", "front"], "east": ["front", "right"]},
	"props": {"*": [
		# West shore: a bench, a lamp and two trees on the back bank, tufts
		# along the back of the grass.
		{"slot": "tree", "floor": "west", "edge": "back", "along": 0.12, "size": 0.95},
		{"slot": "bench", "floor": "west", "edge": "back", "along": 0.35},
		{"slot": "lamp", "floor": "west", "edge": "back", "along": 0.54},
		{"slot": "tree", "floor": "west", "edge": "back", "along": 0.85, "size": 0.9, "variant": 2},
		{"slot": "scatter", "floor": "west", "edge": "back", "out": -16, "span": [0.13, 0.65], "spacing": 60, "vary": true},
		# The relay: a plank landing stage with a lamp and a little clutter
		# behind it.
		{"slot": "lamp", "floor": "relay", "edge": "back", "along": 0.11},
		{"slot": "clutter", "floor": "relay", "edge": "back", "along": 0.5},
		{"slot": "shrub", "floor": "relay", "edge": "back", "along": 0.88, "size": 0.7},
		# East: the cottage garden the seed is planted in, on a deep back bank.
		{"slot": "bank", "floor": "east", "edge": "back", "depth": 120, "height": 12},
		{"slot": "landmark", "floor": "east", "edge": "back", "along": 0.7, "width": 140, "depth": 90, "size": 0.8},
		{"slot": "tree", "floor": "east", "edge": "back", "along": 0.125, "size": 0.9, "variant": 1},
		{"slot": "lamp", "floor": "east", "edge": "back", "along": 0.386},
	]},
}
