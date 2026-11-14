extends RefCounted
## Descriptor for the Flower pot cosmetic (the Pollen hats and leaves board). Fields: content/cosmetics/index.gd.
const PlayerCopy = preload("res://presentation/player_copy.gd")
const DATA := {
	"id": "flower_pot",
	"slot": "hat",
	"tier": "common",
	"name": PlayerCopy.COSMETIC_FLOWER_POT,
	"art": "res://presentation/pip_wear/vessel_hat.gd",
	"code": 202,
	## Held back until the server's release list names it.
	"released": false,
	## It stands above the head.
	"tall": true,
	## The leaf grows clear beside it.
	"leaf_mode": "pokes_through",
	"leaf_max": "medium",
}
