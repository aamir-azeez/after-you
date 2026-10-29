extends SceneTree
## What a player hears about a together run's leaderboard time:
## services/board_status.gd (one state for a run), presentation/board_status_line.gd
## (the end-of-run line and its Turn off Forgiving catches button),
## presentation/board_feedback_flow.gd (the line's one board read and Home's
## throttled watch), the board screen's reason under Your best, LocalSave's
## one-time Forgiving catches switch off, and the cloud never turning it back on.
## Every request goes to a fake transport; saves use their own files.
const BoardStatus = preload("res://services/board_status.gd")
const Line = preload("res://presentation/board_status_line.gd")
const Flow = preload("res://presentation/board_feedback_flow.gd")
const Runs = preload("res://services/leaderboard_runs.gd")
const Client = preload("res://services/leaderboard_client.gd")
const Placings = preload("res://services/leaderboard_placings.gd")
const Screen = preload("res://presentation/leaderboard_screen.gd")
const Registry = preload("res://services/chapter_registry.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const Storage = preload("res://services/local_save.gd")
const Sources = preload("res://services/platform_games/cloud_save_sources.gd")
const Bundle = preload("res://services/platform_games/cloud_save_bundle.gd")
const OWNER := "OOOOOOOOOOOOOOOOOOOOOO"
const PARTNER := "GGGGGGGGGGGGGGGGGGGGGG"
const RUNS_PATH := "user://board-feedback-runs-test.json"
const PLACINGS_PATH := "user://board-feedback-placings-test.json"
const CHOICE_PATH := "user://board-feedback-name-test.json"
const LIGHTHOUSE_BOARD := "sleeping-lighthouse@2"
const RELAY_BOARD := "relay-isles@2"

var checks := 0
var failures := 0
func _initialize() -> void: _run.call_deferred()
func _check(okay: bool, message: String) -> void:
	checks += 1
	if not okay: failures += 1; push_error(message)

## A stand-in for services/rooms_api.gd: answers from `replies` by "METHOD path" and records each request.
class FakeApi extends Node:
	var player_id := ""
	var replies: Dictionary = {}
	var requests: Array = []
	func request_json(method: int, path: String, body: Dictionary = {}, _still: Callable = Callable()) -> Dictionary:
		var name: String = {HTTPClient.METHOD_GET: "GET", HTTPClient.METHOD_PUT: "PUT", HTTPClient.METHOD_POST: "POST"}.get(method, "?")
		requests.append([name, path, body])
		await Engine.get_main_loop().process_frame
		return replies.get(name + " " + path, {"ok": false, "code": "not_found"}).duplicate(true)

class FakeSession extends RefCounted:
	var on := true
	func leaderboards_supported() -> bool: return on

class FakeSettingsFlow extends RefCounted:
	var saves: RefCounted
	var kept := true
	func save_setting(key: String, value: Variant) -> bool:
		if not kept: return false
		saves.data.settings[key] = value
		return true

class FakeSaves extends RefCounted:
	var data := {"settings": {"assistance": true}}

## The parts of Main presentation/board_feedback_flow.gd reads.
class FakeHost extends Node:
	var api: Node
	var saves := FakeSaves.new()
	var relay_session: RefCounted = FakeSession.new()
	var settings_flow := FakeSettingsFlow.new()
	var relay_child: Node
	var free_for_card := true
	var toasts: Array = []
	func _home_free_for_card() -> bool: return free_for_card
	func _home_settling() -> bool: return false
	func _toast(text: String) -> void: toasts.append(text)

func _run() -> void:
	for path: String in [RUNS_PATH, PLACINGS_PATH, CHOICE_PATH]: _clear(path)
	Runs.use_path(RUNS_PATH)
	Placings.use_shared(Placings.new(PLACINGS_PATH))
	_states()
	_line_words()
	await _end_of_run_line()
	await _home_watch()
	await _board_reasons()
	_settings_migration()
	_cloud_never_turns_it_on()
	Placings.use_shared(null)
	for path: String in [RUNS_PATH, PLACINGS_PATH, CHOICE_PATH]: _clear(path)
	print("Board feedback: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _clear(path: String) -> void:
	for suffix: String in ["", ".tmp", ".backup"]:
		if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))

