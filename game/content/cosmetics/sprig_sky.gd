extends RefCounted
## Descriptor for the Sky sprig cosmetic (the Orchard, bought with Fruits). Fields: content/cosmetics/index.gd.
const PlayerCopy = preload("res://presentation/player_copy.gd")
const DATA := {
	"id": "sprig_sky",
	"slot": "leaf",
	"tier": "sprig",
	"name": PlayerCopy.COSMETIC_SPRIG_SKY,
	"art": "res://presentation/pip_wear/sprig.gd",
}
