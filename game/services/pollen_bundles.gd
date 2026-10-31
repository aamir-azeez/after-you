extends RefCounted
## The four one-time Pollen bundles (POLLEN-RULES.md "Money", Pollen board 2):
## what each one adds, read from content/pollen_bundles.json, which the
## server's own table (backend/src/pollen/bundles.json) is pinned to by a
## backend test. Pure: no saves, no nodes. The server alone credits a bundle
## (services/bundle_claims.gd); these numbers only describe the cards.
##
## - pollen: what the bundle adds, its bonus included ("21,000");
## - bonus: how much of that is bonus ("1,000"), and its share of the base (5%);
## - the store's own price, read from the RevenueCat offering's package
##   (`price` as the store formats it, `price_micros`, `currency`). A card shows
##   no price it did not get from the store.
## - per store ("play_store", "app_store"): the store's product id and its US
##   price. This phone's store is the App Store on iOS and Google Play anywhere
##   else; the one "pollen" offering lists both stores' products, and the SDK
##   gives each phone only its own store's.
## - first_bonus_percent: the one-time gift on a first bundle, 0 while it is off.
const PlatformSupport = preload("res://services/platform_support.gd")
const PATH := "res://content/pollen_bundles.json"
const PLAY_STORE := "play_store"
const APP_STORE := "app_store"
const ORDER: Array[String] = ["pinch", "pouch", "jar", "basket"]
## The RevenueCat offering that lists the bundles' packages (never the Full Journey one).
const OFFERING := "pollen"

static var _table: Dictionary = {}

static func table() -> Dictionary:
	if _table.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		_table = parsed if parsed is Dictionary and parsed.get("bundles") is Dictionary else {"first_bonus_percent": 0, "bundles": {}}
	return _table

static func ids() -> Array[String]:
	var result: Array[String] = []
	for id: String in ORDER:
		if (table().bundles as Dictionary).has(id): result.append(id)
	return result

static func pollen(id: String) -> int:
	return int((table().bundles as Dictionary).get(id, {}).get("pollen", 0))

static func bonus(id: String) -> int:
	return int((table().bundles as Dictionary).get(id, {}).get("bonus", 0))

## The bundle without its bonus ("20,000" for the Pouch).
static func base(id: String) -> int:
	return pollen(id) - bonus(id)

## The bonus as a whole percent of the base (5 for the Pouch).
static func bonus_percent(id: String) -> int:
	return roundi(100.0 * bonus(id) / base(id)) if base(id) > 0 else 0

## The store this phone buys from: the App Store on iOS, Google Play anywhere else.
static func store() -> String:
	return APP_STORE if PlatformSupport.is_ios() else PLAY_STORE

static func _in_store(id: String, in_store: String) -> Dictionary:
	var entry: Variant = (table().bundles as Dictionary).get(id, {}).get(in_store if not in_store.is_empty() else store(), {})
	return entry if entry is Dictionary else {}

## The US price in cents in a store, this phone's by default (99 for the Pinch on Play, 149 on the App Store).
static func usd_cents(id: String, in_store: String = "") -> int:
	return int(_in_store(id, in_store).get("usd_cents", 0))

## The first bundle's one-time gift for this bundle, at `percent` (0 while it is off).
static func gift(id: String, percent: int) -> int:
	return floori(pollen(id) * maxi(percent, 0) / 100.0)

## Pollen for one unit of the store's currency at `price_micros`, rounded to the
## nearest (5,051 for the Pinch at $0.99, as the rules write it). 0 when the store gave no price.
static func per_unit(id: String, price_micros: int) -> int:
	return roundi(pollen(id) * 1000000.0 / price_micros) if price_micros > 0 else 0

## The store product id that sells a bundle in a store, this phone's by default
## ("after_you_pollen_pouch" on Play, "after_you_pollen_pouch_ios" on the App Store).
static func product(id: String, in_store: String = "") -> String:
	return str(_in_store(id, in_store).get("product", ""))

## The bundle a product id of this phone's store sells ("after_you_pollen_pouch", or with
## its purchase option "after_you_pollen_pouch:buy"), or "". Another store's product is "".
static func bundle_for_product(product_id: Variant, in_store: String = "") -> String:
	var wanted := str(product_id).get_slice(":", 0) if product_id is String else ""
	if wanted.is_empty(): return ""
	for id: String in ids():
		if product(id, in_store) == wanted: return id
	return ""

## The bundles the store sells now, from an offerings payload (services/purchases.gd
## fetch_offerings): {bundle id: {offering_id, id, price, price_micros, currency}}
## from the Pollen offering only (never the Full Journey one). A package with no
## price is left out.
static func packages(payload: Dictionary, in_store: String = "") -> Dictionary:
	var found := {}
	for entry: Variant in payload.get("offerings", []):
		if not entry is Dictionary or str(entry.get("id", "")) != OFFERING: continue
		for item: Variant in entry.get("packages", []):
			if not item is Dictionary or str(item.get("id", "")).is_empty() or str(item.get("price", "")).is_empty(): continue
			var bundle := bundle_for_product(item.get("product_id"), in_store)
			if bundle.is_empty() or found.has(bundle): continue
			found[bundle] = {"offering_id": OFFERING, "id": str(item.id), "price": str(item.price), "price_micros": int(item.get("price_micros", 0)), "currency": str(item.get("currency", ""))}
	return found
