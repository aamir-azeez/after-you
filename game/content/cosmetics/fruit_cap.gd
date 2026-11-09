extends RefCounted
## Descriptor for the Fruit cap cosmetic (the Orchard, bought with Fruits). Fields: content/cosmetics/index.gd.
const PlayerCopy = preload("res://presentation/player_copy.gd")
const DATA := {
	"id": "fruit_cap",
	"slot": "hat",
	"tier": "fruit_hat",
	"name": PlayerCopy.COSMETIC_FRUIT_CAP,
	"art": "res://presentation/pip_wear/fruit_cap.gd",
	"set": "orchard",
	## Its collar, stem and leaf stand above the head.
	"tall": true,
	## A worn leaf item grows out of the hood's top (the plain leaf hides).
	"leaf_lift": 0.07,
}
