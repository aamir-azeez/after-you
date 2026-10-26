extends RefCounted
## Descriptor for the Lighthouse lamp cosmetic. Fields: content/cosmetics/index.gd.
const PlayerCopy = preload("res://presentation/player_copy.gd")
const DATA := {
	"id": "lighthouse_lamp",
	"slot": "hat",
	"tier": "special",
	"name": PlayerCopy.COSMETIC_LIGHTHOUSE_LAMP,
	"art": "res://presentation/pip_wear/lighthouse_lamp.gd",
	"unlock": "sleeping-lighthouse",
	"tall": true,
}
