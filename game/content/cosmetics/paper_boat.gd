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
	## The leaf comes out of the boat's hull just left of the stripe, raised
	## this far to the hull's rim there (its own leaf point, not the shared top
	## anchor; it may clip the paper it passes).
	"leaf_mode": "sits_on_top",
	"leaf_lift": 0.045,
	"leaf_max": "medium",
}
