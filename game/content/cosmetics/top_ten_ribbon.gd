extends RefCounted
## Descriptor for the Top 10 ribbon cosmetic. Fields: content/cosmetics/index.gd.
const PlayerCopy = preload("res://presentation/player_copy.gd")
const DATA := {
	"id": "top_ten_ribbon",
	"slot": "",
	"tier": "earned",
	"name": PlayerCopy.COSMETIC_TOP_TEN_RIBBON,
	"art": "",
	## A together run in a chapter board's all time top 10. The owner has not
	## placed it on the pip yet, so it has no slot and no art.
}
