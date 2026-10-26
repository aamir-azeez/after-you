extends RefCounted
## Descriptor for the Seashell cosmetic. Fields: content/cosmetics/index.gd.
const PlayerCopy = preload("res://presentation/player_copy.gd")
const DATA := {
	"id": "seashell",
	"slot": "hat",
	"tier": "common",
	"name": PlayerCopy.COSMETIC_SEASHELL,
	"art": "res://presentation/pip_wear/seashell.gd",
}
