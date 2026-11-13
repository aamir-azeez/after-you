extends RefCounted
## Blue pottery (body): cream glazeware with one broad blue wave round
## the bottom of the head and a narrow pale blue edge along its top; the body
## and feet stay cream. Flat colour, no glaze shine.
## A recipe for the skin pattern kit (kit/skin_pattern.gd), in the board's
## surface coordinates and palette.
const SkinPattern = preload("res://presentation/kit/skin_pattern.gd")

const CREAM := Color("eee5d2")
const BLUE := Color("527c9c")
const PALE := Color("b5ccd3")
const RECIPE := {
	"id": "blue_pottery",
	"head": {
		"base": CREAM,
		"bands": [{"from": 0.69, "to": 0.98, "kind": "wave", "period": 0.36, "amplitude": 0.08, "color": BLUE, "edge": 0.04, "edge_color": PALE}],
	},
	"body": {"base": CREAM},
	"feet": [CREAM, CREAM],
}

static func wear(look: RefCounted) -> void:
	SkinPattern.wear(look, RECIPE)
