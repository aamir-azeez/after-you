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
## - first_bonus_percent: the one-time gift on a first bundle, 0 while it is off.
const PATH := "res://content/pollen_bundles.json"
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

## The US price in cents, the rules' figure (99 for the Pinch).
static func usd_cents(id: String) -> int:
	return int((table().bundles as Dictionary).get(id, {}).get("usd_cents", 0))

## The first bundle's one-time gift for this bundle, at `percent` (0 while it is off).
static func gift(id: String, percent: int) -> int:
	return floori(pollen(id) * maxi(percent, 0) / 100.0)

## Pollen for one unit of the store's currency at `price_micros`, rounded to the
## nearest (5,051 for the Pinch at $0.99, as the rules write it). 0 when the store gave no price.
static func per_unit(id: String, price_micros: int) -> int:
	return roundi(pollen(id) * 1000000.0 / price_micros) if price_micros > 0 else 0

## The Google Play product id that sells a bundle ("after_you_pollen_pouch"), from the table.
static func play_product(id: String) -> String:
	return str((table().bundles as Dictionary).get(id, {}).get("play_product", ""))

## The bundle a store product id sells ("after_you_pollen_pouch", or with its purchase option
## "after_you_pollen_pouch:buy"), or "".
static func bundle_for_product(product_id: Variant) -> String:
	var product := str(product_id).get_slice(":", 0) if product_id is String else ""
	if product.is_empty(): return ""
	for id: String in ids():
		if play_product(id) == product: return id
	return ""

## The bundles the store sells now, from an offerings payload (services/purchases.gd
## fetch_offerings): {bundle id: {offering_id, id, price, price_micros, currency}}
## from the Pollen offering only (never the Full Journey one). A package with no
## price is left out.
static func packages(payload: Dictionary) -> Dictionary:
	var found := {}
	for entry: Variant in payload.get("offerings", []):
		if not entry is Dictionary or str(entry.get("id", "")) != OFFERING: continue
		for item: Variant in entry.get("packages", []):
			if not item is Dictionary or str(item.get("id", "")).is_empty() or str(item.get("price", "")).is_empty(): continue
			var bundle := bundle_for_product(item.get("product_id"))
			if bundle.is_empty() or found.has(bundle): continue
			found[bundle] = {"offering_id": OFFERING, "id": str(item.id), "price": str(item.price), "price_micros": int(item.get("price_micros", 0)), "currency": str(item.get("currency", ""))}
	return found
