extends RefCounted
## Participant-bound replay cache. All remote work is GET-only. The active room,
## lobby, pending request and rehearsal stores are never changed by this service.
const Store = preload("res://services/shared_replay_store.gd")
const OnlineStore = preload("res://services/relay_online_store.gd")
const Coordinator = preload("res://services/relay_room_coordinator.gd")
const Registry = preload("res://services/chapter_registry.gd")
const Levels = preload("res://core/levels.gd")
const LegacySimulation = preload("res://core/simulation.gd")
const Canonical = preload("res://core/v2/canonical.gd")
var last_error := ""
var _api: Node
var _identity: Callable
var _store: RefCounted
var _online: RefCounted
var _owner := ""
var _epoch := -1
var _generation := 0
var _busy := false
var _rooms: Dictionary = {}
var _memories: Dictionary = {}
var _cache_hold := false

func _init(api: Node, identity: Callable, storage: RefCounted = null, online_storage: RefCounted = null) -> void:
	_api = api
	_identity = identity
	_store = Store.new() if storage == null else storage
	_online = OnlineStore.new() if online_storage == null else online_storage

func invalidate_identity() -> void:
	_generation += 1
	_owner = ""
	_epoch = -1
	_rooms.clear()
	_memories.clear()
	_busy = false
	_cache_hold = false

func busy() -> bool: return _busy

func _ready_owner() -> bool:
	var identity: Dictionary = _identity.call()
	if not identity.get("ready", false) or not _id(identity.get("player_id")): return false
	if _owner == identity.player_id and _epoch == int(identity.get("epoch", -1)): return not _cache_hold
	invalidate_identity()
	_owner = identity.player_id
	_epoch = int(identity.epoch)
	var saved: Dictionary = _store.load_scope(_scope("index"))
	if not saved.get("ok", false): return _hold("Your saved replay list could not be read. Nothing was replaced.")
	if saved.get("found", false):
		var value: Variant = saved.get("value")
		if not value is Dictionary or value.size() != 3 or value.get("schema_version") != 1 or value.get("owner") != _owner or not value.get("rooms") is Dictionary or value.rooms.size() > 256:
			return _hold("The saved replay list needs a compatible app.")
		for key: Variant in value.rooms:
			if not key is String or not _valid_room(value.rooms[key], _owner) or key != _room_key(value.rooms[key]): return _hold("The saved replay list could not be verified.")
		_rooms = value.rooms.duplicate(true)
	return true

func rooms() -> Array:
	if not _ready_owner(): return []
	var values: Array = _rooms.values().duplicate(true)
	values.sort_custom(func(a: Dictionary, b: Dictionary): return (str(a.title) + a.room_id) < (str(b.title) + b.room_id))
	return values

func load_saved(legacy_room: Dictionary = {}) -> bool:
	if not _ready_owner(): return false
	if not legacy_room.is_empty(): _remember_room(legacy_room, "legacy")
	var lobby: Dictionary = _online.load_scope("relay-lobby-v2:" + _owner)
	if lobby.get("ok", false) and lobby.get("found", false):
		var value: Variant = lobby.get("value")
		if value is Dictionary and value.get("owner_player_id") == _owner and value.get("room_ids") is Array and value.room_ids.size() <= 128:
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
		if not values is Array or values.size() > 128: complete = false; _error("The shared room list was not understood."); continue
		for value: Variant in values:
			if not value is Dictionary or not _remember_room(value, family): complete = false
	return complete

func memories(room_key: String) -> Array:
	if not _ready_owner() or not _rooms.has(room_key) or not _load_memories(room_key): return []
	var rows: Array = []
	for entry: Dictionary in _memories[room_key].values():
		rows.append(summary(entry, true))
	rows.sort_custom(func(a: Dictionary, b: Dictionary): return a.id < b.id)
	return rows

