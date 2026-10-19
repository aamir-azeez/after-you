extends RefCounted
## A hard room's own requests (services/hard_mode.gd):
## - the reset after a slip, POST /v2/rooms/<id>/hard-reset. It is kept in a
##   small journal per identity and room until the server answers it, and is
##   resent byte for byte (the server answers a resend with the reset it
##   already made). While one waits, the room's turns wait too.
## - the read of the failures the room keeps that this phone has not seen,
##   GET /v2/rooms/<id>/hard/<seen>, only when the room says it holds more.
## The journal also keeps how many slips this phone has shown a card for, so
## a slip's card shows once, apart from whether its recording was read.
## Turns cost no request here.
const RoomsApi = preload("res://services/rooms_api.gd")
const Typed = preload("res://services/typed_values.gd")
const HardMode = preload("res://services/hard_mode.gd")
const SCOPE := "relay-hard-v1:"
const MAX_FAILURES := 5
## Refusals that may pass on their own: the reset waits and is sent again.
const PASSING := [401, 408, 429]

var busy := false
var last_code := ""
var _api: Node
var _identity: Callable
var _store: RefCounted
var _owner := ""
var _room := ""
var _state: Dictionary = {}
var _generation := 0

func _init(api: Node, identity: Callable, store: RefCounted) -> void:
	_api = api
	_identity = identity
	_store = store

## Loads this identity's journal for `room_id`. False when it cannot be read.
func bind(room_id: String) -> bool:
	var owner := _player()
	if owner.is_empty() or not _id(room_id): return _fail("identity_changed")
	if owner == _owner and room_id == _room and not _state.is_empty(): return true
	if busy: return _fail("request_busy")
	_generation += 1
	_owner = owner
	_room = room_id
	_state = {}
	var loaded: Dictionary = _store.load_scope(_scope())
	if not loaded.get("ok", false): return _fail("hard_storage_unavailable")
	var value: Variant = loaded.get("value", {})
	if value is Dictionary and not value.is_empty() and valid_journal(value, owner, room_id, _server()): _state = value.duplicate(true)
	else: _state = {"schema_version": 1, "owner_player_id": owner, "room_id": room_id, "server_hash": _server(), "pending": {}, "seen": 0, "shown": 0}
	return true

func invalidate() -> void:
	_generation += 1
	busy = false
	_owner = ""
	_room = ""
	_state = {}

func pending() -> Dictionary:
	return _state.get("pending", {}).duplicate(true) if _current() else {}

## How many of the room's failures this phone has already taken in.
func seen() -> int:
	return int(_state.get("seen", 0)) if _current() else 0

## How many of the room's failures this phone has shown a card for.
func shown() -> int:
	return int(_state.get("shown", 0)) if _current() else 0

## The card of the room's `count`th failure was shown. False when that could
## not be kept (the card then shows again next time).
func mark_shown(count: int) -> bool:
	if not _current() or count <= shown(): return true
	var next := _state.duplicate(true)
	next.shown = count
	return _persist(next)

## Keeps the reset of `room` (the snapshot the slip was played on) until it
## is answered. `slip` is the slipped turn's recording, or {}.
func queue_reset(room: Dictionary, reason: String, slip: Dictionary) -> bool:
	if not _current() or not pending().is_empty(): return _fail("request_busy")
	var body := {"base_revision": int(room.revision), "branch": int(room.branch), "idempotency_key": RoomsApi.new_key(), "reason": reason,
		"stage_index": int(room.stage_index), "role": str(room.active_role)}
	if not slip.is_empty(): body.slip = slip.duplicate(true)
	var next := _state.duplicate(true)
	next.pending = body
	return _persist(next)