func _now_iso(offset_seconds: int = 0) -> String:
	return Time.get_datetime_string_from_unix_time(int(Time.get_unix_time_from_system()) + offset_seconds) + ".000Z"

func _lighthouse_final() -> Dictionary:
	var chain: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/lighthouse/v2-chain.json"))
	return chain.checkpoints[-1]

func _relay_final() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/v2/final-checkpoint.json"))

func _snapshot(room: String, checkpoint: Dictionary, updated_at: String) -> Dictionary:
	return {"room_id": room, "branch": 1, "active_role": "complete", "host_id": OWNER, "guest_id": PARTNER, "checkpoint": checkpoint, "updated_at": updated_at}

func _view(board: String, top: Array, checking: Array) -> Dictionary:
	return {"schema_version": 1, "board": board, "top": top, "checking": checking}

func _row(rank: int, entry: String, ticks: int) -> Dictionary:
	return {"rank": rank, "entry_id": entry, "ticks": ticks, "finished_on": "2026-10-29", "names": null, "gold_leaf": false, "replay_hash": null}

func _states() -> void:
	var now := Time.get_unix_time_from_system()
	var fresh := {"board": LIGHTHOUSE_BOARD, "entry_id": "a".repeat(32), "ticks": 1470, "assisted": false, "finished_at": _now_iso(-30)}
	var old := fresh.duplicate()
	old.finished_at = "2026-10-20T10:00:00.000Z"
	var assisted := fresh.duplicate()
	assisted.assisted = true
	_check(BoardStatus.of_run(fresh, false, {}, now).state == BoardStatus.OFF, "with leaderboards off on the server, nothing was posted")
	_check(BoardStatus.of_run(assisted, true, {}, now).state == BoardStatus.ASSISTED, "a run with Forgiving catches on can't rank")
	_check(BoardStatus.of_run(fresh, true, {}, now).state == BoardStatus.CHECKING, "a run just finished counts as checking before any board read")
	_check(BoardStatus.of_run(fresh, true, _view(LIGHTHOUSE_BOARD, [], [fresh.entry_id]), now).state == BoardStatus.CHECKING, "a run the board lists as checking is checking")
	var ranked := BoardStatus.of_run(fresh, true, _view(LIGHTHOUSE_BOARD, [_row(1, "c".repeat(32), 900), _row(2, fresh.entry_id, 1470)], []), now)
	_check(ranked.state == BoardStatus.RANKED and ranked.rank == 2 and ranked.ticks == 1470, "a run in the top 10 has its place: %s" % [ranked])
	_check(BoardStatus.of_run(fresh, true, _view(LIGHTHOUSE_BOARD, [], []), now).state == BoardStatus.CHECKING, "a board copy from before the post does not call a new run settled")
	_check(BoardStatus.of_run(old, true, _view(LIGHTHOUSE_BOARD, [], []), now).state == BoardStatus.NOT_LISTED, "an older run the board no longer lists is off the board")
	var ten: Array = []
	for index in range(10): ten.append(_row(index + 1, "%032x" % (index + 1), 100 + index))
	_check(BoardStatus.of_run(fresh, true, _view(LIGHTHOUSE_BOARD, ten, []), now).state == BoardStatus.NOT_LISTED, "a run slower than ten listed runs is off the board at once")
	_check(BoardStatus.of_run({"board": LIGHTHOUSE_BOARD, "entry_id": "d".repeat(32), "ticks": 5, "assisted": false, "finished_at": ""}, true, _view(LIGHTHOUSE_BOARD, [], []), now).state == BoardStatus.CHECKING, "a run with no readable time is never called settled")

