extends RefCounted
## Autumn (body): a warm rust pip with three broad five lobed leaves on
## the face, one gold and two deep brown, and two more on the crown, kept clear of the eyes; the body and
## feet stay plain. Its leaf slot is still free for a leaf item. The left
## leaf sits further out than the notes give, round the side as the board
## draws it, so the eye's safety oval takes only its edge.
## A recipe for the skin pattern kit (kit/skin_pattern.gd), in the board's
## surface coordinates and palette.
const SkinPattern = preload("res://presentation/kit/skin_pattern.gd")

const RUST := Color("bd7c58")
const GOLD := Color("e6b16a")
const BROWN := Color("945c44")
const RECIPE := {
	"id": "autumn",
	"head": {
		"base": RUST,
		"stamps": [
			{"shape": "leaf", "at": Vector2(0.60, 0.14), "width": 0.27, "turn": 0.45, "color": GOLD},
			{"shape": "leaf", "at": Vector2(0.06, 0.46), "width": 0.30, "turn": -0.6, "color": BROWN},
			{"shape": "leaf", "at": Vector2(0.77, 0.84), "width": 0.26, "turn": 0.25, "color": BROWN},
			# Two more on the crown, for the chapters' high cameras.
			{"shape": "leaf", "at": Vector2(0.32, -0.55), "width": 0.3, "turn": -0.3, "color": GOLD},
			{"shape": "leaf", "at": Vector2(0.72, -1.0), "width": 0.26, "turn": 0.8, "color": BROWN},
		],
	},
	"body": {"base": RUST},
	"feet": [RUST, RUST],
}

static func wear(look: RefCounted) -> void:
	SkinPattern.wear(look, RECIPE)
