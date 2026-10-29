extends RefCounted
## Where a finished together run stands on its leaderboard, as one state the
## end-of-run card, the board screen and Home all read the same way:
## - OFF: the server has leaderboards off, so nothing was posted;
## - ASSISTED: a turn had Forgiving catches on, so the server never posts it
##   (backend leaderboards/run.ts runTicks);
## - CHECKING: posted and waiting for its replay check (or a person). The
##   server posts before it answers the final turn (v2/routes.ts), so a run
##   just finished counts as checking until a board read says otherwise;
## - RANKED: in the top 10, with its place;
## - NOT_LISTED: settled and not on the board (slower than the ten listed, or
##   it did not pass the checks).
## Pure: no storage, no requests. Runs come from services/leaderboard_runs.gd
## and views from services/leaderboard_client.gd (valid_view).
const Runs = preload("res://services/leaderboard_runs.gd")
const Typed = preload("res://services/typed_values.gd")

const OFF := "off"
const ASSISTED := "assisted"
const CHECKING := "checking"
const RANKED := "ranked"
const NOT_LISTED := "not_listed"
## A board read this soon after the run finished may come from a copy the
## server kept from before the post (backend view-cache.ts keeps one for up to
## two minutes), so a run this new that it does not list still counts as checking.
const SETTLE_SECONDS := 600
const TOP_PLACES := 10

## The state of `run` (a Runs entry: board, entry_id, ticks, assisted,
## finished_at) given whether the server has leaderboards on and the newest
## board view ({} when none was read). {state, ticks, rank (0 unless RANKED)}.
static func of_run(run: Dictionary, supported: bool, view: Dictionary, now_unix: float) -> Dictionary:
	var ticks := int(run.get("ticks", 0))
	var result := {"state": CHECKING, "ticks": ticks, "rank": 0}
	if not supported: result.state = OFF
	elif bool(run.get("assisted", false)): result.state = ASSISTED
	elif view.get("top") is Array and view.get("checking") is Array:
		var id := str(run.get("entry_id", ""))
		for row: Dictionary in view.top:
			if row.get("entry_id") == id:
				result.state = RANKED
				result.rank = int(row.rank)
				return result
		if id in view.checking: return result
		var full: bool = view.top.size() >= TOP_PLACES and ticks > int(view.top[TOP_PLACES - 1].get("ticks", 0))
		if full or not recent(run, now_unix): result.state = NOT_LISTED
	return result

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
