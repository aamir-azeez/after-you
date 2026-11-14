extends RefCounted
## The wardrobe on this phone: a copy of what the server last said about the
## player's cosmetics (the `wardrobe` part of GET /v1/pollen while the wardrobe
## is on; backend/src/pollen/wardrobe.ts). The server holds what is owned and
## worn and decides what is sold; nothing here grants or prices anything.
##
## Kept per server and player (a scope), in one small file written whole with
## AtomicFile:
## - enabled: the server said the wardrobe is on (its capabilities): owned and
##   earned items, and wearing them;
## - shop: the server said the shop is on too: buying, prices and the name
##   change price;
## - bundles: the server said Pollen bundles sell too (POLLEN_BUNDLES, never
##   without the shop), with the view's `bundles` part: whether the first
##   bundle's gift is still open, its percent, and the money spent on bundles;
## - items, packs: what the player owns (bought, dropped or earned);
## - look, look_revision: what the player wears ({slot: id}) and its revision;
## - offered: what the server releases (sold or earned), which pips may draw,
##   this player's and every friend's; offered_tag: the server's tag of it
##   (capabilities `pollen_offered_tag`, backend/src/pollen/catalog.ts
##   offeredTag) when this read came, so a release reads the wallet again
##   (needs_read) and a friend's new item shows on this phone;
## - offered_packs, prices, pack_price, sets, unlocked: what the server sells,
##   its sets and the Specials whose chapter this player has cleared (only
##   while the shop is on; empty otherwise); prices and sets are in Pollen;
## - fruit_prices, fruit_sets, fruit_set_costs: the Orchard items and sets the
##   server sells for Fruits while FRUITS is on, and what each set with a missing
##   piece costs this player now (empty otherwise). spend_currency and spend_price
##   say which a spend is in, so every screen prices it the same way;
## - name_price: what the next name change costs (0 while one is free, -1
##   while the server sends none, as without the shop);
## - name_price_next: what the change after that one costs, once it went
##   through (-1 from a server that sends none): a free change followed by a
##   paid one is "free this time" (presentation/display_name_prompt.gd).
## - pending: a look the player put on that the server has not confirmed yet
##   ({look, revision, key}), worn on this phone at once (effective_look) and
##   sent by services/wardrobe_client.gd sync, offline or not. Its revision is
##   the phone's clock when it was put on and its key the equip's idempotency
##   key, both fixed then, so every send of it is the same equip. The rule
##   when the server's look changed meanwhile (another phone): the newer intent
##   wins by revision. Once the server's look_revision reaches the pending
##   one's (a wallet read or an equip receipt), the server's look stands and
##   the pending one goes: past it, another phone put a look on later; equal,
##   this one landed. The server applies the same rule (an equip at or under
##   its revision answers its current look), so a pending look put on before
##   the other phone's change never replaces it. A pending look with an item
##   the server says is no longer owned goes too.
##
## Beside the file, in memory only: the server's offered tag and featured item
## code from its last capabilities read (featured_code; services/featured_shelf.gd
## shows it), so a phone that has not reached the server this launch shows
## the built-in shelf.
##
## Every value read from the file or a server reply is checked; anything that
## fails is dropped. A file that cannot be read reads as empty, and the client
## asks the server again (services/wardrobe_client.gd, services/pollen_client.gd).
##
## The active scope is the signed-in player's (scope_source, Main's _names_scope):
## services/own_look.gd reads the look from it, and its offered items tell the
## catalogue what the server releases (services/cosmetic_catalog.gd set_offered).
const AtomicFile = preload("res://services/atomic_file.gd")
const Typed = preload("res://services/typed_values.gd")
const Catalog = preload("res://services/cosmetic_catalog.gd")

const PATH := "user://wardrobe.json"
const VERSION := 1
const ID_PATTERN := "^[a-z0-9_]{1,40}$"
## Ids a list may hold: well past any catalogue the server sends.
const MAX_IDS := 256
const MAX_SET_PIECES := 16
const TAG_PATTERN := "^[a-f0-9]{8}$"
const KEY_PATTERN := "^[a-f0-9]{32}$"

