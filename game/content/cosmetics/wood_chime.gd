extends RefCounted
## Descriptor for the Wood chime (bell sound). Fields: content/cosmetics/index.gd.
const PlayerCopy = preload("res://presentation/player_copy.gd")
const DATA := {
	"id": "wood_chime",
	"code": 322,
	"slot": "bell_sound",
	"tier": "uncommon",
	"name": PlayerCopy.COSMETIC_WOOD_CHIME,
	"art": "res://presentation/pip_wear/wood_chime.gd",
	"sound": "bell_wood_chime",
}
