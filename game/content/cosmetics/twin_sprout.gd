extends RefCounted
## Descriptor for the Twin sprout cosmetic (the Pollen hats and leaves board). Fields: content/cosmetics/index.gd.
const PlayerCopy = preload("res://presentation/player_copy.gd")
const DATA := {
	"id": "twin_sprout",
	"slot": "leaf",
	"tier": "uncommon",
	"name": PlayerCopy.COSMETIC_TWIN_SPROUT,
	"art": "res://presentation/pip_wear/garden_leaf.gd",
	"code": 211,
	## Held back until the server's release list names it.
	"released": false,
	## It stands above the head.
	"tall": true,
}