static var _shared: RefCounted = null
static var _id := RegEx.create_from_string(ID_PATTERN)
static var _tag := RegEx.create_from_string(TAG_PATTERN)
static var _key := RegEx.create_from_string(KEY_PATTERN)

var path := PATH
var _scopes: Dictionary = {}
var _active := ""
## Scope key -> the server's offered tag from its last capabilities read (memory only).
var _offered_tags: Dictionary = {}
## Scope key -> the code of the shop's featured item from the last capabilities read (memory only).
var _featured: Dictionary = {}
## () -> {server, owner} of the signed-in player, or {} (Main's _names_scope).
var scope_source: Callable

## Emitted when the active scope's wardrobe changes (a new look, an item, a refresh).
signal changed
## Emitted when a scope's featured item code changes (an open Wardrobe redraws its shelf).
signal featured_changed

static func shared() -> RefCounted:
	if _shared == null: _shared = load("res://services/wardrobe.gd").new()
	return _shared

## Installs a store as the shared one (tests), or clears it with null.
static func use_shared(store: RefCounted) -> void:
	_shared = store

func _init(storage_path: String = PATH) -> void:
	path = storage_path
	_load()

# --- Checks ----------------------------------------------------------------

static func valid_id(value: Variant) -> bool:
	return value is String and _id.search(value) != null

static func _ids(value: Variant) -> Array:
	if not value is Array or value.size() > MAX_IDS: return []
	var kept: Array = []
	for id: Variant in value:
		if valid_id(id) and not id in kept: kept.append(id)
	return kept

## A look as kept: {slot: id} for known slots only, or {} when any part is wrong.
static func checked_look(value: Variant) -> Dictionary:
	if not value is Dictionary or value.size() > Catalog.slots().size(): return {}
	var kept := {}
	for slot: Variant in value:
		if not slot is String or not slot in Catalog.slots() or not valid_id(value[slot]): return {}
		kept[slot] = value[slot]
	return kept

## The reaction slots as kept (backend src/pollen/reaction-loadout.ts): six
## places, each "" or a face id, no face twice; null when off the contract.
## The faces each reaction pack owns (services/reaction_catalog.gd PACKS).
const PACK_FACES := preload("res://services/reaction_catalog.gd").PACKS
const REACTION_SLOT_COUNT := 6
static func checked_slots(value: Variant) -> Variant:
	if not value is Array or (value as Array).size() != REACTION_SLOT_COUNT: return null
	var kept: Array[String] = []
	for face: Variant in value:
		if not face is String or (not (face as String).is_empty() and (not valid_id(face) or face in kept)): return null
		kept.append(face)
	return kept

