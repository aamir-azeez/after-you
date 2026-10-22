extends "res://tests/test_relay_room_coordinator.gd"
## A room whose friend asked for a redo again and again, each time while this
## phone held a turn in progress, keeps taking the room's new state and lets a
## refused turn be kept. The phone keeps its four newest old turns.

func _run() -> void:
	for name: String in ["relay-a", "relay-b", "garden-a", "garden-b", "initial-checkpoint", "relay-checkpoint", "final-checkpoint"]:
		fixtures[name] = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/v2/" + name + ".json"))
	await _many_new_branches()
	await _refused_turn_with_four_kept()
	print("Room held drafts: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _many_new_branches() -> void:
	var boundary := Boundary.new()
	var coordinator = await _open(boundary)
	for branch in range(1, 7):
		_check(coordinator.save_draft(fixtures["relay-a"]), "A turn in progress is saved on branch %d" % (branch - 1))
		boundary.responses.append(_ok(_snapshot(HOST, 0, false, branch + 1, branch)))
		_check(await coordinator.refresh(), "The room's new branch %d is taken (%s)" % [branch, coordinator.last_code])
		_check(int(coordinator.snapshot().get("branch", -1)) == branch, "The phone shows branch %d" % branch)
		_check(coordinator.held_drafts().size() == mini(branch, Coordinator.MAX_HELD), "At most %d old turns are kept (%d)" % [Coordinator.MAX_HELD, coordinator.held_drafts().size()])
	var newest: Array = coordinator.held_drafts().map(func(held: Dictionary) -> int: return int(held.origin.branch))
	_check(newest == [2, 3, 4, 5], "The newest old turns are the ones kept (%s)" % [newest])
	var restarted = _coordinator(boundary)
	_check(restarted.bind_room(ROOM) and not restarted.read_only and restarted.held_drafts().size() == Coordinator.MAX_HELD, "A cold start reads the room with its kept turns")

func _refused_turn_with_four_kept() -> void:
	var boundary := Boundary.new()
	var coordinator = await _open(boundary)
	for branch in range(1, 5):
		_check(coordinator.save_draft(fixtures["relay-a"]), "A turn in progress is saved")
		boundary.responses.append(_ok(_snapshot(HOST, 0, false, branch + 1, branch)))
		_check(await coordinator.refresh(), "The room's new branch is taken")
	_check(coordinator.held_drafts().size() == Coordinator.MAX_HELD, "Four old turns are kept")
	boundary.responses.append(_error(409, "stale_revision"))
	_check(not await coordinator.commit(fixtures["relay-a"]) and coordinator.pending().held, "A turn the room refused is held")
	_check(coordinator.archive_held_submission(), "Keep rehearsal still works with four old turns kept (%s)" % coordinator.last_code)
	var kept: Array = coordinator.held_drafts().map(func(held: Dictionary) -> int: return int(held.origin.branch))
	_check(coordinator.pending().is_empty() and kept == [1, 2, 3, 4], "The refused turn is kept in place of the oldest (%s)" % [kept])
