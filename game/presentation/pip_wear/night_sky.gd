extends RefCounted
## Night sky (body): deep blue all over with three cream stars on the
## face (and one on top of the head), kept clear of the eyes (the board's upper left star sits a little
## further out than its notes give, so it clears the eye's safety oval whole), and one small dusk blue star round the back.
## The stars drift very slowly (8 s, triangle shaped) with the pip's clock;
## Reduce motion holds them still.
## A recipe for the skin pattern kit (kit/skin_pattern.gd), in the board's
## surface coordinates and palette.
const SkinPattern = preload("res://presentation/kit/skin_pattern.gd")

const NIGHT := Color("244752")
const DUSK := Color("6d8792")
const STAR := Color("eee5d2")
const RECIPE := {
	"id": "night_sky",
	"head": {
		"base": NIGHT,
		"stamps": [
			{"shape": "star", "at": Vector2(0.06, 0.24), "width": 0.20, "turn": -0.25, "color": STAR},
			{"shape": "star", "at": Vector2(0.59, 0.13), "width": 0.18, "turn": 0.15, "color": STAR},
			{"shape": "star", "at": Vector2(0.72, 0.81), "width": 0.19, "turn": 0.35, "color": STAR},
			{"shape": "star", "at": Vector2(0.38, 0.30), "width": 0.12, "turn": 0.1, "color": DUSK, "back": true},
			# On top of the head, for the chapters' high cameras.
			{"shape": "star", "at": Vector2(0.45, -0.55), "width": 0.22, "turn": 0.2, "color": STAR},
		],
	},
	"body": {"base": NIGHT},
	"feet": [NIGHT, NIGHT],
	"drift": 0.0075,
}

static func wear(look: RefCounted) -> void:
	SkinPattern.wear(look, RECIPE)
