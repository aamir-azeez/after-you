extends RefCounted
## Where a finished together run stands on its leaderboard, as one state the
## end-of-run card, the board screen and Home all read the same way:
## - OFF: the server had leaderboards off when this phone last asked;
## - ASSISTED: a turn had Forgiving catches on, so the server never posts it
##   (backend leaderboards/run.ts runTicks);
## - CHECKING: posted and waiting for its replay check (or a person). The
##   server posts before it answers the final turn (v2/routes.ts), so a run
##   just finished counts as checking until a board read says otherwise;
## - RANKED: in the top 10, with its place;
## - NOT_LISTED: settled and not on the board (slower than the ten listed, a
##   pair's repeat no faster than its own run already there, or it did not
##   pass the checks);
## - UNKNOWN: an older run and no board read to say where it stands: no line.
## shown_rows() is the board as this phone shows it, with this player's runs
## that wait for their check at their places.
## Pure: no storage, no requests. Runs come from services/leaderboard_runs.gd
## and views from services/leaderboard_client.gd (valid_view).
const Runs = preload("res://services/leaderboard_runs.gd")
const Typed = preload("res://services/typed_values.gd")

const OFF := "off"
const ASSISTED := "assisted"
const CHECKING := "checking"
const RANKED := "ranked"
const NOT_LISTED := "not_listed"
const UNKNOWN := ""
## A board read this soon after the run finished may come from a copy the
## server kept from before the post (backend view-cache.ts keeps one for up to
## two minutes), so a run this new that it does not list still counts as checking.
const SETTLE_SECONDS := 600
const TOP_PLACES := 10

## The state of `run` (a Runs entry: board, entry_id, ticks, assisted,
## finished_at, partner) given whether the server has leaderboards on, the
## newest board view ({} when none was read) and `mine`, this player's runs on
## that board (Runs.on_board). {state, ticks, rank (0 unless RANKED)}.
static func of_run(run: Dictionary, supported: bool, view: Dictionary, now_unix: float, mine: Array = []) -> Dictionary:
	var ticks := int(run.get("ticks", 0))
	var result := {"state": CHECKING, "ticks": ticks, "rank": 0}
	if not supported: result.state = OFF
	elif bool(run.get("assisted", false)): result.state = ASSISTED
	elif not view.get("top") is Array or not view.get("checking") is Array:
		if not recent(run, now_unix): result.state = UNKNOWN
	else:
		var id := str(run.get("entry_id", ""))
		for row: Dictionary in view.top:
			if row.get("entry_id") == id:
				result.state = RANKED
				result.rank = int(row.rank)
				return result
		if id in view.checking: return result
		var full: bool = view.top.size() >= TOP_PLACES and ticks > int(view.top[TOP_PLACES - 1].get("ticks", 0))
		if full or pair_ahead(run, view, mine) or not recent(run, now_unix): result.state = NOT_LISTED
	return result

