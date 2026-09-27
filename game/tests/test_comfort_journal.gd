extends SceneTree
## Actual native dense proof through Coordinator; transport is a synthetic server.
const Existing = preload("res://tests/test_relay_room_coordinator.gd")
const Coordinator = preload("res://services/relay_room_coordinator.gd")
const Registry = preload("res://services/chapter_registry.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const HOST := "HHHHHHHHHHHHHHHHHHHHHH"
const GUEST := "GGGGGGGGGGGGGGGGGGGGGG"
const ROOM := "RRRRRRRRRRRRRRRRRRRRRR"
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
	_check(JSON.stringify(saved).to_utf8_buffer().size() < Coordinator.MAX_BYTES,"Original3MiB byte bound remains sufficient")
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
	old.snapshot.simulation_version = 9
	_check(not Coordinator._journal_bounded(old),"Unknown future versions receive no journal allowance")
	var too_big := saved.duplicate(true)
	too_big["unknown"] = Array(range(180001))
	_check(not Coordinator._journal_bounded(too_big),"The comfort journal remains node bounded")
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
