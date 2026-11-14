extends RefCounted
## Descriptor for the Paper boat cosmetic (the Pollen hats and leaves board). Fields: content/cosmetics/index.gd.
const PlayerCopy = preload("res://presentation/player_copy.gd")
const DATA := {
	"id": "paper_boat",
	"slot": "hat",
	"tier": "common",
	"name": PlayerCopy.COSMETIC_PAPER_BOAT,
	"art": "res://presentation/pip_wear/paper_boat.gd",
	"code": 200,
	## Held back until the server's release list names it.
	"released": false,
	## It stands above the head.
	"tall": true,
	## Its raised end hangs out past the head on the side the views turn away.
	"wide": true,
	## The leaf grows clear beside it.
	"leaf_mode": "pokes_through",
	"leaf_max": "medium",
}
