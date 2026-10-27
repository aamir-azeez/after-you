extends SceneTree
## Sending Pollen claims and reading the wallet (services/pollen_client.gd),
## through a fake transport as the display name tests do:
## - nothing is sent while the server has not said Pollen is on;
## - claims go four to a request, one request at a time, and a flush asked for
##   while one is out runs after it, never beside it;
## - credited claims keep their receipts, refused ones go, and a failed request
##   or a server pause keeps them for the next flush;
## - the wallet is read only when this phone has none;
## - a server that keeps answering "retry" costs a few requests, not a loop;
## - an answer that arrives after the player changed is not recorded.
const PollenWallet = preload("res://services/pollen_wallet.gd")
const Client = preload("res://services/pollen_client.gd")

# Synthetic ids only.
const ME := "aaaaaaaaaaaaaaaaaaaaaa"
const OTHER := "bbbbbbbbbbbbbbbbbbbbbb"
const ROOM := "RRRRRRRRRRRRRRRRRRRRRR"

var checks := 0
var failures := 0
var _paths: Array[String] = []

class Api extends Node:
	var base_url := "https://pollen.example.test"
	var player_id := "aaaaaaaaaaaaaaaaaaaaaa"

## A transport that answers from a queue, one frame later, and counts how
## many requests are out at once.
class Fake extends RefCounted:
	var tree: SceneTree
	var sent: Array = []
	var replies: Array = []
	var out := 0
	var most_out := 0
	func call_it(method: int, path: String, body: Dictionary) -> Dictionary:
		sent.append({"method": method, "path": path, "body": body.duplicate(true)})
		out += 1
		most_out = maxi(most_out, out)
		await tree.process_frame
		await tree.process_frame
		out -= 1
		var reply: Variant = replies.pop_front() if not replies.is_empty() else {"ok": false, "code": "connection_interrupted"}
		return reply.call(body) if reply is Callable else reply

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await _off()
	await _claims()
	await _one_at_a_time()
	await _failures()
	await _wallet_read()
	await _bounded()
	await _identity_change()
	await _first_clears()
	for path: String in _paths:
		for suffix: String in ["", ".tmp", ".backup"]:
			if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(path + suffix)
	print("AFTER YOU POLLEN CLIENT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)

func _store() -> RefCounted:
	var path := "user://test-pollen-client-%s.json" % Crypto.new().generate_random_bytes(6).hex_encode()
	_paths.append(path)
	return PollenWallet.new(path)

static func _hash(n: int) -> String:
	return ("%x" % n).lpad(64, "0")

static func _receipt(earned: int, balance: int) -> Dictionary:
	return {"schema_version": 1.0, "earned": float(earned), "balance": float(balance), "clears": [],
		"turn": {"kind": "bank", "base": 89.0, "bonuses": [], "bonus_percent": 0.0, "amount": 89.0, "bloom": 1.0, "bloom_extra": 0.0, "boost_percent": 0.0, "boost": 0.0, "total": float(earned)}}

## The claims route's answer: each claim credited with `earned`, in order.
static func _credited(earned: int) -> Callable:
	return func(body: Dictionary) -> Dictionary:
		var results: Array = []
		var balance := 0
		for claim: Dictionary in body.claims:
			balance += earned
			results.append({"room_id": claim.room_id, "recording_hash": claim.recording_hash, "status": "credited", "receipt": _receipt(earned, balance)})
		return {"ok": true, "data": {"schema_version": 1.0, "results": results}}

static func _wallet(balance: int) -> Dictionary:
	return {"ok": true, "data": {"schema_version": 1.0, "balance": float(balance), "earned": float(balance), "bank": 12.0}}

func _setup(enabled: bool = true) -> Dictionary:
	var api := Api.new()
	root.add_child(api)
	var store := _store()
	var fake := Fake.new()
	fake.tree = self
	var who := {"owner": ME}
	var scope := func() -> Dictionary: return {"server": api.base_url, "owner": who.owner}
	var client: RefCounted = Client.new(api, scope, fake.call_it, store)
	if enabled: store.set_enabled(api.base_url, ME, true)
	return {"api": api, "store": store, "fake": fake, "client": client, "who": who}

func _settle(client: RefCounted) -> void:
	for i in range(40):
		if not client.sending(): return
		await process_frame

func _off() -> void:
	var t := _setup(false)
	t.store.queue_claim(t.api.base_url, ME, ROOM, _hash(1))
	t.client.flush()
	await _settle(t.client)
	_check(t.fake.sent.is_empty(), "While Pollen is off nothing is sent, even a claim waiting")
	t.api.queue_free()

func _claims() -> void:
	var t := _setup()
	t.store.note_wallet(t.api.base_url, ME, {"schema_version": 1.0, "balance": 0.0, "earned": 0.0, "bank": 12.0})
	for n in range(1, 7): t.store.queue_claim(t.api.base_url, ME, ROOM, _hash(n))
	t.fake.replies = [_credited(89), _credited(89)]
	t.client.flush()
	await _settle(t.client)
	_check(t.fake.sent.size() == 2 and t.fake.sent[0].path == "/v1/pollen/turn-claims" and t.fake.sent[0].method == HTTPClient.METHOD_POST, "Six claims go in two requests")
	_check(t.fake.sent[0].body.claims.size() == 4 and t.fake.sent[1].body.claims.size() == 2, "four to a request")
	_check(t.fake.sent[0].body == {"schema_version": 1, "claims": [{"room_id": ROOM, "recording_hash": _hash(1)}, {"room_id": ROOM, "recording_hash": _hash(2)}, {"room_id": ROOM, "recording_hash": _hash(3)}, {"room_id": ROOM, "recording_hash": _hash(4)}]}, "The body is the contract's")
	_check(t.store.claims(t.api.base_url, ME).is_empty() and not t.store.result_for(t.api.base_url, ME, ROOM, _hash(6)).is_empty(), "Each credited claim keeps its receipt and stops waiting")
	t.client.flush()
	await _settle(t.client)
	_check(t.fake.sent.size() == 2, "Nothing waiting and a wallet kept: a flush sends nothing")
	t.api.queue_free()

func _one_at_a_time() -> void:
	var t := _setup()
	t.store.note_wallet(t.api.base_url, ME, {"schema_version": 1.0, "balance": 0.0, "earned": 0.0, "bank": 12.0})
	t.store.queue_claim(t.api.base_url, ME, ROOM, _hash(1))
	t.fake.replies = [_credited(89), _credited(89)]
	t.client.flush()
	await process_frame
	# A turn accepted while the first request is out queues a claim and asks again.
	t.store.queue_claim(t.api.base_url, ME, ROOM, _hash(2))
	t.client.flush()
	t.client.flush()
	await _settle(t.client)
	_check(t.fake.most_out == 1, "Never two requests at once")
	_check(t.fake.sent.size() == 2 and t.fake.sent[1].body.claims == [{"room_id": ROOM, "recording_hash": _hash(2)}], "The flush asked for while one was out ran after it")
	t.api.queue_free()

func _failures() -> void:
	var t := _setup()
	t.store.note_wallet(t.api.base_url, ME, {"schema_version": 1.0, "balance": 0.0, "earned": 0.0, "bank": 12.0})
	for n in range(1, 4): t.store.queue_claim(t.api.base_url, ME, ROOM, _hash(n))
	t.fake.replies = [{"ok": false, "status": 0, "code": "connection_interrupted"}]
	t.client.flush()
	await _settle(t.client)
	_check(t.fake.sent.size() == 1 and t.store.claims(t.api.base_url, ME).size() == 3, "A failed request keeps every claim and stops until the next flush")
	t.fake.replies = [{"ok": true, "data": {"schema_version": 1.0, "results": [
		{"room_id": ROOM, "recording_hash": _hash(1), "status": "refused", "code": "pollen_claim_expired"},
		{"room_id": ROOM, "recording_hash": _hash(2), "status": "retry"},
		{"room_id": ROOM, "recording_hash": _hash(3), "status": "credited", "receipt": _receipt(89, 89)}]}}]
	t.client.flush()
	await _settle(t.client)
	var left: Array = t.store.claims(t.api.base_url, ME).map(func(entry: Dictionary) -> String: return entry.recording_hash)
	_check(left == [_hash(2)], "Refused goes for good, credited is kept, a server pause waits")
	t.fake.replies = [{"ok": true, "data": {"schema_version": 1.0, "results": []}}]
	t.client.flush()
	await _settle(t.client)
	_check(t.store.claims(t.api.base_url, ME).size() == 1, "An answer that does not match the claims sent changes nothing")
	t.api.queue_free()

func _wallet_read() -> void:
	var t := _setup()
	t.fake.replies = [_wallet(1200)]
	t.client.flush()
	await _settle(t.client)
	_check(t.fake.sent.size() == 1 and t.fake.sent[0].path == "/v1/pollen" and t.fake.sent[0].method == HTTPClient.METHOD_GET, "A phone with no wallet asks for it")
	_check(t.store.wallet(t.api.base_url, ME) == {"balance": 1200, "earned": 1200, "bank": 12}, "and keeps the answer")
	t.client.flush()
	await _settle(t.client)
	_check(t.fake.sent.size() == 1, "Once kept, it is not asked for again on every flush")
	var broken := _setup()
	broken.fake.replies = [{"ok": true, "data": {"schema_version": 1.0, "balance": -3.0, "earned": 0.0, "bank": 0.0}}]
	broken.client.flush()
	await _settle(broken.client)
	_check(broken.store.wallet(broken.api.base_url, ME).is_empty(), "A broken wallet answer is not kept")
	t.api.queue_free()
	broken.api.queue_free()

func _bounded() -> void:
	var t := _setup()
	t.store.note_wallet(t.api.base_url, ME, {"schema_version": 1.0, "balance": 0.0, "earned": 0.0, "bank": 12.0})
	t.store.queue_claim(t.api.base_url, ME, ROOM, _hash(1))
	var pause := {"ok": true, "data": {"schema_version": 1.0, "results": [{"room_id": ROOM, "recording_hash": _hash(1), "status": "retry"}]}}
	t.fake.replies = [pause, pause, pause, pause, pause, pause]
	t.client.flush()
	await _settle(t.client)
	_check(t.fake.sent.size() == 1 and t.store.claims(t.api.base_url, ME).size() == 1, "A flush where nothing moved stops after one request")
	t.api.queue_free()
	# A claim the server cannot pay yet goes behind the others, so newer ones are tried next time.
	var r := _setup()
	r.store.note_wallet(r.api.base_url, ME, {"schema_version": 1.0, "balance": 0.0, "earned": 0.0, "bank": 12.0})
	for n in range(1, 6): r.store.queue_claim(r.api.base_url, ME, ROOM, _hash(n))
	var held := func(body: Dictionary) -> Dictionary:
		return {"ok": true, "data": {"schema_version": 1.0, "results": body.claims.map(func(claim: Dictionary) -> Dictionary: return {"room_id": claim.room_id, "recording_hash": claim.recording_hash, "status": "retry"})}}
	r.fake.replies = [held]
	r.client.flush()
	await _settle(r.client)
	var order: Array = r.store.claims(r.api.base_url, ME).map(func(entry: Dictionary) -> String: return entry.recording_hash)
	_check(order == [_hash(5), _hash(1), _hash(2), _hash(3), _hash(4)], "Claims the server could not pay yet go behind the one it has not seen")
	r.api.queue_free()

func _identity_change() -> void:
	var t := _setup()
	t.store.note_wallet(t.api.base_url, ME, {"schema_version": 1.0, "balance": 0.0, "earned": 0.0, "bank": 12.0})
	t.store.queue_claim(t.api.base_url, ME, ROOM, _hash(1))
	t.fake.replies = [_credited(89)]
	t.client.flush()
	await process_frame
	t.who.owner = OTHER
	await _settle(t.client)
	_check(t.store.result_for(t.api.base_url, ME, ROOM, _hash(1)).is_empty() and t.store.claims(t.api.base_url, ME).size() == 1, "An answer that comes back after the player changed is not recorded")
	t.api.queue_free()

## The clear-claims route's answer: each claim credited with `earned`.
static func _clears_credited(earned: int) -> Callable:
	return func(body: Dictionary) -> Dictionary:
		var results: Array = []
		for claim: Dictionary in body.claims:
			var answer := claim.duplicate()
			answer.merge({"status": "credited", "receipt": {"schema_version": 1.0, "earned": float(earned), "balance": float(earned), "clears": []}})
			results.append(answer)
		return {"ok": true, "data": {"schema_version": 1.0, "results": results}}

func _first_clears() -> void:
	var t := _setup()
	t.store.note_wallet(t.api.base_url, ME, {"schema_version": 1.0, "balance": 0.0, "earned": 0.0, "bank": 12.0})
	var solo: Array = ["first-steps", "high-and-low"]
	t.client.solo_levels = func() -> Array: return solo
	t.store.queue_clear(t.api.base_url, ME, "room:" + ROOM)
	t.store.queue_claim(t.api.base_url, ME, ROOM, _hash(1))
	# Offline: everything waits, in order, and nothing is lost.
	t.fake.replies = [{"ok": false, "status": 0, "code": "connection_interrupted"}]
	t.client.flush()
	await _settle(t.client)
	_check(t.fake.sent.size() == 1 and t.store.clear_claims(t.api.base_url, ME).size() == 1 and t.store.claims(t.api.base_url, ME).size() == 1, "Offline, turn claims and first clears wait")
	t.fake.replies = [_credited(89), _clears_credited(1200)]
	t.client.flush()
	await _settle(t.client)
	_check(t.fake.sent.size() == 3 and t.fake.sent[1].path == "/v1/pollen/turn-claims" and t.fake.sent[2].path == "/v1/pollen/clear-claims", "Turn claims go first, then first clears")
	_check(t.fake.sent[2].body == {"schema_version": 1, "claims": [{"room_id": ROOM}, {"level_id": "first-steps"}, {"level_id": "high-and-low"}]}, "A finished room and the chapters finished solo go as the route takes them")
	_check(t.store.clear_claims(t.api.base_url, ME).is_empty() and t.store.cleared(t.api.base_url, ME, "room:" + ROOM) and t.store.cleared(t.api.base_url, ME, "level:high-and-low"), "Confirmed first clears are settled")
	t.client.flush()
	await _settle(t.client)
	_check(t.fake.sent.size() == 3, "and never sent again, though the keepsakes still show them")
	solo.append("rolling-home")
	t.fake.replies = [{"ok": true, "data": {"schema_version": 1.0, "results": [{"level_id": "rolling-home", "status": "retry"}]}}]
	t.client.flush()
	await _settle(t.client)
	_check(t.fake.sent.size() == 4 and t.store.clear_claims(t.api.base_url, ME).size() == 1, "A newly finished chapter is claimed; a server pause keeps it")
	t.api.queue_free()

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
