extends RefCounted
## Snow steps (trail): pale snow marks of eight arms, left on the floor while the pip walks
## (the board's Snow steps row). A recipe for the trail kit (kit/trail_kit.gd),
## with the board's numbers (the width as its walking row reads at phone size): an interval of 0.5 s, a
## life of 0.8 s, a drift of 0.025 pip widths and 12 degrees a second.
const TrailKit = preload("res://presentation/kit/trail_kit.gd")

const RECIPE := {
	"id": "snow_steps",
	"shape": &"snow_mark",
	"width": 0.24,
	"colors": [Color("d6e4df"), Color("b8d2d0")],
	"interval": 0.5,
	"life": 0.8,
	"drift": 0.025,
	"spin": 12.0,
	"turn": PI,
}

static func wear(look: RefCounted) -> void:
	TrailKit.wear(look, RECIPE)