## The wardrobe part of a wallet answer (GET /v1/pollen while the wardrobe is
## on) as kept, or {} when it is missing or any part is not the contract's.
## The shop's parts and the name price come only while the shop is on: when
## absent they read as nothing sold and no price.
static func checked_view(value: Variant) -> Dictionary:
	if not value is Dictionary or not value.get("wardrobe") is Dictionary: return {}
	var part: Dictionary = value.wardrobe
	if not Typed.whole_number(part.get("look_revision")) or float(part.look_revision) < 0.0: return {}
	var price: Variant = value.get("name_price")
	if price != null and (not Typed.whole_number(price) or float(price) < 0.0): return {}
	# The price after the next change: a value off the contract reads as none, never as a reason to drop the view.
	var after: Variant = value.get("name_price_next")
	var price_next := Typed.as_int(after) if price != null and Typed.whole_number(after) and float(after) >= 0.0 else -1
	for list: String in ["items", "packs", "offered"]:
		if not part.get(list) is Array: return {}
	for list: String in ["offered_packs", "unlocked"]:
		if part.has(list) and not part.get(list) is Array: return {}
	if not part.get("look") is Dictionary or part.has("sets") and not part.get("sets") is Dictionary: return {}
	var look := checked_look(part.look)
	if look.size() != (part.look as Dictionary).size(): return {}
	# The server's prices for what it sells: what a confirm card shows and a spend checks.
	var prices := _checked_prices(part.get("prices", {}))
	var sets := _checked_sets(part.get("sets", {}))
	# The Orchard's prices and sets in Fruits, while FRUITS is on: a part off the contract reads as none.
	var fruit_prices := _checked_prices(part.get("fruit_prices", {}))
	var fruit_sets := _checked_sets(part.get("fruit_sets", {}))
	# What each Orchard set with a missing piece costs this player now (set_cost).
	var fruit_set_costs := _checked_prices(part.get("fruit_set_costs", {}))
	# The face items while FACE_SINGLES is on: owned faces, the slots and how many places are open.
	var faces := {}
	var slots: Variant = checked_slots(part.get("reactions"))
	if part.get("faces") is Array and slots != null and Typed.whole_number(part.get("reaction_slots")):
		faces = {"faces": _ids(part.faces), "reactions": slots, "reaction_slots": clampi(Typed.as_int(part.reaction_slots), 4, REACTION_SLOT_COUNT)}
	return faces.merged({"fruit_prices": fruit_prices, "fruit_sets": fruit_sets, "fruit_set_costs": fruit_set_costs, "items": _ids(part.items), "packs": _ids(part.packs), "look": look, "look_revision": Typed.as_int(part.look_revision),
		"offered": _ids(part.offered), "prices": prices, "offered_packs": _ids(part.get("offered_packs", [])), "pack_price": Typed.as_int(part.get("pack_price"), 0), "sets": sets, "unlocked": _ids(part.get("unlocked", [])),
		"name_price": Typed.as_int(price) if price != null else -1, "name_price_next": price_next, "bundles": checked_bundles(value.get("bundles"))})

## {id: price} for well formed ids and prices above 0; anything else is left out.
static func _checked_prices(sent: Variant) -> Dictionary:
	var prices := {}
	if not sent is Dictionary: return prices
	for id: Variant in sent:
		if valid_id(id) and Typed.whole_number(sent[id]) and float(sent[id]) > 0.0: prices[id] = Typed.as_int(sent[id])
	return prices

## {set id: [piece ids]} for well formed sets; anything else is left out.
static func _checked_sets(sent: Variant) -> Dictionary:
	var sets := {}
	if not sent is Dictionary: return sets
	for set_id: Variant in sent:
		var pieces := _ids(sent[set_id])
		if valid_id(set_id) and not pieces.is_empty() and pieces.size() <= MAX_SET_PIECES: sets[set_id] = pieces
	return sets

## The currency a spend of `id` costs in a kept view: "fruits" for an Orchard
## item or set the server prices in Fruits, else what the item's tier says
## (services/cosmetic_catalog.gd currency), else "pollen".
static func spend_currency(view: Dictionary, id: String) -> String:
	if (view.get("fruit_prices", {}) as Dictionary).has(id) or (view.get("fruit_sets", {}) as Dictionary).has(id): return "fruits"
	if (view.get("prices", {}) as Dictionary).has(id) or (view.get("sets", {}) as Dictionary).has(id): return "pollen"
	return Catalog.currency(id) if Catalog.has(id) else "pollen"

## What an item costs in its own currency (spend_currency), as sale() prices it:
## 0 for an item not sold (an Orchard item the server gives no Fruit price, an
## earned or unknown item), so a tier's Fruit price is never read as Pollen.
static func spend_price(view: Dictionary, id: String) -> int:
	return int(sale(view, id).get("price", 0))

## The pieces of a set, Pollen or Orchard ([] for an unknown set).
static func set_pieces(view: Dictionary, set_id: String) -> Array:
	var pieces: Variant = (view.get("fruit_sets", {}) as Dictionary).get(set_id, (view.get("sets", {}) as Dictionary).get(set_id, []))
	return (pieces as Array).duplicate()