## The board as this phone shows it to this player: the top 10 of `view` with
## this player's runs that wait for their check (CHECKING by of_run, `mine` from
## Runs.on_board) placed by their time, flagged `pending`. Only this phone ever
## sees them; the server ranks them only once they pass.
## - A pair has one entry (backend board.ts submit): only its fastest waiting
##   run shows, and it takes the place of the pair's slower ranked row, whose
##   names it keeps. Other pairs' waiting runs never move anyone.
## - On equal times a listed run stays ahead: it finished first (rules.ts compareRuns).
## - Places count again from 1 and stop at 10; the Gold leaf stays only on first
##   place. A waiting run first, faster than every run below it, wears it here
##   before its check (and while a person looks at it), since passing earns it
##   (backend board.ts award, rules.ts strictlyFirst), and the run it passes
##   loses it here. A failed check takes the waiting row away, so the leaf
##   goes back where it was.
## - `gone` (entry_id -> true): runs an earlier read listed as checking that
##   this one lists nowhere. They failed their check, so they go at once
##   rather than when the settle window ends.
## - `known` (partner -> two names, pair_names()): a waiting run whose pair has
##   no ranked row here to take the names of is named as the board would name it.
## A pending row: {rank, entry_id, ticks, names, gold_leaf, finished_on,
## replay_hash: null, looks: [], pending: true, partner}. [] without a board read.
static func shown_rows(view: Dictionary, mine: Array, now_unix: float, gone: Dictionary = {}, known: Dictionary = {}) -> Array:
	if not view.get("top") is Array or not view.get("checking") is Array: return []
	var waiting: Dictionary = {}
	for run: Dictionary in mine:
		# A run the pair's own listed run is no slower than never entered (pair_ahead).
		if gone.has(run.entry_id) or bool(run.get("assisted", false)) or of_run(run, true, view, now_unix, mine).state != CHECKING or pair_ahead(run, view, mine): continue
		var pair := str(run.get("partner", ""))
		var key := pair if not pair.is_empty() else "run:" + str(run.entry_id)
		if not waiting.has(key) or _ahead(run, waiting[key]): waiting[key] = run
	var replaced: Dictionary = {}
	var names: Dictionary = known.duplicate(true)
	for run: Dictionary in mine:
		var pair := str(run.get("partner", ""))
		if not pair.is_empty() and waiting.has(pair): replaced[run.entry_id] = pair
	var listed: Array = []
	for row: Dictionary in view.top:
		if replaced.has(row.get("entry_id")):
			names[replaced[row.entry_id]] = row.get("names")
			continue
		var kept := row.duplicate(true)
		kept.pending = false
		listed.append(kept)
	var runs: Array = waiting.values()
	runs.sort_custom(_ahead)
	# The listed rows keep the server's order; each waiting run goes in before
	# the first listed row slower than it.
	var rows: Array = []
	var next := 0
	for row: Dictionary in listed:
		while next < runs.size() and int(runs[next].ticks) < int(row.ticks):
			rows.append(_pending_row(runs[next], names))
			next += 1
		rows.append(row)
	for index in range(next, runs.size()): rows.append(_pending_row(runs[index], names))
	rows = rows.slice(0, TOP_PLACES)
	for index in range(rows.size()):
		rows[index].rank = index + 1
		rows[index].gold_leaf = index == 0 and bool(rows[index].get("gold_leaf", false))
	if not rows.is_empty() and rows[0].pending: rows[0].gold_leaf = rows.size() == 1 or int(rows[0].ticks) < int(rows[1].ticks)
	return rows

## The row `run` has on the board this phone shows (shown_rows), or {} when
## it has none there (off the board, settled, or no board read).
static func shown_row(run: Dictionary, view: Dictionary, now_unix: float, mine: Array, known: Dictionary = {}) -> Dictionary:
	for row: Dictionary in shown_rows(view, mine, now_unix, {}, known):
		if row.entry_id == run.get("entry_id"): return row
	return {}

## Its place there, or 0.
static func place(run: Dictionary, view: Dictionary, now_unix: float, mine: Array) -> int:
	return int(shown_row(run, view, now_unix, mine).get("rank", 0))

static func _ahead(a: Dictionary, b: Dictionary) -> bool:
	return int(a.ticks) < int(b.ticks) or (int(a.ticks) == int(b.ticks) and str(a.get("finished_at", "")) < str(b.get("finished_at", "")))

## A waiting run as a row; `names` holds the names of the pair's ranked row it
## takes the place of, else the ones pair_names() knows for the pair.
static func _pending_row(run: Dictionary, names: Dictionary) -> Dictionary:
	var partner := str(run.get("partner", ""))
	return {"rank": 0, "entry_id": run.entry_id, "ticks": int(run.ticks), "names": names.get(partner) if not partner.is_empty() else null, "gold_leaf": false,
		"finished_on": str(run.get("finished_at", "")).left(10), "replay_hash": null, "looks": [], "pending": true, "partner": partner}

