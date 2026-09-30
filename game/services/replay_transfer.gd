extends RefCounted
## Completed replay transfers never mutate gameplay journals or delete local copies.
const Canonical = preload("res://core/v2/canonical.gd")
const Coordinator = preload("res://services/relay_room_coordinator.gd")
const Registry = preload("res://services/chapter_registry.gd")
const Collection = preload("res://services/shared_replay_collection.gd")
const Store = preload("res://services/shared_replay_store.gd")
const MAX_ARCHIVE_BYTES := 16 * 1024 * 1024
const MAX_INTEGER := 9007199254740991
const ROOM_KEYS := ["schema_version", "room_id", "revision", "branch", "stage_index", "level_id", "level_version", "definition_hash", "host_id", "guest_id", "checkpoint_hash", "a_turn_id", "completed_pair_ids", "invite_expires_at", "created_at", "updated_at"]
var last_code := ""
var _transport: Callable
var _identity: Callable
var _eligibility: Callable
var _store: RefCounted
var _busy := false
var _generation := 0
var _worker: Thread

func _init(transport: Callable, identity: Callable, eligibility: Callable, storage: RefCounted = null) -> void:
	_transport = transport
	_identity = identity
	_eligibility = eligibility
	_store = Store.new() if storage == null else storage

func busy() -> bool: return _busy or _worker != null

func invalidate_identity() -> void:
	_generation += 1
	_busy = false

func download(room_id: String) -> Dictionary:
	var ticket := _begin(room_id)
	if ticket.is_empty(): return _failure(last_code)
	var response := await _request(ticket, HTTPClient.METHOD_GET, "", {})
	if not response.get("ok", false): return _finish(ticket, response)
	var value: Variant = response.get("data").duplicate(true) if response.get("data") is Dictionary else null
	if not value is Dictionary or not _exact(value, ["schema_version", "manifest", "acked_player_ids", "transferred", "archive"]): return _finish(ticket, _failure("invalid_replay_transfer"))
	var transfer: Dictionary = value.duplicate()
	transfer.erase("archive")
	if not valid_transfer(transfer, ticket.owner, room_id): return _finish(ticket, _failure("invalid_replay_transfer"))
	var result: Dictionary
	if value.archive == null:
		result = await _load_verified(ticket, value.manifest)
	else:
		var checked := await _verify(ticket, value.archive, value.manifest)
		if not checked.get("ok", false): return _finish(ticket, checked)
		result = await _save_verified(ticket, value.manifest, value.archive)
	if not result.get("ok", false): return _finish(ticket, result)
	result["transferred"] = transfer.transferred
	result["acked_player_ids"] = transfer.acked_player_ids.duplicate()
	return _finish(ticket, result)

func local_archive(room_id: String, manifest: Dictionary) -> Dictionary:
	manifest = manifest.duplicate(true)
	var ticket := _begin(room_id)
	if ticket.is_empty(): return _failure(last_code)
	return _finish(ticket, await _load_verified(ticket, manifest))

func acknowledge(room_id: String, manifest: Dictionary) -> Dictionary:
	manifest = manifest.duplicate(true)
	var ticket := _begin(room_id)
	if ticket.is_empty(): return _failure(last_code)
	if not _current(ticket, true): return _finish(ticket, _failure("replay_ack_held"))
	var saved := await _load_verified(ticket, manifest)
	if not saved.get("ok", false): return _finish(ticket, saved)
	# The last admission check follows durable readback and native verification.
	if not _current(ticket, true): return _finish(ticket, _failure("replay_ack_held"))
	var response := await _request(ticket, HTTPClient.METHOD_POST, "/ack", _key(manifest), true)
	if not response.get("ok", false): return _finish(ticket, response)
	var value: Variant = response.get("data")
	if not valid_transfer(value, ticket.owner, room_id) or not Canonical.same(value.manifest, manifest) or ticket.owner not in value.acked_player_ids:
		return _finish(ticket, _failure("invalid_replay_ack"))
	return _finish(ticket, {"ok": true, "transfer": value.duplicate(true)})

