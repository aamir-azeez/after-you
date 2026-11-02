extends RefCounted
## What a player hears about a together run's leaderboard time, after the run:
## - line_for(): the end-of-run card's line (presentation/board_status_line.gd).
##   It shows at once from what the phone knows (the run's own final
##   checkpoint and the board this phone last read), then reads the board
##   once (services/leaderboard_client.gd board(), which keeps a read for a
##   minute) and says it again. A run that places on the board this phone
##   shows (services/board_status.gd shown_row(), its check still to come) is
##   celebrated over the room at once, from the kept board or else that read:
##   the same celebration a confirmed place gets, once a run, since it is
##   marked shown in services/leaderboard_placings.gd before it opens, named
##   as the board would name the pair (BoardStatus.pair_names). Its
##   confirmation later is then no news; a run that fails its check just
##   leaves the board this phone shows.
## - service_home(): every frame on Home, but it does work at most every
##   CHECK_MS. While this player's newest run of the last WATCH_SECONDS may
##   still wait for its check, it reads that board at most every READ_MS. Once
##   a read (the card's or its own) has found it listed as checking, Home posts one note
##   when it is free; a read that finds it
##   ranked hands it to services/leaderboard_placings.gd (inside board()), so
##   Home's existing celebration shows the place. A run seen settled is not read again.
## Every board read goes through the shared client; nothing here keeps a view.
const BoardStatus = preload("res://services/board_status.gd")
const BoardStatusLine = preload("res://presentation/board_status_line.gd")
const LeaderboardClient = preload("res://services/leaderboard_client.gd")
const Runs = preload("res://services/leaderboard_runs.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const Placings = preload("res://services/leaderboard_placings.gd")
const Celebration = preload("res://presentation/leaderboard_celebration.gd")
const Soundscape = preload("res://services/soundscape.gd")

const CHECK_MS := 15_000
const READ_MS := 600_000
const WATCH_SECONDS := 172_800.0

var host: Node
## entry_id -> true: runs a read showed ranked or off the board.
var _settled: Dictionary = {}
## entry_id -> true: runs whose checking note was posted this session.
var _noted: Dictionary = {}
## entry_id -> true: runs a read from here found checking.
var _seen_checking: Dictionary = {}
## board -> ticks (msec) of its last read from here.
var _read_at: Dictionary = {}
var _next_check := 0
var _reading := false

func _init(main: Node) -> void:
	host = main

## The line for a finished room's card, or null when the room is not a finished together run with a board.
func line_for(snapshot: Dictionary, chapter_key: String) -> Control:
	var owner := _owner()
	var run := BoardStatus.room_run(owner, snapshot, chapter_key)
	if run.is_empty(): return null
	var line := BoardStatusLine.new()
	line.turn_off_assistance = func() -> bool: return turn_off_assistance()
	line.assistance_on = func() -> bool: return bool(host.saves.data.settings.get("assistance", false))
	var supported := _supported()
	var client := _client() if supported else null
	var kept: Dictionary = client.kept_view(run.board) if client != null else {}
	line.show_status(BoardStatus.of_run(run, supported, kept, _now(), Runs.on_board(owner, run.board)))
	if client != null and not run.assisted:
		# Once the line is on the card, so the room it belongs to is known.
		_celebrate.call_deferred(run, kept, line)
		_read_for_line(client, run, line)
	return line

func _read_for_line(client: RefCounted, run: Dictionary, line: Control) -> void:
	_read_at[run.board] = Time.get_ticks_msec()
	var answer: Dictionary = await client.board(run.board)
	if not answer.get("ok", false) or not is_instance_valid(line): return
	var status := BoardStatus.of_run(run, true, answer.view, _now(), Runs.on_board(_owner(), run.board))
	_note_settled(run, status)
	# Home says it once when the player gets back there, with no read of its own,
	# only when the board itself lists it (never on the just-finished guess).
	if BoardStatus.listed_checking(run, answer.view): _seen_checking[run.entry_id] = true
	line.show_status(status)
	_celebrate(run, answer.view, line)

## Celebrates the place `view` gives the run on this phone, over the room whose
## card holds `line`, once a run. No board read, a place outside the top 10, a
## card already gone or a celebration already up: nothing.
func _celebrate(run: Dictionary, view: Dictionary, line: Control) -> void:
	var owner := _owner()
	var room: Node = host.relay_child
	if owner.is_empty() or not is_instance_valid(line) or not is_instance_valid(room): return
	var parent: Variant = room.get("ui")
	if not parent is Control or not (parent as Control).is_ancestor_of(line) or not (line.get_parent() as Control).is_visible_in_tree() or Celebration.showing(parent): return
	if Placings.shared().was_shown(owner, run.entry_id): return
	var row := BoardStatus.shown_row(run, view, _now(), Runs.on_board(owner, run.board), _pair_names(owner))
	if row.is_empty() or Placings.tier(int(row.rank)).is_empty(): return
	Placings.shared().mark_shown(owner, run.entry_id)
	# The row as the board shows it: a confirmed one brings its names and Gold leaf.
	var placing := Placings.placing_of(row, run.board, str(run.get("partner", "")))
	var shown: Control = Celebration.open(parent, placing, bool(host.saves.data.settings.get("reduced_motion", false)))
	if shown == null: return
	shown.view_board.connect(_view_board)
	# The room's own soundscape: Main's is quiet under it.
	Soundscape.play_on(room, shown.cue())

## View board from a room's celebration: the room closes, then the board opens
## as from Home. A room that does not close yet (a save still going) stays.
func _view_board(board: String) -> void:
	if is_instance_valid(host.relay_child) and not host.relay_child.leave(): return
	host._view_leaderboard(board)

## Turns Forgiving catches off on this phone and in the open room; true when
## saved. A failed save says so, as Settings does.
func turn_off_assistance() -> bool:
	if not host.settings_flow.save_setting("assistance", false):
		host._toast(PlayerCopy.MAIN_34B82590B663)
		return false
	if is_instance_valid(host.relay_child) and host.relay_child.get("settings") is Dictionary: host.relay_child.settings.assistance = false
	return true

func service_home() -> void:
	var now := Time.get_ticks_msec()
	if _reading or now < _next_check: return
	_next_check = now + CHECK_MS
	if not _supported() or not host._home_free_for_card() or host._home_settling(): return
	var owner := _owner()
	var run := BoardStatus.newest_waiting(owner, _settled, _now(), WATCH_SECONDS)
	if run.is_empty(): return
	if _seen_checking.has(run.entry_id) and not _noted.has(run.entry_id):
		_post_note(run)
		return
	if _read_at.has(run.board) and now - int(_read_at[run.board]) < READ_MS: return
	_read_at[run.board] = now
	_reading = true
	var answer: Dictionary = await _client().board(run.board)
	_reading = false
	if not answer.get("ok", false) or owner != _owner(): return
	var status := BoardStatus.of_run(run, true, answer.view, _now(), Runs.on_board(owner, run.board))
	_note_settled(run, status)
	if BoardStatus.listed_checking(run, answer.view):
		_seen_checking[run.entry_id] = true
		if not _noted.has(run.entry_id) and host._home_free_for_card(): _post_note(run)

## "Your time is being checked", once a session for each run.
func _post_note(run: Dictionary) -> void:
	_noted[run.entry_id] = true
	host._toast(PlayerCopy.BOARD_HOME_CHECKING % Runs.time_text(int(run.ticks)))

func _note_settled(run: Dictionary, status: Dictionary) -> void:
	if status.state in [BoardStatus.RANKED, BoardStatus.NOT_LISTED]: _settled[run.entry_id] = true

## The names the board would give this player's pairs (BoardStatus.pair_names), as the board screen names a waiting row.
func _pair_names(owner: String) -> Dictionary:
	var client := _client()
	return BoardStatus.pair_names(Runs.runs_of(owner), client.kept_views(), client.show_name())

func _supported() -> bool:
	return host.relay_session != null and host.relay_session.leaderboards_supported()

func _owner() -> String:
	return str(host.api.player_id) if host.api != null else ""

func _client() -> RefCounted:
	return LeaderboardClient.shared(host.api, _owner())

static func _now() -> float:
	return Time.get_unix_time_from_system()
