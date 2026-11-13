extends RefCounted
## Patchwork (body): broad softly curved colour fields, cream up top right,
## mint low left and plum low right of the head on a warm clay base; the body
## and feet split mint and plum with a small cream field at the top.
## A recipe for the skin pattern kit (kit/skin_pattern.gd), in the board's
## surface coordinates and palette.
const SkinPattern = preload("res://presentation/kit/skin_pattern.gd")

const CLAY := Color("dbab91")
const CREAM := Color("eee5d2")
const MINT := Color("9fc5b4")
const PLUM := Color("89778d")
const RECIPE := {
	"id": "patchwork",
	"head": {
		"base": CLAY,
		"fields": [
			{"points": [Vector2(0.42, -2.6), Vector2(0.42, -0.1), Vector2(0.65, 0.34), Vector2(1.4, 0.45), Vector2(1.4, -2.6)], "color": CREAM, "wander": 0.02},
			{"points": [Vector2(-0.4, 0.43), Vector2(0.22, 0.48), Vector2(0.49, 0.77), Vector2(0.48, 1.4), Vector2(-0.4, 1.4)], "color": MINT, "wander": 0.02},
			{"points": [Vector2(0.59, 0.64), Vector2(1.4, 0.42), Vector2(1.4, 1.4), Vector2(0.47, 1.4)], "color": PLUM, "wander": 0.02},
			# The crown's back left, so the top reads as patchwork from the chapters' high cameras.
			{"points": [Vector2(-0.4, -2.6), Vector2(0.44, -2.6), Vector2(0.4, -0.72), Vector2(-0.4, -0.55)], "color": PLUM, "wander": 0.02},
		],
	},
	"body": {
		"base": CLAY,
		"fields": [
			{"points": [Vector2(-0.4, -0.4), Vector2(0.5, -0.4), Vector2(0.53, 1.4), Vector2(-0.4, 1.4)], "color": MINT, "wander": 0.02},
			{"points": [Vector2(0.5, -0.4), Vector2(1.4, -0.4), Vector2(1.4, 1.4), Vector2(0.53, 1.4)], "color": PLUM, "wander": 0.02},
			{"points": [Vector2(0.32, -0.4), Vector2(0.7, -0.4), Vector2(0.62, 0.3), Vector2(0.4, 0.34)], "color": CREAM, "wander": 0.015},
		],
	},
	"feet": [MINT, PLUM],
}

static func wear(look: RefCounted) -> void:
	SkinPattern.wear(look, RECIPE)
