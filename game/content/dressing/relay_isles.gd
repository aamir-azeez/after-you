extends RefCounted
## The Relay Isles as a garden crossing. A meadow shore
## with a bench and a hedge, a plank landing stage in the middle where the seed
## rests, and a cottage garden at the far end. Every prop stands on a bank
## outside the floors, clear of the plates, the sockets and the throw line.

const DATA := {
	"theme": "garden",
	"ground": {"west": "grass", "relay": "timber", "east": "grass"},
	"pad": "stand_spot",
	"props": {"*": [
		# West shore: a planted bank along the back, a hedge down the left,
		# flowers along the front.
		{"slot": "bank", "rect": [-720, -300, -260, -220], "surface": "west", "height": 12},
		{"slot": "bank", "rect": [-800, -220, -720, 270], "surface": "west", "height": 12},
		{"slot": "bank", "rect": [-720, 240, -270, 290], "surface": "west", "height": 6},
		{"slot": "tree", "at": [-665, -282], "surface": "west", "y": 12, "size": 0.95},
		{"slot": "bench", "at": [-560, -266], "surface": "west", "y": 12},
		{"slot": "lamp", "at": [-470, -262], "surface": "west", "y": 12},
		{"slot": "tree", "at": [-330, -280], "surface": "west", "y": 12, "size": 0.9, "variant": 2},
		{"slot": "fence", "from": [-762, -190], "to": [-762, 240], "surface": "west", "y": 12},
		{"slot": "trim", "from": [-680, 266], "to": [-310, 266], "count": 4, "surface": "west", "y": 6, "size": 0.6, "vary": true},
		{"slot": "scatter", "from": [-660, -204], "to": [-420, -204], "count": 4, "surface": "west", "vary": true},
		# The relay: a plank landing stage with a lamp and a little clutter
		# behind it, flowers in front.
		{"slot": "bank", "rect": [-140, -250, 220, -180], "surface": "relay", "height": 12},
		{"slot": "bank", "rect": [-140, 200, 220, 250], "surface": "relay", "height": 6},
		{"slot": "lamp", "at": [-100, -215], "surface": "relay", "y": 12},
		{"slot": "clutter", "at": [40, -218], "surface": "relay", "y": 12},
		{"slot": "shrub", "at": [178, -218], "surface": "relay", "y": 12, "size": 0.7},
		{"slot": "trim", "from": [-110, 226], "to": [190, 226], "count": 3, "surface": "relay", "y": 6, "size": 0.6, "vary": true},
		# East: the cottage garden the seed is planted in.
		{"slot": "bank", "rect": [340, -340, 780, -220], "surface": "east", "height": 12},
		{"slot": "bank", "rect": [800, -220, 840, 290], "surface": "east", "height": 6},
		{"slot": "bank", "rect": [350, 240, 800, 290], "surface": "east", "height": 6},
		{"slot": "landmark", "at": [650, -292], "surface": "east", "y": 12, "width": 140, "depth": 90, "size": 0.8},
		{"slot": "tree", "at": [395, -278], "surface": "east", "y": 12, "size": 0.9, "variant": 1},
		{"slot": "lamp", "at": [510, -262], "surface": "east", "y": 12},
		{"slot": "trim", "from": [820, -180], "to": [820, 200], "count": 4, "surface": "east", "y": 6, "size": 0.6, "vary": true},
		{"slot": "trim", "from": [390, 266], "to": [750, 266], "count": 4, "surface": "east", "y": 6, "size": 0.6, "vary": true},
	]},
}
