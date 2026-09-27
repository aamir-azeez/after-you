extends SceneTree
## New chapter evidence traverses the same durable local and online boundaries.
const Registry = preload("res://services/chapter_registry.gd")
const Journey = preload("res://services/relay_journey.gd")
const Storage = preload("res://services/local_save.gd")
const Coordinator = preload("res://services/relay_room_coordinator.gd")
const Simulation = preload("res://core/cooperative/simulation.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const Boundaries = preload("res://tests/test_relay_room_coordinator.gd")
const HOST := "HHHHHHHHHHHHHHHHHHHHHH"
const GUEST := "GGGGGGGGGGGGGGGGGGGGGG"
const ROOM := "RRRRRRRRRRRRRRRRRRRRRR"
var checks := 0
var failures := 0
var documents: Dictionary = {}
var directory := "user://cooperative-integration-" + Crypto.new().generate_random_bytes(8).hex_encode()

class Disk extends Storage:
	var reject := false
	func update_values(changes: Dictionary, erase_keys: Array = []) -> bool:
		if reject:
			last_error = "Synthetic storage failure"
			return false
		return super(changes, erase_keys)

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(directory)
	for key: String in [Registry.HIGH_AND_LOW, Registry.ROLLING_HOME]:
		var level := Registry.definition(key)
		var item := {"definition": level, "pairs": [], "checkpoints": [_fixture(level.id + "-initial-checkpoint")]}
		_check(Canonical.same(level, _fixture(level.id + "-definition")), "Backend-shared definition remains exact for " + key)
		for stage: Dictionary in level.stages:
			item.pairs.append({"a": _fixture(stage.id + "-a"), "b": _fixture(stage.id + "-b")})
			item.checkpoints.append(_fixture(stage.id + "-checkpoint"))
		if failures: break
		documents[key] = item
		_local(key, item)
		await _online(key, item)
	for filename: String in DirAccess.get_files_at(directory): DirAccess.remove_absolute(directory.path_join(filename))
	DirAccess.remove_absolute(directory)
	print("COOPERATIVE INTEGRATION: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _local(key: String, item: Dictionary) -> void:
	var path := directory.path_join(item.definition.id + ".json")
	var disk := Disk.new(path)
	var journal := Journey.new(path, disk, key)
	journal.load_data()
	_check(not journal.read_only and journal.stage_id() == item.definition.stages[0].id, "Each chapter opens its own empty journal")
	var live: RefCounted = journal.create_live_simulation()
	_check(live != null and live.get_script() == Simulation, "The registry supplies the physical engine to the actual journal")
	if live == null: return
	live.step({"move_x": 1.0})
	_check(journal.save_live_draft(live), "The registered live engine saves an actual rehearsal interval")
	var draft: Dictionary = journal.draft()
	var restart := Journey.new(path, null, key)
	restart.load_data()
	_check(not restart.read_only and Canonical.same(restart.draft(), draft) and restart.pairs().is_empty(), "Restart retains the exact draft without accepting it")
	var before := _hashes(path)
	var foreign := Journey.new(path, null, Registry.ROLLING_HOME if key == Registry.HIGH_AND_LOW else Registry.HIGH_AND_LOW)
	foreign.load_data()
	_check(foreign.read_only and _hashes(path) == before, "Opening the journal with another chapter preserves all saved generations")
	disk.reject = true
	_check(not journal.accept_recording(item.pairs[0].a) and journal.role() == "a" and _hashes(path) == before, "A failed first acceptance rolls back role and exact durable bytes")
	disk.reject = false
	_check(journal.accept_recording(item.pairs[0].a), "A real verified source advances only after its durable write")
	live = journal.create_live_simulation()
	if live == null:
		_check(false, "Accepted source must permit a live receiver")
		return
	for frame: Dictionary in Simulation.expand_recording_inputs(item.pairs[0].b).slice(0, 20): live.step(frame)
	_check(journal.save_live_draft(live), "Receiver rehearsal uses the immutable accepted source")
	before = _hashes(path)
	var source_hash := Canonical.digest(journal.prior_recording())
	var forged: Dictionary = item.pairs[0].b.duplicate(true)
	forged.actions[0].x = 100 if forged.actions[0].x != 100 else -100
	forged.recording_hash = Simulation.recording_hash(forged)
	_check(not journal.accept_recording(forged) and _hashes(path) == before and Canonical.digest(journal.prior_recording()) == source_hash, "Rehashed receiver tampering preserves the real draft and accepted source")
	_check(journal.accept_recording(item.pairs[0].b) and journal.pairs().size() == 1 and not journal.chapter_complete(), "One real pair cannot complete the two-stage chapter")
	_check(journal.accept_recording(item.pairs[1].a) and journal.accept_recording(item.pairs[1].b), "The role-swapped second pair accepts against its exact carried state")
	var completed: Array = journal.pairs()
	_check(journal.chapter_complete() and Canonical.same(journal.checkpoint(), item.checkpoints[2]), "Completion keeps exact native-generated physical proof")
	_check(journal.fork_from_stage(1) and journal.pairs().size() == 1, "Retrying the second stage preserves the independently completed first pair")
	var archives: Array = journal.archived_attempts()
	_check(archives.size() == 1 and Canonical.same(journal.archived_pairs(archives[0].id), completed), "A retry retains the previous complete attempt for replay")

func _online(key: String, item: Dictionary) -> void:
	var boundary := Boundaries.Boundary.new()
	var coordinator := Coordinator.new(boundary.transport, boundary.load_store, boundary.save_store, boundary.owner, boundary.key)
	_check(coordinator.bind_room(ROOM), "Bind a new room within the injected test owner")
	boundary.responses.append(_ok(_room(item)))
	_check(await coordinator.refresh() and coordinator.chapter_key() == key, "The real coordinator replay-verifies the new chapter snapshot")
	var live: RefCounted = coordinator.create_live_simulation()
	_check(live != null and live.get_script() == Simulation, "Online admission dispatches the bundled version-six engine")
	if live == null: return
	live.step({"move_x": 1.0})
	var saved_live: bool = coordinator.save_live_draft(live)
	_check(saved_live, "Online rehearsals persist through the existing live-draft boundary: " + coordinator.last_code + " " + coordinator.last_error)
	if key == Registry.ROLLING_HOME:
		boundary.responses.append({"ok": false, "status": 402, "code": "host_unlock_required"})
	_check(not await coordinator.commit(item.pairs[0].a), "A lost acknowledgement or host access hold leaves the submitted source pending")
	var pending: Dictionary = coordinator.pending()
	_check(not pending.is_empty() and boundary.all_posts_persisted, "The source request is durable before transport")
	if pending.is_empty(): return
	_check(not pending.held, "A recoverable purchase hold does not retire the original source request")
	var restarted := Coordinator.new(boundary.transport, boundary.load_store, boundary.save_store, boundary.owner, boundary.key)
	_check(restarted.bind_room(ROOM) and Canonical.same(restarted.pending(), pending), "Restart preserves the exact idempotent source request")
	if key == Registry.ROLLING_HOME:
		boundary.responses.append({"ok": false, "status": 404, "code": "operation_not_found"})
	boundary.responses.append(_ok(_receipt(pending.body, _room(item, 0, true, 2))))
	_check(await restarted.reconcile() and restarted.pending().is_empty(), "The matching receipt reconciles the original accepted source")
	if key == Registry.ROLLING_HOME:
		_check(Canonical.same(boundary.requests[-1].body, pending.body), "Restored paid-host access retries the exact body and key after a missing receipt")
	boundary.responses.append(_ok(_room(item, 1, false, 3)))
	_check(await restarted.refresh() and restarted.create_live_simulation() == null, "The host waits when the physical source role moves to its partner")
	boundary.responses.append(_ok(_room(item, 1, true, 4)))
	_check(await restarted.refresh(), "The second source arrives with independently replayed prior-stage proof")
	live = restarted.create_live_simulation()
	_check(live != null and live.active_slot == "p0", "The same host becomes the later receiver without switching physical identity")
	var before: Dictionary = restarted.snapshot()
	var wrong := _room(item, 1, true, 5)
	wrong.definition_hash = "f".repeat(64)
	boundary.responses.append(_ok(wrong))
	_check(not await restarted.refresh() and Canonical.same(restarted.snapshot(), before), "Unknown chapter hashes cannot replace the last verified room")
	boundary.responses.append(_ok(_room(item, 2, false, 5)))
	_check(await restarted.refresh() and restarted.snapshot().active_role == "complete", "A full two-stage room proof reaches completion through the shared coordinator")

func _room(item: Dictionary, index: int = 0, has_a: bool = false, revision: int = 1) -> Dictionary:
	var level: Dictionary = item.definition
	var first: Variant = HOST if index == 0 else GUEST
	var second: Variant = GUEST if index == 0 else HOST
	return {"schema_version": 2, "api_version": 2, "simulation_version": 6, "room_id": ROOM, "revision": revision, "branch": 0,
		"stage_index": index, "level_id": level.id, "level_version": level.version, "definition_hash": Canonical.digest(level),
		"host_id": HOST, "guest_id": GUEST, "checkpoint": item.checkpoints[index], "a_turn_id": "t0-%d-a" % index if has_a else null,
		"completed_pair_ids": ["p0-0", "p0-1"].slice(0, index), "invite_code": "A1".repeat(10),
		"invite_expires_at": "2026-09-30T12:00:00Z", "created_at": "2026-09-27T12:00:00Z", "updated_at": "2026-09-27T12:00:00Z",
		"active_role": "complete" if index == 2 else "b" if has_a else "a", "first_player_id": null if index == 2 else first,
		"active_player_id": null if index == 2 else second if has_a else first, "player_slot": "p0",
		"stage_id": "" if index == 2 else level.stages[index].id, "recording_a": item.pairs[index].a if has_a else null,
		"validation": "structural_client_replay_required"}

func _receipt(body: Dictionary, room: Dictionary) -> Dictionary:
	var request := body.duplicate(true)
	request.operation = "turns"
	return {"room": room, "receipt": {"schema_version": 2, "room_id": ROOM, "idempotency_key": body.idempotency_key,
		"request_hash": Canonical.digest(request), "operation": "turns", "accepted_revision": body.base_revision + 1,
		"branch": 0, "stage_index": 0, "stage_id": body.recording.stage_id, "turn_id": "t0-0-a",
		"recording_hash": body.recording.recording_hash, "pair_id": null, "checkpoint_hash": body.recording.checkpoint_hash}}

func _fixture(name: String) -> Dictionary:
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/cooperative/" + name + ".json"))
	_check(value is Dictionary, "Native-generated fixture exists: " + name)
	return value if value is Dictionary else {}

func _hashes(path: String) -> Dictionary:
	var result := {}
	for suffix: String in ["", ".backup", ".tmp"]:
		result[suffix] = FileAccess.get_sha256(path + suffix) if FileAccess.file_exists(path + suffix) else "absent"
	return result

func _ok(value: Dictionary) -> Dictionary: return {"ok": true, "status": 200, "data": value}

func _check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)
