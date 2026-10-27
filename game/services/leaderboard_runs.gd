extends RefCounted
## This phone's own finished together runs, for the leaderboard screen: which
## run on a board is ours (to pin "Your best" and say "Checking"), and our best
## time where the board does not list us.
##
## A run is a finished standalone chapter room with two players. Its id on the
## board is the server's (backend leaderboards/run.ts entryId): a hash of the
## room and the branch it finished on, so only the two members can find it.
## Its time is the sum of every turn's ticks on that branch, read from the
## room's final checkpoint, which nests every pair. A run with catch assistance
## on any turn is kept but marked, since it never ranks.
##
## services/shared_replay_collection.gd calls note() for every chapter room it
## remembers; only a finished one is kept. One small file per phone, newest
## MAX_RUNS runs per player, written whole with services/atomic_file.gd.
const Registry = preload("res://services/chapter_registry.gd")
const Typed = preload("res://services/typed_values.gd")
const AtomicFile = preload("res://services/atomic_file.gd")
const PATH := "user://leaderboard-runs.json"
const MAX_RUNS := 128
const TICK_RATE := 30
const ENTRY_DOMAIN := "after-you leaderboard entry v1\n"

static var _path := PATH
static var _loaded := false
static var _data: Dictionary = {}

## Tests use their own file.
static func use_path(path: String) -> void:
	_path = path
	_loaded = false
	_data = {}

## The board a chapter version ranks on: "<level_id>@<level_version>", or "".
static func board_key(chapter_key: String) -> String:
	var known := Registry.descriptor(chapter_key)
	return "" if known.is_empty() else "%s@%d" % [known.level_id, int(known.level_version)]

## The run's id on its board (32 hex characters).
static func entry_id(room_id: String, branch: int) -> String:
	return ("%s%s\n%d" % [ENTRY_DOMAIN, room_id, branch]).sha256_text().left(32)

## {ticks, assisted} of a whole run from its final checkpoint, or {} when the chain is not a whole run.
static func run_time(chapter_key: String, checkpoint: Dictionary) -> Dictionary:
	var stages := int(Registry.descriptor(chapter_key).get("stage_count", 0))
	if stages < 1 or not Typed.equal(checkpoint.get("stage_index"), stages): return {}
	var ticks := 0
	var assisted := false
	var current := checkpoint
	for index in range(stages, 0, -1):
		var proof: Variant = current.get("proof")
		if not Typed.equal(current.get("stage_index"), index) or not proof is Dictionary: return {}
		for role: String in ["a", "b"]:
			var turn: Variant = proof.get(role)
			if not turn is Dictionary or not Typed.whole_number(turn.get("duration_ticks")): return {}
			ticks += int(turn.duration_ticks)
			assisted = assisted or not Typed.equal(turn.get("catch_assistance"), false)
		current = Registry.previous_checkpoint(chapter_key, current)
	return {"ticks": ticks, "assisted": assisted} if Typed.equal(current.get("stage_index"), 0) else {}

## A room this phone remembers; kept only when it is a finished run with a partner.
static func note(owner: String, snapshot: Dictionary, chapter_key: String) -> void:
	if owner.is_empty() or chapter_key.is_empty() or not Typed.equal(snapshot.get("active_role"), "complete"): return
	if not snapshot.get("guest_id") is String or snapshot.get("guest_id") == snapshot.get("host_id"): return
	if not snapshot.get("checkpoint") is Dictionary or not snapshot.get("room_id") is String or not Typed.whole_number(snapshot.get("branch")): return
	var board := board_key(chapter_key)
	var time := run_time(chapter_key, snapshot.checkpoint)
	if board.is_empty() or time.is_empty(): return
	var id := entry_id(snapshot.room_id, int(snapshot.branch))
	var mine: Array = runs_of(owner)
	for run: Dictionary in mine:
		if run.entry_id == id: return
	mine.append({"board": board, "entry_id": id, "ticks": int(time.ticks), "assisted": bool(time.assisted), "finished_at": str(snapshot.get("updated_at", ""))})
	while mine.size() > MAX_RUNS: mine.pop_front()
	_data[owner] = mine
	AtomicFile.write_text(_path, JSON.stringify({"schema_version": 1, "players": _data}))

## This player's runs, oldest first.
static func runs_of(owner: String) -> Array:
	_load()
	var value: Variant = _data.get(owner, [])
	return value.duplicate(true) if value is Array else []

## This player's runs on one board, fastest first.
static func on_board(owner: String, board: String) -> Array:
	var found: Array = runs_of(owner).filter(func(run: Dictionary) -> bool: return run.board == board)
	found.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.ticks) < int(b.ticks) or (int(a.ticks) == int(b.ticks) and str(a.finished_at) < str(b.finished_at)))
	return found

## A time as players read it: minutes, seconds and tenths ("1:05.3").
static func time_text(ticks: int) -> String:
	var tenths := maxi(ticks, 0) * 10 / TICK_RATE
	return "%d:%02d.%d" % [tenths / 600, (tenths / 10) % 60, tenths % 10]

static func _load() -> void:
	if _loaded: return
	_loaded = true
	_data = {}
	var text := AtomicFile.read_text(_path)
	if text.is_empty(): return
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary or not Typed.equal(parsed.get("schema_version"), 1) or not parsed.get("players") is Dictionary: return
	for owner: Variant in parsed.players:
		var list: Variant = parsed.players[owner]
		if not owner is String or not list is Array: continue
		var kept: Array = []
		for run: Variant in list:
			if run is Dictionary and run.get("board") is String and run.get("entry_id") is String and str(run.entry_id).length() == 32 and Typed.whole_number(run.get("ticks")) and run.get("assisted") is bool:
				kept.append({"board": run.board, "entry_id": run.entry_id, "ticks": int(run.ticks), "assisted": run.assisted, "finished_at": str(run.get("finished_at", ""))})
		_data[owner] = kept.slice(maxi(kept.size() - MAX_RUNS, 0))
