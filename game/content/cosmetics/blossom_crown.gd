extends RefCounted
## Descriptor for the Blossom crown cosmetic (the Orchard, bought with Fruits). Fields: content/cosmetics/index.gd.
const PlayerCopy = preload("res://presentation/player_copy.gd")
const DATA := {
	"id": "blossom_crown",
	"code": 12,
	"slot": "hat",
	"tier": "fruit_hat",
	"name": PlayerCopy.COSMETIC_BLOSSOM_CROWN,
	"art": "res://presentation/pip_wear/blossom_crown.gd",
	## The leaf stands up on the ring of blossoms, raised clear of them, so
	## the views pull back for it.
	"tall": true,
	"leaf_lift": 0.1,
	"leaf_mode": "sits_on_top",
	"leaf_max": "small",
}
