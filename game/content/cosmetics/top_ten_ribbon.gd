extends RefCounted
## Descriptor for the Top 10 ribbon cosmetic. Fields: content/cosmetics/index.gd.
const PlayerCopy = preload("res://presentation/player_copy.gd")
const DATA := {
	"id": "top_ten_ribbon",
	"code": 9,
	"slot": "hat",
	"tier": "earned",
	"name": PlayerCopy.COSMETIC_TOP_TEN_RIBBON,
	"earn": PlayerCopy.COSMETIC_TOP_TEN_RIBBON_EARN,
	"art": "res://presentation/pip_wear/top_ten_ribbon.gd",
	## The views pull back so the whole rosette shows.
	"tall": true,
	## A together run in a chapter board's all time top 10.,
	## The leaf grows clear beside it.
	"leaf_mode": "pokes_through",
	"leaf_max": "tall",
}