func _line_words() -> void:
	_check(Line.text({"state": BoardStatus.CHECKING, "ticks": 1470}) == PlayerCopy.BOARD_LINE_CHECKING % "0:49.0", "checking names the pending time")
	_check(Line.text({"state": BoardStatus.RANKED, "ticks": 1470, "rank": 3}) == PlayerCopy.BOARD_LINE_RANKED % ["0:49.0", "3rd"], "a ranked run names its place")
	_check(Line.text({"state": BoardStatus.ASSISTED, "ticks": 1}) == PlayerCopy.BOARD_LINE_ASSISTED and Line.text({"state": BoardStatus.OFF}) == PlayerCopy.BOARD_LINE_OFF, "assisted and off have their own lines")
	_check(Line.text({"state": BoardStatus.NOT_LISTED, "ticks": 1470}) == PlayerCopy.BOARD_LINE_NOT_LISTED % "0:49.0" and Line.text({}).is_empty(), "off the board has its line; no state, no line")
	var lines := [PlayerCopy.BOARD_LINE_OFF, PlayerCopy.BOARD_LINE_ASSISTED, PlayerCopy.BOARD_LINE_TURN_OFF, PlayerCopy.BOARD_LINE_TURNED_OFF, PlayerCopy.BOARD_LINE_CHECKING, PlayerCopy.BOARD_LINE_RANKED,
		PlayerCopy.BOARD_LINE_NOT_LISTED, PlayerCopy.BOARD_HOME_CHECKING, PlayerCopy.LEADERBOARD_OWN_ASSISTED, PlayerCopy.LEADERBOARD_OWN_NOT_LISTED, PlayerCopy.LEADERBOARD_RULES,
		PlayerCopy.SETTINGS_ASSISTANCE_CONFIRM_TITLE, PlayerCopy.SETTINGS_ASSISTANCE_CONFIRM_BODY, PlayerCopy.SETTINGS_ASSISTANCE_CONFIRM_ACCEPT]
	_check(lines.all(func(text: String) -> bool: return not text.is_empty() and not "—" in text and not "–" in text and not " - " in text), "the new words have no dashes")

func _host() -> FakeHost:
	var host := FakeHost.new()
	host.api = FakeApi.new()
	host.api.player_id = OWNER
	host.settings_flow.saves = host.saves
	root.add_child(host.api)
	root.add_child(host)
	Client.shared(host.api, OWNER)._choice_path = CHOICE_PATH
	return host

func _drop(host: FakeHost) -> void:
	host.api.queue_free()
	host.queue_free()

func _frames(count: int) -> void:
	for frame in range(count): await process_frame

