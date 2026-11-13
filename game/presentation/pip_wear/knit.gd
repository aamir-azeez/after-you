extends RefCounted
## Knit (body): a cream knit with broad rose zigzag bands round the head
## (one more across the crown, which the chapters' high cameras see most)
## and one round the body, rose feet and a thin seam down the back of the head
## and body, all flat colour on the pip's own surfaces (the board's Knit).
## A recipe for the skin pattern kit (kit/skin_pattern.gd), in the board's
## surface coordinates and palette.
const SkinPattern = preload("res://presentation/kit/skin_pattern.gd")

const CREAM := Color("eee5d2")
const ROSE := Color("c18c8b")
const SEAM := Color("9b756e")
const RECIPE := {
	"id": "knit",
	"head": {
		"base": CREAM,
		"bands": [
			{"from": 0.28, "to": 0.58, "kind": "zigzag", "period": 0.40, "amplitude": 0.06, "color": ROSE},
			{"from": 0.82, "to": 0.98, "kind": "zigzag", "period": 0.40, "amplitude": 0.06, "color": ROSE},
			# Over the crown, for the chapters' high cameras.
			{"from": -0.92, "to": -0.62, "kind": "zigzag", "period": 0.40, "amplitude": 0.06, "color": ROSE},
			# And one down the back.
			{"from": -2.0, "to": -1.7, "kind": "zigzag", "period": 0.40, "amplitude": 0.06, "color": ROSE},
		],
		"seam": {"color": SEAM, "width": 0.025},
	},
	"body": {
		"base": CREAM,
		"bands": [{"from": 0.45, "to": 0.80, "kind": "zigzag", "period": 0.40, "amplitude": 0.06, "color": ROSE}],
		"seam": {"color": SEAM, "width": 0.025},
	},
	"feet": [ROSE, ROSE],
}

static func wear(look: RefCounted) -> void:
	SkinPattern.wear(look, RECIPE)
