extends RefCounted
## Seed fluff (trail): soft cream fluff puffs, left on the floor while the pip walks
## (the board's Seed fluff row). A recipe for the trail kit (kit/trail_kit.gd),
## with the board's numbers (the width as its walking row reads at phone size): a life of 0.75 s, a drift of 0.035 pip widths and 10 degrees a second.
const TrailKit = preload("res://presentation/kit/trail_kit.gd")

const RECIPE := {
	"id": "seed_fluff",
	"shape": &"puff",
	"width": 0.22,
	"colors": [Color("eee9d4"), Color("d9d7bb")],
	"life": 0.75,
	"drift": 0.035,
	"spin": 10.0,
	"turn": PI,
}

static func wear(look: RefCounted) -> void:
	TrailKit.wear(look, RECIPE)
