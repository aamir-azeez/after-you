extends RefCounted
## The Falls' ending (services/ending_scene.gd has the format): one pip wobbles
## on the last stone, the other takes their hand and steadies them; the first
## gets across, the helper's foot slips, and down they go into the pool at the
## foot of the falls. The helper bobs up wet and laughing, then both watch the
## pipsport float off downstream into the fog. The helper is the pipsport's
## carrier. It plays at the falls past the far bank (the dressing's
## "falls_pool" anchor, the falls' foot): the world stands the falls, the pool
## and the bank; the scene adds only the last stone, the splash and the fog,
## and the real pipsport in place of the world's.

const DATA := {
	"cast": {"holds": "pipsport", "fallback": "p0"},
	"origin": "falls_pool",
	"props": {
		"stone": {"shape": "cylinder", "size": [0.32, 0.4], "color": "a3906f", "at": [-2.2, 0.04, 0.8]},
		"splash": {"shape": "sphere", "size": [0.5, 1.0], "color": "ffffff", "at": [-1.2, 0.06, 1.1], "shown": false, "alpha": 0.0},
		"pipsport": {"shape": "item", "style": "pipsport", "at": [-2.9, 1.22, 0.6], "rot": [0, -15, 0]},
		"fog": {"shape": "box", "size": [3.2, 1.4, 0.3], "color": "eef2f2", "at": [-4.8, 0.76, 3.5], "alpha": 0.0},
	},
	"steps": [
		{"do": "prop", "id": "pipsport", "follow": "carrier"},
		{"do": "camera", "at": [-2.3, 0.56, 0.9], "size": 6.5, "time": 1.0},
		{"do": "move", "who": "other", "to": [-2.2, 0.24, 0.8], "time": 1.0},
		{"do": "move", "who": "carrier", "to": [-3.35, 0.16, 0.8], "time": 1.0},
		{"do": "wait", "time": 1.1},
		# The last stone: a wobble.
		{"do": "face", "who": "carrier", "toward": "other"},
		{"do": "face", "who": "other", "toward": "carrier"},
		{"do": "pose", "who": "other", "face": "nervous", "for": 2.2, "wobble": {"amp": 0.2, "rate": 1.6, "for": 2.0}},
		{"do": "wait", "time": 1.3},
		# A hand out, and they are steady.
		{"do": "move", "who": "carrier", "to": [-3.02, 0.16, 0.8], "time": 0.5},
		{"do": "pose", "who": "carrier", "face": "please", "for": 1.2},
		{"do": "wait", "time": 0.7},
		{"do": "pose", "who": "other", "face": "touched", "for": 1.0, "wobble": {"amp": 0.0, "rate": 1.0, "for": 0.0}},
		{"do": "wait", "time": 0.8},
		# Across, safe.
		{"do": "move", "who": "other", "to": [-3.7, 0.16, 1.0], "time": 0.7, "arc": 0.25, "carried": true},
		{"do": "pose", "who": "other", "hop": 0.7},
		{"do": "pose", "who": "carrier", "face": "happy", "for": 0.8},
		{"do": "wait", "time": 0.8},
		# The helper's foot slips on the wet stone.
		{"do": "pose", "who": "carrier", "face": "surprised", "for": 1.2, "bump": true},
		{"do": "move", "who": "carrier", "to": [-2.7, 0.21, 0.85], "time": 0.3, "carried": true},
		{"do": "wait", "time": 0.35},
		{"do": "move", "who": "carrier", "to": [-1.2, -0.14, 1.1], "time": 0.7, "arc": 0.6, "carried": true, "ease": "in"},
		{"do": "wait", "time": 0.7},
		# Splash.
		{"do": "sound", "cue": "ending_splash"},
		{"do": "prop", "id": "splash", "show": true, "alpha": 0.9},
		{"do": "prop", "id": "splash", "alpha": 0.0, "time": 0.8},
		{"do": "pose", "who": "other", "face": "gasp", "for": 1.4},
		{"do": "camera", "at": [-2.0, 0.36, 1.0], "size": 5.5, "time": 0.8},
		{"do": "wait", "time": 0.6},
		# Up again, wet and laughing, not hurt.
		{"do": "move", "who": "carrier", "to": [-1.3, 0.02, 1.1], "time": 0.5, "carried": true},
		{"do": "pose", "who": "carrier", "face": "giggle", "for": 3.0, "bob": {"amp": 0.04, "rate": 0.8, "for": 6.0}},
		{"do": "pose", "who": "other", "face": "giggle", "for": 1.6},
		{"do": "sound", "cue": "drip"},
		{"do": "wait", "time": 1.4},
		# The pipsport floats off downstream into the fog.
		{"do": "prop", "id": "pipsport", "follow": ""},
		{"do": "prop", "id": "pipsport", "to": [-4.3, 0.06, 2.9], "time": 3.6, "ease": "linear", "spin": 25.0},
		{"do": "prop", "id": "fog", "alpha": 0.85, "time": 2.0},
		{"do": "face", "who": "carrier", "toward": [-4.3, 0.16, 2.9]},
		{"do": "face", "who": "other", "toward": [-4.3, 0.16, 2.9]},
		{"do": "pose", "who": "carrier", "face": "gasp", "for": 2.6},
		{"do": "pose", "who": "other", "face": "huh", "for": 2.6},
		{"do": "camera", "at": [-3.2, 0.36, 1.9], "size": 6.0, "time": 2.0},
		{"do": "wait", "time": 2.2},
		{"do": "prop", "id": "pipsport", "alpha": 0.0, "time": 1.2},
		{"do": "wait", "time": 1.6},
	],
}
