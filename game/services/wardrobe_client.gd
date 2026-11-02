extends RefCounted
## Talks to the wardrobe routes (backend/src/pollen/routes.ts) and records each
## answer: the wallet read (GET /v1/pollen, which carries the wardrobe while it
## is on), a look (POST /v1/pollen/equip, POLLEN_WARDROBE) and a purchase (POST
## /v1/pollen/spend, POLLEN_SHOP). Nothing is sent while the server has not said
## the wardrobe is on, and no purchase while it has not said the shop is.
##
## Safe to repeat and to send out of order:
## - every purchase and look carries its own idempotency key, kept for that one
##   action, so a send that got no answer goes again with the same key and the
##   server answers the first receipt (never a second charge);
## - a look also carries a revision (this phone's clock, never below the last
##   one confirmed), so an older look that arrives late never replaces a newer one;
## - a purchase names the cost the confirm sheet showed (`expected_cost`), so a
##   price that changed in between is refused instead of charged;
## - one request at a time: an action asked for while one is out answers "busy".
##
## Wearing works offline (services/wardrobe.gd pending): wear() puts the look on
## this phone at once, with its revision and key fixed then, and sync() sends
## it with the equip call whenever the app reaches the server (now, or from
## Main when the phone is back online and after each Pollen flush). A send
## with no answer keeps it for the next sync; an answer settles it; a refusal
## drops it and reads the wardrobe again. Only the newest look put on is sent:
## a newer one put on while a send is out goes next, in the same sync. Nothing
## is sent while services/connectivity.gd says offline. Buying never queues:
## it needs an answer, so offline it is refused ("offline").
const Wardrobe = preload("res://services/wardrobe.gd")
const PollenWallet = preload("res://services/pollen_wallet.gd")
const Presence = preload("res://services/friend_presence.gd")
const Typed = preload("res://services/typed_values.gd")
const Connectivity = preload("res://services/connectivity.gd")

const WALLET_PATH := "/v1/pollen"
const SPEND_PATH := "/v1/pollen/spend"
const EQUIP_PATH := "/v1/pollen/equip"
## Sends of one action that got no answer before it gives up (the next tap starts a new one).
const MAX_SENDS := 3
## Answers after which the phone reads the wardrobe again, because what it showed was out of date.
const STALE := ["already_owned", "pollen_price_changed", "not_for_sale", "not_owned", "pollen_locked"]

## The wardrobe or the balance changed.
signal changed

var store: RefCounted
var wallet: RefCounted
var _api: Node
## () -> {server, owner} of the signed-in player, or {} (Main's _names_scope).
var _scope: Callable
var _transport: Callable
var _busy := false
## Whether the server is reached (services/connectivity.gd); tests set their own.
var connectivity: RefCounted

## transport(method, path, body) -> response, for tests; else the API's queue.
func _init(api: Node, scope_source: Callable, transport: Callable = Callable(), wardrobe: RefCounted = null, pollen: RefCounted = null) -> void:
	_api = api
	_scope = scope_source
	_transport = transport
	store = wardrobe if wardrobe != null else Wardrobe.shared()
	wallet = pollen if pollen != null else PollenWallet.shared()

## {server, owner} while the server has said the wardrobe is on, else {}.
func scope() -> Dictionary:
	var value: Variant = _scope.call() if _scope.is_valid() else null
	if not value is Dictionary or value.is_empty() or not Presence.valid_id(value.get("owner")): return {}
	return value if store.enabled(str(value.server), str(value.owner)) else {}

func busy() -> bool:
	return _busy

func online() -> bool:
	return (connectivity if connectivity != null else Connectivity.shared()).online()

## Reads the wallet and wardrobe. {ok, code}. A look put on and not sent yet goes after it.
func refresh() -> Dictionary:
	var context := scope()
	if context.is_empty(): return {"ok": false, "code": "pollen_wardrobe_disabled"}
	if _busy: return {"ok": false, "code": "busy"}
	_busy = true
	var response := await _request(HTTPClient.METHOD_GET, WALLET_PATH, {})
	_busy = false
	var answer := _note_wallet(context, response)
	_sync_later()
	return answer

## Buys `id` (kind "item", "set" or "pack") for the cost the player saw. {ok, code, receipt}.
func buy(kind: String, id: String, cost: int) -> Dictionary:
	var context := scope()
	if context.is_empty() or not store.shop(str(context.server), str(context.owner)): return {"ok": false, "code": "pollen_shop_disabled"}
	if not online(): return {"ok": false, "code": "offline"}
	if _busy: return {"ok": false, "code": "busy"}
	_busy = true
	var body := {"schema_version": 1, "idempotency_key": new_key(), "kind": kind, "id": id, "expected_cost": cost}
	var response := await _send(SPEND_PATH, body)
	var answer := _answer(response)
	if answer.ok and scope() == context:
		store.note_spend(context.server, context.owner, answer.receipt)
		wallet.note_balance(context.server, context.owner, answer.receipt.get("balance"))
		changed.emit()
	_busy = false
	if not answer.ok and answer.code in STALE: await refresh()
	else: _sync_later()
	return answer