func _end_of_run_line() -> void:
	var host := _host()
	var flow := Flow.new(host)
	var path := "/v1/leaderboards/" + LIGHTHOUSE_BOARD
	var room := "L1L1L1L1L1L1L1L1L1L1L1"
	var entry := Runs.entry_id(room, 1)
	host.api.replies["GET " + path] = {"ok": true, "data": _view(LIGHTHOUSE_BOARD, [], [entry])}
	var line: Control = flow.line_for(_snapshot(room, _lighthouse_final(), _now_iso(-5)), Registry.LIGHTHOUSE_V2)
	root.add_child(line)
	var words := line.find_child("BoardStatusText", true, false) as Label
	_check(line.visible and words.text == PlayerCopy.BOARD_LINE_CHECKING % "0:49.0", "the end-of-run card says the time is being checked at once")
	_check(Runs.on_board(OWNER, LIGHTHOUSE_BOARD).any(func(run: Dictionary) -> bool: return run.entry_id == entry), "the finished run is noted for the board screen too")
	await _frames(4)
	_check(host.api.requests.size() == 1 and host.api.requests[0][1] == path, "the line reads its board once: %s" % [host.api.requests])
	_check(words.text == PlayerCopy.BOARD_LINE_CHECKING % "0:49.0" and not (line.find_child("BoardStatusTurnOff", true, false) as Button).visible, "the board confirms it is checking; no button")
	var reads: int = host.api.requests.size()
	flow.service_home()
	await _frames(2)
	flow._next_check = 0
	flow.service_home()
	await _frames(2)
	_check(host.toasts == [PlayerCopy.BOARD_HOME_CHECKING % "0:49.0"] and host.api.requests.size() == reads, "back on Home it says so once, with no read of its own: %s" % [host.toasts])
	line.queue_free()
	# A run already ranked by the time the card opens again shows its place.
	var ranked_room := "R1R1R1R1R1R1R1R1R1R1R1"
	host.api.replies["GET " + path] = {"ok": true, "data": _view(LIGHTHOUSE_BOARD, [_row(1, Runs.entry_id(ranked_room, 1), 1470)], [])}
	Client.shared(host.api, OWNER)._views.clear()
	line = flow.line_for(_snapshot(ranked_room, _lighthouse_final(), _now_iso(-5)), Registry.LIGHTHOUSE_V2)
	root.add_child(line)
	await _frames(4)
	_check((line.find_child("BoardStatusText", true, false) as Label).text == PlayerCopy.BOARD_LINE_RANKED % ["0:49.0", "1st"], "a ranked run's card names its place")
	line.queue_free()
	# Assisted: no request, a button that turns Forgiving catches off in place.
	host.api.requests.clear()
	line = flow.line_for(_snapshot("S1S1S1S1S1S1S1S1S1S1S1", _relay_final(), _now_iso(-5)), Registry.RELAY)
	root.add_child(line)
	await _frames(3)
	var button := line.find_child("BoardStatusTurnOff", true, false) as Button
	_check((line.find_child("BoardStatusText", true, false) as Label).text == PlayerCopy.BOARD_LINE_ASSISTED and button.visible, "an assisted run says why it can't rank and offers to turn it off")
	_check(host.api.requests.is_empty(), "an assisted run needs no board read")
	button.pressed.emit()
	_check(host.saves.data.settings.assistance == false and not button.visible and (line.find_child("BoardStatusText", true, false) as Label).text == PlayerCopy.BOARD_LINE_TURNED_OFF, "Turn off saves it and says the next run can count")
	line.queue_free()
	line = flow.line_for(_snapshot("S1S1S1S1S1S1S1S1S1S1S1", _relay_final(), _now_iso(-5)), Registry.RELAY)
	root.add_child(line)
	_check(not (line.find_child("BoardStatusTurnOff", true, false) as Button).visible, "with it already off on this phone there is no button")
	line.queue_free()
	# Leaderboards off on the server: says so, asks nothing.
	host.relay_session.on = false
	host.api.requests.clear()
	line = flow.line_for(_snapshot(room, _lighthouse_final(), _now_iso(-5)), Registry.LIGHTHOUSE_V2)
	root.add_child(line)
	await _frames(3)
	_check((line.find_child("BoardStatusText", true, false) as Label).text == PlayerCopy.BOARD_LINE_OFF and host.api.requests.is_empty(), "with the board off the line says it was not posted")
	line.queue_free()
	var solo := _snapshot(room, _lighthouse_final(), _now_iso())
	solo.guest_id = null
	_check(flow.line_for(solo, Registry.LIGHTHOUSE_V2) == null, "a room without a partner has no line")
	_drop(host)

