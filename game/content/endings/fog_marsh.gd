extends RefCounted
## Fog Marsh's ending (services/ending_scene.gd has the format): the soggy
## pipsport is set on the stamp desk, a thunk as it is stamped, both pips hold
## it up, the fog lifts, and a little rocket waits on a hill: next, Space.
## It plays at the post office's stamp desk (the dressing's "stamp_desk"
## anchor, the desk's foot), the pips beside it on the office floor; the scene
## adds the stamp, its mark, the fog it lifts, the hill out in the marsh behind
## the office with its rocket, the moon, and
## the real pipsport in place of the world's.
const PlayerCopy = preload("res://presentation/player_copy.gd")

const DATA := {
	"cast": {"holds": "pipsport", "fallback": "p0"},
	"origin": "stamp_desk",
	"props": {
		"pipsport": {"shape": "item", "style": "pipsport", "at": [1.17, 1.06, 0.25]},
		"stamp": {"shape": "cylinder", "size": [0.12, 0.3], "color": "6b5038", "at": [0.0, 1.6, 0.0], "shown": false},
		"mark": {"shape": "cylinder", "size": [0.08, 0.01], "color": "c0504d", "at": [0.0, 0.735, 0.0], "shown": false},
		"fog": {"shape": "box", "size": [40.0, 1.8, 40.0], "color": "e8eeee", "at": [0.95, 0.7, 0.35], "alpha": 0.45},
		"hill": {"shape": "sphere", "size": [1.0, 2.0], "color": "7fa36a", "at": [5.4, -1.6, -5.2]},
		"rocket": {"shape": "cylinder", "size": [0.16, 0.8], "color": "f4f1ea", "at": [5.4, -0.2, -5.2], "shown": false},
		"nose": {"shape": "cone", "size": [0.16, 0.32], "color": "d9534f", "at": [5.4, 0.36, -5.2], "shown": false},
		"fins": {"shape": "box", "size": [0.5, 0.18, 0.06], "color": "d9534f", "at": [5.4, -0.52, -5.2], "shown": false},
		"moon": {"shape": "sphere", "size": [0.45, 0.9], "color": "f3e3a3", "at": [7.2, 2.6, -7.6], "shown": false, "glow": 0.8},
	},
	"steps": [
		{"do": "prop", "id": "pipsport", "follow": "carrier"},
		{"do": "camera", "at": [1.17, 0.5, 0.05], "size": 5.5, "time": 1.0},
		{"do": "move", "who": "carrier", "to": [0.62, 0.0, 0.25], "time": 1.0},
		{"do": "move", "who": "other", "to": [1.72, 0.0, 0.25], "time": 1.0},
		{"do": "wait", "time": 1.1},
		# The soggy pipsport, set on the stamp desk.
		{"do": "face", "who": "carrier", "toward": [0.0, 0.0, 0.0]},
		{"do": "face", "who": "other", "toward": [0.0, 0.0, 0.0]},
		{"do": "prop", "id": "pipsport", "follow": ""},
		{"do": "prop", "id": "pipsport", "to": [0.0, 0.69, 0.0], "time": 0.6, "arc": 0.2},
		{"do": "pose", "who": "carrier", "face": "nervous", "for": 1.0},
		{"do": "sound", "cue": "drip"},
		{"do": "wait", "time": 0.9},
		# Thunk. Stamped for Space.
		{"do": "prop", "id": "stamp", "show": true},
		{"do": "prop", "id": "stamp", "to": [0.0, 0.9, 0.0], "time": 0.35, "ease": "in"},
		{"do": "wait", "time": 0.35},
		{"do": "sound", "cue": "ending_stamp"},
		{"do": "prop", "id": "mark", "show": true},
		{"do": "pose", "who": "other", "face": "wow", "for": 1.0},
		{"do": "pose", "who": "carrier", "face": "surprised", "for": 0.6},
		{"do": "prop", "id": "stamp", "to": [0.0, 1.6, 0.0], "time": 0.4},
		{"do": "wait", "time": 0.6},
		{"do": "prop", "id": "stamp", "show": false},
		# Both hold it up, and the fog lifts off the marsh.
		{"do": "move", "who": "carrier", "to": [0.77, 0.0, 0.25], "time": 0.5},
		{"do": "move", "who": "other", "to": [1.57, 0.0, 0.25], "time": 0.5},
		{"do": "prop", "id": "pipsport", "to": [1.17, 1.3, 0.25], "time": 0.6, "arc": 0.15},
		{"do": "prop", "id": "mark", "to": [1.17, 1.325, 0.25], "time": 0.6, "arc": 0.15},
		{"do": "wait", "time": 0.6},
		{"do": "face", "who": "carrier", "toward": "other"},
		{"do": "face", "who": "other", "toward": "carrier"},
		{"do": "pose", "who": "carrier", "face": "joy", "for": 2.6, "hop": 0.5, "cheer": true},
		{"do": "pose", "who": "other", "face": "joy", "for": 2.6, "hop": 0.5, "cheer": true},
		{"do": "prop", "id": "fog", "alpha": 0.0, "time": 2.4},
		{"do": "wait", "time": 2.6},
		# A little rocket on the hill: the next chapter.
		{"do": "prop", "id": "rocket", "show": true},
		{"do": "prop", "id": "nose", "show": true},
		{"do": "prop", "id": "fins", "show": true},
		{"do": "prop", "id": "moon", "show": true},
		{"do": "camera", "at": [3.4, 0.3, -2.6], "size": 5.6, "time": 1.6},
		{"do": "wait", "time": 1.2},
		{"do": "caption", "text": PlayerCopy.ENDING_NEXT_SPACE, "for": 2.6},
		{"do": "wait", "time": 2.8},
	],
}
