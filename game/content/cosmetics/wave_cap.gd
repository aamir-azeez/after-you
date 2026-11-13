extends RefCounted
## Descriptor for the Wave cap cosmetic (the Pollen hats and leaves board). Fields: content/cosmetics/index.gd.
const PlayerCopy = preload("res://presentation/player_copy.gd")
const DATA := {
	"id": "wave_cap",
	"slot": "hat",
	"tier": "rare",
	"name": PlayerCopy.COSMETIC_WAVE_CAP,
	"art": "res://presentation/pip_wear/wave_cap.gd",
	"code": 206,
	## Held back until the server's release list names it.
	"released": false,
	## Its waves stand above the head.
	"tall": true,
	## The leaf grows clear beside it.
	"leaf_mode": "pokes_through",
	"leaf_max": "medium",
}
