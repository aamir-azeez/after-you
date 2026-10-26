extends RefCounted
## Descriptor for the Gold leaf cosmetic. Fields: content/cosmetics/index.gd.
const PlayerCopy = preload("res://presentation/player_copy.gd")
const DATA := {
	"id": "gold_leaf",
	"slot": "leaf",
	"tier": "earned",
	"name": PlayerCopy.COSMETIC_GOLD_LEAF,
	"art": "res://presentation/pip_wear/gold_leaf.gd",
	## Ever holding first place on a chapter board.
	## Its sparkles stand above the leaf.
	"tall": true,
}
