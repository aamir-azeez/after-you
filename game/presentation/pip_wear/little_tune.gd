extends RefCounted
## Little tune (trail): pairs of joined notes, upright, left on the floor while
## the pip walks; the trail makes no sound
## (the board's Little tune row). A recipe for the trail kit (kit/trail_kit.gd),
## with the board's numbers: width in pip widths, an interval of 1.0 / 1.7 s, a
## life of 0.75 s, a drift of 0.03 pip widths and 0 degrees a second.
const TrailKit = preload("res://presentation/kit/trail_kit.gd")

const RECIPE := {
	"id": "little_tune",
	"shape": &"notes",
	"width": 0.11,
	"colors": [Color("e6d7ae"), Color("b6c9ad")],
	"interval": 1.0 / 1.7,
	"life": 0.75,
	"drift": 0.03,
	"spin": 0.0,
	"turn": 0.3,
}

static func wear(look: RefCounted) -> void:
	TrailKit.wear(look, RECIPE)
