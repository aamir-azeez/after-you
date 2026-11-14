extends RefCounted
## Descriptor for the Feather cosmetic (the Pollen hats and leaves board). Fields: content/cosmetics/index.gd.
const PlayerCopy = preload("res://presentation/player_copy.gd")
const DATA := {
	"id": "feather",
	"slot": "leaf",
	"tier": "uncommon",
	"name": PlayerCopy.COSMETIC_FEATHER,
	"art": "res://presentation/pip_wear/garden_leaf.gd",
	"code": 209,
	## Held back until the server's release list names it.
	"released": false,
	## It stands above the head.
	"tall": true,
}
