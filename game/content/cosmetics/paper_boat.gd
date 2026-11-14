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
	## The boat sits over the leaf's sprout and the leaf comes out of it: from
	## inside the hull up through the sail's middle and out of its top, raised
	## this far (its own leaf point, not the shared top anchor; it may clip
	## the paper it passes through).
	"leaf_mode": "sits_on_top",
	"leaf_lift": 0.135,
	"leaf_max": "medium",
}