func restore(room_id: String, manifest: Dictionary) -> Dictionary:
	manifest = manifest.duplicate(true)
	var ticket := _begin(room_id)
	if ticket.is_empty(): return _failure(last_code)
	var saved := await _load_verified(ticket, manifest)
	if not saved.get("ok", false): return _finish(ticket, saved)
	var body := _key(manifest)
	body["archive"] = saved.archive
	# An interrupted restore keeps the same epoch/hash. No new operation key or
	# guessed success is created; the exact server request is safe to repeat.
	var response := await _request(ticket, HTTPClient.METHOD_POST, "/restore", body)
	if not response.get("ok", false): return _finish(ticket, response)
	var value: Variant = response.get("data")
	if not value is Dictionary or not _exact(value, ["restored", "transfer"]) or value.restored != true or not valid_transfer(value.transfer, ticket.owner, room_id):
		return _finish(ticket, _failure("invalid_replay_restore"))
	var expected := manifest.duplicate(true)
	expected.epoch = int(manifest.epoch) + 1
	if not Canonical.same(value.transfer.manifest, expected) or value.transfer.transferred or not value.transfer.acked_player_ids.is_empty():
		return _finish(ticket, _failure("invalid_replay_restore"))
	var retained := await _save_verified(ticket, expected, saved.archive)
	if not retained.get("ok", false): return _finish(ticket, retained)
	retained["transfer"] = value.transfer.duplicate(true)
	return _finish(ticket, retained)

func _begin(room_id: String) -> Dictionary:
	if busy(): last_code = "replay_transfer_busy"; return {}
	if not _id(room_id) or not _identity.is_valid() or not _eligibility.is_valid(): last_code = "replay_transfer_unavailable"; return {}
	var identity: Variant = _identity.call()
	var scope: Variant = _eligibility.call(room_id)
	if not identity is Dictionary or identity.get("ready") != true or not _id(identity.get("player_id")) or not _integer(identity.get("epoch"), 0, MAX_INTEGER) or not _valid_scope(scope):
		last_code = "replay_transfer_unavailable"
		return {}
	_busy = true
	last_code = ""
	return {"owner": identity.player_id, "identity": identity.duplicate(true), "server_key": scope.server_key, "room": room_id, "generation": _generation}

func _current(ticket: Dictionary, acknowledgement: bool = false) -> bool:
	if ticket.get("generation") != _generation or not _identity.is_valid() or not _eligibility.is_valid() or not Canonical.same(ticket.identity, _identity.call()): return false
	var scope: Variant = _eligibility.call(ticket.room)
	if not _valid_scope(scope) or scope.server_key != ticket.server_key: return false
	return not acknowledgement or (scope.enabled and not scope.gameplay_pending and not scope.photo_pending and not scope.redo_pending)

static func _valid_scope(value: Variant) -> bool:
	if not value is Dictionary or value.get("ok") != true or value.get("standalone") != true or not _hash(value.get("server_key")): return false
	for name: String in ["gameplay_pending", "photo_pending", "redo_pending", "enabled"]:
		if not value.get(name) is bool: return false
	return true

func _request(ticket: Dictionary, method: int, suffix: String, body: Dictionary, acknowledgement: bool = false) -> Dictionary:
	if not _current(ticket, acknowledgement) or not _transport.is_valid(): return _failure("replay_transfer_context_changed")
	var value: Variant = await _transport.call({"owner_player_id": ticket.owner, "identity_epoch": ticket.identity.epoch, "method": method, "path": "/v2/rooms/" + ticket.room + "/replay-transfer" + suffix, "body": body.duplicate(true)})
	if not _current(ticket, acknowledgement): return _failure("replay_transfer_context_changed")
	return value if value is Dictionary else _failure("invalid_replay_transfer_response")

