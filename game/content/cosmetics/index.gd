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
##   "code":  the item's permanent number, a whole number from 1 to CODE_MAX,
##            one per item. The server's CONFIG names items by it (the release
##            list and the featured item, backend/src/pollen/catalog.ts), so it
##            never changes and is never given to another item, even one that
##            was retired. tests/fixtures/cosmetic_codes.json pins every code
##            ever given (test_cosmetic_catalog and the backend's tests check
##            it): a new item adds its line there, and no line is changed or
##            removed. When a block first ships, its codes are also copied into
##            SHIPPED in tests/test_cosmetic_catalog.gd, whose lines never
##            change. Blocks so far: 1 to 99 the first catalogue (1 to 18,
##            in ITEMS order), 200 to 299 the hats batch, 300 to 399 the
##            skins batch. A new item ships "released": false here and in the
##            server's catalog.json, which gives it the same code, and the
##            server releases it by listing the code in CONFIG.
##   "slot":  a row of SLOTS, or "" while the owner has not placed it (it can
##            not be worn then)
##   "tier":  a row of TIER_PRICES
##   "name":  a PlayerCopy constant
##   "art":   the presentation/pip_wear/ script that dresses a pip in it, or ""
##            while its art is not made (it draws nothing then)
## Optional fields, with the value a descriptor gets when it leaves one out:
const OPTIONAL := {
	## true: built as released, drawn on pips whatever the server says. false
	## (every item so far) keeps the item out of every pip and every list until
	## the server offers it (the wallet read's `offered`, which follows the
	## server's catalog.json and its CONFIG release list by code).
	"released": false,
	## The level id (any version) a player must clear before a Special can be
	## bought, or "".
	"unlock": "",
	## true: the Settings, name page and chip views pull back a little so the
	## item stays in frame.
	"tall": false,
	## true: the item hangs out past the head on the side the three-quarter
	## views turn away, so those views pull back further and look a little
	## toward it (presentation/kit/pip_stage.gd).
	"wide": false,
	## Metres the leaf sits higher while the item is worn (it pokes up through
	## a hat's brim).
	"leaf_lift": 0.0,
	## true: its look moves on its own (the Orchard skin's falling petals), so
	## a Wardrobe item card showing it draws a live pip at the idle card rate
	## instead of a still picture (kit/pip_avatar.gd animate_moving).
	"moving": false,
	## The set the item belongs to (lower case letters, digits and "_"), or "".
	## Buying a set's missing pieces together costs less
	## (backend/src/pollen/spend.ts).
	"set": "",
	## How an earned item is earned, a PlayerCopy constant: the Wardrobe shows
	## it under a picked earned item the player does not own. "" for an item
	## that is sold.
	"earn": "",
	## The places its art shows in (presentation/pip_outfit.gd PLACES: "world",
	## "studio", "stage", "wardrobe"), or [] for everywhere: a foot ring only on
	## room and result pages and in the Wardrobe.
	"places": [],
	## A Bell sound item: the fixed cue (services/sound_cues.gd CUES) the
	## player's result screen plays once, or "".
	"sound": "",
}
const REQUIRED := ["id", "code", "slot", "tier", "name", "art"]
## The highest item code (backend/src/config.ts COSMETIC_CODE_MAX).
const CODE_MAX := 999

## The places on a pip, one item each, in the order they are listed and dressed.
## "trail": marks left on the floor while walking (presentation/kit/trail_kit.gd).
## The little extras: "carry" (a small thing held at the side), "foot_ring" (a
## ring under the feet on room and result screens) and "bell_sound" (a result
## screen sound).
const SLOTS: Array[String] = ["hat", "body", "leaf", "trail", "carry", "foot_ring", "bell_sound"]
## Slots the Wardrobe lists under one chip: slot -> chip. A slot left out is
## its own chip.
const SLOT_CHIPS := {"carry": "extras", "foot_ring": "extras", "bell_sound": "extras"}
## The price per tier, in the tier's currency (TIER_CURRENCY). 0: earned
## only, never sold.
const TIER_PRICES := {
	"common": 1000,
	"uncommon": 5000,
	"rare": 20000,
	"epic": 50000,
	"special": 100000,
	"earned": 0,
	# The Orchard, bought with Fruits (backend catalog.json tier_currency).
	"sprig": 20,
	"fruit_small": 50,
	"fruit_hat": 100,
	"fruit_body": 200,
}
## The currency each tier is sold in, for the tiers not sold with Pollen: a
## tier left out of this list is "pollen". The server's catalogue names the
## same currencies, so a price is always read in the currency it was set in.
const TIER_CURRENCY := {"sprig": "fruits", "fruit_small": "fruits", "fruit_hat": "fruits", "fruit_body": "fruits"}

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
	# The Orchard (Fruits).
	preload("res://content/cosmetics/apple_hood.gd"),
	preload("res://content/cosmetics/blueberry_hood.gd"),
	preload("res://content/cosmetics/blossom_crown.gd"),
	preload("res://content/cosmetics/orchard_skin.gd"),
	preload("res://content/cosmetics/apple_leaf.gd"),
	preload("res://content/cosmetics/sprig_coral.gd"),
	preload("res://content/cosmetics/sprig_plum.gd"),
	preload("res://content/cosmetics/sprig_sun.gd"),
	preload("res://content/cosmetics/sprig_sky.gd"),
	# Pollen skins, trails and little extras (board 2026-11-12).
	preload("res://content/cosmetics/knit.gd"),
	preload("res://content/cosmetics/night_sky.gd"),
	preload("res://content/cosmetics/patchwork.gd"),
	preload("res://content/cosmetics/blue_pottery.gd"),
	preload("res://content/cosmetics/autumn.gd"),
	preload("res://content/cosmetics/sea_glass.gd"),
	preload("res://content/cosmetics/leaves.gd"),
	preload("res://content/cosmetics/seed_fluff.gd"),
	preload("res://content/cosmetics/rain_drops.gd"),
	preload("res://content/cosmetics/soft_stars.gd"),
	preload("res://content/cosmetics/snow_steps.gd"),
	preload("res://content/cosmetics/little_tune.gd"),
	preload("res://content/cosmetics/pocket_pebble.gd"),
	preload("res://content/cosmetics/soft_ring.gd"),
	preload("res://content/cosmetics/wood_chime.gd"),
]

## Worked out once when this file loads, then only read.
static var _ids: Array[String] = _ordered_ids()
static var _data: Dictionary = _by_id()
static var _codes: Dictionary = _by_code()

## Every item id in order. A copy: callers may change it.
static func ids() -> Array[String]:
	return _ids.duplicate()

## One item's descriptor with every optional field filled in, or {} if there
## is no such item. Read-only.
static func data(id: String) -> Dictionary:
	return _data.get(id, {})

## The id of the item with this code, or "" when no item has it.
static func id_of_code(code: int) -> String:
	return _codes.get(code, "")

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

static func _by_code() -> Dictionary:
	var result: Dictionary = {}
	for file: Script in ITEMS:
		var code: Variant = file.DATA.get("code")
		if not code is int: continue
		assert(not result.has(code), "Two cosmetic descriptors share the code %d" % code)
		result[code] = str(file.DATA.get("id", ""))
	result.make_read_only()
	return result