func refresh_memories(room_key: String) -> Array:
	if not _ready_owner() or not _rooms.has(room_key): return []
	var room: Dictionary = _rooms[room_key]
	var generation := _generation
	var response := await _request_get(_room_path(room) + "/collection")
	if generation != _generation: return []
	if not response.get("ok", false): return memories(room_key)
	var data: Variant = response.get("data")
	var values: Variant = data.get("islands" if room.family == "legacy" else "pairs") if data is Dictionary else null
	if not values is Array or values.size() > 65:
		_error("The shared memory list was not understood.")
		return memories(room_key)
	if room.family == "legacy":
		for value: Variant in values:
			if value is Dictionary and value.get("room_id") == room.room_id and _same_members(value, room):
				_cache_legacy(value, room)
		return memories(room_key)
	var rows := memories(room_key)
	for value: Variant in values:
		if not value is Dictionary or not _pair_id(value.get("pair_id")) or not _hash(value.get("a_hash")) or not _hash(value.get("b_hash")) or not _hash(value.get("checkpoint_hash")) or value.get("stage_index") != int(str(value.pair_id).get_slice("-", 1)) or value.get("branch") != int(str(value.pair_id).substr(1).get_slice("-", 0)):
			_error("The shared memory list could not be verified.")
			return memories(room_key)
		var found := false
		for row: Dictionary in rows:
			if row.id == value.pair_id:
				found = true
				if row.a_hash != value.a_hash or row.b_hash != value.b_hash: _error("A saved memory changed unexpectedly; its local copy was preserved.")
		if not found:
			var row: Dictionary = value.duplicate(true)
			row.id = row.pair_id
			row.title = _stage_title(room.chapter_key, int(row.stage_index))
			row.cached = false
			rows.append(row)
	return rows

func open_memory(room_key: String, memory_id: String, expected: Dictionary = {}) -> Dictionary:
	if not _ready_owner() or not _rooms.has(room_key) or not _load_memories(room_key): return {}
	if _memories[room_key].has(memory_id):
		var cached: Dictionary = _memories[room_key][memory_id]
		if verify_entry(cached, _owner):
			if cached.room.family == "chapter" and not _matches_summary(cached.pair, expected):
				_error("That memory no longer matches the selected contribution."); return {}
			return cached.duplicate(true)
		_error("That saved replay could not be verified. It was not replaced.")
		return {}
	var room: Dictionary = _rooms[room_key]
	if room.family != "chapter" or not _pair_id(memory_id): return {}
	var generation := _generation
	var response := await _request_get(_room_path(room) + "/pairs/" + memory_id)
	if generation != _generation: return {}
	if not response.get("ok", false): return {}
	var pair: Variant = response.get("data")
	if not pair is Dictionary or pair.get("pair_id") != memory_id: return {}
	var entry := {"schema_version": 1, "room": room.duplicate(true), "pair": pair.duplicate(true)}
	if not verify_entry(entry, _owner): _error("The downloaded memory failed replay verification."); return {}
	if not _matches_summary(pair, expected):
		_error("That memory no longer matches the selected contribution."); return {}
	if not _cache(entry): return {}
	return entry

func _remember_room(snapshot: Dictionary, family: String, verified: bool = false) -> bool:
	if family == "chapter" and not verified:
		var checker := Coordinator.new(Callable(), func(_scope_value: String): return {"ok": true, "found": false}, _reject_game_save, _identity)
		if not checker.bind_room(str(snapshot.get("room_id", ""))) or not checker._valid_snapshot(snapshot): return _error("A shared chapter could not be verified.")
	var room := {"family": family, "room_id": snapshot.get("room_id"), "host_id": snapshot.get("host_id"), "guest_id": snapshot.get("guest_id"), "chapter_key": Registry.resolve(snapshot) if family == "chapter" else "", "title": str(Registry.descriptor(Registry.resolve(snapshot)).get("title", "Shared chapter")) if family == "chapter" else "Earlier islands"}
	if not _valid_room(room, _owner): return false
	var key := _room_key(room)
	if _rooms.has(key) and (_rooms[key].host_id != room.host_id or (_rooms[key].guest_id != null and _rooms[key].guest_id != room.guest_id)): return _error("This shared room's participants changed unexpectedly.")
	if not _rooms.has(key) and _rooms.size() >= 256: return _error("Your saved shared room list is full. Existing replays were kept.")
	var next := _rooms.duplicate(true)
	next[key] = room
	if not Canonical.same(next, _rooms) and not _store.save_scope(_scope("index"), {"schema_version": 1, "owner": _owner, "rooms": next}): return _error("Your shared room list could not be saved.")
	_rooms = next
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
	if snapshot.get("active_role") != "complete" or not snapshot.get("recordings") is Dictionary: return
	var pair := {"attempt": snapshot.get("attempt"), "level_id": snapshot.get("level_id"), "first_player_id": snapshot.get("first_player_id"), "a": snapshot.recordings.get("a"), "b": snapshot.recordings.get("b")}
	_cache({"schema_version": 1, "room": room, "pair": pair})

