extends SceneTree
const Collection = preload("res://services/shared_replay_collection.gd")
const Disk = preload("res://services/shared_replay_store.gd")
const View = preload("res://presentation/shared_replay_view.gd")
const Registry = preload("res://services/chapter_registry.gd")
const Coordinator = preload("res://services/relay_room_coordinator.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const Main = preload("res://main.gd")
const Save = preload("res://services/local_save.gd")
const PhotoLibrary = preload("res://services/turn_photo_library.gd")
const PhotoController = preload("res://services/turn_photo_controller.gd")
const Session = preload("res://services/relay_online_session.gd")
const HOST := "HHHHHHHHHHHHHHHHHHHHHH"
const GUEST := "GGGGGGGGGGGGGGGGGGGGGG"
const ROOM := "RRRRRRRRRRRRRRRRRRRRRR"
const OTHER := "SSSSSSSSSSSSSSSSSSSSSS"
var checks := 0
var failures := 0

class Boundary extends RefCounted:
	var player := HOST
	var epoch := 1
	var ready := true
	func identity() -> Dictionary: return {"ready": ready, "player_id": player, "epoch": epoch}

class SnapshotTrace extends RefCounted:
	var reads := 0
	var retaining := false
	var retained: Array[Dictionary] = []
	func capture(value: Dictionary) -> Dictionary:
		reads += 1
		if retaining: retained.append({"actual": value, "expected": value.duplicate(true)})
		return value
	func unchanged() -> bool:
		if retained.is_empty(): return false
		for value: Dictionary in retained:
			if not Canonical.same(value.actual, value.expected): return false
		return true

class CountedLegacy extends "res://core/simulation.gd":
	var trace := SnapshotTrace.new()
	func snapshot() -> Dictionary: return trace.capture(super.snapshot())

class CountedFirstSteps extends "res://core/first_steps/simulation.gd":
	var trace := SnapshotTrace.new()
	func snapshot() -> Dictionary: return trace.capture(super.snapshot())

class CountedPhysical extends "res://core/cooperative/simulation.gd":
	var trace := SnapshotTrace.new()
	func snapshot() -> Dictionary: return trace.capture(super.snapshot())

class CountedJourney extends "res://core/journey/simulation.gd":
	var trace := SnapshotTrace.new()
	func snapshot() -> Dictionary: return trace.capture(super.snapshot())

class Memory extends RefCounted:
	var values: Dictionary = {}
	var writes := 0
	var reads: Array[String] = []
	func load_scope(scope: String) -> Dictionary:
		reads.append(scope)
		return {"ok": true, "found": values.has(scope), "value": values.get(scope, {}).duplicate(true)}
	func save_scope(scope: String, value: Dictionary) -> bool:
		writes += 1
		values[scope] = value.duplicate(true)
		return true

class OnlineMemory extends Memory:
	func save_game(scope: String, value: Dictionary) -> Dictionary:
		save_scope(scope, value)
		return {"ok": true}

class Api extends Node:
	signal release
	var player_id := HOST
	var device_token := "synthetic-token"
	var busy := false
	var hold := false
	var replies: Dictionary = {}
	var calls: Array = []
	func request_json(method: int, path: String, body: Dictionary = {}) -> Dictionary:
		calls.append({"method": method, "path": path, "body": body.duplicate(true)})
		busy = true
		if hold: hold = false; await release
		busy = false
		return replies.get(path, {"ok": false, "status": 0, "code": "offline"}).duplicate(true)

class PhotoApi extends Node:
	signal release
	var player_id := HOST
	var device_token := "synthetic-token"
	var busy := false
	var hold_payload := false
	var library: RefCounted
	var photo: Dictionary
	var bytes := PackedByteArray()
	var calls: Array = []
	var ack_valid := false
	var acks := 0
	func request_json(method: int, path: String, body: Dictionary = {}) -> Dictionary:
		calls.append({"method": method, "path": path, "body": body.duplicate(true)})
		busy = true
		var base := "/v2/rooms/" + ROOM + "/photos/" + str(photo.turn_id)
		var data: Dictionary = {}
		if method == HTTPClient.METHOD_GET and path == base + "/delivery":
			data = _delivery()
		elif method == HTTPClient.METHOD_GET and path == base:
			data = {"photo": photo.duplicate(true), "jpeg_base64": Marshalls.raw_to_base64(bytes)}
			if hold_payload:
				hold_payload = false
				await release
		elif method == HTTPClient.METHOD_POST and path == base + "/ack":
			var cached: Dictionary = library.read_cache(HOST, ROOM, photo)
			ack_valid = Canonical.same(body, {"recording_hash": photo.recording_hash, "photo_revision": photo.photo_revision, "sha256": photo.sha256}) and cached.get("found", false) and cached.get("bytes") == bytes
			if ack_valid:
				acks += 1
				data = _delivery()
				data.acked = true
		busy = false
		return {"ok": true, "status": 200, "data": data} if not data.is_empty() else {"ok": false, "status": 403, "code": "unexpected_request"}
	func _delivery() -> Dictionary:
		return {"schema_version": 1, "photo": photo.duplicate(true), "available": true, "removed_reason": null, "intended_player_ids": [HOST, GUEST], "acked_player_ids": [HOST] if acks > 0 else []}

func _initialize() -> void: _run.call_deferred()

func _fixture(folder: String, name: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/" + (folder + "/" if not folder.is_empty() else "") + name + ".json"))

func _snapshot(chapter: String, room_id: String = ROOM, count: int = 2) -> Dictionary:
	var level := Registry.definition(chapter)
	var folder := "first_steps" if chapter == Registry.FIRST_STEPS else "v2"
	var checkpoint := _fixture(folder, "initial-checkpoint" if count == 0 else "final-checkpoint")
	return {"schema_version": 2, "api_version": 2, "room_id": room_id, "revision": 5 if count == 2 else 1, "branch": 0, "stage_index": count, "level_id": level.id, "level_version": level.version, "definition_hash": Canonical.digest(level), "host_id": HOST, "guest_id": GUEST, "checkpoint": checkpoint, "a_turn_id": null, "completed_pair_ids": ["p0-0", "p0-1"] if count == 2 else [], "invite_code": "A1".repeat(10), "invite_expires_at": "2026-09-21T12:00:00Z", "created_at": "2026-09-14T12:00:00Z", "updated_at": "2026-09-14T12:00:00Z", "active_role": "complete" if count == 2 else "a", "first_player_id": null if count == 2 else HOST, "active_player_id": null if count == 2 else HOST, "player_slot": "p0", "stage_id": "" if count == 2 else level.stages[0].id, "recording_a": null, "validation": "structural_client_replay_required"}

func _ok(data: Dictionary) -> Dictionary: return {"ok": true, "status": 200, "data": data}
func _offline(_request: Dictionary) -> Dictionary: return {"ok": false, "status": 0, "code": "offline"}

func _run() -> void:
	root.size = Vector2i(1920, 1080)
	var owner := Boundary.new()
	var api := Api.new()
	root.add_child(api)
	var cache := Memory.new()
	var online := OnlineMemory.new()
	var source := Coordinator.new(_offline, online.load_scope, online.save_game, owner.identity)
	_check(source.bind_room(ROOM) and source._accept_snapshot(_snapshot(Registry.FIRST_STEPS)), "Existing room file contains a fully verified two-stage First Steps checkpoint")
	var pending := Coordinator.new(_offline, online.load_scope, online.save_game, owner.identity)
	_check(pending.bind_room(OTHER) and pending._accept_snapshot(_snapshot(Registry.FIRST_STEPS, OTHER, 0)), "Independent unfinished room starts from the actual initial checkpoint")
	_check(not await pending.commit(_fixture("first_steps", "a-little-lift-a")) and not pending.pending().is_empty(), "Real accepted-shape input with an interrupted response creates a durable pending request")
	online.values["relay-lobby-v2:" + HOST] = {"schema_version": 1, "owner_player_id": HOST, "room_ids": [ROOM, OTHER], "last_room": OTHER, "pending": {}}
	var before := Canonical.digest(online.values)
	var writes := online.writes
	var collection := Collection.new(api, owner.identity, cache, online)
	_check(collection.load_saved() and collection.rooms().size() == 2, "Shared rooms are discovered from saved owner-scoped files without network access")
	var key := "chapter:" + ROOM
	var rows: Array = collection.memories(key)
	_check(rows.size() == 2 and rows[0].cached and rows[1].cached, "Both completed stages become separately selectable offline memories")
	var entry: Dictionary = await collection.open_memory(key, "p0-1")
	_check(Collection.verify_entry(entry, HOST), "Offline selected stage replays against its exact earlier checkpoint proof")
	await _local_scan(online)
	_transfer_adoption(collection.local_entries(key))
	await _local_identity_race()
	await _local_disk_race(online, entry)
	await _sequence_playback(collection.local_sequence(key), api, owner)
	_check(api.calls.is_empty() and Canonical.digest(online.values) == before and online.writes == writes, "Discovery and offline playback leave pending, draft, snapshot and lobby bytes untouched")
	var refs: Array = Collection.photo_turns(entry, HOST)
	_check(refs.size() == 2 and refs[0].turn_id == "t0-1-a" and refs[1].turn_id == "t0-1-b", "Photo references retain contribution-specific turn IDs")
	_check(refs[0].player_slot == "p1" and refs[0].owner_player_id == GUEST and not refs[0].own and refs[1].player_slot == "p0" and refs[1].own, "Stage-two role reversal preserves the actual physical participants")
	_check(refs[0].recording_hash == entry.pair.a.recording_hash and refs[1].recording_hash == entry.pair.b.recording_hash, "Photo lookup never substitutes another stage or latest avatar hash")
	var reopened := Collection.new(api, owner.identity, cache, OnlineMemory.new())
	_check(reopened.rooms().size() == 2 and not (await reopened.open_memory(key, "p0-1")).is_empty(), "Saved shared replay cache reopens without the gameplay room journal")
	var tampered := entry.duplicate(true)
	tampered.pair.b.final_state_hash = "0".repeat(64)
	_check(not Collection.verify_entry(tampered, HOST), "A tampered final recording cannot become a shared replay")
	_check(not Collection.verify_entry(entry, OTHER), "Another identity cannot reuse participant-bound cached metadata")
	api.replies["/v2/rooms/" + ROOM + "/collection"] = _ok({"pairs": [{"pair_id": "p1-1", "branch": 1, "stage_index": 1, "a_hash": entry.pair.a.recording_hash, "b_hash": entry.pair.b.recording_hash, "checkpoint_hash": entry.pair.checkpoint.checkpoint_hash}], "active_pair_ids": []})
	var archived: Dictionary = entry.pair.duplicate(true)
	archived.pair_id = "p1-1"
	archived.branch = 1
	api.replies["/v2/rooms/" + ROOM + "/pairs/p1-1"] = _ok(archived)
	rows = await collection.refresh_memories(key)
	var remote: Dictionary = rows[-1]
	_check(rows.size() == 3 and not remote.cached and remote.id == "p1-1", "Server-only historical pair appears without eagerly downloading every recording")
	var expected := remote.duplicate(true)
	expected.a_hash = "f".repeat(64)
	_check((await collection.open_memory(key, "p1-1", expected)).is_empty(), "Downloaded pair must match the selected immutable metadata")
	var archive_entry: Dictionary = await collection.open_memory(key, "p1-1", remote)
	_check(not archive_entry.is_empty() and Collection.photo_turns(archive_entry, HOST)[0].turn_id == "t1-1-a", "An archived fork uses its original branch turn IDs and native source checkpoint")
	_check((await collection.open_memory(key, "p1-1", expected)).is_empty(), "A cached pair also rejects mismatched selected contribution hashes")
	_check(Canonical.digest(online.values) == before, "Fetching an archived replay never switches the active room or reconciles its pending POST")
	for call: Dictionary in api.calls: _check(call.method == HTTPClient.METHOD_GET and call.body.is_empty(), "Every collection network operation is GET-only")
	var legacy := {"room_id": "L".repeat(22), "host_id": HOST, "guest_id": GUEST, "level_id": "first-light", "attempt": 3, "first_player_id": GUEST, "active_role": "complete", "recordings": {"a": _fixture("", "first-light-a"), "b": _fixture("", "first-light-b")}}
	_check(collection.load_saved(legacy), "Earlier-island collection remains compatible with its original engine")
	var legacy_entry: Dictionary = await collection.open_memory("legacy:" + str(legacy.room_id), "a3")
	_check(not legacy_entry.is_empty() and Collection.photo_turns(legacy_entry, HOST).is_empty(), "Legacy replay is verified without inventing chapter photo references")
	await _viewer(entry, api, owner, "2 · a-place-to-grow")
	await _viewer(legacy_entry, api, owner, "First Light")
	for fixture: Array in [[Registry.ROLLING_HOME, "cooperative", "bring-it-home"], [Registry.CONSERVATORY, "journey", "a-light-above"]]:
		var published := _published_entry(fixture[0], fixture[1], fixture[2])
		_check(Collection.verify_entry(published, HOST), "Published physical or Journey pair passes native shared-replay verification: " + str(fixture[0]))
		await _viewer(published, api, owner, str(Collection.summary(published).title))
	await _rejected_view(tampered, api, HOST)
	await _rejected_view(entry, api, OTHER)
	await _delivery_ack(entry, api, owner)
	await _first_photo_read(entry)
	await _local_photo_read(entry)
	var relay := _snapshot(Registry.RELAY, "T".repeat(22))
	_check(collection._remember_room(relay, "chapter") and collection.memories("chapter:" + str(relay.room_id)).size() == 2, "Original Relay schema and proof chain are supported alongside First Steps")
	await _identity_race(collection, api, owner, cache)
	_disk()
	await _home_entries()
	api.queue_free()
	await process_frame
	print("SHARED REPLAYS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _drain_local(collection: RefCounted) -> void:
	var deadline := Time.get_ticks_msec() + 15000
	while collection.local_loading() and Time.get_ticks_msec() < deadline:
		collection.advance_local_load()
		await process_frame
	_check(not collection.local_loading(), "Bounded local scan finishes and releases its worker")

func _transfer_adoption(entries: Array) -> void:
	var owner := Boundary.new()
	var api := Api.new()
	var cache := Memory.new()
	var collection := Collection.new(api, owner.identity, cache, OnlineMemory.new())
	var manifest := {"room": _snapshot(Registry.FIRST_STEPS), "pairs": []}
	for entry: Dictionary in entries:
		var pair: Dictionary = entry.pair
		manifest.pairs.append({"pair_id": pair.pair_id, "branch": pair.branch, "stage_index": pair.stage_index, "a_hash": pair.a.recording_hash, "b_hash": pair.b.recording_hash, "checkpoint_hash": pair.checkpoint.checkpoint_hash})
	_check(collection.cache_transferred_entries(ROOM, entries, manifest), "A verified archive adopts all replay pairs in a durable bulk cache")
	_check(collection.local_sequence("chapter:" + ROOM).size() == 2 and api.calls.is_empty(), "Transfer adoption enables complete offline playback without transport")
	var before := Canonical.digest(cache.values)
	var wrong := manifest.duplicate(true)
	wrong.pairs[0].a_hash = "0".repeat(64)
	_check(not collection.cache_transferred_entries(ROOM, entries, wrong) and Canonical.digest(cache.values) == before, "A manifest mismatch cannot overwrite accepted replay history")
	var stored: Dictionary = cache.values["shared-replays:" + HOST + ":chapter:" + ROOM]
	stored.entries["p5-1"] = entries.back().duplicate(true)
	before = Canonical.digest(cache.values)
	_check(not collection.cache_transferred_entries(ROOM, entries, manifest) and Canonical.digest(cache.values) == before, "An archive that omits existing local history cannot authorize replacement or ACK")
	api.free()

func _settle_view(view: Node) -> void:
	view.set_physics_process(false)
	var deadline := Time.get_ticks_msec() + 15000
	while view.mode in ["loading", "preparing"] and Time.get_ticks_msec() < deadline:
		view._process(0.0)
		await process_frame
	view.set_process(false)
	if view.world != null: view.world.set_process(false)
	_check(view.mode not in ["loading", "preparing"], "Replay admission finishes before playback starts")

func _local_scan(online: RefCounted) -> void:
	var owner := Boundary.new()
	var api := Api.new()
	root.add_child(api)
	var cache := Memory.new()
	var collection := Collection.new(api, owner.identity, cache, online)
	var before := Canonical.digest(online.values)
	var writes: int = online.writes
	_check(collection.begin_local_load() and collection.local_loading(), "Local replay discovery queues work without fetching rooms")
	var reads: int = cache.reads.size()
	_check(collection.memories("chapter:" + ROOM, true).is_empty() and cache.reads.size() == reads, "Opening an unverified local row cannot synchronously load the recording cache")
	await _drain_local(collection)
	var rows: Array = collection.memories("chapter:" + ROOM, true)
	_check(rows.size() == 2 and rows.all(func(row: Dictionary): return row.cached), "Worker discovery makes both native-verified parts available offline")
	reads = cache.reads.count("shared-replays:" + HOST + ":chapter:" + ROOM)
	_check(collection.memories("chapter:" + ROOM, true).size() == 2 and cache.reads.count("shared-replays:" + HOST + ":chapter:" + ROOM) == reads, "Returning to a verified local row does not reload its recording file")
	_check(api.calls.is_empty() and online.writes == writes and Canonical.digest(online.values) == before, "Async discovery performs no HTTP request and leaves pending gameplay journals unchanged")
	api.queue_free()
	await process_frame

func _local_identity_race() -> void:
	var owner := Boundary.new()
	var api := Api.new()
	root.add_child(api)
	var cache := Memory.new()
	var online := OnlineMemory.new()
	var first := Coordinator.new(_offline, online.load_scope, online.save_game, owner.identity)
	_check(first.bind_room(ROOM) and first._accept_snapshot(_snapshot(Registry.FIRST_STEPS)), "Identity-race source is a real verified room")
	online.values["relay-lobby-v2:" + HOST] = {"owner_player_id": HOST, "room_ids": [ROOM]}
	var collection := Collection.new(api, owner.identity, cache, online)
	_check(collection.begin_local_load(), "First account starts local discovery")
	collection.advance_local_load()
	# The worker may finish, but its result has not yet been adopted.
	owner.player = OTHER
	owner.epoch += 1
	api.player_id = OTHER
	var next_room := "N".repeat(22)
	var snapshot := _snapshot(Registry.FIRST_STEPS, next_room)
	snapshot.host_id = OTHER
	var second := Coordinator.new(_offline, online.load_scope, online.save_game, owner.identity)
	_check(second.bind_room(next_room) and second._accept_snapshot(snapshot), "New account has its own independently verified room")
	online.values["relay-lobby-v2:" + OTHER] = {"owner_player_id": OTHER, "room_ids": [next_room]}
	_check(collection.begin_local_load(), "New identity can queue discovery while the retired worker drains")
	await _drain_local(collection)
	var rooms: Array = collection.rooms()
	_check(rooms.size() == 1 and rooms[0].room_id == next_room and collection.memories("chapter:" + next_room, true).size() == 2, "Only the current identity receives discovered replay rows")
	_check(cache.values.keys().all(func(scope: String): return scope.begins_with("shared-replays:" + OTHER + ":")) and api.calls.is_empty(), "Retired worker cannot write the former account's cache or make a request")
	api.queue_free()
	await process_frame

func _local_disk_race(online: RefCounted, final_entry: Dictionary) -> void:
	var owner := Boundary.new()
	var api := Api.new()
	root.add_child(api)
	var directory := "user://shared-replay-race-%d" % Time.get_ticks_usec()
	var store := Disk.new(directory)
	var writer := Collection.new(api, owner.identity, store, OnlineMemory.new())
	writer.rooms() # Bind the owner before calling the internal ingestion path.
	_check(writer._remember_room(_snapshot(Registry.FIRST_STEPS), "chapter"), "Independent cache writer stores both original parts")
	var collection := Collection.new(api, owner.identity, store, online)
	_check(collection.begin_local_load(), "Disk-backed scan starts from the original generation")
	collection.advance_local_load()
	var forked := final_entry.duplicate(true)
	forked.pair.pair_id = "p1-1"
	forked.pair.branch = 1
	_check(writer._cache(forked), "Another collection durably adds a verified archived pair before scan adoption")
	var extra_room := "Z".repeat(22)
	_check(writer._remember_room(_snapshot(Registry.FIRST_STEPS, extra_room), "chapter"), "Concurrent index writer adds an independent completed room")
	await _drain_local(collection)
	var rows: Array = collection.memories("chapter:" + ROOM, true)
	var saved: Dictionary = store.load_scope("shared-replays:" + HOST + ":chapter:" + ROOM)
	_check(rows.size() == 3 and saved.get("value", {}).get("entries", {}).has("p1-1"), "Worker rescans a changed disk generation without overwriting the newer archived pair")
	_check(store.load_scope("shared-replays:" + HOST + ":index").value.rooms.has("chapter:" + extra_room), "Worker room discovery preserves a concurrently added index entry")
	_check(collection.begin_local_load(), "A warm collection can rescan local changes")
	collection.advance_local_load()
	forked.pair.pair_id = "p2-1"
	forked.pair.branch = 2
	_check(writer._cache(forked), "A second archive appears after warm-scan capture")
	await _drain_local(collection)
	_check(collection.memories("chapter:" + ROOM, true).size() == 4, "The unchanged fast path still notices another writer's newer file")
	_check(api.calls.is_empty(), "Disk-generation conflict resolution remains entirely local")
	for key: String in ["index", "chapter:" + ROOM, "chapter:" + OTHER, "chapter:" + extra_room]:
		var path := directory.path_join(("shared-replays:" + HOST + ":" + key).sha256_text() + ".json")
		for suffix: String in ["", ".backup", ".tmp"]:
			if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(path + suffix)
	DirAccess.remove_absolute(directory)
	api.queue_free()
	await process_frame

func _sequence_playback(sequence: Array, api: Node, owner: RefCounted) -> void:
	_check(sequence.size() == 2 and View.valid_sequence(sequence, HOST), "Watch-all selects two parts joined by the exact native checkpoint")
	if sequence.size() != 2: return
	_check(sequence[0].pair.stage_index == 0 and sequence[1].pair.stage_index == 1, "Combined playback starts with the earlier part")
	var reversed: Array = [sequence[1], sequence[0]]
	var later_branch: Array = sequence.duplicate(true)
	later_branch[0].pair.branch = 1
	later_branch[0].pair.pair_id = "p1-0"
	var foreign: Array = sequence.duplicate(true)
	foreign[1].room.room_id = OTHER
	var broken: Array = sequence.duplicate(true)
	broken[1].pair.checkpoint.checkpoint_hash = "0".repeat(64)
	_check(not View.valid_sequence(reversed, HOST) and not View.valid_sequence(later_branch, HOST), "Combined playback rejects reversed parts and a first part from a later fork")
	_check(not View.valid_sequence(foreign, HOST) and not View.valid_sequence(broken, HOST), "A different room or altered checkpoint cannot be stitched into a replay")
	var original := Canonical.digest(sequence)
	var calls: int = api.calls.size()
	var view := View.new()
	view.entry = sequence[0]
	view.sequence = sequence
	view.api = api
	view.identity = owner.identity
	view.settings = {"sound": false, "haptics": false, "reduced_motion": true}
	root.add_child(view)
	await _settle_view(view)
	view.backgrounded = false
	if view.mode != "replay" or view.sim == null:
		_check(false, "Verified linked sequence starts its native replay")
		root.remove_child(view)
		view.queue_free()
		await process_frame
		return
	for part in range(2):
		_check(view.mode == "replay" and view.cursor == 0 and view.entry.pair.stage_index == part, "Combined replay starts the expected part with a fresh cursor")
		var limit := 0
		while view.running and limit < 1300:
			view._physics_process(1.0 / 30.0)
			limit += 1
		_check(view.mode == "bloom" and Canonical.same(view.sim.export_recording(), sequence[part].pair.b), "Each combined part finishes using its exact accepted recording")
		view._pause()
		view._process(View.COMPLETION_DURATION * 2)
		_check(view.mode == "paused" and view.entry.pair.stage_index == part, "Pausing the bloom cannot skip into the next part")
		view._resume()
		view._process(View.COMPLETION_DURATION)
	_check(view.mode == "complete" and view.entry.pair.stage_index == 1, "Only the final part shows the completed replay card")
	var replay := _button(view.controls.overlay, "Replay")
	if replay != null: replay.pressed.emit()
	_check(replay != null and view.mode == "replay" and view.entry.pair.stage_index == 0 and view.cursor == 0, "Replay restarts the whole sequence from its first part")
	_check(Canonical.digest(sequence) == original and api.calls.size() == calls, "Combined playback preserves source evidence and performs no remote request")
	root.remove_child(view)
	view.queue_free()
	await process_frame

func _published_entry(chapter: String, folder: String, stage: String) -> Dictionary:
	var checkpoint := _fixture(folder, stage + "-checkpoint")
	var index := int(checkpoint.stage_index) - 1
	return {"schema_version": 1,
		"room": {"family": "chapter", "room_id": ("J" if Registry.is_journey(chapter) else "P").repeat(22),
			"host_id": HOST, "guest_id": GUEST, "chapter_key": chapter, "title": str(Registry.descriptor(chapter).title)},
		"pair": {"pair_id": "p0-" + str(index), "branch": 0, "stage_index": index,
			"a": _fixture(folder, stage + "-a"), "b": _fixture(folder, stage + "-b"), "checkpoint": checkpoint}}

func _expected_snapshots_per_tick() -> int:
	return 1

func _counted_simulation(entry: Dictionary) -> RefCounted:
	var native: RefCounted
	var ready := false
	if entry.room.family == "legacy":
		native = CountedLegacy.new()
		ready = native.reset(View.Levels.get_level(entry.pair.level_id), entry.pair.a, "b")
	else:
		var key: String = entry.room.chapter_key
		if key == Registry.FIRST_STEPS: native = CountedFirstSteps.new()
		elif Registry.is_journey(key): native = CountedJourney.new()
		else: native = CountedPhysical.new()
		ready = Registry.reset_simulation(native, key, Registry.definition(key), str(entry.pair.b.stage_id),
			Registry.previous_checkpoint(key, entry.pair.checkpoint), entry.pair.a, "b", entry.pair.b)
	native.catch_assistance = bool(entry.pair.b.get("catch_assistance", true))
	_check(ready, "Snapshot-counting native replay resets from the verified pair")
	return native if ready else null

func _viewer(entry: Dictionary, api: Node, owner: RefCounted, expected_title: String) -> void:
	var original := Canonical.digest(entry)
	var expected_label := "SHARED REPLAY\n" + expected_title
	var view := View.new()
	view.entry = entry
	view.api = api
	view.identity = owner.identity
	view.settings = {"sound": false, "haptics": false, "reduced_motion": true}
	root.add_child(view)
	await _settle_view(view)
	view.backgrounded = false
	if view.mode != "replay" or view.sim == null:
		_check(false, "Verified memory starts its native replay")
		root.remove_child(view)
		view.queue_free()
		await process_frame
		return
	var counted := _counted_simulation(entry)
	if counted == null:
		root.remove_child(view)
		view.queue_free()
		await process_frame
		return
	_check(Canonical.same(counted.snapshot(), view.sim.snapshot()), "Counting wrapper preserves the actual engine's initial snapshot")
	view.sim = counted
	var trace: SnapshotTrace = counted.trace
	trace.retaining = true
	_check(view.mode == "replay" and view.running and not view.controls.stick.visible, "Real shared replay viewer starts without editable gameplay controls")
	_check(view.controls.chapter_label.text == expected_label and view.controls.hud.visible, "Each newly opened replay shows its own chapter or legacy title")
	for i in range(5):
		var reads := trace.reads
		view._physics_process(1.0 / 30.0)
		_check(view.cursor == i + 1 and trace.reads == reads + _expected_snapshots_per_tick(), "Each normal replay tick uses the expected number of native snapshots")
		_check(view.controls.chapter_label.text == expected_label, "Replay HUD ticks retain the selected memory title")
	_check(trace.unchanged(), "World and HUD leave retained native snapshots, including nested values, unchanged")
	var cursor: int = view.cursor
	view._pause()
	_check(not view.running and view.mode == "paused" and view.cursor == cursor, "Shared replay pause retains its exact presentation cursor")
	_check(view.controls.chapter_label.text == expected_label and not view.controls.hud.visible, "Pause hides the HUD without changing the selected title")
	var resume_reads := trace.reads
	view._resume()
	_check(trace.reads == resume_reads + 1 and trace.unchanged(), "Resume reads a fresh native snapshot without mutating it or retained earlier state")
	trace.retaining = false
	_check(view.controls.chapter_label.text == expected_label and view.controls.hud.visible, "Resume restores the same title to the visible HUD")
	var limit := 0
	while view.running and limit < 610:
		view._physics_process(1.0 / 30.0)
		limit += 1
	_check(view.mode == "bloom" and not view.controls.overlay.visible and view.sim.snapshot().complete, "Shared replay holds the actual completed garden before displaying its menu")
	_check(view.cursor > 100 and trace.unchanged(), "Retained snapshots remain unchanged after more than one hundred real replay ticks")
	_check(Canonical.same(view.sim.export_recording(), entry.pair.b), "Completed replay exports the exact published recording, including nested outcomes and checks")
	view._process(2.5)
	_check(view.mode == "bloom" and not view.controls.overlay.visible, "Shared replay gives the complete bloom time to unfold")
	var remaining: float = view.completion_remaining
	view._pause()
	view._process(20.0)
	_check(view.mode == "paused" and view.completion_remaining == remaining and Canonical.digest(entry) == original, "Pausing celebration retains its remaining time and exact source")
	view._resume()
	_check(view.mode == "bloom" and not view.running and not view.controls.overlay.visible, "Resume returns to the held celebration without restarting simulation")
	view._process(View.COMPLETION_DURATION)
	_check(view.mode == "complete" and view.sim.snapshot().can_commit and Canonical.digest(entry) == original, "Actual input replay finishes successfully without altering the source pair")
	_check(_button(view.controls.overlay, "Replay") != null and _button(view.controls.overlay, "Save turn") == null, "Completed shared viewer offers replay and return, never Save or fork")
	var replay_button := _button(view.controls.overlay, "Replay")
	if replay_button != null: replay_button.pressed.emit()
	_check(view.mode == "replay" and view.running and view.cursor == 0 and view.controls.hud.visible and view.controls.chapter_label.text == expected_label,
		"The actual Replay button restarts the selected memory with the same title")
	for i in range(3): view._physics_process(1.0 / 30.0)
	_check(view.controls.chapter_label.text == expected_label and Canonical.digest(entry) == original, "Restarted HUD updates retain the title and leave the original replay entry untouched")
	root.remove_child(view)
	view.queue_free()
	await process_frame

func _rejected_view(entry: Dictionary, api: Node, player: String) -> void:
	var owner := Boundary.new()
	owner.player = player
	var calls: int = api.calls.size()
	var original := Canonical.digest(entry)
	var view := View.new()
	view.entry = entry
	view.api = api
	view.identity = owner.identity
	root.add_child(view)
	await _settle_view(view)
	_check(view.mode == "error" and not view.running and view.sim == null and view.world == null and not view.controls.hud.visible,
		"Invalid recording or foreign identity cannot start a titled replay")
	_check(api.calls.size() == calls and Canonical.digest(entry) == original, "Rejected replay entries trigger no request or source mutation")
	root.remove_child(view)
	view.queue_free()
	await process_frame

func _identity_race(collection: RefCounted, api: Node, owner: RefCounted, cache: RefCounted) -> void:
	api.replies["/v1/rooms"] = _ok({"rooms": []})
	api.hold = true
	var result := {"done": false}
	var run := func(): await collection.refresh_rooms(); result.done = true
	run.call()
	var calls: int = api.calls.size()
	var saved := Canonical.digest(cache.values)
	owner.player = OTHER
	owner.epoch += 1
	api.player_id = OTHER
	api.release.emit()
	await process_frame
	_check(result.done and api.calls.size() == calls and Canonical.digest(cache.values) == saved, "Late old-owner response cannot write metadata or launch another account's second request")
	_check(collection.rooms().is_empty(), "Changing identity clears the visible shared collection")

func _delivery_ack(entry: Dictionary, api: Node, owner: RefCounted) -> void:
	var session := View.ReadSession.new(api, owner.identity)
	session.photo_targets = Collection.photo_turns(entry, HOST)
	var target: Dictionary = session.photo_targets[0]
	var path := "/v2/rooms/" + str(target.room_id) + "/photos/" + str(target.turn_id) + "/ack"
	api.replies[path] = _ok({"acked": true})
	var request := {"method": HTTPClient.METHOD_POST, "path": path, "body": {"recording_hash": target.recording_hash, "photo_revision": 1, "sha256": "a".repeat(64)}, "owner_player_id": HOST, "identity_epoch": owner.epoch}
	var count: int = api.calls.size()
	_check((await session.transport(request)).get("ok", false) and api.calls.size() == count + 1, "Shared viewer permits an exact contribution delivery ACK")
	for field: String in ["owner", "path", "hash", "revision", "sha", "delete"]:
		var wrong := request.duplicate(true)
		match field:
			"owner": wrong.owner_player_id = OTHER
			"path": wrong.path = path.replace("t0-1-a", "t0-0-a")
			"hash": wrong.body.recording_hash = "0".repeat(64)
			"revision": wrong.body.photo_revision = 0
			"sha": wrong.body.sha256 = "not-a-sha"
			"delete": wrong.method = HTTPClient.METHOD_DELETE
		_check(not (await session.transport(wrong)).get("ok", false) and api.calls.size() == count + 1, "Viewer rejects unrelated or malformed photo mutation: " + field)
	session.invalidate_identity()

func _first_photo_read(entry: Dictionary) -> void:
	var image := Image.create(24, 24, false, Image.FORMAT_RGB8)
	image.fill(Color("a6d9c4"))
	for scenario: String in ["first", "unknown", "revoked", "changed", "epoch", "invalidated"]:
		var owner := Boundary.new()
		owner.ready = scenario != "unknown"
		var api := PhotoApi.new()
		root.add_child(api)
		var library := PhotoLibrary.new("user://shared-first-photo-%d-%s" % [Time.get_ticks_usec(), scenario])
		api.library = library
		api.bytes = image.save_jpg_to_buffer(0.7)
		var store := Memory.new()
		# Delivery and durable ACK belong to the ordinary transfer session;
		# opening a saved replay never starts this network path.
		var session := Session.new(api, owner.identity, store)
		var targets: Array = Collection.photo_turns(entry, HOST)
		session.photo_library = library
		session.photo_store = Memory.new()
		var target: Dictionary = targets[0]
		api.photo = {"schema_version": 1, "turn_id": target.turn_id, "owner_player_id": target.owner_player_id, "recording_hash": target.recording_hash, "photo_revision": 1, "sha256": PhotoController._digest(api.bytes), "width": 24, "height": 24, "byte_length": api.bytes.size(), "updated_at": "2026-09-15T00:00:00Z"}
		_check(session._owner.is_empty() and api.calls.is_empty(), "Fresh photo session has no earlier bind or transport: " + scenario)
		var controller := session.create_photo_controller(Callable())
		session.capabilities = {"mutations_enabled": true}
		if scenario in ["revoked", "changed", "epoch", "invalidated"]:
			api.hold_payload = true
			var state := {"done": false, "result": {}}
			var run := func():
				state.result = await controller.read_shared(ROOM, target.turn_id, target.recording_hash)
				state.done = true
			run.call()
			_check(api.busy and api.calls.size() == 2 and not state.done, "First read reaches a held real JPEG response: " + scenario)
			match scenario:
				"revoked": owner.ready = false
				"changed": owner.player = OTHER; api.player_id = OTHER
				"epoch": owner.epoch += 1
				"invalidated": session.invalidate_identity()
			api.release.emit()
			await process_frame
			_check(state.done and state.result.is_empty() and api.acks == 0 and not library.read_cache(HOST, ROOM, api.photo).get("found", false), "Old identity result never renders, caches, or ACKs: " + scenario)
		else:
			var result: Dictionary = await controller.read_shared(ROOM, target.turn_id, target.recording_hash)
			if scenario == "unknown":
				_check(result.is_empty() and api.calls.is_empty() and api.acks == 0, "Unknown identity cannot issue the first photo request")
			else:
				var cached: Dictionary = library.read_cache(HOST, ROOM, api.photo)
				_check(result.get("bytes") == api.bytes and api.calls.size() == 3, "First controller read returns its exact JPEG without retry or prebinding")
				_check(api.acks == 1 and api.ack_valid and cached.get("found", false) and cached.get("delivery_ack", false), "First read writes real bytes durably before its exact delivery ACK")
		_check(store.writes == 0 and session.photo_store.writes == 0 and api.calls.all(func(call: Dictionary) -> bool: return call.method == HTTPClient.METHOD_GET or (call.method == HTTPClient.METHOD_POST and call.path.ends_with("/ack") and api.ack_valid)), "First photo read leaves gameplay/photo journals untouched and permits only typed ACK: " + scenario)
		session.invalidate_identity()
		api.queue_free()
		await process_frame

func _local_photo_read(entry: Dictionary) -> void:
	var owner := Boundary.new()
	var api := PhotoApi.new()
	root.add_child(api)
	var library := PhotoLibrary.new("user://shared-local-photo-%d" % Time.get_ticks_usec())
	var image := Image.create(24, 24, false, Image.FORMAT_RGB8)
	image.fill(Color("a6d9c4"))
	api.bytes = image.save_jpg_to_buffer(0.7)
	api.library = library
	var target: Dictionary = Collection.photo_turns(entry, HOST)[0]
	api.photo = {"schema_version": 1, "turn_id": target.turn_id, "owner_player_id": target.owner_player_id, "recording_hash": target.recording_hash, "photo_revision": 1, "sha256": PhotoController._digest(api.bytes), "width": 24, "height": 24, "byte_length": api.bytes.size(), "updated_at": "2026-09-15T00:00:00Z"}
	var session := View.ReadSession.new(api, owner.identity, Memory.new())
	session.photo_targets = [target]
	session.photo_library = library
	session.photo_store = Memory.new()
	var controller: RefCounted = session.create_photo_controller(Callable())
	var missing: Dictionary = await controller.read_shared(ROOM, target.turn_id, target.recording_hash)
	_check(missing.is_empty() and api.calls.is_empty(), "An uncached optional image does not cause a saved replay to download it")
	var stored: Dictionary = library.store_cache(HOST, ROOM, api.photo, api.bytes)
	_check(stored.get("ok", false) and stored.get("durable", false), "Local replay fixture has a real durable image")
	var cached: Dictionary = await controller.read_shared(ROOM, target.turn_id, target.recording_hash)
	_check(cached.get("bytes") == api.bytes and api.calls.is_empty() and api.acks == 0, "Saved replay reads exact phone bytes without delivery lookup or ACK")
	var removed := api.photo.duplicate(true)
	removed.photo_revision = 2
	removed.sha256 = null
	removed.width = null
	removed.height = null
	removed.byte_length = 0
	_check(library.mark_deleted(HOST, ROOM, removed).get("ok", false), "Known owner removal is retained locally")
	_check((await controller.read_shared(ROOM, target.turn_id, target.recording_hash)).is_empty() and api.calls.is_empty(), "Local-only playback respects a known deletion without fetching old pixels")
	owner.player = OTHER
	owner.epoch += 1
	api.player_id = OTHER
	_check((await controller.read_shared(ROOM, target.turn_id, target.recording_hash)).is_empty() and api.calls.is_empty(), "Another identity cannot read or download the former owner's cached photo")
	session.invalidate_identity()
	api.queue_free()
	await process_frame

func _disk() -> void:
	var directory := "user://shared-replay-disk-%d" % Time.get_ticks_usec()
	var store := Disk.new(directory)
	var scope := "shared-replays:" + HOST + ":index"
	_check(store.save_scope(scope, {"schema_version": 1, "owner": HOST, "rooms": {}}), "Real replay cache writes an independent recoverable local envelope")
	var file_path := directory.path_join(scope.sha256_text() + ".json")
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(file_path))
	raw.shared_replay_value.schema_version = 2
	var file := FileAccess.open(file_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(raw))
	file.close()
	var before := FileAccess.get_sha256(file_path)
	_check(not store.load_scope(scope).ok and not store.save_scope(scope, {"schema_version": 1, "owner": HOST, "rooms": {}}), "Future replay-cache data is held rather than overwritten")
	_check(FileAccess.get_sha256(file_path) == before, "Future cache bytes remain exactly preserved")
	for suffix: String in ["", ".backup", ".tmp"]:
		if FileAccess.file_exists(file_path + suffix): DirAccess.remove_absolute(file_path + suffix)
	DirAccess.remove_absolute(directory)

func _home_entries() -> void:
	var app := Main.new()
	app.saves = Save.new("user://shared-menu-test-%d.json" % Time.get_ticks_usec())
	app.saves.data.settings.sound = false
	app.saves.data.settings.haptics = false
	_check(app.saves.flush(), "Prepare isolated muted shared-menu save")
	root.add_child(app)
	await process_frame
	_check(not app.soundscape.sound_enabled and not app.soundscape.ambience.playing, "Shared-menu fixture starts with audio muted")
	app._show_home()
	var replays := _button(app.overlay, "Replays")
	_check(replays != null and _button(app.overlay, "Your replays") == null and _button(app.overlay, "Shared replays") == null, "Actual home has one Replays entry instead of separate local and shared buttons")
	if replays != null: replays.pressed.emit()
	var solo_tab := _button(app.overlay, "Solo")
	var together_tab := _button(app.overlay, "Together")
	_check(app.mode == "collection" and solo_tab != null and solo_tab.disabled and together_tab != null and not together_tab.disabled, "Replays opens the Solo library with a distinct Together destination")
	_check(_button(app.overlay, "Replays from your online room") == null, "Own replay list no longer mixes in the active online room")
	app.identity_loading = true
	if together_tab != null: together_tab.pressed.emit()
	_check(app.mode == "shared_replays" and _button(app.overlay, "Account & recovery") != null and app.shared_replays == null, "Together tab opens shared replays, and unknown identity cannot open another owner's saved list")
	root.remove_child(app)
	app.queue_free()
	await process_frame

func _button(node: Node, text: String) -> Button:
	if node is Button and node.text == text: return node
	for child: Node in node.get_children():
		var value := _button(child, text)
		if value != null: return value
	return null

func _check(value: bool, text: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(text)
