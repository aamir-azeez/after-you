extends RefCounted
## Leaves (trail): small brown and tan leaves that turn gently as they drift, left on the floor while the pip walks
## (the board's Leaves row). A recipe for the trail kit (kit/trail_kit.gd),
## with the board's numbers: width in pip widths, an interval of 0.4 s, a
## life of 0.8 s, a drift of 0.06 pip widths and 20 degrees a second.
const TrailKit = preload("res://presentation/kit/trail_kit.gd")

const RECIPE := {
	"id": "leaves",
	"shape": &"leaf",
	"width": 0.1,
	"colors": [Color("af895a"), Color("d3a66c")],
	"interval": 0.4,
	"life": 0.8,
	"drift": 0.06,
	"spin": 20.0,
	"turn": PI,
}

static func wear(look: RefCounted) -> void:
	TrailKit.wear(look, RECIPE)