## Wears `look` ({slot: id}; {} for the default look): on this phone at once,
## offline too, then sent (sync). {ok, code, receipt, pending}: ok once it is
## worn here; `pending` while the server has not confirmed it yet.
func wear(look: Dictionary) -> Dictionary:
	var context := scope()
	if context.is_empty(): return {"ok": false, "code": "pollen_wardrobe_disabled"}
	var put: Dictionary = store.put_on(str(context.server), str(context.owner), look, int(Time.get_unix_time_from_system() * 1000.0))
	if put.is_empty(): return {"ok": false, "code": "not_owned"}
	changed.emit()
	return await sync()

## Sends the look put on and not confirmed yet, if any, while the server is
## reached; the newest one each time round. {ok, code, receipt, pending}.
func sync() -> Dictionary:
	var context := scope()
	if context.is_empty(): return {"ok": false, "code": "pollen_wardrobe_disabled"}
	var server := str(context.server)
	var owner := str(context.owner)
	var waiting := {"ok": true, "code": "", "receipt": {}, "pending": true}
	if store.pending(server, owner).is_empty(): return {"ok": true, "code": "", "receipt": {}}
	# Offline it waits for the next sync; a send already out sends this one next.
	if not online() or _busy: return waiting
	_busy = true
	var answer := waiting
	var stale := false
	while true:
		var put: Dictionary = store.pending(server, owner)
		if put.is_empty() or scope() != context or not online(): break
		var body := {"schema_version": 1, "idempotency_key": put.key, "revision": put.revision, "look": (put.look as Dictionary).duplicate()}
		var response := await _send(EQUIP_PATH, body)
		if scope() != context: break
		answer = _answer(response)
		if answer.ok:
			store.settle_look(server, owner, str(put.key), answer.receipt)
			changed.emit()
			continue
		var status := int(response.get("status", 0))
		if status >= 400 and status < 500:
			# Refused for good (an item no longer owned, a revision off the clock): the confirmed look shows again.
			store.drop_pending(server, owner, str(put.key))
			changed.emit()
			stale = true
		else: answer = waiting
		break
	_busy = false
	if stale: await refresh()
	return answer

## A sync once the current call returns: a look put on while a read or a
## purchase was out goes as soon as the slot is free.
func _sync_later() -> void:
	var context := scope()
	if not context.is_empty() and not store.pending(str(context.server), str(context.owner)).is_empty(): sync.call_deferred()

## A fresh idempotency key: 32 hex characters.
static func new_key() -> String:
	return Crypto.new().generate_random_bytes(16).hex_encode()

## Sends one action, again with the same body and key when no answer came.
func _send(path: String, body: Dictionary) -> Dictionary:
	var response: Dictionary = {}
	for attempt in range(MAX_SENDS):
		# No more tries once the phone reads as offline: the action keeps its key for later.
		if attempt > 0 and not online(): break
		response = await _request(HTTPClient.METHOD_POST, path, body)
		if response.get("ok", false) or int(response.get("status", 0)) > 0 and int(response.get("status", 0)) < 500: break
	return response

static func _answer(response: Dictionary) -> Dictionary:
	var data: Variant = response.get("data")
	if response.get("ok", false) and data is Dictionary and Typed.equal(data.get("schema_version"), 1): return {"ok": true, "code": "", "receipt": data}
	return {"ok": false, "code": str(response.get("code", "connection_interrupted")), "receipt": {}}

func _note_wallet(context: Dictionary, response: Dictionary) -> Dictionary:
	if not response.get("ok", false) or scope() != context: return {"ok": false, "code": str(response.get("code", "connection_interrupted"))}
	var data: Variant = response.get("data")
	var noted: bool = wallet.note_wallet(context.server, context.owner, data)
	noted = store.note_view(context.server, context.owner, data) and noted
	if noted: changed.emit()
	return {"ok": noted, "code": "" if noted else "invalid_response"}

func _request(method: int, path: String, body: Dictionary) -> Dictionary:
	var response: Variant
	if _transport.is_valid(): response = await _transport.call(method, path, body)
	elif is_instance_valid(_api): response = await _api.request_json(method, path, body)
	return response if response is Dictionary else {"ok": false, "code": "invalid_response"}
