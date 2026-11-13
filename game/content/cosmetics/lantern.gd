extends RefCounted
## Descriptor for the Lantern cosmetic. Fields: content/cosmetics/index.gd.
const PlayerCopy = preload("res://presentation/player_copy.gd")
const DATA := {
	"id": "lantern",
	"slot": "hat",
	"tier": "epic",
	"name": PlayerCopy.COSMETIC_LANTERN,
	"art": "res://presentation/pip_wear/lantern.gd",
	## Its stalk arcs above the head.
	"tall": true,
	## It hangs beside the head on the side the pip views turn away.
	"wide": true,
	## The leaf grows clear beside it.
	"leaf_mode": "pokes_through",
	"leaf_max": "tall",
}
