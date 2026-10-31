extends RefCounted
## Claims the Pollen bundles the player bought (POST /v1/pollen/bundle-claims,
## backend/src/pollen/bundle-settle.ts). The phone never says what was bought
## or how much it adds: the server reads the player's store purchases from
## RevenueCat itself, credits each one once into its own ledger, and takes back
## refunded ones. So a claim is always safe to send again, in any order.
##
## The store page sets a `pending` mark in a small file before the store's
## sheet opens (mark_pending), so a purchase is never forgotten: not when the app
## is closed during the sheet, nor when the sheet reports a failure for a payment
## that settles later. Only a purchase the player cancelled drops the mark. While
## it is set, the claim goes again on each flush (services/pollen_client.gd calls
## flush() on launch, resume and each capabilities read) until an answer credits
## something, MAX_EMPTY answers credited nothing, or MARK_DAYS have passed.
## Receipts the player has not seen yet stay with it, with the balance their
## answer gave, so the store shows them the next time it opens.
##
## Kept per server and player (a scope) in one file written whole with AtomicFile.
const AtomicFile = preload("res://services/atomic_file.gd")
const Typed = preload("res://services/typed_values.gd")
const Bundles = preload("res://services/pollen_bundles.gd")
const Wardrobe = preload("res://services/wardrobe.gd")
const PollenWallet = preload("res://services/pollen_wallet.gd")
const Presence = preload("res://services/friend_presence.gd")

const PATH := "user://pollen_bundle_claims.json"
const VERSION := 1
const CLAIM_PATH := "/v1/pollen/bundle-claims"
## Receipts kept while unseen; more than this keeps the newest.
const MAX_UNSEEN := 8
## Answers that credit nothing before a waiting claim stops.
const MAX_EMPTY := 12
## As the server's own check (backend/src/pollen/bundle-provider.ts).
const ORDER_PATTERN := "^[A-Za-z0-9._:-]{1,128}$"
## Days a mark keeps asking before it stops.
const MARK_DAYS := 7

## A claim answered: `credited` and `refunded` are what that answer applied.
signal settled(credited: Array, refunded: Array)

static var _shared: RefCounted = null
static var _order := RegEx.create_from_string(ORDER_PATTERN)

var path := PATH
var wardrobe: RefCounted
var wallet: RefCounted
var _api: Node
var _scope_source: Callable
var _transport: Callable
var _scopes: Dictionary = {}
var _sending := false

static func shared() -> RefCounted:
	if _shared == null: _shared = load("res://services/bundle_claims.gd").new()
	return _shared

## Installs a store as the shared one (tests), or clears it with null.
static func use_shared(store: RefCounted) -> void:
	_shared = store

func _init(storage_path: String = PATH, wardrobe_store: RefCounted = null, pollen: RefCounted = null) -> void:
	path = storage_path
	wardrobe = wardrobe_store if wardrobe_store != null else Wardrobe.shared()
	wallet = pollen if pollen != null else PollenWallet.shared()
	_load()

## Where claims go: Main's api and _names_scope, or a test's transport(method, path, body).
func connect_to(api: Node, scope_source: Callable, transport: Callable = Callable()) -> void:
	_api = api
	_scope_source = scope_source
	_transport = transport

## {server, owner} while the server has said bundles sell for the signed-in player, else {}.
func scope() -> Dictionary:
	var value: Variant = _scope_source.call() if _scope_source.is_valid() else null
	if not value is Dictionary or value.is_empty() or not Presence.valid_id(value.get("owner")): return {}
	return value if wardrobe.bundles(str(value.server), str(value.owner)) else {}

func sending() -> bool:
	return _sending

## Whether a claim waits for the signed-in player (and is still young enough to ask).
func pending() -> bool:
	var context := scope()
	if context.is_empty(): return false
	var entry := _entry(context)
	return bool(entry.get("pending", false)) and _now() - int(entry.get("since", 0)) <= MARK_DAYS * 86400

## Sets the mark before a purchase opens the store's sheet. True when this
## call set it (a mark already waiting stays as it is).
func mark_pending() -> bool:
	var context := scope()
	if context.is_empty(): return false
	var entry := _entry(context, true)
	if bool(entry.pending) and pending(): return false
	entry.pending = true
	entry.empty = 0
	entry.since = _now()
	_save()
	return true

## Drops a mark this purchase set (the player cancelled the sheet).
func drop_mark() -> void:
	var context := scope()
	if context.is_empty() or _entry(context).is_empty(): return
	_entry(context).pending = false
	_save()

static func _now() -> int:
	return int(Time.get_unix_time_from_system())

## Marks a claim as waiting (a purchase just went through) and sends it.
## The claim stays waiting until an answer credits something (or MAX_EMPTY answers did not).
## {ok, code, credited, refunded, balance}.
func claim() -> Dictionary:
	var context := scope()
	if context.is_empty(): return {"ok": false, "code": "pollen_bundles_disabled", "credited": [], "refunded": []}
	if not pending(): mark_pending()
	return await _send(context)

## Sends a waiting claim, if any. Safe to call at any time.
func flush() -> void:
	if _sending or not pending(): return
	await _send(scope())

