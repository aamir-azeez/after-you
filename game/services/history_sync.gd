extends RefCounted
## Keeps this phone's copy of a room's finished attempts and lets the server keep
## only their hashes once both phones hold them (room history, replay transfer
## schema 2). Runs between turns, one room at a time, never during play.
##
## For each finished attempt the server lists:
## - held and not on this phone: download the exact bytes, check them on a worker
##   thread (length, SHA-256, the chain link, the room), write them durably, read
##   them back, and only then confirm (ACK) when no gameplay, photo or redo work
##   is waiting for the room;
## - offloaded and on this phone, when the friend's phone asked: send the bytes back;
## - offloaded and not on this phone: ask the friend's phone for it and report it.

const Store = preload("res://services/history_store.gd")
const Reaper = preload("res://services/worker_reaper.gd")
const Registry = preload("res://services/chapter_registry.gd")
const Save = preload("res://services/local_save.gd")

const ATTEMPT_KEYS := ["position", "branch", "digest", "link", "byte_length", "last_stage", "state", "acked_by_you", "partner_acked", "wanted_by_partner", "pair_ids"]

var store: RefCounted
var _transport: Callable
var _eligibility: Callable
var _busy := false
var _checking := false

## transport(method, path, body, raw) -> {ok, status, code, data | bytes}.
## eligibility(room_id) -> {ok, owner, server_key, offload_enabled, gameplay_pending, photo_pending, redo_pending}.
func _init(transport: Callable, eligibility: Callable, history_store: RefCounted = null) -> void:
	_transport = transport
	_eligibility = eligibility
	store = Store.new() if history_store == null else history_store

func busy() -> bool:
	return _busy or _checking

static func path(room_id: String, position: int = -1, action: String = "") -> String:
	var value := "/v2/rooms/" + room_id + "/history"
	if position >= 0: value += "/" + str(position)
	if not action.is_empty(): value += "/" + action
	return value

static func _hash(value: Variant) -> bool:
	return Store._hash(value)

static func _int(value: Variant, low: int, high: int) -> bool:
	return (value is int or (value is float and is_finite(value) and value == floor(value))) and int(value) >= low and int(value) <= high

## The server's list, checked: one record a finished attempt in order, and the head
## is the last link. Every attempt keeps the server's exact field set.
static func valid_view(value: Variant) -> bool:
	if not value is Dictionary or value.size() != 6 or not Save.equal(value.get("schema_version"), 1.0) or not value.get("mode") in ["attempts", "v1_transferred"] or not _hash(value.get("head")) or not value.get("attempts") is Array or not value.get("partner_supports") is bool: return false
	var room: Variant = value.get("room")
	if not room is Dictionary or room.size() != 6 or not Store._id(str(room.get("room_id"))) or not Store._id(str(room.get("host_id"))) or not (room.get("guest_id") == null or Store._id(str(room.guest_id))) or Registry.resolve(room).is_empty(): return false
	var attempts: Array = value.attempts
	if attempts.size() > Store.MAX_ATTEMPTS or (value.mode == "v1_transferred" and not attempts.is_empty()): return false
	for index in range(attempts.size()):
		var item: Variant = attempts[index]
		if not item is Dictionary or item.size() != ATTEMPT_KEYS.size() or ATTEMPT_KEYS.any(func(key: String) -> bool: return not item.has(key)): return false
		if not _int(item.position, index, index) or not _int(item.branch, index, index) or not _hash(item.digest) or not _hash(item.link) or not _int(item.byte_length, 1, Store.MAX_ATTEMPT_BYTES) or not _int(item.last_stage, 0, 8): return false
		if not item.state in ["held", "offloaded"] or not item.acked_by_you is bool or not item.partner_acked is bool or not item.wanted_by_partner is bool or not item.pair_ids is Array: return false
		for pair_id: Variant in item.pair_ids:
			if not pair_id is String or RegEx.create_from_string("^p%d-[0-7]$" % index).search(pair_id) == null: return false
	return value.head == (attempts.back().link if not attempts.is_empty() else Store.ZERO_LINK)

