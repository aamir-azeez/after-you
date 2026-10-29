extends RefCounted
## Sends this player's waiting Pollen claims (POST /v1/pollen/turn-claims), its
## waiting first clears (POST /v1/pollen/clear-claims: rooms seen finished
## together, and chapters finished solo as the Home keepsake marks show), and
## reads the wallet (GET /v1/pollen) when this phone has none, recording each
## answer in PollenWallet. One request at a time: a flush asked for while one
## runs goes once that one returns. Main flushes at launch (once the server's
## capabilities are read) and on every resume. Nothing is sent while the server
## has not said Pollen earning is on.
## While the monthly grant is on, a phone that has Full Journey also reads the
## wallet at most every GRANT_READ_MS: the server pays an instalment that is due
## inside that read (services/pollen_grant.gd keeps what it says).
const PollenWallet = preload("res://services/pollen_wallet.gd")
const PollenGrant = preload("res://services/pollen_grant.gd")
const Wardrobe = preload("res://services/wardrobe.gd")
const Presence = preload("res://services/friend_presence.gd")
const CLAIMS_PATH := "/v1/pollen/turn-claims"
const CLEARS_PATH := "/v1/pollen/clear-claims"
const WALLET_PATH := "/v1/pollen"
const HISTORY_PATH := "/v1/pollen/history"
const PollenHistory = preload("res://services/pollen_history.gd")
## Claims per request: the server's MAX_CLAIMS_PER_REQUEST.
const PER_REQUEST := 4
## Requests one flush may make, so a server that keeps answering "retry" costs
## a few requests, not a loop.
const MAX_REQUESTS := 4
## How often a Full Journey phone reads the wallet for the monthly grant (memory
## only, so each launch reads once). A free player's phone never reads for it.
const GRANT_READ_MS := 6 * 3600 * 1000

## A flush finished; the wallet or a result may have changed.
signal settled

var wallet: RefCounted
## The wardrobe kept from the same wallet read while the shop is on (services/wardrobe.gd).
var wardrobe: RefCounted
## The monthly grant kept from the same wallet read while it is on (services/pollen_grant.gd).
var grant: RefCounted
## () -> bool: whether this phone holds Full Journey (Main's cached entitlement).
var subscribed: Callable
## Scope key -> Time.get_ticks_msec() of the last wallet read made for the grant.
var _grant_read_at: Dictionary = {}
var _api: Node
## () -> {server, owner} of the signed-in player, or {}.
var _scope: Callable
var _transport: Callable
## () -> Array of level ids this player finished solo (Main: HomeKeepsakes.solo_finished_levels).
var solo_levels: Callable
var _sending := false
var _again := false

## transport(method, path, body) -> response, for tests; else the API's queue.
func _init(api: Node, scope_source: Callable, transport: Callable = Callable(), store: RefCounted = null) -> void:
	_api = api
	_scope = scope_source
	_transport = transport
	wallet = store if store != null else PollenWallet.shared()
	wardrobe = Wardrobe.shared()
	grant = PollenGrant.shared()

## {server, owner} while the server has said Pollen earning is on, else {}.
func scope() -> Dictionary:
	var value: Variant = _scope.call() if _scope.is_valid() else null
	if not value is Dictionary or value.is_empty() or not Presence.valid_id(value.get("owner")): return {}
	return value if wallet.enabled(str(value.server), str(value.owner)) else {}

func sending() -> bool:
	return _sending

## Sends what waits. Safe to call at any time: it returns at once and works in
## the background, one request after another.
func flush() -> void:
	if _sending:
		_again = true
		return
	_run()

