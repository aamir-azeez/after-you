extends RefCounted
## Descriptor for the Pond bud cosmetic (the Pollen hats and leaves board). Fields: content/cosmetics/index.gd.
const PlayerCopy = preload("res://presentation/player_copy.gd")
const DATA := {
	"id": "pond_bud",
	"slot": "leaf",
	"tier": "rare",
	"name": PlayerCopy.COSMETIC_POND_BUD,
	"art": "res://presentation/pip_wear/garden_leaf.gd",
	"code": 213,
	## Held back until the server's release list names it.
	"released": false,
	## It stands above the head.
	"tall": true,
}
