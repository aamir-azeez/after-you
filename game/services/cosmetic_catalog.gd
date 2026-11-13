extends RefCounted
## The pip cosmetics' rules, read from content/cosmetics/index.gd: what each
## item is, what it costs and whether it is offered. Pure: no saves, no
## server, no nodes. What a pip may wear is services/outfit.gd.
const Index = preload("res://content/cosmetics/index.gd")
const INDEX_PATH := "res://content/cosmetics/index.gd"

const EARNED := "earned"

## Every item id in shop order.
static func ids() -> Array[String]:
	return Index.ids()

## The slot ids, in order (content/cosmetics/index.gd SLOTS).
static func slots() -> Array[String]:
	return Index.SLOTS.duplicate()

static func has(id: String) -> bool:
	return not Index.data(id).is_empty()

## The item's descriptor with its optional fields filled in, or {}. Read-only.
static func item(id: String) -> Dictionary:
	return Index.data(id)

## The item's permanent code (content/cosmetics/index.gd "code"), or 0 for an unknown item.
static func code(id: String) -> int:
	var value: Variant = Index.data(id).get("code", 0)
	return value if value is int else 0

## Whether a value (a server reply's number among them, which may come as a
## float) is a whole item code from 1 to content/cosmetics/index.gd CODE_MAX.
static func valid_code(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value)) and float(value) >= 1.0 and float(value) <= float(Index.CODE_MAX)

## The id of the item with this code, or "" for a code this build has no item for.
static func of_code(value: int) -> String:
	return Index.id_of_code(value)

## The slot the item is worn in, or "" for none (unknown or not placed yet).
static func slot(id: String) -> String:
	var value := str(Index.data(id).get("slot", ""))
	return value if value in Index.SLOTS else ""

## Item ids the server's catalogue offers (services/wardrobe.gd sets them from
## the wallet read): the server decides what is released, so an item this
## build knows shows once the server offers it, whatever its shipped flag says.
static var _offered: Dictionary = {}

## Whether the item is released: shipped as released, or offered by the server.
static func released(id: String) -> bool:
	return bool(Index.data(id).get("released", false)) or (_offered.has(id) and has(id))

## Takes the server's offered ids ([] clears them).
static func set_offered(ids: Array) -> void:
	_offered = {}
	for id: Variant in ids:
		if id is String: _offered[id] = true

## The tier name ("common" ... "special", "earned"), or "".
static func tier(id: String) -> String:
	return str(Index.data(id).get("tier", ""))

## The level id a Special waits for, or "".
static func unlock(id: String) -> String:
	return str(Index.data(id).get("unlock", ""))

## The item's PlayerCopy name, or "".
static func display_name(id: String) -> String:
	return str(Index.data(id).get("name", ""))

## Pollen it costs, from its tier: 0 for an earned item or an unknown one.
static func price(id: String) -> int:
	return int(Index.TIER_PRICES.get(str(Index.data(id).get("tier", "")), 0))

## The currency the item is sold in, from its tier: content/cosmetics/index.gd
## TIER_CURRENCY names the Orchard tiers ("fruits"); any tier it does not name
## is "pollen". Read from the script's constant map, so a build whose index has
## no Fruit tiers yet reads every item as Pollen.
static func currency(id: String) -> String:
	if _tier_currency.is_empty(): _tier_currency = {"": (load(INDEX_PATH) as Script).get_script_constant_map().get("TIER_CURRENCY", {})}
	return str((_tier_currency[""] as Dictionary).get(tier(id), "pollen"))

static var _tier_currency: Dictionary = {}

## Whether it can ever be bought with Pollen (earned items never can).
static func sold(id: String) -> bool:
	return has(id) and str(Index.data(id).get("tier", "")) != EARNED and price(id) > 0

## How an earned item is earned (its PlayerCopy line), or "" for one that is sold.
static func earn(id: String) -> String:
	return str(Index.data(id).get("earn", "")) if tier(id) == EARNED else ""

## Released item ids in shop order.
static func released_ids() -> Array[String]:
	var result: Array[String] = []
	for id: String in Index.ids():
		if released(id): result.append(id)
	return result

## Whether wearing it pulls the pip views back.
static func tall(id: String) -> bool:
	return bool(Index.data(id).get("tall", false))

## Whether its look moves on its own (a Wardrobe card shows it live).
static func moving(id: String) -> bool:
	return bool(Index.data(id).get("moving", false))

## Whether wearing it pulls the pip views back further and toward its side.
static func wide(id: String) -> bool:
	return bool(Index.data(id).get("wide", false))

## Whether it lies round the feet (the pip views pull back and look lower).
static func low(id: String) -> bool:
	return bool(Index.data(id).get("low", false))

## Metres the leaf sits higher while it is worn.
static func leaf_lift(id: String) -> float:
	return float(Index.data(id).get("leaf_lift", 0.0))

## The Wardrobe chip a slot is listed under (content/cosmetics/index.gd
## SLOT_CHIPS): the slot itself unless it is grouped.
static func chip(slot_id: String) -> String:
	return str(Index.SLOT_CHIPS.get(slot_id, slot_id))

## The Wardrobe chips in slot order, each once.
static func chips() -> Array[String]:
	var result: Array[String] = []
	for slot_id: String in Index.SLOTS:
		if not chip(slot_id) in result: result.append(chip(slot_id))
	return result

## The places (presentation/pip_outfit.gd PLACES) the item's art shows in,
## or [] for everywhere.
static func places(id: String) -> Array:
	return Index.data(id).get("places", [])

## Whether its art shows on a pip drawn in `place`.
static func shows_in(id: String, place: StringName) -> bool:
	var only := places(id)
	return only.is_empty() or str(place) in only

## A Bell sound item's fixed cue (services/sound_cues.gd), or "".
static func sound(id: String) -> String:
	return str(Index.data(id).get("sound", ""))

## The presentation/pip_wear/ script that dresses a pip in it, or "".
static func art(id: String) -> String:
	return str(Index.data(id).get("art", ""))
