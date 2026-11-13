extends RefCounted
## Descriptor for the Soft ring (foot ring). Fields: content/cosmetics/index.gd.
const PlayerCopy = preload("res://presentation/player_copy.gd")
const DATA := {
	"id": "soft_ring",
	"code": 321,
	"slot": "foot_ring",
	"tier": "uncommon",
	"name": PlayerCopy.COSMETIC_SOFT_RING,
	"art": "res://presentation/pip_wear/soft_ring.gd",
	## Room and result pages and the Wardrobe only: never in a chapter, where
	## it could be taken for a pad or a target.
	"places": ["stage", "wardrobe"],
}
