extends RefCounted
## Talks to the wardrobe routes (backend/src/pollen/routes.ts) and records each
## answer: the wallet read (GET /v1/pollen, which carries the wardrobe while it
## is on and the monthly grant, services/pollen_grant.gd, while that pays), a
## look (POST /v1/pollen/equip, POLLEN_WARDROBE) and a purchase (POST
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
## Fruits (services/fruit_wallet.gd) are spent on the same route the same way:
## an Orchard item or set through buy() with its cost in Fruits, Fruits into
## Pollen through convert() and Sunshine through buy_sunshine(), each with its
## own key, its retries and its refusals as any purchase. Each receipt is kept
## through services/wallet_reply.gd note_spend: `balance` stays the Pollen
## balance, `fruit_balance` the Fruit one, `sunshine_left` the Sunshine turns.
## A duel energy refill (refill_energy(), Fruits too) keeps the receipt's
## `energy` meter in services/duel_energy.gd the same way.
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
const PollenGrant = preload("res://services/pollen_grant.gd")
const WalletReply = preload("res://services/wallet_reply.gd")
const Presence = preload("res://services/friend_presence.gd")
const Typed = preload("res://services/typed_values.gd")
const Connectivity = preload("res://services/connectivity.gd")
const FruitWallet = preload("res://services/fruit_wallet.gd")
const DuelEnergy = preload("res://services/duel_energy.gd")

const WALLET_PATH := "/v1/pollen"
const SPEND_PATH := "/v1/pollen/spend"
const EQUIP_PATH := "/v1/pollen/equip"
## Sends of one action that got no answer before it gives up (the next tap starts a new one).
const MAX_SENDS := 3
## Answers after which the phone reads the wardrobe again, because what it showed was out of date.
const STALE := ["already_owned", "pollen_price_changed", "not_for_sale", "not_owned", "pollen_locked", "fruits_short", "fruits_blocked", "sunshine_active", "energy_full"]
## The spend kinds that turn Fruits into Pollen, and that buy Sunshine (the server's spend route).
const CONVERT := "convert"
const SUNSHINE := "sunshine"
## The spend kind and id that fill the duel energy meter for Fruits.
const ENERGY := "energy"
## Equip refusals that will not pass: the look put on goes. Anything else
## (rate limits, a token problem, an update needed, a server error) keeps it.
const FINAL_REFUSALS := ["invalid_pollen_equip", "not_owned", "identity_absent"]

## The wardrobe or the balance changed.
signal changed

var store: RefCounted
var wallet: RefCounted
## The monthly grant kept from the same wallet read (services/pollen_grant.gd): a read
## made here may be the one that pays an instalment, and its card must still show.
var grant: RefCounted
## The Fruits kept from the same reads and spends (services/fruit_wallet.gd).
var fruits: RefCounted
## The duel energy meter kept from the same reads and the refill's receipt (services/duel_energy.gd).
var energy: RefCounted
var _api: Node
## () -> {server, owner} of the signed-in player, or {} (Main's _names_scope).
var _scope: Callable
var _transport: Callable
var _busy := false
## Whether the server is reached (services/connectivity.gd); tests set their own.
var connectivity: RefCounted

## transport(method, path, body) -> response, for tests; else the API's queue.
func _init(api: Node, scope_source: Callable, transport: Callable = Callable(), wardrobe: RefCounted = null, pollen: RefCounted = null, monthly: RefCounted = null, fruit_store: RefCounted = null, energy_store: RefCounted = null) -> void:
	_api = api
	_scope = scope_source
	_transport = transport
	store = wardrobe if wardrobe != null else Wardrobe.shared()
	wallet = pollen if pollen != null else PollenWallet.shared()
	grant = monthly if monthly != null else PollenGrant.shared()
	fruits = fruit_store if fruit_store != null else FruitWallet.shared()
	energy = energy_store if energy_store != null else DuelEnergy.shared()

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

## Buys `id` (kind "item", "set" or "pack") for the cost the player saw: in
## Pollen, or in Fruits for an Orchard item or set (services/wardrobe.gd
## spend_currency). {ok, code, receipt}.
func buy(kind: String, id: String, cost: int) -> Dictionary:
	return await _spend(kind, id, cost, false)

