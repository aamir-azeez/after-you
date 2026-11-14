extends RefCounted
## Descriptor for the Mushroom cosmetic (the Pollen hats and leaves board). Fields: content/cosmetics/index.gd.
const PlayerCopy = preload("res://presentation/player_copy.gd")
const DATA := {
	"id": "mushroom",
	"slot": "hat",
	"tier": "uncommon",
	"name": PlayerCopy.COSMETIC_MUSHROOM,
	"art": "res://presentation/pip_wear/soft_cap.gd",
	"code": 204,
	## Held back until the server's release list names it.
	"released": false,
	## Its cap stands above the head.
	"tall": true,
	## The cap is whole: the leaf comes out of its top on a short stem.
	"leaf_mode": "sits_on_top",
	"leaf_lift": 0.185,
	"leaf_max": "tall",
}
