extends RefCounted
## The Sleeping Lighthouse, version 3, on the shared journey world: version
## 1's golden hour (content/dressing/sleeping_lighthouse.gd), with every isle
## dressed on every stage (the journey keeps all six isles in view from the
## start) and the camera following the live pip across the isles and in depth.

const V1 = preload("res://content/dressing/sleeping_lighthouse.gd")

const DATA := {
	"look": V1.DATA.look,
	"ground": V1.DATA.ground,
	"bridges": V1.DATA.bridges,
	"fireflies": V1.DATA.fireflies,
	"picks": V1.DATA.picks,
	"edging": V1.DATA.edging,
	"edged": V1.DATA.edged,
	"camera": {"follow": {"size": 5.8, "axes": "xz", "lift": 1.0, "inset": [5.0, 1.6], "zoom": [0.75, 1.6], "pan": [1.0, 0.7], "from": [6.0, 12.0, 20.0]}},
	"props": {"*": V1.DATA.props["*"] + V1.NORTH + V1.SOUTH + V1.TOWER},
}
