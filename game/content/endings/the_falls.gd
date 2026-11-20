extends RefCounted
## The Falls' ending (services/ending_scene.gd has the format): one pip wobbles
## on the last stone, the other takes their hand and steadies them; the first
## gets across, the helper's foot slips, and down they go into the pool at the
## foot of the falls. The helper bobs up wet and laughing, then both watch the
## pipsport float off downstream into the fog. The helper is the pipsport's
## carrier. It plays at the falls past the far bank (the dressing's
## "falls_pool" anchor, the falls' foot): the world stands the falls, the pool
## and the bank; the scene adds only the last stone, the splash and the fog
## banks the pipsport floats into, out on the pool clear of the far bank,
## and the real pipsport in place of the world's.
## Shot like a short film: letterbox bars slide in, the camera pushes in on the
## last stone, the slip has a little lurch first and a white splash flash, then
## the camera drifts round after the pipsport as the screen cools into the fog;
## the bars and the wash leave together as the camera glides back to the
## game's own view, so the world comes back without a jump.

const DATA := {
	"cast": {"holds": "pipsport", "fallback": "p0"},
	"origin": "falls_pool",
	"props": {
		"stone": {"shape": "cylinder", "size": [0.32, 0.4], "color": "a3906f", "at": [-3.5, 0.04, 1.8]},
		"splash": {"shape": "sphere", "size": [0.5, 1.0], "color": "ffffff", "at": [-2.5, 0.06, 2.1], "shown": false, "alpha": 0.0},
		"pipsport": {"shape": "item", "style": "pipsport", "at": [-4.2, 1.22, 1.6], "rot": [0, -15, 0]},
		# Soft banks of fog downstream, out on the pool past the far bank.
		"fog": {"shape": "sphere", "size": [1.0, 0.5], "color": "eef2f2", "at": [-2.3, 0.35, 6.7], "alpha": 0.0},
		"fog2": {"shape": "sphere", "size": [0.8, 0.4], "color": "eef2f2", "at": [-0.8, 0.32, 6.3], "alpha": 0.0},
		"fog3": {"shape": "sphere", "size": [1.2, 0.6], "color": "eef2f2", "at": [-1.5, 0.4, 7.4], "alpha": 0.0},
	},
	"steps": [
		{"do": "prop", "id": "pipsport", "follow": "carrier"},
		{"do": "bars", "show": true, "time": 0.7},
		{"do": "camera", "at": [-3.6, 0.56, 1.9], "size": 6.0, "time": 1.6, "orbit": -10},
		{"do": "move", "who": "other", "to": [-3.5, 0.24, 1.8], "time": 1.0},
		{"do": "move", "who": "carrier", "to": [-4.65, 0.16, 1.8], "time": 1.0},
		{"do": "wait", "time": 1.1},
		# The last stone: a wobble.
		{"do": "face", "who": "carrier", "toward": "other"},
		{"do": "face", "who": "other", "toward": "carrier"},
		{"do": "pose", "who": "other", "face": "nervous", "for": 2.2, "wobble": {"amp": 0.2, "rate": 1.6, "for": 2.0}},
		{"do": "camera", "at": [-3.9, 0.46, 1.85], "size": 4.8, "time": 1.3},
		{"do": "wait", "time": 1.3},
		# A hand out, and they are steady.
		{"do": "move", "who": "carrier", "to": [-4.32, 0.16, 1.8], "time": 0.5, "ease": "back"},
		{"do": "pose", "who": "carrier", "face": "please", "for": 1.2},
		{"do": "wait", "time": 0.7},
		{"do": "pose", "who": "other", "face": "touched", "for": 1.0, "wobble": {"amp": 0.0, "rate": 1.0, "for": 0.0}},
		{"do": "wait", "time": 0.8},
		# Across, safe.
		{"do": "move", "who": "other", "to": [-5, 0.16, 2], "time": 0.7, "arc": 0.25, "carried": true, "ease": "back"},
		{"do": "pose", "who": "other", "hop": 0.7},
		{"do": "pose", "who": "carrier", "face": "happy", "for": 0.8},
		{"do": "wait", "time": 0.8},
		# The helper's foot slips on the wet stone.
		{"do": "pose", "who": "carrier", "face": "surprised", "for": 1.2, "bump": true},
		# A lurch the other way first, then the slip.
		{"do": "move", "who": "carrier", "to": [-4.42, 0.18, 1.8], "time": 0.18, "ease": "out", "carried": true},
		{"do": "wait", "time": 0.18},
		{"do": "move", "who": "carrier", "to": [-4, 0.21, 1.85], "time": 0.3, "carried": true},
		{"do": "wait", "time": 0.35},
		{"do": "camera", "at": [-3.3, 0.36, 2], "size": 5.2, "time": 0.7, "ease": "out"},
		{"do": "move", "who": "carrier", "to": [-2.5, -0.14, 2.1], "time": 0.7, "arc": 0.6, "carried": true, "ease": "in"},
		{"do": "wait", "time": 0.7},
		# Splash.
		{"do": "sound", "cue": "ending_splash"},
		{"do": "tint", "color": "ffffff", "alpha": 0.35, "time": 0.06},
		{"do": "prop", "id": "splash", "show": true, "alpha": 0.9},
		{"do": "prop", "id": "splash", "alpha": 0.0, "time": 0.8},
		{"do": "pose", "who": "other", "face": "gasp", "for": 1.4},
		{"do": "wait", "time": 0.08},
		{"do": "tint", "color": "ffffff", "alpha": 0.0, "time": 0.5, "ease": "out"},
		{"do": "wait", "time": 0.52},
		# Up again, wet and laughing, not hurt.
		{"do": "move", "who": "carrier", "to": [-2.6, 0.02, 2.1], "time": 0.5, "carried": true, "ease": "back"},
		{"do": "pose", "who": "carrier", "face": "giggle", "for": 3.0, "bob": {"amp": 0.04, "rate": 0.8, "for": 6.0}},
		{"do": "pose", "who": "other", "face": "giggle", "for": 1.6},
		{"do": "sound", "cue": "drip"},
		{"do": "wait", "time": 1.4},
		# The pipsport floats off downstream into the fog.
		{"do": "prop", "id": "pipsport", "follow": ""},
		{"do": "prop", "id": "pipsport", "to": [-1.7, 0.06, 6], "time": 3.6, "ease": "linear", "spin": 25.0},
		{"do": "prop", "id": "fog", "alpha": 0.6, "time": 2.0},
		{"do": "prop", "id": "fog2", "alpha": 0.5, "time": 2.0},
		{"do": "prop", "id": "fog3", "alpha": 0.6, "time": 2.0},
		{"do": "face", "who": "carrier", "toward": [-1.7, 0.16, 6]},
		{"do": "face", "who": "other", "toward": [-1.7, 0.16, 6]},
		{"do": "pose", "who": "carrier", "face": "gasp", "for": 2.6},
		{"do": "pose", "who": "other", "face": "huh", "for": 2.6},
		{"do": "camera", "at": [-2.9, 0.36, 4], "size": 6.0, "time": 3.0, "orbit": 22},
		{"do": "tint", "color": "dfe9ea", "alpha": 0.3, "time": 2.4},
		{"do": "wait", "time": 2.2},
		{"do": "prop", "id": "pipsport", "alpha": 0.0, "time": 1.2},
		{"do": "wait", "time": 0.8},
		# The bars and the wash leave together as the camera glides home.
		{"do": "bars", "show": false, "time": 0.8},
		{"do": "camera", "home": true, "time": 0.8},
		{"do": "tint", "color": "dfe9ea", "alpha": 0.0, "time": 0.8},
		{"do": "wait", "time": 0.8},
	],
}
