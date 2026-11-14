extends RefCounted
## Descriptor for the Warm tip cosmetic (the Pollen hats and leaves board). Fields: content/cosmetics/index.gd.
const PlayerCopy = preload("res://presentation/player_copy.gd")
const DATA := {
	"id": "warm_tip",
	"slot": "leaf",
	"tier": "common",
	"name": PlayerCopy.COSMETIC_WARM_TIP,
	"art": "res://presentation/pip_wear/garden_leaf.gd",
	"code": 212,
	## Held back until the server's release list names it.
	"released": false,
	## It stands above the head.
	"tall": true,
}
