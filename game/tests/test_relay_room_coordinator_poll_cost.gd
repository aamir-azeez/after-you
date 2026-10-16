extends SceneTree
## A waiting phone polls its room every few seconds. An identical snapshot must
## not pay for another full checkpoint and recording re-simulation.

const Coordinator = preload("res://services/relay_room_coordinator.gd")
const Catalog = preload("res://core/v2/stage_catalog.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const Schedule = preload("res://services/refresh_schedule.gd")
const RelayPreview = preload("res://relay_preview.gd")
const IDLE_WAIT_MS := 600000
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
	await _unchanged_replies(checkpoint, recording)
	var before := await _idle_wait(checkpoint, recording, false)
	var after := await _idle_wait(checkpoint, recording, true)
	print("Relay room poll cost: a %d-minute idle wait sends %d room reads without the idle backoff, %d with it" % [IDLE_WAIT_MS / 60000, before, after])
	_check(before >= 195 and after <= 60, "A 10-minute idle wait sends far fewer room reads (%d before, %d after)" % [before, after])
	await _change_during_idle_wait(checkpoint, recording)
	print("Relay room poll cost: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

## The conditional poll: the room GET names the held revision and branch, and
## an exact small reply changes nothing on this phone.
func _unchanged_replies(checkpoint: Dictionary, recording: Dictionary) -> void:
	var room := _snapshot(checkpoint, recording, 3)
	var boundary := Boundary.new()
	var sent: Array = []
	var coordinator := Counting.new(func(request: Dictionary) -> Dictionary:
		sent.append(request.duplicate(true))
		return await boundary.transport(request), boundary.load_store, boundary.save_store, boundary.owner, boundary.key)
	_check(coordinator.bind_room(ROOM), "Bind a room for the small poll reply")
	boundary.responses.append({"ok": true, "status": 200, "data": room})
	_check(await coordinator.refresh(), "The first read takes the full room")
	_check(not sent[0].has("headers"), "A phone with no stored room asks for the full room")
	var verified := coordinator.verifications
	var writes := boundary.writes
	var small := {"schema_version": 1, "unchanged": true, "revision": 3, "branch": 0, "updated_at": room.updated_at}
	boundary.responses.append({"ok": true, "status": 200, "data": small})
	sent.clear()
	_check(await coordinator.refresh(), "An exact unchanged reply is accepted")
	_check(sent.size() == 1 and Array(sent[0].get("headers", PackedStringArray())) == ["X-AfterYou-Known-Room: 3.0"], "The poll names the held revision and branch")
	_check(coordinator.verifications == verified and boundary.writes == writes and Canonical.same(coordinator.snapshot(), room), "An unchanged reply runs no verification, writes nothing and keeps the same room")
	_check(coordinator.last_error.is_empty() and coordinator.last_refresh_result().get("status") == 200 and not coordinator.last_refresh_result().get("terminal"), "An unchanged reply counts as a good read")
	for change: String in ["revision", "branch", "updated_at", "extra", "schema"]:
		var wrong := small.duplicate(true)
		if change == "revision": wrong.revision = 2
		elif change == "branch": wrong.branch = 1
		elif change == "updated_at": wrong.updated_at = "2026-09-14T12:00:01Z"
		elif change == "extra": wrong["room_id"] = ROOM
		else: wrong.schema_version = 2
		boundary.responses.append({"ok": true, "status": 200, "data": wrong})
		boundary.responses.append({"ok": true, "status": 200, "data": room})
		sent.clear()
		_check(await coordinator.refresh(), "A mismatched small reply (%s) falls back to the full room" % change)
		_check(sent.size() == 2 and not sent[1].has("headers") and coordinator.verifications == verified, "The fallback read once without the header and found the same verified room (%s)" % change)
	# A Worker from before the small reply ignores the header and sends the full room.
	boundary.responses.append({"ok": true, "status": 200, "data": room})
	_check(await coordinator.refresh() and coordinator.verifications == verified, "An older Worker's identical full room runs no verification")

## A waiting phone's room reads over a simulated idle wait: the real
## coordinator and refresh schedule, a 100 ms clock and instant replies, with
## the room screen's own change test (RelayPreview.poll_changed).
## `backoff` false passes every read as changed, the cadence before the backoff.
func _idle_wait(checkpoint: Dictionary, recording: Dictionary, backoff: bool, change_at_ms: int = -1, gaps: Array = []) -> int:
	var room := _snapshot(checkpoint, recording, 3)
	var newer := _snapshot(checkpoint, recording, 4)
	newer.updated_at = "2026-09-14T12:00:09Z"
	var boundary := Boundary.new()
	var coordinator := Counting.new(boundary.transport, boundary.load_store, boundary.save_store, boundary.owner, boundary.key)
	_check(coordinator.bind_room(ROOM), "Bind the room for the idle wait")
	boundary.responses.append({"ok": true, "status": 200, "data": room})
	_check(await coordinator.refresh(), "The idle wait starts from the full room")
	var schedule := Schedule.new()
	schedule.bind("guest:" + ROOM, 0)
	var reads := 0
	var last := 0
	for now in range(0, IDLE_WAIT_MS, 100):
		var token: Dictionary = schedule.begin_if_due(now, true, false)
		if token.is_empty(): continue
		reads += 1
		gaps.append(now - last)
		last = now
		var held: Dictionary = coordinator.snapshot()
		var held_turn: bool = coordinator.my_turn()
		var held_pending: Dictionary = coordinator.pending()
		if change_at_ms >= 0 and now >= change_at_ms and int(held.revision) == 3:
			boundary.responses.append({"ok": true, "status": 200, "data": newer})
		else:
			boundary.responses.append({"ok": true, "status": 200, "data": {"schema_version": 1, "unchanged": true, "revision": held.revision, "branch": 0, "updated_at": held.updated_at}})
		var succeeded := await coordinator.refresh()
		var changed := not backoff or RelayPreview.poll_changed(coordinator, held, held_turn, held_pending, succeeded, false)
		schedule.complete(token, now, succeeded, 0, false, changed)
	_check(boundary.responses.is_empty() and coordinator.last_error.is_empty(), "Every idle read was answered and accepted")
	return reads

## A partner's turn that lands while the backoff is long is seen at the next
## read, and the reads after it keep the 3 s cadence for a minute.
func _change_during_idle_wait(checkpoint: Dictionary, recording: Dictionary) -> void:
	var gaps: Array = []
	await _idle_wait(checkpoint, recording, true, 300000, gaps)
	var at := 0
	var seen := -1
	for index in gaps.size():
		at += int(gaps[index])
		if at >= 300000:
			seen = index
			break
	_check(seen > 0 and at - 300000 < 15000, "The turn is read within one 15 s idle wait (%d ms after it landed)" % [at - 300000])
	_check(seen + 21 < gaps.size() and gaps.slice(seen + 1, seen + 21).all(func(gap: int) -> bool: return gap == 3000) and int(gaps[seen + 21]) == 4500, "After the change reads come every 3 s for a minute, then the room backs off again: %s" % [gaps.slice(seen, seen + 23)])

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