## What the server sells item `id` for in a kept view: {currency, price}, or {}
## when it does not sell it. Every list and card that shows a price asks here,
## so a price is only ever shown in the currency it is charged in: an Orchard
## item (its tier's currency is Fruits, services/cosmetic_catalog.gd currency)
## sells only at its `fruit_prices` price, never at its tier's price; a Pollen
## item at its `prices` price, else its tier's Pollen price (a server that sends
## no prices); an item the server prices in the other currency is not sold.
## Whether it is offered and released is the caller's (wardrobe_flow.gd model).
static func sale(view: Dictionary, id: String) -> Dictionary:
	var fruit_prices: Dictionary = view.get("fruit_prices", {})
	var prices: Dictionary = view.get("prices", {})
	if Catalog.currency(id) == "fruits":
		if not fruit_prices.has(id) or prices.has(id): return {}
		return {"currency": "fruits", "price": int(fruit_prices[id])}
	if fruit_prices.has(id): return {}
	return {"currency": "pollen", "price": int(prices.get(id, Catalog.price(id)))}

## What Orchard set `set_id` costs this player now, as the server said it
## (`fruit_set_costs`, the price the spend checks: the set rule is the server's
## alone): {currency, pieces (the ones `owned` lacks), full (their own prices
## added up, for the struck price), cost}. {} when the server gave no cost (every
## piece owned, an unknown set, a Pollen set, Fruits off) or a piece is not sold
## in Fruits (sale), so no set card shows a price the server did not send.
static func set_cost(view: Dictionary, set_id: String, owned: Array) -> Dictionary:
	var costs: Dictionary = view.get("fruit_set_costs", {})
	var pieces := set_pieces(view, set_id)
	if not costs.has(set_id) or not (view.get("fruit_sets", {}) as Dictionary).has(set_id) or pieces.is_empty(): return {}
	var missing: Array = []
	var full := 0
	for id: String in pieces:
		var sold := sale(view, id)
		if sold.is_empty() or sold.currency != "fruits": return {}
		if id in owned: continue
		missing.append(id)
		full += int(sold.price)
	if missing.is_empty(): return {}
	return {"currency": "fruits", "pieces": missing, "full": full, "cost": int(costs[set_id])}

## The wallet read's bundles part (only while bundles sell) as kept, or {}.
static func checked_bundles(value: Variant) -> Dictionary:
	if not value is Dictionary or not value.get("first_gift") is bool: return {}
	var percent: Variant = value.get("first_gift_percent", 0)
	var spent: Variant = value.get("spent_usd_cents", 0)
	if not Typed.whole_number(percent) or float(percent) < 0.0 or float(percent) > 100.0 or not Typed.whole_number(spent): return {}
	return {"first_gift": value.first_gift and float(percent) > 0.0, "first_gift_percent": Typed.as_int(percent), "spent_usd_cents": Typed.as_int(spent)}

# --- Scopes ----------------------------------------------------------------

static func scope_key(server: String, owner: String) -> String:
	return server.strip_edges().trim_suffix("/") + "|" + owner

func _scope(server: String, owner: String, create: bool = false) -> Dictionary:
	if owner.is_empty() or server.strip_edges().is_empty(): return {}
	var key := scope_key(server, owner)
	if not _scopes.has(key):
		if not create: return {}
		_scopes[key] = {"enabled": false, "shop": false, "bundles": false, "view": {}}
	return _scopes[key]

## Whether the server said the wardrobe is on for this player.
func enabled(server: String, owner: String) -> bool:
	return bool(_scope(server, owner).get("enabled", false))

## Whether the server said the shop is on for this player too (never without the wardrobe).
func shop(server: String, owner: String) -> bool:
	var scope := _scope(server, owner)
	return bool(scope.get("enabled", false)) and bool(scope.get("shop", false))

## Whether the server said Pollen bundles sell for this player (never without the shop).
func bundles(server: String, owner: String) -> bool:
	return shop(server, owner) and bool(_scope(server, owner).get("bundles", false))

