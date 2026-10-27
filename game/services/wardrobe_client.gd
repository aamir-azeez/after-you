extends RefCounted
## Talks to the wardrobe routes (backend/src/pollen/routes.ts, POLLEN_SHOP) and
## records each answer: the wallet read (GET /v1/pollen, which carries the
## wardrobe while the shop is on), a purchase (POST /v1/pollen/spend) and a
## look (POST /v1/pollen/equip). Nothing is sent while the server has not said
## the shop is on.
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
const Wardrobe = preload("res://services/wardrobe.gd")
const PollenWallet = preload("res://services/pollen_wallet.gd")
const Presence = preload("res://services/friend_presence.gd")
const Typed = preload("res://services/typed_values.gd")

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

## transport(method, path, body) -> response, for tests; else the API's queue.
func _init(api: Node, scope_source: Callable, transport: Callable = Callable(), wardrobe: RefCounted = null, pollen: RefCounted = null) -> void:
	_api = api
	_scope = scope_source
	_transport = transport
	store = wardrobe if wardrobe != null else Wardrobe.shared()
	wallet = pollen if pollen != null else PollenWallet.shared()

## {server, owner} while the server has said the shop is on, else {}.
func scope() -> Dictionary:
	var value: Variant = _scope.call() if _scope.is_valid() else null
	if not value is Dictionary or value.is_empty() or not Presence.valid_id(value.get("owner")): return {}
	return value if store.enabled(str(value.server), str(value.owner)) else {}

func busy() -> bool:
	return _busy

## Reads the wallet and wardrobe. {ok, code}.
func refresh() -> Dictionary:
	var context := scope()
	if context.is_empty(): return {"ok": false, "code": "pollen_shop_disabled"}
	if _busy: return {"ok": false, "code": "busy"}
	_busy = true
	var response := await _request(HTTPClient.METHOD_GET, WALLET_PATH, {})
	_busy = false
	return _note_wallet(context, response)

## Buys `id` (kind "item", "set" or "pack") for the cost the player saw. {ok, code, receipt}.
func buy(kind: String, id: String, cost: int) -> Dictionary:
	var context := scope()
	if context.is_empty(): return {"ok": false, "code": "pollen_shop_disabled"}
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
	return answer

## Wears `look` ({slot: id}; {} for the default look). {ok, code, receipt}.
func wear(look: Dictionary) -> Dictionary:
	var context := scope()
	if context.is_empty(): return {"ok": false, "code": "pollen_shop_disabled"}
	if _busy: return {"ok": false, "code": "busy"}
	_busy = true
	var known: Dictionary = store.view(context.server, context.owner)
	var revision := maxi(int(Time.get_unix_time_from_system() * 1000.0), int(known.get("look_revision", 0)) + 1)
	var body := {"schema_version": 1, "idempotency_key": new_key(), "revision": revision, "look": look.duplicate()}
	var response := await _send(EQUIP_PATH, body)
	var answer := _answer(response)
	if answer.ok and scope() == context:
		store.note_look(context.server, context.owner, answer.receipt)
		changed.emit()
	_busy = false
	if not answer.ok and answer.code in STALE: await refresh()
	return answer

## A fresh idempotency key: 32 hex characters.
static func new_key() -> String:
	return Crypto.new().generate_random_bytes(16).hex_encode()

## Sends one action, again with the same body and key when no answer came.
func _send(path: String, body: Dictionary) -> Dictionary:
	var response: Dictionary = {}
	for _attempt in range(MAX_SENDS):
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
