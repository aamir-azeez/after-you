extends RefCounted
## Descriptor for the Apple leaf cosmetic (the Orchard, bought with Fruits). Fields: content/cosmetics/index.gd.
const PlayerCopy = preload("res://presentation/player_copy.gd")
const DATA := {
	"id": "apple_leaf",
	"slot": "leaf",
	"tier": "fruit_small",
	"name": PlayerCopy.COSMETIC_APPLE_LEAF,
	"art": "res://presentation/pip_wear/apple_leaf.gd",
	"set": "orchard",
}
