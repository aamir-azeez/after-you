extends RefCounted
## Every pip cosmetic, in shop order: one descriptor file per item in this
## folder, the same pattern as content/chapters/index.gd. The rules that read
## it are services/cosmetic_catalog.gd (prices, what is offered) and
## services/outfit.gd (what a pip may wear).
##
## A descriptor declares `const DATA := {...}`. Pure data: the art is a script
## path string, and the only preload allowed is
## res://presentation/player_copy.gd, so a name is referenced, never repeated.
## No descriptor stores a price: its tier does (TIER_PRICES).
## Required fields:
##   "id":    the item's id, lower case letters, digits and "_"; never changes
##            once released, because wardrobes and rooms will store it
##   "slot":  a row of SLOTS, or "" while the owner has not placed it (it can
##            not be worn then)
##   "tier":  a row of TIER_PRICES
##   "name":  a PlayerCopy constant
##   "art":   the presentation/pip_wear/ script that dresses a pip in it, or ""
##            while its art is not made (it draws nothing then)
## Optional fields, with the value a descriptor gets when it leaves one out:
const OPTIONAL := {
	## false keeps the item out of every pip and every list: only the default
	## look shows until the item is offered.
	"released": false,
	## The level id (any version) a player must clear before a Special can be
	## bought, or "".
	"unlock": "",
	## true: the Settings, name page and chip views pull back a little so the
	## item stays in frame.
	"tall": false,
	## Metres the leaf sits higher while the item is worn (it pokes up through
	## a hat's brim).
	"leaf_lift": 0.0,
	## The set the item belongs to (lower case letters, digits and "_"), or "".
	## Buying a set's missing pieces together costs less
	## (backend/src/pollen/spend.ts).
	"set": "",
}
const REQUIRED := ["id", "slot", "tier", "name", "art"]

## The places on a pip, one item each, in the order they are listed and dressed.
const SLOTS: Array[String] = ["hat", "body", "leaf"]
## Pollen per tier. 0: earned only, never sold.
const TIER_PRICES := {
	"common": 1000,
	"uncommon": 5000,
	"rare": 20000,
	"epic": 50000,
	"special": 100000,
	"earned": 0,
}

const ITEMS := [
	preload("res://content/cosmetics/daisy.gd"),
	preload("res://content/cosmetics/seashell.gd"),
	preload("res://content/cosmetics/straw_hat.gd"),
	preload("res://content/cosmetics/tide.gd"),
	preload("res://content/cosmetics/lantern.gd"),
	preload("res://content/cosmetics/lighthouse_lamp.gd"),
	preload("res://content/cosmetics/gold_leaf.gd"),
	preload("res://content/cosmetics/every_hard.gd"),
	preload("res://content/cosmetics/top_ten_ribbon.gd"),
]

## Worked out once when this file loads, then only read.
static var _ids: Array[String] = _ordered_ids()
static var _data: Dictionary = _by_id()

## Every item id in order. A copy: callers may change it.
static func ids() -> Array[String]:
	return _ids.duplicate()

## One item's descriptor with every optional field filled in, or {} if there
## is no such item. Read-only.
static func data(id: String) -> Dictionary:
	return _data.get(id, {})

static func _ordered_ids() -> Array[String]:
	var result: Array[String] = []
	for file: Script in ITEMS: result.append(str(file.DATA.get("id", "")))
	result.make_read_only()
	return result

static func _by_id() -> Dictionary:
	var result: Dictionary = {}
	for file: Script in ITEMS:
		var data: Dictionary = OPTIONAL.duplicate(true)
		data.merge(file.DATA, true)
		assert(not result.has(data.get("id")), "Two cosmetic descriptors share the id %s" % data.get("id"))
		data.make_read_only()
		result[str(data.get("id", ""))] = data
	result.make_read_only()
	return result