func _load_memories(key: String) -> bool:
	if _memories.has(key): return true
	var loaded: Dictionary = _store.load_scope(_scope(key))
	if not loaded.get("ok", false): return _error("Your saved shared memories could not be read. Nothing was replaced.")
	var value: Variant = loaded.get("value") if loaded.get("found", false) else {"schema_version": 1, "owner": _owner, "entries": {}}
	if not value is Dictionary or value.size() != 3 or value.get("schema_version") != 1 or value.get("owner") != _owner or not value.get("entries") is Dictionary or value.entries.size() > 65: return _error("This memory cache needs a compatible app.")
	for id: Variant in value.entries:
		var entry: Variant = value.entries[id]
		if not entry is Dictionary or not verify_entry(entry, _owner) or _room_key(entry.room) != key or str(id) != summary(entry).id: return _error("A saved memory could not be verified. Nothing was replaced.")
	_memories[key] = value.entries.duplicate(true)
	return true

func _cache(entry: Dictionary) -> bool:
	if not verify_entry(entry, _owner): return false
	var key := _room_key(entry.room)
	if not _load_memories(key): return false
	var id: String = summary(entry).id
	if _memories[key].has(id):
		return Canonical.same(_memories[key][id], entry) or _error("Two different recordings used the same memory identifier. The original was kept.")
	if _memories[key].size() >= 65: return _error("This room's saved memory cache is full. Existing recordings were kept.")
	var next: Dictionary = _memories[key].duplicate(true)
	next[id] = entry.duplicate(true)
	if not _store.save_scope(_scope(key), {"schema_version": 1, "owner": _owner, "entries": next}): return _error("This replay could not be saved for offline viewing.")
	_memories[key] = next
	return true

func _request_get(path: String) -> Dictionary:
	if not _ready_owner() or _busy or _api.busy or _api.player_id != _owner: return {"ok": false}
	var generation := _generation
	_busy = true
	var response: Dictionary = await _api.request_json(HTTPClient.METHOD_GET, path)
	if generation != _generation: return {"ok": false}
	_busy = false
	var owner: Dictionary = _identity.call()
	if not owner.get("ready", false) or owner.get("player_id") != _owner or int(owner.get("epoch", -1)) != _epoch:
		invalidate_identity(); return {"ok": false}
	if not response.get("ok", false): _error("Connection unavailable. Replays already saved on this device still work.")
	return response

func _scope(key: String) -> String: return "shared-replays:" + _owner + ":" + key
func _error(message: String) -> bool: last_error = message; return false
func _hold(message: String) -> bool: _cache_hold = true; return _error(message)
func _reject_game_save(_scope_value: String, _value: Dictionary) -> Dictionary: return {"ok": false}
static func _room_key(room: Dictionary) -> String: return str(room.family) + ":" + str(room.room_id)
static func _room_path(room: Dictionary) -> String: return ("/v2/rooms/" if room.family == "chapter" else "/v1/rooms/") + str(room.room_id)
static func _same_members(a: Dictionary, b: Dictionary) -> bool: return a.get("host_id") == b.get("host_id") and a.get("guest_id") == b.get("guest_id")
static func _matches_summary(pair: Dictionary, expected: Dictionary) -> bool:
	return expected.is_empty() or (expected.get("a_hash") == pair.a.recording_hash and expected.get("b_hash") == pair.b.recording_hash and expected.get("checkpoint_hash") == pair.checkpoint.checkpoint_hash)