func _load_verified(ticket: Dictionary, manifest: Dictionary) -> Dictionary:
	if not _current(ticket) or not _manifest_valid(manifest, ticket.owner, ticket.room): return _failure("invalid_replay_manifest")
	var raw: bool = _store.get_script() == Store
	var stored: Dictionary = _store.capture_scope(_scope(ticket, manifest)) if raw else _store.load_scope(_scope(ticket, manifest))
	if not _current(ticket): return _failure("replay_transfer_context_changed")
	return await _run_validation(ticket, Callable(get_script(), "_verify_saved").bind(stored.duplicate(true), raw, manifest.duplicate(true), ticket.owner, ticket.room, ticket.server_key))

static func _verify_saved(source: Dictionary, raw: bool, manifest: Dictionary, owner: String, room_id: String, server_key: String) -> Dictionary:
	var stored: Dictionary = Store.decode_scope(source) if raw else source
	if not stored.get("ok", false) or not stored.get("found", false): return _failure("local_replay_archive_missing")
	var value: Variant = stored.get("value")
	if not value is Dictionary or not _exact(value, ["schema_version", "owner", "server_key", "manifest", "archive"]) or value.schema_version != 1 or value.owner != owner or value.server_key != server_key or not Canonical.same(value.manifest, manifest):
		return _failure("local_replay_archive_mismatch")
	var checked := verify_archive(value.archive, manifest, owner, room_id)
	if not checked.get("ok", false): return checked
	return {"ok": true, "manifest": manifest.duplicate(true), "archive": value.archive.duplicate(true), "entries": checked.entries}

func _save_verified(ticket: Dictionary, manifest: Dictionary, archive: Dictionary) -> Dictionary:
	if not _current(ticket): return _failure("replay_transfer_context_changed")
	var scope := _scope(ticket, manifest)
	var value := {"schema_version": 1, "owner": ticket.owner, "server_key": ticket.server_key, "manifest": manifest.duplicate(true), "archive": archive.duplicate(true)}
	var prior: Dictionary = _store.capture_scope(scope) if _store.get_script() == Store else _store.load_scope(scope)
	if not _current(ticket): return _failure("replay_transfer_context_changed")
	if not prior.get("ok", false): return _failure("local_replay_archive_unreadable")
	if prior.get("found", false):
		# The existing epoch is immutable. Verify its exact manifest and content
		# hash instead of overwriting a conflicting or unreadable generation.
		return await _load_verified(ticket, manifest)
	elif not _store.save_scope(scope, value): return _failure("local_replay_archive_unsaved")
	# Read the actual recoverable file, not the transport value or a write return.
	return await _load_verified(ticket, manifest)

func _verify(ticket: Dictionary, archive: Variant, manifest: Dictionary) -> Dictionary:
	var frozen: Variant = archive.duplicate(true) if archive is Dictionary else archive
	return await _run_validation(ticket, Callable(get_script(), "verify_archive").bind(frozen, manifest.duplicate(true), ticket.owner, ticket.room))

func _run_validation(ticket: Dictionary, callback: Callable) -> Dictionary:
	if not _current(ticket): return _failure("replay_transfer_context_changed")
	var loop := Engine.get_main_loop() as SceneTree
	if loop == null: return _failure("replay_validation_unavailable")
	_worker = Thread.new()
	if _worker.start(callback) != OK:
		_worker = null
		return _failure("replay_validation_unavailable")
	while _worker.is_alive(): await loop.process_frame
	var checked: Dictionary = _worker.wait_to_finish()
	_worker = null
	return checked if _current(ticket) else _failure("replay_transfer_context_changed")

func _finish(ticket: Dictionary, result: Dictionary) -> Dictionary:
	if ticket.generation == _generation:
		_busy = false
		last_code = "" if result.get("ok", false) else str(result.get("code", "replay_transfer_failed"))
	return result

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _worker != null and _worker.is_started(): _worker.wait_to_finish()

static func _scope(ticket: Dictionary, manifest: Dictionary) -> String:
	return "shared-replays:" + str(ticket.owner) + ":transfer:" + str(ticket.room) + ":" + str(int(manifest.epoch))

static func _key(manifest: Dictionary) -> Dictionary:
	return {"schema_version": 1, "epoch": manifest.epoch, "archive_hash": manifest.archive_hash}