func _home_watch() -> void:
	Runs.use_path(RUNS_PATH)
	_clear(RUNS_PATH)
	Runs.use_path(RUNS_PATH)
	var host := _host()
	var flow := Flow.new(host)
	var room := "H1H1H1H1H1H1H1H1H1H1H1"
	var entry := Runs.entry_id(room, 1)
	var path := "/v1/leaderboards/" + LIGHTHOUSE_BOARD
	Runs.note(OWNER, _snapshot(room, _lighthouse_final(), _now_iso(-60)), Registry.LIGHTHOUSE_V2)
	host.api.replies["GET " + path] = {"ok": true, "data": _view(LIGHTHOUSE_BOARD, [], [entry])}
	host.free_for_card = false
	flow.service_home()
	await _frames(3)
	_check(host.api.requests.is_empty(), "Home reads nothing while it is busy")
	host.free_for_card = true
	flow._next_check = 0
	flow.service_home()
	await _frames(4)
	_check(host.api.requests.size() == 1 and host.toasts == [PlayerCopy.BOARD_HOME_CHECKING % "0:49.0"], "Home reads the board once and says the time is being checked: %s %s" % [host.api.requests, host.toasts])
	for step in range(3):
		flow.service_home()
		await _frames(2)
	_check(host.api.requests.size() == 1, "every frame after costs nothing")
	flow._next_check = 0
	flow.service_home()
	await _frames(3)
	_check(host.api.requests.size() == 1, "the same board is read again only after READ_MS")
	# Ten minutes on, the run has ranked: the read hands it to Home's celebration and stops.
	flow._next_check = 0
	flow._read_at[LIGHTHOUSE_BOARD] = Time.get_ticks_msec() - Flow.READ_MS - 1
	Client.shared(host.api, OWNER)._views.clear()
	host.api.replies["GET " + path] = {"ok": true, "data": _view(LIGHTHOUSE_BOARD, [_row(4, entry, 1470)], [])}
	flow.service_home()
	await _frames(4)
	_check(host.api.requests.size() == 2 and host.toasts.size() == 1, "one more read, no second note")
	_check(Placings.shared().has_pending(OWNER) and Placings.shared().next(OWNER).entry_id == entry, "the ranked run waits for Home's celebration")
	flow._next_check = 0
	flow._read_at.clear()
	flow.service_home()
	await _frames(3)
	_check(host.api.requests.size() == 2, "a settled run is not read again")
	var later := Flow.new(host)
	host.relay_session.on = false
	later.service_home()
	await _frames(2)
	_check(host.api.requests.size() == 2, "with the board off Home reads nothing")
	_drop(host)

func _board_reasons() -> void:
	_clear(RUNS_PATH)
	Runs.use_path(RUNS_PATH)
	var api := FakeApi.new()
	root.add_child(api)
	Runs.note(OWNER, _snapshot("A1A1A1A1A1A1A1A1A1A1A1", _relay_final(), "2026-10-20T10:00:00.000Z"), Registry.RELAY)
	api.replies["GET /v1/leaderboards/" + RELAY_BOARD] = {"ok": true, "data": _view(RELAY_BOARD, [], [])}
	var screen := Screen.new()
	screen.client = Client.new(api, OWNER, CHOICE_PATH)
	screen.player_id = OWNER
	screen.chapter_filter = func(key: String) -> bool: return key == Registry.RELAY
	root.add_child(screen)
	await _frames(10)
	var own: Node = screen.find_child("LeaderboardOwn", true, false)
	_check(own != null and _texts(own).has(PlayerCopy.LEADERBOARD_OWN_ASSISTED), "Your best from an assisted run says why it has no place: %s" % [_texts(own) if own != null else []])
	screen.close()
	_clear(RUNS_PATH)
	Runs.use_path(RUNS_PATH)
	Runs.note(OWNER, _snapshot("B1B1B1B1B1B1B1B1B1B1B1", _lighthouse_final(), "2026-10-20T10:00:00.000Z"), Registry.LIGHTHOUSE_V2)
	api.replies["GET /v1/leaderboards/" + LIGHTHOUSE_BOARD] = {"ok": true, "data": _view(LIGHTHOUSE_BOARD, [], [])}
	screen = Screen.new()
	screen.client = Client.new(api, OWNER, CHOICE_PATH)
	screen.player_id = OWNER
	screen.chapter_filter = func(key: String) -> bool: return key == Registry.LIGHTHOUSE_V2
	root.add_child(screen)
	await _frames(10)
	own = screen.find_child("LeaderboardOwn", true, false)
	_check(own != null and _texts(own).has(PlayerCopy.LEADERBOARD_OWN_NOT_LISTED) and not _texts(own).has(PlayerCopy.LEADERBOARD_OWN_ASSISTED), "an older run the board does not list says it didn't make the board")
	screen.close()
	api.queue_free()
	await _frames(2)

func _texts(node: Node) -> Array:
	var result: Array = []
	for label: Node in node.find_children("*", "Label", true, false): result.append(label.text)
	return result

func _save_path(tag: String) -> String:
	return "user://board-feedback-save-%s-%s.json" % [tag, Crypto.new().generate_random_bytes(6).hex_encode()]

