extends RefCounted
## Descriptor for the Wool cap cosmetic (the Pollen hats and leaves board). Fields: content/cosmetics/index.gd.
const PlayerCopy = preload("res://presentation/player_copy.gd")
const DATA := {
	"id": "wool_cap",
	"slot": "hat",
	"tier": "uncommon",
	"name": PlayerCopy.COSMETIC_WOOL_CAP,
	"art": "res://presentation/pip_wear/soft_cap.gd",
	"code": 203,
	## Held back until the server's release list names it.
	"released": false,
	## Its crown stands above the head.
	"tall": true,
	## The leaf pokes through a notch cut on its side.
	"leaf_mode": "pokes_through",
	"leaf_max": "medium",
}