static func valid_transfer(value: Variant, owner: String, room_id: String) -> bool:
	if not value is Dictionary or not _exact(value, ["schema_version", "manifest", "acked_player_ids", "transferred"]) or value.schema_version != 1 or not value.transferred is bool or not _manifest_valid(value.manifest, owner, room_id) or not value.acked_player_ids is Array: return false
	var members: Array = [value.manifest.room.host_id, value.manifest.room.guest_id]
	var expected: Array = members.filter(func(id: String): return id in value.acked_player_ids)
	return Canonical.same(value.acked_player_ids, expected) and value.transferred == (expected.size() == 2)

static func _manifest_valid(value: Variant, owner: String, room_id: String) -> bool:
	if not value is Dictionary or not _exact(value, ["schema_version", "epoch", "archive_hash", "room", "turns", "pairs"]) or value.schema_version != 1 or not _integer(value.epoch, 1, MAX_INTEGER) or not _hash(value.archive_hash) or not value.room is Dictionary: return false
	var room: Dictionary = value.room
	var fields := ROOM_KEYS.duplicate()
	if room.has("simulation_version"): fields.append("simulation_version")
	var chapter := Registry.resolve(room)
	if chapter.is_empty() or not _exact(room, fields) or room.schema_version != 2 or room.room_id != room_id or not _id(room_id) or not _id(room.host_id) or not _id(room.guest_id) or room.host_id == room.guest_id or owner not in [room.host_id, room.guest_id]: return false
	if not _integer(room.revision, 1, MAX_INTEGER) or not _integer(room.branch, 0, 31) or room.stage_index != 2 or room.a_turn_id != null or not _hash(room.checkpoint_hash): return false
	var level := Registry.definition(chapter)
	var rules: Variant = room.get("simulation_version", level.simulation_version)
	if not _integer(rules, 1, MAX_INTEGER) or int(rules) not in Registry.supported_rules(chapter): return false
	for name: String in ["created_at", "updated_at", "invite_expires_at"]:
		if not _timestamp(room[name]): return false
	if not value.turns is Array or value.turns.size() < 4 or value.turns.size() > 128 or not value.pairs is Array or value.pairs.size() < 2 or value.pairs.size() > 64: return false
	var turns: Dictionary = {}
	var revisions: Dictionary = {}
	for item: Variant in value.turns:
		if not item is Dictionary or not _exact(item, ["turn_id", "player_id", "accepted_revision", "recording_hash"]) or not Coordinator._pattern(item.turn_id, "^t([0-9]|[12][0-9]|3[01])-[01]-[ab]$") or turns.has(item.turn_id) or not _hash(item.recording_hash) or not _integer(item.accepted_revision, 1, int(room.revision)) or revisions.has(item.accepted_revision): return false
		var id: String = item.turn_id
		if int(id.substr(1).get_slice("-", 0)) > room.branch: return false
		var stage: Dictionary = level.stages[int(id.get_slice("-", 1))]
		var first: String = room.host_id if stage.first_player_slot == "p0" else room.guest_id
		var second: String = room.guest_id if first == room.host_id else room.host_id
		if item.player_id != (first if id.ends_with("-a") else second): return false
		turns[id] = item
		revisions[item.accepted_revision] = true
	var pairs: Dictionary = {}
	for item: Variant in value.pairs:
		if not item is Dictionary or not _exact(item, ["pair_id", "branch", "stage_index", "a_hash", "b_hash", "checkpoint_hash"]) or not _integer(item.branch, 0, int(room.branch)) or not _integer(item.stage_index, 0, 1) or item.pair_id != "p%d-%d" % [item.branch, item.stage_index] or pairs.has(item.pair_id) or not _hash(item.checkpoint_hash): return false
		var stem := "t%d-%d-" % [item.branch, item.stage_index]
		if turns.get(stem + "a", {}).get("recording_hash") != item.a_hash or turns.get(stem + "b", {}).get("recording_hash") != item.b_hash: return false
		if turns[stem + "a"].accepted_revision >= turns[stem + "b"].accepted_revision: return false
		pairs[item.pair_id] = item
	if not room.completed_pair_ids is Array or room.completed_pair_ids.size() != 2: return false
	for index in range(2):
		if not room.completed_pair_ids[index] is String or pairs.get(room.completed_pair_ids[index], {}).get("stage_index") != index: return false
	if pairs[room.completed_pair_ids[1]].branch != room.branch or pairs[room.completed_pair_ids[1]].checkpoint_hash != room.checkpoint_hash: return false
	for id: String in turns:
		var branch := int(id.substr(1).get_slice("-", 0))
		var index := int(id.get_slice("-", 1))
		var pair_id := "p%d-%d" % [branch, index]
		if branch == room.branch and room.completed_pair_ids[index] != pair_id: return false
		if id.ends_with("-b") and not pairs.has(pair_id): return false
	return true