## Sends the waiting reset. {"ok": true, "room", "failure"} once the server
## made it; {"ok": false, "settled": true} when the room no longer takes it
## (the reset is dropped); {"ok": false} to try again later.
func send() -> Dictionary:
	var body := pending()
	if body.is_empty() or busy: return {"ok": false, "code": "request_busy"}
	var generation := _generation
	busy = true
	var response: Dictionary = await _api.request_json(HTTPClient.METHOD_POST, _path() + "/hard-reset", body, func() -> bool: return generation == _generation)
	if generation != _generation: return {"ok": false, "code": "identity_changed"}
	busy = false
	var code := str(response.get("code", ""))
	var status := int(response.get("status", 0))
	if response.get("ok", false) and _valid_reset(response.get("data"), body):
		var next := _state.duplicate(true)
		var number := int(response.data.room.hard.failures)
		next.pending = {}
		# This phone's own slip: its card is the one already shown.
		next.seen = maxi(int(next.seen), number)
		next.shown = maxi(int(next.shown), number)
		if not _persist(next): return {"ok": false, "code": last_code}
		last_code = ""
		return {"ok": true, "room": response.data.room, "failure": response.data.failure, "number": number}
	# A slip too big or not taken: the reset goes again without it, as a new request.
	if status in [413, 422] and body.has("slip"):
		var lighter := body.duplicate(true)
		lighter.erase("slip")
		lighter.idempotency_key = RoomsApi.new_key()
		var retried := _state.duplicate(true)
		retried.pending = lighter
		if _persist(retried): return await send()
	# Any other definite refusal: the reset is no longer this phone's to send.
	if status >= 400 and status < 500 and status not in PASSING:
		var cleared := _state.duplicate(true)
		cleared.pending = {}
		_persist(cleared)
		_fail(code if not code.is_empty() else "hard_reset_refused")
		return {"ok": false, "settled": true, "code": last_code}
	_fail(code if not code.is_empty() else "hard_reset_unavailable")
	return {"ok": false, "code": last_code}

## The room's failures this phone has not seen, oldest first, when it holds
## more than seen(): {"ok", "list"}. Each is {by, stage_index, role, reason,
## at, number, slip: null or {recording, checkpoint, prior}}. Marks them seen
## once read. {"ok": false} when the read failed.
func read_failures(room: Dictionary) -> Dictionary:
	var hard: Variant = room.get("hard")
	if not _current() or busy or not hard is Dictionary or int(hard.get("failures", 0)) <= seen(): return {"ok": true, "list": []}
	var generation := _generation
	var known := seen()
	busy = true
	var response: Dictionary = await _api.request_json(HTTPClient.METHOD_GET, _path() + "/hard/" + str(known), {}, func() -> bool: return generation == _generation)
	if generation != _generation: return {"ok": false, "code": "identity_changed"}
	busy = false
	if not response.get("ok", false) or not valid_failures(response.get("data"), room, known):
		_fail(str(response.get("code", "hard_read_unavailable")))
		return {"ok": false, "code": last_code}
	var data: Dictionary = response.data
	var next := _state.duplicate(true)
	next.seen = maxi(int(next.seen), int(data.failures))
	if not _persist(next): return {"ok": false, "code": last_code}
	return {"ok": true, "list": data.list}

## The read of one room's kept failures after the `since`th: numbered in
## order, each past `since` and none past the room's count.
static func valid_failures(value: Variant, room: Dictionary, since: int = 0) -> bool:
	if not value is Dictionary or value.size() != 3 or not Typed.equal(value.get("schema_version"), 1) or not Typed.whole_number(value.get("failures")) or not value.get("list") is Array or value.list.size() > MAX_FAILURES: return false
	var last := since
	for item: Variant in value.list:
		if not valid_failure(item, room) or int(item.number) <= last or int(item.number) > int(value.failures): return false
		last = int(item.number)
	return true

## One kept failure: who slipped, where and how (valid_last), its number
## among the room's slips, and its slip.
static func valid_failure(item: Variant, room: Dictionary) -> bool:
	if not item is Dictionary or item.size() != 7 or not item.has("slip") or not Typed.whole_number(item.get("number")) or int(item.number) < 1: return false
	var summary: Dictionary = item.duplicate()
	summary.erase("slip")
	summary.erase("number")
	if not valid_last(summary, room): return false
	var slip: Variant = item.get("slip")
	return slip == null or (slip is Dictionary and slip.size() == 3 and slip.get("recording") is Dictionary and slip.get("checkpoint") is Dictionary and (slip.get("prior") == null or slip.get("prior") is Dictionary))

