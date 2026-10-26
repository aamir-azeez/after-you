extends RefCounted
## What a pip wears: one item id per slot (content/cosmetics/index.gd SLOTS),
## as a Dictionary {slot: id} holding only the slots that are filled. {} is
## the default look. Pure rules, so a wardrobe, a room's look or a test can
## build one from anything and get the same answer.
##
## from() is the only way in: it keeps one item per known slot, and drops a
## slot it does not know, an id that is unknown, worn in another slot or not
## released (unless asked to keep unreleased ones), and anything not a String.
## digest() is a short stable key for caches (kit/pip_snapshots.gd).
const Catalog = preload("res://services/cosmetic_catalog.gd")

const EMPTY := {}

## A clean outfit from any value. With `unreleased`, items not offered yet are
## kept (the art tools and tests); a player's pip never passes it.
static func from(value: Variant, unreleased: bool = false) -> Dictionary:
	var result: Dictionary = {}
	if not value is Dictionary: return result
	for slot: String in Catalog.slots():
		var id: Variant = value.get(slot)
		if not id is String and not id is StringName: continue
		var key := str(id)
		if Catalog.slot(key) != slot: continue
		if not unreleased and not Catalog.released(key): continue
		result[slot] = key
	return result

## One item, alone in its slot ({} when it can't be worn).
static func of(id: String, unreleased: bool = false) -> Dictionary:
	return from({Catalog.slot(id): id}, unreleased)

static func is_empty(outfit: Dictionary) -> bool:
	return outfit.is_empty()

## The worn ids in slot order.
static func items(outfit: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for slot: String in Catalog.slots():
		if outfit.has(slot): result.append(str(outfit[slot]))
	return result

## A stable key covering every slot: "hat=daisy;body=;leaf=". Equal outfits
## give equal keys, whatever order their entries were made in.
static func digest(outfit: Dictionary) -> String:
	var parts: PackedStringArray = []
	for slot: String in Catalog.slots():
		parts.append("%s=%s" % [slot, str(outfit.get(slot, ""))])
	return ";".join(parts)

## Whether any worn item pulls the pip views back.
static func tall(outfit: Dictionary) -> bool:
	for id: String in items(outfit):
		if Catalog.tall(id): return true
	return false

## The highest leaf lift of the worn items, in metres.
static func leaf_lift(outfit: Dictionary) -> float:
	var lift := 0.0
	for id: String in items(outfit): lift = maxf(lift, Catalog.leaf_lift(id))
	return lift