## Pure worker check of a downloaded attempt: the exact canonical bytes for this
## room at this place in the chain, or an empty result.
static func check_download(tagged: PackedByteArray, record: Dictionary, previous_link: String, room_id: String) -> Dictionary:
	var bytes := Store.verified_bytes(tagged, record)
	if bytes.is_empty(): return {}
	var blob: Variant = JSON.parse_string(bytes.get_string_from_utf8())
	if not blob is Dictionary or not Save.equal(blob.get("format"), "after-you.attempt") or not Save.equal(blob.get("format_version"), 1.0) or not Save.equal(blob.get("room_id"), room_id) or not Save.equal(blob.get("position"), float(record.position)): return {}
	if Store.link(blob, int(record.position), previous_link, record.digest, int(record.byte_length)) != record.link: return {}
	return blob

func _on_worker(task: Callable) -> Variant:
	_checking = true
	var result: Variant = await Reaper.run(task)
	_checking = false
	return result

func list(room_id: String) -> Dictionary:
	var response: Dictionary = await _transport.call(HTTPClient.METHOD_GET, path(room_id), {}, false)
	if not response.get("ok", false): return response
	if not valid_view(response.get("data")): return {"ok": false, "status": 0, "code": "invalid_history"}
	return {"ok": true, "view": response.data}

## Downloads, checks and durably saves one held attempt. True when this phone has it.
func download(room_id: String, scope: Dictionary, view: Dictionary, position: int) -> Dictionary:
	var record: Dictionary = view.attempts[position]
	var previous: String = view.attempts[position - 1].link if position > 0 else Store.ZERO_LINK
	var response: Dictionary = await _transport.call(HTTPClient.METHOD_GET, path(room_id, position), {}, true)
	if not response.get("ok", false): return response
	var tagged: PackedByteArray = response.get("bytes", PackedByteArray())
	var blob: Variant = await _on_worker(Callable(get_script(), "check_download").bind(tagged, record, previous, room_id))
	if not blob is Dictionary or blob.is_empty(): return {"ok": false, "status": 0, "code": "history_mismatch"}
	if not store.save(scope.server_key, scope.owner, room_id, record, tagged): return {"ok": false, "status": 0, "code": "history_unsaved"}
	return {"ok": true}

## One pass over a room. Safe to repeat: every step is keyed by an attempt's link.
## {mode: "v1"} means this room stays with replay transfer v1 and nothing was done.
func sync_room(room_id: String) -> Dictionary:
	if _busy: return {"ok": false, "status": 0, "code": "history_busy"}
	_busy = true
	var result := await _sync_room(room_id)
	_busy = false
	return result

func _sync_room(room_id: String) -> Dictionary:
	var scope: Dictionary = _eligibility.call(room_id)
	if not scope.get("ok", false): return {"ok": false, "status": 0, "code": "history_unavailable"}
	var listed := await list(room_id)
	if not listed.get("ok", false): return listed
	var view: Dictionary = listed.view
	# History runs once something already left the server, or when offload is on and
	# both phones keep attempts. Otherwise the room keeps replay transfer v1, as today.
	var offloaded: bool = view.attempts.any(func(item: Dictionary) -> bool: return item.state == "offloaded")
	if view.mode == "v1_transferred" or not (offloaded or (scope.get("offload_enabled", false) and view.partner_supports)):
		return {"ok": true, "mode": "v1", "missing": [], "acknowledged": [], "view": view}
	var missing: Array = []
	var acknowledged: Array = []
	for item: Dictionary in view.attempts:
		var position := int(item.position)
		var local: bool = store.has(scope.server_key, scope.owner, room_id, position, item.link)
		if item.state == "held":
			if not local:
				var saved := await download(room_id, scope, view, position)
				if not saved.get("ok", false): return saved
				local = true
			# Re-read: a turn, photo or redo may have started while this ran.
			scope = _eligibility.call(room_id)
			var quiet: bool = scope.get("ok", false) and scope.get("offload_enabled", false) and not scope.gameplay_pending and not scope.photo_pending and not scope.redo_pending
			if local and quiet and not item.acked_by_you and store.has(scope.server_key, scope.owner, room_id, position, item.link):
				var ack: Dictionary = await _transport.call(HTTPClient.METHOD_POST, path(room_id, position, "ack"), {"schema_version": 1, "link": item.link}, false)
				if not ack.get("ok", false): return ack
				acknowledged.append(position)
		elif local and item.wanted_by_partner:
			var sent := await upload(room_id, scope, position)
			if not sent.get("ok", false): return sent
		elif not local:
			# A new or restored phone: ask the friend's phone for it (the server keeps one request).
			missing.append(position)
			var asked := await want(room_id, position)
			if not asked.get("ok", false): return asked
	return {"ok": true, "mode": "attempts", "missing": missing, "acknowledged": acknowledged, "view": view}

