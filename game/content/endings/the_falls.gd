extends RefCounted
## The Falls' ending (services/ending_scene.gd has the format): one pip wobbles
## on the last stone, the other takes their hand and steadies them; the first
## gets across, the helper's foot slips, and down they go into the pool at the
## foot of the falls. The helper bobs up wet and laughing, then both watch the
## pipsport float off downstream into the fog. The helper is the pipsport's
## carrier. The falls, pool, stone, bank and fog are placeholders until the
## chapter's world is built; then they come out and the points follow its own.

const DATA := {
	"cast": {"holds": "pipsport", "fallback": "p0"},
	"origin": "pips",
	"props": {
		"falls": {"shape": "box", "size": [1.0, 2.6, 0.25], "color": "bfe3ee", "at": [-2.9, 1.25, -0.6], "alpha": 0.85},
		"foam": {"shape": "sphere", "size": [0.45, 0.9], "color": "ffffff", "at": [-2.6, 0.02, -0.25]},
		"pool": {"shape": "cylinder", "size": [1.3, 0.06], "color": "7fb8c9", "at": [-1.9, -0.05, 0.4]},
		"stone": {"shape": "cylinder", "size": [0.32, 0.16], "color": "a3906f", "at": [-0.7, 0.0, 0.2]},
		"bank": {"shape": "box", "size": [1.6, 0.3, 1.4], "color": "b5c98a", "at": [0.9, -0.15, 0.2]},
		"splash": {"shape": "sphere", "size": [0.5, 1.0], "color": "ffffff", "at": [-1.7, -0.1, 0.5], "shown": false, "alpha": 0.0},
		"pipsport": {"shape": "box", "size": [0.22, 0.04, 0.3], "color": "3d4f7a", "at": [0.0, 1.06, 0.0], "rot": [0, 15, 0]},
		"fog": {"shape": "box", "size": [3.2, 1.4, 0.3], "color": "eef2f2", "at": [1.9, 0.6, 2.9], "alpha": 0.0},
	},
	"steps": [
		{"do": "prop", "id": "pipsport", "follow": "carrier"},
		{"do": "camera", "at": [-0.6, 0.4, 0.3], "size": 6.5, "time": 1.0},
		{"do": "move", "who": "other", "to": [-0.7, 0.08, 0.2], "time": 1.0},
		{"do": "move", "who": "carrier", "to": [0.45, 0.0, 0.2], "time": 1.0},
		{"do": "wait", "time": 1.1},
		# The last stone: a wobble.
		{"do": "face", "who": "carrier", "toward": "other"},
		{"do": "face", "who": "other", "toward": "carrier"},
		{"do": "pose", "who": "other", "face": "nervous", "for": 2.2, "wobble": {"amp": 0.2, "rate": 1.6, "for": 2.0}},
		{"do": "wait", "time": 1.3},
		# A hand out, and they are steady.
		{"do": "move", "who": "carrier", "to": [0.12, 0.0, 0.2], "time": 0.5},
		{"do": "pose", "who": "carrier", "face": "please", "for": 1.2},
		{"do": "wait", "time": 0.7},
		{"do": "pose", "who": "other", "face": "touched", "for": 1.0, "wobble": {"amp": 0.0, "rate": 1.0, "for": 0.0}},
		{"do": "wait", "time": 0.8},
		# Across, safe.
		{"do": "move", "who": "other", "to": [0.8, 0.0, 0.4], "time": 0.7, "arc": 0.25, "carried": true},
		{"do": "pose", "who": "other", "hop": 0.7},
		{"do": "pose", "who": "carrier", "face": "happy", "for": 0.8},
		{"do": "wait", "time": 0.8},
		# The helper's foot slips on the wet stone.
		{"do": "pose", "who": "carrier", "face": "surprised", "for": 1.2, "bump": true},
		{"do": "move", "who": "carrier", "to": [-0.2, 0.05, 0.25], "time": 0.3, "carried": true},
		{"do": "wait", "time": 0.35},
		{"do": "move", "who": "carrier", "to": [-1.7, -0.3, 0.5], "time": 0.7, "arc": 0.6, "carried": true, "ease": "in"},
		{"do": "wait", "time": 0.7},
		# Splash.
		{"do": "sound", "cue": "ending_splash"},
		{"do": "prop", "id": "splash", "show": true, "alpha": 0.9},
		{"do": "prop", "id": "splash", "alpha": 0.0, "time": 0.8},
		{"do": "pose", "who": "other", "face": "gasp", "for": 1.4},
		{"do": "camera", "at": [-0.9, 0.2, 0.4], "size": 5.5, "time": 0.8},
		{"do": "wait", "time": 0.6},
		# Up again, wet and laughing, not hurt.
		{"do": "move", "who": "carrier", "to": [-1.6, -0.14, 0.5], "time": 0.5, "carried": true},
		{"do": "pose", "who": "carrier", "face": "giggle", "for": 3.0, "bob": {"amp": 0.04, "rate": 0.8, "for": 6.0}},
		{"do": "pose", "who": "other", "face": "giggle", "for": 1.6},
		{"do": "sound", "cue": "drip"},
		{"do": "wait", "time": 1.4},
		# The pipsport floats off downstream into the fog.
		{"do": "prop", "id": "pipsport", "follow": ""},
		{"do": "prop", "id": "pipsport", "to": [1.4, -0.1, 2.3], "time": 3.6, "ease": "linear", "spin": 25.0},
		{"do": "prop", "id": "fog", "alpha": 0.85, "time": 2.0},
		{"do": "face", "who": "carrier", "toward": [1.4, 0.0, 2.3]},
		{"do": "face", "who": "other", "toward": [1.4, 0.0, 2.3]},
		{"do": "pose", "who": "carrier", "face": "gasp", "for": 2.6},
		{"do": "pose", "who": "other", "face": "huh", "for": 2.6},
		{"do": "camera", "at": [0.3, 0.2, 1.3], "size": 6.0, "time": 2.0},
		{"do": "wait", "time": 2.2},
		{"do": "prop", "id": "pipsport", "alpha": 0.0, "time": 1.2},
		{"do": "wait", "time": 1.6},
	],
}
