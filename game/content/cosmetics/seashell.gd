extends RefCounted
## Descriptor for the Seashell cosmetic. Fields: content/cosmetics/index.gd.
const PlayerCopy = preload("res://presentation/player_copy.gd")
const DATA := {
	"id": "seashell",
	"code": 2,
	"slot": "hat",
	"tier": "common",
	"name": PlayerCopy.COSMETIC_SEASHELL,
	"art": "res://presentation/pip_wear/seashell.gd",
	## The leaf grows clear beside it.
	"leaf_mode": "pokes_through",
	"leaf_max": "tall",
}
