extends RefCounted
## Descriptor for the Mushroom cosmetic (the Pollen hats and leaves board). Fields: content/cosmetics/index.gd.
const PlayerCopy = preload("res://presentation/player_copy.gd")
const DATA := {
	"id": "mushroom",
	"slot": "hat",
	"tier": "common",
	"name": PlayerCopy.COSMETIC_MUSHROOM,
	"art": "res://presentation/pip_wear/soft_cap.gd",
	"code": 204,
	## Held back until the server's release list names it.
	"released": false,
	## The cap is whole: the leaf sits right on its top (kit/wear_fit.gd top anchor).
	"leaf_mode": "sits_on_top",
	"leaf_max": "medium",
}
