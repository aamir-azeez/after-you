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
##   a read (the card's or its own) has found it listed as checking and standing
##   on the board this phone shows (services/board_status.gd stands_waiting, the
##   same rule as the board's clock and card), Home posts one note when it is
##   free; a run that can't move its pair up says nothing. A read that finds it
##   ranked hands it to services/leaderboard_placings.gd (inside board()), so
##   Home's existing celebration shows the place. A run seen settled is not read again.
## - While the server posts only runs whose players both have a Play Games or
##   Game Center account (relay_online_session.gd leaderboards_platform_required,
##   backend leaderboards/platform-rule.ts), the card first asks the server to
##   post the room's run (services/leaderboard_client.gd post_room), once a
##   session for each run. Posted: the line and celebration go on as above.
##   Refused: the run is noted refused (services/leaderboard_runs.gd), so no
##   surface calls it waiting, and the line says who must sign in; for this
##   player a Sign in button runs the same sign-in and link as Settings
##   (services/platform_games/platform_games.gd sign_in_now) and posts again.
##   Linking any other way (Settings) posts this player's refused runs again too.
## Every board read goes through the shared client; nothing here keeps a view.
const ServerSwitches = preload("res://services/server_switches.gd")
const BoardStatus = preload("res://services/board_status.gd")
const BoardStatusLine = preload("res://presentation/board_status_line.gd")
const LeaderboardClient = preload("res://services/leaderboard_client.gd")
const Runs = preload("res://services/leaderboard_runs.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const Placings = preload("res://services/leaderboard_placings.gd")
const Celebration = preload("res://presentation/leaderboard_celebration.gd")
const Soundscape = preload("res://services/soundscape.gd")
const PlatformGames = preload("res://services/platform_games/platform_games.gd")

const CHECK_MS := 15_000
const READ_MS := 600_000
const WATCH_SECONDS := 172_800.0
## Refused runs posted again at most when this player links (the newest first).
const MAX_REPOST := 8

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
## entry_id -> true: runs this session asked the server to post (the platform rule).
var _asked: Dictionary = {}
## Whether the platform service said linked when it last changed, and a repost is running.
var _was_linked := false
var _reposting := false
## Whether this session swept this player's refused runs once linked, and the posts in flight (entry_id -> true).
var _swept := false
var _posting: Dictionary = {}

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
	var gated: bool = client != null and not run.assisted and _platform_required()
	if gated: _wire_sign_in(client, run, str(snapshot.room_id), line)
	var guess := BoardStatus.of_run(run, supported, kept, _now(), Runs.on_board(owner, run.board))
	line.show_status(guess)
	if gated and _should_post(run, guess, kept): _read_then_post(client, run, str(snapshot.room_id), line)
	elif client != null and not run.assisted:
		# Once the line is on the card, so the room it belongs to is known. A refused run is
		# never celebrated (BoardStatus.shown_rows leaves it out); the read still says where it stands.
		# Under the platform rule a run this card did not just post is celebrated only once a read lists it.
		if not gated: _celebrate.call_deferred(run, kept, line)
		_read_for_line(client, run, line, gated)
	return line

## Whether the server posts only runs whose players both have a platform account:
## this session's capabilities when they say so, else the switch last heard
## (services/server_switches.gd), as _supported() reads leaderboards.
func _platform_required() -> bool:
	var session: Variant = host.relay_session
	if session != null and session.has_method("leaderboards_platform_required") and session.leaderboards_platform_required(): return true
	return ServerSwitches.shared().on_for(host.api, "leaderboards_platform")

## Whether the card may need to ask the server to post the run: once a
## session, only for a run finished within WATCH_SECONDS or still marked
## refused, never one the kept board already lists or rules out
## (BoardStatus.ruled_out), and not a run this player kept off while this
## phone is still not linked. _read_then_post reads first.
func _should_post(run: Dictionary, guess: Dictionary, kept: Dictionary) -> bool:
	if _asked.has(run.entry_id) or _posting.has(run.entry_id) or guess.state == BoardStatus.RANKED or BoardStatus.listed_checking(run, kept): return false
	if BoardStatus.ruled_out(run, kept, Runs.on_board(_owner(), run.board)): return false
	var refused := str(run.get("refused", ""))
	# Play is turn by turn: the partner who did not take the final turn often opens this card hours later.
	if refused.is_empty(): return _now() - BoardStatus.finished_unix(run) < WATCH_SECONDS
	var games := _games()
	return refused != Runs.REFUSED_YOU or (games != null and games.linked())

## The card's fresh board read first (free while the board's copy is cached:
## the turn's own post stored it), as for any run. Only a run that read neither
## lists nor rules out is posted through the route (3 Durable Object requests
## or so): a pair both linked already got on the board from the final turn.
func _read_then_post(client: RefCounted, run: Dictionary, room_id: String, line: Control) -> void:
	_asked[run.entry_id] = true
	_posting[run.entry_id] = true
	var view: Dictionary = await _read_for_line(client, run, line, true)
	var mine: Array = Runs.on_board(_owner(), run.board)
	# Settled only by what the read shows, never by the run's age: listed, or one the server would never take.
	var settled: bool = not view.is_empty() and (BoardStatus.of_run(_kept_run(run), true, view, _now(), mine).state == BoardStatus.RANKED or BoardStatus.listed_checking(run, view) or BoardStatus.ruled_out(run, view, mine))
	if not settled: await _post_for_line(client, run, room_id, line)
	_posting.erase(run.entry_id)

## Asks the server to post the room's run, then says who must sign in when it
## did not. Posted: it goes on as any run, celebrated at once from the kept
## board. Any other answer, or none: the card's read decides, and a place is
## celebrated only once that read lists the run.
func _post_for_line(client: RefCounted, run: Dictionary, room_id: String, line: Control) -> void:
	var answer: Dictionary = await _post(client, run, room_id)
	if not is_instance_valid(line): return
	run = _kept_run(run)
	if not str(run.get("refused", "")).is_empty():
		line.show_status(BoardStatus.of_run(run, true, client.kept_view(run.board), _now(), Runs.on_board(_owner(), run.board)))
		return
	var posted: bool = answer.get("ok", false) and answer.get("status") == "posted"
	if posted: _celebrate(run, client.kept_view(run.board), line)
	_read_for_line(client, run, line, not posted)

## One post of a room's run (services/leaderboard_client.gd post_room), noting
## the answer on the run: who has no platform account, or "" otherwise. Returns the answer.
func _post(client: RefCounted, run: Dictionary, room_id: String) -> Dictionary:
	var owner := _owner()
	_asked[run.entry_id] = true
	var answer: Dictionary = await client.post_room(room_id)
	if not answer.get("ok", false) or owner != _owner(): return answer
	var who := ""
	if answer.status == "platform_required": who = Runs.REFUSED_PARTNER if answer.you else Runs.REFUSED_YOU
	Runs.set_refused(owner, run.entry_id, who, room_id)
	return answer

## The run as the runs file has it now (`run` itself when it is gone).
func _kept_run(run: Dictionary) -> Dictionary:
	for kept: Dictionary in Runs.runs_of(_owner()):
		if kept.entry_id == run.entry_id: return kept
	return run

## The line's Sign in button: the platform's name, whether this phone offers
## it, and what a tap does (sign in and link, then post again).
func _wire_sign_in(client: RefCounted, run: Dictionary, room_id: String, line: Control) -> void:
	var games := _games()
	_watch_games(games)
	line.platform_name = BoardStatusLine.platform_of(games)
	line.sign_in_offered = func() -> bool: return games != null and is_instance_valid(games) and games.offered()
	line.sign_in = func() -> void: _sign_in_for_line(client, run, room_id, line)

func _sign_in_for_line(client: RefCounted, run: Dictionary, room_id: String, line: Control) -> void:
	var games := _games()
	# Linking just now also posts this player's other refused runs (_on_games_changed); this one goes here, once.
	_posting[run.entry_id] = true
	if games != null and not games.linked(): await games.sign_in_now()
	if games != null and games.linked(): await _post_for_line(client, run, room_id, line)
	elif is_instance_valid(line):
		# Not linked (cancelled, offline, or a choice waiting in Settings): the button comes back.
		line.show_status(BoardStatus.of_run(_kept_run(run), true, client.kept_view(run.board), _now(), Runs.on_board(_owner(), run.board)))
	_posting.erase(run.entry_id)

func _games() -> Node:
	return PlatformGames.shared(host.get_tree()) if host.is_inside_tree() else null

## Linking anywhere (Settings too) posts this player's refused runs again, once each time it becomes linked.
func _watch_games(games: Node) -> void:
	if games == null or games.changed.is_connected(_on_games_changed): return
	_was_linked = games.linked()
	games.changed.connect(_on_games_changed)

func _on_games_changed() -> void:
	var games := _games()
	var linked: bool = games != null and games.linked()
	var became := linked and not _was_linked
	_was_linked = linked
	if became: _repost_mine()

## Posts this player's refused runs again (the newest MAX_REPOST), skipping any
## a post from this session is still waiting on. One sweep at a time.
func _repost_mine() -> void:
	if _reposting or not _platform_required(): return
	_reposting = true
	_swept = true
	var owner := _owner()
	for run: Dictionary in Runs.refused_by_me(owner).slice(0, MAX_REPOST):
		if owner != _owner(): break
		if _posting.has(run.entry_id): continue
		_posting[run.entry_id] = true
		await _post(_client(), run, str(run.room))
		_posting.erase(run.entry_id)
	_reposting = false

## Home's upkeep for the platform rule, at most every CHECK_MS: with the rule
## off, no run stays marked refused; with it on and this player already linked
## (Settings, or the quiet sign-in at launch), their refused runs go again once a session.
func _platform_upkeep() -> void:
	if not _supported(): return
	var owner := _owner()
	if not _platform_required():
		# Only on this session's own capabilities read: a switch never heard (a launch before any read) says nothing.
		var session: Variant = host.relay_session
		if session != null and session.has_method("leaderboards_platform_required") and session.leaderboards_supported(): Runs.clear_refused(owner)
		return
	var games := _games()
	_watch_games(games)
	if not _swept and games != null and games.linked() and not Runs.refused_by_me(owner).is_empty(): _repost_mine()

## `listed_only`: celebrate only when this read lists the run (a post the server did not confirm).
## Returns the board read ({} when it failed).
func _read_for_line(client: RefCounted, run: Dictionary, line: Control, listed_only: bool = false) -> Dictionary:
	_read_at[run.board] = Time.get_ticks_msec()
	# Fresh: a board kept from before the run never lists it, and this read is the post's answer.
	var answer: Dictionary = await client.board(run.board, true)
	if not answer.get("ok", false): return {}
	if not is_instance_valid(line): return answer.view
	var status := BoardStatus.of_run(run, true, answer.view, _now(), Runs.on_board(_owner(), run.board))
	_note_settled(run, status)
	# Home says it once when the player gets back there, with no read of its own,
	# only when the board itself lists it (never on the just-finished guess).
	if _waiting(run, answer.view): _seen_checking[run.entry_id] = true
	line.show_status(status)
	if not listed_only or status.state == BoardStatus.RANKED or BoardStatus.listed_checking(run, answer.view): _celebrate(run, answer.view, line)
	return answer.view

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
	# The row as the board shows it here, with its names and Gold leaf (a waiting first place wears it too).
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
	_platform_upkeep()
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
	if _waiting(run, answer.view):
		_seen_checking[run.entry_id] = true
		if not _noted.has(run.entry_id) and host._home_free_for_card(): _post_note(run)

## Whether Home may say the run is being checked: the board lists it waiting
## and it stands there as the board screen shows it (BoardStatus.stands_waiting).
func _waiting(run: Dictionary, view: Dictionary) -> bool:
	return BoardStatus.listed_checking(run, view) and BoardStatus.stands_waiting(run, view, _now(), Runs.on_board(_owner(), run.board))

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

## This session's capabilities when they say on, else the public switch last
## heard (services/server_switches.gd), so Home's board watch runs after a launch too.
func _supported() -> bool:
	return (host.relay_session != null and host.relay_session.leaderboards_supported()) or ServerSwitches.shared().on_for(host.api, "leaderboards")

func _owner() -> String:
	return str(host.api.player_id) if host.api != null else ""

func _client() -> RefCounted:
	return LeaderboardClient.shared(host.api, _owner())

static func _now() -> float:
	return Time.get_unix_time_from_system()
