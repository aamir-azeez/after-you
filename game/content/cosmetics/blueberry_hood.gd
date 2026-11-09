extends RefCounted
## Descriptor for the Blueberry hood cosmetic (the Orchard, bought with Fruits). Fields: content/cosmetics/index.gd.
const PlayerCopy = preload("res://presentation/player_copy.gd")
const DATA := {
	"id": "blueberry_hood",
	"slot": "hat",
	"tier": "fruit_hat",
	"name": PlayerCopy.COSMETIC_BLUEBERRY_HOOD,
	"art": "res://presentation/pip_wear/fruit_hood.gd",
	## Its star crown stands above the head.
	"tall": true,
	## A worn leaf item grows out of the hood's top (the plain leaf hides).
	"leaf_lift": 0.05,
}
