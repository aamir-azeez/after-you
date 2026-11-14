extends RefCounted
## Descriptor for the Glass house cosmetic (the Pollen hats and leaves board). Fields: content/cosmetics/index.gd.
const PlayerCopy = preload("res://presentation/player_copy.gd")
const DATA := {
	"id": "glass_house",
	"slot": "hat",
	"tier": "special",
	"name": PlayerCopy.COSMETIC_GLASS_HOUSE,
	"art": "res://presentation/pip_wear/glass_house.gd",
	"code": 207,
	## Held back until the server's release list names it.
	"released": false,
	## Clearing The Conservatory first, as the catalogue themes it.
	"unlock": "conservatory",
	## It stands above the head.
	"tall": true,
	## The leaf grows clear beside it.
	"leaf_mode": "pokes_through",
	"leaf_max": "medium",
}
