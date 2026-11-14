extends RefCounted
## Descriptor for the Patchwork body skin. Fields: content/cosmetics/index.gd.
const PlayerCopy = preload("res://presentation/player_copy.gd")
const DATA := {
	"id": "patchwork",
	"code": 302,
	"slot": "body",
	"tier": "uncommon",
	"name": PlayerCopy.COSMETIC_PATCHWORK,
	"art": "res://presentation/pip_wear/patchwork.gd",
}