## The server's answer: the wardrobe `on`, the shop with it (`shop_on`), and bundles with the shop (`bundles_on`).
func set_enabled(server: String, owner: String, on: bool, shop_on: bool = on, bundles_on: bool = false) -> void:
	var scope := _scope(server, owner, on)
	var selling := on and shop_on
	var bundling := selling and bundles_on
	if scope.is_empty() or bool(scope.enabled) == on and bool(scope.get("shop", false)) == selling and bool(scope.get("bundles", false)) == bundling: return
	scope.enabled = on
	scope.shop = selling
	scope.bundles = bundling
	_save()
	_announce(server, owner)

## The last confirmed wardrobe ({} until the server has said).
func view(server: String, owner: String) -> Dictionary:
	var scope := _scope(server, owner)
	return (scope.view as Dictionary).duplicate(true) if not scope.is_empty() else {}

## The server's tag of what it offers (capabilities `pollen_offered_tag`); anything else is none.
func note_offered_tag(server: String, owner: String, value: Variant) -> void:
	var key := scope_key(server, owner)
	if valid_tag(value): _offered_tags[key] = value
	else: _offered_tags.erase(key)

## The server's featured item (capabilities `pollen_featured_code`): a whole
## number from 1 to the highest item code; anything else, or none, is none.
func note_featured(server: String, owner: String, value: Variant) -> void:
	var key := scope_key(server, owner)
	var code := int(value) if Catalog.valid_code(value) else 0
	if code == int(_featured.get(key, 0)): return
	if code: _featured[key] = code
	else: _featured.erase(key)
	featured_changed.emit()

## The featured item's code from the server this launch, or 0 for none.
func featured_code(server: String, owner: String) -> int:
	return int(_featured.get(scope_key(server, owner), 0))

static func valid_tag(value: Variant) -> bool:
	return value is String and _tag.search(value) != null

## Whether the wallet should be read for the wardrobe: it is on, and nothing is
## kept yet, or what is kept came with another offered tag than the server's
## now (an item was released, or the read is older than tags). A server that
## sends no tag asks for nothing more than an empty view did.
func needs_read(server: String, owner: String) -> bool:
	var scope := _scope(server, owner)
	if scope.is_empty() or not bool(scope.get("enabled", false)): return false
	if (scope.view as Dictionary).is_empty(): return true
	var tag: String = _offered_tags.get(scope_key(server, owner), "")
	return not tag.is_empty() and str(scope.get("offered_tag", "")) != tag

## A wallet answer: keeps its wardrobe part when it has one, with the offered tag it came under.
func note_view(server: String, owner: String, value: Variant) -> bool:
	var kept := checked_view(value)
	var scope := _scope(server, owner, not kept.is_empty())
	if scope.is_empty(): return false
	var tag: String = _offered_tags.get(scope_key(server, owner), "")
	var retagged: bool = not tag.is_empty() and str(scope.get("offered_tag", "")) != tag
	if retagged: scope.offered_tag = tag
	# An answer this build cannot keep (callers pass only answered reads) still
	# counts as read under this tag, so it is not asked for again on every flush.
	if kept.is_empty():
		if retagged: _save()
		return false
	if scope.view != kept:
		scope.view = kept
		_settle_pending(scope)
		_save()
		_announce(server, owner)
	elif _settle_pending(scope):
		_save()
		_announce(server, owner)
	elif retagged: _save()
	return true

