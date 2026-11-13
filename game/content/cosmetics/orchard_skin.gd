extends RefCounted
## Descriptor for the Orchard skin cosmetic (the Orchard, bought with Fruits). Fields: content/cosmetics/index.gd.
const PlayerCopy = preload("res://presentation/player_copy.gd")
const DATA := {
	"id": "orchard_skin",
	"code": 13,
	"slot": "body",
	"tier": "fruit_body",
	"name": PlayerCopy.COSMETIC_ORCHARD_SKIN,
	"art": "res://presentation/pip_wear/orchard_skin.gd",
	"set": "orchard",
	"moving": true,
}
