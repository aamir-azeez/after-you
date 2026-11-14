extends RefCounted
## Descriptor for the Knit body skin. Fields: content/cosmetics/index.gd.
const PlayerCopy = preload("res://presentation/player_copy.gd")
const DATA := {
	"id": "knit",
	"code": 300,
	"slot": "body",
	"tier": "uncommon",
	"name": PlayerCopy.COSMETIC_KNIT,
	"art": "res://presentation/pip_wear/knit.gd",
}