## A purchase the server confirmed (POST /v1/pollen/spend): its pieces are owned now.
func note_spend(server: String, owner: String, receipt: Variant) -> bool:
	var scope := _scope(server, owner)
	if scope.is_empty() or (scope.view as Dictionary).is_empty() or not receipt is Dictionary or not Typed.equal(receipt.get("schema_version"), 1): return false
	var pieces := _ids(receipt.get("pieces"))
	if pieces.is_empty(): return false
	var list := "packs" if receipt.get("kind") == "pack" else "items"
	for id: String in pieces:
		if not id in scope.view[list]: scope.view[list].append(id)
	scope.view[list].sort()
	# A face or reaction slot bought: owned and open at once, as the next read will say.
	if scope.view.has("reactions"):
		for id: String in pieces:
			if Catalog.item(id).get("slot") == "reaction" and not id in scope.view.faces: scope.view.faces.append(id)
			# A pack owns its faces.
			for face: String in PACK_FACES.get(id, []):
				if not face in scope.view.faces: scope.view.faces.append(face)
			if Catalog.item(id).get("slot") == "reaction_slot": scope.view.reaction_slots = mini(int(scope.view.reaction_slots) + 1, REACTION_SLOT_COUNT)
	# A set the purchase took a piece of costs something else now: its cost goes until the next read says it.
	var costs: Dictionary = scope.view.get("fruit_set_costs", {})
	for set_id: String in costs.keys():
		if ((scope.view.get("fruit_sets", {}) as Dictionary).get(set_id, []) as Array).any(func(id: String) -> bool: return id in pieces): costs.erase(set_id)
	_save()
	_announce(server, owner)
	return true

## Takes item drops from `drops` (services/pollen_wallet.gd item_dropped) into
## note_drop. Main calls it each time it is built, and each return from a
## chapter builds Main again over the same shared stores, so it connects once.
func follow_drops(drops: Signal) -> void:
	if not drops.is_connected(note_drop): drops.connect(note_drop)

## An item an item bloom dropped, from a confirmed turn receipt: owned now, so
## the wardrobe shows it without reading the wallet again. Nothing before the
## first wardrobe read; that read carries it anyway.
func note_drop(server: String, owner: String, item_id: Variant) -> bool:
	var scope := _scope(server, owner)
	if scope.is_empty() or (scope.view as Dictionary).is_empty() or not valid_id(item_id) or item_id in scope.view.items: return false
	scope.view.items.append(item_id)
	scope.view.items.sort()
	_save()
	_announce(server, owner)
	return true

## A look the server confirmed (POST /v1/pollen/equip). An older revision never replaces a newer one.
func note_look(server: String, owner: String, receipt: Variant) -> bool:
	var scope := _scope(server, owner)
	if scope.is_empty() or (scope.view as Dictionary).is_empty() or not receipt is Dictionary or not Typed.whole_number(receipt.get("revision")): return false
	var look := checked_look(receipt.get("look"))
	if not receipt.get("look") is Dictionary or look.size() != (receipt.look as Dictionary).size(): return false
	if Typed.as_int(receipt.revision) < int(scope.view.look_revision): return false
	scope.view.look = look
	scope.view.look_revision = Typed.as_int(receipt.revision)
	var slots: Variant = checked_slots(receipt.get("reactions"))
	if slots != null and scope.view.has("reactions"): scope.view.reactions = slots
	_settle_pending(scope)
	_save()
	_announce(server, owner)
	return true

# --- A look not confirmed yet ------------------------------------------------

## The look put on and not confirmed yet ({look, revision, key}), or {}.
func pending(server: String, owner: String) -> Dictionary:
	var scope := _scope(server, owner)
	return (scope.get("pending", {}) as Dictionary).duplicate(true) if not scope.is_empty() else {}

## The reaction slots on this phone: the pending ones, else the confirmed
## ones; [] while the server keeps no slots (FACE_SINGLES off or an older server).
func effective_slots(server: String, owner: String) -> Array:
	var scope := _scope(server, owner)
	if scope.is_empty() or not (scope.view as Dictionary).has("reactions"): return []
	if scope.has("pending") and scope.pending.has("reactions"): return (scope.pending.reactions as Array).duplicate()
	return (scope.view.reactions as Array).duplicate()

## What the player wears on this phone: the pending look, else the confirmed one.
func effective_look(server: String, owner: String) -> Dictionary:
	var scope := _scope(server, owner)
	if scope.is_empty(): return {}
	if scope.has("pending"): return (scope.pending.look as Dictionary).duplicate()
	return ((scope.view as Dictionary).get("look", {}) as Dictionary).duplicate()

