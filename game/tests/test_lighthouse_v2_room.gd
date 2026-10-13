extends SceneTree
## sleeping-lighthouse@2 as a six-stage room: the coordinator, the session,
## the photo controller and the id grammars read the stage count from the
## chapter, and a room journal is sized by it. Native proofs come from the
## C2 chain fixture; transport and storage are synthetic.
const Existing = preload("res://tests/test_relay_room_coordinator.gd")
const Coordinator = preload("res://services/relay_room_coordinator.gd")
const Session = preload("res://services/relay_online_session.gd")
const PhotoController = preload("res://services/turn_photo_controller.gd")
const SafetyStore = preload("res://services/safety_store.gd")
const AuxiliaryContext = preload("res://services/campaign_auxiliary_context.gd")
const RoomStages = preload("res://services/room_stages.gd")
const Store = preload("res://services/relay_online_store.gd")
const Registry = preload("res://services/chapter_registry.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const HOST := "HHHHHHHHHHHHHHHHHHHHHH"
const GUEST := "GGGGGGGGGGGGGGGGGGGGGG"
const ROOM := "RRRRRRRRRRRRRRRRRRRRRR"
const KEY := Registry.LIGHTHOUSE_V2
## The Lighthouse's turn cap: 600 ticks (20 s).
const TURN_TICKS := 600
var checks := 0
var failures := 0
var chain: Dictionary
var level: Dictionary

class MemoryStore extends RefCounted:
	var values: Dictionary = {}
	func load_scope(scope: String) -> Dictionary:
		return {"ok": true, "found": values.has(scope), "value": values.get(scope, {}).duplicate(true)}
	func save_scope(scope: String, value: Dictionary) -> Dictionary:
		values[scope] = JSON.parse_string(JSON.stringify(value))
		return {"ok": true}

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	chain = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/lighthouse/v2-chain.json"))
	level = Registry.definition(KEY)
	_check(RoomStages.count(level) == 6 and Registry.descriptor(KEY).stage_count == 6, "The chapter has six stages")
	_check(Canonical.same(chain.definition, level), "The fixture chain is the registered chapter")
	await _coordinator_walk()
	await _fork_and_pairs()
	_refusals()
	_session_and_photos()
	_grammars()
	_journal_bounds()
	print("LIGHTHOUSE V2 ROOM: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

## A room snapshot at stage index k (6 = complete), as the server sends it to the host.
func _room(k: int, with_a: bool, revision: int, branch: int = 0) -> Dictionary:
	var complete := k == RoomStages.count(level)
	var first := ""
	var second := ""
	if not complete:
		first = HOST if level.stages[k].first_player_slot == "p0" else GUEST
		second = GUEST if first == HOST else HOST
	var completed: Array = []
	for index in range(k): completed.append("p%d-%d" % [0 if index < 3 or branch == 0 else branch, index])
	return {"schema_version": 2, "api_version": 2, "room_id": ROOM, "revision": revision, "branch": branch, "stage_index": k,
		"level_id": level.id, "level_version": level.version, "definition_hash": Canonical.digest(level), "host_id": HOST, "guest_id": GUEST,
		"checkpoint": chain.checkpoints[k].duplicate(true), "a_turn_id": "t%d-%d-a" % [branch, k] if with_a else null, "completed_pair_ids": completed,
		"invite_code": "A1".repeat(10), "invite_expires_at": "2026-10-01T12:00:00Z", "created_at": "2026-09-27T12:00:00Z", "updated_at": "2026-09-27T12:00:00Z",
		"active_role": "complete" if complete else ("b" if with_a else "a"), "first_player_id": null if complete else first,
		"active_player_id": null if complete else (second if with_a else first), "player_slot": "p0", "stage_id": "" if complete else level.stages[k].id,
		"recording_a": chain.pairs[k].a.duplicate(true) if with_a else null, "validation": "structural_client_replay_required"}

func _ok(value: Variant) -> Dictionary: return {"ok": true, "status": 200, "data": value}

func _coordinator() -> Array:
	var disk := Existing.Boundary.new()
	var coordinator := Coordinator.new(disk.transport, disk.load_store, disk.save_store, disk.owner, disk.key)
	_check(coordinator.bind_room(ROOM), "A six-stage room journal binds")
	return [coordinator, disk]

## Every stage of a six-stage room is accepted in order, and the host's last
## B turn completes it at stage index 6.
func _coordinator_walk() -> void:
	var made := _coordinator()
	var coordinator: RefCounted = made[0]
	var disk: RefCounted = made[1]
	var revision := 1
	for k in range(6):
		for with_a: bool in [false, true]:
			disk.responses.append(_ok(_room(k, with_a, revision)))
			_check(await coordinator.refresh(), "Stage %d %s is a valid six-stage room" % [k + 1, "B" if with_a else "A"])
			revision += 1
	_check(coordinator.snapshot().stage_index == 5 and coordinator.role() == "b" and coordinator.my_turn(), "The host records the last B turn")
	var final_b: Dictionary = chain.pairs[5].b
	disk.responses.append(func(request: Dictionary) -> Dictionary:
		var body: Dictionary = request.body
		var receipt := {"schema_version": 2, "room_id": ROOM, "idempotency_key": body.idempotency_key, "request_hash": Coordinator._request_hash("turns", body),
			"operation": "turns", "accepted_revision": int(body.base_revision) + 1, "branch": 0, "stage_index": 5, "stage_id": level.stages[5].id,
			"turn_id": "t0-5-b", "recording_hash": final_b.recording_hash, "pair_id": "p0-5", "checkpoint_hash": chain.checkpoints[6].checkpoint_hash}
		return _ok({"receipt": receipt, "room": _room(6, false, int(body.base_revision) + 1)}))
	_check(await coordinator.commit(final_b), "The last B turn commits with its stage-6 checkpoint")
	var sent: Dictionary = disk.requests.back().body
	_check(Canonical.same(sent.get("checkpoint"), chain.checkpoints[6]), "The derived checkpoint nests all six proofs")
	_check(coordinator.chapter_complete() and int(coordinator.snapshot().stage_index) == 6 and coordinator.pending().is_empty(), "The room is complete only at stage index 6")
	var restarted := Coordinator.new(disk.transport, disk.load_store, disk.save_store, disk.owner, disk.key)
	_check(restarted.bind_room(ROOM) and not restarted.read_only and restarted.chapter_complete(), "A cold restart verifies the complete six-stage journal")

## Fork back into the middle of the chapter, and read a stage-5 pair.
func _fork_and_pairs() -> void:
	var made := _coordinator()
	var coordinator: RefCounted = made[0]
	var disk: RefCounted = made[1]
	disk.responses.append(_ok(_room(5, true, 20)))
	_check(await coordinator.refresh(), "A room at stage 6 B is accepted")
	_check(not await coordinator.fork(6) and coordinator.last_code == "nothing_to_fork", "Stage index 6 cannot be forked")
	_check(not await coordinator.fork(7) and coordinator.last_code == "nothing_to_fork", "Stage index 7 cannot be forked")
	var requests: int = disk.requests.size()
	disk.responses.append(func(request: Dictionary) -> Dictionary:
		var body: Dictionary = request.body
		var receipt := {"schema_version": 2, "room_id": ROOM, "idempotency_key": body.idempotency_key, "request_hash": Coordinator._request_hash("fork", body),
			"operation": "fork", "accepted_revision": int(body.base_revision) + 1, "branch": 1, "stage_index": 3, "stage_id": level.stages[3].id,
			"turn_id": null, "recording_hash": null, "pair_id": null, "checkpoint_hash": chain.checkpoints[3].checkpoint_hash}
		return _ok({"receipt": receipt, "room": _room(3, false, int(body.base_revision) + 1, 1)}))
	_check(await coordinator.fork(3), "A fork back to stage 4 walks the nested proofs back three steps")
	_check(disk.requests.size() == requests + 1 and int(disk.requests.back().body.stage_index) == 3, "The fork request names stage index 3")
	_check(int(coordinator.snapshot().branch) == 1 and int(coordinator.snapshot().stage_index) == 3 and coordinator.role() == "a", "The forked room plays stage 4 again")
	disk.responses.append(_ok({"pair_id": "p0-4", "branch": 0, "stage_index": 4, "a": chain.pairs[4].a, "b": chain.pairs[4].b, "checkpoint": chain.checkpoints[5]}))
	var pair: Dictionary = await coordinator.fetch_pair("p0-4")
	_check(not pair.is_empty() and int(pair.stage_index) == 4, "A stage-5 pair is fetched and natively derived")
	requests = disk.requests.size()
	for id: String in ["p0-6", "p0-7", "p0-8"]:
		_check((await coordinator.fetch_pair(id)).is_empty(), "A pair past the last stage is refused: " + id)
	_check(disk.requests.size() == requests, "...before any request is made")
	disk.responses.append(_ok({"pair_id": "p0-4", "branch": 0, "stage_index": 4, "a": chain.pairs[3].a, "b": chain.pairs[3].b, "checkpoint": chain.checkpoints[5]}))
	_check((await coordinator.fetch_pair("p0-4")).is_empty(), "A pair with another stage's records is refused")

func _refusals() -> void:
	var made := _coordinator()
	var coordinator: RefCounted = made[0]
	var probe := func(value: Dictionary) -> bool: return coordinator.verify_room_snapshot(value)
	# Bind the chapter first, as a real room open does.
	coordinator.accept_room_snapshot(_room(2, false, 5))
	_check(probe.call(_room(4, true, 9)), "A later valid stage passes the navigation probe")
	var past := _room(6, false, 9)
	past.stage_index = 7
	past.completed_pair_ids.append("p0-6")
	_check(not probe.call(past), "Stage index 7 is refused")
	var early := _room(2, false, 9)
	early.stage_id = ""
	early.active_role = "complete"
	early.first_player_id = null
	early.active_player_id = null
	_check(not probe.call(early), "A six-stage room is not complete at stage index 2")
	var mismatched := _room(4, false, 9)
	mismatched.checkpoint = chain.checkpoints[3].duplicate(true)
	_check(not probe.call(mismatched), "A checkpoint from another stage is refused")
	var skipped := _room(4, false, 9)
	skipped.completed_pair_ids = ["p0-0", "p0-1", "p0-2"]
	_check(not probe.call(skipped), "A completed pair list shorter than the stage index is refused")
	var two_stage := Registry.definition(Registry.TURN_OF_THE_TIDE)
	_check(RoomStages.within(1, two_stage) and not RoomStages.within(2, two_stage) and RoomStages.within(5, level) and not RoomStages.within(6, level) and not RoomStages.within(-1, level) and not RoomStages.within(1.5, level), "Stage bounds come from each chapter")

func _session_and_photos() -> void:
	var identity := func() -> Dictionary: return {"ready": true, "player_id": HOST, "epoch": 1}
	var api := Node.new()
	var session := Session.new(api, identity, MemoryStore.new())
	_check(session._ready(), "The session binds its identity")
	var disk := Existing.Boundary.new()
	var coordinator := Coordinator.new(disk.transport, disk.load_store, disk.save_store, disk.owner, disk.key)
	coordinator.bind_room(ROOM)
	coordinator.accept_room_snapshot(_room(6, false, 30))
	session.coordinator = coordinator
	var pairs: Array = session.chapter_pairs()
	_check(pairs.size() == 6, "A complete room lists all six pairs")
	var ordered := true
	for index in range(pairs.size()):
		ordered = ordered and Canonical.same(pairs[index].a, chain.pairs[index].a) and Canonical.same(pairs[index].b, chain.pairs[index].b)
	_check(ordered, "...in stage order")
	# A stage-6 B turn the host recorded is a photo target; stage index 6 is not.
	var room := _room(6, false, 30)
	var receipt := {"schema_version": 2, "room_id": ROOM, "idempotency_key": "k".repeat(20), "request_hash": "a".repeat(64), "operation": "turns",
		"accepted_revision": 30, "branch": 0, "stage_index": 5, "stage_id": level.stages[5].id, "turn_id": "t0-5-b",
		"recording_hash": chain.pairs[5].b.recording_hash, "pair_id": "p0-5", "checkpoint_hash": chain.checkpoints[6].checkpoint_hash}
	var target: Dictionary = session._photo_hint_target(receipt, room)
	_check(target.get("turn_id") == "t0-5-b" and int(target.get("stage_index", -1)) == 5, "The session accepts a stage-6 photo receipt")
	var photos := PhotoController.new(Callable(), Callable(), Callable(), identity, Callable())
	photos._owner = HOST
	var accepted: Dictionary = photos._accepted_target({"receipt": receipt, "room": room}, ROOM, receipt.idempotency_key)
	_check(accepted.get("turn_id") == "t0-5-b" and int(accepted.get("stage_index", -1)) == 5, "The photo controller accepts a stage-6 receipt")
	for wrong: Array in [[6, "t0-6-b", "p0-6"], [7, "t0-7-b", "p0-7"]]:
		var bad := receipt.duplicate()
		bad.stage_index = wrong[0]
		bad.turn_id = wrong[1]
		bad.pair_id = wrong[2]
		_check(session._photo_hint_target(bad, room).is_empty() and photos._accepted_target({"receipt": bad, "room": room}, ROOM, receipt.idempotency_key).is_empty(), "A receipt past the last stage is refused: " + str(wrong[1]))
	var wrong_stage := receipt.duplicate()
	wrong_stage.stage_id = level.stages[4].id
	_check(session._photo_hint_target(wrong_stage, room).is_empty(), "A receipt naming another stage is refused")
	api.free()

func _grammars() -> void:
	for id: String in ["t0-0-a", "t31-5-b", "t3-7-a"]:
		_check(PhotoController._turn(id) and SafetyStore.matches(id, RoomStages.TURN_ID), "Turn ids carry any stage digit below 8: " + id)
	for id: String in ["t0-8-a", "t32-1-a", "t0-12-b", "t0-1-c"]:
		_check(not PhotoController._turn(id), "Turn ids outside the grammar are refused: " + id)
	var report := {"schema_version": 1, "room_family": "relay", "room_id": ROOM, "idempotency_key": "k".repeat(20), "reason": "other",
		"photo": {"turn_id": "t0-5-a", "sha256": "a".repeat(64), "photo_revision": 1}}
	_check(SafetyStore.valid_report(report), "A photo report can name a stage-6 turn")
	report.photo.turn_id = "t0-8-a"
	_check(not SafetyStore.valid_report(report), "...but not a stage digit of 8")
	var ack := {"method": HTTPClient.METHOD_POST, "path": "/v2/rooms/" + ROOM + "/photos/t2-5-b/ack", "body": {"photo_revision": 1, "sha256": "a".repeat(64), "recording_hash": "b".repeat(64)}}
	_check(AuxiliaryContext.delivery_ack(ack), "A stage-6 photo delivery acknowledgement is routable")
	ack.path = "/v2/rooms/" + ROOM + "/photos/t2-8-b/ack"
	_check(not AuxiliaryContext.delivery_ack(ack), "...and a stage digit of 8 is not")

## C4: a journal's node cap comes from its chapter's stage count.
func _journal_bounds() -> void:
	_check(Coordinator.journal_nodes(Registry.definition(Registry.RELAY)) == 140000 and Coordinator.journal_nodes(Registry.definition(Registry.TURN_OF_THE_TIDE)) == 140000, "Two-stage chapters keep the 140k journal cap")
	_check(Coordinator.journal_nodes(level) == 420000, "The six-stage Lighthouse journal cap is 420k values")
	# The widest structure: a receiver's draft at stage 6, four held drafts and
	# an unresolved B submission, every record in every nested proof widened to
	# 600 one-tick runs.
	var widened: Array = []
	for checkpoint: Dictionary in chain.checkpoints: widened.append(_widen_checkpoint(checkpoint.duplicate(true)))
	var origin := _room(5, true, 999, 0)
	origin.checkpoint = widened[5]
	origin.recording_a = _widest(chain.pairs[5].a)
	var b: Dictionary = _widest(chain.pairs[5].b)
	var draft := {"origin": origin, "recording": b}
	var hash := "f".repeat(64)
	var journal := {"schema_version": 1, "api_version": 2, "owner_player_id": HOST, "room_id": ROOM, "snapshot": origin, "draft": draft, "held_drafts": [draft, draft, draft, draft],
		"pending": {"operation": "turns", "body": {"base_revision": 999, "idempotency_key": "k".repeat(80), "branch": 0, "recording": b, "checkpoint": widened[6]}, "request_hash": hash, "origin": origin, "held": false, "error_code": ""},
		"last_receipt": {}, "auth_required": false}
	var nodes := _nodes(journal)
	var size := JSON.stringify(journal).to_utf8_buffer().size()
	print("LIGHTHOUSE WIDEST JOURNAL: %d nodes / %d bytes; widest checkpoint %d values / %d bytes" % [nodes, size, _nodes(widened[6]), JSON.stringify(widened[6]).to_utf8_buffer().size()])
	_check(Coordinator._journal_bounded(journal), "The widest six-stage journal fits its chapter's cap")
	_check(not Coordinator._bounded_nodes(journal, Coordinator.MAX_BYTES, 140000), "...which the two-stage 140k cap would refuse")
	_check(nodes * 5 <= Coordinator.journal_nodes(level) * 4 and size * 2 <= Coordinator.MAX_BYTES, "...with room to spare: %d of %d values, %d of %d bytes" % [nodes, Coordinator.journal_nodes(level), size, Coordinator.MAX_BYTES])
	_check(Coordinator._bounded(origin) and Coordinator._pair_bounded({"a": b, "b": b, "checkpoint": widened[6]}), "One widest snapshot and pair stay inside the unchanged per-value caps")
	# Exactly at the cap fits; one value more does not.
	var filled := journal.duplicate(true)
	var filler: Array = []
	filler.resize(Coordinator.journal_nodes(level) - nodes - 1)
	filled["unknown"] = filler
	_check(_nodes(filled) == Coordinator.journal_nodes(level) and Coordinator._journal_bounded(filled), "A six-stage journal at exactly its node cap fits")
	filler.append(null)
	_check(not Coordinator._journal_bounded(filled), "One value more is refused")
	# The store keeps it under the unchanged 8 MiB room value cap.
	var directory := "user://lighthouse-room-journal-" + Crypto.new().generate_random_bytes(8).hex_encode()
	DirAccess.make_dir_recursive_absolute(directory)
	var scope := "relay-room-v2:" + HOST + ":" + ROOM
	var store := Store.new(directory)
	_check(store.save_scope(scope, journal).ok and Canonical.same(Store.new(directory).load_scope(scope).get("value"), journal), "The store saves and cold-reads the widest six-stage journal")
	var path := directory.path_join(scope.sha256_text() + ".json")
	for suffix: String in ["", ".tmp", ".backup"]:
		if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(path + suffix)
	DirAccess.remove_absolute(directory)
	# The real maximal journal (native proofs, four held drafts, pending B)
	# survives a cold restart with every proof re-verified.
	var made := _coordinator()
	var coordinator: RefCounted = made[0]
	var disk: RefCounted = made[1]
	disk.responses.append(_ok(_room(5, true, 40)))
	_check(await coordinator.refresh(), "A stage-6 B room opens")
	for branch in range(4):
		_check(coordinator.save_draft(chain.pairs[5].b), "A current draft natively verifies")
		var next := _room(5, true, 41 + branch, branch + 1)
		next.completed_pair_ids = ["p0-0", "p0-1", "p0-2", "p0-3", "p0-4"]
		next.a_turn_id = "t%d-5-a" % (branch + 1)
		disk.responses.append(_ok(next))
		_check(await coordinator.refresh(), "A new branch holds the previous draft")
	_check(coordinator.held_drafts().size() == 4 and coordinator.save_draft(chain.pairs[5].b), "Four held drafts and a current one")
	_check(not await coordinator.commit(chain.pairs[5].b) and not coordinator.pending().is_empty(), "A lost reply keeps the B submission pending")
	var restarted := Coordinator.new(disk.transport, disk.load_store, disk.save_store, disk.owner, disk.key)
	_check(restarted.bind_room(ROOM) and not restarted.read_only and restarted.held_drafts().size() == 4 and Canonical.same(restarted.pending(), coordinator.pending()), "A cold restart verifies every held draft and the pending proof")

func _widen_checkpoint(checkpoint: Dictionary) -> Dictionary:
	var proof: Variant = checkpoint.get("proof")
	if proof is Dictionary and not proof.is_empty():
		proof.a = _widest(proof.a)
		proof.b = _widest(proof.b)
		proof.checkpoint = _widen_checkpoint(proof.checkpoint)
	return checkpoint

func _widest(record: Dictionary) -> Dictionary:
	var result := record.duplicate(true)
	var actions: Array = []
	for index in range(TURN_TICKS): actions.append({"action": index % 2 == 1, "ticks": 1, "x": -100, "z": -100})
	var count := TURN_TICKS / 30 + 1
	var replay_checks: Array = []
	for index in range(count): replay_checks.append({"tick": TURN_TICKS - count + 1 + index, "state_hash": record.final_state_hash})
	result.actions = actions
	result.replay_checks = replay_checks
	result.duration_ticks = TURN_TICKS
	return result

func _nodes(value: Variant) -> int:
	var count := 1
	if value is Dictionary:
		for child: Variant in value.values(): count += _nodes(child)
	elif value is Array:
		for child: Variant in value: count += _nodes(child)
	return count

func _check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)
