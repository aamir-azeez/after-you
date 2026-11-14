extends RefCounted
## Soft stars (trail): soft four point stars in gold and cream, no flashing, left on the floor while the pip walks
## (the board's Soft stars row). A recipe for the trail kit (kit/trail_kit.gd),
## with the board's numbers (the width as its walking row reads at phone size): a life of 0.7 s, a drift of 0.02 pip widths and 0 degrees a second.
const TrailKit = preload("res://presentation/kit/trail_kit.gd")

const RECIPE := {
	"id": "soft_stars",
	"shape": &"sparkle",
	"width": 0.22,
	"colors": [Color("e4cc90"), Color("eee9d4")],
	"life": 0.7,
	"drift": 0.02,
	"spin": 0.0,
	"turn": 0.4,
}

static func wear(look: RefCounted) -> void:
	TrailKit.wear(look, RECIPE)