## Puts `look` on now (worn here at once) as the newest intent: a revision past
## the confirmed and any earlier pending one, and its own key. Only over a
## wardrobe the server has said, with owned items only. The new pending look, or {}.
## While the server keeps reaction slots, every look carries them (`reactions`,
## else the slots shown now), so the server never reads it as an older app's.
func put_on(server: String, owner: String, look: Dictionary, now_ms: int, reactions: Variant = null) -> Dictionary:
	var scope := _scope(server, owner)
	if scope.is_empty() or not bool(scope.get("enabled", false)) or (scope.view as Dictionary).is_empty(): return {}
	var kept := checked_look(look)
	if kept.size() != look.size() or not _owned(scope.view, kept): return {}
	var slots: Variant = null
	if (scope.view as Dictionary).has("reactions"):
		slots = checked_slots(reactions) if reactions != null else effective_slots(server, owner)
		if slots == null: return {}
	var least := int(scope.view.look_revision)
	if scope.has("pending"): least = maxi(least, int(scope.pending.revision))
	scope.pending = {"look": kept, "revision": maxi(now_ms, least + 1), "key": Crypto.new().generate_random_bytes(16).hex_encode()}
	if slots != null: scope.pending.reactions = slots
	_save()
	_announce(server, owner)
	return (scope.pending as Dictionary).duplicate(true)

## An equip answered: the receipt is kept as any look is (note_look), and the
## pending look it answered goes, unless a newer one replaced it meanwhile.
func settle_look(server: String, owner: String, key: String, receipt: Variant) -> bool:
	var noted := note_look(server, owner, receipt)
	var scope := _scope(server, owner)
	if not scope.is_empty() and scope.has("pending") and scope.pending.key == key:
		scope.erase("pending")
		_save()
		_announce(server, owner)
	return noted

## The server refused the pending look with `key` (an item no longer owned, a
## bad revision): it goes, and the confirmed look shows again.
func drop_pending(server: String, owner: String, key: String) -> void:
	var scope := _scope(server, owner)
	if scope.is_empty() or not scope.has("pending") or scope.pending.key != key: return
	scope.erase("pending")
	_save()
	_announce(server, owner)

## The rule above, after the confirmed view changed. True when the pending look went.
static func _settle_pending(scope: Dictionary) -> bool:
	if not scope.has("pending"): return false
	var view: Dictionary = scope.view
	if int(view.get("look_revision", 0)) >= int(scope.pending.revision) or not _owned(view, scope.pending.look):
		scope.erase("pending")
		return true
	return false

static func _owned(view: Dictionary, look: Dictionary) -> bool:
	var items: Array = view.get("items", [])
	for slot: String in look:
		if not look[slot] in items: return false
	return true

## A saved pending look as kept, or {} when any part is wrong.
static func checked_pending(value: Variant) -> Dictionary:
	if not value is Dictionary or not value.get("look") is Dictionary or not Typed.whole_number(value.get("revision")) or float(value.revision) < 1.0: return {}
	if not value.get("key") is String or _key.search(value.key) == null: return {}
	var look := checked_look(value.look)
	if look.size() != (value.look as Dictionary).size(): return {}
	var kept := {"look": look, "revision": Typed.as_int(value.revision), "key": value.key}
	if value.has("reactions"):
		var slots: Variant = checked_slots(value.reactions)
		if slots == null: return {}
		kept.reactions = slots
	return kept

## What the next name change costs, or -1 while the server has not said or the shop is off.
func name_price(server: String, owner: String) -> int:
	var known: Dictionary = view(server, owner)
	return int(known.get("name_price", -1)) if shop(server, owner) and not known.is_empty() else -1

## What the name change after the next one costs, or -1 while the server has not said.
func name_price_next(server: String, owner: String) -> int:
	var known: Dictionary = view(server, owner)
	return int(known.get("name_price_next", -1)) if shop(server, owner) and not known.is_empty() else -1

# --- The signed-in player ---------------------------------------------------

