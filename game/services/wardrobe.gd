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
## - offered: what the server releases (sold or earned), which pips may draw;
## - offered_packs, prices, pack_price, sets, unlocked: what the server sells,
##   its sets and the Specials whose chapter this player has cleared (only
##   while the shop is on; empty otherwise);
## - name_price: what the next name change costs (0 while one is free, -1
##   while the server sends none, as without the shop);
## - name_price_next: what the change after that one costs, once it went
##   through (-1 from a server that sends none): a free change followed by a
##   paid one is "free this time" (presentation/display_name_prompt.gd).
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

static var _shared: RefCounted = null
static var _id := RegEx.create_from_string(ID_PATTERN)

var path := PATH
var _scopes: Dictionary = {}
var _active := ""
## () -> {server, owner} of the signed-in player, or {} (Main's _names_scope).
var scope_source: Callable

## Emitted when the active scope's wardrobe changes (a new look, an item, a refresh).
signal changed

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
	var prices := {}
	var sent: Variant = part.get("prices", {})
	if sent is Dictionary:
		for id: Variant in sent:
			if valid_id(id) and Typed.whole_number(sent[id]) and float(sent[id]) > 0.0: prices[id] = Typed.as_int(sent[id])
	var sets := {}
	var sent_sets: Dictionary = part.get("sets", {})
	for set_id: Variant in sent_sets:
		var pieces := _ids(sent_sets[set_id])
		if valid_id(set_id) and not pieces.is_empty() and pieces.size() <= MAX_SET_PIECES: sets[set_id] = pieces
	return {"items": _ids(part.items), "packs": _ids(part.packs), "look": look, "look_revision": Typed.as_int(part.look_revision),
		"offered": _ids(part.offered), "prices": prices, "offered_packs": _ids(part.get("offered_packs", [])), "pack_price": Typed.as_int(part.get("pack_price"), 0), "sets": sets, "unlocked": _ids(part.get("unlocked", [])),
		"name_price": Typed.as_int(price) if price != null else -1, "name_price_next": price_next, "bundles": checked_bundles(value.get("bundles"))}

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

## A wallet answer: keeps its wardrobe part when it has one.
func note_view(server: String, owner: String, value: Variant) -> bool:
	var kept := checked_view(value)
	var scope := _scope(server, owner, not kept.is_empty())
	if kept.is_empty() or scope.is_empty(): return false
	if scope.view != kept:
		scope.view = kept
		_save()
		_announce(server, owner)
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
	_save()
	_announce(server, owner)
	return true

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
	_save()
	_announce(server, owner)
	return true

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
func follow() -> void:
	var value: Variant = scope_source.call() if scope_source.is_valid() else null
	var key := scope_key(str(value.server), str(value.owner)) if value is Dictionary and not value.is_empty() and value.has("server") and value.has("owner") else ""
	if key == _active: return
	_active = key
	_offer()
	changed.emit()

## What the signed-in player wears ({} for the default look or while the shop is off).
func active_look() -> Dictionary:
	follow()
	var scope: Dictionary = _scopes.get(_active, {})
	if scope.is_empty() or not bool(scope.get("enabled", false)): return {}
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

# --- File ------------------------------------------------------------------

func _load() -> void:
	_scopes = {}
	var parsed: Variant = _parsed(AtomicFile.read_text(path, func(text: String) -> bool:
		var value: Variant = _parsed(text)
		return value is Dictionary and Typed.equal(value.get("schema_version"), VERSION) and value.get("scopes") is Dictionary))
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

## JSON text as a value, or null, without logging an error for a missing or damaged file.
static func _parsed(text: String) -> Variant:
	var json := JSON.new()
	return json.data if not text.is_empty() and json.parse(text) == OK else null

func _save() -> bool:
	return AtomicFile.write_text(path, JSON.stringify({"schema_version": VERSION, "scopes": _scopes}))