func _remove_save(path: String) -> void:
	_clear(path)
	var dir := DirAccess.open("user://")
	if dir == null: return
	for name: String in dir.get_files():
		if name.begins_with(path.get_file() + Storage.UNREADABLE) or name.begins_with(path.get_file() + ".") and name.contains(Storage.UNREADABLE):
			dir.remove(name)

func _open(path: String) -> RefCounted:
	var store := Storage.new(path)
	store.load_data()
	store.start_fresh_if_unreadable()
	return store

func _settings_migration() -> void:
	# An existing install from before: Forgiving catches on, no migration mark.
	var path := _save_path("old")
	var old := Storage.new(path)
	old.load_data()
	old.data.settings.sound = false
	_check(old.data.settings.assistance == true and old.flush(), "an older install's save keeps Forgiving catches on")
	var store := _open(path)
	_check(store.settle_settings(), "the first start of this build switches it off")
	_check(store.data.settings.assistance == false and store.data.settings.sound == false and store.data[Storage.SETTINGS_MIGRATION_KEY] == Storage.SETTINGS_MIGRATION, "only Forgiving catches changes, and the save is marked")
	var reread := _open(path)
	_check(reread.data.settings.assistance == false and reread.data.get(Storage.SETTINGS_MIGRATION_KEY) == Storage.SETTINGS_MIGRATION, "the switch off is written at once")
	_check(not reread.data.settings.has(Storage.SETTINGS_MIGRATION_KEY) and Storage.default_settings_envelope_valid(Storage.defaults().settings) and Storage.defaults().settings.assistance == true, "the mark sits outside settings; chapter envelopes and defaults() are unchanged")
	# The player turns it back on: their choice stays.
	var next: Dictionary = reread.data.settings.duplicate(true)
	next.assistance = true
	_check(reread.update_values({"settings": next}), "turning it on again saves")
	var again := _open(path)
	_check(not again.settle_settings() and again.data.settings.assistance == true, "a later start keeps the player's choice")
	_remove_save(path)
	# A brand new install: off, marked in memory, nothing written until the first save.
	path = _save_path("new")
	var fresh := _open(path)
	_check(fresh.fresh and fresh.settle_settings() and fresh.data.settings.assistance == false and fresh.data[Storage.SETTINGS_MIGRATION_KEY] == Storage.SETTINGS_MIGRATION, "a new install starts with it off and marked")
	_check(not FileAccess.file_exists(path), "a new install writes nothing at start")
	_check(fresh.flush() and _open(path).data.settings.assistance == false and not _open(path).settle_settings(), "after its first save it is never migrated again")
	_remove_save(path)
	# A save a newer app wrote is left alone.
	path = _save_path("newer")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"version": 2, "generation": 4, "settings": {"assistance": true}}))
	file.close()
	var newer := _open(path)
	_check(newer.read_only and not newer.settle_settings() and newer.data.settings.assistance == true, "a read-only save is not changed")
	_remove_save(path)
	# A save that could not be read starts over as a new install would.
	path = _save_path("broken")
	file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string("{ not json")
	file.close()
	var started_over := _open(path)
	_check(started_over.fresh and started_over.settle_settings() and started_over.data.settings.assistance == false, "a save that starts over gets the new player settings too")
	_remove_save(path)

func _cloud_never_turns_it_on() -> void:
	var local := {"assistance": false, "sound": true}
	_check(Sources.cloud_values({"assistance": true, "sound": false}, local) == {"assistance": false, "sound": false}, "a cloud copy never turns Forgiving catches on, and other settings still follow")
	_check(Sources.cloud_values({"assistance": false}, {"assistance": true}) == {"assistance": false}, "turning it off still follows from the cloud")
	_check(Sources.cloud_values({"assistance": true}, {"assistance": true}) == {"assistance": true}, "a copy that agrees changes nothing")
	_check(Sources.cloud_values({"assistance": true, "haptics": false}, {}) == {"haptics": false}, "with no local value it is left out, never turned on")
	_check("assistance" in Bundle.SETTINGS_KEYS, "the bundle format is unchanged, so older builds still read it")
