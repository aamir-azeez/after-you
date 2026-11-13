extends RefCounted
## Descriptor for the Plum sprig cosmetic (the Orchard, bought with Fruits). Fields: content/cosmetics/index.gd.
const PlayerCopy = preload("res://presentation/player_copy.gd")
const DATA := {
	"id": "sprig_plum",
	"code": 16,
	"slot": "leaf",
	"tier": "sprig",
	"name": PlayerCopy.COSMETIC_SPRIG_PLUM,
	"art": "res://presentation/pip_wear/sprig.gd",
}
