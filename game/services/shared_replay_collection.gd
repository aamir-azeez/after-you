extends RefCounted
const PlayerCopy = preload("res://presentation/player_copy.gd")
const Reaper = preload("res://services/worker_reaper.gd")
## Participant-bound replay cache. All remote work is GET-only. The active room,
## lobby, pending request and rehearsal stores are never changed by this service.
const Store = preload("res://services/shared_replay_store.gd")
const OnlineStore = preload("res://services/relay_online_store.gd")
const Coordinator = preload("res://services/relay_room_coordinator.gd")
const Registry = preload("res://services/chapter_registry.gd")
const RoomChapterTitle = preload("res://services/room_chapter_title.gd")
const Levels = preload("res://core/levels.gd")
const LegacySimulation = preload("res://core/simulation.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const Keepsakes = preload("res://services/home_keepsakes.gd")
const KeepsakeCatalog = preload("res://services/home_keepsake_catalog.gd")
const LoadProgress = preload("res://services/replay_load_progress.gd")
const RoomStages = preload("res://services/room_stages.gd")
const Typed = preload("res://services/typed_values.gd")
const TurnTries = preload("res://services/turn_tries.gd")
const EndReactionStore = preload("res://services/end_reaction_store.gd")
const RunReactionStore = preload("res://services/run_reaction_store.gd")
const VERIFIED_PROOF_LIMIT := 256
static var _verified_proofs: Dictionary = {}
static var _verified_proof_mutex := Mutex.new()
var last_error := ""
## Room history: (room_id, chapter_key, pair_id) -> the pair from an attempt this
## phone keeps, or {}; and (room_id, position) -> asks the friend's phone for one.
var history_pair: Callable
var ask_for_attempt: Callable
## Whether the server lists a room's turn try counts (its capability); awaited.
## Unset reads as no.
var turn_tries_supported: Callable
## Whether the server lists a room's end-of-run reactions (its capability);
## awaited. Unset reads as no.
var end_reactions_supported: Callable
var _api: Node
var _identity: Callable
var _store: RefCounted
var _online: RefCounted
var _context_factory: RefCounted
var _context_required := false
var _context_generation := 0
var _owner := ""
var _epoch := -1
var _generation := 0
var _busy := false
var _rooms: Dictionary = {}
## Each room's last server update in Unix seconds, kept beside the index in
## its own scope so the index and the replay entries keep their exact shape.
var _times: Dictionary = {}
var _times_loaded := false
## Parts the server listed at the last check that this phone has not saved yet,
## by room key. They stay listed (to download) until saved or the identity changes.
var _remote_rows: Dictionary = {}
var _memories: Dictionary = {}
var _cache_hold := false
var _index_loaded := false
var _keepsake_failed_rooms: Dictionary = {}
var _keepsake_verified_rooms: Dictionary = {}
var _local_worker: Thread
var _local_job: Dictionary = {}
var _local_queue: Array[String] = []
var _local_verified: Dictionary = {}
var _local_total := 0
var _local_complete: Dictionary = {}
var _local_failed: Dictionary = {}
## Set when a finished local check changed what the library lists (a room, its
## rows or an error); taken by local_load_changed(). A room whose saved
## replays were already listed as they are changes nothing.
var _local_changed := false

class ReadSource extends RefCounted:
	var value: Dictionary
	func read(_scope_value: String) -> Dictionary: return value
	func reject(_scope_value: String, _value: Dictionary) -> Dictionary: return {"ok": false}
	var owner := ""
	func identity() -> Dictionary: return {"ready": true, "player_id": owner, "epoch": 1}

func _init(api: Node, identity: Callable, storage: RefCounted = null, online_storage: RefCounted = null, context_factory: RefCounted = null) -> void:
	_api = api
	_identity = identity
	_store = Store.new() if storage == null else storage
	_online = OnlineStore.new() if online_storage == null else online_storage
	_context_factory = context_factory
	_context_required = context_factory != null

func configure_context_factory(factory: RefCounted) -> void:
	if _context_required and _context_factory == factory: return
	_context_factory = factory
	_context_required = true
	# Retire only outstanding remote observations. Accepted local evidence and
	# keepsake verification remain owned by their original identity generation.
	_context_generation += 1

func invalidate_identity() -> void:
	_generation += 1
	_owner = ""
	_epoch = -1
	_rooms.clear()
	_times.clear()
	_times_loaded = false
	_remote_rows.clear()
	_memories.clear()
	_busy = false
	_cache_hold = false
	_index_loaded = false
	_keepsake_failed_rooms.clear()
	_keepsake_verified_rooms.clear()
	_local_queue.clear()
	_local_verified.clear()
	_local_total = 0
	_local_complete.clear()
	_local_failed.clear()
	_legacy_local_source.clear()

func busy() -> bool: return _busy or local_loading()

func local_loading() -> bool: return _local_worker != null or not _local_queue.is_empty()

## Whether the last finished local check changed anything listed, once.
func local_load_changed() -> bool:
	var changed := _local_changed
	_local_changed = false
	return changed

func local_progress() -> Dictionary:
	var value := {"active": false, "rooms_done": 0, "rooms_total": 0, "checked": 0, "total": 0, "phase": "waiting", "failed": false}
	var identity: Dictionary = _identity.call()
	if not identity.get("ready", false) or identity.get("player_id") != _owner or identity.get("epoch") != _epoch: return value
	value.merge({"active": local_loading(), "rooms_done": _local_complete.size(), "rooms_total": _local_total, "failed": not _local_failed.is_empty()}, true)
	if _local_job.get("owner") == _owner and _local_job.get("epoch") == _epoch and _local_job.get("generation") == _generation and _local_job.get("progress") is RefCounted:
		value.merge(_local_job.progress.snapshot(), true)
	elif not value.active: value.phase = "failed" if value.failed else "complete"
	return value

func _finish_local_progress(key: String) -> void:
	_local_failed.erase(key)
	_local_complete[key] = true

func begin_local_load(legacy_room: Dictionary = {}) -> bool:
	_index_loaded = false
	if not _ready_owner(): return false
	if local_loading() and (_local_job.is_empty() or (_local_job.owner == _owner and _local_job.epoch == _epoch and _local_job.generation == _generation)): return false
	_local_complete.clear()
	_local_failed.clear()
	# Index metadata is enough to draw the first screen. Replay validation is
	# performed one room at a time on an isolated worker, with no transport.
	var lobby: Dictionary = _online.load_scope("relay-lobby-v2:" + _owner)
	var value: Variant = lobby.get("value")
	if lobby.get("ok", false) and lobby.get("found", false) and value is Dictionary and Typed.equal(value.get("owner_player_id"), _owner) and value.get("room_ids") is Array and value.room_ids.size() <= 128:
		for room_id: Variant in value.room_ids:
			if _id(room_id) and not _local_queue.has("chapter:" + room_id): _local_queue.append("chapter:" + room_id)
	for key: String in _rooms:
		if not _local_queue.has(key) and not _memories.has(key): _local_queue.append(key)
	if not legacy_room.is_empty() and _remember_room(legacy_room, "legacy", true, false):
		var key := "legacy:" + str(legacy_room.room_id)
		if not _local_queue.has(key): _local_queue.append(key)
		# The legacy source is already a private local value; verify it with the
		# cache on the worker rather than replaying its inputs during menu setup.
		_local_verified.erase(key)
		_legacy_local_source[key] = legacy_room.duplicate(true)
	_local_total = _local_queue.size()
	return true

var _legacy_local_source: Dictionary = {}

func advance_local_load() -> bool:
	if _local_worker != null:
		if _local_worker.is_alive(): return false
		var result: Dictionary = _local_worker.wait_to_finish()
		var job := _local_job
		_local_worker = null
		_local_job = {}
		var listed_error := last_error
		var listed_rooms := _rooms.size()
		var finished := _advance_finished_room(job, result)
		if last_error != listed_error or _rooms.size() != listed_rooms: _local_changed = true
		return finished
	if _local_queue.is_empty() or not _ready_owner(): return false

	var key: String = _local_queue.pop_front()
	var online_raw: bool = _online.get_script() == OnlineStore
	var scope := "relay-room-v2:" + _owner + ":" + key.substr(8)
	var journal: Dictionary = (_online.capture_scope(scope) if online_raw else _online.load_scope(scope)) if key.begins_with("chapter:") else {"ok": true, "found": false}
	var cached: Dictionary = _store.capture_scope(_scope(key)) if _store.get_script() == Store else _store.load_scope(_scope(key))
	_local_job = {"owner": _owner, "epoch": _epoch, "generation": _generation, "key": key, "journal": journal, "cached": cached, "raw": _store.get_script() == Store, "online_raw": online_raw and key.begins_with("chapter:"), "verified": _local_verified.get(key, ""), "legacy": _legacy_local_source.get(key, {})}
	_local_job.progress = LoadProgress.new()
	# Joined before this library is freed: polled when done, or in PREDELETE
	# from its own fields (never through a self method there).
	_local_worker = Thread.new()
	if _local_worker.start(Callable(get_script(), "_verify_local_room").bind(_local_job)) != OK:
		_local_worker = null
		_local_job = {}
		_local_failed[key] = true
		_error(PlayerCopy.SHARED_REPLAY_COLLECTION_358437D8CCC9)
		_local_changed = true
		return true
	return false

## The finished path of a local room check. True: a step finished.
func _advance_finished_room(job: Dictionary, result: Dictionary) -> bool:
	if not _ready_owner(false) or job.owner != _owner or job.epoch != _epoch or job.generation != _generation: return true
	_local_failed[job.key] = true
	if not result.get("ok", false):
		_error(PlayerCopy.SHARED_REPLAY_COLLECTION_358437D8CCC9)
		return true
	# A second collection can save while this worker is running. Never
	# replace a newer generation with the captured one; rescan it instead.
	if job.raw and _store.capture_scope(_scope(job.key)) != job.cached:
		if not _local_queue.has(job.key): _local_queue.append(job.key)
		_local_failed.erase(job.key)
		return true
	if result.get("unchanged", false):
		if _memories.has(job.key) and not _filter_removed(job.key, _memories[job.key]): return true
		_finish_local_progress(job.key)
		return true
	# Index writes can also come from another live collection. Reload this
	# small metadata file before merging a newly discovered room into it.
	_index_loaded = false
	if not _ready_owner(): return true
	var room: Dictionary = result.get("room", {})
	if not room.is_empty() and not _remember_room(room, "chapter" if str(job.key).begins_with("chapter:") else "legacy", true, false): return true
	var key: String = job.key
	if not _rooms.has(key):
		_finish_local_progress(key)
		return true
	var merged: Dictionary = result.entries
	for entry: Dictionary in merged.values():
		if not _same_members(entry.room, _rooms[key]) or entry.room.family != _rooms[key].family or entry.room.chapter_key != _rooms[key].chapter_key: return true
	# A receipt or another local consumer may have added a newer cache row.
	for id: String in _memories.get(key, {}):
		if merged.has(id) and not Typed.same(merged[id], _memories[key][id]):
			_error(PlayerCopy.SHARED_REPLAY_COLLECTION_A8680E064CEB)
			return true
		merged[id] = _memories[key][id]
	if merged.size() > 65: return true
	if not _filter_removed(key, merged): return true
	if result.changed and not _store.save_scope(_scope(key), {"schema_version": 1, "owner": _owner, "entries": merged}):
		_error(PlayerCopy.SHARED_REPLAY_COLLECTION_4ACE7DB17681)
		return true
	if result.changed or not _memories.has(key) or _ids(_memories[key]) != _ids(merged): _local_changed = true
	_memories[key] = merged
	_local_verified[key] = result.signature
	_finish_local_progress(key)
	return true

static func _ids(entries: Dictionary) -> Array:
	var ids := entries.keys()
	ids.sort()
	return ids

static func _verify_local_room(job: Dictionary) -> Dictionary:
	# This worker only receives private values. It cannot read identity, perform
	# HTTP requests, award keepsakes or write any gameplay/replay file.
	var progress: RefCounted = job.get("progress")
	if progress != null: progress.set_phase("reading")
	var signature := _local_fingerprint(job)
	if job.verified == signature: return {"ok": true, "unchanged": true}
	var journal: Dictionary = OnlineStore.decode_scope(job.journal) if job.online_raw else job.journal
	if not journal.get("ok", false): return {"ok": false}
	var cached: Dictionary = Store.decode_scope(job.cached) if job.raw else job.cached
	var value: Variant = cached.get("value") if cached.get("found", false) else {"schema_version": 1, "owner": job.owner, "entries": {}}
	if not cached.get("ok", false) or not value is Dictionary or value.size() != 3 or not Typed.equal(value.get("schema_version"), 1) or not Typed.equal(value.get("owner"), job.owner) or not value.get("entries") is Dictionary or value.entries.size() > 65: return {"ok": false}
	var entries: Dictionary = value.entries
	if progress != null:
		progress.set_total(entries.size() + 1)
		progress.set_phase("entries")
	for id: Variant in entries:
		var entry: Variant = entries[id]
		if not entry is Dictionary or not verify_entry(entry, job.owner) or _room_key(entry.room) != job.key or str(id) != summary(entry).id: return {"ok": false}
		if progress != null: progress.advance()
	if progress != null: progress.set_phase("journal")
	var room: Dictionary = {}
	var changed := false
	if journal.get("found", false):
		var source := ReadSource.new()
		source.owner = job.owner
		source.value = journal
		var checker := Coordinator.new(Callable(), source.read, source.reject, source.identity)
		if not checker.bind_room(str(job.key).substr(8)): return {"ok": false}
		room = checker.snapshot()
		if not room.is_empty():
			var chapter := Registry.resolve(room)
			var metadata := {"family": "chapter", "room_id": room.room_id, "host_id": room.host_id, "guest_id": room.guest_id, "chapter_key": chapter, "title": RoomChapterTitle.title(chapter)}
			var checkpoint: Dictionary = room.checkpoint
			for index in range(room.completed_pair_ids.size() - 1, -1, -1):
				var proof: Dictionary = checkpoint.proof
				var id: String = room.completed_pair_ids[index]
				var pair := {"pair_id": id, "branch": int(id.substr(1).get_slice("-", 0)), "stage_index": index, "a": proof.a, "b": proof.b, "checkpoint": checkpoint}
				var entry := {"schema_version": 1, "room": metadata, "pair": pair}
				if entries.has(id) and not Typed.same(entries[id], entry): return {"ok": false}
				changed = changed or not entries.has(id)
				entries[id] = entry
				checkpoint = Registry.previous_checkpoint(chapter, checkpoint)
	elif not job.legacy.is_empty():
		room = job.legacy
		if Typed.equal(room.get("active_role"), "complete") and room.get("recordings") is Dictionary:
			var metadata := {"family": "legacy", "room_id": room.room_id, "host_id": room.host_id, "guest_id": room.guest_id, "chapter_key": "", "title": "Earlier islands"}
			var pair := {"attempt": room.get("attempt"), "level_id": room.get("level_id"), "first_player_id": room.get("first_player_id"), "a": room.recordings.get("a"), "b": room.recordings.get("b")}
			var entry := {"schema_version": 1, "room": metadata, "pair": pair}
			if not verify_entry(entry, job.owner): return {"ok": false}
			var id: String = summary(entry).id
			if entries.has(id) and not Typed.same(entries[id], entry): return {"ok": false}
			changed = not entries.has(id)
			entries[id] = entry
	if entries.size() <= 65 and progress != null:
		progress.advance()
		progress.set_phase("ready")
	return {"ok": entries.size() <= 65, "room": room, "entries": entries, "changed": changed, "signature": signature}

static func _local_fingerprint(job: Dictionary) -> String:
	# Retain digests, not another set of every room's raw save generations.
	var parts: PackedStringArray = [Canonical.digest(job.legacy)]
	for name: String in ["cached", "journal"]:
		var source: Dictionary = job[name]
		if source.has("raw"):
			parts.append(str(source.get("ok", false)))
			for bytes: PackedByteArray in source.raw:
				var hash := HashingContext.new()
				hash.start(HashingContext.HASH_SHA256)
				hash.update(bytes)
				parts.append(hash.finish().hex_encode())
		else: parts.append(Canonical.digest(source))
	return "|".join(parts).sha256_text()

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _local_worker != null and _local_worker.is_started():
		_local_worker.wait_to_finish()

func _ready_owner(load_index: bool = true) -> bool:
	var identity: Dictionary = _identity.call()
	if not identity.get("ready", false) or not _id(identity.get("player_id")): return false
	if _owner != identity.player_id or _epoch != int(identity.get("epoch", -1)):
		invalidate_identity()
		_owner = identity.player_id
		_epoch = int(identity.epoch)
	if _cache_hold: return false
	if not load_index or _index_loaded: return true
	var saved: Dictionary = _store.load_scope(_scope("index"))
	if not saved.get("ok", false): return _hold(PlayerCopy.SHARED_REPLAY_COLLECTION_56EB8B13F662)
	if saved.get("found", false):
		var value: Variant = saved.get("value")
		if not value is Dictionary or value.size() != 3 or not Typed.equal(value.get("schema_version"), 1) or not Typed.equal(value.get("owner"), _owner) or not value.get("rooms") is Dictionary or value.rooms.size() > 256:
			return _hold(PlayerCopy.SHARED_REPLAY_COLLECTION_B8854381546B)
		for key: Variant in value.rooms:
			if not key is String or not _valid_room(value.rooms[key], _owner) or key != _room_key(value.rooms[key]): return _hold(PlayerCopy.SHARED_REPLAY_COLLECTION_62B26750A2CB)
		_rooms = value.rooms.duplicate(true)
	_index_loaded = true
	return true

func rooms() -> Array:
	if not _ready_owner(): return []
	var values: Array = _rooms.values().duplicate(true)
	values.sort_custom(func(a: Dictionary, b: Dictionary): return (str(a.title) + a.room_id) < (str(b.title) + b.room_id))
	return values

## When the room last changed on the server (a finished room: when it finished),
## in Unix seconds, or 0 when this phone never saw it.
func updated_at(room: Dictionary) -> int:
	if not _ready_owner() or not _load_times(): return 0
	return int(_times.get(_room_key(room), 0))

func _load_times() -> bool:
	if _times_loaded: return true
	var saved: Dictionary = _store.load_scope(_scope("times"))
	if not saved.get("ok", false): return false
	_times_loaded = true
	var value: Variant = saved.get("value")
	if not saved.get("found", false) or not value is Dictionary or not Typed.equal(value.get("schema_version"), 1) or not Typed.equal(value.get("owner"), _owner) or not value.get("times") is Dictionary or value.times.size() > 256: return true
	for key: Variant in value.times:
		var at: Variant = value.times[key]
		if key is String and key.length() <= 40 and (at is int or at is float) and is_finite(at) and at > 0: _times[key] = int(at)
	return true

func _remember_time(key: String, snapshot: Dictionary) -> void:
	var at: Variant = snapshot.get("updated_at")
	if not at is String or at.length() < 19 or at.length() > 40 or not _load_times(): return
	var seconds := int(Time.get_unix_time_from_datetime_string(at.substr(0, 19)))
	if seconds <= int(_times.get(key, 0)): return
	var next := _times.duplicate()
	next[key] = seconds
	while next.size() > 256: next.erase(next.keys()[0])
	if _store.save_scope(_scope("times"), {"schema_version": 1, "owner": _owner, "times": next}): _times = next

func load_saved(legacy_room: Dictionary = {}) -> bool:
	if not _ready_owner(): return false
	if not legacy_room.is_empty(): _remember_room(legacy_room, "legacy")
	var lobby: Dictionary = _online.load_scope("relay-lobby-v2:" + _owner)
	if lobby.get("ok", false) and lobby.get("found", false):
		var value: Variant = lobby.get("value")
		if value is Dictionary and Typed.equal(value.get("owner_player_id"), _owner) and value.get("room_ids") is Array and value.room_ids.size() <= 128:
			for room_id: Variant in value.room_ids:
				if not _id(room_id): continue
				var coordinator := Coordinator.new(Callable(), _online.load_scope, _reject_game_save, _identity)
				if coordinator.bind_room(room_id):
					var snapshot: Dictionary = coordinator.snapshot()
					if not snapshot.is_empty(): _remember_room(snapshot, "chapter", true)
	return true

func refresh_rooms() -> bool:
	if not _ready_owner(): return false
	var generation := _generation
	var complete := true
	for family: String in ["legacy", "chapter"]:
		var response := await _request_get("/v1/rooms" if family == "legacy" else "/v2/rooms")
		if generation != _generation: return false
		if not response.get("ok", false): complete = false; continue
		var data: Variant = response.get("data")
		var values: Variant = data.get("rooms") if data is Dictionary else null
		if not values is Array or values.size() > 128: complete = false; _error(PlayerCopy.SHARED_REPLAY_COLLECTION_6599B5A786DB); continue
		for value: Variant in values:
			if not value is Dictionary or not _remember_room(value, family): complete = false
	return complete

func memories(room_key: String, cached_only: bool = false) -> Array:
	if not _ready_owner() or not _rooms.has(room_key): return []
	if cached_only and not _memories.has(room_key): return []
	if not _load_memories(room_key): return []
	var rows: Array = []
	for entry: Dictionary in _memories[room_key].values():
		rows.append(summary(entry, true))
	rows.sort_custom(func(a: Dictionary, b: Dictionary): return a.id < b.id)
	return rows

## Every part of one finished run of the chapter, first stage first: the
## newest final pair and, one stage back at a time, the single cached pair
## whose checkpoint it nests. [] when any part is missing or ambiguous.
func local_sequence(room_key: String) -> Array:
	if not _ready_owner() or not _memories.has(room_key) or not _load_memories(room_key): return []
	var values: Array = _memories[room_key].values()
	var endings: Array = values.filter(func(value: Dictionary): return value.room.family == "chapter" and int(value.pair.stage_index) == RoomStages.count(Registry.definition(str(value.room.chapter_key))) - 1)
	endings.sort_custom(func(a: Dictionary, b: Dictionary): return a.pair.branch > b.pair.branch)
	for last: Dictionary in endings:
		var sequence: Array = [last.duplicate(true)]
		var current: Dictionary = last
		while int(current.pair.stage_index) > 0:
			var previous := Registry.previous_checkpoint(last.room.chapter_key, current.pair.checkpoint)
			var later: Dictionary = current
			var matches: Array = values.filter(func(value: Dictionary): return value.room == last.room and int(value.pair.stage_index) == int(later.pair.stage_index) - 1 and value.pair.branch <= later.pair.branch and Typed.same(value.pair.checkpoint, previous))
			# Do not guess which fork's photo belongs to an ambiguous ancestor.
			if matches.size() != 1: break
			current = matches[0]
			sequence.push_front(current.duplicate(true))
		if int(current.pair.stage_index) == 0: return sequence
	return []

func local_entries(room_key: String) -> Array:
	if not _ready_owner() or not _memories.has(room_key) or not _load_memories(room_key): return []
	var entries: Array = _memories[room_key].values()
	return entries.duplicate(true)

# Only the durable transfer helper supplies this callback, after native archive
# verification. Match every pair to the manifest and retain conflicting history.
func cache_transferred_entries(room_id: String, entries: Array, manifest: Dictionary) -> bool:
	_index_loaded = false
	if not _ready_owner() or local_loading() or not _id(room_id) or not manifest.get("room") is Dictionary or manifest.room.get("room_id") != room_id or _owner not in [manifest.room.get("host_id"), manifest.room.get("guest_id")] or not manifest.get("pairs") is Array or entries.size() != manifest.pairs.size() or entries.size() > 64: return false
	var owner := _owner
	var epoch := _epoch
	var chapter := Registry.resolve(manifest.room)
	if entries.size() < maxi(1, RoomStages.count(Registry.definition(chapter))): return false
	var key := "chapter:" + room_id
	var next: Dictionary = {}
	if not manifest.pairs.all(func(value: Variant): return value is Dictionary): return false
	for entry: Variant in entries:
		if not entry is Dictionary or not entry.get("room") is Dictionary or not entry.get("pair") is Dictionary or _room_key(entry.room) != key or not _same_members(entry.room, manifest.room) or entry.room.get("chapter_key") != chapter: return false
		var pair: Dictionary = entry.pair
		var id: String = str(pair.get("pair_id", ""))
		if not _pair_id(id) or next.has(id): return false
		var matches: Array = manifest.pairs.filter(func(value: Dictionary): return value.get("pair_id") == id)
		if matches.size() != 1: return false
		var expected: Dictionary = matches[0]
		if pair.get("branch") != expected.get("branch") or pair.get("stage_index") != expected.get("stage_index") or pair.get("a", {}).get("recording_hash") != expected.get("a_hash") or pair.get("b", {}).get("recording_hash") != expected.get("b_hash") or pair.get("checkpoint", {}).get("checkpoint_hash") != expected.get("checkpoint_hash"): return false
		next[id] = entry.duplicate(true)
	var loaded: Dictionary = _store.load_scope(_scope(key))
	if not loaded.get("ok", false): return false
	if loaded.get("found", false):
		var existing: Variant = loaded.get("value")
		if not existing is Dictionary or not Typed.equal(existing.get("schema_version"), 1) or not Typed.equal(existing.get("owner"), owner) or not existing.get("entries") is Dictionary: return false
		for id: Variant in existing.entries:
			if not next.has(id) or not Typed.same(next[id], existing.entries[id]): return false
	if not _remember_room(manifest.room, "chapter", true, false): return false
	# The complete durable transfer archive remains intact. Collection removal
	# only excludes a selected replay from this phone's browsing cache.
	if not _filter_removed(key, next): return false
	var value := {"schema_version": 1, "owner": owner, "entries": next}
	if not _store.save_scope(_scope(key), value): return false
	var readback: Dictionary = _store.load_scope(_scope(key))
	if not _ready_owner(false) or owner != _owner or epoch != _epoch or not readback.get("ok", false) or not readback.get("found", false) or not Typed.same(readback.get("value"), value): return false
	_memories[key] = next
	_local_verified.erase(key)
	return true

## Room history: parts rebuilt from attempts this phone keeps join the room's
## replays, each checked natively first exactly like a downloaded part. Parts
## already cached stay; a part that does not match its cached copy is refused.
func cache_history_pairs(facts: Dictionary, pairs: Array) -> bool:
	if pairs.is_empty() or pairs.size() > 64: return pairs.is_empty()
	if not _ready_owner() or local_loading() or not _id(str(facts.get("room_id", ""))) or facts.get("guest_id") == null or _owner not in [facts.get("host_id"), facts.get("guest_id")]: return false
	var owner := _owner
	var generation := _generation
	if not _remember_room(facts, "chapter", true, false): return false
	var room: Dictionary = _rooms.get("chapter:" + str(facts.room_id), {})
	if room.is_empty(): return false
	for pair: Variant in pairs:
		if not pair is Dictionary: return false
		var entry := {"schema_version": 1, "room": room.duplicate(true), "pair": pair.duplicate(true)}
		var proven: bool = await _verify_on_worker(entry, owner)
		if generation != _generation or owner != _owner: return false
		if not proven: return _error(PlayerCopy.SHARED_REPLAY_COLLECTION_021757D055C8)
		if not _cache(entry): return false
	return true

func keepsake_backfill_snapshot(retry_failed: bool = false) -> Dictionary:
	# Capture bounded immutable evidence on the main thread. Native simulation
	# verification happens in the keepsake worker; this method never mutates a
	# gameplay journal or downloads anything.
	var raw_store: bool = _store.get_script() == Store
	if not _ready_owner(not raw_store): return {"ok": false, "ids": [], "pending": false, "source": {}}
	if not _index_loaded:
		var captured: Dictionary = _store.capture_scope(_scope("index"))
		if not captured.get("ok", false):
			_hold(PlayerCopy.SHARED_REPLAY_COLLECTION_56EB8B13F662)
			return {"ok": false, "ids": [], "pending": false, "source": {}}
		return {"ok": true, "ids": [], "pending": true, "source": {"kind": "friend", "owner": _owner, "epoch": _epoch, "generation": _generation, "target": "index", "raw_scope": captured}}
	if retry_failed: _keepsake_failed_rooms.clear()
	var ids: Array[String] = []
	var source: Dictionary = {}
	var pending := false
	var read_one := false
	var okay := true
	for key: String in _rooms:
		if _memories.has(key):
			for entry: Dictionary in _memories[key].values():
				for id: String in _keepsake_places(entry):
					if not ids.has(id): ids.append(id)
			continue
		if _keepsake_verified_rooms.has(key):
			for id: String in _keepsake_verified_rooms[key]:
				if not ids.has(id): ids.append(id)
			continue
		if _keepsake_failed_rooms.has(key):
			okay = false
			continue
		if read_one:
			pending = true
			continue
		read_one = true
		if raw_store:
			var captured: Dictionary = _store.capture_scope(_scope(key))
			if not captured.get("ok", false):
				_keepsake_failed_rooms[key] = true
				okay = false
				continue
			source = {"kind": "friend", "owner": _owner, "epoch": _epoch, "generation": _generation, "room_key": key, "raw_scope": captured}
			pending = true
			continue
		var loaded: Dictionary = _store.load_scope(_scope(key))
		var value: Variant = loaded.get("value") if loaded.get("found", false) else {"schema_version": 1, "owner": _owner, "entries": {}}
		if not loaded.get("ok", false) or not value is Dictionary or value.size() != 3 or not Typed.equal(value.get("schema_version"), 1) or not Typed.equal(value.get("owner"), _owner) or not value.get("entries") is Dictionary or value.entries.size() > 65:
			_keepsake_failed_rooms[key] = true
			okay = false
			continue
		source = {"kind": "friend", "owner": _owner, "epoch": _epoch, "generation": _generation, "room_key": key, "entries": value.entries.duplicate(true)}
		pending = true
	return {"ok": okay, "ids": ids, "pending": pending, "source": source}

func accept_keepsake_result(source: Dictionary, result: Dictionary) -> bool:
	# Identity changes discard worker results. Only public IDs are retained; do
	# not replace a replay cache that may have gained new entries while working.
	if not _ready_owner(false) or source.get("owner") != _owner or source.get("epoch") != _epoch or source.get("generation") != _generation: return false
	if source.get("target") == "index":
		# A regular collection operation may already have loaded a newer index.
		# Never overwrite it with a worker's older snapshot.
		if _index_loaded: return true
		if not result.get("ok", false): return _hold(PlayerCopy.SHARED_REPLAY_COLLECTION_56EB8B13F662)
		_rooms = result.rooms
		_index_loaded = true
		return true
	if not _rooms.has(source.get("room_key")): return false
	if not result.get("ok", false):
		_keepsake_failed_rooms[source.room_key] = true
		return false
	_keepsake_verified_rooms[source.room_key] = result.ids.duplicate()
	return true

func cache_accepted_receipt(evidence: Dictionary) -> bool:
	# Called by the coordinator only after its exact server receipt is durably
	# saved. A newer fork may have retired this older completed proof already.
	if not _ready_owner() or evidence.get("owner") != _owner or evidence.get("epoch") != _epoch or not evidence.get("origin") is Dictionary or not evidence.get("receipt") is Dictionary or not evidence.get("pair") is Dictionary: return false
	var origin: Dictionary = evidence.origin
	var receipt: Dictionary = evidence.receipt
	var pair: Dictionary = evidence.pair
	if receipt.get("operation") != "turns" or receipt.get("room_id") != origin.get("room_id") or receipt.get("pair_id") != pair.get("pair_id") or receipt.get("branch") != pair.get("branch") or receipt.get("stage_index") != pair.get("stage_index") or not pair.get("b") is Dictionary or receipt.get("recording_hash") != pair.b.get("recording_hash") or not pair.get("checkpoint") is Dictionary or receipt.get("checkpoint_hash") != pair.checkpoint.get("checkpoint_hash"): return false
	if not _remember_room(origin, "chapter"): return false
	var key := "chapter:" + str(origin.room_id)
	return _cache({"schema_version": 1, "room": _rooms[key].duplicate(true), "pair": pair.duplicate(true)})

static func verify_keepsake_snapshot(source: Dictionary) -> Dictionary:
	# Worker-only pure validation: no identity calls, cache writes or account I/O.
	var entries: Dictionary = {}
	if source.has("raw_scope"):
		var loaded := Store.decode_scope(source.raw_scope)
		if not loaded.get("ok", false): return {"ok": false, "ids": []}
		var field := "rooms" if source.get("target") == "index" else "entries"
		var value: Variant = loaded.get("value") if loaded.get("found", false) else {"schema_version": 1, "owner": source.owner, field: {}}
		if not value is Dictionary or value.size() != 3 or not Typed.equal(value.get("schema_version"), 1) or not Typed.equal(value.get("owner"), source.owner) or not value.get(field) is Dictionary or value[field].size() > (256 if field == "rooms" else 65): return {"ok": false, "ids": []}
		if field == "rooms":
			for key: Variant in value.rooms:
				if not key is String or not _valid_room(value.rooms[key], source.owner) or key != _room_key(value.rooms[key]): return {"ok": false, "ids": []}
			return {"ok": true, "ids": [], "rooms": value.rooms}
		entries = value.entries
	else:
		entries = source.entries
	var ids: Array[String] = []
	for id: Variant in entries:
		var entry: Variant = entries[id]
		if not entry is Dictionary or not verify_entry(entry, source.owner) or _room_key(entry.room) != source.room_key or str(id) != summary(entry).id: return {"ok": false, "ids": []}
		for place: String in _keepsake_places(entry):
			if not ids.has(place): ids.append(place)
	return {"ok": true, "ids": ids}

func refresh_memories(room_key: String) -> Array:
	var generation := _generation
	var rows := await _refresh_memory_rows(room_key)
	if generation == _generation and not rows.is_empty() and _rooms.has(room_key) and _rooms[room_key].family == "chapter": await _refresh_turn_tries(_rooms[room_key], rows)
	if generation == _generation and not rows.is_empty() and _rooms.has(room_key) and _rooms[room_key].family == "chapter": await _refresh_end_reactions(_rooms[room_key], rows)
	return rows

func _refresh_memory_rows(room_key: String) -> Array:
	if not _ready_owner() or not _rooms.has(room_key): return []
	var room: Dictionary = _rooms[room_key]
	var generation := _generation
	var response := await _request_get(_room_path(room) + "/collection", str(room.room_id) if room.family == "chapter" else "")
	if generation != _generation: return []
	if not response.get("ok", false): return memories(room_key)
	var data: Variant = response.get("data")
	var values: Variant = data.get("islands" if room.family == "legacy" else "pairs") if data is Dictionary else null
	if not values is Array or values.size() > 65:
		_error(PlayerCopy.SHARED_REPLAY_COLLECTION_A28F454EF942)
		return memories(room_key)
	if room.family == "legacy":
		for value: Variant in values:
			if value is Dictionary and Typed.equal(value.get("room_id"), room.room_id) and _same_members(value, room):
				_cache_legacy(value, room)
		return memories(room_key)
	var rows := memories(room_key)
	var removed := _read_removals(room_key)
	if not removed.get("ok", false): return []
	for value: Variant in values:
		if not value is Dictionary or not _pair_id(value.get("pair_id")) or not _hash(value.get("a_hash")) or not _hash(value.get("b_hash")) or not _hash(value.get("checkpoint_hash")) or not Typed.equal(value.get("stage_index"), int(str(value.pair_id).get_slice("-", 1))) or not Typed.equal(value.get("branch"), int(str(value.pair_id).substr(1).get_slice("-", 0))):
			_error(PlayerCopy.SHARED_REPLAY_COLLECTION_9D9E39D6BA85)
			return memories(room_key)
		if _removed_summary(removed.entries, str(value.pair_id), value): continue
		var found := false
		for row: Dictionary in rows:
			if row.id == value.pair_id:
				found = true
				if row.a_hash != value.a_hash or row.b_hash != value.b_hash: _error(PlayerCopy.SHARED_REPLAY_COLLECTION_97C97316B16C)
		if not found:
			var row: Dictionary = value.duplicate(true)
			row.id = row.pair_id
			row.title = _stage_title(room.chapter_key, int(row.stage_index))
			row.cached = false
			rows.append(row)
	_remote_rows[room_key] = rows.filter(func(row: Dictionary) -> bool: return not row.get("cached", true))
	return rows

## Every part to list for a room: the saved ones, then the ones the last server
## check found that are not saved yet, in part order.
func listed(room_key: String) -> Array:
	var rows := memories(room_key, true)
	var saved := {}
	for row: Dictionary in rows: saved[row.id] = true
	for row: Dictionary in _remote_rows.get(room_key, []):
		if not saved.has(row.id): rows.append(row.duplicate(true))
	rows.sort_custom(func(a: Dictionary, b: Dictionary): return a.id < b.id)
	return rows

func open_memory(room_key: String, memory_id: String, expected: Dictionary = {}) -> Dictionary:
	if not _ready_owner() or not _rooms.has(room_key) or not _load_memories(room_key): return {}
	if _memories[room_key].has(memory_id):
		var cached: Dictionary = _memories[room_key][memory_id]
		# Every insertion into this private cache has already replay-verified the
		# inputs. Navigation returns a copy.
		if cached.room.family == "chapter" and not _matches_summary(cached.pair, expected):
			_error(PlayerCopy.SHARED_REPLAY_COLLECTION_DEC15671DC42); return {}
		return cached.duplicate(true)
	var room: Dictionary = _rooms[room_key]
	if room.family != "chapter" or not _pair_id(memory_id): return {}
	var removed := _read_removals(room_key)
	if not removed.get("ok", false) or (removed.entries.has(memory_id) and (expected.is_empty() or _removed_summary(removed.entries, memory_id, expected))): return {}
	var generation := _generation
	var response := await _request_get(_room_path(room) + "/pairs/" + memory_id, str(room.room_id))
	if generation != _generation: return {}
	if not response.get("ok", false) and response.get("status") == 410 and response.get("code") == "history_offloaded":
		# The server keeps only this part's hashes now. Play it from this phone's copy,
		# checked below exactly like a downloaded part, or ask the friend's phone for it.
		var kept: Dictionary = history_pair.call(str(room.room_id), str(room.chapter_key), memory_id) if history_pair.is_valid() else {}
		if kept.is_empty():
			if ask_for_attempt.is_valid(): await ask_for_attempt.call(str(room.room_id), int(memory_id.substr(1).get_slice("-", 0)))
			if generation != _generation: return {}
			_error(PlayerCopy.SHARED_REPLAY_ON_FRIENDS_PHONE); return {}
		response = {"ok": true, "data": kept}
	if not response.get("ok", false): return {}
	var pair: Variant = response.get("data")
	if not pair is Dictionary or not Typed.equal(pair.get("pair_id"), memory_id): return {}
	var entry := {"schema_version": 1, "room": room.duplicate(true), "pair": pair.duplicate(true)}
	var proven: bool = await _verify_on_worker(entry, _owner)
	if generation != _generation: return {}
	if not proven: _error(PlayerCopy.SHARED_REPLAY_COLLECTION_021757D055C8); return {}
	if not _matches_summary(pair, expected):
		_error(PlayerCopy.SHARED_REPLAY_COLLECTION_DEC15671DC42); return {}
	if not _cache(entry): return {}
	return _memories.get(room_key, {}).get(memory_id, {}).duplicate(true)

func _remember_room(snapshot: Dictionary, family: String, verified: bool = false, cache_pairs: bool = true) -> bool:
	if family == "chapter" and not verified:
		var checker := Coordinator.new(Callable(), func(_scope_value: String): return {"ok": true, "found": false}, _reject_game_save, _identity)
		if not checker.bind_room(str(snapshot.get("room_id", ""))) or not checker._valid_snapshot(snapshot): return _error(PlayerCopy.SHARED_REPLAY_COLLECTION_6AC2E1B2141C)
	var room := {"family": family, "room_id": snapshot.get("room_id"), "host_id": snapshot.get("host_id"), "guest_id": snapshot.get("guest_id"), "chapter_key": Registry.resolve(snapshot) if family == "chapter" else "", "title": RoomChapterTitle.title(Registry.resolve(snapshot), "Shared chapter") if family == "chapter" else "Earlier islands"}
	if not _valid_room(room, _owner): return false
	var key := _room_key(room)
	if _rooms.has(key) and (_rooms[key].host_id != room.host_id or _rooms[key].chapter_key != room.chapter_key or (_rooms[key].guest_id != null and _rooms[key].guest_id != room.guest_id)): return _error(PlayerCopy.SHARED_REPLAY_COLLECTION_B198911049D6)
	if not _rooms.has(key) and _rooms.size() >= 256: return _error(PlayerCopy.SHARED_REPLAY_COLLECTION_84B86110B572)
	var next := _rooms.duplicate(true)
	next[key] = room
	if not Typed.same(next, _rooms) and not _store.save_scope(_scope("index"), {"schema_version": 1, "owner": _owner, "rooms": next}): return _error(PlayerCopy.SHARED_REPLAY_COLLECTION_E2EA0728968C)
	_rooms = next
	_remember_time(key, snapshot)
	if not cache_pairs: return true
	if family == "legacy":
		_cache_legacy(snapshot, room)
	elif not snapshot.get("completed_pair_ids", []).is_empty():
		var checkpoint: Dictionary = snapshot.checkpoint
		for index in range(snapshot.completed_pair_ids.size() - 1, -1, -1):
			var proof: Dictionary = checkpoint.proof
			var id: String = snapshot.completed_pair_ids[index]
			var pair := {"pair_id": id, "branch": int(id.substr(1).get_slice("-", 0)), "stage_index": index, "a": proof.a.duplicate(true), "b": proof.b.duplicate(true), "checkpoint": checkpoint.duplicate(true)}
			_cache({"schema_version": 1, "room": room, "pair": pair})
			checkpoint = Registry.previous_checkpoint(room.chapter_key, checkpoint)
	return true

func _cache_legacy(snapshot: Dictionary, room: Dictionary) -> void:
	if not Typed.equal(snapshot.get("active_role"), "complete") or not snapshot.get("recordings") is Dictionary: return
	var pair := {"attempt": snapshot.get("attempt"), "level_id": snapshot.get("level_id"), "first_player_id": snapshot.get("first_player_id"), "a": snapshot.recordings.get("a"), "b": snapshot.recordings.get("b")}
	_cache({"schema_version": 1, "room": room, "pair": pair})

func _load_memories(key: String) -> bool:
	if _memories.has(key): return _filter_removed(key, _memories[key])
	var loaded: Dictionary = _store.load_scope(_scope(key))
	if not loaded.get("ok", false): return _error(PlayerCopy.SHARED_REPLAY_COLLECTION_443522A1FE1C)
	var value: Variant = loaded.get("value") if loaded.get("found", false) else {"schema_version": 1, "owner": _owner, "entries": {}}
	if not value is Dictionary or value.size() != 3 or not Typed.equal(value.get("schema_version"), 1) or not Typed.equal(value.get("owner"), _owner) or not value.get("entries") is Dictionary or value.entries.size() > 65: return _error(PlayerCopy.SHARED_REPLAY_COLLECTION_E4268D68D7C0)
	for id: Variant in value.entries:
		var entry: Variant = value.entries[id]
		if not entry is Dictionary or not verify_entry(entry, _owner) or _room_key(entry.room) != key or str(id) != summary(entry).id: return _error(PlayerCopy.SHARED_REPLAY_COLLECTION_358437D8CCC9)
	var retained: Dictionary = value.entries.duplicate(true)
	if not _filter_removed(key, retained): return false
	_memories[key] = retained
	return true

func _cache(entry: Dictionary) -> bool:
	if not verify_entry(entry, _owner): return false
	var key := _room_key(entry.room)
	if not _load_memories(key): return false
	var id: String = summary(entry).id
	var removed := _read_removals(key)
	if not removed.get("ok", false): return false
	if _entry_removed(removed.entries, id, entry): return true
	if _memories[key].has(id):
		if not Typed.same(_memories[key][id], entry): return _error(PlayerCopy.SHARED_REPLAY_COLLECTION_A8680E064CEB)
		_remember_keepsake(entry)
		return true
	if _memories[key].size() >= 65: return _error(PlayerCopy.SHARED_REPLAY_COLLECTION_E45145AF7D59)
	var next: Dictionary = _memories[key].duplicate(true)
	next[id] = entry.duplicate(true)
	if not _store.save_scope(_scope(key), {"schema_version": 1, "owner": _owner, "entries": next}): return _error(PlayerCopy.SHARED_REPLAY_COLLECTION_4ACE7DB17681)
	_memories[key] = next
	_remember_keepsake(entry)
	return true

# Removal markers affect only this owner's collection. They never modify the
# gameplay checkpoint, complete transfer archive, photos or partner's copy.
func remove_memory(key: String, id: String, expected_entry: Dictionary) -> bool:
	if not _ready_owner() or not _rooms.has(key) or not verify_entry(expected_entry, _owner) or _room_key(expected_entry.room) != key or str(summary(expected_entry).id) != id: return false
	var removed := _read_removals(key)
	if not removed.get("ok", false): return false
	if _entry_removed(removed.entries, id, expected_entry): return true
	if not _load_memories(key) or not Typed.same(_memories[key].get(id), expected_entry): return false
	var next: Dictionary = removed.entries.duplicate(true)
	if not next.has(id) and next.size() >= 65: return _error(PlayerCopy.SHARED_REPLAY_COLLECTION_E45145AF7D59)
	var marker := {"entry_hash": _removal_hash(expected_entry)}
	if expected_entry.room.family == "chapter":
		marker["a_hash"] = expected_entry.pair.a.recording_hash
		marker["b_hash"] = expected_entry.pair.b.recording_hash
		marker["checkpoint_hash"] = expected_entry.pair.checkpoint.checkpoint_hash
	next[id] = marker
	var owner := _owner
	var epoch := _epoch
	var value := {"schema_version": 1, "owner": owner, "entries": next}
	if not _store.save_scope(_scope("removed:" + key), value): return _error(PlayerCopy.SHARED_REPLAY_COLLECTION_4ACE7DB17681)
	var confirmed := _read_removals(key)
	if not _ready_owner(false) or owner != _owner or epoch != _epoch or not confirmed.get("ok", false) or not Typed.same(confirmed.entries, next): return false
	# Retire captured GET/worker/keepsake results, without destroying the retained
	# thread or touching any room journal. Old work is drained by its normal path.
	_generation += 1
	_busy = false
	_memories[key].erase(id)
	_local_verified.erase(key)
	# The confirmed marker is authoritative even if pruning the redundant
	# browsing cache fails. Full transfer/gameplay recovery data is separate.
	_prune_removed_cache(key, owner, epoch)
	if not _ready_owner(false) or owner != _owner or epoch != _epoch: return false
	last_error = ""
	return true

func _prune_removed_cache(key: String, owner: String, epoch: int) -> void:
	# Another collection may have persisted a newer fork since this instance
	# loaded its RAM cache. Only prune freshly read, fully valid disk contents.
	var loaded: Dictionary = _store.load_scope(_scope(key))
	if not _ready_owner(false) or owner != _owner or epoch != _epoch or not loaded.get("ok", false) or not loaded.get("found", false): return
	var value: Variant = loaded.get("value")
	if not value is Dictionary or value.size() != 3 or not Typed.equal(value.get("schema_version"), 1) or not Typed.equal(value.get("owner"), owner) or not value.get("entries") is Dictionary or value.entries.size() > 65: return
	for id: Variant in value.entries:
		var entry: Variant = value.entries[id]
		if not entry is Dictionary or not verify_entry(entry, owner) or _room_key(entry.room) != key or str(id) != summary(entry).id: return
	var retained: Dictionary = value.entries.duplicate(true)
	if not _filter_removed(key, retained): return
	if not _ready_owner(false) or owner != _owner or epoch != _epoch: return
	if not _store.save_scope(_scope(key), {"schema_version": 1, "owner": owner, "entries": retained}): return
	if _ready_owner(false) and owner == _owner and epoch == _epoch: _memories[key] = retained

func _read_removals(key: String) -> Dictionary:
	if not _ready_owner(false) or not Store._scope_valid(_scope("removed:" + key)): return {"ok": false}
	var owner := _owner
	var epoch := _epoch
	var loaded: Dictionary = _store.load_scope(_scope("removed:" + key))
	if not _ready_owner(false) or owner != _owner or epoch != _epoch: return {"ok": false}
	var value: Variant = loaded.get("value") if loaded.get("found", false) else {"schema_version": 1, "owner": owner, "entries": {}}
	var valid: bool = loaded.get("ok", false) and value is Dictionary and value.size() == 3 and Typed.equal(value.get("schema_version"), 1) and Typed.equal(value.get("owner"), owner) and value.get("entries") is Dictionary and value.entries.size() <= 65
	if valid:
		for id: Variant in value.entries:
			var marker: Variant = value.entries[id]
			var chapter := key.begins_with("chapter:")
			var keys: Array = ["entry_hash", "a_hash", "b_hash", "checkpoint_hash"] if chapter else ["entry_hash"]
			if not id is String or not (_pair_id(id) if chapter else Coordinator._pattern(id, "^a[0-9]{1,7}$")) or not marker is Dictionary or not Coordinator._exact(marker, keys): valid = false; break
			for field: String in keys:
				if not _hash(marker[field]): valid = false; break
			if not valid: break
	if not valid:
		_hold(PlayerCopy.SHARED_REPLAY_COLLECTION_443522A1FE1C)
		return {"ok": false}
	return {"ok": true, "entries": value.entries}

func _filter_removed(key: String, entries: Dictionary) -> bool:
	var removed := _read_removals(key)
	if not removed.get("ok", false): return false
	for id: String in entries.keys():
		if _entry_removed(removed.entries, id, entries[id]): entries.erase(id)
	return true

static func _entry_removed(markers: Dictionary, id: String, entry: Dictionary) -> bool:
	return markers.has(id) and markers[id].entry_hash == _removal_hash(entry)

static func _removal_hash(entry: Dictionary) -> String:
	# A display-title refresh must not restore the same participant-bound proof.
	var room: Dictionary = entry.room.duplicate(true)
	room.erase("title")
	return Canonical.digest({"schema_version": entry.schema_version, "room": room, "pair": entry.pair})

static func _removed_summary(markers: Dictionary, id: String, row: Dictionary) -> bool:
	if not markers.has(id): return false
	var marker: Dictionary = markers[id]
	return marker.get("a_hash") == row.get("a_hash") and marker.get("b_hash") == row.get("b_hash") and marker.get("checkpoint_hash") == row.get("checkpoint_hash")

static func _keepsake_places(entry: Dictionary) -> Array[String]:
	if entry.room.family == "legacy": return ["earlier/" + str(entry.pair.level_id)]
	# Native verification includes the earlier proof chain, so an archived final
	# pair can restore its whole accepted prefix even if earlier cache rows expired.
	var places := KeepsakeCatalog.chapter_places(entry.room.chapter_key)
	return places.slice(0, int(entry.pair.stage_index) + 1)

static func _remember_keepsake(entry: Dictionary) -> void:
	if entry.room.family == "legacy":
		Keepsakes.record_legacy_friend(str(entry.pair.level_id))
	else:
		Keepsakes.record_friend_prefix(entry.room.chapter_key, int(entry.pair.stage_index) + 1)

## Both players' try counts for the room's turns, kept on this phone by
## recording hash. The server keeps them for every attempt, offloaded or moved
## to the phones too, so they are read even when the room's list is not. A
## room is read again only when its parts changed since the last read.
## Nothing is said when the read fails; Replays then shows no counts.
func _refresh_turn_tries(room: Dictionary, rows: Array) -> void:
	var covered := _parts_covered(rows)
	var counts := TurnTries.new()
	if not counts.read_wanted(str(room.room_id), covered): return
	if not turn_tries_supported.is_valid() or not await turn_tries_supported.call(): return
	var response := await _request_get(_room_path(room) + "/tries", str(room.room_id), true)
	var data: Variant = response.get("data") if response.get("ok", false) else null
	if data is Dictionary and Typed.equal(data.get("schema_version"), 1.0) and data.get("tries") is Dictionary and data.tries.size() <= 128:
		counts.remember(data.tries, str(room.room_id), covered)

## Both players' end-of-run faces for the room's turns, kept on this phone by
## recording hash (services/end_reaction_store.gd), read the way try counts
## are: only with the capability, again only when the room's parts changed,
## and quietly; Replays then shows the faces it already has. The same read
## brings every turn's reactions made during the run, when the server has them
## (services/run_reaction_store.gd), so a replay plays them.
func _refresh_end_reactions(room: Dictionary, rows: Array) -> void:
	var covered := _parts_covered(rows)
	var faces := EndReactionStore.new()
	if not faces.read_wanted(str(room.room_id), covered): return
	if not end_reactions_supported.is_valid() or not await end_reactions_supported.call(): return
	var response := await _request_get(_room_path(room) + "/end-reactions", str(room.room_id), true)
	var data: Variant = response.get("data") if response.get("ok", false) else null
	if data is Dictionary and Typed.equal(data.get("schema_version"), 1.0) and data.get("faces") is Dictionary and data.faces.size() <= EndReactionStore.MAX_LISTED:
		# rooms_api.gd takes them out of the reply, beside it.
		RunReactionStore.new().note(response.get("run_reactions"))
		faces.remember(data.faces, str(room.room_id), covered)

## What a room's parts are, as one short string that changes when a turn is added.
static func _parts_covered(rows: Array) -> String:
	var parts: Array[String] = []
	for row: Dictionary in rows: parts.append("%s:%s:%s" % [row.get("id", ""), row.get("a_hash", ""), row.get("b_hash", "")])
	parts.sort()
	return ",".join(parts).sha256_text()

func _request_get(path: String, chapter_room_id: String = "", quiet: bool = false) -> Dictionary:
	# A room history pass still out goes first; this read takes the next turn in the one request queue.
	if not _ready_owner() or _busy or _api.player_id != _owner: return {"ok": false}
	var generation := _generation
	var context_generation := _context_generation
	var context: RefCounted
	if not chapter_room_id.is_empty() and _context_required:
		if not _id(chapter_room_id) or _context_factory == null or not _context_factory.has_method("current") or not _context_factory.current() or not _context_factory.has_method("for_room"): return _context_hold()
		var resolved: Variant = _context_factory.for_room(chapter_room_id, "replay")
		context = resolved if resolved is RefCounted else null
		if context == null or not context.has_method("current") or not context.current() or not context.has_method("request"): return _context_hold()
	_busy = true
	var response: Dictionary
	if context != null:
		response = await context.request({"owner_player_id": _owner, "identity_epoch": _epoch, "method": HTTPClient.METHOD_GET, "path": path, "body": {}})
	else:
		response = await _api.request_json(HTTPClient.METHOD_GET, path, {}, func() -> bool: return generation == _generation and context_generation == _context_generation)
	if generation != _generation: return {"ok": false}
	_busy = false
	if context_generation != _context_generation or (context != null and not context.current()): return _context_hold()
	var owner: Dictionary = _identity.call()
	if not owner.get("ready", false) or owner.get("player_id") != _owner or int(owner.get("epoch", -1)) != _epoch:
		invalidate_identity(); return {"ok": false}
	if response.get("ignored", false): return _context_hold()
	if not response.get("ok", false) and not quiet: _error(PlayerCopy.SHARED_REPLAY_COLLECTION_790E8697F4D2)
	return response

func _context_hold() -> Dictionary:
	_error(PlayerCopy.SHARED_REPLAY_COLLECTION_790E8697F4D2)
	return {"ok": false, "ignored": true, "status": 0, "code": "campaign_context_changed"}

func _scope(key: String) -> String: return "shared-replays:" + _owner + ":" + key
func _error(message: String) -> bool: last_error = message; return false
func _hold(message: String) -> bool: _cache_hold = true; return _error(message)
func _reject_game_save(_scope_value: String, _value: Dictionary) -> Dictionary: return {"ok": false}
static func _room_key(room: Dictionary) -> String: return str(room.family) + ":" + str(room.room_id)
static func _room_path(room: Dictionary) -> String: return ("/v2/rooms/" if room.family == "chapter" else "/v1/rooms/") + str(room.room_id)
static func _same_members(a: Dictionary, b: Dictionary) -> bool: return Typed.equal(a.get("host_id"), b.get("host_id")) and Typed.equal(a.get("guest_id"), b.get("guest_id"))
static func _matches_summary(pair: Dictionary, expected: Dictionary) -> bool:
	return expected.is_empty() or (expected.get("a_hash") == pair.a.recording_hash and expected.get("b_hash") == pair.b.recording_hash and expected.get("checkpoint_hash") == pair.checkpoint.checkpoint_hash)
static func _id(value: Variant) -> bool: return Coordinator._token(value, 22)
static func _hash(value: Variant) -> bool: return Coordinator._pattern(value, "^[a-f0-9]{64}$")
static func _pair_id(value: Variant) -> bool: return Coordinator._pattern(value, "^p([0-9]|[12][0-9]|3[01])-" + RoomStages.DIGIT + "$")
static func _valid_room(room: Variant, owner: String) -> bool:
	return room is Dictionary and room.size() == 6 and room.get("family") in ["legacy", "chapter"] and _id(room.get("room_id")) and _id(room.get("host_id")) and (room.get("guest_id") == null or (_id(room.get("guest_id")) and room.guest_id != room.host_id)) and owner in [room.host_id, room.guest_id] and room.get("title") is String and room.title.length() <= 80 and (Typed.equal(room.get("chapter_key"), "") if room.family == "legacy" else not Registry.descriptor(str(room.get("chapter_key", ""))).is_empty())

## verify_entry on a worker, for a part just downloaded: its replay check took
## seconds in one frame (a Turn of the Tide stage, 2-5 s on a desktop). Same
## verdict; a success is remembered as verify_entry remembers it, so the cache
## check that follows does not replay it again. Frames keep drawing meanwhile.
static func _verify_on_worker(entry: Dictionary, owner: String) -> bool:
	return await Reaper.run(Callable(load("res://services/shared_replay_collection.gd"), "verify_entry").bind(entry.duplicate(true), owner), true) == true

static func verify_entry(entry: Variant, owner: String) -> bool:
	if not Coordinator._pair_bounded(entry) or not entry is Dictionary or entry.size() != 3 or not Typed.equal(entry.get("schema_version"), 1) or not _valid_room(entry.get("room"), owner) or not entry.get("pair") is Dictionary or entry.room.guest_id == null: return false
	var pair: Dictionary = entry.pair
	if not pair.get("a") is Dictionary or not pair.get("b") is Dictionary or not Typed.equal(pair.a.get("role"), "a") or not Typed.equal(pair.b.get("role"), "b"): return false
	# The library worker and viewer receive copies of the same immutable proof.
	# Remember only a successful native check of its complete typed contents,
	# never a claimed recording hash, current permission or saved-file identity.
	var key := _entry_proof_key(entry, owner)
	_verified_proof_mutex.lock()
	var verified := _verified_proofs.has(key)
	if verified:
		_verified_proofs.erase(key)
		_verified_proofs[key] = true
	_verified_proof_mutex.unlock()
	if verified: return true
	if not _verify_entry_proof(entry): return false
	_verified_proof_mutex.lock()
	_verified_proofs.erase(key)
	_verified_proofs[key] = true
	while _verified_proofs.size() > VERIFIED_PROOF_LIMIT:
		_verified_proofs.erase(_verified_proofs.keys()[0])
	_verified_proof_mutex.unlock()
	return true

static func _entry_proof_key(entry: Dictionary, owner: String) -> String:
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(var_to_bytes(entry))
	return owner + ":" + hash.finish().hex_encode()

static func _verify_entry_proof(entry: Dictionary) -> bool:
	var pair: Dictionary = entry.pair
	if entry.room.family == "chapter":
		if pair.size() != 6 or not _pair_id(pair.get("pair_id")) or not Typed.equal(pair.get("branch"), int(pair.pair_id.substr(1).get_slice("-", 0))) or not Typed.equal(pair.get("stage_index"), int(pair.pair_id.get_slice("-", 1))) or not pair.get("checkpoint") is Dictionary: return false
		var start := Registry.previous_checkpoint(entry.room.chapter_key, pair.checkpoint)
		if start.is_empty(): return false
		var engine: Script = Registry.simulation_script(entry.room.chapter_key)
		var checked: Dictionary = engine.derive_checkpoint(Registry.definition(entry.room.chapter_key), start, pair.a, pair.b)
		return checked.get("valid", false) and Typed.same(checked.get("checkpoint"), pair.checkpoint) and int(pair.checkpoint.stage_index) == int(pair.stage_index) + 1
	if pair.size() != 5 or not Coordinator._range(pair.get("attempt"), 0, 1000000) or pair.get("first_player_id") not in [entry.room.host_id, entry.room.guest_id]: return false
	var level := Levels.get_level(str(pair.get("level_id", "")))
	if level.is_empty(): return false
	var checked: Dictionary = LegacySimulation.verify_recording(level, pair.b, pair.a)
	return checked.get("valid", false) and checked.get("snapshot", {}).get("can_commit", false)

static func summary(entry: Dictionary, cached: bool = true) -> Dictionary:
	var pair: Dictionary = entry.pair
	if entry.room.family == "legacy": return {"id": "a%d" % int(pair.attempt), "title": RoomChapterTitle.legacy_title(pair.level_id), "cached": cached}
	return {"id": pair.pair_id, "title": _stage_title(entry.room.chapter_key, int(pair.stage_index)), "stage_index": pair.stage_index, "a_hash": pair.a.recording_hash, "b_hash": pair.b.recording_hash, "checkpoint_hash": pair.checkpoint.checkpoint_hash, "cached": cached}

static func _stage_title(key: String, index: int) -> String:
	var definition := Registry.definition(key)
	if index < 0 or index >= definition.stages.size(): return "Saved stage"
	var stage: Dictionary = definition.stages[index]
	# A stage without its own title (the Lighthouse's) is named by the registry.
	return "%d · %s" % [index + 1, str(stage.get("title", Registry.stage_presentation(key, stage).get("title", stage.id)))]

static func photo_turns(entry: Dictionary, owner: String) -> Array:
	if entry.room.family != "chapter" or not verify_entry(entry, owner): return []
	return _verified_photo_turns(entry, owner)

static func _verified_photo_turns(entry: Dictionary, owner: String) -> Array:
	# Internal view path: its frozen sequence was native-verified on a worker.
	if entry.room.family != "chapter": return []
	var result: Array = []
	for role: String in ["a", "b"]:
		var record: Dictionary = entry.pair[role]
		var player: String = entry.room.host_id if record.player_slot == "p0" else entry.room.guest_id
		result.append({"room_id": entry.room.room_id, "turn_id": "t" + entry.pair.pair_id.substr(1) + "-" + role, "recording_hash": record.recording_hash, "owner_player_id": player, "own": player == owner, "role": role, "player_slot": record.player_slot})
	return result
