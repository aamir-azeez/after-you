extends RefCounted
## The pip cosmetics' rules, read from content/cosmetics/index.gd: what each
## item is, what it costs and whether it is offered. Pure: no saves, no
## server, no nodes. What a pip may wear is services/outfit.gd.
const Index = preload("res://content/cosmetics/index.gd")

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

## Whether it can ever be bought with Pollen (earned items never can).
static func sold(id: String) -> bool:
	return has(id) and str(Index.data(id).get("tier", "")) != EARNED and price(id) > 0

## Released item ids in shop order.
static func released_ids() -> Array[String]:
	var result: Array[String] = []
	for id: String in Index.ids():
		if released(id): result.append(id)
	return result

## Whether wearing it pulls the pip views back.
static func tall(id: String) -> bool:
	return bool(Index.data(id).get("tall", false))

## Metres the leaf sits higher while it is worn.
static func leaf_lift(id: String) -> float:
	return float(Index.data(id).get("leaf_lift", 0.0))

## The presentation/pip_wear/ script that dresses a pip in it, or "".
static func art(id: String) -> String:
	return str(Index.data(id).get("art", ""))
