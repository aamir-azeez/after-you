extends RefCounted
## Descriptor for the Night sky body skin. Fields: content/cosmetics/index.gd.
const PlayerCopy = preload("res://presentation/player_copy.gd")
const DATA := {
	"id": "night_sky",
	"code": 301,
	"slot": "body",
	"tier": "epic",
	"name": PlayerCopy.COSMETIC_NIGHT_SKY,
	"art": "res://presentation/pip_wear/night_sky.gd",
	## Its stars drift slowly (an 8 s loop), so a Wardrobe card shows it live.
	"moving": true,
}
