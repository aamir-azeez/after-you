extends SceneTree
const Transfer = preload("res://services/replay_transfer.gd")
const Store = preload("res://services/shared_replay_store.gd")
const Cleanup = preload("res://services/deleted_identity_cache_cleanup.gd")
const Registry = preload("res://services/chapter_registry.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const Fixture = preload("res://tests/replay_transfer_fixture.gd")
const Memory = Fixture.Memory
const HOST := Fixture.HOST
const GUEST := Fixture.GUEST
const ROOM := Fixture.ROOM
const OTHER := Fixture.OTHER
var checks := 0
var failures := 0

class Boundary extends RefCounted:
	var identity := {"ready": true, "player_id": HOST, "epoch": 1}
	var context := {"ok": true, "server_key": "a".repeat(64), "standalone": true, "gameplay_pending": false, "photo_pending": false, "redo_pending": false, "enabled": true}
	var calls: Array = []
	var replies: Array = []
	var on_request: Callable
	func owner() -> Dictionary: return identity.duplicate(true)
	func eligible(_room: String) -> Dictionary: return context.duplicate(true)
	func transport(request: Dictionary) -> Dictionary:
		calls.append(request.duplicate(true))
		if on_request.is_valid(): on_request.call(request)
		if replies.is_empty(): return {"ok": false, "status": 0, "code": "connection_interrupted"}
		var value: Variant = replies.pop_front()
		return JSON.parse_string(JSON.stringify(value.call(request) if value is Callable else value))

func _initialize() -> void: _run.call_deferred()
func _check(okay: bool, message: String) -> void:
	checks += 1
	if not okay: failures += 1; push_error(message)
func _fixture(path: String) -> Dictionary:
	return Fixture.fixture(path)
func _ok(value: Dictionary) -> Dictionary: return {"ok": true, "status": 200, "data": value}
func _service(boundary: Boundary, store: RefCounted) -> RefCounted:
	return Transfer.new(boundary.transport, boundary.owner, boundary.eligible, store)

func _archive(chapter: String, final_checkpoint: Dictionary) -> Dictionary:
	return Fixture.archive(chapter, final_checkpoint)

func _manifest(archive: Dictionary, epoch: int = 1) -> Dictionary:
	return Fixture.manifest(archive, epoch)

func _transfer(manifest: Dictionary, acked: Array = []) -> Dictionary:
	return {"schema_version": 1, "manifest": manifest.duplicate(true), "acked_player_ids": acked.duplicate(), "transferred": acked.size() == 2}
func _download(archive: Dictionary, manifest: Dictionary) -> Dictionary:
	var value := _transfer(manifest)
	value["archive"] = archive.duplicate(true)
	return _ok(value)

func _run() -> void:
	var archive := _archive(Registry.RELAY, _fixture("v2/final-checkpoint"))
	var manifest := _manifest(archive)
	_native_archives()
	_malformed(archive, manifest)
	await _durability(archive, manifest)
	await _boundaries(archive, manifest)
	await _restore(archive, manifest)
	await _real_store(archive, manifest)
	print("REPLAY TRANSFER: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _native_archives() -> void:
	var paths := {Registry.RELAY: "v2/final-checkpoint", Registry.FIRST_STEPS: "first_steps/final-checkpoint", Registry.HIGH_AND_LOW: "cooperative/high-and-low-final-checkpoint", Registry.ROLLING_HOME: "cooperative/rolling-home-final-checkpoint", Registry.HOUSE: "cooperative/a-house-for-two-final-checkpoint", Registry.CONSERVATORY: "journey/conservatory-final-checkpoint", Registry.LONG_WAY_HOME: "journey/long-way-home-final-checkpoint"}
	for chapter: String in paths:
		var archive := _archive(chapter, _fixture(paths[chapter]))
		var checked := Transfer.verify_archive(archive, _manifest(archive), HOST, ROOM)
		_check(checked.get("ok", false) and checked.get("entries", []).size() == 2, "Published native recordings remain transferable: " + chapter + ": " + str(checked.get("code", "ok")))
	var comfort := _fixture("comfort8/recordings")
	for chapter: String in [Registry.RELAY, Registry.HIGH_AND_LOW, Registry.ROLLING_HOME, Registry.HOUSE, Registry.CONSERVATORY, Registry.LONG_WAY_HOME]:
		var key := "relay" if chapter == Registry.RELAY else chapter.get_slice("@", 0)
		var archive := _archive(chapter, comfort[key].checkpoints[2])
		_check(Transfer.verify_archive(archive, _manifest(archive), GUEST, ROOM).get("ok", false), "Current comfort recordings retain guest access: " + chapter)
	var steps := _fixture("comfort8/first-steps")
	var current_steps := _archive(Registry.FIRST_STEPS, steps.pairs[1].checkpoint)
	_check(Transfer.verify_archive(current_steps, _manifest(current_steps), HOST, ROOM).get("ok", false), "Current First Steps recordings use their native compatibility path")
	var forked := _archive(Registry.RELAY, _fixture("v2/final-checkpoint"))
	# Replay identical native inputs on a later accepted fork, retaining an A
	# from the abandoned branch. No fixture proof is edited or manufactured.
	var orphan: Dictionary = forked.turns[0].duplicate(true)
	orphan.turn_id = "t1-0-a"
	orphan.accepted_revision = 7
	forked.turns.append(orphan)
	for index in range(2):
		var pair: Dictionary = forked.pairs[index].duplicate(true)
		pair.pair_id = "p2-%d" % index
		pair.branch = 2
		forked.pairs.append(pair)
		for role: String in ["a", "b"]:
			var record: Dictionary = pair[role]
			forked.turns.append({"turn_id": "t2-%d-%s" % [index, role], "player_id": HOST if record.player_slot == "p0" else GUEST, "accepted_revision": 9 + index * 2 + (1 if role == "b" else 0), "recording": record.duplicate(true)})
	forked.room.branch = 2
	forked.room.revision = 12
	forked.room.completed_pair_ids = ["p2-0", "p2-1"]
	forked = JSON.parse_string(JSON.stringify(forked))
	var checked := Transfer.verify_archive(forked, _manifest(forked), HOST, ROOM)
	_check(checked.get("ok", false) and checked.get("entries", []).size() == 4 and forked.turns.size() == 9, "All historical pairs and a native orphan A survive archive verification")
	var damaged := forked.duplicate(true)
	damaged.turns[4].recording.actions[0].x = 73
	_check(not Transfer.verify_archive(damaged, _manifest(damaged), HOST, ROOM).get("ok", false), "An orphan turn must replay natively even with a newly recomputed archive hash")

func _malformed(archive: Dictionary, manifest: Dictionary) -> void:
	_check(Transfer.valid_transfer(_transfer(manifest), HOST, ROOM), "Exact server manifest identifies the completed member room")
	_check(manifest.room.simulation_version is float and Transfer.valid_transfer(_transfer(manifest), HOST, ROOM), "Integral JSON numbers use the native supported-rules path")
	var native_numbers := manifest.duplicate(true)
	native_numbers.room.simulation_version = int(native_numbers.room.simulation_version)
	_check(Transfer.valid_transfer(_transfer(native_numbers), HOST, ROOM), "Native integer rules and JSON numeric rules are equivalent")
	for change: String in ["foreign", "room", "duplicate_ack", "false_transfer", "future", "turn_player", "turn_revision", "pair_hash", "invite", "incomplete", "unknown_rules", "fractional_rules", "bad_date", "active_branch", "current_orphan", "orphan_b"]:
		var value := _transfer(manifest)
		if change == "duplicate_ack": value.acked_player_ids = [HOST, HOST]
		elif change == "false_transfer": value.transferred = true
		elif change == "future": value.schema_version = 2
		elif change == "turn_player": value.manifest.turns[0].player_id = GUEST
		elif change == "turn_revision": value.manifest.turns[1].accepted_revision = value.manifest.turns[0].accepted_revision
		elif change == "pair_hash": value.manifest.pairs[0].a_hash = "0".repeat(64)
		elif change == "invite": value.manifest.room["invite_code"] = "A1".repeat(10)
		elif change == "incomplete": value.manifest.room.stage_index = 1
		elif change == "unknown_rules": value.manifest.room.simulation_version = 99
		elif change == "fractional_rules": value.manifest.room.simulation_version = 2.5
		elif change == "bad_date": value.manifest.room.created_at = "2026-13-35T00:00:00.000Z"
		elif change == "active_branch": value.manifest.room.branch = 1
		elif change == "current_orphan":
			value.manifest.room.branch = 1
			value.manifest.room.revision = 7
			value.manifest.pairs[1].pair_id = "p1-1"
			value.manifest.pairs[1].branch = 1
			value.manifest.room.completed_pair_ids[1] = "p1-1"
			value.manifest.turns[2].turn_id = "t1-1-a"
			value.manifest.turns[3].turn_id = "t1-1-b"
			var orphan: Dictionary = value.manifest.turns[0].duplicate()
			orphan.turn_id = "t1-0-a"
			orphan.accepted_revision = 7
			value.manifest.turns.append(orphan)
		elif change == "orphan_b":
			value.manifest.room.branch = 2
			value.manifest.room.revision = 6
			value.manifest.pairs[1].pair_id = "p2-1"
			value.manifest.pairs[1].branch = 2
			value.manifest.room.completed_pair_ids[1] = "p2-1"
			value.manifest.turns[2].turn_id = "t2-1-a"
			value.manifest.turns[3].turn_id = "t2-1-b"
			var orphan: Dictionary = value.manifest.turns[3].duplicate()
			orphan.turn_id = "t1-1-b"
			orphan.accepted_revision = 6
			value.manifest.turns.append(orphan)
		_check(not Transfer.valid_transfer(value, OTHER if change == "foreign" else HOST, OTHER if change == "room" else ROOM), "Malformed metadata cannot authorize transfer: " + change)
	var changed := archive.duplicate(true)
	changed.turns[0].recording.final_state_hash = "0".repeat(64)
	_check(not Transfer.verify_archive(changed, manifest, HOST, ROOM).get("ok", false), "Archive hash is checked independently of the advertised turn hash")
	changed = archive.duplicate(true)
	changed["operations"] = [{"idempotency_key": "private-operation-key"}]
	_check(not Transfer.verify_archive(changed, _manifest(changed), HOST, ROOM).get("ok", false), "Archive cannot retain unrelated private operation keys")

func _durability(archive: Dictionary, manifest: Dictionary) -> void:
	var boundary := Boundary.new()
	var memory := Memory.new()
	var helper := _service(boundary, memory)
	boundary.replies.append(_download(archive, manifest))
	var result: Dictionary = await helper.download(ROOM)
	_check(result.get("ok", false) and result.entries.size() == 2 and boundary.calls.size() == 1 and memory.writes == 1, "Downloading verifies and saves every pair without acknowledging delivery")
	if not result.get("ok", false): return
	var baseline := Canonical.digest(memory.values)
	var reads := memory.reads
	boundary.on_request = func(request: Dictionary):
		if request.method == HTTPClient.METHOD_POST: _check(memory.reads > reads and Canonical.digest(memory.values) == baseline, "ACK follows an independent durable readback and does not rewrite the archive")
	boundary.replies.append(_ok(_transfer(manifest, [HOST])))
	_check((await helper.acknowledge(ROOM, manifest)).get("ok", false), "Exact durable member archive can be acknowledged")
	var body: Dictionary = boundary.calls[1].body
	_check(Transfer._exact(body, ["schema_version", "epoch", "archive_hash"]) and Canonical.same(body, {"schema_version": 1, "epoch": 1, "archive_hash": manifest.archive_hash}), "ACK contains only the exact epoch and archive digest")
	boundary.on_request = Callable()
	var cold := _service(boundary, memory)
	var calls := boundary.calls.size()
	_check((await cold.local_archive(ROOM, manifest)).get("ok", false) and boundary.calls.size() == calls, "Cold local playback needs no network request")
	var transferred := _transfer(manifest, [HOST, GUEST])
	transferred["archive"] = null
	boundary.replies.append(_ok(transferred))
	_check((await cold.download(ROOM)).get("ok", false), "A compacted server response reuses the exact durable local archive")
	for failure: String in ["write", "readback", "missing"]:
		boundary = Boundary.new()
		memory = Memory.new()
		helper = _service(boundary, memory)
		memory.fail_save = failure == "write"
		memory.corrupt_readback = failure == "readback"
		if failure != "missing":
			boundary.replies.append(_download(archive, manifest))
			_check(not (await helper.download(ROOM)).get("ok", false), "Failed local " + failure + " is not durable delivery")
		_check(not (await helper.acknowledge(ROOM, manifest)).get("ok", false) and boundary.calls.all(func(request: Dictionary): return request.method == HTTPClient.METHOD_GET), "No ACK after local " + failure + " failure")

func _boundaries(archive: Dictionary, manifest: Dictionary) -> void:
	for field: String in ["gameplay_pending", "photo_pending", "redo_pending", "enabled"]:
		var boundary := Boundary.new()
		var memory := Memory.new()
		var helper := _service(boundary, memory)
		boundary.replies.append(_download(archive, manifest))
		_check((await helper.download(ROOM)).get("ok", false), "Boundary fixture is genuinely durable")
		boundary.context[field] = field != "enabled"
		var calls := boundary.calls.size()
		_check(not (await helper.acknowledge(ROOM, manifest)).get("ok", false) and boundary.calls.size() == calls, "ACK is held for " + field)
	for change: String in ["identity", "epoch", "server", "standalone"]:
		var boundary := Boundary.new()
		var memory := Memory.new()
		var helper := _service(boundary, memory)
		boundary.replies.append(_download(archive, manifest))
		boundary.on_request = func(_request: Dictionary):
			if change == "identity": boundary.identity.player_id = OTHER
			elif change == "epoch": boundary.identity.epoch += 1
			elif change == "server": boundary.context.server_key = "b".repeat(64)
			else: boundary.context.standalone = false
		_check(not (await helper.download(ROOM)).get("ok", false) and memory.writes == 0, "Late response cannot save across " + change + " change")
		# The mutation fixture deliberately captures its own boundary. Release
		# that test-only cycle after the awaited response has completed.
		boundary.on_request = Callable()
	var boundary := Boundary.new()
	var memory := Memory.new()
	var helper := _service(boundary, memory)
	boundary.replies.append(_download(archive, manifest))
	var retiring := func():
		for _attempt in range(60):
			if helper._worker != null:
				helper.invalidate_identity()
				return
			await process_frame
	retiring.call_deferred()
	_check(not (await helper.download(ROOM)).get("ok", false) and memory.writes == 0 and helper._worker == null, "Retired validation drains its worker but cannot save or ACK")

func _restore(archive: Dictionary, manifest: Dictionary) -> void:
	var boundary := Boundary.new()
	var memory := Memory.new()
	var helper := _service(boundary, memory)
	boundary.replies.append(_download(archive, manifest))
	var downloaded: Dictionary = await helper.download(ROOM)
	_check(downloaded.get("ok", false), "Restore begins with a durable local archive")
	if not downloaded.get("ok", false): return
	var original := Canonical.digest(memory.values)
	boundary.context.enabled = false
	boundary.context.gameplay_pending = true
	boundary.context.redo_pending = true
	_check(not (await helper.restore(ROOM, manifest)).get("ok", false), "Lost restore response remains unresolved")
	var first: Dictionary = boundary.calls[-1]
	var next := manifest.duplicate(true)
	next.epoch = 2
	boundary.replies.append(_ok({"restored": true, "transfer": _transfer(next)}))
	var restored: Dictionary = await helper.restore(ROOM, manifest)
	_check(restored.get("ok", false) and Canonical.same(first, boundary.calls[-1]), "Explicit restore retries exact bytes despite a disabled ACK flag or unresolved redo")
	_check(memory.values.size() == 2 and Canonical.digest({Transfer._scope({"owner": HOST, "room": ROOM}, manifest): memory.values[Transfer._scope({"owner": HOST, "room": ROOM}, manifest)]}) == original, "New restore epoch retains the older durable archive unchanged")
	var calls := boundary.calls.size()
	_check((await helper.local_archive(ROOM, next)).get("ok", false) and boundary.calls.size() == calls, "Restored epoch has its own durable local alias with no download")
	var changed := next.duplicate(true)
	changed.archive_hash = "0".repeat(64)
	_check(not (await helper.restore(ROOM, changed)).get("ok", false) and boundary.calls.size() == calls, "Mismatched local archive is never offered as restore")

func _real_store(archive: Dictionary, manifest: Dictionary) -> void:
	var directory := "user://replay-transfer-%d" % Time.get_ticks_usec()
	var storage := Store.new(directory.path_join("shared"))
	var boundary := Boundary.new()
	var helper := _service(boundary, storage)
	boundary.replies.append(_download(archive, manifest))
	var downloaded: Dictionary = await helper.download(ROOM)
	_check(downloaded.get("ok", false), "Actual recoverable archive is written and reread before delivery: " + str(downloaded.get("code", "ok")))
	if not downloaded.get("ok", false): return
	var scope := Transfer._scope({"owner": HOST, "room": ROOM}, manifest)
	var path := storage.directory.path_join(scope.sha256_text() + ".json")
	var initial := FileAccess.get_file_as_bytes(path)
	var current: Dictionary = storage.load_scope(scope).value
	_check(storage.save_scope(scope, current), "Second exact generation creates a recoverable backup")
	var file := FileAccess.open(path, FileAccess.WRITE)
	_check(file != null, "Fault injection opens only the isolated owned test archive")
	if file == null: return
	file.store_string("{interrupted")
	file.close()
	var cold := _service(boundary, Store.new(storage.directory))
	_check((await cold.local_archive(ROOM, manifest)).get("ok", false), "Truncated newest generation recovers the verified archive")
	var other_scope := "shared-replays:" + OTHER + ":transfer:" + ROOM + ":1"
	_check(storage.save_scope(other_scope, {"schema_version": 1, "owner": OTHER}), "Independent owner archive has a separate ownership envelope")
	var other_path := storage.directory.path_join(other_scope.sha256_text() + ".json")
	var other_bytes := FileAccess.get_file_as_bytes(other_path)
	var large_scope := "shared-replays:" + HOST + ":transfer:" + ROOM + ":3"
	_check(storage.save_scope(large_scope, {"schema_version": 1, "owner": HOST, "test_padding": "x".repeat(Store.MAX_BYTES)}), "Transfer ownership envelope can exceed the ordinary cache file bound")
	var large_path := storage.directory.path_join(large_scope.sha256_text() + ".json")
	_check(FileAccess.get_file_as_bytes(large_path).size() > Store.MAX_BYTES, "Large cleanup fixture actually crosses the former reader limit")
	var cleanup := Cleanup.new()
	cleanup.shared_directory = storage.directory
	cleanup.relay_directory = directory.path_join("relay")
	cleanup.safety_directory = directory.path_join("safety")
	_check(cleanup.erase_owner(HOST).get("ok", false) and not FileAccess.file_exists(path) and not FileAccess.file_exists(path + ".backup") and not FileAccess.file_exists(large_path), "Explicit deleted-identity cleanup includes every owned transfer generation and larger archives")
	_check(FileAccess.get_file_as_bytes(other_path) == other_bytes and not initial.is_empty(), "Transfer cleanup preserves another identity's archive bytes")
	_check(not Store._scope_valid(scope.trim_suffix(":1") + ":0") and not Store._scope_valid(scope.trim_suffix(":1") + ":9007199254740992"), "Epoch scopes are positive exact safe integers")
	_check(Store._file_limit(scope) == 20 * 1024 * 1024 and Store._file_limit("shared-replays:" + HOST + ":index") == 16 * 1024 * 1024, "Archive envelope headroom does not alter ordinary replay bounds")
