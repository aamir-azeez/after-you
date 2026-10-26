extends RefCounted
## Descriptor for the Straw hat cosmetic. Fields: content/cosmetics/index.gd.
const PlayerCopy = preload("res://presentation/player_copy.gd")
const DATA := {
	"id": "straw_hat",
	"slot": "hat",
	"tier": "uncommon",
	"name": PlayerCopy.COSMETIC_STRAW_HAT,
	"art": "res://presentation/pip_wear/straw_hat.gd",
	## The leaf pokes up through the brim.
	"leaf_lift": 0.075,
	"tall": true,
}