static func verify_archive(archive: Variant, manifest: Dictionary, owner: String, room_id: String) -> Dictionary:
	# Pure worker: no files, identity observations, transport or shared writers.
	if not _manifest_valid(manifest, owner, room_id) or not Coordinator._bounded_nodes(archive, MAX_ARCHIVE_BYTES, 2000000) or not archive is Dictionary or not _exact(archive, ["schema_version", "room", "turns", "pairs"]) or archive.schema_version != 1 or not archive.room is Dictionary or not archive.turns is Array or not archive.pairs is Array: return _failure("invalid_replay_archive")
	if Canonical.digest(archive) != manifest.archive_hash or archive.turns.size() != manifest.turns.size() or archive.pairs.size() != manifest.pairs.size(): return _failure("replay_archive_mismatch")
	var room: Dictionary = archive.room
	var metadata := room.duplicate()
	var checkpoint: Variant = metadata.get("checkpoint")
	metadata.erase("checkpoint")
	metadata["checkpoint_hash"] = checkpoint.get("checkpoint_hash") if checkpoint is Dictionary else null
	if not Canonical.same(metadata, manifest.room): return _failure("replay_archive_mismatch")
	var chapter := Registry.resolve(room)
	var level := Registry.definition(chapter)
	var engine := Registry.simulation_script(chapter)
	var native_room := _metadata(room, chapter)
	var checkpoints: Dictionary = {}
	var checkpoint_context: Dictionary = {}
	var initial := Registry.initial_checkpoint(chapter)
	checkpoints[initial.checkpoint_hash] = initial
	var pairs: Dictionary = {}
	var turns: Dictionary = {}
	var output: Array = []
	for index in range(archive.turns.size()):
		var item: Variant = archive.turns[index]
		if not item is Dictionary or not _exact(item, ["turn_id", "player_id", "accepted_revision", "recording"]) or not item.recording is Dictionary: return _failure("invalid_replay_turn")
		var facts: Dictionary = item.duplicate()
		facts.erase("recording")
		facts["recording_hash"] = item.recording.get("recording_hash")
		if not Canonical.same(facts, manifest.turns[index]): return _failure("replay_archive_mismatch")
		turns[item.turn_id] = item
	for index in range(archive.pairs.size()):
		var pair: Variant = archive.pairs[index]
		if not pair is Dictionary or not _exact(pair, ["pair_id", "branch", "stage_index", "a", "b", "checkpoint"]) or not pair.a is Dictionary or not pair.b is Dictionary or not pair.checkpoint is Dictionary: return _failure("invalid_replay_pair")
		var facts := {"pair_id": pair.pair_id, "branch": pair.branch, "stage_index": pair.stage_index, "a_hash": pair.a.get("recording_hash"), "b_hash": pair.b.get("recording_hash"), "checkpoint_hash": pair.checkpoint.get("checkpoint_hash")}
		var entry := {"schema_version": 1, "room": native_room, "pair": pair}
		if not Canonical.same(facts, manifest.pairs[index]) or not Collection.verify_entry(entry, owner): return _failure("invalid_replay_pair")
		var stem := "t%d-%d-" % [pair.branch, pair.stage_index]
		if not Canonical.same(turns[stem + "a"].recording, pair.a) or not Canonical.same(turns[stem + "b"].recording, pair.b): return _failure("replay_archive_mismatch")
		if checkpoints.has(pair.checkpoint.checkpoint_hash) and not Canonical.same(checkpoints[pair.checkpoint.checkpoint_hash], pair.checkpoint): return _failure("replay_checkpoint_conflict")
		checkpoints[pair.checkpoint.checkpoint_hash] = pair.checkpoint
		if not checkpoint_context.has(pair.checkpoint.checkpoint_hash): checkpoint_context[pair.checkpoint.checkpoint_hash] = []
		checkpoint_context[pair.checkpoint.checkpoint_hash].append({"branch": pair.branch, "revision": turns[stem + "b"].accepted_revision})
		pairs[pair.pair_id] = pair
		output.append(entry.duplicate(true))
	if not Canonical.same(room.checkpoint, pairs[room.completed_pair_ids[1]].checkpoint) or not Canonical.same(pairs[room.completed_pair_ids[0]].checkpoint, Registry.previous_checkpoint(chapter, room.checkpoint)): return _failure("replay_checkpoint_conflict")
	for item: Dictionary in archive.turns:
		var record: Dictionary = item.recording
		var id: String = item.turn_id
		var stage_index := int(id.get_slice("-", 1))
		var role := id.get_slice("-", 2)
		var source: Variant = checkpoints.get(record.get("checkpoint_hash"))
		if not source is Dictionary or source.stage_index != stage_index or record.get("stage_id") != level.stages[stage_index].id or record.get("role") != role or record.get("simulation_version") != room.get("simulation_version", level.simulation_version): return _failure("invalid_replay_turn")
		if stage_index > 0:
			var branch := int(id.substr(1).get_slice("-", 0))
			var contexts: Array = checkpoint_context.get(record.checkpoint_hash, [])
			if not contexts.any(func(value: Dictionary): return value.branch <= branch and value.revision < item.accepted_revision): return _failure("invalid_replay_turn_history")
		var prior: Dictionary = {}
		if role == "b":
			var pair_id := "p" + id.substr(1).trim_suffix("-b")
			if not pairs.has(pair_id): return _failure("invalid_replay_turn")
			prior = turns[id.trim_suffix("-b") + "-a"].recording
		var checked: Dictionary = engine.verify_recording(level, record, source, prior)
		if not checked.get("valid", false) or not checked.get("snapshot", {}).get("can_commit", false): return _failure("invalid_replay_turn")
	return {"ok": true, "entries": output}