## Who slipped, where and how: {by, stage_index, role, reason, at}.
static func valid_last(item: Variant, room: Dictionary) -> bool:
	if not item is Dictionary or item.size() != 5 or item.get("by") not in [room.get("host_id"), room.get("guest_id")] or item.get("reason") not in HardMode.REASONS or item.get("role") not in ["a", "b"]: return false
	return Typed.whole_number(item.get("stage_index")) and int(item.stage_index) >= 0 and int(item.stage_index) <= 63 and item.get("at") is String and item.at.length() <= 40

## The view's `hard` field: {schema_version 1, failures, over, last}.
static func valid_view(value: Variant, room: Dictionary) -> bool:
	if not value is Dictionary or value.size() != 4 or not Typed.equal(value.get("schema_version"), 1) or not Typed.whole_number(value.get("failures")) or int(value.failures) < 0 or not value.get("over") is bool: return false
	var last: Variant = value.get("last")
	if last == null: return int(value.failures) == 0
	return int(value.failures) > 0 and valid_last(last, room)

func _valid_reset(value: Variant, body: Dictionary) -> bool:
	if not value is Dictionary or not value.get("room") is Dictionary or not value.get("failure") is Dictionary: return false
	var room: Dictionary = value.room
	if not Typed.equal(room.get("room_id"), _room) or not valid_view(room.get("hard"), room) or int(room.get("revision", -1)) <= int(body.base_revision): return false
	return valid_last(value.failure, room) and Typed.equal(value.failure.get("by"), _owner) and Typed.equal(value.failure.get("stage_index"), body.stage_index)

static func valid_journal(value: Dictionary, owner: String, room_id: String, server_hash: String) -> bool:
	if value.size() != 7 or not Typed.equal(value.get("schema_version"), 1) or not Typed.equal(value.get("owner_player_id"), owner) or not Typed.equal(value.get("room_id"), room_id) or not Typed.equal(value.get("server_hash"), server_hash): return false
	if not Typed.whole_number(value.get("seen")) or int(value.seen) < 0 or not Typed.whole_number(value.get("shown")) or int(value.shown) < 0 or not value.get("pending") is Dictionary: return false
	var body: Dictionary = value.pending
	if body.is_empty(): return true
	var keys := ["base_revision", "branch", "idempotency_key", "reason", "stage_index", "role"]
	if body.has("slip"): keys.append("slip")
	if body.size() != keys.size(): return false
	for key: String in keys:
		if not body.has(key): return false
	return Typed.whole_number(body.base_revision) and Typed.whole_number(body.branch) and Typed.whole_number(body.stage_index) and body.idempotency_key is String and body.reason in HardMode.REASONS and body.role in ["a", "b"] and (not body.has("slip") or body.slip is Dictionary)

func _current() -> bool:
	return not _state.is_empty() and _owner == _player() and not _owner.is_empty()

func _persist(value: Dictionary) -> bool:
	if not _current() or not valid_journal(value, _owner, _room, _server()) or not _store.save_scope(_scope(), value).get("ok", false): return _fail("hard_storage_unavailable")
	_state = value.duplicate(true)
	return true

func _scope() -> String: return SCOPE + _owner + ":" + _room
func _path() -> String: return "/v2/rooms/" + _room
func _server() -> String: return str(_api.base_url).sha256_text() if is_instance_valid(_api) else ""

func _player() -> String:
	var value: Variant = _identity.call() if _identity.is_valid() else null
	if not value is Dictionary or value.get("ready") != true or not _id(value.get("player_id")) or not is_instance_valid(_api) or _api.player_id != value.player_id: return ""
	return str(value.player_id)

func _fail(code: String) -> bool:
	last_code = code
	return false

static func _id(value: Variant) -> bool:
	return value is String and value.length() == 22 and RegEx.create_from_string("^[A-Za-z0-9_-]{22}$").search(value) != null