## Sends this phone's exact bytes of an attempt back to the server.
func upload(room_id: String, scope: Dictionary, position: int) -> Dictionary:
	var loaded: Dictionary = store.read_attempt(scope.server_key, scope.owner, room_id, position)
	if not loaded.get("ok", false): return loaded
	return await _transport.call(HTTPClient.METHOD_POST, path(room_id, position), loaded.tagged, true)

## Asks the friend's phone (through the server) for an attempt this phone lacks.
func want(room_id: String, position: int) -> Dictionary:
	return await _transport.call(HTTPClient.METHOD_POST, path(room_id, position, "want"), {"schema_version": 1}, false)

## Before a fork or redo on a finished room whose last attempt left the server:
## sends it back from this phone. {ok:false, code:"history_missing"} when this phone
## lacks it; {mode:"v1_transferred"} when the room left through replay transfer v1.
func restore_final(room_id: String) -> Dictionary:
	if _busy: return {"ok": false, "status": 0, "code": "history_busy"}
	_busy = true
	var result := await _restore_final(room_id)
	_busy = false
	return result

func _restore_final(room_id: String) -> Dictionary:
	var scope: Dictionary = _eligibility.call(room_id)
	if not scope.get("ok", false): return {"ok": false, "status": 0, "code": "history_unavailable"}
	var listed := await list(room_id)
	if not listed.get("ok", false): return listed
	var view: Dictionary = listed.view
	if view.mode == "v1_transferred": return {"ok": true, "mode": "v1_transferred"}
	if view.attempts.is_empty(): return {"ok": false, "status": 0, "code": "history_missing"}
	var final: Dictionary = view.attempts.back()
	if final.state == "held": return {"ok": true, "mode": "attempts"}
	if not store.has(scope.server_key, scope.owner, room_id, int(final.position), final.link): return {"ok": false, "status": 0, "code": "history_missing"}
	var sent := await upload(room_id, scope, int(final.position))
	return {"ok": true, "mode": "attempts", "restored": true} if sent.get("ok", false) else sent

## Every completed pair of every attempt this phone keeps for the room, rebuilt
## from the stored bytes (for the Replays cache).
func local_pairs(server_key: String, owner: String, view: Dictionary) -> Array:
	var room: Dictionary = view.room
	var chapter := Registry.resolve(room)
	var result: Array = []
	for item: Dictionary in view.attempts:
		if not store.has(server_key, owner, room.room_id, int(item.position), item.link): continue
		for pair_id: String in item.pair_ids:
			var pair := local_pair(server_key, owner, room.room_id, chapter, pair_id)
			if not pair.is_empty(): result.append(pair)
	return result

## One completed pair of an attempt this phone keeps, rebuilt from the attempt's last
## checkpoint (which nests every stage once), or {} when this phone lacks it.
func local_pair(server_key: String, owner: String, room_id: String, chapter_key: String, pair_id: String) -> Dictionary:
	var found := RegEx.create_from_string("^p([0-9]{1,2})-([0-7])$").search(pair_id)
	if found == null: return {}
	var position := int(found.get_string(1))
	var stage := int(found.get_string(2))
	var loaded: Dictionary = store.read_attempt(server_key, owner, room_id, position)
	if not loaded.get("ok", false): return {}
	var blob: Variant = JSON.parse_string(loaded.bytes.get_string_from_utf8())
	if not blob is Dictionary or not blob.get("checkpoint") is Dictionary or not Save.equal(blob.get("room_id"), room_id): return {}
	var checkpoint: Dictionary = blob.checkpoint
	while int(checkpoint.get("stage_index", -1)) > stage + 1:
		checkpoint = Registry.previous_checkpoint(chapter_key, checkpoint)
		if checkpoint.is_empty(): return {}
	if int(checkpoint.get("stage_index", -1)) != stage + 1 or not checkpoint.get("proof") is Dictionary: return {}
	var proof: Dictionary = checkpoint.proof
	if not proof.get("a") is Dictionary or not proof.get("b") is Dictionary: return {}
	return {"pair_id": pair_id, "branch": position, "stage_index": stage, "a": proof.a.duplicate(true), "b": proof.b.duplicate(true), "checkpoint": checkpoint.duplicate(true)}
