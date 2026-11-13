extends RefCounted
## Descriptor for the Blue pottery body skin. Fields: content/cosmetics/index.gd.
const PlayerCopy = preload("res://presentation/player_copy.gd")
const DATA := {
	"id": "blue_pottery",
	"code": 303,
	"slot": "body",
	"tier": "rare",
	"name": PlayerCopy.COSMETIC_BLUE_POTTERY,
	"art": "res://presentation/pip_wear/blue_pottery.gd",
}
