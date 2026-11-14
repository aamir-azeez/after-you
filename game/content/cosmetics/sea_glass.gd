extends RefCounted
## Descriptor for the Sea glass body skin. Fields: content/cosmetics/index.gd.
const PlayerCopy = preload("res://presentation/player_copy.gd")
const DATA := {
	"id": "sea_glass",
	"code": 305,
	"slot": "body",
	"tier": "epic",
	"name": PlayerCopy.COSMETIC_SEA_GLASS,
	"art": "res://presentation/pip_wear/sea_glass.gd",
	## Its current drifts slowly (an 8 s loop), so a Wardrobe card shows it live.
	"moving": true,
}
