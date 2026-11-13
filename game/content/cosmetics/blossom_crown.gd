extends RefCounted
## Descriptor for the Blossom crown cosmetic (the Orchard, bought with Fruits). Fields: content/cosmetics/index.gd.
const PlayerCopy = preload("res://presentation/player_copy.gd")
const DATA := {
	"id": "blossom_crown",
	"code": 12,
	"slot": "hat",
	"tier": "fruit_hat",
	"name": PlayerCopy.COSMETIC_BLOSSOM_CROWN,
	"art": "res://presentation/pip_wear/blossom_crown.gd",
}