static func _id(value: Variant) -> bool: return Coordinator._token(value, 22)
static func _hash(value: Variant) -> bool: return Coordinator._pattern(value, "^[a-f0-9]{64}$")
static func _pair_id(value: Variant) -> bool: return Coordinator._pattern(value, "^p([0-9]|[12][0-9]|3[01])-[01]$")
static func _valid_room(room: Variant, owner: String) -> bool:
	return room is Dictionary and room.size() == 6 and room.get("family") in ["legacy", "chapter"] and _id(room.get("room_id")) and _id(room.get("host_id")) and (room.get("guest_id") == null or (_id(room.get("guest_id")) and room.guest_id != room.host_id)) and owner in [room.host_id, room.guest_id] and room.get("title") is String and room.title.length() <= 80 and (room.get("chapter_key") == "" if room.family == "legacy" else not Registry.descriptor(str(room.get("chapter_key", ""))).is_empty())

static func verify_entry(entry: Variant, owner: String) -> bool:
	if not Coordinator._bounded(entry, 1048576) or not entry is Dictionary or entry.size() != 3 or entry.get("schema_version") != 1 or not _valid_room(entry.get("room"), owner) or not entry.get("pair") is Dictionary or entry.room.guest_id == null: return false
	var pair: Dictionary = entry.pair
	if not pair.get("a") is Dictionary or not pair.get("b") is Dictionary or pair.a.get("role") != "a" or pair.b.get("role") != "b": return false
	if entry.room.family == "chapter":
		if pair.size() != 6 or not _pair_id(pair.get("pair_id")) or pair.get("branch") != int(pair.pair_id.substr(1).get_slice("-", 0)) or pair.get("stage_index") != int(pair.pair_id.get_slice("-", 1)) or not pair.get("checkpoint") is Dictionary: return false
		var start := Registry.previous_checkpoint(entry.room.chapter_key, pair.checkpoint)
		if start.is_empty(): return false
		var engine: Script = Registry.simulation_script(entry.room.chapter_key)
		var checked: Dictionary = engine.derive_checkpoint(Registry.definition(entry.room.chapter_key), start, pair.a, pair.b)
		return checked.get("valid", false) and Canonical.same(checked.get("checkpoint"), pair.checkpoint) and int(pair.checkpoint.stage_index) == int(pair.stage_index) + 1
	if pair.size() != 5 or not Coordinator._range(pair.get("attempt"), 0, 1000000) or pair.get("first_player_id") not in [entry.room.host_id, entry.room.guest_id]: return false
	var level := Levels.get_level(str(pair.get("level_id", "")))
	if level.is_empty(): return false
	var checked: Dictionary = LegacySimulation.verify_recording(level, pair.b, pair.a)
	return checked.get("valid", false) and checked.get("snapshot", {}).get("can_commit", false)

static func summary(entry: Dictionary, cached: bool = true) -> Dictionary:
	var pair: Dictionary = entry.pair
	if entry.room.family == "legacy": return {"id": "a%d" % int(pair.attempt), "title": str(Levels.get_level(pair.level_id).title), "cached": cached}
	return {"id": pair.pair_id, "title": _stage_title(entry.room.chapter_key, int(pair.stage_index)), "stage_index": pair.stage_index, "a_hash": pair.a.recording_hash, "b_hash": pair.b.recording_hash, "checkpoint_hash": pair.checkpoint.checkpoint_hash, "cached": cached}

static func _stage_title(key: String, index: int) -> String:
	var definition := Registry.definition(key)
	return "%d · %s" % [index + 1, str(definition.stages[index].get("title", definition.stages[index].id))] if index >= 0 and index < definition.stages.size() else "Saved stage"

static func photo_turns(entry: Dictionary, owner: String) -> Array:
	if entry.room.family != "chapter" or not verify_entry(entry, owner): return []
	var result: Array = []
	for role: String in ["a", "b"]:
		var record: Dictionary = entry.pair[role]
		var player: String = entry.room.host_id if record.player_slot == "p0" else entry.room.guest_id
		result.append({"room_id": entry.room.room_id, "turn_id": "t" + entry.pair.pair_id.substr(1) + "-" + role, "recording_hash": record.recording_hash, "owner_player_id": player, "own": player == owner, "role": role, "player_slot": record.player_slot})
	return result
