extends RefCounted
## The one-time packs of each currency (POLLEN-RULES.md "Money", Pollen board 2,
## Fruits board 3): the four Pollen bundles and the four Fruit packs, read from
## content/pollen_bundles.json (schema 3), which the server's own table
## (backend/src/pollen/bundles.json) is pinned to by a backend test. Pure: no
## saves, no nodes. The server alone credits a pack (services/bundle_claims.gd);
## these numbers only describe the cards.
##
## Every function that names no currency means Pollen, as it did before Fruits,
## so the Pollen screens read the same answers they always did.
## - currency: "pollen" or "fruits" per pack (ids(currency) lists one kind);
## - amount: what the pack adds, its bonus included ("21,000", "55");
## - bonus: how much of that is bonus, and its share of the base;
## - the store's own price, read from the RevenueCat offering's package
##   (`price` as the store formats it, `price_micros`, `currency`). A card shows
##   no price it did not get from the store.
## - per store ("play_store", "app_store"): the store's product id and its US
##   price. This phone's store is the App Store on iOS and Google Play anywhere
##   else; each offering ("pollen", "fruits") lists both stores' products, and
##   the SDK gives each phone only its own store's. A Fruit pack sells only while
##   the "fruits" offering has its product (packages), so a pack whose product is
##   not set up yet never shows.
## - first_bonus_percent(currency): the one-time gift on a first pack of that
##   currency, 0 while it is off.
## - display_name: the PlayerCopy name (the Jar shows "Basket" and the Basket
##   "Wheelbarrow"; ids and products never change).
const PlatformSupport = preload("res://services/platform_support.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const PATH := "res://content/pollen_bundles.json"
const PLAY_STORE := "play_store"
const APP_STORE := "app_store"
const POLLEN := "pollen"
const FRUITS := "fruits"
const CURRENCIES: Array[String] = ["pollen", "fruits"]
## The Pollen bundles in store order.
const ORDER: Array[String] = ["pinch", "pouch", "jar", "basket"]
## The Fruit packs in store order.
const FRUIT_ORDER: Array[String] = ["handful", "bowl", "crate", "barrel"]
## The RevenueCat offering that lists the Pollen bundles' packages (never the Full Journey one).
const OFFERING := "pollen"
## The RevenueCat offering that lists the Fruit packs' packages; package ids are the keys.
const FRUITS_OFFERING := "fruits"

static var _table: Dictionary = {}

## The table as kept: {first_bonus_percent: {currency: percent}, bundles: {id: entry}}.
## A pack off the schema is left out; a file that cannot be read keeps none.
static func table() -> Dictionary:
	if _table.is_empty(): _table = checked_table(JSON.parse_string(FileAccess.get_file_as_string(PATH)))
	return _table

## A bundles.json value as kept (tests feed broken ones): each pack needs a known
## currency, whole amounts and both stores' entries; anything else is left out.
static func checked_table(parsed: Variant) -> Dictionary:
	var kept := {"first_bonus_percent": {}, "bundles": {}}
	if not parsed is Dictionary or not parsed.get("bundles") is Dictionary: return kept
	var gifts: Variant = parsed.get("first_bonus_percent")
	for currency: String in CURRENCIES:
		var percent: Variant = gifts.get(currency) if gifts is Dictionary else null
		kept.first_bonus_percent[currency] = clampi(int(percent), 0, 1000) if _whole(percent) else 0
	for id: Variant in parsed.bundles:
		var entry: Variant = parsed.bundles[id]
		if not id is String or not entry is Dictionary or not entry.get("currency") in CURRENCIES: continue
		if not _whole(entry.get("amount")) or int(entry.amount) <= 0 or not _whole(entry.get("bonus")) or int(entry.bonus) < 0 or int(entry.bonus) >= int(entry.amount): continue
		var stores := {}
		for store_name: String in [PLAY_STORE, APP_STORE]:
			var part: Variant = entry.get(store_name)
			if part is Dictionary and part.get("product") is String and _whole(part.get("usd_cents")):
				stores[store_name] = {"product": part.product, "usd_cents": int(part.usd_cents)}
		if stores.size() != 2: continue
		kept.bundles[id] = {"currency": entry.currency, "amount": int(entry.amount), "bonus": int(entry.bonus), PLAY_STORE: stores[PLAY_STORE], APP_STORE: stores[APP_STORE]}
	return kept

static func _whole(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floorf(float(value)) and float(value) >= 0.0

static func _entry(id: String) -> Dictionary:
	var entry: Variant = (table().bundles as Dictionary).get(id, {})
	return entry if entry is Dictionary else {}

## The packs of one currency in store order (Pollen by default).
static func ids(currency: String = POLLEN) -> Array[String]:
	var result: Array[String] = []
	for id: String in ORDER + FRUIT_ORDER:
		if currency_of(id) == currency: result.append(id)
	return result

## The currency a pack adds ("pollen" or "fruits"), or "" for an unknown id.
static func currency_of(id: String) -> String:
	return str(_entry(id).get("currency", ""))

## What a pack adds, its bonus included, in its own currency.
static func amount(id: String) -> int:
	return int(_entry(id).get("amount", 0))

## The Pollen a bundle adds, its bonus included; 0 for a Fruit pack.
static func pollen(id: String) -> int:
	return amount(id) if currency_of(id) == POLLEN else 0

static func bonus(id: String) -> int:
	return int(_entry(id).get("bonus", 0))

## The pack without its bonus ("20,000" for the Pouch, "50" for the Bowl).
static func base(id: String) -> int:
	return amount(id) - bonus(id)

## The bonus as a whole percent of the base (5 for the Pouch, 10 for the Bowl).
static func bonus_percent(id: String) -> int:
	return roundi(100.0 * bonus(id) / base(id)) if base(id) > 0 else 0

## The first pack gift's percent the table ships for a currency (20 for Pollen, 100 for Fruits).
static func first_bonus_percent(currency: String = POLLEN) -> int:
	return int((table().first_bonus_percent as Dictionary).get(currency, 0))

## The pack's PlayerCopy name ("Basket" for the jar), or its id when it has none.
static func display_name(id: String) -> String:
	return str(PlayerCopy.POLLEN_STORE_BUNDLES.get(id, PlayerCopy.FRUIT_PACKS.get(id, id)))

## The store this phone buys from: the App Store on iOS, Google Play anywhere else.
static func store() -> String:
	return APP_STORE if PlatformSupport.is_ios() else PLAY_STORE

static func _in_store(id: String, in_store: String) -> Dictionary:
	var entry: Variant = _entry(id).get(in_store if not in_store.is_empty() else store(), {})
	return entry if entry is Dictionary else {}

## The US price in cents in a store, this phone's by default (99 for the Pinch on Play, 149 on the App Store).
static func usd_cents(id: String, in_store: String = "") -> int:
	return int(_in_store(id, in_store).get("usd_cents", 0))

## The first pack's one-time gift for this pack, at `percent` (0 while it is off).
static func gift(id: String, percent: int) -> int:
	return floori(amount(id) * maxi(percent, 0) / 100.0)

## The first pack gift's percent an offer part gives now: its percent while the
## gift is on and unused, else 0. The Pollen offer is a wardrobe view's `bundles`
## part (services/wardrobe.gd); the Fruit offer is services/fruit_wallet.gd offer(),
## in the same shape.
static func gift_percent(part: Dictionary) -> int:
	return int(part.get("first_gift_percent", 0)) if bool(part.get("first_gift", false)) else 0

## What buying `id` adds now: its amount with its bonus, and the first pack
## gift while `offer` (see gift_percent) holds it.
static func adds(id: String, offer: Dictionary = {}) -> int:
	return amount(id) + gift(id, gift_percent(offer))

## The pack to suggest when the player is `shortfall` short in `currency`: the
## smallest (store order) whose adds() covers it, else the largest. "" when no pack is known.
## `priced`: the packs the store priced (packages()), or null while that is not
## known yet; a pack the store did not price is never named.
static func cover(shortfall: int, offer: Dictionary = {}, currency: String = POLLEN, priced: Variant = null) -> String:
	var known := ids(currency)
	if priced is Dictionary: known = known.filter(func(id: String) -> bool: return (priced as Dictionary).has(id))
	for id: String in known:
		if adds(id, offer) >= shortfall: return id
	return known.back() if not known.is_empty() else ""

## The pack's amount for one unit of the store's currency at `price_micros`, rounded to
## the nearest (5,051 Pollen for the Pinch at $0.99). 0 when the store gave no price.
static func per_unit(id: String, price_micros: int) -> int:
	return roundi(amount(id) * 1000000.0 / price_micros) if price_micros > 0 else 0

## The store product id that sells a pack in a store, this phone's by default
## ("after_you_pollen_pouch" on Play, "after_you_fruits_bowl_ios" on the App Store).
static func product(id: String, in_store: String = "") -> String:
	return str(_in_store(id, in_store).get("product", ""))

## The pack a product id of this phone's store sells ("after_you_pollen_pouch", or with
## its purchase option "after_you_pollen_pouch:buy"), in `currency` (Pollen by default;
## "" for any), or "". Another store's product is "".
static func bundle_for_product(product_id: Variant, in_store: String = "", currency: String = POLLEN) -> String:
	var wanted := str(product_id).get_slice(":", 0) if product_id is String else ""
	if wanted.is_empty(): return ""
	for id: String in ORDER + FRUIT_ORDER:
		if (currency.is_empty() or currency_of(id) == currency) and product(id, in_store) == wanted: return id
	return ""

## The RevenueCat offering that sells a currency's packs.
static func offering(currency: String = POLLEN) -> String:
	return FRUITS_OFFERING if currency == FRUITS else OFFERING

## The packs of `currency` the store sells now, from an offerings payload
## (services/purchases.gd fetch_offerings): {pack id: {offering_id, id, price,
## price_micros, currency}} from that currency's offering only (never the Full
## Journey one). A package with no price, or whose product is not one of this
## store's packs of that currency, is left out.
static func packages(payload: Dictionary, in_store: String = "", currency: String = POLLEN) -> Dictionary:
	var found := {}
	var wanted := offering(currency)
	var offerings: Variant = payload.get("offerings", [])
	if not offerings is Array: return found
	for entry: Variant in offerings:
		if not entry is Dictionary or str(entry.get("id", "")) != wanted or not entry.get("packages") is Array: continue
		for item: Variant in entry.packages:
			if not item is Dictionary or str(item.get("id", "")).is_empty() or str(item.get("price", "")).is_empty(): continue
			var bundle := bundle_for_product(item.get("product_id"), in_store, currency)
			if bundle.is_empty() or found.has(bundle): continue
			found[bundle] = {"offering_id": wanted, "id": str(item.id), "price": str(item.price), "price_micros": int(item.get("price_micros", 0)), "currency": str(item.get("currency", ""))}
	return found
