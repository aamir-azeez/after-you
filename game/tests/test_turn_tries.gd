extends "res://tests/test_relay_room_coordinator.gd"
## Turn try counts: the counting service, the solo turn seams and the Try pill,
## the count sent with a room turn, and the pills on Replays rows.

const TurnTries = preload("res://services/turn_tries.gd")
const Preview = preload("res://relay_preview.gd")
const Journey = preload("res://services/relay_journey.gd")
const Replays = preload("res://presentation/replays_flow.gd")
const TryPill = preload("res://presentation/try_pill.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const HASH_A := "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
const HASH_B := "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

var _paths: Array[String] = []

func _run() -> void:
	for name: String in ["relay-a", "relay-b", "garden-a", "garden-b", "initial-checkpoint", "relay-checkpoint", "final-checkpoint"]:
		fixtures[name] = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/v2/" + name + ".json"))
	await _service()
	await _solo_seams()
	await _room_send()
	_replays_pills()
	for frame in range(300):
		if not _paths.any(func(file: String) -> bool: return TurnTries.writing(file)): break
		await process_frame
	for path: String in _paths:
		for suffix: String in ["", ".tmp", ".backup"]: DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
	print("Turn tries: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _path(label: String) -> String:
	var path := "user://turn-tries-test-%s-%s.json" % [label, Crypto.new().generate_random_bytes(6).hex_encode()]
	_paths.append(path)
	_paths.append(path.get_basename() + "-open.json")
	return path

class SlotJourney extends RefCounted:
	var room := {}
	var stage := "relay"
	var turn_role := "a"
	var start_hash := HASH_A
	var prior := {}
	func snapshot() -> Dictionary: return room
	func stage_id() -> String: return stage
	func role() -> String: return turn_role
	func checkpoint() -> Dictionary: return {"checkpoint_hash": start_hash}
	func prior_recording() -> Dictionary: return prior

func _service() -> void:
	var path := _path("service")
	var tries := TurnTries.new(path)
	var journey := SlotJourney.new()
	var solo := TurnTries.slot_for(journey, "relay-isles@2", false)
	journey.room = JSON.parse_string(JSON.stringify({"room_id": ROOM, "branch": 0}))
	var room := TurnTries.slot_for(journey, "relay-isles@2", true)
	journey.room = {"room_id": ROOM, "branch": 0}
	_check(room == TurnTries.slot_for(journey, "relay-isles@2", true), "A room's slot is the same whether its branch came from JSON or not")
	_check(tries.count(solo) == 0 and tries.start(solo) == 1 and tries.start(solo) == 2, "Each start of a turn counts one try, the first is try 1")
	_check(tries.start(room) == 1 and tries.count(solo) == 2, "A room's turn and a solo turn with the same start count apart")
	journey.room = {"room_id": ROOM, "branch": 1}
	_check(TurnTries.slot_for(journey, "relay-isles@2", true) != room, "A redo's new branch is a new slot")
	var other := TurnTries.new(path)
	_check(other.count(solo) == 2, "Open counts survive the app closing")
	other.start(room)
	_check(tries.start(solo) == 3 and TurnTries.new(path).count(room) == 2, "Two holders of the files never undo each other's counts")
	_check(TurnTries.new(path).count(solo) == 3, "Every holder reads a start's counts while its worker writes them")
	var frames := 0
	while TurnTries.writing(tries.open_path) and frames < 300:
		await process_frame
		frames += 1
	_check(not TurnTries.writing(tries.open_path) and not FileAccess.file_exists(path) and FileAccess.file_exists(tries.open_path), "Starting a turn writes only the small file of open counts, off the tap's thread")
	_check(TurnTries.new(path).count(solo) == 3 and TurnTries.new(path).count(room) == 2, "The written file holds the newest counts")
	_check(tries.freeze(solo, HASH_B) == 3 and tries.tries(HASH_B) == 3 and tries.count(solo) == 3, "Saving keeps the count under the recording and goes on counting until accepted")
	tries.close(solo)
	_check(tries.count(solo) == 0 and tries.start(solo) == 1, "After the turn is saved, the same start begins a new count")
	_check(tries.freeze(room, HASH_A) == 2 and tries.tries(HASH_A) == 2, "A sent room turn keeps its count too")
	journey.stage = "garden"; journey.turn_role = "b"; journey.start_hash = HASH_B; journey.prior = {"recording_hash": HASH_A}
	var second := TurnTries.slot_for(journey, "relay-isles@2", false)
	_check(tries.resume(second) == 1 and tries.resume(second) == 1, "A draft resumed without a count is the first try, once")
	_check(tries.freeze(second, "c".repeat(64)) == 1 and tries.tries("c".repeat(64)) == 0, "A first try keeps no count: it shows nothing")
	tries.restart_solo("relay-isles@2")
	_check(tries.count(solo) == 0 and tries.count(second) == 0 and tries.count(room) == 2, "A solo redo or restart starts only that chapter's counts again")
	_check(tries.read_wanted(ROOM, "x"), "A room never read is read")
	tries.remember({HASH_A: 5.0, "d".repeat(64): 1.0, "e".repeat(64): 1000.0, "not-a-hash": 4.0, "f".repeat(64): "3"}, ROOM, "x")
	_check(tries.tries(HASH_A) == 5 and tries.tries("d".repeat(64)) == 0 and tries.tries("e".repeat(64)) == 0 and tries.tries("f".repeat(64)) == 0, "Server counts are kept only when they are whole numbers from 2 to 999")
	_check(not TurnTries.new(path).read_wanted(ROOM, "x") and TurnTries.new(path).read_wanted(ROOM, "y"), "A room is read again only when its parts changed, across a reload")
	for index in range(TurnTries.MAX_OPEN + 3): tries.start("solo|bounded|%d" % index)
	_check(tries.count("solo|bounded|0") == 0 and tries.count("solo|bounded|%d" % (TurnTries.MAX_OPEN + 2)) == 1 and TurnTries.new(path)._open.size() == TurnTries.MAX_OPEN, "Open counts are bounded, oldest out first, across a reload")
	var damaged := _path("damaged")
	var file := FileAccess.open(damaged.get_basename() + "-open.json", FileAccess.WRITE)
	file.store_string("{\"schema_version\":1,\"open\":[]}")
	file.close()
	_paths.append(damaged.get_basename() + "-open.json")
	_check(TurnTries.new(damaged).start("x") == 1, "A damaged file reads as no counts")

func _solo_preview(journal: String, counts: String) -> Node3D:
	var app := Preview.new()
	app.journey = Journey.new(journal)
	app.turn_tries = TurnTries.new(counts)
	app.settings = {"sound": false, "haptics": false, "reduced_motion": true, "assistance": true, "left_handed": false}
	root.add_child(app)
	app.set_physics_process(false)
	app.set_process(false)
	return app

func _pill(app: Node3D) -> Control:
	return app.controls.try_pill

func _solo_seams() -> void:
	root.size = Vector2i(1280, 720)
	var journal := _path("journal")
	var counts := _path("solo-counts")
	var app := _solo_preview(journal, counts)
	await process_frame
	app._begin()
	await process_frame
	_check(app._live_tries == 1 and not _pill(app).visible, "The first try of a turn shows no pill")
	var record: Dictionary = fixtures["relay-a"]
	var inputs: Array = Simulation.expand_recording_inputs(record)
	for input: Dictionary in inputs: app.advance_input(input)
	app._finish()
	_check(app.mode == "review", "The finished turn opens review")
	_press(app, "Retry")
	await process_frame
	_check(app.mode == "play" and app._live_tries == 2 and _pill(app).visible and _pill(app).label.text == PlayerCopy.TRY_PILL % 2, "Retry from review starts try 2 and the pill says so")
	app._pause()
	_press(app, "Retry")
	await process_frame
	_check(app._live_tries == 3 and _pill(app).label.text == "Try 3", "Retry from pause starts try 3")
	var pill_rect: Rect2 = _pill(app).get_global_rect()
	var title_rect: Rect2 = app.controls.chapter_label.get_global_rect()
	_check(pill_rect.position.y >= title_rect.end.y and pill_rect.position.x == title_rect.position.x, "The pill sits under the stage line, flush with it")
	for control: Control in [app.controls.stick, app.controls.objective_panel, app.controls.pause_button, app.controls.turn_progress]:
		_check(not pill_rect.intersects(control.get_global_rect()), "The pill keeps clear of " + control.name)
	for index in range(40): app.advance_input(inputs[index])
	_check(app._persist_draft(), "A draft of try 3 is saved")
	app.queue_free()
	await process_frame
	app = _solo_preview(journal, counts)
	await process_frame
	app._resume_draft()
	await process_frame
	_check(app.mode == "play" and app._live_tries == 3 and _pill(app).label.text == "Try 3", "A draft resumed after the app closed keeps its count")
	app._pause()
	_press(app, "Retry")
	await process_frame
	for input: Dictionary in inputs: app.advance_input(input)
	app._finish()
	var saved_hash := str(app.review.get("recording_hash", ""))
	app._accept()
	_check(app.mode != "error" and app.journey.role() == "b", "Save turn accepts try 4")
	_check(app.turn_tries.tries(saved_hash) == 4, "The saved turn keeps its count of 4 under its recording")
	app._show_ready()
	app._begin()
	await process_frame
	_check(app._live_tries == 1 and not _pill(app).visible, "The next turn starts again at try 1")
	app._pause()
	_press(app, "Retry")
	await process_frame
	_check(app._live_tries == 2, "The second turn counts its own retries")
	app._pause()
	app._run_solo_redo(app.journey.redo_plan(), "paused")
	await process_frame
	_check(app.journey.role() == "a" and app._live_tries == 2, "Redo takes back the first turn")
	app._begin()
	await process_frame
	_check(app._live_tries == 1 and app.turn_tries.tries(saved_hash) == 4, "The redone turn starts a new count and the old one keeps its own")
	app.queue_free()
	await process_frame

func _room_send() -> void:
	var boundary := Boundary.new()
	var coordinator = await _open(boundary)
	boundary.responses.append(func(request: Dictionary) -> Dictionary: return _ok(_receipt(request, _snapshot(HOST, 0, true, 2))))
	_check(await coordinator.commit(fixtures["relay-a"], 3), "A room turn is sent with its count")
	var sent: Dictionary = boundary.requests.back().body
	_check(sent.get("tries") == 3 and Canonical.same(sent.recording, fixtures["relay-a"]), "The count travels beside the recording, which is unchanged")
	boundary = Boundary.new()
	coordinator = await _open(boundary)
	_check(not await coordinator.commit(fixtures["relay-a"], 2), "A lost answer leaves the counted turn pending")
	var pending: Dictionary = coordinator.pending().duplicate(true)
	coordinator = _coordinator(boundary)
	_check(coordinator.bind_room(ROOM) and Canonical.same(coordinator.pending(), pending) and pending.body.tries == 2, "The pending turn reloads with its count, so a resend is byte for byte")
	boundary = Boundary.new()
	coordinator = await _open(boundary)
	boundary.responses.append(func(request: Dictionary) -> Dictionary: return _ok(_receipt(request, _snapshot(HOST, 0, true, 2))))
	_check(await coordinator.commit(fixtures["relay-a"]) and not boundary.requests.back().body.has("tries"), "A server without counts gets the old body")
	boundary = Boundary.new()
	coordinator = await _open(boundary)
	await coordinator.commit(fixtures["relay-a"], 2)
	var scope := "relay-room-v2:" + HOST + ":" + ROOM
	boundary.disk[scope].pending.body.tries = 1000
	coordinator = _coordinator(boundary)
	_check(not coordinator.bind_room(ROOM) and coordinator.read_only, "A stored count out of range is not trusted")

func _press(app: Node3D, text: String) -> void:
	var button := _find_button(app.overlay, text)
	_check(button != null and not button.disabled, "The visible UI offers an enabled " + text + " control")
	if button != null and not button.disabled: button.pressed.emit()

func _find_button(node: Node, text: String) -> Button:
	if node is Button and node.text == text and node.is_visible_in_tree(): return node
	for child in node.get_children():
		var found := _find_button(child, text)
		if found != null: return found
	return null

func _replays_pills() -> void:
	var counts := _path("replays-counts")
	var tries := TurnTries.new(counts)
	tries.remember({HASH_A: 3, HASH_B: 7})
	var flow := Replays.new()
	flow._turn_tries = TurnTries.new(counts)
	var row := {"pair": {"a": {"recording_hash": HASH_A}, "b": {"recording_hash": "c".repeat(64)}}}
	var pills: Control = flow._tries_row(Replays._solo_turns(row))
	_check(pills != null and pills.get_child_count() == 1 and (pills.get_child(0) as TryPill).label.text == PlayerCopy.TRY_COUNT % [PlayerCopy.TRY_FIRST_TURN, 3], "A solo part shows a pill only for the turn that took more than one try")
	_check(flow._tries_row(Replays._solo_turns({"pair": {"a": {"recording_hash": "c".repeat(64)}, "b": {}}})) == null, "A part whose turns were first tries shows nothing")
	_check(flow._tries_row(Replays._solo_turns({})) == null, "A part still being checked shows nothing")
	var both: Control = flow._tries_row([["You", HASH_A], ["Sam", HASH_B]])
	_check(both.get_child_count() == 2 and (both.get_child(1) as TryPill).label.text == "Sam · 7 tries", "A shared part names each player's count")
	_check(Replays._turn_owners("p0", true, "Sam", HASH_A, HASH_B) == [["You", HASH_A, "peach", true], ["Sam", HASH_B, "mint", false]] and Replays._turn_owners("p0", false, "Sam", HASH_A, HASH_B) == [["Sam", HASH_A, "peach", false], ["You", HASH_B, "mint", true]], "A stage the host starts: the host's first turn, the guest's second, each in its spirit's colour")
	_check(Replays._turn_owners("p1", false, "Sam", HASH_A, HASH_B) == [["You", HASH_A, "mint", true], ["Sam", HASH_B, "peach", false]] and Replays._turn_owners("p1", true, "Sam", HASH_A, HASH_B) == [["Sam", HASH_A, "mint", false], ["You", HASH_B, "peach", true]], "A stage the guest starts: the guest's first turn, the host's second, each in its spirit's colour")
	_check(Replays._turn_owners("", true, "Sam", HASH_A, HASH_B).is_empty(), "A stage without a first slot names nobody")
	for pill: Node in [pills, both]: pill.free()
	flow.free()
