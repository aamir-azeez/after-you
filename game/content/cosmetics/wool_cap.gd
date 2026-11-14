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
	## The cap is whole: the leaf comes out of its top on a short stem.
	"leaf_mode": "sits_on_top",
	"leaf_lift": 0.205,
	"leaf_max": "tall",
}
