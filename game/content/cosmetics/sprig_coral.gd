extends RefCounted
## Descriptor for the Coral sprig cosmetic (the Orchard, bought with Fruits). Fields: content/cosmetics/index.gd.
const PlayerCopy = preload("res://presentation/player_copy.gd")
const DATA := {
	"id": "sprig_coral",
	"slot": "leaf",
	"tier": "sprig",
	"name": PlayerCopy.COSMETIC_SPRIG_CORAL,
	"art": "res://presentation/pip_wear/sprig.gd",
}
