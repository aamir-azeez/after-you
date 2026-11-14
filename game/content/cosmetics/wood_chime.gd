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
	## Its chime is drawn only in the Wardrobe, standing for the sound.
	"places": ["wardrobe"],
	"sound": "bell_wood_chime",
}
