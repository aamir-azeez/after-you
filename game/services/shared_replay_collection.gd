extends RefCounted
const PlayerCopy = preload("res://presentation/player_copy.gd")
## Participant-bound replay cache. All remote work is GET-only. The active room,
## lobby, pending request and rehearsal stores are never changed by this service.
const Store = preload("res://services/shared_replay_store.gd")
const OnlineStore = preload("res://services/relay_online_store.gd")
const Coordinator = preload("res://services/relay_room_coordinator.gd")
const Registry = preload("res://services/chapter_registry.gd")
const CampaignProtocol = preload("res://services/campaign_protocol.gd")
const Levels = preload("res://core/levels.gd")
const LegacySimulation = preload("res://core/simulation.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const Keepsakes = preload("res://services/home_keepsakes.gd")
const KeepsakeCatalog = preload("res://services/home_keepsake_catalog.gd")
var last_error := ""
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
var _memories: Dictionary = {}
var _story_selections: Dictionary = {}
var _cache_hold := false
var _index_loaded := false
var _keepsake_failed_rooms: Dictionary = {}
var _keepsake_verified_rooms: Dictionary = {}

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
	_memories.clear()
	_story_selections.clear()
	_busy = false
	_cache_hold = false
	_index_loaded = false
	_keepsake_failed_rooms.clear()
	_keepsake_verified_rooms.clear()

func busy() -> bool: return _busy

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
		if not value is Dictionary or value.size() != 3 or value.get("schema_version") != 1 or value.get("owner") != _owner or not value.get("rooms") is Dictionary or value.rooms.size() > 256:
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
		if not values is Array or values.size() > 128: complete = false; _error(PlayerCopy.SHARED_REPLAY_COLLECTION_6599B5A786DB); continue
		for value: Variant in values:
			if not value is Dictionary or not _remember_room(value, family): complete = false
	return complete

func memories(room_key: String) -> Array:
	if not _ready_owner() or not _rooms.has(room_key) or not _load_memories(room_key): return []
	var rows: Array = []
	for entry: Dictionary in _memories[room_key].values():
		if not _story_entry_matches(entry): return []
		rows.append(summary(entry, true))
	rows.sort_custom(func(a: Dictionary, b: Dictionary): return a.id < b.id)
	return rows

# Explicit Story discovery adds one chosen room, never every campaign child.
func cached_story_chapter(selection: Dictionary) -> String:
	if not _ready_owner() or not _story_selection_valid(selection): return ""
	var context := _story_context(selection)
	if context == null: return ""
	var key := "chapter:"+str(selection.room_id)
	if not _rooms.has(key): return ""
	var room: Dictionary = _rooms[key]
	if not _story_room_matches(room,selection) or not _load_memories(key): return ""
	for entry: Dictionary in _memories[key].values():
		if not _story_pair_matches(entry,selection):
			_error(PlayerCopy.SHARED_REPLAY_COLLECTION_021757D055C8)
			return ""
	return key if context.current() and _retain_story_selection(key,selection) else ""

func open_story_chapter(selection: Dictionary) -> String:
	if not _ready_owner() or not _story_selection_valid(selection) or _story_context(selection) == null: return ""
	var chosen := selection.duplicate(true)
	var generation := _generation
	var response := await _request_get("/v2/rooms/"+str(chosen.room_id),str(chosen.room_id))
	if generation != _generation or not response.get("ok",false) or _story_context(chosen) == null: return ""
	var snapshot: Variant = response.get("data")
	if not snapshot is Dictionary or snapshot.get("room_id") != chosen.room_id or snapshot.get("host_id") != chosen.host_id or snapshot.get("guest_id") != chosen.guest_id:
		_error(PlayerCopy.SHARED_REPLAY_COLLECTION_B198911049D6)
		return ""
	for field: String in ["level_id","level_version","definition_hash"]:
		if snapshot.get(field) != chosen.chapter[field]:
			_error(PlayerCopy.SHARED_REPLAY_COLLECTION_6AC2E1B2141C)
			return ""
	# Match the existing room binding rule: Relay omits its authored version2;
	# First Steps' authored default4 must never be promoted to current Story5.
	var authored := Registry.definition(Registry.resolve(chosen.chapter))
	if snapshot.get("simulation_version",authored.get("simulation_version")) != chosen.chapter.simulation_version:
		_error(PlayerCopy.SHARED_REPLAY_COLLECTION_6AC2E1B2141C)
		return ""
	if not _remember_room(snapshot,"chapter"): return ""
	return cached_story_chapter(chosen)

func _story_selection_valid(value: Dictionary) -> bool:
	if not CampaignProtocol.exact(value,["room_id","chapter","host_id","guest_id"]) or not _id(value.room_id) or not _id(value.host_id) or not _id(value.guest_id) or value.host_id == value.guest_id or _owner not in [value.host_id,value.guest_id] or not CampaignProtocol.pin_valid(value.chapter): return false
	var key := "chapter:"+str(value.room_id)
	return not _story_selections.has(key) or Canonical.same(_story_selections[key],value)

func _story_context(selection: Dictionary) -> RefCounted:
	# This Story-only seam must never infer an ordinary transport on failure.
	if not _context_required or _context_factory == null or not _context_factory.has_method("current") or not _context_factory.current() or not _context_factory.has_method("for_room"): return null
	var value: Variant = _context_factory.for_room(str(selection.room_id),"replay")
	var context: RefCounted = value if value is RefCounted else null
	return context if context != null and context.has_method("current") and context.current() and context.has_method("request") else null

func _story_room_matches(room: Dictionary, selection: Dictionary) -> bool:
	return room.family == "chapter" and room.room_id == selection.room_id and room.host_id == selection.host_id and room.guest_id == selection.guest_id and room.chapter_key == Registry.resolve(selection.chapter)

func _story_pair_matches(entry: Dictionary, selection: Dictionary) -> bool:
	return _story_room_matches(entry.room,selection) and verify_entry(entry,_owner) and entry.pair.a.get("simulation_version") == selection.chapter.simulation_version and entry.pair.b.get("simulation_version") == selection.chapter.simulation_version

func _retain_story_selection(key: String, selection: Dictionary) -> bool:
	# Only successful exact discovery installs this additional constraint. It
	# grants no transport authority and survives ordinary collection navigation.
	if _story_selections.has(key):
		return Canonical.same(_story_selections[key],selection) or _error(PlayerCopy.SHARED_REPLAY_COLLECTION_6AC2E1B2141C)
	if _story_selections.size() >= 256: return _error(PlayerCopy.SHARED_REPLAY_COLLECTION_84B86110B572)
	_story_selections[key] = selection.duplicate(true)
	return true

func _story_entry_matches(entry: Dictionary) -> bool:
	var key := _room_key(entry.room)
	return not _story_selections.has(key) or _story_pair_matches(entry,_story_selections[key]) or _error(PlayerCopy.SHARED_REPLAY_COLLECTION_021757D055C8)


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
		if not loaded.get("ok", false) or not value is Dictionary or value.size() != 3 or value.get("schema_version") != 1 or value.get("owner") != _owner or not value.get("entries") is Dictionary or value.entries.size() > 65:
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
		if not value is Dictionary or value.size() != 3 or value.get("schema_version") != 1 or value.get("owner") != source.owner or not value.get(field) is Dictionary or value[field].size() > (256 if field == "rooms" else 65): return {"ok": false, "ids": []}
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
			if value is Dictionary and value.get("room_id") == room.room_id and _same_members(value, room):
				_cache_legacy(value, room)
		return memories(room_key)
	var rows := memories(room_key)
	for value: Variant in values:
		if not value is Dictionary or not _pair_id(value.get("pair_id")) or not _hash(value.get("a_hash")) or not _hash(value.get("b_hash")) or not _hash(value.get("checkpoint_hash")) or value.get("stage_index") != int(str(value.pair_id).get_slice("-", 1)) or value.get("branch") != int(str(value.pair_id).substr(1).get_slice("-", 0)):
			_error(PlayerCopy.SHARED_REPLAY_COLLECTION_9D9E39D6BA85)
			return memories(room_key)
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
	return rows

func open_memory(room_key: String, memory_id: String, expected: Dictionary = {}) -> Dictionary:
	if not _ready_owner() or not _rooms.has(room_key) or not _load_memories(room_key): return {}
	if _memories[room_key].has(memory_id):
		var cached: Dictionary = _memories[room_key][memory_id]
		if verify_entry(cached, _owner) and _story_entry_matches(cached):
			if cached.room.family == "chapter" and not _matches_summary(cached.pair, expected):
				_error(PlayerCopy.SHARED_REPLAY_COLLECTION_DEC15671DC42); return {}
			return cached.duplicate(true)
		_error(PlayerCopy.SHARED_REPLAY_COLLECTION_249527DA8EE5)
		return {}
	var room: Dictionary = _rooms[room_key]
	if room.family != "chapter" or not _pair_id(memory_id): return {}
	var generation := _generation
	var response := await _request_get(_room_path(room) + "/pairs/" + memory_id, str(room.room_id))
	if generation != _generation: return {}
	if not response.get("ok", false): return {}
	var pair: Variant = response.get("data")
	if not pair is Dictionary or pair.get("pair_id") != memory_id: return {}
	var entry := {"schema_version": 1, "room": room.duplicate(true), "pair": pair.duplicate(true)}
	if not verify_entry(entry, _owner): _error(PlayerCopy.SHARED_REPLAY_COLLECTION_021757D055C8); return {}
	if not _story_entry_matches(entry): return {}
	if not _matches_summary(pair, expected):
		_error(PlayerCopy.SHARED_REPLAY_COLLECTION_DEC15671DC42); return {}
	if not _cache(entry): return {}
	return entry

func _remember_room(snapshot: Dictionary, family: String, verified: bool = false) -> bool:
	if family == "chapter" and not verified:
		var checker := Coordinator.new(Callable(), func(_scope_value: String): return {"ok": true, "found": false}, _reject_game_save, _identity)
		if not checker.bind_room(str(snapshot.get("room_id", ""))) or not checker._valid_snapshot(snapshot): return _error(PlayerCopy.SHARED_REPLAY_COLLECTION_6AC2E1B2141C)
	var room := {"family": family, "room_id": snapshot.get("room_id"), "host_id": snapshot.get("host_id"), "guest_id": snapshot.get("guest_id"), "chapter_key": Registry.resolve(snapshot) if family == "chapter" else "", "title": str(Registry.descriptor(Registry.resolve(snapshot)).get("title", "Shared chapter")) if family == "chapter" else "Earlier islands"}
	if not _valid_room(room, _owner): return false
	var key := _room_key(room)
	if _story_selections.has(key):
		var selection: Dictionary = _story_selections[key]
		var authored := Registry.definition(Registry.resolve(selection.chapter))
		if not _story_room_matches(room,selection) or snapshot.get("simulation_version",authored.get("simulation_version")) != selection.chapter.simulation_version:
			return _error(PlayerCopy.SHARED_REPLAY_COLLECTION_6AC2E1B2141C)
	if _rooms.has(key) and (_rooms[key].host_id != room.host_id or (_rooms[key].guest_id != null and _rooms[key].guest_id != room.guest_id)): return _error(PlayerCopy.SHARED_REPLAY_COLLECTION_B198911049D6)
	if not _rooms.has(key) and _rooms.size() >= 256: return _error(PlayerCopy.SHARED_REPLAY_COLLECTION_84B86110B572)
	var next := _rooms.duplicate(true)
	next[key] = room
	if not Canonical.same(next, _rooms) and not _store.save_scope(_scope("index"), {"schema_version": 1, "owner": _owner, "rooms": next}): return _error(PlayerCopy.SHARED_REPLAY_COLLECTION_E2EA0728968C)
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
	if not loaded.get("ok", false): return _error(PlayerCopy.SHARED_REPLAY_COLLECTION_443522A1FE1C)
	var value: Variant = loaded.get("value") if loaded.get("found", false) else {"schema_version": 1, "owner": _owner, "entries": {}}
	if not value is Dictionary or value.size() != 3 or value.get("schema_version") != 1 or value.get("owner") != _owner or not value.get("entries") is Dictionary or value.entries.size() > 65: return _error(PlayerCopy.SHARED_REPLAY_COLLECTION_E4268D68D7C0)
	for id: Variant in value.entries:
		var entry: Variant = value.entries[id]
		if not entry is Dictionary or not verify_entry(entry, _owner) or _room_key(entry.room) != key or str(id) != summary(entry).id: return _error(PlayerCopy.SHARED_REPLAY_COLLECTION_358437D8CCC9)
		if not _story_entry_matches(entry): return false
	_memories[key] = value.entries.duplicate(true)
	return true

func _cache(entry: Dictionary) -> bool:
	if not verify_entry(entry, _owner) or not _story_entry_matches(entry): return false
	var key := _room_key(entry.room)
	if not _load_memories(key): return false
	var id: String = summary(entry).id
	if _memories[key].has(id):
		if not Canonical.same(_memories[key][id], entry): return _error(PlayerCopy.SHARED_REPLAY_COLLECTION_A8680E064CEB)
		_remember_keepsake(entry)
		return true
	if _memories[key].size() >= 65: return _error(PlayerCopy.SHARED_REPLAY_COLLECTION_E45145AF7D59)
	var next: Dictionary = _memories[key].duplicate(true)
	next[id] = entry.duplicate(true)
	if not _store.save_scope(_scope(key), {"schema_version": 1, "owner": _owner, "entries": next}): return _error(PlayerCopy.SHARED_REPLAY_COLLECTION_4ACE7DB17681)
	_memories[key] = next
	_remember_keepsake(entry)
	return true

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

func _request_get(path: String, chapter_room_id: String = "") -> Dictionary:
	if not _ready_owner() or _busy or _api.busy or _api.player_id != _owner: return {"ok": false}
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
		response = await _api.request_json(HTTPClient.METHOD_GET, path)
	if generation != _generation: return {"ok": false}
	_busy = false
	if context_generation != _context_generation or (context != null and not context.current()): return _context_hold()
	var owner: Dictionary = _identity.call()
	if not owner.get("ready", false) or owner.get("player_id") != _owner or int(owner.get("epoch", -1)) != _epoch:
		invalidate_identity(); return {"ok": false}
	if response.get("ignored", false): return _context_hold()
	if not response.get("ok", false): _error(PlayerCopy.SHARED_REPLAY_COLLECTION_790E8697F4D2)
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