## Follows the signed-in player (scope_source): their offered items tell the
## catalogue what the server releases. Cheap when nothing changed.
## A source whose object is gone (Main, freed while a solo chapter scene runs)
## keeps the last player: they are still signed in, so their pips still wear
## their look and the catalogue still releases their items. A new Main sets a
## new source on its way in.
func follow() -> void:
	if not scope_source.is_null() and not scope_source.is_valid(): return
	var value: Variant = scope_source.call() if scope_source.is_valid() else null
	var key := scope_key(str(value.server), str(value.owner)) if value is Dictionary and not value.is_empty() and value.has("server") and value.has("owner") else ""
	if key == _active: return
	_active = key
	_offer()
	changed.emit()

## What the signed-in player wears ({} for the default look or while the
## wardrobe is off): a look put on and not confirmed yet shows at once, offline too.
func active_look() -> Dictionary:
	follow()
	var scope: Dictionary = _scopes.get(_active, {})
	if scope.is_empty() or not bool(scope.get("enabled", false)): return {}
	if scope.has("pending"): return (scope.pending.look as Dictionary).duplicate()
	return ((scope.view as Dictionary).get("look", {}) as Dictionary).duplicate()

func _announce(server: String, owner: String) -> void:
	follow()
	if scope_key(server, owner) != _active: return
	_offer()
	changed.emit()

func _offer() -> void:
	var scope: Dictionary = _scopes.get(_active, {})
	var on: bool = not scope.is_empty() and bool(scope.get("enabled", false))
	Catalog.set_offered(((scope.view as Dictionary).get("offered", []) as Array) if on else [])

## Forgets everything kept for a player on every server (account deletion).
## False when the file, or a damaged copy of it kept aside, could not be changed (services/deleted_identity_stores.gd tries again).
func clear_owner(owner: String) -> bool:
	for key: String in _scopes.keys():
		if key.get_slice("|", 1) == owner: _scopes.erase(key)
	# Written even when nothing changed: a damaged file read as empty, and the
	# copy of it kept aside (AtomicFile.read_json), hold every player's wardrobe here.
	var saved := _save()
	var removed := AtomicFile.remove_unreadable(path)
	# The catalogue stops releasing what a forgotten active player was offered.
	if not _active.is_empty() and not _scopes.has(_active): _offer()
	return removed and saved

# --- File ------------------------------------------------------------------

func _load() -> void:
	_scopes = {}
	var parsed: Variant = AtomicFile.read_json(path, func(value: Variant) -> bool:
		return value is Dictionary and Typed.equal(value.get("schema_version"), VERSION) and value.get("scopes") is Dictionary)
	if not parsed is Dictionary or not parsed.get("scopes") is Dictionary: return
	for key: Variant in parsed.scopes:
		var value: Variant = parsed.scopes[key]
		if not key is String or not key.contains("|") or not value is Dictionary: continue
		var saved: Variant = value.get("view")
		var price: Variant = saved.get("name_price") if saved is Dictionary and Typed.whole_number(saved.get("name_price")) and float(saved.name_price) >= 0.0 else null
		var kept := checked_view({"wardrobe": saved, "name_price": price, "name_price_next": saved.get("name_price_next") if saved is Dictionary else null, "bundles": saved.get("bundles") if saved is Dictionary else null}) if saved is Dictionary and not saved.is_empty() else {}
		# A file from before the split has no shop key: the shop reads off until the server says again; bundles likewise.
		var selling: bool = value.get("enabled") == true and value.get("shop") == true
		_scopes[key] = {"enabled": value.get("enabled") == true, "shop": selling, "bundles": selling and value.get("bundles") == true, "view": kept}
		if not kept.is_empty() and valid_tag(value.get("offered_tag")): _scopes[key].offered_tag = value.offered_tag
		# A pending look only over a kept wardrobe, and only while the rule still keeps it.
		var waiting := checked_pending(value.get("pending"))
		if not kept.is_empty() and not waiting.is_empty():
			_scopes[key].pending = waiting
			_settle_pending(_scopes[key])

func _save() -> bool:
	return AtomicFile.write_text(path, JSON.stringify({"schema_version": VERSION, "scopes": _scopes}))
