extends RefCounted
## Sends this player's waiting Pollen claims (POST /v1/pollen/turn-claims) and
## reads the wallet (GET /v1/pollen) when this phone has none, recording each
## answer in PollenWallet. One request at a time: a flush asked for while one
## runs goes once that one returns. Main flushes at launch (once the server's
## capabilities are read) and on every resume. Nothing is sent while the server
## has not said Pollen earning is on.
const PollenWallet = preload("res://services/pollen_wallet.gd")
const Presence = preload("res://services/friend_presence.gd")
const CLAIMS_PATH := "/v1/pollen/turn-claims"
const WALLET_PATH := "/v1/pollen"
## Claims per request: the server's MAX_CLAIMS_PER_REQUEST.
const PER_REQUEST := 4
## Requests one flush may make, so a server that keeps answering "retry" costs
## a few requests, not a loop.
const MAX_REQUESTS := 4

## A flush finished; the wallet or a result may have changed.
signal settled

var wallet: RefCounted
var _api: Node
## () -> {server, owner} of the signed-in player, or {}.
var _scope: Callable
var _transport: Callable
var _sending := false
var _again := false

## transport(method, path, body) -> response, for tests; else the API's queue.
func _init(api: Node, scope_source: Callable, transport: Callable = Callable(), store: RefCounted = null) -> void:
	_api = api
	_scope = scope_source
	_transport = transport
	wallet = store if store != null else PollenWallet.shared()

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
		# A phone with no wallet (a new install, or a file that could not be read) asks for it.
		if wallet.wallet(context.server, context.owner).is_empty():
			requests += 1
			var read: Dictionary = await _request(HTTPClient.METHOD_GET, WALLET_PATH, {})
			if scope() != context or not read.get("ok", false) or not wallet.note_wallet(context.server, context.owner, read.get("data")): break
		if not _again: break
	_sending = false
	settled.emit()

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

func _request(method: int, path: String, body: Dictionary) -> Dictionary:
	var response: Variant
	if _transport.is_valid(): response = await _transport.call(method, path, body)
	elif is_instance_valid(_api): response = await _api.request_json(method, path, body)
	return response if response is Dictionary else {"ok": false, "code": "invalid_response"}
