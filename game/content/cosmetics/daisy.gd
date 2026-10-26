extends RefCounted
## Descriptor for the Daisy cosmetic. Fields: content/cosmetics/index.gd.
const PlayerCopy = preload("res://presentation/player_copy.gd")
const DATA := {
	"id": "daisy",
	"slot": "hat",
	"tier": "common",
	"name": PlayerCopy.COSMETIC_DAISY,
	"art": "res://presentation/pip_wear/daisy.gd",
}