static func _metadata(room: Dictionary, chapter: String) -> Dictionary:
	return {"family": "chapter", "room_id": room.room_id, "host_id": room.host_id, "guest_id": room.guest_id, "chapter_key": chapter, "title": Registry.descriptor(chapter).title}

static func _timestamp(value: Variant) -> bool:
	if not Coordinator._pattern(value, "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\\.[0-9]{3}Z$"): return false
	var year := int(value.substr(0, 4))
	var month := int(value.substr(5, 2))
	var day := int(value.substr(8, 2))
	if month < 1 or month > 12 or int(value.substr(11, 2)) > 23 or int(value.substr(14, 2)) > 59 or int(value.substr(17, 2)) > 59: return false
	var days: Array = [31, 29 if year % 4 == 0 and (year % 100 != 0 or year % 400 == 0) else 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
	if day < 1 or day > int(days[month - 1]): return false
	var seconds := Time.get_unix_time_from_datetime_string(value.substr(0, 19))
	return Time.get_datetime_string_from_unix_time(seconds) == value.substr(0, 19)

static func _exact(value: Dictionary, keys: Array) -> bool: return Coordinator._exact(value, keys)
static func _id(value: Variant) -> bool: return Coordinator._token(value, 22)
static func _hash(value: Variant) -> bool: return Coordinator._pattern(value, "^[a-f0-9]{64}$")
static func _integer(value: Variant, low: int, high: int) -> bool: return Coordinator._range(value, low, high)
static func _failure(code: String) -> Dictionary: return {"ok": false, "code": code}
