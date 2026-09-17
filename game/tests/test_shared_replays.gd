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

class Memory extends RefCounted:
	var values: Dictionary = {}
	var writes := 0
	func load_scope(scope: String) -> Dictionary: return {"ok": true, "found": values.has(scope), "value": values.get(scope, {}).duplicate(true)}
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
	await _viewer(entry, api, owner)
	await _viewer(legacy_entry, api, owner)
	await _delivery_ack(entry, api, owner)
	await _first_photo_read(entry)
	var relay := _snapshot(Registry.RELAY, "T".repeat(22))
	_check(collection._remember_room(relay, "chapter") and collection.memories("chapter:" + str(relay.room_id)).size() == 2, "Original Relay schema and proof chain are supported alongside First Steps")
	await _identity_race(collection, api, owner, cache)
	_disk()
	await _home_entries()
	api.queue_free()
	await process_frame
	print("SHARED REPLAYS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _viewer(entry: Dictionary, api: Node, owner: RefCounted) -> void:
	var view := View.new()
	view.entry = entry
	view.api = api
	view.identity = owner.identity
	view.settings = {"sound": false, "haptics": false, "reduced_motion": true}
	root.add_child(view)
	view.set_physics_process(false)
	view.world.set_process(false)
	view.backgrounded = false
	_check(view.mode == "replay" and view.running and not view.controls.stick.visible, "Real shared replay viewer starts without editable gameplay controls")
	var original := Canonical.digest(entry)
	for i in range(5): view._physics_process(1.0 / 30.0)
	var cursor: int = view.cursor
	view._pause()
	_check(not view.running and view.mode == "paused" and view.cursor == cursor, "Shared replay pause retains its exact presentation cursor")
	view._resume()
	var limit := 0
	while view.running and limit < 610:
		view._physics_process(1.0 / 30.0)
		limit += 1
	_check(view.mode == "complete" and view.sim.snapshot().can_commit and Canonical.digest(entry) == original, "Actual input replay finishes successfully without altering the source pair")
	_check(_button(view.controls.overlay, "Replay") != null and _button(view.controls.overlay, "Save turn") == null, "Completed shared viewer offers replay and return, never Save or fork")
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
		var session := View.ReadSession.new(api, owner.identity, store)
		session.photo_targets = Collection.photo_turns(entry, HOST)
		session.photo_library = library
		session.photo_store = Memory.new()
		var target: Dictionary = session.photo_targets[0]
		api.photo = {"schema_version": 1, "turn_id": target.turn_id, "owner_player_id": target.owner_player_id, "recording_hash": target.recording_hash, "photo_revision": 1, "sha256": PhotoController._digest(api.bytes), "width": 24, "height": 24, "byte_length": api.bytes.size(), "updated_at": "2026-09-15T00:00:00Z"}
		_check(session._owner.is_empty() and api.calls.is_empty(), "Fresh photo session has no earlier bind or transport: " + scenario)
		var controller := session.create_photo_controller(Callable())
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
	root.add_child(app)
	await process_frame
	app._show_home()
	_check(_button(app.overlay, "Your replays") != null and _button(app.overlay, "Shared replays") != null, "Actual home has distinct local and shared replay destinations")
	app._show_collection()
	_check(_button(app.overlay, "Replays from your online room") == null, "Own replay list no longer mixes in the active online room")
	app.identity_loading = true
	app._show_shared_replays()
	_check(_button(app.overlay, "Account & recovery") != null and app.shared_replays == null, "Unknown identity cannot open another owner's saved shared list")
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
