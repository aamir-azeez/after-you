extends RefCounted
## First Steps: a cottage garden on a spring morning. A meadow shore with a
## stone path to a timber rope lift (its hand winch stands beside the power
## spot) and a plank loft with a little cottage behind it. Every prop stands
## on a bank outside the floors, clear of every spot and walking line.

const DATA := {
	"theme": "garden",
	"ground": {"shore": "grass", "loft": "timber"},
	"pad": "stand_spot",
	"lift": "rope_tower",
	"props": {"*": [
		# Shore: a planted bank along the back with a bench and a lamp, a hedge
		# down the left, low flowers along the front.
		{"slot": "bank", "rect": [-660, -320, -130, -240], "surface": "shore", "height": 12},
		{"slot": "bank", "rect": [-700, -240, -620, 272], "surface": "shore", "height": 12},
		{"slot": "bank", "rect": [-620, 240, -140, 290], "surface": "shore", "height": 6},
		{"slot": "tree", "at": [-600, -298], "surface": "shore", "y": 12, "size": 0.9},
		{"slot": "bench", "at": [-520, -286], "surface": "shore", "y": 12},
		{"slot": "lamp", "at": [-440, -282], "surface": "shore", "y": 12},
		{"slot": "shrub", "at": [-215, -292], "surface": "shore", "y": 12, "size": 0.85},
		{"slot": "fence", "from": [-660, -190], "to": [-660, 230], "surface": "shore", "y": 12},
		{"slot": "trim", "from": [-590, 266], "to": [-180, 266], "count": 5, "surface": "shore", "y": 6, "size": 0.6, "vary": true},
		{"slot": "scatter", "from": [-580, -220], "to": [-380, -220], "count": 4, "surface": "shore", "vary": true},
		# A stone path up to the lift's open side.
		{"slot": "path", "at": [-152, 0], "surface": "shore", "width": 56, "depth": 64},
		# Loft: a cottage and a lamp on a bank behind it, a railing along the
		# rest of its back, low flowers along the front, a shrub at its far side.
		{"slot": "bank", "rect": [300, -380, 520, -240], "surface": "loft", "height": 12},
		{"slot": "landmark", "at": [420, -312], "surface": "loft", "y": 12, "width": 120, "depth": 80, "size": 0.75},
		{"slot": "railing", "from": [90, -264], "to": [290, -264], "surface": "loft"},
		{"slot": "bank", "rect": [90, 240, 500, 290], "surface": "loft", "height": 6},
		{"slot": "lamp", "at": [310, -272], "surface": "loft", "y": 12},
		{"slot": "trim", "from": [120, 266], "to": [470, 266], "count": 4, "surface": "loft", "y": 6, "size": 0.6, "vary": true},
		{"slot": "bank", "rect": [500, -240, 540, 240], "surface": "loft", "height": 12},
		{"slot": "shrub", "at": [536, 60], "surface": "loft", "y": 12, "size": 0.5},
	]},
}
