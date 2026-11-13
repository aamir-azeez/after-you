extends RefCounted
## Raindrops (trail): pale blue drops, upright, no splash, left on the floor while the pip walks
## (the board's Raindrops row). A recipe for the trail kit (kit/trail_kit.gd),
## with the board's numbers (the width as its walking row reads at phone size): an interval of 0.4 s, a
## life of 0.7 s, a drift of 0.03 pip widths and 0 degrees a second.
const TrailKit = preload("res://presentation/kit/trail_kit.gd")

const RECIPE := {
	"id": "rain_drops",
	"shape": &"raindrop",
	"width": 0.22,
	"colors": [Color("a5ccd5"), Color("77a7b7")],
	"interval": 0.4,
	"life": 0.7,
	"drift": 0.03,
	"spin": 0.0,
	"turn": 0.35,
}

static func wear(look: RefCounted) -> void:
	TrailKit.wear(look, RECIPE)