## The names the board would give each of this player's pairs on a run it
## has not ranked yet (partner -> [two names]). The board names a pair only
## when both players chose to show their names (backend board.ts shownNames),
## and only a named row of the pair tells this phone the partner did: a row in
## one of `views` (board -> view, the boards this phone read) of a run in
## `runs` (this player's runs on any board) with that partner, taken while this
## player still shows their name (`show_own`). The names are the row's own, the
## players' display names, never a friend nickname, as on any row. A pair
## with no such row is left out, so its run shows as "A pair", as the board would.
static func pair_names(runs: Array, views: Dictionary, show_own: bool) -> Dictionary:
	var known: Dictionary = {}
	if not show_own: return known
	for run: Dictionary in runs:
		var partner := str(run.get("partner", ""))
		var view: Variant = views.get(run.get("board"))
		if partner.is_empty() or known.has(partner) or not view is Dictionary or not view.get("top") is Array: continue
		for row: Variant in view.top:
			if row is Dictionary and row.get("entry_id") == run.get("entry_id") and row.get("names") is Array and (row.names as Array).size() == 2:
				known[partner] = (row.names as Array).duplicate()
				break
	return known

## Whether `view` lists the run as waiting for its check (never a guess).
static func listed_checking(run: Dictionary, view: Dictionary) -> bool:
	return view.get("checking") is Array and str(run.get("entry_id", "")) in view.checking

## Whether the board already holds a run by the same pair (this player and the
## same partner) no slower than `run`: the server then never took it (backend
## board.ts submit, one entry per pair).
static func pair_ahead(run: Dictionary, view: Dictionary, mine: Array) -> bool:
	var partner := str(run.get("partner", ""))
	if partner.is_empty(): return false
	var on_board: Dictionary = {}
	for row: Dictionary in view.get("top", []): on_board[row.get("entry_id")] = true
	for id: Variant in view.get("checking", []): on_board[id] = true
	for other: Dictionary in mine:
		if other.get("entry_id") == run.get("entry_id") or str(other.get("partner", "")) != partner or bool(other.get("assisted", false)): continue
		if on_board.has(other.get("entry_id")) and int(other.get("ticks", 0)) <= int(run.get("ticks", 0)): return true
	return false

## Whether the run finished within SETTLE_SECONDS of `now_unix` (a run with no
## readable time counts as recent, so it is never called settled too early).
static func recent(run: Dictionary, now_unix: float) -> bool:
	var finished := finished_unix(run)
	return finished <= 0.0 or now_unix - finished < SETTLE_SECONDS

## The run's finish time in Unix seconds, or 0 when it has none.
static func finished_unix(run: Dictionary) -> float:
	var text := str(run.get("finished_at", ""))
	if text.length() < 19: return 0.0
	return float(Time.get_unix_time_from_datetime_string(text.left(19)))

## The run a finished room is on this phone, noting it first (Runs.note keeps
## each run once), or {} when the room is not a finished together run with a board.
static func room_run(owner: String, snapshot: Dictionary, chapter_key: String) -> Dictionary:
	if owner.is_empty() or not snapshot.get("room_id") is String or not Typed.whole_number(snapshot.get("branch")): return {}
	if not Typed.equal(snapshot.get("active_role"), "complete") or not snapshot.get("guest_id") is String or snapshot.get("guest_id") == snapshot.get("host_id"): return {}
	Runs.note(owner, snapshot, chapter_key)
	var id := Runs.entry_id(str(snapshot.room_id), int(snapshot.branch))
	for run: Dictionary in Runs.runs_of(owner):
		if run.entry_id == id: return run
	return {}

## This player's newest run on any board that may still be waiting for its
## check: not assisted, finished within `window_seconds`, and not shown settled
## by `settled` (entry_id -> true). {} when none.
static func newest_waiting(owner: String, settled: Dictionary, now_unix: float, window_seconds: float) -> Dictionary:
	var newest: Dictionary = {}
	for run: Dictionary in Runs.runs_of(owner):
		if run.assisted or settled.has(run.entry_id): continue
		var finished := finished_unix(run)
		if finished <= 0.0 or now_unix - finished > window_seconds: continue
		if newest.is_empty() or str(run.finished_at) > str(newest.finished_at): newest = run
	return newest
