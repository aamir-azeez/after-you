extends RefCounted
## Descriptor for the Apple hood cosmetic (the Orchard, bought with Fruits). Fields: content/cosmetics/index.gd.
const PlayerCopy = preload("res://presentation/player_copy.gd")
const DATA := {
	"id": "apple_hood",
	"code": 10,
	"slot": "hat",
	"tier": "fruit_hat",
	"name": PlayerCopy.COSMETIC_APPLE_HOOD,
	"art": "res://presentation/pip_wear/fruit_hood.gd",
	"set": "orchard",
	## Its stem and leaf stand above the head.
	"tall": true,
	## A worn leaf item stands on a short stem out of the hood's top, raised
	## clear of it (the plain leaf hides).
	"leaf_lift": 0.12,
	"leaf_mode": "sits_on_top",
	"leaf_max": "tall",
}
