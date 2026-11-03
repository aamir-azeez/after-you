extends RefCounted
## Which chapter times go to Google Play Games and Game Center leaderboards, and when (owner,
## 2026-11-03; claude-20261011 platform-boards board 5). Pure: no storage, no requests. The
## service (platform_games.gd post_boards) reads this player's runs (services/leaderboard_runs.gd),
## the boards this phone read (services/leaderboard_client.gd kept views) and what it kept from
## earlier passes (platform_board_store.gd), and posts what this answers.
##
## Only runs our own board would take: finished together, no turn with Forgiving catches. Each
## run gets one verdict, kept across launches, since the boards a phone read live only in memory:
## - GO: post it when it is this account's best on that chapter. A run slower than our tenth
##   place on a full board, not listed there, is GO at once: our board never checks such a run.
## - WAIT: it could make our top 10 (faster than tenth, a board with fewer than ten runs, or
##   listed as checking). It turns GO once a board read shows it RANKED, and NEVER once a read
##   shows it settled off the board (services/board_status.gd of_run: failed its check, or the
##   pair already had a faster run there).
## - no verdict yet: no read of its board this session. Nothing is posted until one comes, and
##   no new read is made for it (the end card, Home and the board screen already read boards).
## A run waiting for its check that no read of this phone ever saw is the accepted gap: if it
## failed while unseen and the board later filled with faster runs, it would read as GO.
##
## Times: ticks at 30 a second, cut down to hundredths with integer maths, as our tenths are
## (services/leaderboard_runs.gd time_text), so a platform time always starts with ours. Game
## Center takes the hundredths; Play Games takes milliseconds on a Time board, so it gets the
## hundredths times 10 and both platforms show the same digits. 6661 ticks: 22203 and 222030.
const Runs = preload("res://services/leaderboard_runs.gd")
const BoardStatus = preload("res://services/board_status.gd")
const GamesProvider = preload("res://services/platform_games/games_provider.gd")

const GO := "go"
const WAIT := "wait"
const NEVER := "never"
const VERDICTS := [GO, WAIT, NEVER]

## A time in hundredths of a second, rounded down.
static func hundredths(ticks: int) -> int:
	return maxi(ticks, 0) * 100 / Runs.TICK_RATE

## What `kind` is sent for a time of `hundredths_value`: milliseconds on Play Games, hundredths on Game Center.
static func score(kind: String, hundredths_value: int) -> int:
	return hundredths_value * 10 if kind == GamesProvider.PLAY_GAMES else hundredths_value

## The verdicts for `runs` (this player's runs, Runs.runs_of) given the boards read (board ->
## view) and the verdicts kept (entry_id -> verdict). Returns the verdicts of these runs only;
## a run with none yet is left out.
static func judge(runs: Array, views: Dictionary, kept: Dictionary, now_unix: float) -> Dictionary:
	var verdicts: Dictionary = {}
	var by_board: Dictionary = {}
	for run: Dictionary in runs:
		if not by_board.has(run.board): by_board[run.board] = []
		by_board[run.board].append(run)
	for run: Dictionary in runs:
		if bool(run.get("assisted", false)): continue
		var id := str(run.entry_id)
		var held := str(kept.get(id, ""))
		if held in [GO, NEVER]:
			verdicts[id] = held
			continue
		var view: Variant = views.get(run.board)
		if not _readable(view):
			if held == WAIT: verdicts[id] = WAIT
			continue
		if held.is_empty() and not _listed(run, view) and _below_tenth(run, view):
			verdicts[id] = GO
			continue
		var state := str(BoardStatus.of_run(run, true, view, now_unix, by_board[run.board]).state)
		verdicts[id] = GO if state == BoardStatus.RANKED else NEVER if state == BoardStatus.NOT_LISTED else WAIT
	return verdicts

## What to post: board -> hundredths, the fastest GO run on each board in `boards` (the ones the
## platform has) that beats what this account already posted there (`posted`, board -> hundredths).
static func due(runs: Array, verdicts: Dictionary, boards: Array, posted: Dictionary) -> Dictionary:
	var best: Dictionary = {}
	for run: Dictionary in runs:
		if verdicts.get(run.entry_id) != GO or not run.board in boards: continue
		var time := hundredths(int(run.ticks))
		if time > 0 and (not best.has(run.board) or time < int(best[run.board])): best[run.board] = time
	var out: Dictionary = {}
	for board: String in best:
		var held: Variant = posted.get(board)
		if not held is int or int(best[board]) < int(held): out[board] = best[board]
	return out

static func _readable(view: Variant) -> bool:
	return view is Dictionary and view.get("top") is Array and view.get("checking") is Array

static func _listed(run: Dictionary, view: Dictionary) -> bool:
	if BoardStatus.listed_checking(run, view): return true
	for row: Dictionary in view.top:
		if row.get("entry_id") == run.entry_id: return true
	return false

## Slower than, or as fast as, tenth place on a full board: our board would never take it
## (backend leaderboards/view.ts mightPlace; on equal times the listed run finished first).
static func _below_tenth(run: Dictionary, view: Dictionary) -> bool:
	var top: Array = view.top
	return top.size() >= BoardStatus.TOP_PLACES and int(run.ticks) >= int(top[BoardStatus.TOP_PLACES - 1].get("ticks", 0))
