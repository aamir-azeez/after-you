extends RefCounted
## Descriptor for the Tide cosmetic. Fields: content/cosmetics/index.gd.
const PlayerCopy = preload("res://presentation/player_copy.gd")
const DATA := {
	"id": "tide",
	"slot": "body",
	"tier": "rare",
	"name": PlayerCopy.COSMETIC_TIDE,
	"art": "res://presentation/pip_wear/tide.gd",
}
