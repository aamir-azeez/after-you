extends RefCounted
## The player's own pip: its colour and what it wears. Every view of the
## player's own pip (kit/pip_avatar.gd with `own`) asks here, so the wardrobe
## plugs in at this one place. Until the wardrobe exists it is always the
## default look.
const Look = preload("res://presentation/spirit_look.gd")
const Outfit = preload("res://services/outfit.gd")

## The colour the player's own pip is drawn in outside a room.
static func color() -> Color:
	return Look.PEACH

## What the player's own pip wears (services/outfit.gd).
static func outfit() -> Dictionary:
	return Outfit.EMPTY
