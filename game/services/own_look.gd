extends RefCounted
## The player's own pip: its colour and what it wears. Every view of the
## player's own pip (kit/pip_avatar.gd with `own`) and the player's own slot in
## a room (presentation/slot_looks.gd) asks here, so the wardrobe plugs in at
## this one place. The look is the signed-in player's wardrobe
## (services/wardrobe.gd), cleaned like any outfit; the default look while the
## shop is off or nothing is worn.
const Look = preload("res://presentation/spirit_look.gd")
const Outfit = preload("res://services/outfit.gd")
const Wardrobe = preload("res://services/wardrobe.gd")

## The colour the player's own pip is drawn in outside a room.
static func color() -> Color:
	return Look.PEACH

## What the player's own pip wears (services/outfit.gd).
static func outfit() -> Dictionary:
	return Outfit.from(Wardrobe.shared().active_look())
