extends RefCounted
## Autumn (body): a warm rust pip scattered with maple leaves in gold, deep
## brown and one red: three on the face, kept clear of the eyes, two on the
## crown, three on the back of the head, and two on the body front and back.
## Its leaf slot is still free for a leaf item. The left face leaf sits
## further out than the notes give, round the side as the board draws it, so
## the eye's safety oval takes only its edge.
## A recipe for the skin pattern kit (kit/skin_pattern.gd), in the board's
## surface coordinates and palette.
const SkinPattern = preload("res://presentation/kit/skin_pattern.gd")

const RUST := Color("bd7c58")
const GOLD := Color("e6b16a")
const BROWN := Color("945c44")
const RED := Color("c8402e")
const RECIPE := {
	"id": "autumn",
	"head": {
		"base": RUST,
		"stamps": [
			{"shape": "leaf", "at": Vector2(0.60, 0.14), "width": 0.27, "turn": 0.45, "color": GOLD},
			{"shape": "leaf", "at": Vector2(0.06, 0.46), "width": 0.30, "turn": -0.6, "color": BROWN},
			{"shape": "leaf", "at": Vector2(0.77, 0.84), "width": 0.26, "turn": 0.25, "color": RED},
			# Two more on the crown, for the chapters' high cameras.
			{"shape": "leaf", "at": Vector2(0.32, -0.55), "width": 0.3, "turn": -0.3, "color": GOLD},
			{"shape": "leaf", "at": Vector2(0.72, -1.0), "width": 0.26, "turn": 0.8, "color": BROWN},
			# And round the back.
			{"shape": "leaf", "at": Vector2(0.28, 0.42), "width": 0.3, "turn": 0.5, "color": BROWN, "back": true},
			{"shape": "leaf", "at": Vector2(0.74, 0.58), "width": 0.28, "turn": -0.4, "color": GOLD, "back": true},
			{"shape": "leaf", "at": Vector2(0.42, 0.88), "width": 0.26, "turn": 0.9, "color": RED, "back": true},
		],
	},
	"body": {
		"base": RUST,
		"stamps": [
			{"shape": "leaf", "at": Vector2(0.3, 0.66), "width": 0.3, "turn": 0.3, "color": GOLD},
			{"shape": "leaf", "at": Vector2(0.74, 0.74), "width": 0.28, "turn": -0.5, "color": BROWN},
			{"shape": "leaf", "at": Vector2(0.36, 0.7), "width": 0.3, "turn": -0.3, "color": RED, "back": true},
			{"shape": "leaf", "at": Vector2(0.72, 0.62), "width": 0.28, "turn": 0.6, "color": GOLD, "back": true},
		],
	},
	"feet": [RUST, RUST],
}

static func wear(look: RefCounted) -> void:
	SkinPattern.wear(look, RECIPE)
