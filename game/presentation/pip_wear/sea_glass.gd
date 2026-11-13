extends RefCounted
## Sea glass (body): mint all over with one broad blue current flowing
## round the head through the eyes' height and a pale field up top left. The
## current drifts very slowly (8 s, triangle shaped) with the pip's clock;
## Reduce motion holds it still. Matte, no see-through or shine.
## A recipe for the skin pattern kit (kit/skin_pattern.gd), in the board's
## surface coordinates and palette.
const SkinPattern = preload("res://presentation/kit/skin_pattern.gd")

const MINT := Color("9fd1c1")
const CURRENT := Color("7eb4c5")
const PALE := Color("d1e5d8")
const RECIPE := {
	"id": "sea_glass",
	"head": {
		"base": MINT,
		"fields": [{"points": [Vector2(-0.05, -0.05), Vector2(0.66, -0.05), Vector2(0.48, 0.18), Vector2(0.22, 0.27), Vector2(-0.05, 0.3)], "color": PALE, "wander": 0.02}],
		"bands": [{"from": 0.30, "to": 0.65, "kind": "wave", "period": 0.90, "amplitude": 0.08, "color": CURRENT}],
	},
	"body": {"base": MINT},
	"feet": [MINT, MINT],
	"drift": 0.01,
}

static func wear(look: RefCounted) -> void:
	SkinPattern.wear(look, RECIPE)
