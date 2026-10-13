extends SceneTree
## Actual native dense proof through Coordinator; transport is a synthetic server.
const Existing = preload("res://tests/test_relay_room_coordinator.gd")
const Coordinator = preload("res://services/relay_room_coordinator.gd")
const Store = preload("res://services/relay_online_store.gd")
const Registry = preload("res://services/chapter_registry.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const HOST := "HHHHHHHHHHHHHHHHHHHHHH"
const GUEST := "GGGGGGGGGGGGGGGGGGGGGG"
const ROOM := "RRRRRRRRRRRRRRRRRRRRRR"
## Turn of the Tide's turns: 2,700 ticks for A and 3,000 for B.
const TIDE_A_TICKS := 2700
const TIDE_B_TICKS := 3000
var checks := 0
var failures := 0
var proof: Dictionary

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	proof = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/comfort8/dense-physical.json"))
	var disk := Existing.Boundary.new()
	var coordinator := Coordinator.new(disk.transport,disk.load_store,disk.save_store,disk.owner,disk.key)
	_check(coordinator.bind_room(ROOM),"Dense journal binds its actual owner")
	disk.responses.append(_ok(_room(0)))
	_check(await coordinator.refresh(),"Dense stage2 source and prior completed pair independently verify")
	for branch in range(4):
		_check(coordinator.save_draft(proof.pairs[1].b),"Current dense B draft natively verifies before branch change")
		disk.responses.append(_ok(_room(branch+1)))
		_check(await coordinator.refresh(),"A new validated branch retains the prior dense draft")
		_check(coordinator.held_drafts().size() == branch+1,"Each separate old-branch draft remains recoverable")
	_check(coordinator.save_draft(proof.pairs[1].b),"Fifth current dense draft coexists with four held drafts")
	_check(not await coordinator.commit(proof.pairs[1].b),"Lost synthetic response keeps the real native submission pending")
	_check(not coordinator.pending().is_empty() and disk.all_posts_persisted,"Whole pending body is durable before POST despite maximal held drafts")
	var scope := "relay-room-v2:"+HOST+":"+ROOM
	var saved: Dictionary = disk.disk[scope].duplicate(true)
	var nodes := _nodes(saved)
	_check(nodes > 140000 and nodes < 180000,"Actual journal crosses retained node cap but fits explicit8 limit")
	_check(not Coordinator._bounded(saved,Coordinator.MAX_BYTES) and Coordinator._journal_bounded(saved),"Only the full comfort journal receives the node allowance")
	_check(JSON.stringify(saved).to_utf8_buffer().size() < 3145728,"Original3MiB byte bound remains sufficient")
	var before := Canonical.digest(disk.disk)
	var restarted := Coordinator.new(disk.transport,disk.load_store,disk.save_store,disk.owner,disk.key)
	_check(restarted.bind_room(ROOM) and not restarted.read_only,"JSON cold restore verifies all dense retained drafts and pending proof")
	_check(Canonical.digest(disk.disk) == before and Canonical.same(restarted.pending(),coordinator.pending()),"Cold restore neither rewrites saved bytes nor reconstructs a different request")
	disk.responses.append({"ok":false,"status":404,"code":"operation_not_found"})
	_check(not await restarted.reconcile(),"Explicit retry remains unresolved when exact replayed POST loses its reply")
	_check(Canonical.same(disk.requests.back().body,saved.pending.body),"Retry submits the entire original dense body unchanged")
	_check(Canonical.same(disk.disk[scope],saved),"Unknown response preserves full draft and pending evidence")
	var old := saved.duplicate(true)
	old.snapshot.simulation_version = 6
	_check(not Coordinator._journal_bounded(old),"Old journal declaration keeps its exact140k limit")
	for version: int in [9, 10]:
		old.snapshot.simulation_version = version
		_check(not Coordinator._journal_bounded(old),"Rules this chapter does not play receive no journal allowance: %d" % version)
	# The comfort allowance is exact: its node cap fits, one value more does not.
	var filled := saved.duplicate(true)
	var filler: Array = []
	filler.resize(Coordinator.COMFORT_JOURNAL_NODES - nodes - 1)
	filled["unknown"] = filler
	_check(_nodes(filled) == Coordinator.COMFORT_JOURNAL_NODES and Coordinator._journal_bounded(filled),"A comfort journal at exactly its node cap fits")
	filler.append(null)
	_check(not Coordinator._journal_bounded(filled),"The comfort journal remains node bounded")
	# The same for bytes, well under the node cap.
	var heavy := saved.duplicate(true)
	var strings: Array = []
	heavy["unknown"] = strings
	var base := JSON.stringify(heavy).to_utf8_buffer().size()
	var entry := "x".repeat(510)
	for index in range(int((Coordinator.MAX_BYTES - base - 2) / 513)): strings.append(entry)
	strings.append("x".repeat(Coordinator.MAX_BYTES - JSON.stringify(heavy).to_utf8_buffer().size() - 3))
	_check(JSON.stringify(heavy).to_utf8_buffer().size() == Coordinator.MAX_BYTES and _nodes(heavy) < Coordinator.COMFORT_JOURNAL_NODES and Coordinator._journal_bounded(heavy),"A comfort journal of exactly 8 MiB fits")
	strings.append("")
	_check(not Coordinator._journal_bounded(heavy),"The comfort journal remains byte bounded")
	_tide()
	print("COMFORT8 JOURNAL: %d nodes / %d bytes" % [nodes,JSON.stringify(saved).to_utf8_buffer().size()])
	print("AFTER YOU COMFORT JOURNAL: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func _room(branch: int) -> Dictionary:
	var level := Registry.definition(Registry.HIGH_AND_LOW)
	return {"schema_version":2,"api_version":2,"simulation_version":8,"room_id":ROOM,"revision":4+branch*2,"branch":branch,
		"stage_index":1,"level_id":level.id,"level_version":level.version,"definition_hash":Canonical.digest(level),"host_id":HOST,"guest_id":GUEST,
		"checkpoint":proof.checkpoints[1].duplicate(true),"a_turn_id":"t%d-1-a" % branch,"completed_pair_ids":["p0-0"],
		"invite_code":"A1".repeat(10),"invite_expires_at":"2026-10-01T12:00:00Z","created_at":"2026-09-27T12:00:00Z","updated_at":"2026-09-27T12:00:00Z",
		"active_role":"b","first_player_id":GUEST,"active_player_id":HOST,"player_slot":"p0","stage_id":level.stages[1].id,
		"recording_a":proof.pairs[1].a.duplicate(true),"validation":"structural_client_replay_required"}

func _ok(value: Dictionary) -> Dictionary: return {"ok":true,"status":200,"data":value}

## The widest Turn of the Tide journal: a receiver's draft at stage 2, four held
## drafts and an unresolved B submission, every record at the turn's whole cap
## with one action entry a tick in its widest form.
func _tide() -> void:
	var a1 := _widest(_fixture("set-the-tide-a"), TIDE_A_TICKS)
	var b1 := _widest(_fixture("set-the-tide-b"), TIDE_B_TICKS)
	var a2 := _widest(_fixture("slack-water-a"), TIDE_A_TICKS)
	var b2 := _widest(_fixture("slack-water-b"), TIDE_B_TICKS)
	var middle := _fixture("set-the-tide-checkpoint")
	middle.proof = {"checkpoint": _fixture("turn-of-the-tide-initial-checkpoint"), "a": a1, "b": b1}
	var final := _fixture("slack-water-checkpoint")
	final.proof = {"checkpoint": middle, "a": a2, "b": b2}
	var level := Registry.descriptor(Registry.TURN_OF_THE_TIDE)
	var origin := {"schema_version":2,"api_version":2,"room_id":ROOM,"revision":999,"branch":31,"stage_index":1,
		"level_id":level.level_id,"level_version":level.level_version,"definition_hash":level.definition_hash,"host_id":HOST,"guest_id":GUEST,
		"checkpoint":middle,"a_turn_id":"t31-1-a","completed_pair_ids":["p31-0"],"invite_expires_at":"2026-10-01T12:00:00Z","created_at":"2026-09-27T12:00:00Z","updated_at":"2026-09-27T12:00:00Z",
		"active_role":"b","first_player_id":GUEST,"active_player_id":HOST,"player_slot":"p0","stage_id":a2.stage_id,"recording_a":a2,"validation":"structural_client_replay_required"}
	var draft := {"origin":origin,"recording":b2}
	var hash := "f".repeat(64)
	var journal := {"schema_version":1,"api_version":2,"owner_player_id":HOST,"room_id":ROOM,"snapshot":origin,"draft":draft,"held_drafts":[draft,draft,draft,draft],
		"pending":{"operation":"turns","body":{"base_revision":999,"idempotency_key":"k".repeat(80),"branch":31,"recording":b2,"checkpoint":final},"request_hash":hash,"origin":origin,"held":false,"error_code":""},
		"last_receipt":{"schema_version":2,"room_id":ROOM,"idempotency_key":"k".repeat(80),"request_hash":hash,"operation":"turns","accepted_revision":999,"branch":31,"stage_index":1,
			"stage_id":a2.stage_id,"turn_id":"t31-1-a","recording_hash":hash,"pair_id":null,"checkpoint_hash":hash},"auth_required":false}
	var nodes := _nodes(journal)
	var size := JSON.stringify(journal).to_utf8_buffer().size()
	print("TIDE JOURNAL: %d nodes / %d bytes" % [nodes, size])
	_check(Coordinator._journal_bounded(journal) and not Coordinator._bounded_nodes(journal, Coordinator.MAX_BYTES, 140000),"The widest Turn of the Tide journal fits, on the comfort allowance")
	_check(nodes * 3 <= Coordinator.COMFORT_JOURNAL_NODES * 2 and size * 3 <= Coordinator.MAX_BYTES * 2,"...with at least 1.5x to spare: %d of %d values, %d of %d bytes" % [nodes, Coordinator.COMFORT_JOURNAL_NODES, size, Coordinator.MAX_BYTES])
	_check(not Coordinator._bounded_nodes(journal, 3145728, 180000),"It would not have fit the former 3 MiB / 180k journal")
	# The store keeps it: the room value limit is the journal's, and the file has room for the envelope.
	var directory := "user://comfort-journal-" + Crypto.new().generate_random_bytes(8).hex_encode()
	DirAccess.make_dir_recursive_absolute(directory)
	var scope := "relay-room-v2:"+HOST+":"+ROOM
	var store := Store.new(directory)
	_check(Store._value_limit(scope) == Coordinator.MAX_BYTES and Store._file_limit(scope) >= Store.VALUE_BYTES + 1048576,"The store's room value limit is the journal's, with 1 MiB more for the file")
	_check(store.save_scope(scope, journal).ok,"The store saves the widest tide journal")
	var path := directory.path_join(scope.sha256_text() + ".json")
	var loaded := Store.new(directory).load_scope(scope)
	_check(loaded.get("ok", false) and Canonical.same(loaded.get("value"), journal) and FileAccess.get_file_as_bytes(path).size() <= Store.MAX_BYTES,"...and reads it back from a cold start")
	_check(not store.save_scope(scope, {"padding":"x".repeat(Store.VALUE_BYTES)}).ok,"A value over the room limit is refused")
	for suffix: String in ["", ".tmp", ".backup"]:
		if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(path + suffix)
	DirAccess.remove_absolute(directory)

func _fixture(name: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/journey/%s.json" % name))

func _widest(record: Dictionary, ticks: int) -> Dictionary:
	var actions: Array = []
	for index in range(ticks): actions.append({"action":false,"ticks":1,"x":-100,"z":-99 if index % 2 else -100})
	var count := ticks / 30 + 1
	var replay_checks: Array = []
	for index in range(count): replay_checks.append({"tick":ticks - count + 1 + index,"state_hash":record.final_state_hash})
	record.actions = actions
	record.replay_checks = replay_checks
	record.duration_ticks = ticks
	record.catch_assistance = false
	return record

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
