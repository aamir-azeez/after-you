extends RefCounted
## The Conservatory, version 2: version 1's look, with the fork balcony over
## the court's west side laid as a plank deck. Its posts, rails and the fern
## trough meeting the back wall are the world's (conservatory_world.gd
## _build_balcony), since they stand over the court's walkable floor. The west
## basket hangs further west, clear of the balcony's corner.

const V1 = preload("res://content/dressing/conservatory.gd")

const DATA := {
	"look": V1.DATA.look,
	"ground": {"*": "tile", "garden": "grass", "fork-balcony": "deck"},
	"stairs": V1.DATA.stairs,
	"bridges": V1.DATA.bridges,
	"stair_rail": V1.DATA.stair_rail,
	"goal": V1.DATA.goal,
	"props": {"*": V1.COURT_BACK + [{"kind": "basket", "at": [-600, -436], "surface": "court", "y": 150, "wall": true}] + V1.REST},
}
