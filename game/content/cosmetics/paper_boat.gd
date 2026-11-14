extends RefCounted
## Descriptor for the Paper boat cosmetic (the Pollen hats and leaves board). Fields: content/cosmetics/index.gd.
const PlayerCopy = preload("res://presentation/player_copy.gd")
const DATA := {
	"id": "paper_boat",
	"slot": "hat",
	"tier": "uncommon",
	"name": PlayerCopy.COSMETIC_PAPER_BOAT,
	"art": "res://presentation/pip_wear/paper_boat.gd",
	"code": 200,
	## Held back until the server's release list names it.
	"released": false,
	## It stands above the head.
	"tall": true,
	## The boat sits under the leaf and the leaf comes out of its top (kit/wear_fit.gd top anchor).
	"leaf_mode": "sits_on_top",
	"leaf_max": "medium",
}
