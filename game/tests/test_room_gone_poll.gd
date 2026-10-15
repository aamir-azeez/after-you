extends "res://tests/test_relay_room_coordinator.gd"
## A phone waiting in a room learns from its next poll that the other member
## closed the room or erased their account, so the room screen can say so. A
## phone holding its own rehearsal keeps the recoverable hold instead, and a
## finished room stays finished.

func _run() -> void:
	for name: String in ["relay-a", "relay-b", "garden-a", "garden-b", "initial-checkpoint", "relay-checkpoint", "final-checkpoint"]:
		fixtures[name] = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/v2/" + name + ".json"))
	await _gone_while_waiting()
	await _not_gone()
	await _rehearsal_keeps_hold()
	await _finished_room_stays_finished()
	print("Room gone poll: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _gone_while_waiting() -> void:
	for reply: Array in [[404, "room_not_found"], [410, "room_closed"], [410, "room_deleted"]]:
		var boundary := Boundary.new()
		var coordinator = await _open(boundary)
		var room: Dictionary = coordinator.snapshot()
		boundary.responses.append(_error(reply[0], reply[1]))
		_check(not await coordinator.refresh() and coordinator.room_gone(), "A poll answered %d %s marks the room gone" % reply)
		_check(coordinator.pending().is_empty() and coordinator.last_refresh_result().get("terminal", false), "Nothing was pending and polling stops: %s" % reply[1])
		boundary.responses.append(_ok(room))
		_check(await coordinator.refresh() and not coordinator.room_gone(), "The same room readable again is no longer gone: %s" % reply[1])

func _not_gone() -> void:
	for reply: Array in [[403, "player_blocked"], [404, "room_unavailable"], [410, "replay_transferred"], [503, "service_unavailable"], [0, "connection_interrupted"]]:
		var boundary := Boundary.new()
		var coordinator = await _open(boundary)
		boundary.responses.append(_error(reply[0], reply[1]))
		_check(not await coordinator.refresh() and not coordinator.room_gone(), "A poll answered %d %s does not call the room closed" % reply)

func _rehearsal_keeps_hold() -> void:
	var boundary := Boundary.new()
	var coordinator = await _open(boundary)
	var room: Dictionary = coordinator.snapshot()
	_check(coordinator.save_draft(fixtures["relay-a"]), "A rehearsal is saved in the room")
	boundary.responses.append(_error(404, "room_not_found"))
	_check(not await coordinator.refresh() and not coordinator.room_gone() and not coordinator.my_turn(), "A room holding a rehearsal stays on the recoverable hold")
	boundary.responses.append(_ok(room))
	_check(await coordinator.refresh() and coordinator.my_turn() and Canonical.same(coordinator.draft(), fixtures["relay-a"]), "The rehearsal is still there when the room reads again")

func _finished_room_stays_finished() -> void:
	var boundary := Boundary.new()
	var coordinator = await _open(boundary, _snapshot(HOST, 2, false, 5))
	_check(coordinator.chapter_complete(), "The room is finished")
	boundary.responses.append(_error(404, "room_not_found"))
	_check(not await coordinator.refresh() and not coordinator.room_gone() and coordinator.chapter_complete(), "A finished room whose partner left stays finished, not closed")
