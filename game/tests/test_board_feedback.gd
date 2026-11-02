extends SceneTree
## What a player hears about a together run's leaderboard time:
## services/board_status.gd (one state for a run), presentation/board_status_line.gd
## (the end-of-run line and its Turn off Forgiving catches button),
## presentation/board_feedback_flow.gd (the line's one board read, the place
## celebrated over the room before its check, and Home's throttled watch), the
## board as this phone shows it (a run waiting for its check at its place, with
## a clock), the board screen's reason under Your best, LocalSave's
## one-time Forgiving catches switch off, and the cloud never turning it back on.
## Every request goes to a fake transport; saves use their own files.
const BoardStatus = preload("res://services/board_status.gd")
const Line = preload("res://presentation/board_status_line.gd")
const Flow = preload("res://presentation/board_feedback_flow.gd")
const Runs = preload("res://services/leaderboard_runs.gd")
const Client = preload("res://services/leaderboard_client.gd")
const Placings = preload("res://services/leaderboard_placings.gd")
const Screen = preload("res://presentation/leaderboard_screen.gd")
const Celebration = preload("res://presentation/leaderboard_celebration.gd")
const Registry = preload("res://services/chapter_registry.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const Storage = preload("res://services/local_save.gd")
const Sources = preload("res://services/platform_games/cloud_save_sources.gd")
const Bundle = preload("res://services/platform_games/cloud_save_bundle.gd")
const State = preload("res://services/platform_games/platform_games_state.gd")
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
	var data := {"settings": {"assistance": true, "reduced_motion": true}}

class FakeSound extends Node:
	var cues: Array = []
	func play_fixed_cue(key: String, _variant: int = 0) -> void: cues.append(key)

## The parts of a room's screen (relay_preview.gd) the flow reads: its ui, its soundscape and leave().
class FakeRoom extends Node:
	var ui := Control.new()
	var soundscape := FakeSound.new()
	var card := VBoxContainer.new()
	var host: Node
	var stays := false
	func _init() -> void:
		ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(ui)
		ui.add_child(card)
		add_child(soundscape)
	func leave() -> bool:
		if stays: return false
		host.relay_child = null
		return true

## The parts of Main presentation/board_feedback_flow.gd reads.
class FakeHost extends Node:
	var api: Node
	var saves := FakeSaves.new()
	var relay_session: RefCounted = FakeSession.new()
	var settings_flow := FakeSettingsFlow.new()
	var relay_child: Node
	var free_for_card := true
	var toasts: Array = []
	var boards_viewed: Array = []
	func _home_free_for_card() -> bool: return free_for_card
	func _view_leaderboard(board: String) -> void: boards_viewed.append(board)
	func _home_settling() -> bool: return false
	func _toast(text: String) -> void: toasts.append(text)

func _run() -> void:
	for path: String in [RUNS_PATH, PLACINGS_PATH, CHOICE_PATH]: _clear(path)
	Runs.use_path(RUNS_PATH)
	Placings.use_shared(Placings.new(PLACINGS_PATH))
	_states()
	_shown_rows()
	_line_words()
	await _end_of_run_line()
	await _end_of_run_celebration()
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
	_check(BoardStatus.of_run(old, true, {}, now).state == BoardStatus.UNKNOWN and Line.text(BoardStatus.of_run(old, true, {}, now)).is_empty(), "an older run with no board read has no line, never a guess")
	# One entry per pair (backend board.ts submit): a repeat no faster than the pair's own listed run was never taken.
	var mine_first := {"board": LIGHTHOUSE_BOARD, "entry_id": "e".repeat(32), "ticks": 1400, "assisted": false, "finished_at": _now_iso(-3600), "partner": PARTNER}
	var repeat := fresh.duplicate()
	repeat.partner = PARTNER
	var waiting := _view(LIGHTHOUSE_BOARD, [], [mine_first.entry_id])
	_check(BoardStatus.of_run(repeat, true, waiting, now, [mine_first, repeat]).state == BoardStatus.NOT_LISTED, "a slower repeat by the same pair is off the board at once, even just finished")
	_check(BoardStatus.of_run(repeat, true, _view(LIGHTHOUSE_BOARD, [_row(1, mine_first.entry_id, 1400)], []), now, [mine_first, repeat]).state == BoardStatus.NOT_LISTED, "the same when the pair's faster run is ranked")
	var other_partner := mine_first.duplicate()
	other_partner.partner = "PPPPPPPPPPPPPPPPPPPPPP"
	_check(BoardStatus.of_run(repeat, true, waiting, now, [other_partner, repeat]).state == BoardStatus.CHECKING, "a run with another partner is a different pair")
	var slower := mine_first.duplicate()
	slower.ticks = 1600
	_check(BoardStatus.of_run(repeat, true, waiting, now, [slower, repeat]).state == BoardStatus.CHECKING, "a faster repeat replaces the pair's run, so it may be checking")
	_check(BoardStatus.listed_checking(fresh, _view(LIGHTHOUSE_BOARD, [], [fresh.entry_id])) and not BoardStatus.listed_checking(fresh, _view(LIGHTHOUSE_BOARD, [], [])) and not BoardStatus.listed_checking(fresh, {}), "only a board that lists the run says it is checking")

func _run_on(entry: String, ticks: int, partner: String, finished_at: String, assisted: bool = false) -> Dictionary:
	return {"board": LIGHTHOUSE_BOARD, "entry_id": entry, "ticks": ticks, "assisted": assisted, "finished_at": finished_at, "partner": partner}

func _ranks(rows: Array) -> Array:
	return rows.map(func(row: Dictionary) -> Array: return [row.rank, str(row.entry_id).left(2), bool(row.pending)])

## The board as this phone shows it (BoardStatus.shown_rows and place).
func _shown_rows() -> void:
	var now := Time.get_unix_time_from_system()
	var ten: Array = []
	for index in range(10): ten.append(_row(index + 1, ("%02d" % (index + 1)).repeat(16), 1000 + 100 * index))
	var waiting := _run_on("aa".repeat(16), 1250, PARTNER, _now_iso(-30))
	var view := _view(LIGHTHOUSE_BOARD, ten, [waiting.entry_id])
	var rows := BoardStatus.shown_rows(view, [waiting], now)
	_check(rows.size() == 10 and rows[3].entry_id == waiting.entry_id and rows[3].pending and rows[3].rank == 4 and rows[4].entry_id == ten[3].entry_id and rows[4].rank == 5, "a run waiting for its check stands at the place its time gets, the rest move down: %s" % [_ranks(rows)])
	_check(not rows.any(func(row: Dictionary) -> bool: return row.entry_id == ten[9].entry_id), "and the tenth drops off the board this phone shows")
	_check(BoardStatus.place(waiting, view, now, [waiting]) == 4, "its place: %d" % BoardStatus.place(waiting, view, now, [waiting]))
	_check(ten[3].rank == 4 and not ten[3].has("pending"), "the board read is never changed")
	var tie := waiting.duplicate()
	tie.ticks = 1300
	_check(BoardStatus.place(tie, _view(LIGHTHOUSE_BOARD, ten, [tie.entry_id]), now, [tie]) == 5, "on equal times the listed run stays ahead")
	var others := _view(LIGHTHOUSE_BOARD, ten.slice(0, 3), ["bb".repeat(16), "cc".repeat(16)])
	_check(_ranks(BoardStatus.shown_rows(others, [], now)) == [[1, "01", false], [2, "02", false], [3, "03", false]], "other pairs' runs waiting for their checks move nobody")
	# The pair's slower ranked run gives its place to the faster run waiting, and keeps its names.
	var ranked := _run_on("dd".repeat(16), 1650, PARTNER, "2026-10-20T10:00:00.000Z")
	var with_ranked: Array = ten.duplicate(true)
	with_ranked[6] = _row(7, ranked.entry_id, 1650)
	with_ranked[6].names = ["Ada", "Bo"]
	rows = BoardStatus.shown_rows(_view(LIGHTHOUSE_BOARD, with_ranked, [waiting.entry_id]), [ranked, waiting], now)
	_check(rows.size() == 10 and not rows.any(func(row: Dictionary) -> bool: return row.entry_id == ranked.entry_id) and rows[3].pending and rows[3].names == ["Ada", "Bo"] and rows[9].entry_id == ten[9].entry_id, "one row a pair: the waiting run takes the pair's ranked row's place and names: %s" % [_ranks(rows)])
	var slower := waiting.duplicate()
	slower.entry_id = "ee".repeat(16)
	slower.ticks = 1700
	var slower_view := _view(LIGHTHOUSE_BOARD, with_ranked, [])
	_check(BoardStatus.place(slower, slower_view, now, [ranked, slower]) == 0 and BoardStatus.place(ranked, slower_view, now, [ranked, slower]) == 7 and not BoardStatus.shown_rows(slower_view, [ranked, slower], now).any(func(row: Dictionary) -> bool: return row.pending), "a repeat slower than the pair's ranked run shows nothing waiting")
	var both := waiting.duplicate()
	both.entry_id = "ff".repeat(16)
	both.ticks = 1150
	rows = BoardStatus.shown_rows(_view(LIGHTHOUSE_BOARD, ten, []), [waiting, both], now)
	_check(rows.filter(func(row: Dictionary) -> bool: return row.pending).size() == 1 and rows[2].entry_id == both.entry_id, "two runs just finished by one pair: only the faster shows: %s" % [_ranks(rows)])
	var first := waiting.duplicate()
	first.ticks = 900
	var gold: Array = ten.duplicate(true)
	gold[0].gold_leaf = true
	rows = BoardStatus.shown_rows(_view(LIGHTHOUSE_BOARD, gold, [first.entry_id]), [first], now)
	_check(rows[0].pending and not rows[0].gold_leaf and not rows[1].gold_leaf, "a waiting first place never shows the Gold leaf, and the run it passes loses it here: %s" % [rows.slice(0, 2)])
	# A board read that does not list the run yet (the server's copy from before the post).
	_check(BoardStatus.place(waiting, _view(LIGHTHOUSE_BOARD, ten, []), now, [waiting]) == 4, "a run a moment old the board does not list yet keeps its place")
	# Refused: off the checking list once past the settle window.
	var refused := waiting.duplicate()
	refused.finished_at = _now_iso(-BoardStatus.SETTLE_SECONDS - 60)
	_check(BoardStatus.shown_rows(_view(LIGHTHOUSE_BOARD, ten, []), [refused], now).all(func(row: Dictionary) -> bool: return not row.pending), "a run that failed its check leaves the board quietly")
	_check(BoardStatus.shown_rows(_view(LIGHTHOUSE_BOARD, ten, []), [waiting], now, {waiting.entry_id: true}).all(func(row: Dictionary) -> bool: return not row.pending), "and at once when an earlier read listed it waiting, inside the settle window too")
	var accepted: Array = ten.duplicate(true)
	accepted.insert(3, _row(4, waiting.entry_id, 1250))
	rows = BoardStatus.shown_rows(_view(LIGHTHOUSE_BOARD, accepted.slice(0, 10), []), [waiting], now)
	_check(rows[3].entry_id == waiting.entry_id and not rows[3].pending, "a run that passed is an ordinary row, no clock")
	var assisted := waiting.duplicate()
	assisted.assisted = true
	_check(BoardStatus.place(assisted, view, now, [assisted]) == 0, "a run with Forgiving catches never shows")
	_check(BoardStatus.shown_rows({}, [waiting], now).is_empty() and BoardStatus.place(waiting, {}, now, [waiting]) == 0, "without a board read nothing is placed")
	var eleventh := waiting.duplicate()
	eleventh.ticks = 5000
	_check(BoardStatus.place(eleventh, _view(LIGHTHOUSE_BOARD, ten, [eleventh.entry_id]), now, [eleventh]) == 0, "a run slower than the ten listed has no place")

func _line_words() -> void:
	_check(Line.text({"state": BoardStatus.CHECKING, "ticks": 1470}).is_empty(), "a run waiting for its check has no words on the card (2026-11-02): its place is celebrated instead")
	_check(Line.text({"state": BoardStatus.RANKED, "ticks": 1470, "rank": 3}) == PlayerCopy.BOARD_LINE_RANKED % ["0:49.0", "3rd"], "a ranked run names its place")
	_check(Line.text({"state": BoardStatus.ASSISTED, "ticks": 1}) == PlayerCopy.BOARD_LINE_ASSISTED and Line.text({"state": BoardStatus.OFF}) == PlayerCopy.BOARD_LINE_OFF, "assisted and off have their own lines")
	_check(Line.text({"state": BoardStatus.NOT_LISTED, "ticks": 1470}) == PlayerCopy.BOARD_LINE_NOT_LISTED % "0:49.0" and Line.text({}).is_empty(), "off the board has its line; no state, no line")
	var lines := [PlayerCopy.BOARD_LINE_OFF, PlayerCopy.BOARD_LINE_ASSISTED, PlayerCopy.BOARD_LINE_TURN_OFF, PlayerCopy.BOARD_LINE_TURNED_OFF, PlayerCopy.LEADERBOARD_WAITING_CHECK, PlayerCopy.BOARD_LINE_RANKED,
		PlayerCopy.BOARD_LINE_NOT_LISTED, PlayerCopy.BOARD_HOME_CHECKING, PlayerCopy.LEADERBOARD_OWN_ASSISTED, PlayerCopy.LEADERBOARD_OWN_NOT_LISTED, PlayerCopy.LEADERBOARD_RULES,
		PlayerCopy.SETTINGS_ASSISTANCE_CONFIRM_TITLE, PlayerCopy.SETTINGS_ASSISTANCE_CONFIRM_BODY, PlayerCopy.SETTINGS_ASSISTANCE_CONFIRM_ACCEPT]
	_check(lines.all(func(text: String) -> bool: return not text.is_empty() and not "—" in text and not "–" in text and not " - " in text), "the new words have no dashes")
	_check(not "week" in PlayerCopy.LEADERBOARD_RULES and not "different" in PlayerCopy.LEADERBOARD_RULES, "the rules name no account age or partner count (relaxed 2026-10-29)")

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
	_check(not line.visible and words.text.is_empty(), "the end-of-run card never says the time is being checked")
	_check(Runs.on_board(OWNER, LIGHTHOUSE_BOARD).any(func(run: Dictionary) -> bool: return run.entry_id == entry), "the finished run is noted for the board screen too")
	await _frames(4)
	_check(host.api.requests.size() == 1 and host.api.requests[0][1] == path, "the line reads its board once: %s" % [host.api.requests])
	_check(not line.visible and not (line.find_child("BoardStatusTurnOff", true, false) as Button).visible, "nor once the board confirms it is checking; no button")
	var reads: int = host.api.requests.size()
	flow.service_home()
	await _frames(2)
	flow._next_check = 0
	flow.service_home()
	await _frames(2)
	_check(host.toasts == [PlayerCopy.BOARD_HOME_CHECKING % "0:49.0"] and host.api.requests.size() == reads, "back on Home it says so once, with no read of its own: %s" % [host.toasts])
	line.queue_free()
	host.toasts.clear()
	# Just finished and not listed yet: the card guesses checking; Home stays quiet.
	var guess_room := "Q1Q1Q1Q1Q1Q1Q1Q1Q1Q1Q1"
	host.api.replies["GET " + path] = {"ok": true, "data": _view(LIGHTHOUSE_BOARD, [], [])}
	Client.shared(host.api, OWNER)._views.clear()
	line = flow.line_for(_snapshot(guess_room, _lighthouse_final(), _now_iso(-1)), Registry.LIGHTHOUSE_V2)
	root.add_child(line)
	await _frames(4)
	_check((line.find_child("BoardStatusText", true, false) as Label).text.is_empty(), "nor for a run a moment old the board does not list yet")
	flow._next_check = 0
	flow.service_home()
	await _frames(3)
	_check(host.toasts.is_empty() and not flow._seen_checking.has(Runs.entry_id(guess_room, 1)), "Home posts nothing on that guess")
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
	host.settings_flow.kept = false
	button.pressed.emit()
	_check(host.toasts == [PlayerCopy.MAIN_34B82590B663] and button.visible and host.saves.data.settings.assistance == true, "a failed save says so and keeps the button")
	host.toasts.clear()
	host.settings_flow.kept = true
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

## Each case its own runs: one pair's runs share one row.
func _fresh_runs() -> void:
	_clear(RUNS_PATH)
	Runs.use_path(RUNS_PATH)

## The end card celebrates the run's place straight away over the room, once.
func _end_of_run_celebration() -> void:
	_clear(RUNS_PATH)
	_clear(PLACINGS_PATH)
	Runs.use_path(RUNS_PATH)
	Placings.use_shared(Placings.new(PLACINGS_PATH))
	var host := _host()
	var room := FakeRoom.new()
	room.host = host
	host.relay_child = room
	root.add_child(room)
	var flow := Flow.new(host)
	var path := "/v1/leaderboards/" + LIGHTHOUSE_BOARD
	var three := [_row(1, "01".repeat(16), 900), _row(2, "02".repeat(16), 1200), _row(3, "03".repeat(16), 2000)]
	var first_room := "C1C1C1C1C1C1C1C1C1C1C1"
	var entry := Runs.entry_id(first_room, 1)
	host.api.replies["GET " + path] = {"ok": true, "data": _view(LIGHTHOUSE_BOARD, three, [entry])}
	Client.shared(host.api, OWNER)._views.clear()
	var snapshot := _snapshot(first_room, _lighthouse_final(), _now_iso(-5))
	var line: Control = flow.line_for(snapshot, Registry.LIGHTHOUSE_V2)
	room.card.add_child(line)
	await _frames(5)
	var shown: Node = room.ui.find_child(Celebration.NODE_NAME, false, false)
	_check(shown != null and shown.placing.rank == 3 and shown.placing.entry_id == entry and shown.placing.ticks == 1470 and shown.placing.names == null and not shown.placing.gold_leaf, "once the board is read the place the run gets is celebrated over the room: %s" % [shown.placing if shown != null else {}])
	_check(room.soundscape.cues == ["ui_third"], "with the place's own sound, on the room's soundscape: %s" % [room.soundscape.cues])
	_check(Placings.shared().was_shown(OWNER, entry) and not line.visible, "marked shown, and the card says nothing about the check")
	_check(shown != null and shown.reduced, "under Reduce motion")
	_check(Celebration.close_over(room.ui) and not Celebration.close_over(room.ui), "Back closes the celebration, and only it")
	await _frames(1)
	# The card drawn again (the room refreshed, or opened again later): no second one.
	line.queue_free()
	line = flow.line_for(snapshot, Registry.LIGHTHOUSE_V2)
	room.card.add_child(line)
	await _frames(5)
	_check(not Celebration.showing(room.ui) and room.soundscape.cues.size() == 1, "a run is celebrated once")
	# It passes: the read that ranks it queues nothing for Home.
	host.api.replies["GET " + path] = {"ok": true, "data": _view(LIGHTHOUSE_BOARD, [three[0], three[1], _row(3, entry, 1470), _row(4, three[2].entry_id, 2000)], [])}
	await Client.shared(host.api, OWNER).board(LIGHTHOUSE_BOARD, true)
	_check(not Placings.shared().has_pending(OWNER), "its confirmation later is no news")
	line.queue_free()
	# A board already read celebrates at once, before the card's own read.
	_fresh_runs()
	var kept_room := "C2C2C2C2C2C2C2C2C2C2C2"
	var kept_entry := Runs.entry_id(kept_room, 1)
	host.api.replies["GET " + path] = {"ok": true, "data": _view(LIGHTHOUSE_BOARD, [_row(1, "01".repeat(16), 2000)], [])}
	await Client.shared(host.api, OWNER).board(LIGHTHOUSE_BOARD, true)
	line = flow.line_for(_snapshot(kept_room, _lighthouse_final(), _now_iso(-2)), Registry.LIGHTHOUSE_V2)
	room.card.add_child(line)
	await _frames(1)
	shown = room.ui.find_child(Celebration.NODE_NAME, false, false)
	_check(shown != null and shown.placing.entry_id == kept_entry and shown.placing.rank == 1 and room.soundscape.cues.back() == "ui_first", "the board this phone kept places it first straight away")
	room.stays = true
	shown.find_child("CelebrationViewBoard", true, false).pressed.emit()
	_check(host.boards_viewed.is_empty() and host.relay_child == room, "a room that can't close yet keeps the player in it")
	room.stays = false
	await _frames(5)
	_check(not Celebration.showing(room.ui), "the card's own read after it celebrates nothing more")
	Placings.use_shared(Placings.new(PLACINGS_PATH))
	_check(Placings.shared().was_shown(OWNER, kept_entry), "shown survives a restart")
	line.queue_free()
	# View board leaves the room, then opens the board.
	_fresh_runs()
	var view_room := "C3C3C3C3C3C3C3C3C3C3C3"
	Client.shared(host.api, OWNER)._views.clear()
	line = flow.line_for(_snapshot(view_room, _lighthouse_final(), _now_iso(-2)), Registry.LIGHTHOUSE_V2)
	room.card.add_child(line)
	await _frames(5)
	shown = room.ui.find_child(Celebration.NODE_NAME, false, false)
	_check(shown != null and shown.placing.rank == 1, "a run placing first celebrates")
	if shown != null: shown.find_child("CelebrationViewBoard", true, false).pressed.emit()
	_check(host.boards_viewed == [LIGHTHOUSE_BOARD] and host.relay_child == null, "View board leaves the room, then opens its board: %s" % [host.boards_viewed])
	host.relay_child = room
	line.queue_free()
	await _frames(1)
	# A run already confirmed when the card reads its board: its row's names and Gold leaf.
	_fresh_runs()
	var gold_room := "C7C7C7C7C7C7C7C7C7C7C7"
	var gold_row := _row(1, Runs.entry_id(gold_room, 1), 1470)
	gold_row.names = ["Ada", "Bo"]
	gold_row.gold_leaf = true
	host.api.replies["GET " + path] = {"ok": true, "data": _view(LIGHTHOUSE_BOARD, [gold_row], [])}
	Client.shared(host.api, OWNER)._views.clear()
	line = flow.line_for(_snapshot(gold_room, _lighthouse_final(), _now_iso(-2)), Registry.LIGHTHOUSE_V2)
	room.card.add_child(line)
	await _frames(5)
	shown = room.ui.find_child(Celebration.NODE_NAME, false, false)
	_check(shown != null and shown.placing.gold_leaf and shown.placing.names == ["Ada", "Bo"] and not Placings.shared().has_pending(OWNER), "a confirmed first place keeps its Gold leaf and names, celebrated once, here")
	if shown != null: Celebration.close_over(room.ui)
	line.queue_free()
	await _frames(1)
	# The room changed under the card's read: nothing, and Home can still celebrate it.
	_fresh_runs()
	var swap_room := "C8C8C8C8C8C8C8C8C8C8C8"
	host.api.replies["GET " + path] = {"ok": true, "data": _view(LIGHTHOUSE_BOARD, [_row(1, "01".repeat(16), 2000)], [])}
	Client.shared(host.api, OWNER)._views.clear()
	line = flow.line_for(_snapshot(swap_room, _lighthouse_final(), _now_iso(-2)), Registry.LIGHTHOUSE_V2)
	room.card.add_child(line)
	var other := FakeRoom.new()
	other.host = host
	root.add_child(other)
	host.relay_child = other
	await _frames(5)
	_check(not Celebration.showing(room.ui) and not Celebration.showing(other.ui) and not Placings.shared().was_shown(OWNER, Runs.entry_id(swap_room, 1)), "a card whose room is no longer the open one celebrates nothing")
	host.relay_child = room
	other.queue_free()
	line.queue_free()
	# No celebration: the card gone before the read, a failed read, a place outside the top 10.
	_fresh_runs()
	var gone_room := "C4C4C4C4C4C4C4C4C4C4C4"
	Client.shared(host.api, OWNER)._views.clear()
	line = flow.line_for(_snapshot(gone_room, _lighthouse_final(), _now_iso(-2)), Registry.LIGHTHOUSE_V2)
	room.card.add_child(line)
	line.queue_free()
	await _frames(5)
	_check(not Celebration.showing(room.ui) and not Placings.shared().was_shown(OWNER, Runs.entry_id(gone_room, 1)), "a card gone before its read celebrates nothing, so Home can later")
	var failed_room := "C5C5C5C5C5C5C5C5C5C5C5"
	Client.shared(host.api, OWNER)._views.clear()
	host.api.replies["GET " + path] = {"ok": false, "code": "offline"}
	line = flow.line_for(_snapshot(failed_room, _lighthouse_final(), _now_iso(-2)), Registry.LIGHTHOUSE_V2)
	room.card.add_child(line)
	await _frames(5)
	_check(not Celebration.showing(room.ui) and not Placings.shared().was_shown(OWNER, Runs.entry_id(failed_room, 1)), "no board read, no guess")
	line.queue_free()
	var ten: Array = []
	for index in range(10): ten.append(_row(index + 1, ("%02d" % (index + 11)).repeat(16), 100 + index))
	var slow_room := "C6C6C6C6C6C6C6C6C6C6C6"
	host.api.replies["GET " + path] = {"ok": true, "data": _view(LIGHTHOUSE_BOARD, ten, [])}
	Client.shared(host.api, OWNER)._views.clear()
	line = flow.line_for(_snapshot(slow_room, _lighthouse_final(), _now_iso(-2)), Registry.LIGHTHOUSE_V2)
	room.card.add_child(line)
	await _frames(5)
	_check(not Celebration.showing(room.ui), "a time outside the top 10 celebrates nothing")
	line.queue_free()
	room.queue_free()
	host.relay_child = null
	_drop(host)
	await _frames(1)
	_clear(PLACINGS_PATH)
	Placings.use_shared(Placings.new(PLACINGS_PATH))

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
	# A save read from its backup keeps the note for the player through the switch off.
	path = _save_path("backup")
	var first := Storage.new(path)
	first.load_data()
	first.flush()
	first.flush()
	var broken := FileAccess.open(path, FileAccess.WRITE)
	broken.store_string("{ damaged")
	broken.close()
	var from_backup := Storage.new(path)
	from_backup.load_data()
	var note := from_backup.last_error
	_check(not note.is_empty() and not from_backup.read_only and from_backup.settle_settings() and from_backup.last_error == note and from_backup.data.settings.assistance == false, "the switch off keeps the startup note: %s" % from_backup.last_error)
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
	_check(Sources.cloud_values({"assistance": true, "sound": false}) == {"sound": false} and Sources.cloud_values({"assistance": false, "haptics": true}) == {"haptics": true}, "Forgiving catches never comes from the cloud, on or off; other settings still follow")
	var bundle := Bundle.collect({"settings": {"assistance": true, "sound": false}}, 5, {}, {})
	_check(not bundle.settings.values.has("assistance") and bundle.settings.values.sound == false, "this phone never sends it")
	var older := Bundle.empty()
	older.settings = {"values": {"assistance": true, "sound": true}, "stamp": 9}
	_check(not Bundle.validated(older).is_empty(), "a copy from an older build that holds it still reads")
	var host := Node.new()
	root.add_child(host)
	var state_path := "user://board-feedback-cloud-state.json"
	_clear(state_path)
	var sources: RefCounted = Sources.new(host, State.new(state_path))
	var fresh_settings: Dictionary = Storage.defaults().settings.duplicate()
	fresh_settings.merge(Storage.NEW_PLAYER_SETTINGS, true)
	_check(sources.settings_stamp(Sources._values(fresh_settings)) == 0, "a new install's untouched settings count as no change, so a restore takes the cloud's Sound and Haptics")
	_clear(state_path)
	host.queue_free()