## Turns `count` Fruits into Pollen, one way (the Pollen it makes shows before
## the player confirms: services/fruit_wallet.gd convert_pollen). `count` is a
## whole number of the server's steps. {ok, code, receipt}; the receipt's
## `pollen` is the Pollen added.
func convert(count: int) -> Dictionary:
	var context := scope()
	if not context.is_empty() and fruits.enabled(str(context.server), str(context.owner)) and not fruits.convert_valid(str(context.server), str(context.owner), count):
		return {"ok": false, "code": "invalid_pollen_spend", "receipt": {}}
	return await _spend(CONVERT, str(count), count, true)

## Buys Sunshine at the price the server last said (services/fruit_wallet.gd
## sunshine). {ok, code, receipt}; refused "sunshine_active" while turns are left.
func buy_sunshine() -> Dictionary:
	var context := scope()
	var price := 0
	if not context.is_empty(): price = int(fruits.sunshine(str(context.server), str(context.owner)).get("price", 0))
	if not context.is_empty() and fruits.enabled(str(context.server), str(context.owner)) and price <= 0:
		return {"ok": false, "code": "invalid_pollen_spend", "receipt": {}}
	return await _spend(SUNSHINE, SUNSHINE, price, true)

## Fills the duel energy meter at the price the server last said
## (services/duel_energy.gd meter's refill_fruits), only below its max.
## {ok, code, receipt}; refused "energy_full" at the max (the meter is read
## again with the wallet, as STALE says), "energy_disabled" while energy is off.
func refill_energy() -> Dictionary:
	var context := scope()
	if not context.is_empty() and not energy.enabled(str(context.server), str(context.owner)): return {"ok": false, "code": "energy_disabled", "receipt": {}}
	var price := 0
	if not context.is_empty(): price = int(energy.meter(str(context.server), str(context.owner)).get("refill_fruits", 0))
	if not context.is_empty() and price <= 0: return {"ok": false, "code": "invalid_pollen_spend", "receipt": {}}
	return await _spend(ENERGY, ENERGY, price, true)

## One spend: never queued (it needs an answer, so offline it is refused), one
## key for every send of it, the receipt kept in every store it feeds.
## `fruit_only`: a convert or Sunshine, which needs Fruits on too.
func _spend(kind: String, id: String, cost: int, fruit_only: bool) -> Dictionary:
	var context := scope()
	if context.is_empty() or not store.shop(str(context.server), str(context.owner)): return {"ok": false, "code": "pollen_shop_disabled", "receipt": {}}
	if fruit_only and not fruits.enabled(str(context.server), str(context.owner)): return {"ok": false, "code": "fruits_disabled", "receipt": {}}
	if not online(): return {"ok": false, "code": "offline", "receipt": {}}
	if _busy: return {"ok": false, "code": "busy", "receipt": {}}
	_busy = true
	var body := {"schema_version": 1, "idempotency_key": new_key(), "kind": kind, "id": id, "expected_cost": cost}
	var response := await _send(SPEND_PATH, body)
	var answer := _answer(response)
	if answer.ok and scope() == context:
		WalletReply.note_spend(context.server, context.owner, answer.receipt, wallet, store, fruits, energy)
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
		if answer.code in FINAL_REFUSALS:
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
	# Every store the read feeds keeps its part, the grant's too (services/wallet_reply.gd).
	var kept: Dictionary = WalletReply.note(context.server, context.owner, data, wallet, store, grant, fruits, energy)
	var noted: bool = kept.wallet and kept.wardrobe
	if noted: changed.emit()
	return {"ok": noted, "code": "" if noted else "invalid_response"}

func _request(method: int, path: String, body: Dictionary) -> Dictionary:
	var response: Variant
	if _transport.is_valid(): response = await _transport.call(method, path, body)
	elif is_instance_valid(_api): response = await _api.request_json(method, path, body)
	return response if response is Dictionary else {"ok": false, "code": "invalid_response"}
