extends RefCounted
## Descriptor for the Top 10 ribbon cosmetic. Fields: content/cosmetics/index.gd.
const PlayerCopy = preload("res://presentation/player_copy.gd")
const DATA := {
	"id": "top_ten_ribbon",
	"slot": "hat",
	"tier": "earned",
	"name": PlayerCopy.COSMETIC_TOP_TEN_RIBBON,
	"art": "res://presentation/pip_wear/top_ten_ribbon.gd",
	## A together run in a chapter board's all time top 10.
}
