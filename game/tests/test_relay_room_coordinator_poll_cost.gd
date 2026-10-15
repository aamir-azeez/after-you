extends SceneTree
## A waiting phone polls its room every few seconds. An identical snapshot must
## not pay for another full checkpoint and recording re-simulation.

const Coordinator = preload("res://services/relay_room_coordinator.gd")
const Catalog = preload("res://core/v2/stage_catalog.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const HOST := "HHHHHHHHHHHHHHHHHHHHHH"
const GUEST := "GGGGGGGGGGGGGGGGGGGGGG"
const ROOM := "RRRRRRRRRRRRRRRRRRRRRR"

## Counts every full snapshot verification, the step that re-simulates the
## checkpoint and the partner's recording.
class Counting:
	extends "res://services/relay_room_coordinator.gd"
	var verifications := 0
	func _valid_snapshot(value: Variant) -> bool:
		verifications += 1
		return super(value)

class Boundary:
	extends RefCounted
	var identity := {"ready": true, "player_id": GUEST, "epoch": 1}
	var disk: Dictionary = {}
	var writes := 0
	var responses: Array = []
	func owner() -> Dictionary: return identity.duplicate(true)
	func load_store(scope: String) -> Dictionary:
		return {"ok": true, "found": disk.has(scope), "value": disk.get(scope, {}).duplicate(true)}
	func save_store(scope: String, value: Dictionary) -> Dictionary:
		writes += 1
		disk[scope] = JSON.parse_string(JSON.stringify(value))
		return {"ok": true}
	func key() -> String: return "synthetic-operation-0001"
	func transport(_request: Dictionary) -> Dictionary:
		if responses.is_empty(): return {"ok": false, "status": 0, "code": "connection_interrupted"}
		return JSON.parse_string(JSON.stringify(responses.pop_front()))

var checks := 0
var failures := 0
var level := Catalog.relay_isles()

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var checkpoint: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/v2/initial-checkpoint.json"))
	var recording: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/v2/relay-a.json"))
	var room := _snapshot(checkpoint, recording, 3)
	var boundary := Boundary.new()
	var coordinator := Counting.new(boundary.transport, boundary.load_store, boundary.save_store, boundary.owner, boundary.key)
	_check(coordinator.bind_room(ROOM), "Bind the waiting guest's room")
	boundary.responses.append({"ok": true, "status": 200, "data": room})
	_check(await coordinator.refresh(), "The first snapshot with the host's turn is accepted")
	_check(coordinator.verifications == 1, "The first snapshot runs one full verification")
	var writes := boundary.writes
	for poll in range(3):
		boundary.responses.append({"ok": true, "status": 200, "data": room})
		_check(await coordinator.refresh(), "Identical poll %d is accepted" % poll)
	_check(coordinator.verifications == 1, "Identical polls run no further verification")
	_check(boundary.writes == writes, "Identical polls write no new save generation")
	_check(coordinator.last_error.is_empty(), "Identical polls leave no error")
	var tampered := room.duplicate(true)
	tampered.recording_a.erase("role")
	boundary.responses.append({"ok": true, "status": 200, "data": tampered})
	_check(not await coordinator.refresh() and coordinator.last_code == "invalid_snapshot", "A changed snapshot at the same revision is still verified and refused")
	_check(coordinator.verifications == 2, "Only the changed snapshot paid for verification")
	var newer := _snapshot(checkpoint, recording, 4)
	newer.updated_at = "2026-09-14T12:00:09Z"
	boundary.responses.append({"ok": true, "status": 200, "data": newer})
	_check(await coordinator.refresh() and int(coordinator.snapshot().revision) == 4, "A newer snapshot is verified and accepted")
	_check(coordinator.verifications == 3, "A newer snapshot runs one full verification")
	var reopened := Counting.new(boundary.transport, boundary.load_store, boundary.save_store, boundary.owner, boundary.key)
	_check(reopened.bind_room(ROOM), "A reopened room verifies its stored snapshot on load")
	var on_load := reopened.verifications
	boundary.responses.append({"ok": true, "status": 200, "data": newer})
	_check(await reopened.refresh() and reopened.verifications == on_load, "After a reopen, an identical poll reuses the snapshot verified on load")
	print("Relay room poll cost: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _snapshot(checkpoint: Dictionary, recording: Dictionary, revision: int) -> Dictionary:
	return {
		"schema_version": 2, "api_version": 2, "room_id": ROOM, "revision": revision,
		"branch": 0, "stage_index": 0, "level_id": "relay-isles", "level_version": 2,
		"definition_hash": Canonical.digest(level), "host_id": HOST, "guest_id": GUEST,
		"checkpoint": checkpoint.duplicate(true), "a_turn_id": "t0-0-a", "completed_pair_ids": [],
		"invite_expires_at": "2026-09-21T12:00:00Z", "created_at": "2026-09-14T12:00:00Z", "updated_at": "2026-09-14T12:00:00Z",
		"active_role": "b", "first_player_id": HOST, "active_player_id": GUEST, "player_slot": "p1",
		"stage_id": level.stages[0].id, "recording_a": recording.duplicate(true), "validation": "structural_client_replay_required"
	}

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