func _run() -> void:
	_sending = true
	var requests := 0
	while requests < MAX_REQUESTS:
		_again = false
		var context := scope()
		if context.is_empty(): break
		var batch: Array = wallet.claims(context.server, context.owner, PER_REQUEST)
		if not batch.is_empty():
			requests += 1
			var response: Dictionary = await _request(HTTPClient.METHOD_POST, CLAIMS_PATH, {"schema_version": 1, "claims": batch})
			if scope() != context or not _settle_claims(context, batch, response): break
			continue
		_queue_solo(context)
		var clears: Array = wallet.clear_claims(context.server, context.owner, PER_REQUEST)
		if not clears.is_empty():
			requests += 1
			var answer: Dictionary = await _request(HTTPClient.METHOD_POST, CLEARS_PATH, {"schema_version": 1, "claims": clears.map(func(entry: Dictionary) -> Dictionary: return entry.claim)})
			if scope() != context or not _settle_clears(context, clears, answer): break
			continue
		# A phone with no wallet (a new install, or a file that could not be read) asks for it,
		# and so does one with no wardrobe while the shop is on: the same read carries both.
		if wallet.wallet(context.server, context.owner).is_empty() or _wardrobe_missing(context) or _grant_due(context):
			requests += 1
			var read: Dictionary = await _request(HTTPClient.METHOD_GET, WALLET_PATH, {})
			if scope() != context or not read.get("ok", false) or not wallet.note_wallet(context.server, context.owner, read.get("data")): break
			# Only an answered read counts for the grant: an offline launch tries again on the next flush.
			if _grant_wanted(context): _grant_read_at[PollenWallet.scope_key(context.server, context.owner)] = Time.get_ticks_msec()
			if wardrobe != null: wardrobe.note_view(context.server, context.owner, read.get("data"))
			if grant != null: grant.note_view(context.server, context.owner, read.get("data"))
		if not _again: break
	_sending = false
	settled.emit()

## A Full Journey phone while the grant is on.
func _grant_wanted(context: Dictionary) -> bool:
	return grant != null and grant.enabled(context.server, context.owner) and subscribed.is_valid() and bool(subscribed.call())

## The grant wants a wallet read: none yet this launch, or the last one is GRANT_READ_MS old.
func _grant_due(context: Dictionary) -> bool:
	if not _grant_wanted(context): return false
	var key := PollenWallet.scope_key(context.server, context.owner)
	return not _grant_read_at.has(key) or Time.get_ticks_msec() - int(_grant_read_at[key]) >= GRANT_READ_MS

func _wardrobe_missing(context: Dictionary) -> bool:
	return wardrobe != null and wardrobe.enabled(context.server, context.owner) and wardrobe.view(context.server, context.owner).is_empty()

## Records each claim's answer; false when the request itself failed (sent again later).
func _settle_claims(context: Dictionary, batch: Array, response: Dictionary) -> bool:
	var data: Variant = response.get("data")
	if not response.get("ok", false) or not data is Dictionary or not data.get("results") is Array or data.results.size() != batch.size(): return false
	var progressed := false
	for index in range(batch.size()):
		var answer: Variant = data.results[index]
		if not answer is Dictionary or answer.get("room_id") != batch[index].room_id or answer.get("recording_hash") != batch[index].recording_hash: continue
		wallet.settle_claim(context.server, context.owner, batch[index].room_id, batch[index].recording_hash, answer)
		progressed = progressed or answer.get("status") in ["credited", "refused"]
	return progressed

## Chapters finished solo that have no first clear settled yet wait to be claimed.
func _queue_solo(context: Dictionary) -> void:
	if not solo_levels.is_valid(): return
	var levels: Variant = solo_levels.call()
	if not levels is Array: return
	for level: Variant in levels:
		if level is String: wallet.queue_clear(context.server, context.owner, "level:" + level)

## Records each first clear's answer; false when the request itself failed or nothing moved.
func _settle_clears(context: Dictionary, batch: Array, response: Dictionary) -> bool:
	var data: Variant = response.get("data")
	if not response.get("ok", false) or not data is Dictionary or not data.get("results") is Array or data.results.size() != batch.size(): return false
	var progressed := false
	for index in range(batch.size()):
		var answer: Variant = data.results[index]
		var claim: Dictionary = batch[index].claim
		if not answer is Dictionary or claim.keys().any(func(field: String) -> bool: return answer.get(field) != claim[field]): continue
		wallet.settle_clear(context.server, context.owner, batch[index].key, answer)
		progressed = progressed or answer.get("status") in ["credited", "refused"]
	return progressed

## The Pollen from play page's one read (GET /v1/pollen/history), when the page
## opens and never on a timer: checked (services/pollen_history.gd), or {} when
## it could not be read or Pollen earning is off.
func history() -> Dictionary:
	var context := scope()
	if context.is_empty(): return {}
	var response: Dictionary = await _request(HTTPClient.METHOD_GET, HISTORY_PATH, {})
	if scope() != context or not response.get("ok", false): return {}
	return PollenHistory.checked(response.get("data"))

func _request(method: int, path: String, body: Dictionary) -> Dictionary:
	var response: Variant
	if _transport.is_valid(): response = await _transport.call(method, path, body)
	elif is_instance_valid(_api): response = await _api.request_json(method, path, body)
	return response if response is Dictionary else {"ok": false, "code": "invalid_response"}