func _send(context: Dictionary) -> Dictionary:
	if _sending: return {"ok": false, "code": "busy", "credited": [], "refunded": []}
	_sending = true
	var response := await _request(HTTPClient.METHOD_POST, CLAIM_PATH, {"schema_version": 1})
	_sending = false
	if scope() != context: return {"ok": false, "code": "identity_changed", "credited": [], "refunded": []}
	var answer := checked_answer(response.get("data")) if response.get("ok", false) else {}
	if answer.is_empty():
		var status := int(response.get("status", 0))
		# Only a refusal of the claim itself is final; anything else (a changed device, a pause) asks again later.
		if status == 400:
			_entry(context, true).pending = false
			_save()
		return {"ok": false, "code": str(response.get("code", "connection_interrupted")), "credited": [], "refunded": []}
	var entry := _entry(context, true)
	# A claim right after a purchase that found nothing new yet stays waiting (RevenueCat may list
	# the purchase a moment later), for at most MAX_EMPTY answers, so a purchase that never lands stops asking.
	entry.empty = int(entry.get("empty", 0)) + 1 if answer.credited.is_empty() and bool(entry.pending) else 0
	entry.pending = bool(entry.pending) and answer.credited.is_empty() and int(entry.empty) < MAX_EMPTY
	for receipt: Dictionary in answer.credited:
		var kept := receipt.duplicate()
		kept.balance = answer.balance
		(entry.unseen as Array).append(kept)
	while (entry.unseen as Array).size() > MAX_UNSEEN: (entry.unseen as Array).pop_front()
	_save()
	wallet.note_balance(context.server, context.owner, answer.balance)
	settled.emit(answer.credited, answer.refunded)
	return {"ok": true, "code": "", "credited": answer.credited, "refunded": answer.refunded, "balance": answer.balance}

## Credited receipts the player has not seen yet, oldest first.
func unseen() -> Array:
	var context := scope()
	return (_entry(context).get("unseen", []) as Array).duplicate(true) if not context.is_empty() else []

## The player saw these receipts.
func mark_seen() -> void:
	var context := scope()
	if context.is_empty(): return
	var entry := _entry(context)
	if entry.is_empty() or (entry.unseen as Array).is_empty(): return
	entry.unseen = []
	_save()

## A claim answer as kept, or {} when any part is not the contract's.
static func checked_answer(value: Variant) -> Dictionary:
	if not value is Dictionary or not Typed.equal(value.get("schema_version"), 1) or not Typed.whole_number(value.get("balance")): return {}
	if not value.get("credited") is Array or not value.get("refunded") is Array or value.credited.size() > 100 or value.refunded.size() > 100: return {}
	# A receipt that fails its check is left out; the balance the server gave still counts.
	var credited: Array = []
	for item: Variant in value.credited:
		var kept := checked_receipt(item)
		if not kept.is_empty(): credited.append(kept)
	var refunded: Array = []
	for item: Variant in value.refunded:
		if not item is Dictionary or not str(item.get("bundle", "")) in Bundles.ids() or not Typed.whole_number(item.get("amount")): continue
		var back := {"bundle": str(item.bundle), "amount": Typed.as_int(item.amount), "order": str(item.get("order", ""))}
		if item.get("store") == Bundles.APP_STORE: back.store = Bundles.APP_STORE
		refunded.append(back)
	return {"balance": Typed.as_int(value.balance), "credited": credited, "refunded": refunded}

## One credited purchase as kept, or {}.
static func checked_receipt(item: Variant) -> Dictionary:
	if not item is Dictionary or not str(item.get("bundle", "")) in Bundles.ids(): return {}
	for field: String in ["pollen", "first_gift", "purchased_at", "usd_cents"]:
		if not Typed.whole_number(item.get(field)) or float(item.get(field)) < 0.0: return {}
	var order: Variant = item.get("order", "")
	if not order is String or (not order.is_empty() and _order.search(order) == null): return {}
	var kept := {"bundle": str(item.bundle), "pollen": Typed.as_int(item.pollen), "first_gift": Typed.as_int(item.first_gift), "order": order,
		"purchased_at": Typed.as_int(item.purchased_at), "usd_cents": Typed.as_int(item.usd_cents)}
	# An App Store purchase names its store, so its receipt says "App Store transaction".
	if item.get("store") == Bundles.APP_STORE: kept.store = Bundles.APP_STORE
	# A kept receipt also has the balance its answer gave.
	if Typed.whole_number(item.get("balance")): kept.balance = Typed.as_int(item.balance)
	return kept

func _entry(context: Dictionary, create: bool = false) -> Dictionary:
	var key := Wardrobe.scope_key(str(context.server), str(context.owner))
	if not _scopes.has(key):
		if not create: return {}
		_scopes[key] = {"pending": false, "empty": 0, "since": 0, "unseen": []}
	return _scopes[key]

func _request(method: int, route: String, body: Dictionary) -> Dictionary:
	var response: Variant
	if _transport.is_valid(): response = await _transport.call(method, route, body)
	elif is_instance_valid(_api): response = await _api.request_json(method, route, body)
	return response if response is Dictionary else {"ok": false, "code": "invalid_response"}

func _load() -> void:
	_scopes = {}
	var text := AtomicFile.read_text(path)
	var json := JSON.new()
	if text.is_empty() or json.parse(text) != OK or not json.data is Dictionary or not Typed.equal(json.data.get("schema_version"), VERSION) or not json.data.get("scopes") is Dictionary: return
	for key: Variant in json.data.scopes:
		var value: Variant = json.data.scopes[key]
		if not key is String or not key.contains("|") or not value is Dictionary: continue
		var unseen: Array = []
		for item: Variant in (value.unseen if value.get("unseen") is Array else []):
			var kept := checked_receipt(item)
			if not kept.is_empty(): unseen.append(kept)
		_scopes[key] = {"pending": value.get("pending") == true, "empty": clampi(Typed.as_int(value.get("empty"), 0), 0, MAX_EMPTY), "since": maxi(0, Typed.as_int(value.get("since"), 0)), "unseen": unseen.slice(-MAX_UNSEEN)}

func _save() -> bool:
	return AtomicFile.write_text(path, JSON.stringify({"schema_version": VERSION, "scopes": _scopes}))
