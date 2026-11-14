extends RefCounted
## Descriptor for the Pocket pebble (carry). Fields: content/cosmetics/index.gd.
const PlayerCopy = preload("res://presentation/player_copy.gd")
const DATA := {
	"id": "pocket_pebble",
	"code": 320,
	"slot": "carry",
	"tier": "common",
	"name": PlayerCopy.COSMETIC_POCKET_PEBBLE,
	"art": "res://presentation/pip_wear/pocket_pebble.gd",
}
